library;

abi TokenRouter {
    #[storage(read, write)]
    #[payable]
    fn transfer_remote(destination: u32, recipient: b256, amount: u64) -> b256;
}
