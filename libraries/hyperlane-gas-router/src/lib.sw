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

pub struct GasRouter {
    routers: Routers,
    a: u64,
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

    #[storage(read)]
    pub fn destination_gas(self, domain: u32) -> u64 {
        self.destination_gas.get(domain).try_read().unwrap_or(0)
    }
}

impl GasRouterStorageKeys {
    #[storage(read)]
    pub fn quote_gas_payment(self, destination_domain: u32) -> u64 {
        let igp = abi(InterchainGasPaymaster, interchain_gas_paymaster());
        igp.quote_gas_payment(destination_domain, self.destination_gas(destination_domain))
    }

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
