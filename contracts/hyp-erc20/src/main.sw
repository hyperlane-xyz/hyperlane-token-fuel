contract;

mod ownable;
mod hyperlane_connection;

use std::u256::U256;

use core::experimental::storage::*;
use std::experimental::storage::*;

use hyperlane_interfaces::{igp::InterchainGasPaymaster, Mailbox};

use hyperlane_connection_client::{interchain_gas_paymaster, mailbox};

abi Token {
    #[storage(read)]
    fn total_supply() -> U256;
    fn decimals() -> u8;
    fn name() -> str[64];
    fn symbol() -> str[32];
}

storage {
    total_supply: U256 = U256::from((0, 0, 0, 0)),
}

configurable {
    NAME: str[64] = "HypErc20                                                        ",
    SYMBOL: str[32] = "HYP                             ",
    DECIMALS: u8 = 9u8,
}

impl Token for Contract {
    #[storage(read)]
    fn total_supply() -> U256 {
        storage.total_supply
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
