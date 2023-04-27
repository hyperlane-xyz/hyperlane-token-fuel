contract;

mod interface;

use std::{
    auth::msg_sender,
    bytes::Bytes,
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    context::{
        msg_amount,
        this_balance,
    },
    token::{
        burn,
        mint,
        transfer,
    },
    u256::U256,
};

use core::experimental::storage::*;
use std::experimental::storage::*;

use hyperlane_interfaces::{
    igp::InterchainGasPaymaster,
    Mailbox,
    MessageRecipient,
    ownable::Ownable,
};

use hyperlane_connection_client::{
    initialize as initialize_hyperlane_connection_client,
    interchain_gas_paymaster,
    interchain_security_module,
    interface::{
        HyperlaneConnectionClientGetter,
        HyperlaneConnectionClientSetter,
    },
    mailbox,
    only_mailbox,
    set_interchain_gas_paymaster,
    set_interchain_security_module,
    set_mailbox,
};

use hyperlane_router::{interface::{HyperlaneRouter, RemoteRouterConfig}, Routers};
use hyperlane_gas_router::{GasRouterStorageKeys, interface::{GasRouterConfig, HyperlaneGasRouter}};

use ownership::{data_structures::State, only_owner, owner, set_ownership, transfer_ownership};

use token_interface::Token;
use token_router::{
    interface::TokenRouter,
    local_amount_to_remote_amount,
    remote_amount_to_local_amount,
    TokenRouterStorageKeys,
};

use interface::HypERC20;

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

impl HypERC20 for Contract {
    #[storage(read, write)]
    fn initialize(
        initial_owner: Identity,
        mailbox_id: b256,
        interchain_gas_paymaster_id: b256,
        interchain_security_module_id: b256,
        total_supply: u64,
    ) {
        // This will revert if called twice, even if the sender is the owner.
        set_ownership(initial_owner);
        initialize_hyperlane_connection_client(mailbox_id, interchain_gas_paymaster_id, interchain_security_module_id);
        if total_supply > 0 {
            mint_to_identity(total_supply, initial_owner);
        }
    }
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

        let amount = remote_amount_to_local_amount(message.amount, REMOTE_DECIMALS, LOCAL_DECIMALS);

        // Transferring an amount of 0 to an Address will cause a panic, which is
        // documented FuelVM behavior.
        // We therefore do not attempt minting when the amount is zero.
        if amount > 0 {
            // TODO: support transferring to ContractIds.
            // There is no way to check if an address is a contract or not,
            // and transferring to a contract vs an EOA requires the use of a different
            // opcode.
            mint_to_identity(amount, Identity::Address(Address::from(message.recipient)));
        }
    }

    /// Returns the address of the ISM used for message verification.
    /// If zero address is returned, the mailbox default ISM is used.
    #[storage(read)]
    fn interchain_security_module() -> ContractId {
        ContractId::from(interchain_security_module())
    }
}

// ===========================================
// ======= Hyperlane Connection Client =======
// ===========================================

impl HyperlaneConnectionClientGetter for Contract {
    /// Gets the Mailbox.
    #[storage(read)]
    fn mailbox() -> b256 {
        mailbox()
    }

    /// Gets the InterchainGasPaymaster.
    #[storage(read)]
    fn interchain_gas_paymaster() -> b256 {
        interchain_gas_paymaster()
    }

    /// Gets the InterchainSecurityModule.
    #[storage(read)]
    fn interchain_security_module_dupe_todo_remove() -> b256 {
        interchain_security_module()
    }
}

impl HyperlaneConnectionClientSetter for Contract {
    /// Sets the Mailbox if the caller is the owner.
    #[storage(read, write)]
    fn set_mailbox(new_mailbox: b256) {
        only_owner();
        set_mailbox(new_mailbox);
    }

    /// Sets the InterchainGasPaymaster if the caller is the owner.
    #[storage(read, write)]
    fn set_interchain_gas_paymaster(new_interchain_gas_paymaster: b256) {
        only_owner();
        set_interchain_gas_paymaster(new_interchain_gas_paymaster);
    }

    /// Sets the InterchainSecurityModule if the caller is the owner.
    #[storage(read, write)]
    fn set_interchain_security_module(module: b256) {
        only_owner();
        set_interchain_security_module(module);
    }
}

// ===========================================
// ================= Ownable =================
// ===========================================

impl Ownable for Contract {
    #[storage(read)]
    fn owner() -> State {
        owner()
    }

    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity) {
        transfer_ownership(new_owner)
    }

    #[storage(read, write)]
    fn set_ownership(new_owner: Identity) {
        set_ownership(new_owner)
    }
}

// ===========================================
// ============ Hyperlane Router =============
// ===========================================

impl HyperlaneRouter for Contract {
    #[storage(read)]
    fn routers(domain: u32) -> Option<b256> {
        storage.routers.routers(domain)
    }

    #[storage(read, write)]
    fn enroll_remote_router(domain: u32, router: Option<b256>) {
        only_owner();
        storage.routers.enroll_remote_router(domain, router);
    }

    #[storage(read, write)]
    fn enroll_remote_routers(configs: Vec<RemoteRouterConfig>) {
        only_owner();
        storage.routers.enroll_remote_routers(configs);
    }
}

// ===========================================
// ========== Hyperlane Gas Router ===========
// ===========================================

impl HyperlaneGasRouter for Contract {
    #[storage(read, write)]
    fn set_destination_gas_configs(configs: Vec<GasRouterConfig>) {
        only_owner();
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

// ===========================================
// ================= helpers =================
// ===========================================

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
fn mint_to_identity(amount: u64, recipient: Identity) {
    mint_tokens(amount);
    transfer(amount, contract_id(), recipient);
}

#[storage(read, write)]
fn mint_tokens(amount: u64) {
    mint(amount);
    storage.total_supply.write(total_supply() + U256::from((0, 0, 0, amount)));
}

#[storage(read)]
fn total_supply() -> U256 {
    storage.total_supply.try_read().unwrap_or(U256::from((0, 0, 0, 0)))
}
