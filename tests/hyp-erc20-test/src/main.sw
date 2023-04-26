contract;

use std::constants::ZERO_B256;

use hyperlane_connection_client::initialize;
use hyperlane_router::Routers;
use hyperlane_gas_router::{GasRouterStorageKeys, interface::{GasRouterConfig, HyperlaneGasRouter}};

use token_router::interface::TokenRouter;

abi TokenRouterTest {
    #[storage(read, write)]
    fn initialize_hyperlane_connection_client(mailbox: b256, igp: b256);
}

storage {
    routers: Routers = Routers {},
    destination_gas: StorageMap<u32, u64> = StorageMap {},
}

impl TokenRouterTest for Contract {
    #[storage(read, write)]
    fn initialize_hyperlane_connection_client(mailbox: b256, igp: b256) {
        initialize(mailbox, igp, ZERO_B256)
    }
}

impl TokenRouter for Contract {
    #[storage(read, write)]
    #[payable]
    fn transfer_remote(destination: u32, recipient: b256) -> b256 {
        ZERO_B256
    }

    #[storage(read)]
    #[payable]
    fn pay_for_gas(message_id: b256, destination: u32) {}
}
