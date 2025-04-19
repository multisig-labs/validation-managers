// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { BaseAbstract } from "./BaseAbstract.sol";
import { Storage } from "./Storage.sol";

import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";

contract BaseUpgradeable is Initializable, BaseAbstract {
  function __BaseUpgradeable_init(Storage gogoStorageAddress) internal onlyInitializing {
    gogoStorage = Storage(gogoStorageAddress);
  }
}
