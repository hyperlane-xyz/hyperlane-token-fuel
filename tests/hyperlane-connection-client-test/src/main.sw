contract;

use hyperlane_connection_client::{
    initialize,
    interchain_gas_paymaster,
    interchain_security_module,
    interface::{
        HyperlaneConnectionClientGetter,
        HyperlaneConnectionClientSetter,
    },
    mailbox,
    only_mailbox,
    set_interchain_gas_paymaster,
    set_interchain_security_module,
    set_mailbox,
};

abi HyperlaneConnectionClientTest {
    #[storage(read, write)]
    fn initialize(
        mailbox_id: b256,
        igp: b256,
        module: b256,
    );

    #[storage(read)]
    fn only_mailbox();
}

impl HyperlaneConnectionClientTest for Contract {
    #[storage(read, write)]
    fn initialize(
        mailbox_id: b256,
        igp: b256,
        module: b256,
    ) {
        initialize(mailbox_id, igp, module);
    }

    #[storage(read)]
    fn only_mailbox() {
        only_mailbox();
    }
}

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
        set_mailbox(new_mailbox);
    }

    #[storage(read, write)]
    fn set_interchain_gas_paymaster(new_interchain_gas_paymaster: b256) {
        set_interchain_gas_paymaster(new_interchain_gas_paymaster);
    }

    #[storage(read, write)]
    fn set_interchain_security_module(module: b256) {
        set_interchain_security_module(module);
    }
}
