export NODE_URL=https://etna.avax-dev.network

ggurl /ext/info info.getNetworkID | jq
ggurl /ext/bc/C/rpc eth_chainId | jq
ggurl /ext/bc/P platform.getSubnets | jq '.result.subnets[].id'
ggurl /ext/bc/P platform.getBlockchains | jq -r '.result.blockchains[].name' | sort | uniq
ggurl /ext/bc/P platform.getCurrentValidators | jq
ggurl /ext/bc/C/rpc eth_getBalance "-s params[]=0x09167154e444884B06d6608CE842Ddc3a768b22a params[]=latest" | jq
