library;

abi HypERC20 {
    #[storage(read, write)]
    fn initialize(initial_owner: Identity, mailbox_id: b256, interchain_gas_paymaster_id: b256, interchain_security_module_id: b256, total_supply: u64);
}
