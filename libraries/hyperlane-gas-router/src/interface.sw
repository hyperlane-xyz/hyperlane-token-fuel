library;

/// A config for a domain and gas amount, used when setting the destination gas.
pub struct GasRouterConfig {
    domain: u32,
    gas: u64,
}

/// An external interface into the gas router.
abi HyperlaneGasRouter {
    #[storage(read, write)]
    fn set_destination_gas_configs(configs: Vec<GasRouterConfig>);

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32) -> u64;

    #[storage(read)]
    fn destination_gas(domain: u32) -> u64;
}
