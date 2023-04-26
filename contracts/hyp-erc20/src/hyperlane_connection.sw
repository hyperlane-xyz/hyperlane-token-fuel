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
    /// Gets the Mailbox.
    #[storage(read)]
    fn mailbox() -> b256 {
        mailbox()
    }

    /// Gets the InterchainGasPaymaster.
    #[storage(read)]
    fn interchain_gas_paymaster() -> b256 {
        interchain_gas_paymaster()
    }

    /// Gets the InterchainSecurityModule.
    #[storage(read)]
    fn interchain_security_module_dupe_todo_remove() -> b256 {
        interchain_security_module()
    }
}

impl HyperlaneConnectionClientSetter for Contract {
    /// Sets the Mailbox if the caller is the owner.
    #[storage(read, write)]
    fn set_mailbox(new_mailbox: b256) {
        only_owner();
        set_mailbox(new_mailbox);
    }

    /// Sets the InterchainGasPaymaster if the caller is the owner.
    #[storage(read, write)]
    fn set_interchain_gas_paymaster(new_interchain_gas_paymaster: b256) {
        only_owner();
        set_interchain_gas_paymaster(new_interchain_gas_paymaster);
    }

    /// Sets the InterchainSecurityModule if the caller is the owner.
    #[storage(read, write)]
    fn set_interchain_security_module(module: b256) {
        only_owner();
        set_interchain_security_module(module);
    }
}
