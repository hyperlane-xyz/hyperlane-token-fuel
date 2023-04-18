library;

abi HyperlaneConnectionClientGetter {
    #[storage(read)]
    fn mailbox() -> b256;

    #[storage(read)]
    fn interchain_gas_paymaster() -> b256;

    #[storage(read)]
    fn interchain_security_module() -> b256;
}

abi HyperlaneConnectionClientSetter {
    #[storage(read, write)]
    fn set_mailbox(mailbox: b256);

    #[storage(read, write)]
    fn set_interchain_gas_paymaster(interchain_gas_paymaster: b256);

    #[storage(read, write)]
    fn set_interchain_security_module(module: b256);
}
