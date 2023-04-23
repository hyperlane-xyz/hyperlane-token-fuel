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
    #[storage(read, write)]
    pub fn transfer_remote(
        self,
        destination: u32,
        recipient: b256,
        amount_or_id: U256,
        metadata: Option<Bytes>,
) -> b256 {
        let gas_router: GasRouterStorageKeys = self;
        let id = gas_router.dispatch_with_gas(destination, EncodedMessage::new(recipient, amount_or_id, metadata).bytes, msg_amount(), msg_sender().unwrap());
        log(SentTransferRemoteEvent {
            destination,
            recipient,
            amount: amount_or_id,
        });
        id
    }

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

pub fn local_amount_to_remote_amount(amount: u64, local_decimals: u8, remote_decimals: u8) -> U256 {
    let amount = U256::from((0, 0, 0, amount));
    convert_decimals(amount, local_decimals, remote_decimals)
}

pub fn remote_amount_to_local_amount(amount: U256, remote_decimals: u8, local_decimals: u8) -> u64 {
    let amount = convert_decimals(amount, remote_decimals, local_decimals);
    amount.as_u64().expect("remote to local amount conversion overflow")
}

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
