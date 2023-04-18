library;

use ownership::{data_structures::State, only_owner, owner, set_ownership, transfer_ownership};

abi Ownable {
    #[storage(read)]
    fn owner() -> State;
    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity);
    #[storage(read, write)]
    fn set_ownership(new_owner: Identity);
}

impl Ownable for Contract {
    #[storage(read)]
    fn owner() -> State {
        owner()
    }

    #[storage(read, write)]
    fn transfer_ownership(new_owner: Identity) {
        transfer_ownership(new_owner)
    }

    #[storage(read, write)]
    fn set_ownership(new_owner: Identity) {
        set_ownership(new_owner)
    }
}
