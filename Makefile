-include .env

.PHONY: anvil deploy verify configure deposit redeem get-balance

anvil-eth :
	anvil --port 8545 --fork-url $(ETH_SEPOLIA_RPC_URL) --chain-id 11155111

anvil-arb :
	anvil --port 8546 --fork-url $(ARB_SEPOLIA_RPC_URL) --chain-id 421614

deploy :
	forge script script/DeployTokenAndTokenPool.s.sol --sender $(SENDER) --account $(ACCOUNT) --rpc-url $(RPC_URL) --broadcast && forge script script/DeployVault.s.sol --sender $(SENDER) --account $(ACCOUNT) --rpc-url $(RPC_URL) --broadcast

verify :
	forge verify-contract $(ADDR) $(NAME) --chain $(CHAIN) --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)

configure :
	forge script script/ConfigureTokenPool.s.sol --sender $(SENDER) --account $(ACCOUNT) --rpc-url $(RPC_URL) --broadcast

deposit :
	forge script script/Interaction.s.sol:Deposit --sig "deposit(uint256)" $(AMOUNT) --sender $(SENDER) --account $(ACCOUNT) --rpc-url $(RPC_URL) --broadcast

redeem :
	forge script script/Interaction.s.sol:Redeem --sender $(SENDER) --account $(ACCOUNT) --rpc-url $(RPC_URL) --broadcast

get-balance :
	cast call $(ADDR) "principleBalanceOf(address)" "$(USER)" --rpc-url $(RPC_URL)

send :
	forge script script/SendTokenCrossChain.s.sol --sig "send(address,uint256,uint64)" "$(RECEIVER)" $(AMOUNT) $(SELECTOR) --sender $(SENDER) --account $(ACCOUNT) --rpc-url $(RPC_URL) --broadcast