library;

use core::experimental::storage::*;
use std::experimental::storage::*;
use std::{bytes::Bytes, constants::BASE_ASSET_ID, logging::log};

use std_lib_extended::option::*;

use hyperlane_interfaces::{igp::InterchainGasPaymaster, Mailbox};
use hyperlane_connection_client::{interchain_gas_paymaster, mailbox};

pub type Routers = StorageMap<u32, b256>;

pub struct RemoteRouterEnrolledEvent {
    domain: u32,
    router: Option<b256>,
}

impl StorageKey<Routers> {
    #[storage(read)]
    pub fn routers(self, domain: u32) -> Option<b256> {
        // Cast to StorageKey<StorageMap<u32, b256>> to get access to the fns implemented
        // for StorageKey<StorageMap<_, _>>.
        let map: StorageKey<StorageMap<u32, b256>> = self;
        map.get(domain).try_read()
    }

    #[storage(read, write)]
    pub fn enroll_remote_router(self, domain: u32, router: Option<b256>) {
        // Cast to StorageKey<StorageMap<u32, b256>> to get access to the fns implemented
        // for StorageKey<StorageMap<_, _>>.
        let map: StorageKey<StorageMap<u32, b256>> = self;
        match router {
            Option::Some(r) => {
                map.insert(domain, r);
            },
            Option::None => {
                // This returns whether the storage was previously set - this can be ignored.
                map.remove(domain);
            }
        }
        log(RemoteRouterEnrolledEvent { domain, router });
    }
}

impl StorageKey<Routers> {
    #[storage(read)]
    pub fn is_remote_router(self, domain: u32, router: b256) -> bool {
        match self.routers(domain) {
            Option::Some(r) => r == router,
            Option::None => false,
        }
    }

    #[storage(read, write)]
    pub fn dispatch(self, destination_domain: u32, message_body: Bytes) -> b256 {
        let router = self.routers(destination_domain).expect("No router enrolled for domain. Did you specify the right domain ID?");

        let mailbox_contract = abi(Mailbox, mailbox());
        mailbox_contract.dispatch(destination_domain, router, message_body)
    }

    #[storage(read, write)]
    pub fn dispatch_with_gas(
        self,
        destination_domain: u32,
        message_body: Bytes,
        gas_amount: u64,
        gas_payment: u64,
        gas_payment_refund_address: Identity,
) -> b256 {
        let router = self.routers(destination_domain).expect("No router enrolled for domain. Did you specify the right domain ID?");

        let mailbox_contract = abi(Mailbox, mailbox());
        let message_id = mailbox_contract.dispatch(destination_domain, router, message_body);

        let igp = abi(InterchainGasPaymaster, interchain_gas_paymaster());
        igp.pay_for_gas {
            asset_id: BASE_ASSET_ID.value,
            coins: gas_payment,
        }(message_id, destination_domain, gas_amount, gas_payment_refund_address);

        message_id
    }
}
