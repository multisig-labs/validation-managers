export ETH_RPC_URL := env_var_or_default("ETH_RPC_URL", "http://127.0.0.1:9650")
export MNEMONIC := env_var_or_default("MNEMONIC", "test test test test test test test test test test test junk")
# First key from MNEMONIC
export PRIVATE_KEY := env_var_or_default("PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")

# Autoload a .env if one exists
set dotenv-load
# export all variables to ENV vars
set export

# Print out some help
default:
	@just --list --unsorted
	
setup:
	forge soldeer install

build:
	forge build

# Run forge unit tests
test contract="." test="." *flags="":
	@# Using date here to give some randomness to tests that use block.timestamp
	forge test --allow-failure --block-timestamp `date '+%s'` --match-contract {{contract}} --match-test {{test}} {{flags}}

# Run forge unit tests forking $ETH_RPC_URL
test-fork contract="." test="." *flags="":
	forge test --fork-url=${ETH_RPC_URL} --allow-failure --match-contract {{contract}} --match-test {{test}} {{flags}}

anvil fork_url="":
	anvil --auto-impersonate --port 8545 ${fork_url:+--fork-url=${fork_url}}

# Execute a Forge script
forge-script cmd *FLAGS:
	#!/usr/bin/env bash
	fn={{cmd}}
	forge script {{FLAGS}} --slow  --broadcast --ffi --fork-url=${ETH_RPC_URL} ${PRIVATE_KEY:+--private-key=$PRIVATE_KEY}  script/${fn%.*.*}.s.sol
