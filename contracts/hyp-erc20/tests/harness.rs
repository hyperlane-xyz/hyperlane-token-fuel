use std::str::FromStr;

use fuels::{prelude::*, tx::ContractId, types::{Bits256, Identity}};

use hyperlane_core::{HyperlaneMessage as HyperlaneAgentMessage, H256, U256 as HyperlaneU256};
use test_utils::{get_revert_reason, get_dispatched_message};

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

use igp_contract::{MockInterchainGasPaymaster, PayForGasCalled, QuoteGasPaymentCalled};
use mailbox_contract::MockMailbox;

const LOCAL_DOMAIN: u32 = 0x6675656cu32;

const TEST_REMOTE_DOMAIN: u32 = 11111;
const TEST_REMOTE_ROUTER: &str = "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
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

    let id = Contract::deploy(
        "./out/debug/hyp-erc20.bin",
        &wallet,
        DeployConfiguration::default(),
    )
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
    let mailbox_id = Contract::deploy(
        "../../mocks/mock-mailbox/out/debug/mock-mailbox.bin",
        &wallet,
        DeployConfiguration::default().set_configurables(mailbox_configurables),
    )
    .await
    .unwrap();

    let mailbox = MockMailbox::new(mailbox_id.clone(), wallet.clone());

    let igp_id = Contract::deploy(
        "../../mocks/mock-interchain-gas-paymaster/out/debug/mock-interchain-gas-paymaster.bin",
        &wallet,
        DeployConfiguration::default(),
    )
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
        .call()
        .await
        .unwrap();

    instance
        .methods()
        .enroll_remote_router(TEST_REMOTE_DOMAIN, Some(Bits256::from_hex_str(TEST_REMOTE_ROUTER).unwrap()))
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

fn get_message_body(recipient: Bits256, amount: HyperlaneU256, metadata: Option<Vec<u8>>) -> Vec<u8> {
    let mut amount_bytes: [u8; 32] = [0; 32];
    amount.to_little_endian(&mut amount_bytes);
    [
        &recipient.0,
        &amount_bytes,
        metadata.unwrap_or_default().as_slice(),
    ].concat()
}

// ============== initialize ==============

#[tokio::test]
async fn test_initialize() {
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
        .call()
        .await
        .unwrap();

    let on_chain_owner = instance.methods().owner().simulate().await.unwrap().value;
    assert_eq!(on_chain_owner, State::Initialized(owner));

    let on_chain_mailbox = instance.methods().mailbox().simulate().await.unwrap().value;
    assert_eq!(on_chain_mailbox, mailbox_id);

    let on_chain_igp = instance.methods().interchain_gas_paymaster().simulate().await.unwrap().value;
    assert_eq!(on_chain_igp, igp_id);

    let on_chain_ism = instance.methods().interchain_security_module().simulate().await.unwrap().value;
    assert_eq!(on_chain_ism, ContractId::from(ism_id.0));

    let total_supply = instance.methods().total_supply().simulate().await.unwrap().value;
    assert_eq!(total_supply, U256 {
        a: 0, b: 0, c: 0, d: initial_total_supply
    });
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
            initial_total_supply
        )
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

    let call = instance
        .methods()
        .transfer_remote(
            TEST_REMOTE_DOMAIN,
            recipient,
        )
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

    let message_amount = HyperlaneU256::from(transfer_amount) * (HyperlaneU256::from(10).pow(9.into()));
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
        }.id()
    )
}
