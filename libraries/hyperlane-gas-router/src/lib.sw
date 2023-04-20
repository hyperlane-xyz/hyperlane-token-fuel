library;

use core::experimental::storage::*;
use std::experimental::storage::*;

use std::{bytes::Bytes, logging::log};

use hyperlane_router::*;

type DestinationGas = StorageMap<u32, u64>;

pub struct GasRouter {
    routers: Routers,
    destination_gas: StorageMap<u32, u64>,
}

pub struct GasRouterStorageKeys {
    routers: StorageKey<Routers>,
    destination_gas: StorageKey<StorageMap<u32, u64>>,
}

pub struct DestinationGasSetEvent {
    domain: u32,
    gas: u64,
}

impl GasRouterStorageKeys {
    #[storage(read, write)]
    pub fn set_destination_gas(self, domain: u32, gas: u64) {
        self.destination_gas.insert(domain, gas);
        log(DestinationGasSetEvent { domain, gas });
    }

    #[storage(read, write)]
    pub fn dispatch_with_gas(
        self,
        destination_domain: u32,
        message_body: Bytes,
        gas_payment: u64,
        gas_payment_refund_address: Identity,
) -> b256 {
        self.routers.dispatch_with_gas(destination_domain, message_body, self.destination_gas.get(destination_domain).try_read().unwrap_or(0), gas_payment, gas_payment_refund_address)
    }
}
