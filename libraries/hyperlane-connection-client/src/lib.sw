library;

mod r#storage;
mod interface;

use std::{auth::msg_sender, logging::log, storage::{get, store}, u256::U256};

use hyperlane_interfaces::{Mailbox};
use std_lib_extended::option::*;

use storage::{
    INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY,
    INTERCHAIN_SECURITY_MODULE_STORAGE_KEY,
    MAILBOX_STORAGE_KEY,
};

pub struct MailboxSetEvent {
    mailbox: b256,
}

pub struct InterchainGasPaymasterSetEvent {
    interchain_gas_paymaster: b256,
}

pub struct InterchainSecurityModuleSetEvent {
    module: b256,
}

// ==================== initializer ====================

/// Sets the mailbox, IGP, and ISM.
/// Reverts if any of them have already been set.
#[storage(read, write)]
pub fn initialize(mailbox: b256, interchain_gas_paymaster: b256, interchain_security_module: b256) {
    require(
        try_mailbox().is_none() &&
        try_interchain_gas_paymaster().is_none() &&
        try_interchain_security_module().is_none(),
        "hyperlane connection client already initialized"
    );

    set_mailbox(mailbox);
    set_interchain_gas_paymaster(interchain_gas_paymaster);
    set_interchain_security_module(interchain_security_module);
}

// ==================== setters ====================

#[storage(read, write)]
pub fn set_mailbox(mailbox: b256) {
    store(MAILBOX_STORAGE_KEY, mailbox);
    log(MailboxSetEvent { mailbox });
}

#[storage(read, write)]
pub fn set_interchain_gas_paymaster(interchain_gas_paymaster: b256) {
    store(INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY, interchain_gas_paymaster);
    log(InterchainGasPaymasterSetEvent {
        interchain_gas_paymaster,
    });
}

#[storage(read, write)]
pub fn set_interchain_security_module(module: b256) {
    store(INTERCHAIN_SECURITY_MODULE_STORAGE_KEY, module);
    log(InterchainSecurityModuleSetEvent { module });
}

// ==================== getters ====================

#[storage(read)]
pub fn mailbox() -> b256 {
    try_mailbox().expect("mailbox not set")
}

#[storage(read)]
pub fn interchain_gas_paymaster() -> b256 {
    try_interchain_gas_paymaster().expect("IGP not set")
}

#[storage(read)]
pub fn interchain_security_module() -> b256 {
    try_interchain_security_module().expect("ISM not set")
}

// ==================== public helpers ====================

#[storage(read)]
pub fn only_mailbox() {
    require(msg_sender_b256() == mailbox(), "msg sender not mailbox");
}

// ==================== internal helpers ====================

#[storage(read)]
fn try_mailbox() -> Option<b256> {
    get(MAILBOX_STORAGE_KEY)
}

#[storage(read)]
fn try_interchain_gas_paymaster() -> Option<b256> {
    get(INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY)
}

#[storage(read)]
fn try_interchain_security_module() -> Option<b256> {
    get(INTERCHAIN_SECURITY_MODULE_STORAGE_KEY)
}

/// Gets the b256 representation of the msg_sender.
fn msg_sender_b256() -> b256 {
    match msg_sender().unwrap() {
        Identity::Address(address) => address.into(),
        Identity::ContractId(id) => id.into(),
    }
}
