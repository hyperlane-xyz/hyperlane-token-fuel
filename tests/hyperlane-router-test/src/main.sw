contract;

use std::bytes::Bytes;

use hyperlane_router::{*, interface::{HyperlaneRouter, RemoteRouterConfig}, Routers};

abi HyperlaneRouterTest {
    #[storage(read)]
    fn is_remote_router(domain: u32, router: b256) -> bool;

    #[storage(read)]
    fn only_remote_router(domain: u32, router: b256);

    #[storage(read, write)]
    fn dispatch(destination_domain: u32, message_body: Bytes) -> b256;

    #[storage(read, write)]
    fn dispatch_with_gas(destination_domain: u32, message_body: Bytes, gas_amount: u64, gas_payment: u64, gas_payment_refund_address: Identity) -> b256;
}

storage {
    routers: Routers = Routers {},
}

impl HyperlaneRouter for Contract {
    #[storage(read)]
    fn routers(domain: u32) -> Option<b256> {
        storage.routers.routers(domain)
    }

    #[storage(read, write)]
    fn enroll_remote_router(domain: u32, router: Option<b256>) {
        storage.routers.enroll_remote_router(domain, router);
    }

    #[storage(read, write)]
    fn enroll_remote_routers(configs: Vec<RemoteRouterConfig>) {
        storage.routers.enroll_remote_routers(configs);
    }
}

impl HyperlaneRouterTest for Contract {
    #[storage(read)]
    fn is_remote_router(domain: u32, router: b256) -> bool {
        storage.routers.is_remote_router(domain, router)
    }

    #[storage(read)]
    fn only_remote_router(domain: u32, router: b256) {
        storage.routers.only_remote_router(domain, router);
    }

    #[storage(read, write)]
    fn dispatch(destination_domain: u32, message_body: Bytes) -> b256 {
        storage.routers.dispatch(destination_domain, message_body)
    }

    #[storage(read, write)]
    fn dispatch_with_gas(
        destination_domain: u32,
        message_body: Bytes,
        gas_amount: u64,
        gas_payment: u64,
        gas_payment_refund_address: Identity,
    ) -> b256 {
        storage.routers.dispatch_with_gas(destination_domain, message_body, gas_amount, gas_payment, gas_payment_refund_address)
    }
}
