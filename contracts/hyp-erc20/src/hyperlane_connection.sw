library;

use hyperlane_connection_client::{
    interchain_gas_paymaster,
    interchain_security_module,
    interface::{
        HyperlaneConnectionClientGetter,
        HyperlaneConnectionClientSetter,
    },
    mailbox,
    set_interchain_gas_paymaster,
    set_interchain_security_module,
    set_mailbox,
};

use ownership::only_owner;

impl HyperlaneConnectionClientGetter for Contract {
    #[storage(read)]
    fn mailbox() -> b256 {
        mailbox()
    }

    #[storage(read)]
    fn interchain_security_module() -> b256 {
        interchain_security_module()
    }

    #[storage(read)]
    fn interchain_gas_paymaster() -> b256 {
        interchain_gas_paymaster()
    }
}

impl HyperlaneConnectionClientSetter for Contract {
    #[storage(read, write)]
    fn set_mailbox(new_mailbox: b256) {
        only_owner();
        set_mailbox(new_mailbox);
    }

    #[storage(read, write)]
    fn set_interchain_gas_paymaster(new_interchain_gas_paymaster: b256) {
        only_owner();
        set_interchain_gas_paymaster(new_interchain_gas_paymaster);
    }

    #[storage(read, write)]
    fn set_interchain_security_module(module: b256) {
        only_owner();
        set_interchain_security_module(module);
    }
}
