library;

mod interface;

use std::{auth::msg_sender, bytes::Bytes, constants::BASE_ASSET_ID, logging::log};

use std_lib_extended::option::*;

use hyperlane_interfaces::{igp::InterchainGasPaymaster, Mailbox};
use hyperlane_connection_client::{interchain_gas_paymaster, mailbox};

use interface::RemoteRouterConfig;

// A library for sending messages to remote domains with a configured amount
// of gas. Expected to be used alongside the hyperlane-connection-client library.

/// A map from domain ID to remote router address.
pub type Routers = StorageMap<u32, b256>;

/// Logged when a remote router is enrolled.
pub struct RemoteRouterEnrolledEvent {
    domain: u32,
    router: Option<b256>,
}

impl StorageKey<Routers> {
    /// Returns the router enrolled for the given domain, or None if no router is enrolled.
    #[storage(read)]
    pub fn routers(self, domain: u32) -> Option<b256> {
        // Cast to StorageKey<StorageMap<u32, b256>> to get access to the fns implemented
        // for StorageKey<StorageMap<_, _>>.
        let map: StorageKey<StorageMap<u32, b256>> = self;
        map.get(domain).try_read()
    }

    /// Enrolls a remote router for the given domain.
    /// If the provided router is None, the router is effectively unenrolled.
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
                let _ = map.remove(domain);
            }
        }
        log(RemoteRouterEnrolledEvent { domain, router });
    }
}

impl StorageKey<Routers> {
    /// Enrolls multiple remote routers.
    #[storage(read, write)]
    pub fn enroll_remote_routers(self, configs: Vec<RemoteRouterConfig>) {
        let mut i = 0;
        let len = configs.len();
        while i < len {
            let config = configs.get(i).unwrap();
            self.enroll_remote_router(config.domain, config.router);
            i += 1;
        }
    }

    /// Returns whether the provided router is enrolled for the given domain.
    /// Does not revert even if there is no router enrolled for the domain.
    #[storage(read)]
    pub fn is_remote_router(self, domain: u32, router: b256) -> bool {
        match self.routers(domain) {
            Option::Some(r) => r == router,
            Option::None => false,
        }
    }

    /// Dispatches a message to the router enrolled for the given domain.
    /// Reverts if there is no router enrolled for the domain.
    /// Reverts if the Mailbox has not been set in the HyperlaneConnectionClient.
    #[storage(read, write)]
    pub fn dispatch(self, destination_domain: u32, message_body: Bytes) -> b256 {
        let router = self.routers(destination_domain).expect("No router enrolled for domain. Did you specify the right domain ID?");
        let mailbox_contract = abi(Mailbox, mailbox());
        mailbox_contract.dispatch(destination_domain, router, message_body)
    }

    /// Dispatches a message to the router enrolled for the given domain,
    /// and pays for interchain gas.
    /// Reverts if there is no router enrolled for the domain.
    /// Reverts if the Mailbox or IGP have not been set in the HyperlaneConnectionClient.
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

impl StorageKey<Routers> {
    /// Reverts if the provided router is not enrolled for the given domain.
    #[storage(read)]
    pub fn only_remote_router(self, domain: u32, router: b256) {
        require(self.is_remote_router(domain, router), "provided router is not enrolled for origin domain");
    }
}
