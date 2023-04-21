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
    GasRouterStorageKeys,
};

use hyperlane_router::{
    interface::{
        HyperlaneRouter,
        RemoteRouterConfig,
    },
    Routers,
};

storage {
    routers: Routers = Routers {},
    destination_gas: StorageMap<u32, u64> = StorageMap {},
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

fn gas_router_storage_keys() -> GasRouterStorageKeys {
    GasRouterStorageKeys {
        routers: storage.routers,
        destination_gas: storage.destination_gas,
    }
}
