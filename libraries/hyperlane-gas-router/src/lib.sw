library;

mod interface;

use core::experimental::storage::*;
use std::experimental::storage::*;

use std::{bytes::Bytes, logging::log};

use hyperlane_connection_client::interchain_gas_paymaster;
use hyperlane_interfaces::igp::InterchainGasPaymaster;
use hyperlane_router::*;

use interface::GasRouterConfig;

type DestinationGas = StorageMap<u32, u64>;


// TODO: the desired interface for using a gas router
// is to declare a single `GasRouter` struct in storage,
// which would give access to Routers and destination gas.
// However, at the time of writing, forc v0.37.1 doesn't allow
// for multiple StorageMaps in a single struct.
// Instead, callers are expected to declare two separate storage variables, e.g.:
//
// storage {
//     routers: Routers,
//     destination_gas: StorageMap<u32, u64>,
// }
//
// Which can then be used to construct a `GasRouterStorageKeys`.

// pub struct GasRouter {
//     routers: Routers,
//     destination_gas: StorageMap<u32, u64>,
// }

/// Storage keys for Routers and the destination_gas map.
/// This is the type in which gas router functionality is
/// implemented for.
pub struct GasRouterStorageKeys {
    routers: StorageKey<Routers>,
    destination_gas: StorageKey<StorageMap<u32, u64>>,
}

/// Logged when a destination gas is set.
pub struct DestinationGasSetEvent {
    domain: u32,
    gas: u64,
}

impl GasRouterStorageKeys {
    /// Sets the gas for a destination.
    /// The caller is expected to perform authentication.
    #[storage(read, write)]
    pub fn set_destination_gas(self, domain: u32, gas: u64) {
        self.destination_gas.insert(domain, gas);
        log(DestinationGasSetEvent { domain, gas });
    }

    /// Gets the gas for a destination, defaulting to 0 if not set.
    #[storage(read)]
    pub fn destination_gas(self, domain: u32) -> u64 {
        self.destination_gas.get(domain).try_read().unwrap_or(0)
    }
}

impl GasRouterStorageKeys {
    /// Quotes the gas payment for a destination domain, using the
    /// configured gas.
    #[storage(read)]
    pub fn quote_gas_payment(self, destination_domain: u32) -> u64 {
        let igp = abi(InterchainGasPaymaster, interchain_gas_paymaster());
        igp.quote_gas_payment(destination_domain, self.destination_gas(destination_domain))
    }

    /// Dispatches a message to the enrolled router for the destination domain.
    /// The gas amount is the configured gas for the destination domain.
    #[storage(read, write)]
    pub fn dispatch_with_gas(
        self,
        destination_domain: u32,
        message_body: Bytes,
        gas_payment: u64,
        gas_payment_refund_address: Identity,
) -> b256 {
        self.routers.dispatch_with_gas(destination_domain, message_body, self.destination_gas(destination_domain), gas_payment, gas_payment_refund_address)
    }

    /// Sets many destination gas configs at once.
    #[storage(read, write)]
    pub fn set_destination_gas_configs(self, configs: Vec<GasRouterConfig>) {
        let mut i = 0;
        let len = configs.len();
        while i < len {
            let config = configs.get(i).unwrap();
            self.set_destination_gas(config.domain, config.gas);
            i += 1;
        }
    }
}
