library;

mod interface;

use std::{auth::msg_sender, bytes::Bytes, context::msg_amount, u256::U256};

use std_lib_extended::{result::*, u256::*};

use hyperlane_gas_router::GasRouterStorageKeys;
use message::{EncodedMessage, Message};

pub type TokenRouterStorageKeys = GasRouterStorageKeys;

pub struct SentTransferRemoteEvent {
    destination: u32,
    recipient: b256,
    amount: U256,
}

pub struct ReceivedTransferRemoteEvent {
    origin: u32,
    recipient: b256,
    amount: U256,
}

impl TokenRouterStorageKeys {
    /// Sends a transfer remote message and logs the event.
    /// Does not pay for gas.
    #[storage(read, write)]
    pub fn transfer_remote(
        self,
        destination: u32,
        recipient: b256,
        amount_or_id: U256,
        metadata: Option<Bytes>,
) -> b256 {
        let id = self.routers.dispatch(destination, EncodedMessage::new(recipient, amount_or_id, metadata).bytes);
        log(SentTransferRemoteEvent {
            destination,
            recipient,
            amount: amount_or_id,
        });
        id
    }

    /// Handles a transfer remote message by logging the event and returning the
    /// decoded message.
    /// Reverts if the sender is not the enrolled remote router for the origin domain.
    #[storage(read)]
    pub fn handle(self, origin: u32, sender: b256, message_bytes: Bytes) -> Message {
        // Only the enrolled remote router can send messages to this contract
        self.routers.only_remote_router(origin, sender);

        let message: Message = EncodedMessage {
            bytes: message_bytes,
        }.into();
        log(ReceivedTransferRemoteEvent {
            origin,
            recipient: message.recipient,
            amount: message.amount,
        });
        message
    }
}

// The following functions are used to convert between local and remote amounts.
// The FuelVM uses u64s for token balance accounting, while other execution
// environments tend to use U256s.
// This means that tokens on remote domains may have higher decimals that cannot
// be directly represented in the local domain. For example, a token with 18 decimals
// on Ethereum should be represented as a u64 with 9 decimals on the FuelVM.

/// Converts a local amount (u64) to a remote amount (U256).
pub fn local_amount_to_remote_amount(amount: u64, local_decimals: u8, remote_decimals: u8) -> U256 {
    let amount = U256::from((0, 0, 0, amount));
    convert_decimals(amount, local_decimals, remote_decimals)
}

/// Converts a remote amount (U256) to a local amount (u64).
pub fn remote_amount_to_local_amount(amount: U256, remote_decimals: u8, local_decimals: u8) -> u64 {
    let amount = convert_decimals(amount, remote_decimals, local_decimals);
    amount.as_u64().expect("remote to local amount conversion overflow")
}

/// Converts a U256 amount from one decimal representation to another.
fn convert_decimals(amount: U256, from_decimals: u8, to_decimals: u8) -> U256 {
    if from_decimals < to_decimals {
        let decimal_difference: u64 = to_decimals - from_decimals;
        let multiplier = U256::from((0, 0, 0, 10)).pow(U256::from((0, 0, 0, decimal_difference)));
        return amount * multiplier;
    } else if from_decimals > to_decimals {
        let decimal_difference: u64 = from_decimals - to_decimals;
        let divisor = U256::from((0, 0, 0, 10)).pow(U256::from((0, 0, 0, decimal_difference)));
        return amount / divisor;
    } else {
        return amount;
    }
}

#[test()]
fn test_local_amount_to_remote_amount() {
    let amount = 112233445566;

    // 9 to 18 decimals
    let local_decimals = 9;
    let remote_decimals = 18;
    // Should be the amount * 10^9
    assert(local_amount_to_remote_amount(amount, local_decimals, remote_decimals) == (U256::from((0, 0, 0, amount)) * U256::from((0, 0, 0, 1000000000))));

    // 9 to 9 decimals
    let local_decimals = 9;
    let remote_decimals = 9;
    // Should be the amount without change
    assert(local_amount_to_remote_amount(amount, local_decimals, remote_decimals) == U256::from((0, 0, 0, amount)));

    // 9 to 3 decimals
    let local_decimals = 9;
    let remote_decimals = 3;
    // Should be the amount / 10^6, which has a loss of precision
    assert(local_amount_to_remote_amount(amount, local_decimals, remote_decimals) == U256::from((0, 0, 0, 112233)));
}

#[test()]
fn test_remote_amount_to_local_amount() {
    // Equal to 112233445566778899000000000,
    // or 112233445.566778899000000000 when 18 decimals
    let amount = U256::from((0, 0, 0, 112233445566778899)) * U256::from((0, 0, 0, 1000000000));
    // 18 to 9 decimals
    let remote_decimals = 18;
    let local_decimals = 9;

    // Should be the amount / 10^9
    assert(remote_amount_to_local_amount(amount, remote_decimals, local_decimals) == 112233445566778899);

    // 18 to 6 decimals while we're at it to show a loss of precision
    let remote_decimals = 18;
    let local_decimals = 6;
    // Should be the amount / 10^12
    assert(remote_amount_to_local_amount(amount, remote_decimals, local_decimals) == 112233445566778);

    // Now with a lower amount that won't overflow on us
    let amount = U256::from((0, 0, 0, 112233445566));

    // 18 to 18 decimals
    let remote_decimals = 18;
    let local_decimals = 18;
    // Should be the amount without change
    assert(remote_amount_to_local_amount(amount, remote_decimals, local_decimals) == 112233445566);

    // 18 to 24 decimals
    let remote_decimals = 18;
    let local_decimals = 24;
    // Should be the amount * 10^6
    assert(remote_amount_to_local_amount(amount, remote_decimals, local_decimals) == 112233445566000000);
}

#[test(should_revert)]
fn test_remote_amount_to_local_amount_reverts_on_overflow() {
    // Equal to 112233445566778899000000000,
    // or 112233445.566778899000000000 when 18 decimals
    let amount = U256::from((0, 0, 0, 112233445566778899)) * U256::from((0, 0, 0, 1000000000));

    // 18 to 18 decimals
    let remote_decimals = 18;
    let local_decimals = 18;
    // This should overflow, because amount > std::u64::MAX
    // And this should revert
    remote_amount_to_local_amount(amount, remote_decimals, local_decimals);
}
