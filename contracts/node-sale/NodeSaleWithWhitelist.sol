// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin-contracts-5.2.0/token/ERC721/IERC721.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
  "@openzeppelin-contracts-upgradeable-5.2.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/utils/ReentrancyGuardUpgradeable.sol";

import {IERC721Receiver} from "@openzeppelin-contracts-5.2.0/token/ERC721/IERC721Receiver.sol";
import {Address} from "@openzeppelin-contracts-5.2.0/utils/Address.sol";
import {MerkleProof} from "@openzeppelin-contracts-5.2.0/utils/cryptography/MerkleProof.sol";

contract NodeSaleWithWhitelist is
  ReentrancyGuardUpgradeable,
  AccessControlDefaultAdminRulesUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  IERC721Receiver
{
  using Address for address payable;

  // Define roles
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  // keccak256(abi.encode(uint256(keccak256("ggp.nftsale.storage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant STORAGE_SLOT = 0x1c7c07bc1eb7695a9541428f3aa4217b112d3c1b2b303c501f8feaf957c5bb00;

  // Struct to hold all state variables
  struct Storage {
    IERC721 nftContract;
    address treasury;
    uint256 price;
    uint256 totalSold;
    uint256 saleStartTime;
    uint256 maxPerWallet;
    bytes32 merkleRoot;
    uint256[] availableTokenIds; // Array of token IDs available for sale
    mapping(address => uint256) purchases;
  }

  // Custom errors
  error SaleNotStarted();
  error InsufficientPayment();
  error SupplyExhausted();
  error ExceedsMaxPerWallet();
  error NFTNotOwned();
  error NotWhitelisted();
  error NoFundsToWithdraw();

  event NFTSold(address buyer, uint256 tokenId, uint256 price);
  event PriceUpdated(uint256 newPrice);
  event SaleStarted(uint256 startTime);
  event MerkleRootUpdated(bytes32 newMerkleRoot);

  // Function to access the storage struct
  function _storage() private pure returns (Storage storage $) {
    bytes32 slot = STORAGE_SLOT;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := slot
    }
  }

  // Initializer instead of constructor
  function initialize(address _nftContract, uint256 _price, uint256 _maxPerWallet, address _initialAdmin, address _treasury) external initializer {
    __ReentrancyGuard_init();
    __AccessControl_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    Storage storage s = _storage();
    s.nftContract = IERC721(_nftContract);
    s.treasury = _treasury;
    s.price = _price;
    s.maxPerWallet = _maxPerWallet;
    s.totalSold = 0;
    s.merkleRoot = bytes32(0);

    _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);

    _pause();
  }

  function buyNFTs(uint256 quantity, bytes32[] calldata merkleProof) external payable whenNotPaused nonReentrant {
    Storage storage $ = _storage();

    if (block.timestamp < $.saleStartTime) revert SaleNotStarted();
    if (msg.value != $.price * quantity) revert InsufficientPayment();
    if ($.availableTokenIds.length < quantity) revert SupplyExhausted();
    if ($.purchases[msg.sender] + quantity > $.maxPerWallet) revert ExceedsMaxPerWallet();

    // Verify whitelist if merkleRoot is set
    if ($.merkleRoot != bytes32(0)) {
      bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
      if (!MerkleProof.verify(merkleProof, $.merkleRoot, leaf)) {
        revert NotWhitelisted();
      }
    }

    // Process multiple NFT purchases
    for (uint256 i = 0; i < quantity;) {
      // Get the next available token ID from the array
      uint256 tokenId = $.availableTokenIds[$.availableTokenIds.length - 1];
      $.availableTokenIds.pop();

      if ($.nftContract.ownerOf(tokenId) != address(this)) revert NFTNotOwned();

      $.nftContract.safeTransferFrom(address(this), msg.sender, tokenId);
      emit NFTSold(msg.sender, tokenId, $.price);

      unchecked {
        i++;
      }
    }

    // Update purchase tracking
    $.purchases[msg.sender] += quantity;
    $.totalSold += quantity;

    // Refund excess payment if any
    if (msg.value > $.price * quantity) {
      payable(msg.sender).sendValue(msg.value - ($.price * quantity));
    }
  }

  // Append available token IDs (manager only, when paused)
  // @dev It is up to the caller to ensure no duplicate token IDs
  // are added and that the token IDs are owned by the contract
  function appendAvailableTokenIds(uint256[] calldata newTokenIds) external onlyRole(MANAGER_ROLE) whenPaused {
    Storage storage $ = _storage();
    for (uint256 i = 0; i < newTokenIds.length;) {
      $.availableTokenIds.push(newTokenIds[i]);
      unchecked {
        i++;
      }
    }
  }

  function getNextTokenId() external view returns (uint256) {
    Storage storage $ = _storage();
    if ($.availableTokenIds.length == 0) revert SupplyExhausted();
    return $.availableTokenIds[$.availableTokenIds.length - 1];
  }

  function getRemainingSupply() external view returns (uint256) {
    Storage storage $ = _storage();
    return $.availableTokenIds.length;
  }

  function setMerkleRoot(bytes32 _merkleRoot) external onlyRole(MANAGER_ROLE) {
    Storage storage $ = _storage();
    $.merkleRoot = _merkleRoot;
    emit MerkleRootUpdated(_merkleRoot);
  }

  function setSaleStartTime(uint256 _saleStartTime) external onlyRole(MANAGER_ROLE) whenPaused {
    Storage storage $ = _storage();
    $.saleStartTime = _saleStartTime;
    _unpause();
    emit SaleStarted($.saleStartTime);
  }

  function setPrice(uint256 _newPrice) external onlyRole(MANAGER_ROLE) {
    Storage storage $ = _storage();
    $.price = _newPrice;
    emit PriceUpdated(_newPrice);
  }

  function pause() external onlyRole(MANAGER_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(MANAGER_ROLE) {
    _unpause();
  }

  function withdraw() external onlyRole(MANAGER_ROLE) {
    uint256 balance = address(this).balance;
    if (balance == 0) revert NoFundsToWithdraw();
    Storage storage $ = _storage();
    payable($.treasury).sendValue(balance);
  }

  function rescueERC721(address token, uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
    Storage storage $ = _storage();
    IERC721(token).safeTransferFrom(address(this), $.treasury, tokenId);
  }

  function rescueERC20(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
    Storage storage $ = _storage();
    IERC20(token).transferFrom(address(this), $.treasury, IERC20(token).balanceOf(address(this)));
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

  function getBalance() external view returns (uint256) {
    return address(this).balance;
  }

  // UUPS: Authorize upgrade
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  // Getter functions for public variables (since they're now in storage struct)
  function nftContract() external view returns (IERC721) {
    return _storage().nftContract;
  }

  function treasury() external view returns (address) {
    return _storage().treasury;
  }

  function price() external view returns (uint256) {
    return _storage().price;
  }

  function totalSold() external view returns (uint256) {
    return _storage().totalSold;
  }

  function saleStartTime() external view returns (uint256) {
    return _storage().saleStartTime;
  }

  function maxPerWallet() external view returns (uint256) {
    return _storage().maxPerWallet;
  }

  function merkleRoot() external view returns (bytes32) {
    return _storage().merkleRoot;
  }

  function purchases(address account) external view returns (uint256) {
    return _storage().purchases[account];
  }

  function availableTokenIds() external view returns (uint256[] memory) {
    return _storage().availableTokenIds;
  }

  function getStorageAsJson() external view returns (string memory) {
    Storage storage s = _storage();
    return string(
      abi.encodePacked(
        "{",
        '"nftContract": "',
        addressToString(address(s.nftContract)),
        '",',
        '"treasury": "',
        addressToString(s.treasury),
        '",',
        '"price": "',
        uint256ToString(s.price),
        '",',
        '"totalSold": "',
        uint256ToString(s.totalSold),
        '",',
        '"saleStartTime": "',
        uint256ToString(s.saleStartTime),
        '",',
        '"maxPerWallet": "',
        uint256ToString(s.maxPerWallet),
        '",',
        '"merkleRoot": "',
        bytes32ToString(s.merkleRoot),
        "}"
      )
    );
  }

  function uint256ArrayToString(uint256[] memory array) internal pure returns (string memory) {
    if (array.length == 0) {
      return "[]";
    }

    string memory result = "[";
    for (uint256 i = 0; i < array.length; i++) {
      if (i > 0) {
        result = string(abi.encodePacked(result, ","));
      }
      result = string(abi.encodePacked(result, uint256ToString(array[i])));
    }
    result = string(abi.encodePacked(result, "]"));
    return result;
  }

  // Helper functions for string conversion
  function addressToString(address _addr) internal pure returns (string memory) {
    bytes memory s = new bytes(42);
    s[0] = "0";
    s[1] = "x";
    for (uint256 i = 0; i < 20; i++) {
      bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2 ** (8 * (19 - i)))));
      bytes1 hi = bytes1(uint8(b) / 16);
      bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
      s[2 + 2 * i] = char(hi);
      s[2 + 2 * i + 1] = char(lo);
    }
    return string(s);
  }

  function char(bytes1 b) internal pure returns (bytes1 c) {
    if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
    else return bytes1(uint8(b) + 0x57);
  }

  function uint256ToString(uint256 value) internal pure returns (string memory) {
    if (value == 0) {
      return "0";
    }
    uint256 temp = value;
    uint256 digits;
    while (temp != 0) {
      digits++;
      temp /= 10;
    }
    bytes memory buffer = new bytes(digits);
    while (value != 0) {
      digits -= 1;
      buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
      value /= 10;
    }
    return string(buffer);
  }

  function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
    bytes memory bytesArray = new bytes(64);
    for (uint256 i; i < 32; i++) {
      bytes1 char1 = bytes1(uint8(uint256(_bytes32) / (2 ** (8 * (31 - i)))));
      bytes1 hi = bytes1(uint8(char1) / 16);
      bytes1 lo = bytes1(uint8(char1) - 16 * uint8(hi));
      bytesArray[i * 2] = char(hi);
      bytesArray[i * 2 + 1] = char(lo);
    }
    return string(abi.encodePacked("0x", bytesArray));
  }
}
