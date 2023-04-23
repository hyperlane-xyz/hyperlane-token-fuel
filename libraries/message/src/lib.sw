library;

use std::{bytes::Bytes, u256::U256};

use std_lib_extended::bytes::*;

pub struct Message {
    recipient: b256,
    amount: U256,
    metadata: Option<Bytes>,
}

/// A heap-allocated tightly packed Hyperlane message.
/// Byte layout:
///   recipient:   [0:32]
///   amount:      [32:64]
///   metadata:    [64:??]
///
/// TODO add link to reference implementation
pub struct EncodedMessage {
    bytes: Bytes,
}

const RECIPIENT_BYTE_OFFSET: u64 = 0;
const AMOUNT_BYTE_OFFSET: u64 = 32;
const METADATA_BYTE_OFFSET: u64 = 64;

impl EncodedMessage {
    pub fn new(recipient: b256, amount: U256, metadata: Option<Bytes>) -> Self {
        let metadata_len = match metadata {
            Option::Some(m) => m.len(),
            Option::None => 0u64,
        };
        let len = METADATA_BYTE_OFFSET + metadata_len;

        let mut bytes = Bytes::with_length(len);

        let _ = bytes.write_b256(RECIPIENT_BYTE_OFFSET, recipient);
        let _ = bytes.write_u256(AMOUNT_BYTE_OFFSET, amount);
        if metadata_len > 0 {
            let _ = bytes.write_bytes(METADATA_BYTE_OFFSET, metadata.unwrap());
        }

        Self { bytes }
    }

    pub fn recipient(self) -> b256 {
        self.bytes.read_b256(RECIPIENT_BYTE_OFFSET)
    }

    pub fn amount(self) -> U256 {
        self.bytes.read_u256(AMOUNT_BYTE_OFFSET)
    }

    pub fn metadata(self) -> Option<Bytes> {
        let metadata_len = self.bytes.len() - METADATA_BYTE_OFFSET;
        if metadata_len > 0 {
            return Option::Some(self.bytes.read_bytes(AMOUNT_BYTE_OFFSET, metadata_len));
        }
        Option::None
    }
}

impl From<Message> for EncodedMessage {
    fn from(message: Message) -> Self {
        EncodedMessage::new(message.recipient, message.amount, message.metadata)
    }

    fn into(self) -> Message {
        Message {
            recipient: self.recipient(),
            amount: self.amount(),
            metadata: self.metadata(),
        }
    }
}
