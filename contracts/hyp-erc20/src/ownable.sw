library;

use hyperlane_interfaces::ownable::Ownable;
use ownership::{data_structures::State, owner, set_ownership, transfer_ownership};

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
