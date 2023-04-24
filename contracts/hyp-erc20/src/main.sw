contract;

mod ownable;
mod hyperlane_connection;

use std::{
    auth::msg_sender,
    bytes::Bytes,
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    context::msg_amount,
    token::{
        burn,
        mint_to,
    },
    u256::U256,
};

use core::experimental::storage::*;
use std::experimental::storage::*;

use hyperlane_interfaces::{igp::InterchainGasPaymaster, Mailbox, MessageRecipient};

use hyperlane_connection_client::{
    interchain_gas_paymaster,
    interchain_security_module,
    mailbox,
    only_mailbox,
};
use hyperlane_router::Routers;
use hyperlane_gas_router::GasRouterStorageKeys;

use token_interface::Token;
use token_router::{
    interface::TokenRouter,
    local_amount_to_remote_amount,
    remote_amount_to_local_amount,
    TokenRouterStorageKeys,
};

storage {
    total_supply: U256 = U256::from((0, 0, 0, 0)),
    routers: Routers = Routers {},
    destination_gas: StorageMap<u32, u64> = StorageMap {},
}

configurable {
    NAME: str[64] = "HypErc20                                                        ",
    SYMBOL: str[32] = "HYP                             ",
    LOCAL_DECIMALS: u8 = 9u8,
    REMOTE_DECIMALS: u8 = 18u8,
}

impl Token for Contract {
    #[storage(read)]
    fn total_supply() -> U256 {
        total_supply()
    }

    fn decimals() -> u8 {
        LOCAL_DECIMALS
    }

    fn name() -> str[64] {
        NAME
    }

    fn symbol() -> str[32] {
        SYMBOL
    }
}

impl TokenRouter for Contract {
    #[storage(read, write)]
    #[payable]
    fn transfer_remote(destination: u32, recipient: b256) -> b256 {
        require(msg_asset_id() == contract_id(), "msg_asset_id not self");
        let amount = msg_amount();
        // Burn the tokens.
        burn_tokens(amount);
        // Transfer to the remote.
        token_router_storage_keys().transfer_remote(destination, recipient, local_amount_to_remote_amount(amount, LOCAL_DECIMALS, REMOTE_DECIMALS), Option::None)
    }

    #[storage(read)]
    #[payable]
    fn pay_for_gas(message_id: b256, destination: u32) {
        token_router_storage_keys().pay_for_gas(message_id, destination, msg_amount(), msg_sender().unwrap());
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

        let message = token_router_storage_keys().handle(origin, sender, message_body);

        // Note that transferring an amount of 0 to an Address will cause a panic.
        // We therefore do not attempt minting when the amount is zero.
        let amount = remote_amount_to_local_amount(message.amount, REMOTE_DECIMALS, LOCAL_DECIMALS);

        if amount > 0 {
            // TODO this should work for Address and ContractIds.
            // Figure out how to determine if the recipient is a contract or not on chain
            transfer_to(amount, Identity::Address(Address::from(message.recipient)));
        }
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
        routers: storage.routers,
        destination_gas: storage.destination_gas,
    }
}

fn token_router_storage_keys() -> TokenRouterStorageKeys {
    gas_router_storage_keys()
}

#[storage(read, write)]
fn burn_tokens(amount: u64) {
    burn(amount);
    storage.total_supply.write(total_supply() - U256::from((0, 0, 0, amount)));
}

#[storage(read, write)]
fn transfer_to(amount: u64, recipient: Identity) {
    mint_to(amount, recipient);
    storage.total_supply.write(total_supply() + U256::from((0, 0, 0, amount)));
}

#[storage(read)]
fn total_supply() -> U256 {
    storage.total_supply.try_read().unwrap_or(U256::from((0, 0, 0, 0)))
}
