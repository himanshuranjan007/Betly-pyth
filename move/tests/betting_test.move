#[test_only]
module orion_betting::betting_test {
    use std::signer;
    use std::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::account;
    use orion_betting::betting;

    #[test(admin = @0x123, user1 = @0x456, user2 = @0x789, treasury = @0xabc, aptos_framework = @0x1)]
    public entry fun test_full_betting_flow(
        admin: signer,
        user1: signer,
        user2: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);
        let treasury_addr = signer::address_of(&treasury);

        // Create accounts
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        account::create_account_for_test(user2_addr);
        account::create_account_for_test(treasury_addr);

        // Initialize AptosCoin
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);

        // Mint coins for testing
        coin::deposit(admin_addr, coin::mint(1000000000, &mint_cap)); // 10 APT
        coin::deposit(user1_addr, coin::mint(1000000000, &mint_cap)); // 10 APT
        coin::deposit(user2_addr, coin::mint(1000000000, &mint_cap)); // 10 APT

        // Initialize betting contract
        betting::init(&admin, 200, treasury_addr); // 2% fee

        // Start a round
        let start_price = 1000000; // $1.00
        betting::start_round(&admin, start_price, 300); // 5 minutes

        // Place bets
        betting::place_bet(&user1, admin_addr, 1, true, 100000000); // 1 APT on UP
        betting::place_bet(&user2, admin_addr, 1, false, 200000000); // 2 APT on DOWN

        // Fast forward time
        timestamp::fast_forward_seconds(301);

        // Settle round (UP wins)
        let end_price = 1100000; // $1.10
        betting::settle(&admin, 1, end_price);

        // Check round data
        let (id, start_p, end_p, expiry, settled, up_pool, down_pool) = 
            betting::get_round(admin_addr, 1);
        
        assert!(id == 1, 0);
        assert!(start_p == start_price, 1);
        assert!(end_p == end_price, 2);
        assert!(settled == true, 3);
        assert!(up_pool == 100000000, 4);
        assert!(down_pool == 200000000, 5);

        // User1 should be able to claim winnings
        let user1_balance_before = coin::balance<AptosCoin>(user1_addr);
        betting::claim(&user1, admin_addr, 1);
        let user1_balance_after = coin::balance<AptosCoin>(user1_addr);
        
        // User1 should get their share of the pool minus fees
        assert!(user1_balance_after > user1_balance_before, 6);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(admin = @0x123, user1 = @0x456, treasury = @0xabc, aptos_framework = @0x1)]
    public entry fun test_tie_case(
        admin: signer,
        user1: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let user1_addr = signer::address_of(&user1);
        let treasury_addr = signer::address_of(&treasury);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        account::create_account_for_test(treasury_addr);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        coin::deposit(admin_addr, coin::mint(1000000000, &mint_cap));
        coin::deposit(user1_addr, coin::mint(1000000000, &mint_cap));

        betting::init(&admin, 200, treasury_addr);
        
        let start_price = 1000000;
        betting::start_round(&admin, start_price, 300);
        
        let bet_amount = 100000000;
        betting::place_bet(&user1, admin_addr, 1, true, bet_amount);

        timestamp::fast_forward_seconds(301);

        // Settle with same price (tie)
        betting::settle(&admin, 1, start_price);

        // User should get their original bet back
        let user1_balance_before = coin::balance<AptosCoin>(user1_addr);
        betting::claim(&user1, admin_addr, 1);
        let user1_balance_after = coin::balance<AptosCoin>(user1_addr);
        
        assert!(user1_balance_after == user1_balance_before + bet_amount, 0);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(admin = @0x123, user1 = @0x456, treasury = @0xabc, aptos_framework = @0x1)]
    public entry fun test_no_opposite_bets(
        admin: signer,
        user1: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let user1_addr = signer::address_of(&user1);
        let treasury_addr = signer::address_of(&treasury);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        account::create_account_for_test(treasury_addr);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        coin::deposit(admin_addr, coin::mint(1000000000, &mint_cap));
        coin::deposit(user1_addr, coin::mint(1000000000, &mint_cap));

        betting::init(&admin, 200, treasury_addr);
        
        let start_price = 1000000;
        betting::start_round(&admin, start_price, 300);
        
        let bet_amount = 100000000;
        betting::place_bet(&user1, admin_addr, 1, true, bet_amount); // Only UP bet

        timestamp::fast_forward_seconds(301);

        // UP wins
        let end_price = 1100000;
        betting::settle(&admin, 1, end_price);

        // User should get 2x their bet (no losing pool to share)
        let user1_balance_before = coin::balance<AptosCoin>(user1_addr);
        betting::claim(&user1, admin_addr, 1);
        let user1_balance_after = coin::balance<AptosCoin>(user1_addr);
        
        assert!(user1_balance_after == user1_balance_before + (bet_amount * 2), 0);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
}
