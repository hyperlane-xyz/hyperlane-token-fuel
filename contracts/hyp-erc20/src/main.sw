contract;

mod ownable;
mod hyperlane_connection;

use std::{bytes::Bytes, u256::U256};

use core::experimental::storage::*;
use std::experimental::storage::*;

use hyperlane_interfaces::{igp::InterchainGasPaymaster, Mailbox, MessageRecipient};

use hyperlane_connection_client::{
    interchain_gas_paymaster,
    interchain_security_module,
    mailbox,
    only_mailbox,
};
use hyperlane_router::{Routers};
use hyperlane_gas_router::{GasRouter, GasRouterStorageKeys};

abi Token {
    #[storage(read)]
    fn total_supply() -> U256;
    fn decimals() -> u8;
    fn name() -> str[64];
    fn symbol() -> str[32];
}

storage {
    total_supply: U256 = U256::from((0, 0, 0, 0)),
    gas_router: GasRouter = GasRouter {
        routers: Routers {},
        destination_gas: StorageMap {},
    },
}

configurable {
    NAME: str[64] = "HypErc20                                                        ",
    SYMBOL: str[32] = "HYP                             ",
    DECIMALS: u8 = 9u8,
}

impl Token for Contract {
    #[storage(read)]
    fn total_supply() -> U256 {
        storage.total_supply.read()
    }

    fn decimals() -> u8 {
        DECIMALS
    }

    fn name() -> str[64] {
        NAME
    }

    fn symbol() -> str[32] {
        SYMBOL
    }
}

impl MessageRecipient for Contract {
    /// Handles a message once it has been verified by Mailbox.process
    ///
    /// ### Arguments
    ///
    /// * `origin` - The origin domain identifier.
    /// * `sender` - The sender address on the origin chain.
    /// * `message_body` - Raw bytes content of the message body.
    #[storage(read, write)]
    fn handle(origin: u32, sender: b256, message_body: Bytes) {
        only_mailbox();

        // TODO
    }

    /// Returns the address of the ISM used for message verification.
    /// If zero address is returned, the mailbox default ISM is used.
    #[storage(read)]
    fn interchain_security_module() -> ContractId {
        ContractId::from(interchain_security_module())
    }
}

fn gas_router_storage_keys() -> GasRouterStorageKeys {
    GasRouterStorageKeys {
        routers: storage.gas_router.routers,
        destination_gas: storage.gas_router.destination_gas,
    }
}
