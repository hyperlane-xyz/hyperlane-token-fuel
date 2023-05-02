library;

mod r#storage;
mod interface;

use std::{auth::msg_sender, logging::log, storage::storage_api::{read, write}, u256::U256};

use hyperlane_interfaces::{Mailbox};
use std_lib_extended::{auth::msg_sender_b256, option::*};

use storage::{
    INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY,
    INTERCHAIN_SECURITY_MODULE_STORAGE_KEY,
    MAILBOX_STORAGE_KEY,
};

// This library manages stored b256s corresponding to the IDs of a mailbox, IGP, and ISM.

// TODO: consider moving things into a struct:
//    struct HyperlaneConnectionClient {
//        mailbox: b256,
//        interchain_gas_paymaster: b256,
//        interchain_security_module: b256,
//    }
//
// This wasnt done because the storage API doesn't allow for
// reading specific fields of a struct, only the entire struct.
// E.g. `connection_client.read().mailbox` is possible,
// but this reads the IGP & ISM b256s as well.

/// Logged when the Mailbox is set.
pub struct MailboxSetEvent {
    mailbox: b256,
}

/// Logged when the InterchainGasPaymaster is set.
pub struct InterchainGasPaymasterSetEvent {
    interchain_gas_paymaster: b256,
}

/// Logged when the InterchainSecurityModule is set.
pub struct InterchainSecurityModuleSetEvent {
    module: b256,
}

// ==================== initializer ====================

/// Sets the mailbox, IGP, and ISM.
/// Reverts if any of them have already been set.
#[storage(read, write)]
pub fn initialize(
    mailbox: b256,
    interchain_gas_paymaster: b256,
    interchain_security_module: b256,
) {
    require(try_mailbox().is_none() && try_interchain_gas_paymaster().is_none() && try_interchain_security_module().is_none(), "hyperlane connection client already initialized");

    set_mailbox(mailbox);
    set_interchain_gas_paymaster(interchain_gas_paymaster);
    set_interchain_security_module(interchain_security_module);
}

// ==================== setters ====================

/// Sets the Mailbox.
/// The caller is expected to perform authentication.
#[storage(write)]
pub fn set_mailbox(mailbox: b256) {
    write(MAILBOX_STORAGE_KEY, 0, mailbox);
    log(MailboxSetEvent { mailbox });
}

/// Sets the InterchainGasPaymaster.
/// The caller is expected to perform authentication.
#[storage(write)]
pub fn set_interchain_gas_paymaster(interchain_gas_paymaster: b256) {
    write(INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY, 0, interchain_gas_paymaster);
    log(InterchainGasPaymasterSetEvent {
        interchain_gas_paymaster,
    });
}

/// Sets the InterchainSecurityModule.
/// The caller is expected to perform authentication.
#[storage(write)]
pub fn set_interchain_security_module(module: b256) {
    write(INTERCHAIN_SECURITY_MODULE_STORAGE_KEY, 0, module);
    log(InterchainSecurityModuleSetEvent { module });
}

// ==================== getters ====================

/// Returns the Mailbox, reverting if one is not set.
#[storage(read)]
pub fn mailbox() -> b256 {
    try_mailbox().expect("mailbox not set")
}

/// Returns the InterchainGasPaymaster, reverting if one is not set.
#[storage(read)]
pub fn interchain_gas_paymaster() -> b256 {
    try_interchain_gas_paymaster().expect("IGP not set")
}

/// Returns the InterchainSecurityModule, reverting if one is not set.
#[storage(read)]
pub fn interchain_security_module() -> b256 {
    try_interchain_security_module().expect("ISM not set")
}

// ==================== public helpers ====================

/// Reverts if the msg sender is not the Mailbox.
#[storage(read)]
pub fn only_mailbox() {
    require(msg_sender_b256() == mailbox(), "msg sender not mailbox");
}

// ==================== internal helpers ====================

/// Returns the Mailbox, or None if one is not set.
#[storage(read)]
fn try_mailbox() -> Option<b256> {
    read(MAILBOX_STORAGE_KEY, 0)
}

/// Returns the InterchainGasPaymaster, or None if one is not set.
#[storage(read)]
fn try_interchain_gas_paymaster() -> Option<b256> {
    read(INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY, 0)
}

/// Returns the InterchainSecurityModule, or None if one is not set.
#[storage(read)]
fn try_interchain_security_module() -> Option<b256> {
    read(INTERCHAIN_SECURITY_MODULE_STORAGE_KEY, 0)
}
