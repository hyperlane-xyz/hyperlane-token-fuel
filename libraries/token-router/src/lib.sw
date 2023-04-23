library;

use std::{auth::msg_sender, bytes::Bytes, context::msg_amount, u256::U256};

use hyperlane_gas_router::GasRouterStorageKeys;
use message::{EncodedMessage, Message};

type TokenRouter = GasRouterStorageKeys;

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

impl TokenRouter {
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
    pub fn handle(origin: u32, _sender: b256, message_bytes: Bytes) -> Message {
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
