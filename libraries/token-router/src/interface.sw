library;

abi TokenRouter {
    #[storage(read, write)]
    #[payable]
    fn transfer_remote(destination: u32, recipient: b256) -> b256;

    #[storage(read)]
    #[payable]
    fn pay_for_gas(message_id: b256, destination: u32);
}
