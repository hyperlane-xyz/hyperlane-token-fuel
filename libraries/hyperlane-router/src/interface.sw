library;

pub struct RemoteRouterConfig {
    domain: u32,
    router: Option<b256>,
}

abi HyperlaneRouter {
    #[storage(read)]
    fn routers(domain: u32) -> Option<b256>;

    #[storage(read, write)]
    fn enroll_remote_router(domain: u32, router: Option<b256>);

    #[storage(read, write)]
    fn enroll_remote_routers(configs: Vec<RemoteRouterConfig>);
}
