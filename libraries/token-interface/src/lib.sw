library;

use std::u256::U256;

use std::call_frames::contract_id;

use std::token::{mint, force_transfer_to_contract, transfer_to_address};

use std::inputs::{
    input_count,
    input_type,
    Input,
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

// TODO - move to std_lib_extended

pub fn transfer_to_id(amount: u64, id: b256) {
    if contract_id_is_input(id) {
        force_transfer_to_contract(amount, contract_id(), ContractId::from(id));
    } else {
        transfer_to_address(amount, contract_id(), Address::from(id));
    }
}

pub const GTF_INPUT_CONTRACT_CONTRACT_ID = 0x113;

pub fn contract_id_is_input(id: b256) -> bool {
    let count = input_count();
    let mut i = 0;
    while i < count {
        if input_type(i) == Input::Contract && input_contract_id(i) == id {
            return true;
        }
        i += 1;
    }
    return false;
}

pub fn input_contract_id(index: u64) -> b256 {
    __gtf::<b256>(index, GTF_INPUT_CONTRACT_CONTRACT_ID)
}
