use fuels::{
    prelude::*,
    tx::ContractId,
    types::{Bits256, Identity},
};

use hyperlane_core::{HyperlaneMessage as HyperlaneAgentMessage, H256};
use test_utils::{bits256_to_h256, get_dispatched_message, h256_to_bits256};

// Load abi from json
abigen!(Contract(
    name = "HyperlaneGasRouterTest",
    abi = "tests/hyperlane-gas-router-test/out/debug/hyperlane-gas-router-test-abi.json"
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

use igp_contract::{MockInterchainGasPaymaster, PayForGasCalled, QuoteGasPaymentCalled};
use mailbox_contract::MockMailbox;

const LOCAL_DOMAIN: u32 = 0x6675656cu32;

const TEST_DOMAIN_0: u32 = 11111;
const TEST_ROUTER_0: &str = "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_DOMAIN_1: u32 = 22222;

async fn get_contract_instance() -> (HyperlaneGasRouterTest<WalletUnlocked>, ContractId) {
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
        "./out/debug/hyperlane-gas-router-test.bin",
        LoadConfiguration::default().set_storage_configuration(StorageConfiguration::load_from(
            "./out/debug/hyperlane-gas-router-test-storage_slots.json",
        ).unwrap()),
    )
    .unwrap()
    .deploy(&wallet, TxParameters::default())
    .await
    .unwrap();

    let instance = HyperlaneGasRouterTest::new(id.clone(), wallet);

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

async fn initialize_hyperlane_connection_client(
    gas_router_test: &HyperlaneGasRouterTest<WalletUnlocked>,
) -> (
    MockMailbox<WalletUnlocked>,
    MockInterchainGasPaymaster<WalletUnlocked>,
) {
    let (mailbox, igp) = get_mailbox_and_igp(gas_router_test.account().clone()).await;
    gas_router_test
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

async fn enroll_remote_router_0_with_gas_amount(
    gas_router_test: &HyperlaneGasRouterTest<WalletUnlocked>,
    router: Bits256,
    gas_amount: u64,
) {
    gas_router_test
        .methods()
        .enroll_remote_router(TEST_DOMAIN_0, Some(router))
        .call()
        .await
        .unwrap();

    gas_router_test
        .methods()
        .set_destination_gas_configs(vec![GasRouterConfig {
            domain: TEST_DOMAIN_0,
            gas: gas_amount,
        }])
        .call()
        .await
        .unwrap();
}

// ============== destination_gas, set_destination_gas_configs ==============

#[tokio::test]
async fn test_destination_gas_configs() {
    let (instance, _id) = get_contract_instance().await;

    let configs = vec![
        GasRouterConfig {
            domain: TEST_DOMAIN_0,
            gas: 100000,
        },
        GasRouterConfig {
            domain: TEST_DOMAIN_1,
            gas: 150000,
        },
    ];

    // Initially, expect the gas to be 0
    for config in configs.iter() {
        assert_eq!(
            instance
                .methods()
                .destination_gas(config.domain)
                .simulate()
                .await
                .unwrap()
                .value,
            0
        );
    }

    // Now set the gas configs
    let call = instance
        .methods()
        .set_destination_gas_configs(configs.clone())
        .call()
        .await
        .unwrap();

    // Confirm the events were logged
    let events = call.decode_logs_with_type::<DestinationGasSetEvent>().unwrap();
    assert_eq!(
        events,
        configs
            .iter()
            .map(|c| DestinationGasSetEvent {
                domain: c.domain,
                gas: c.gas,
            })
            .collect::<Vec<_>>(),
    );

    // And that the new gas amounts are set
    for config in configs.iter() {
        assert_eq!(
            instance
                .methods()
                .destination_gas(config.domain)
                .simulate()
                .await
                .unwrap()
                .value,
            config.gas
        );
    }
}

// ============== dispatch_with_gas ==============

#[tokio::test]
async fn test_dispatch_with_gas() {
    let (instance, _id) = get_contract_instance().await;
    let (_, igp) = initialize_hyperlane_connection_client(&instance).await;

    let gas_amount = 100000;
    let gas_payment = 1;
    let refund_address = Identity::Address(instance.account().address().into());

    let test_router = router_0_bits256();

    // Enroll the remote router and set gas amount
    enroll_remote_router_0_with_gas_amount(&instance, test_router, gas_amount).await;

    let message_body = vec![1, 2, 3, 4, 5];

    let call = instance
        .methods()
        .dispatch_with_gas(
            TEST_DOMAIN_0,
            Bytes(message_body.clone()),
            gas_payment,
            refund_address.clone(),
        )
        .call_params(
            CallParameters::default()
                .set_asset_id(BASE_ASSET_ID)
                .set_amount(gas_payment),
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

// ============== quote_gas_payment ==============

#[tokio::test]
async fn test_quote_gas_payment() {
    let (instance, _id) = get_contract_instance().await;
    let (_, igp) = initialize_hyperlane_connection_client(&instance).await;

    let gas_amount = 100000;

    let test_router = router_0_bits256();

    // Enroll the remote router and set gas amount
    enroll_remote_router_0_with_gas_amount(&instance, test_router, gas_amount).await;

    let call = instance
        .methods()
        .quote_gas_payment(TEST_DOMAIN_0)
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .simulate()
        .await
        .unwrap();
    let events = igp
        .log_decoder()
        .decode_logs_with_type::<QuoteGasPaymentCalled>(&call.receipts)
        .unwrap();
    assert_eq!(
        events,
        vec![QuoteGasPaymentCalled {
            destination_domain: TEST_DOMAIN_0,
            gas_amount,
        }]
    );
}

#[tokio::test]
async fn test_code_size() {
    let (instance, _id) = get_contract_instance().await;

    let (_, igp) = initialize_hyperlane_connection_client(&instance).await;

    let call = instance
        .methods()
        .code_size(Bits256(igp.id().hash().into()))
        // .code_size(Bits256([1u8; 32]))
        // .set_contract_ids(&[ContractId::new([1u8; 32]).into()])
        // .set_contract_ids(&[igp.id()])
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .simulate()
        .await;

    println!("call {:?}", call);

    assert!(call.is_ok());
    println!("call.unwrap().value {:?}", call.unwrap().value);

    // let code_size = call.get_return_value().unwrap().value;
    // assert!(code_size > 0);

    // assert!(false);
}
