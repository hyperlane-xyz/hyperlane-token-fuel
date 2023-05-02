use fuels::{
    prelude::*,
    programs::contract::ContractCallHandler,
    tx::ContractId,
    types::{
        traits::{Parameterize, Tokenizable},
        Bits256,
    },
};
use std::{cmp::PartialEq, fmt::Debug};

use test_utils::get_revert_string;

// Load abi from json
abigen!(Contract(
    name = "HyperlaneConnectionClientTest",
    abi = "tests/hyperlane-connection-client-test/out/debug/hyperlane-connection-client-test-abi.json"
));

const TEST_MAILBOX: &str = "0xcafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe";
const TEST_IGP: &str = "0xfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeed";
const TEST_ISM: &str = "0xdeeddeeddeeddeeddeeddeeddeeddeeddeeddeeddeeddeeddeeddeeddeeddeed";

async fn get_contract_instance() -> (HyperlaneConnectionClientTest<WalletUnlocked>, ContractId) {
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
        "./out/debug/hyperlane-connection-client-test.bin",
        LoadConfiguration::default().set_storage_configuration(
            StorageConfiguration::load_from(
                "./out/debug/hyperlane-connection-client-test-storage_slots.json",
            )
            .unwrap(),
        ),
    )
    .unwrap()
    .deploy(&wallet, TxParameters::default())
    .await
    .unwrap();

    let instance = HyperlaneConnectionClientTest::new(id.clone(), wallet);

    (instance, id.into())
}

fn mailbox_bits256() -> Bits256 {
    Bits256::from_hex_str(TEST_MAILBOX).unwrap()
}

fn igp_bits256() -> Bits256 {
    Bits256::from_hex_str(TEST_IGP).unwrap()
}

fn ism_bits256() -> Bits256 {
    Bits256::from_hex_str(TEST_ISM).unwrap()
}

async fn test_reverts<T: Account, D: Tokenizable + Debug>(
    call_handler: ContractCallHandler<T, D>,
    revert_msg: &str,
) {
    let call = call_handler.simulate().await;
    assert!(call.is_err());
    assert_eq!(get_revert_string(call.err().unwrap()), revert_msg);
}

async fn test_setter<
    SetterT: Account,
    SetterD: Tokenizable + Debug,
    GetterT: Account,
    GetterD: Tokenizable + PartialEq<V> + Debug,
    V: Debug,
    Event: Tokenizable + Parameterize + PartialEq + Debug + 'static,
>(
    setter_handler: ContractCallHandler<SetterT, SetterD>,
    getter_handler: ContractCallHandler<GetterT, GetterD>,
    new_value: V,
    expected_event: Event,
) {
    let call = setter_handler.call().await.unwrap();

    let events = call.decode_logs_with_type::<Event>().unwrap();
    assert_eq!(events, vec![expected_event],);

    let value = getter_handler.simulate().await.unwrap().value;
    assert_eq!(value, new_value);
}

// ============== initialize ==============

#[tokio::test]
async fn test_initialize() {
    let (instance, _id) = get_contract_instance().await;

    let mailbox = mailbox_bits256();
    let igp = igp_bits256();
    let ism = ism_bits256();

    instance
        .methods()
        .initialize(mailbox, igp, ism)
        .call()
        .await
        .unwrap();

    let value = instance.methods().mailbox().simulate().await.unwrap().value;
    assert_eq!(value, mailbox);

    let value = instance
        .methods()
        .interchain_gas_paymaster()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(value, igp);

    let value = instance
        .methods()
        .interchain_security_module()
        .simulate()
        .await
        .unwrap()
        .value;
    assert_eq!(value, ism);
}

async fn assert_initialize_reverts(
    instance: &HyperlaneConnectionClientTest<WalletUnlocked>,
    mailbox: Bits256,
    igp: Bits256,
    ism: Bits256,
) {
    let call = instance
        .methods()
        .initialize(mailbox, igp, ism)
        .call()
        .await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "hyperlane connection client already initialized",
    );
}

#[tokio::test]
async fn test_initialize_reverts_if_called_twice() {
    let (instance, _id) = get_contract_instance().await;

    let mailbox = mailbox_bits256();
    let igp = igp_bits256();
    let ism = ism_bits256();

    instance
        .methods()
        .initialize(mailbox, igp, ism)
        .call()
        .await
        .unwrap();

    assert_initialize_reverts(&instance, mailbox, igp, ism).await;
}

#[tokio::test]
async fn test_initialize_reverts_if_any_id_is_already_set() {
    let mailbox = mailbox_bits256();
    let igp = igp_bits256();
    let ism = ism_bits256();

    // When only mailbox is set
    let (instance, _id) = get_contract_instance().await;
    instance
        .methods()
        .set_mailbox(mailbox)
        .call()
        .await
        .unwrap();
    assert_initialize_reverts(&instance, mailbox, igp, ism).await;

    // When only IGP is set
    let (instance, _id) = get_contract_instance().await;
    instance
        .methods()
        .set_interchain_gas_paymaster(igp)
        .call()
        .await
        .unwrap();
    assert_initialize_reverts(&instance, mailbox, igp, ism).await;

    // When only ISM is set
    let (instance, _id) = get_contract_instance().await;
    instance
        .methods()
        .set_interchain_security_module(ism)
        .call()
        .await
        .unwrap();
    assert_initialize_reverts(&instance, mailbox, igp, ism).await;
}

// ============== mailbox & set_mailbox ==============

#[tokio::test]
async fn test_mailbox_reverts_if_not_set() {
    let (instance, _id) = get_contract_instance().await;
    test_reverts(instance.methods().mailbox(), "mailbox not set").await;
}

#[tokio::test]
async fn test_set_mailbox() {
    let (instance, _id) = get_contract_instance().await;

    let mailbox = mailbox_bits256();

    test_setter(
        instance.methods().set_mailbox(mailbox),
        instance.methods().mailbox(),
        mailbox,
        MailboxSetEvent { mailbox },
    )
    .await;
}

// ============== interchain_gas_paymaster & set_interchain_gas_paymaster ==============

#[tokio::test]
async fn test_interchain_gas_paymaster_reverts_if_not_set() {
    let (instance, _id) = get_contract_instance().await;

    test_reverts(instance.methods().interchain_gas_paymaster(), "IGP not set").await;
}

#[tokio::test]
async fn test_set_interchain_gas_paymaster() {
    let (instance, _id) = get_contract_instance().await;

    let igp = igp_bits256();

    test_setter(
        instance.methods().set_interchain_gas_paymaster(igp),
        instance.methods().interchain_gas_paymaster(),
        igp,
        InterchainGasPaymasterSetEvent {
            interchain_gas_paymaster: igp,
        },
    )
    .await;
}

// ============== interchain_security_module & set_interchain_security_module ==============

#[tokio::test]
async fn test_interchain_security_module_reverts_if_not_set() {
    let (instance, _id) = get_contract_instance().await;

    test_reverts(
        instance.methods().interchain_security_module(),
        "ISM not set",
    )
    .await;
}

#[tokio::test]
async fn test_set_interchain_security_module() {
    let (instance, _id) = get_contract_instance().await;

    let ism = ism_bits256();

    test_setter(
        instance.methods().set_interchain_security_module(ism),
        instance.methods().interchain_security_module(),
        ism,
        InterchainSecurityModuleSetEvent { module: ism },
    )
    .await;
}

// ============== only_mailbox ==============

#[tokio::test]
async fn test_only_mailbox_does_not_revert_if_called_by_mailbox() {
    let (instance, _id) = get_contract_instance().await;

    let wallet_id = Bits256(instance.account().address().hash().into());
    instance
        .methods()
        .set_mailbox(wallet_id)
        .call()
        .await
        .unwrap();

    let call = instance.methods().only_mailbox().simulate().await;
    assert!(call.is_ok());
}

#[tokio::test]
async fn test_only_mailbox_reverts_if_not_called_by_mailbox() {
    let (instance, _id) = get_contract_instance().await;

    instance
        .methods()
        .set_mailbox(mailbox_bits256())
        .call()
        .await
        .unwrap();

    let call = instance.methods().only_mailbox().simulate().await;
    assert!(call.is_err());
    assert_eq!(
        get_revert_string(call.err().unwrap()),
        "msg sender not mailbox",
    );
}
