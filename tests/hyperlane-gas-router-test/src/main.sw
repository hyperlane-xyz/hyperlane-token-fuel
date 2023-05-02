contract;

use std::{bytes::Bytes, constants::ZERO_B256};

use std::call_frames::contract_id;

use std::token::{force_transfer_to_contract, mint, transfer_to_address};

use std::inputs::{Input, input_count, input_type};

use hyperlane_connection_client::initialize;
use hyperlane_gas_router::{GasRouterStorageKeys, interface::{GasRouterConfig, HyperlaneGasRouter}};

use hyperlane_router::{interface::{HyperlaneRouter, RemoteRouterConfig}, Routers};

storage {
    routers: Routers = Routers {},
    destination_gas: StorageMap<u32, u64> = StorageMap {},
}

abi HyperlaneGasRouterTest {
    #[storage(read, write)]
    fn initialize_hyperlane_connection_client(mailbox: b256, igp: b256);

    #[storage(read, write)]
    #[payable]
    fn dispatch_with_gas(destination_domain: u32, message_body: Bytes, gas_payment: u64, gas_payment_refund_address: Identity);

    #[storage(read, write)]
    fn code_size(id: b256) -> bool;
}

impl HyperlaneGasRouterTest for Contract {
    #[storage(read, write)]
    fn initialize_hyperlane_connection_client(mailbox: b256, igp: b256) {
        initialize(mailbox, igp, ZERO_B256);
    }

    #[storage(read, write)]
    #[payable]
    fn dispatch_with_gas(
        destination_domain: u32,
        message_body: Bytes,
        gas_payment: u64,
        gas_payment_refund_address: Identity,
    ) {
        gas_router_storage_keys().dispatch_with_gas(destination_domain, message_body, gas_payment, gas_payment_refund_address);
    }

    #[storage(read, write)]
    fn code_size(id: b256) -> bool {
        // asm(code_size, id: id) {
        //     csiz code_size id;
        //     code_size: u64
        // }
        mint(1000);
        transfer_regardless(1000, id);

        // force_transfer_to_contract(1000, contract_id(), ContractId::from(id));

        // if contract_id_is_input(id) {
        //     let code_size = asm(code_size, id: id) {
        //         csiz code_size id;
        //         code_size: u64
        //     };
        //     return code_size > 0;
        // }
        // let code_size = asm(code_size, id: id) {
        //     csiz code_size id;
        //     code_size: u64
        // };
        // code_size > 0
        false
    }
}

impl HyperlaneGasRouter for Contract {
    #[storage(read, write)]
    fn set_destination_gas_configs(configs: Vec<GasRouterConfig>) {
        gas_router_storage_keys().set_destination_gas_configs(configs);
    }

    #[storage(read)]
    fn quote_gas_payment(destination_domain: u32) -> u64 {
        gas_router_storage_keys().quote_gas_payment(destination_domain)
    }

    #[storage(read)]
    fn destination_gas(domain: u32) -> u64 {
        gas_router_storage_keys().destination_gas(domain)
    }
}

impl HyperlaneRouter for Contract {
    #[storage(read)]
    fn routers(domain: u32) -> Option<b256> {
        storage.routers.routers(domain)
    }

    #[storage(read, write)]
    fn enroll_remote_router(domain: u32, router: Option<b256>) {
        storage.routers.enroll_remote_router(domain, router);
    }

    #[storage(read, write)]
    fn enroll_remote_routers(configs: Vec<RemoteRouterConfig>) {
        storage.routers.enroll_remote_routers(configs);
    }
}

fn gas_router_storage_keys() -> GasRouterStorageKeys {
    GasRouterStorageKeys {
        routers: storage.routers,
        destination_gas: storage.destination_gas,
    }
}

pub fn transfer_regardless(amount: u64, to: b256) {
    if contract_id_is_input(to) {
        force_transfer_to_contract(amount, contract_id(), ContractId::from(to));
    } else {
        transfer_to_address(amount, contract_id(), Address::from(to));
    }
}

pub const GTF_INPUT_CONTRACT_CONTRACT_ID = 0x113;

pub fn contract_id_is_input(id: b256) -> bool {
    let count = input_count();
    let mut i = 0;
    while i < count {
        if input_type(i) == Input::Contract
            && input_contract_id(i) == id
        {
            return true;
        }
        i += 1;
    }
    return false;
}

pub fn input_contract_id(index: u64) -> b256 {
    __gtf::<b256>(index, GTF_INPUT_CONTRACT_CONTRACT_ID)
}
