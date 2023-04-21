library;

pub struct GasRouterConfig {
    domain: u32,
    gas: u64,
}

abi HyperlaneGasRouter {
    #[storage(read, write)]
    fn set_destination_gas_configs(configs: Vec<GasRouterConfig>);

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32) -> u64;

    #[storage(read)]
    fn destination_gas(domain: u32) -> u64;
}
