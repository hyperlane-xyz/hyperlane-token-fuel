use fuels::{prelude::*, tx::ContractId, types::Bits256};

use test_utils::get_revert_string;

// Load abi from json
abigen!(Contract(
    name = "HyperlaneRouterTest",
    abi = "tests/hyperlane-router-test/out/debug/hyperlane-router-test-abi.json"
));

const TEST_DOMAIN_0: u32 = 11111;
const TEST_ROUTER_0: &str = "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_DOMAIN_1: u32 = 22222;
const TEST_ROUTER_1: &str = "0xfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeed";

async fn get_contract_instance() -> (HyperlaneRouterTest<WalletUnlocked>, ContractId) {
    // Launch a local network and deploy the contract
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(1),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await;
    let wallet = wallets.pop().unwrap();

    let id = Contract::deploy(
        "./out/debug/hyperlane-router-test.bin",
        &wallet,
        DeployConfiguration::default(),
    )
    .await
    .unwrap();

    let instance = HyperlaneRouterTest::new(id.clone(), wallet);

    (instance, id.into())
}

fn router_0_bits256() -> Bits256 {
    Bits256::from_hex_str(TEST_ROUTER_0).unwrap()
}

fn router_1_bits256() -> Bits256 {
    Bits256::from_hex_str(TEST_ROUTER_1).unwrap()
}

// ============== routers, enroll_remote_router, and enroll_remote_routers ==============

#[tokio::test]
async fn test_enroll_remote_router() {
    let (instance, _id) = get_contract_instance().await;

    // Initially the router is None
    let on_chain_router = instance
        .methods()
        .routers(TEST_DOMAIN_0)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(on_chain_router, None);

    let test_router = router_0_bits256();

    // Now enroll
    let call = instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(test_router))
        .call()
        .await
        .unwrap();

    // Event is logged
    let events = call
        .get_logs_with_type::<RemoteRouterEnrolledEvent>()
        .unwrap();
    assert_eq!(
        events,
        vec![RemoteRouterEnrolledEvent {
            domain: TEST_DOMAIN_0,
            router: Some(test_router),
        }],
    );

    // And now the router is set on chain
    let on_chain_router = instance
        .methods()
        .routers(TEST_DOMAIN_0)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(on_chain_router, Some(test_router));

    // And now let's try setting it back to None

    let call = instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, None)
        .call()
        .await
        .unwrap();
    // Event is logged
    let events = call
        .get_logs_with_type::<RemoteRouterEnrolledEvent>()
        .unwrap();
    assert_eq!(
        events,
        vec![RemoteRouterEnrolledEvent {
            domain: TEST_DOMAIN_0,
            router: None,
        }],
    );
    // And now the router is set on chain
    let on_chain_router = instance
        .methods()
        .routers(TEST_DOMAIN_0)
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(on_chain_router, None);
}

#[tokio::test]
async fn test_enroll_remote_routers() {
    let (instance, _id) = get_contract_instance().await;

    let configs = vec![
        RemoteRouterConfig {
            domain: TEST_DOMAIN_0,
            router: Some(router_0_bits256()),
        },
        RemoteRouterConfig {
            domain: TEST_DOMAIN_1,
            router: Some(router_1_bits256()),
        },
    ];

    // Initially the routers are all None
    for config in configs.iter() {
        let on_chain_router = instance
            .methods()
            .routers(config.domain)
            .simulate()
            .await
            .unwrap()
            .value;
        assert_eq!(on_chain_router, None);
    }

    // Now enroll
    let call = instance
        .methods()
        .enroll_remote_routers(configs.clone())
        .call()
        .await
        .unwrap();

    // Events are logged
    let events = call
        .get_logs_with_type::<RemoteRouterEnrolledEvent>()
        .unwrap();
    assert_eq!(
        events,
        configs
            .iter()
            .map(|c| RemoteRouterEnrolledEvent {
                domain: c.domain,
                router: c.router
            })
            .collect::<Vec<_>>(),
    );

    // And now the routers are all set on chain
    for config in configs.iter() {
        let on_chain_router = instance
            .methods()
            .routers(config.domain)
            .simulate()
            .await
            .unwrap()
            .value;
        assert_eq!(on_chain_router, config.router);
    }
}

// ============== is_remote_router ==============

#[tokio::test]
async fn test_is_remote_router() {
    let (instance, _id) = get_contract_instance().await;

    let test_router = router_0_bits256();

    // When the router isn't set, expect false

    let is_remote_router = instance
        .methods()
        .is_remote_router(TEST_DOMAIN_0, test_router)
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(!is_remote_router);

    // Now enroll
    instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(test_router))
        .call()
        .await
        .unwrap();

    // Now expect true
    let is_remote_router = instance
        .methods()
        .is_remote_router(TEST_DOMAIN_0, test_router)
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(is_remote_router);
}

// ============== only_remote_router ==============

#[tokio::test]
async fn test_only_remote_router() {
    let (instance, _id) = get_contract_instance().await;

    let test_router = router_0_bits256();

    // When the router isn't set, expect revert

    let call = instance
        .methods()
        .only_remote_router(TEST_DOMAIN_0, test_router)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "provided router is not enrolled for origin domain"
    );

    // Now enroll
    instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(test_router))
        .call()
        .await
        .unwrap();

    // Now expect no revert
    let call = instance
        .methods()
        .only_remote_router(TEST_DOMAIN_0, test_router)
        .call()
        .await;
    assert!(call.is_ok());

    // But try another router and expect revert
    let call = instance
        .methods()
        .only_remote_router(TEST_DOMAIN_0, router_1_bits256())
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "provided router is not enrolled for origin domain"
    );
}

// ============== dispatch ==============

#[tokio::test]
async fn test_dispatch_reverts_if_no_router() {
    let (instance, _id) = get_contract_instance().await;

    let call = instance
        .methods()
        .dispatch(TEST_DOMAIN_0, Bytes(vec![]))
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "No router enrolled for domain. Did you specify the right domain ID?"
    );
}

#[tokio::test]
async fn test_dispatch() {
    let (instance, _id) = get_contract_instance().await;

    // Enroll
    let test_router = router_0_bits256();
    instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(test_router))
        .call()
        .await
        .unwrap();

    // let call = instance.methods().dispatch(TEST_DOMAIN_0, Bytes(vec![])).call().await;
    // assert!(call.is_err());
    // assert_eq!(get_revert_string(call.err().unwrap()), "No router enrolled for domain. Did you specify the right domain ID?");
}
