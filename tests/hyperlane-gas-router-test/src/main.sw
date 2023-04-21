contract;

use core::experimental::storage::*;
use std::{
    bytes::Bytes,
    constants::ZERO_B256,
    experimental::storage::*,
};

impl StorageKey<b256> {
    #[storage(read, write)]
    pub fn insert(self, key: b256) {
        write::<b256>(key, 0, key);
    }
}

use hyperlane_connection_client::initialize;
use hyperlane_gas_router::{
    interface::{
        HyperlaneGasRouter,
        GasRouterConfig,
    },
    GasRouter,
    GasRouterStorageKeys,
};

use hyperlane_router::{
    interface::{
        HyperlaneRouter,
        RemoteRouterConfig,
    },
    Routers,
};

pub struct Foo {
    a: b256,
    b: StorageMap<u64, u64>,
}

storage {
    gas_router: GasRouter = GasRouter {
        routers: Routers {},
        a: 0,
        destination_gas: StorageMap {},
    },

    foo: Foo = Foo {
        a: ZERO_B256,
        b: StorageMap {},
    },
}

abi HyperlaneGasRouterTest {
    #[storage(read, write)]
    fn initialize_hyperlane_connection_client(mailbox: b256, igp: b256);

    #[storage(read, write)]
    #[payable]
    fn dispatch_with_gas(
        destination_domain: u32,
        message_body: Bytes,
        gas_payment: u64,
        gas_payment_refund_address: Identity,
    );

    #[storage(read)]
    fn get_gas_router_storage_keys() -> (b256, u64, b256, u64);
}

impl HyperlaneGasRouterTest for Contract {
    #[storage(read, write)]
    fn initialize_hyperlane_connection_client(mailbox: b256, igp: b256) {
        initialize(mailbox, igp, ZERO_B256);
    }

    #[storage(read, write)]
    #[payable]
    fn dispatch_with_gas(
        destination_domain: u32,
        message_body: Bytes,
        gas_payment: u64,
        gas_payment_refund_address: Identity,
    ) {
        gas_router_storage_keys().dispatch_with_gas(
            destination_domain,
            message_body,
            gas_payment,
            gas_payment_refund_address,
        );
    }

    #[storage(read)]
    fn get_gas_router_storage_keys() -> (b256, u64, b256, u64) {
        let keys = gas_router_storage_keys();
        (keys.routers.slot, keys.routers.offset, keys.destination_gas.slot, keys.destination_gas.offset)
        // (storage.foo.slot, storage.foo.offset, storage.foo.slot, storage.foo.offset)
    }
}

impl HyperlaneGasRouter for Contract {
    #[storage(read, write)]
    fn set_destination_gas_configs(configs: Vec<GasRouterConfig>) {
        gas_router_storage_keys().set_destination_gas_configs(configs);
    }

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32) -> u64 {
        gas_router_storage_keys().quote_gas_payment(destination_domain)
    }

    #[storage(read)]
    fn destination_gas(domain: u32) -> u64 {
        gas_router_storage_keys().destination_gas(domain)
    }
}

impl HyperlaneRouter for Contract {
    #[storage(read)]
    fn routers(domain: u32) -> Option<b256> {
        storage.gas_router.routers.routers(domain)
    }

    #[storage(read, write)]
    fn enroll_remote_router(domain: u32, router: Option<b256>) {
        storage.gas_router.routers.enroll_remote_router(domain, router);
    }

    #[storage(read, write)]
    fn enroll_remote_routers(configs: Vec<RemoteRouterConfig>) {
        storage.gas_router.routers.enroll_remote_routers(configs);
    }
}

fn gas_router_storage_keys() -> GasRouterStorageKeys {
    GasRouterStorageKeys {
        routers: storage.gas_router.routers,
        destination_gas: storage.gas_router.destination_gas,
    }
}
