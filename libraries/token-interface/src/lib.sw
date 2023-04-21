library;

use std::u256::U256;

// TODO: adapt to changes in this interface.
// This is still a WIP standard, see https://github.com/FuelLabs/rfcs/issues/13.
abi Token {
    #[storage(read)]
    fn total_supply() -> U256;

    fn decimals() -> u8;

    fn name() -> str[64];

    fn symbol() -> str[32];
}
