library;

mod r#storage;
mod interface;

use std::{auth::msg_sender, storage::{get, store}, u256::U256};

use hyperlane_interfaces::{Mailbox};
use std_lib_extended::option::*;

use storage::{
    INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY,
    INTERCHAIN_SECURITY_MODULE_STORAGE_KEY,
    MAILBOX_STORAGE_KEY,
};

pub struct MailboxSet {
    mailbox: b256,
}

pub struct InterchainGasPaymasterSet {
    interchain_gas_paymaster: b256,
}

pub struct InterchainSecurityModuleSet {
    module: b256,
}

#[storage(read, write)]
pub fn set_mailbox(mailbox: b256) {
    store(MAILBOX_STORAGE_KEY, mailbox);
    log(MailboxSet { mailbox });
}

#[storage(read, write)]
pub fn set_interchain_gas_paymaster(interchain_gas_paymaster: b256) {
    store(INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY, interchain_gas_paymaster);
    log(InterchainGasPaymasterSet {
        interchain_gas_paymaster,
    });
}

#[storage(read, write)]
pub fn set_interchain_security_module(module: b256) {
    store(INTERCHAIN_SECURITY_MODULE_STORAGE_KEY, module);
    log(InterchainSecurityModuleSet { module });
}

#[storage(read)]
pub fn mailbox() -> b256 {
    get(MAILBOX_STORAGE_KEY).expect("no mailbox stored")
}

#[storage(read)]
pub fn interchain_gas_paymaster() -> b256 {
    get(INTERCHAIN_GAS_PAYMASTER_STORAGE_KEY).expect("no IGP stored")
}

#[storage(read)]
pub fn interchain_security_module() -> b256 {
    get(INTERCHAIN_SECURITY_MODULE_STORAGE_KEY).expect("no ISM stored")
}
