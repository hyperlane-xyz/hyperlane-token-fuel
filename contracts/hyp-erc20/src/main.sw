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

use ownership::{*, data_structures::State};

use token_interface::Token;
use token_router::{
    interface::TokenRouter,
    local_amount_to_remote_amount,
    remote_amount_to_local_amount,
    TokenRouterStorageKeys,
};

use interface::HypERC20;

storage {
    ownership: Ownership = Ownership::uninitialized(),
    total_supply: U256 = U256::from((0, 0, 0, 0)),
    routers: Routers = Routers {},
    destination_gas: StorageMap<u32, u64> = StorageMap {},
}

configurable {
    NAME: str[64] = "HypErc20                                                        ",
    SYMBOL: str[32] = "HYP                             ",
    /// The number of decimals for the local token on Fuel.
    LOCAL_DECIMALS: u8 = 9u8,
    /// The number of decimals for the remote token on remote chains.
    REMOTE_DECIMALS: u8 = 18u8,
}

impl HypERC20 for Contract {
    /// Initializes the contract. Reverts if called more than once.
    #[storage(read, write)]
    fn initialize(
        initial_owner: Identity,
        mailbox_id: b256,
        interchain_gas_paymaster_id: b256,
        interchain_security_module_id: b256,
        total_supply: u64,
    ) {
        // This will revert if called twice, even if the sender is the owner.
        storage.ownership.set_ownership(initial_owner);
        initialize_hyperlane_connection_client(mailbox_id, interchain_gas_paymaster_id, interchain_security_module_id);
        if total_supply > 0 {
            mint_to_identity(total_supply, initial_owner);
        }
    }
}

impl Token for Contract {
    /// The total supply of the token on the local chain.
    #[storage(read)]
    fn total_supply() -> U256 {
        total_supply()
    }

    /// The number of decimals for the token.
    fn decimals() -> u8 {
        LOCAL_DECIMALS
    }

    /// The name of the token with trailing whitespace to fit in 64 chars.
    fn name() -> str[64] {
        NAME
    }

    /// The symbol of the token with trailing whitespace to fit in 32 chars.
    fn symbol() -> str[32] {
        SYMBOL
    }
}

impl TokenRouter for Contract {
    /// Transfers the tokens sent along with this call to a remote recipient.
    /// The tokens are burned on the local chain.
    ///
    /// Note that IGP payments must be made via a subsequent call to `pay_for_gas`.
    /// This is because the FuelVM only allows one asset to be transferred in a
    /// single function call.
    ///
    /// ### Arguments
    ///
    /// * `destination` - The destination domain ID.
    /// * `recipient` - The recipient on the destination chain.
    ///
    /// ### Returns
    ///
    /// * `message_id` - The message ID of the message sent to the remote chain.
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

    /// Pays for interchain gas for a message previously sent via `transfer_remote`.
    /// Refunds are sent to the msg sender.
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
        // We therefore do not attempt minting when the amount is zero, but still allow
        // the message to be processed.
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
}

impl HyperlaneConnectionClientSetter for Contract {
    /// Sets the Mailbox if the caller is the owner.
    #[storage(read, write)]
    fn set_mailbox(new_mailbox: b256) {
        storage.ownership.only_owner();
        set_mailbox(new_mailbox);
    }

    /// Sets the InterchainGasPaymaster if the caller is the owner.
    #[storage(read, write)]
    fn set_interchain_gas_paymaster(new_interchain_gas_paymaster: b256) {
        storage.ownership.only_owner();
        set_interchain_gas_paymaster(new_interchain_gas_paymaster);
    }

    /// Sets the InterchainSecurityModule if the caller is the owner.
    #[storage(read, write)]
    fn set_interchain_security_module(module: b256) {
        storage.ownership.only_owner();
        set_interchain_security_module(module);
    }
}

// ===========================================
// ================= Ownable =================
// ===========================================

impl Ownable for Contract {
    /// Gets the owner.
    #[storage(read)]
    fn owner() -> State {
        storage.ownership.owner()
    }

    /// Transfers ownership if the caller is the owner.
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity) {
        storage.ownership.transfer_ownership(new_owner)
    }

    /// Sets ownership. Can only ever be called once.
    #[storage(read, write)]
    fn set_ownership(new_owner: Identity) {
        storage.ownership.set_ownership(new_owner)
    }
}

// ===========================================
// ============ Hyperlane Router =============
// ===========================================

impl HyperlaneRouter for Contract {
    /// Gets the router for a domain.
    /// Called `routers` to match the interface in Solidity.
    #[storage(read)]
    fn routers(domain: u32) -> Option<b256> {
        storage.routers.routers(domain)
    }

    /// Enrolls a router for a domain.
    /// Only callable by the owner.
    #[storage(read, write)]
    fn enroll_remote_router(domain: u32, router: Option<b256>) {
        storage.ownership.only_owner();
        storage.routers.enroll_remote_router(domain, router);
    }

    /// Enrolls multiple routers for multiple domains.
    /// Only callable by the owner.
    #[storage(read, write)]
    fn enroll_remote_routers(configs: Vec<RemoteRouterConfig>) {
        storage.ownership.only_owner();
        storage.routers.enroll_remote_routers(configs);
    }
}

// ===========================================
// ========== Hyperlane Gas Router ===========
// ===========================================

impl HyperlaneGasRouter for Contract {
    /// Sets multiple destination gas configs, which are used to determine
    /// the amount of gas that IGP payments should pay for.
    /// Only callable by the owner.
    #[storage(read, write)]
    fn set_destination_gas_configs(configs: Vec<GasRouterConfig>) {
        storage.ownership.only_owner();
        gas_router_storage_keys().set_destination_gas_configs(configs);
    }

    /// Quotes the payment for a message to the destination domain.
    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32) -> u64 {
        gas_router_storage_keys().quote_gas_payment(destination_domain)
    }

    /// Gets the amount of destination gas for a domain.
    #[storage(read)]
    fn destination_gas(domain: u32) -> u64 {
        gas_router_storage_keys().destination_gas(domain)
    }
}

// ===========================================
// ================= helpers =================
// ===========================================

/// Returns a `GasRouterStorageKeys`, which is used by the gas router.
fn gas_router_storage_keys() -> GasRouterStorageKeys {
    GasRouterStorageKeys {
        routers: storage.routers,
        destination_gas: storage.destination_gas,
    }
}

/// Returns a `TokenRouterStorageKeys`, which is used by the token router.
fn token_router_storage_keys() -> TokenRouterStorageKeys {
    gas_router_storage_keys()
}

/// Burns the amount of tokens from this contract's balance, and reduces the total supply.
#[storage(read, write)]
fn burn_tokens(amount: u64) {
    burn(amount);
    storage.total_supply.write(total_supply() - U256::from((0, 0, 0, amount)));
}

/// Mints the amount of tokens to this contract's balance, and increases the total supply.
#[storage(read, write)]
fn mint_tokens(amount: u64) {
    mint(amount);
    storage.total_supply.write(total_supply() + U256::from((0, 0, 0, amount)));
}

/// Mints the amount of tokens to the recipient, and increases the total supply.
#[storage(read, write)]
fn mint_to_identity(amount: u64, recipient: Identity) {
    mint_tokens(amount);
    transfer(amount, contract_id(), recipient);
}

/// Returns the total supply of tokens, defaulting to 0 if not initialized.
#[storage(read)]
fn total_supply() -> U256 {
    storage.total_supply.try_read().unwrap_or(U256::from((0, 0, 0, 0)))
}
