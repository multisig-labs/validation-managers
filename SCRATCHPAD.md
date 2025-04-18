export NODE_URL=https://etna.avax-dev.network

ggurl /ext/info info.getNetworkID | jq
ggurl /ext/bc/C/rpc eth_chainId | jq
ggurl /ext/bc/P platform.getSubnets | jq '.result.subnets[].id'
ggurl /ext/bc/P platform.getBlockchains | jq -r '.result.blockchains[].name' | sort | uniq
ggurl /ext/bc/P platform.getCurrentValidators | jq
ggurl /ext/bc/C/rpc eth_getBalance "-s params[]=0x09167154e444884B06d6608CE842Ddc3a768b22a params[]=latest" | jq

export ETH_RPC_URL=http://localhost:8545

cast code 0xC0fFEE1234567890aBCdeF1234567890abcDef34

export L1_RPC="https://testnet-ggpfuji1-yf418.avax-test.network/ext/bc/26Rz4JszWH3RQeEEiD6Ay731Uf81kofRJk8vSEiFL7He252qdr/rpc?token=aa954d6bcccf99a93125bf8f2a3f07a6f7c8a2d0c0217f31c77fc850fdd7a2be"

just anvil $L1_RPC

cast rpc anvil_setBalance 0xe757fdf984e0e4f3b5cc2f049dc4a3b228a10421 0x56BC75E2D63100000
cast rpc anvil_impersonateAccount 0xe757fdf984e0e4f3b5cc2f049dc4a3b228a10421
just forge-script upgrade --froms 0xe757FdF984e0e4F3B5cC2F049Dc4A3b228A10421 --sender 0xe757FdF984e0e4F3B5cC2F049Dc4A3b228A10421
