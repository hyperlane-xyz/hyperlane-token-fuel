library;

use std::{
    call_frames::contract_id,
    inputs::{
        Input,
        input_count,
        input_type,
    },
    token::{
        force_transfer_to_contract,
        mint,
        transfer_to_address,
    },
    u256::U256,
};

// TODO: adapt to changes in this interface.
// This is still a WIP standard, see https://github.com/FuelLabs/rfcs/issues/13.
abi Token {
    #[storage(read)]
    fn total_supply() -> U256;

    fn decimals() -> u8;

    fn name() -> str[64];

    fn symbol() -> str[32];
}
