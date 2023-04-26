use fuels::{
    prelude::*,
    tx::ContractId,
    types::{Bits256, Identity},
};

use hyperlane_core::{HyperlaneMessage as HyperlaneAgentMessage, H256};

use test_utils::{bits256_to_h256, get_dispatched_message, get_revert_string, h256_to_bits256};

// Load abi from json
abigen!(Contract(
    name = "HyperlaneRouterTest",
    abi = "tests/hyperlane-router-test/out/debug/hyperlane-router-test-abi.json"
));

mod mailbox_contract {
    fuels::prelude::abigen!(Contract(
        name = "MockMailbox",
        abi = "mocks/mock-mailbox/out/debug/mock-mailbox-abi.json"
    ));
}

mod igp_contract {
    // Load abi from json
    fuels::prelude::abigen!(Contract(
        name = "MockInterchainGasPaymaster",
        abi =
            "mocks/mock-interchain-gas-paymaster/out/debug/mock-interchain-gas-paymaster-abi.json"
    ));
}

use igp_contract::{MockInterchainGasPaymaster, PayForGasCalled};
use mailbox_contract::MockMailbox;

const LOCAL_DOMAIN: u32 = 0x6675656cu32;

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

    let id = Contract::load_from(
        "./out/debug/hyperlane-router-test.bin",
        LoadConfiguration::default().set_storage_configuration(StorageConfiguration::load_from(
            "./out/debug/hyperlane-router-test-storage_slots.json",
        ).unwrap()),
    )
    .unwrap()
    .deploy(&wallet, TxParameters::default())
    .await
    .unwrap();

    let instance = HyperlaneRouterTest::new(id.clone(), wallet);

    (instance, id.into())
}

async fn get_mailbox_and_igp(
    wallet: WalletUnlocked,
) -> (
    MockMailbox<WalletUnlocked>,
    MockInterchainGasPaymaster<WalletUnlocked>,
) {
    let mailbox_configurables =
        mailbox_contract::MockMailboxConfigurables::new().set_LOCAL_DOMAIN(LOCAL_DOMAIN);

    let mailbox_id = Contract::load_from(
        "../../mocks/mock-mailbox/out/debug/mock-mailbox.bin",
        LoadConfiguration::default().set_storage_configuration(StorageConfiguration::load_from(
            "../../mocks/mock-mailbox/out/debug/mock-mailbox-storage_slots.json",
        ).unwrap()).set_configurables(mailbox_configurables),
    )
    .unwrap()
    .deploy(&wallet, TxParameters::default())
    .await
    .unwrap();

    let mailbox = MockMailbox::new(mailbox_id.clone(), wallet.clone());

    let igp_id = Contract::load_from(
        "../../mocks/mock-interchain-gas-paymaster/out/debug/mock-interchain-gas-paymaster.bin",
        LoadConfiguration::default().set_storage_configuration(StorageConfiguration::load_from(
            "../../mocks/mock-interchain-gas-paymaster/out/debug/mock-interchain-gas-paymaster-storage_slots.json",
        ).unwrap()),
    )
    .unwrap()
    .deploy(&wallet, TxParameters::default())
    .await
    .unwrap();

    let igp = MockInterchainGasPaymaster::new(igp_id.clone(), wallet);

    (mailbox, igp)
}

fn router_0_bits256() -> Bits256 {
    Bits256::from_hex_str(TEST_ROUTER_0).unwrap()
}

fn router_1_bits256() -> Bits256 {
    Bits256::from_hex_str(TEST_ROUTER_1).unwrap()
}

async fn initialize_hyperlane_connection_client(
    router_test: &HyperlaneRouterTest<WalletUnlocked>,
) -> (
    MockMailbox<WalletUnlocked>,
    MockInterchainGasPaymaster<WalletUnlocked>,
) {
    let (mailbox, igp) = get_mailbox_and_igp(router_test.account().clone()).await;
    router_test
        .methods()
        .initialize_hyperlane_connection_client(
            Bits256(mailbox.id().hash().into()),
            Bits256(igp.id().hash().into()),
        )
        .call()
        .await
        .unwrap();

    (mailbox, igp)
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
        .decode_logs_with_type::<RemoteRouterEnrolledEvent>()
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
        .decode_logs_with_type::<RemoteRouterEnrolledEvent>()
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
        .decode_logs_with_type::<RemoteRouterEnrolledEvent>()
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

    let (mailbox, _) = initialize_hyperlane_connection_client(&instance).await;

    // Enroll
    let test_router = router_0_bits256();
    instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(test_router))
        .call()
        .await
        .unwrap();

    let message_body = vec![1, 2, 3, 4, 5];

    let call = instance
        .methods()
        .dispatch(TEST_DOMAIN_0, Bytes(message_body.clone()))
        .set_contract_ids(&[mailbox.contract_id().clone()])
        .call()
        .await
        .unwrap();

    let message = get_dispatched_message(&call).expect("no message found");

    // Ensure the message is to the enrolled router
    assert_eq!(
        message.id(),
        HyperlaneAgentMessage {
            version: 0u8,
            nonce: 0u32,
            origin: LOCAL_DOMAIN,
            sender: H256::from_slice(instance.id().hash().as_slice()),
            destination: TEST_DOMAIN_0,
            recipient: bits256_to_h256(test_router),
            body: message_body,
        }
        .id(),
    );
}

// ============== dispatch_with_gas ==============

#[tokio::test]
async fn test_dispatch_with_gas_reverts_if_no_router() {
    let (instance, _id) = get_contract_instance().await;

    let call = instance
        .methods()
        .dispatch_with_gas(
            TEST_DOMAIN_0,
            Bytes(vec![]),
            0,
            0,
            Identity::Address(instance.account().address().into()),
        )
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "No router enrolled for domain. Did you specify the right domain ID?"
    );
}

#[tokio::test]
async fn test_dispatch_with_gas() {
    let (instance, _id) = get_contract_instance().await;

    let (_, igp) = initialize_hyperlane_connection_client(&instance).await;

    // Enroll
    let test_router = router_0_bits256();
    instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(test_router))
        .call()
        .await
        .unwrap();

    let message_body = vec![1, 2, 3, 4, 5];

    let gas_amount = 100000;
    let payment_amount = 1;
    let refund_address = Identity::Address(instance.account().address().into());

    let call = instance
        .methods()
        .dispatch_with_gas(
            TEST_DOMAIN_0,
            Bytes(message_body.clone()),
            gas_amount,
            payment_amount,
            refund_address.clone(),
        )
        .call_params(
            CallParameters::default()
                .set_asset_id(BASE_ASSET_ID)
                .set_amount(payment_amount),
        )
        .unwrap()
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    let message = get_dispatched_message(&call).expect("no message found");

    // Ensure the message is to the enrolled router
    assert_eq!(
        message.id(),
        HyperlaneAgentMessage {
            version: 0u8,
            nonce: 0u32,
            origin: LOCAL_DOMAIN,
            sender: H256::from_slice(instance.id().hash().as_slice()),
            destination: TEST_DOMAIN_0,
            recipient: bits256_to_h256(test_router),
            body: message_body,
        }
        .id(),
    );

    // And ensure that interchain gas is paid for
    let events = igp
        .log_decoder()
        .decode_logs_with_type::<PayForGasCalled>(&call.receipts)
        .unwrap();
    assert_eq!(
        events,
        vec![PayForGasCalled {
            message_id: h256_to_bits256(message.id()),
            destination_domain: TEST_DOMAIN_0,
            gas_amount,
            refund_address,
        }]
    );
}

// ============== is_remote_router & only_remote_router ==============

#[tokio::test]
async fn test_is_remote_router_and_only_router() {
    let (instance, _id) = get_contract_instance().await;

    let router_0 = router_0_bits256();
    let router_1 = router_1_bits256();

    // No router enrolled

    let is_remote_router = instance
        .methods()
        .is_remote_router(TEST_DOMAIN_0, router_0)
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(!is_remote_router);

    let call = instance
        .methods()
        .only_remote_router(TEST_DOMAIN_0, router_0)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "provided router is not enrolled for origin domain"
    );

    // Router enrolled, but the router supplied is still incorrect

    // First enroll the router...
    instance
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(router_0))
        .call()
        .await
        .unwrap();

    let is_remote_router = instance
        .methods()
        // wrong router
        .is_remote_router(TEST_DOMAIN_0, router_1)
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(!is_remote_router);

    let call = instance
        .methods()
        .only_remote_router(TEST_DOMAIN_0, router_1)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "provided router is not enrolled for origin domain"
    );

    // And now the correct router

    let is_remote_router = instance
        .methods()
        .is_remote_router(TEST_DOMAIN_0, router_0)
        .simulate()
        .await
        .unwrap()
        .value;
    assert!(is_remote_router);

    let call = instance
        .methods()
        .only_remote_router(TEST_DOMAIN_0, router_0)
        .call()
        .await;
    assert!(call.is_ok());
}
