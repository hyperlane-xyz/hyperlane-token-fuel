use std::str::FromStr;

use fuels::{
    prelude::*,
    programs::call_response::FuelCallResponse,
    tx::ContractId,
    types::{Bits256, Identity},
};

use hyperlane_core::{
    Encode, HyperlaneMessage as HyperlaneAgentMessage, H256, U256 as HyperlaneU256,
};
use test_utils::{bits256_to_h256, get_dispatched_message, get_revert_reason, get_revert_string};

// Load abi from json
abigen!(Contract(
    name = "HypERC20",
    abi = "contracts/hyp-erc20/out/debug/hyp-erc20-abi.json"
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

use igp_contract::MockInterchainGasPaymaster;
use mailbox_contract::MockMailbox;

const LOCAL_DOMAIN: u32 = 0x6675656cu32;

const TEST_REMOTE_DOMAIN: u32 = 11111;
const TEST_REMOTE_ROUTER: &str =
    "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_REMOTE_GAS_AMOUNT: u64 = 150000;

async fn get_contract_instance() -> (HypERC20<WalletUnlocked>, ContractId) {
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
        "./out/debug/hyp-erc20.bin",
        LoadConfiguration::default().set_storage_configuration(
            StorageConfiguration::load_from("./out/debug/hyp-erc20-storage_slots.json").unwrap(),
        ),
    )
    .unwrap()
    .deploy(&wallet, TxParameters::default())
    .await
    .unwrap();

    let instance = HypERC20::new(id.clone(), wallet);

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
        LoadConfiguration::default()
            .set_storage_configuration(
                StorageConfiguration::load_from(
                    "../../mocks/mock-mailbox/out/debug/mock-mailbox-storage_slots.json",
                )
                .unwrap(),
            )
            .set_configurables(mailbox_configurables),
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

async fn initialize_and_enroll_remote_router(
    instance: &HypERC20<WalletUnlocked>,
    initial_total_supply: u64,
) -> (
    MockMailbox<WalletUnlocked>,
    MockInterchainGasPaymaster<WalletUnlocked>,
) {
    let (mailbox, igp) = get_mailbox_and_igp(instance.account().clone()).await;

    let owner = Identity::Address(instance.account().address().into());
    let mailbox_id = Bits256(mailbox.id().hash().into());
    let igp_id = Bits256(igp.id().hash().into());
    let ism_id = Bits256([0u8; 32]);

    instance
        .methods()
        .initialize(
            owner.clone(),
            mailbox_id,
            igp_id,
            ism_id,
            initial_total_supply,
        )
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    instance
        .methods()
        .enroll_remote_router(
            TEST_REMOTE_DOMAIN,
            Some(Bits256::from_hex_str(TEST_REMOTE_ROUTER).unwrap()),
        )
        .call()
        .await
        .unwrap();

    instance
        .methods()
        .set_destination_gas_configs(vec![GasRouterConfig {
            domain: TEST_REMOTE_DOMAIN,
            gas: TEST_REMOTE_GAS_AMOUNT,
        }])
        .call()
        .await
        .unwrap();

    (mailbox, igp)
}

fn get_message_body(
    recipient: Bits256,
    amount: HyperlaneU256,
    metadata: Option<Vec<u8>>,
) -> Vec<u8> {
    let mut amount_bytes: [u8; 32] = [0; 32];
    amount.to_big_endian(&mut amount_bytes);
    [
        &recipient.0,
        &amount_bytes,
        metadata.unwrap_or_default().as_slice(),
    ]
    .concat()
}

// ============== initialize ==============

#[tokio::test]
async fn test_initialize() {
    let (instance, instance_id) = get_contract_instance().await;
    let (mailbox, igp) = get_mailbox_and_igp(instance.account().clone()).await;

    let owner_wallet = instance.account();
    let owner_address = owner_wallet.address();
    let owner = Identity::Address(owner_address.into());
    let mailbox_id = Bits256(mailbox.id().hash().into());
    let igp_id = Bits256(igp.id().hash().into());
    let ism_id = Bits256([1u8; 32]);
    let initial_total_supply = 100;

    instance
        .methods()
        .initialize(
            owner.clone(),
            mailbox_id,
            igp_id,
            ism_id,
            initial_total_supply,
        )
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    let on_chain_owner = instance.methods().owner().simulate().await.unwrap().value;
    assert_eq!(on_chain_owner, State::Initialized(owner));

    let on_chain_mailbox = instance.methods().mailbox().simulate().await.unwrap().value;
    assert_eq!(on_chain_mailbox, mailbox_id);

    let on_chain_igp = instance
        .methods()
        .interchain_gas_paymaster()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(on_chain_igp, igp_id);

    let on_chain_ism = instance
        .methods()
        .interchain_security_module()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(on_chain_ism, ContractId::from(ism_id.0));

    let total_supply = instance
        .methods()
        .total_supply()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(
        total_supply,
        U256 {
            a: 0,
            b: 0,
            c: 0,
            d: initial_total_supply
        }
    );

    // Minted to the owner
    let owner_balance = instance
        .account()
        .provider()
        .unwrap()
        .get_asset_balance(owner_address, AssetId::new(instance_id.into()))
        .await
        .unwrap();
    assert_eq!(owner_balance, initial_total_supply);
}

#[tokio::test]
async fn test_initialize_reverts_when_called_twice() {
    let (instance, _id) = get_contract_instance().await;
    let (mailbox, igp) = get_mailbox_and_igp(instance.account().clone()).await;

    let owner = Identity::Address(instance.account().address().into());
    let mailbox_id = Bits256(mailbox.id().hash().into());
    let igp_id = Bits256(igp.id().hash().into());
    let ism_id = Bits256([1u8; 32]);
    let initial_total_supply = 100;

    instance
        .methods()
        .initialize(
            owner.clone(),
            mailbox_id,
            igp_id,
            ism_id,
            initial_total_supply,
        )
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    let call = instance
        .methods()
        .initialize(
            owner.clone(),
            mailbox_id,
            igp_id,
            ism_id,
            initial_total_supply,
        )
        // An output for the initial total supply transfer
        .append_variable_outputs(1)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_reason(call.err().unwrap()),
        "CannotReinitialized",
    );
}

// ============== transfer_remote ==============

#[tokio::test]
async fn test_transfer_remote() {
    // 1000 * 1e9, or 1000 "full" tokens
    let total_supply: u64 = 1000000000000;

    let (instance, instance_id) = get_contract_instance().await;
    let (_mailbox, _igp) = initialize_and_enroll_remote_router(&instance, total_supply).await;

    // 10 * 1e9, or 10 "full" tokens
    let transfer_amount: u64 = 10000000000;
    let recipient = Bits256([12u8; 32]);

    let total_supply_before = sway_u256_to_hyperlane_u256(
        instance
            .methods()
            .total_supply()
            .simulate()
            .await
            .unwrap()
            .value,
    );
    // Sanity check the total supply
    assert_eq!(total_supply_before, total_supply.into(),);

    let call = instance
        .methods()
        .transfer_remote(TEST_REMOTE_DOMAIN, recipient)
        .call_params(
            CallParameters::default()
                .set_asset_id(AssetId::new(instance_id.into()))
                .set_amount(transfer_amount),
        )
        .unwrap()
        .estimate_tx_dependencies(Some(5))
        .await
        .unwrap()
        .call()
        .await
        .unwrap();

    let message_amount =
        HyperlaneU256::from(transfer_amount) * (HyperlaneU256::from(10).pow(9.into()));
    let message = get_dispatched_message(&call).expect("no message found");
    assert_eq!(
        message.id(),
        HyperlaneAgentMessage {
            version: 0u8,
            nonce: 0u32,
            origin: LOCAL_DOMAIN,
            sender: H256::from_slice(instance.id().hash().as_slice()),
            destination: TEST_REMOTE_DOMAIN,
            recipient: H256::from_str(TEST_REMOTE_ROUTER).unwrap(),
            body: get_message_body(recipient, message_amount, None),
        }
        .id()
    );

    // Test that the message ID is returned
    assert_eq!(message.id(), bits256_to_h256(call.value));

    // Ensure that the event was logged
    let events = call
        .decode_logs_with_type::<SentTransferRemoteEvent>()
        .unwrap();
    assert_eq!(
        events,
        vec![SentTransferRemoteEvent {
            destination: TEST_REMOTE_DOMAIN,
            recipient,
            amount: hyperlane_u256_to_sway_u256(message_amount),
        }]
    );

    // Check that the tokens were burned
    let total_supply_after = sway_u256_to_hyperlane_u256(
        instance
            .methods()
            .total_supply()
            .simulate()
            .await
            .unwrap()
            .value,
    );
    assert_eq!(
        total_supply_before - total_supply_after,
        transfer_amount.into(),
    );
}

#[tokio::test]
async fn test_transfer_remote_reverts_if_wrong_asset() {
    // 1000 * 1e9, or 1000 "full" tokens
    let total_supply: u64 = 1000000000000;

    let (instance, _instance_id) = get_contract_instance().await;
    let (_mailbox, _igp) = initialize_and_enroll_remote_router(&instance, total_supply).await;

    let recipient = Bits256([12u8; 32]);

    let call = instance
        .methods()
        .transfer_remote(TEST_REMOTE_DOMAIN, recipient)
        .call_params(
            CallParameters::default()
                .set_asset_id(BASE_ASSET_ID)
                .set_amount(1),
        )
        .unwrap()
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "msg_asset_id not self",
    );
}

// ============== handle ==============

#[tokio::test]
async fn test_handle() {
    let mut total_supply = 100;
    let (instance, instance_id) = get_contract_instance().await;
    let (mailbox, _igp) = initialize_and_enroll_remote_router(&instance, total_supply).await;
    // 10 * 1e9, or 10 "full" tokens
    let transfer_amount: u64 = 10000000000;
    let message_amount =
        HyperlaneU256::from(transfer_amount) * (HyperlaneU256::from(10).pow(9.into()));

    // Vec<(recipient, is_contract)>
    let transfer_recipients = vec![
        // An address
        (Bits256([12; 32]), false),
        // TODO: support contracts
        // (Bits256(igp.id().hash().into()), true), // A contract
    ];

    for (transfer_recipient, is_contract) in transfer_recipients {
        let message = HyperlaneAgentMessage {
            version: 0u8,
            nonce: 0u32,
            origin: TEST_REMOTE_DOMAIN,
            sender: H256::from_str(TEST_REMOTE_ROUTER).unwrap(),
            destination: LOCAL_DOMAIN,
            recipient: H256::from_slice(instance_id.as_slice()),
            body: get_message_body(transfer_recipient, message_amount, None),
        };
        let encoded_message = message.to_vec();

        let call = mailbox
            .methods()
            .process(Bytes(vec![]), Bytes(encoded_message))
            .estimate_tx_dependencies(Some(10))
            .await
            .unwrap()
            .call()
            .await
            .unwrap();

        // Event was logged
        let events = instance
            .log_decoder()
            .decode_logs_with_type::<ReceivedTransferRemoteEvent>(&call.receipts)
            .unwrap();
        assert_eq!(
            events,
            vec![ReceivedTransferRemoteEvent {
                origin: TEST_REMOTE_DOMAIN,
                recipient: transfer_recipient,
                amount: hyperlane_u256_to_sway_u256(message_amount),
            }]
        );

        // Check that the tokens were minted, increasing the total supply

        // Increase the total supply in our test accounting
        total_supply += transfer_amount;
        // Get the on-chain value
        let new_total_supply = sway_u256_to_hyperlane_u256(
            instance
                .methods()
                .total_supply()
                .simulate()
                .await
                .unwrap()
                .value,
        );
        assert_eq!(new_total_supply, total_supply.into());

        // And that they were minted to the correct recipient
        let balance = if is_contract {
            instance
                .account()
                .provider()
                .unwrap()
                .get_contract_asset_balance(
                    &ContractId::new(transfer_recipient.0).into(),
                    AssetId::new(instance_id.into()),
                )
                .await
                .unwrap()
        } else {
            instance
                .account()
                .provider()
                .unwrap()
                .get_asset_balance(
                    &Address::new(transfer_recipient.0).into(),
                    AssetId::new(instance_id.into()),
                )
                .await
                .unwrap()
        };
        assert_eq!(balance, transfer_amount);
    }
}

#[tokio::test]
async fn test_handle_reverts_if_caller_not_mailbox() {
    let (instance, _instance_id) = get_contract_instance().await;
    let (_mailbox, _igp) = initialize_and_enroll_remote_router(&instance, 0).await;

    let call = instance
        .methods()
        // Params don't matter, we expect the only_mailbox check to be first
        .handle(1u32, Bits256([1; 32]), Bytes(vec![1, 2, 3]))
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "msg sender not mailbox",
    );
}

#[tokio::test]
async fn test_handle_reverts_if_message_sender_not_remote_router() {
    let (instance, instance_id) = get_contract_instance().await;
    let (mailbox, _igp) = initialize_and_enroll_remote_router(&instance, 0).await;

    let transfer_recipient = Bits256([12; 32]);
    let transfer_amount = HyperlaneU256::from(123);

    let message = HyperlaneAgentMessage {
        version: 0u8,
        nonce: 0u32,
        origin: TEST_REMOTE_DOMAIN,
        // Sender not remote router
        sender: H256::zero(),
        destination: LOCAL_DOMAIN,
        recipient: H256::from_slice(instance_id.as_slice()),
        body: get_message_body(transfer_recipient, transfer_amount, None),
    };
    let encoded_message = message.to_vec();

    let call = mailbox
        .methods()
        .process(Bytes(vec![]), Bytes(encoded_message))
        .set_contract_ids(&[instance.contract_id().clone()])
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "provided router is not enrolled for origin domain",
    );
}

// ============== hyperlane connection client setters ==============

#[tokio::test]
async fn test_hyperlane_connection_client_setters_revert_if_caller_not_owner() {
    let (instance, _instance_id) = get_contract_instance().await;
    let (_mailbox, _igp) = initialize_and_enroll_remote_router(&instance, 0).await;

    let dummy_bits256 = Bits256([69; 32]);

    // Transfer ownership to a different address
    instance
        .methods()
        .transfer_ownership(Identity::Address(Address::new([1; 32])))
        .call()
        .await
        .unwrap();

    // set_mailbox
    let call = instance.methods().set_mailbox(dummy_bits256).call().await;
    assert_not_owner_revert(call);

    // set_interchain_gas_paymaster
    let call = instance
        .methods()
        .set_interchain_gas_paymaster(dummy_bits256)
        .call()
        .await;
    assert_not_owner_revert(call);

    // set_interchain_security_module
    let call = instance
        .methods()
        .set_interchain_security_module(dummy_bits256)
        .call()
        .await;
    assert_not_owner_revert(call);
}

// ============== hyperlane router ==============

#[tokio::test]
async fn test_hyperlane_router_enrolling_reverts_if_sender_not_owner() {
    let (instance, _instance_id) = get_contract_instance().await;
    let (_mailbox, _igp) = initialize_and_enroll_remote_router(&instance, 0).await;

    let dummy_domain = 1u32;
    let dummy_bits256 = Bits256([69; 32]);

    // Transfer ownership to a different address
    instance
        .methods()
        .transfer_ownership(Identity::Address(Address::new([1; 32])))
        .call()
        .await
        .unwrap();

    // enroll_remote_router
    let call = instance
        .methods()
        .enroll_remote_router(dummy_domain, Some(dummy_bits256))
        .call()
        .await;
    assert_not_owner_revert(call);

    // enroll_remote_routers
    let call = instance
        .methods()
        .enroll_remote_routers(vec![RemoteRouterConfig {
            domain: dummy_domain,
            router: Some(dummy_bits256),
        }])
        .call()
        .await;
    assert_not_owner_revert(call);
}

// ============== hyperlane gas router ==============

#[tokio::test]
async fn test_hyperlane_gas_router_setting_reverts_if_sender_not_owner() {
    let (instance, _instance_id) = get_contract_instance().await;
    let (_mailbox, _igp) = initialize_and_enroll_remote_router(&instance, 0).await;

    let dummy_domain = 1u32;
    let dummy_gas = 1234u64;

    // Transfer ownership to a different address
    instance
        .methods()
        .transfer_ownership(Identity::Address(Address::new([1; 32])))
        .call()
        .await
        .unwrap();

    // set_destination_gas_configs
    let call = instance
        .methods()
        .set_destination_gas_configs(vec![GasRouterConfig {
            domain: dummy_domain,
            gas: dummy_gas,
        }])
        .call()
        .await;
    assert_not_owner_revert(call);
}

// utils

fn hyperlane_u256_to_sway_u256(hyp_u256: HyperlaneU256) -> U256 {
    U256 {
        a: hyp_u256.0[3],
        b: hyp_u256.0[2],
        c: hyp_u256.0[1],
        d: hyp_u256.0[0],
    }
}

fn sway_u256_to_hyperlane_u256(sway_u256: U256) -> HyperlaneU256 {
    HyperlaneU256([sway_u256.d, sway_u256.c, sway_u256.b, sway_u256.a])
}

fn assert_not_owner_revert<D>(call: Result<FuelCallResponse<D>>) {
    assert!(call.is_err());
    assert_eq!(get_revert_reason(call.err().unwrap()), "NotOwner",);
}
