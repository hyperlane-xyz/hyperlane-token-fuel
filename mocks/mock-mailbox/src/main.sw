contract;

use std::{auth::msg_sender, bytes::Bytes, constants::ZERO_B256};

use hyperlane_interfaces::{DispatchIdEvent, Mailbox, MessageRecipient, ProcessEvent};
use hyperlane_message::EncodedMessage;

use std_lib_extended::{auth::msg_sender_b256, option::*};

/// The mailbox version.
const VERSION: u8 = 0;
/// The max bytes in a message body. Equal to 2 KiB, or 2 * (2 ** 10).
const MAX_MESSAGE_BODY_BYTES: u64 = 2048;
/// The log ID for dispatched messages. "hyp" in bytes
const DISPATCHED_MESSAGE_LOG_ID: u64 = 0x687970u64;

configurable {
    /// The domain of the local chain.
    /// Defaults to `fuel` (0x6675656c).
    LOCAL_DOMAIN: u32 = 0x6675656cu32,
}

// A test contract without any security or replay protection, intended
// for easy use with tests

storage {
    count: u32 = 0,
}

impl Mailbox for Contract {
    #[storage(read, write)]
    fn dispatch(
        destination_domain: u32,
        recipient: b256,
        message_body: Bytes,
    ) -> b256 {
        require(message_body.len() <= MAX_MESSAGE_BODY_BYTES, "msg too long");

        let nonce = count();
        let message = EncodedMessage::new(VERSION, nonce, LOCAL_DOMAIN, msg_sender_b256(), destination_domain, recipient, message_body);

        // Get the message's ID and insert it into the merkle tree.
        let message_id = message.id();

        // Log the entire encoded message with a log ID so it can be identified.
        message.log_with_id(DISPATCHED_MESSAGE_LOG_ID);
        // Log the dispatched message ID for easy identification.
        log(DispatchIdEvent { message_id });

        // Increment the count
        storage.count.write(nonce + 1);

        message_id
    }

    #[storage(read, write)]
    fn set_default_ism(module: ContractId) {
        require(false, "not implemented");
    }

    #[storage(read)]
    fn get_default_ism() -> ContractId {
        ContractId::from(ZERO_B256)
    }

    #[storage(read)]
    fn delivered(message_id: b256) -> bool {
        false
    }

    #[storage(read, write)]
    fn process(metadata: Bytes, _message: Bytes) {
        let message = EncodedMessage {
            bytes: _message,
        };

        process_message(message);
    }

    #[storage(read)]
    fn count() -> u32 {
        count()
    }

    #[storage(read)]
    fn root() -> b256 {
        ZERO_B256
    }

    #[storage(read)]
    fn latest_checkpoint() -> (b256, u32) {
        (ZERO_B256, 420)
    }
}

#[storage(read)]
fn count() -> u32 {
    storage.count.try_read().unwrap_or(0)
}

/// Gets the b256 representation of the msg_sender.
fn msg_sender_b256() -> b256 {
    match msg_sender().unwrap() {
        Identity::Address(address) => address.into(),
        Identity::ContractId(id) => id.into(),
    }
}

#[storage(read, write)]
fn process_message(message: EncodedMessage) {
    require(message.version() == VERSION, "!version");
    require(message.destination() == LOCAL_DOMAIN, "!destination");

    let id = message.id();

    let recipient = message.recipient();

    let msg_recipient = abi(MessageRecipient, recipient);

    let origin = message.origin();
    let sender = message.sender();

    msg_recipient.handle(origin, sender, message.body());

    log(ProcessEvent {
        message_id: id,
        origin,
        sender,
        recipient,
    });
}
