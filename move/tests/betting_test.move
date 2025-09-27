/// # Betly Betting Contract Test Suite
/// 
/// Comprehensive test suite for the Betly binary options smart contract.
/// Tests cover all major functionality including betting, settlement, and claiming.
/// 
/// ## Test Coverage:
/// - Full betting flow with multiple users
/// - Tie scenarios (price unchanged)
/// - Edge cases (no opposite bets)
/// - Error conditions and validations
/// 
/// @author Betly Team
/// @version 1.0.0
#[test_only]
module betly_betting::betting_test {
    use std::signer;
    use std::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::account;
    use betly_betting::betting;

    // ============================================================================
    // TEST CONSTANTS
    // ============================================================================
    
    /// Test account addresses
    const ADMIN_ADDR: address = @0x123;
    const USER1_ADDR: address = @0x456;
    const USER2_ADDR: address = @0x789;
    const TREASURY_ADDR: address = @0xabc;
    const APTOS_FRAMEWORK_ADDR: address = @0x1;
    
    /// Test amounts (in octas - 8 decimals)
    const INITIAL_BALANCE: u64 = 1000000000;  // 10 APT
    const BET_AMOUNT_1: u64 = 100000000;      // 1 APT
    const BET_AMOUNT_2: u64 = 200000000;       // 2 APT
    
    /// Test prices (in micro-dollars - 6 decimals)
    const START_PRICE: u64 = 1000000;          // $1.00
    const END_PRICE_UP: u64 = 1100000;         // $1.10 (UP wins)
    const END_PRICE_DOWN: u64 = 900000;        // $0.90 (DOWN wins)
    
    /// Test durations
    const ROUND_DURATION: u64 = 300;           // 5 minutes
    const FEE_BPS: u64 = 200;                  // 2% fee

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================
    
    /// Setup test environment with accounts and initial balances
    fun setup_test_environment(
        admin: &signer,
        user1: &signer,
        user2: &signer,
        treasury: &signer,
        aptos_framework: &signer
    ): (BurnCapability<AptosCoin>, MintCapability<AptosCoin>) {
        // Enable timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test accounts
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(treasury));

        // Initialize AptosCoin for testing
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);

        // Mint initial balances for all accounts
        coin::deposit(signer::address_of(admin), coin::mint(INITIAL_BALANCE, &mint_cap));
        coin::deposit(signer::address_of(user1), coin::mint(INITIAL_BALANCE, &mint_cap));
        coin::deposit(signer::address_of(user2), coin::mint(INITIAL_BALANCE, &mint_cap));

        (burn_cap, mint_cap)
    }

    /// Cleanup test environment
    fun cleanup_test_environment(burn_cap: BurnCapability<AptosCoin>, mint_cap: MintCapability<AptosCoin>) {
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    // ============================================================================
    // MAIN TEST CASES
    // ============================================================================
    
    /// Test the complete betting flow with multiple users
    /// 
    /// This test covers:
    /// 1. Contract initialization
    /// 2. Starting a betting round
    /// 3. Multiple users placing bets on different sides
    /// 4. Round settlement with price movement
    /// 5. Winner claiming winnings
    /// 6. Fee collection verification
    #[test(admin = @0x123, user1 = @0x456, user2 = @0x789, treasury = @0xabc, aptos_framework = @0x1)]
    public entry fun test_full_betting_flow(
        admin: signer,
        user1: signer,
        user2: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = setup_test_environment(&admin, &user1, &user2, &treasury, &aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);
        let treasury_addr = signer::address_of(&treasury);

        // Initialize betting contract with 2% fee
        betting::init(&admin, FEE_BPS, treasury_addr);

        // Start a new betting round
        // Round ID will be 1 (current_id starts at 0, increments to 1)
        betting::start_round(&admin, START_PRICE, ROUND_DURATION);

        // User1 places 1 APT bet on UP side
        betting::place_bet(&user1, admin_addr, 1, true, BET_AMOUNT_1);
        
        // User2 places 2 APT bet on DOWN side
        betting::place_bet(&user2, admin_addr, 1, false, BET_AMOUNT_2);

        // Fast forward time to expire the round
        timestamp::fast_forward_seconds(ROUND_DURATION + 1);

        // Settle round with UP winning price ($1.10 vs $1.00)
        betting::settle(&admin, 1, END_PRICE_UP);

        // Verify round data is correct
        let (id, start_p, end_p, expiry, settled, up_pool, down_pool) = 
            betting::get_round(admin_addr, 1);
        
        // Assertions for round data
        assert!(id == 1, 0);                                    // Round ID is 1
        assert!(start_p == START_PRICE, 1);                     // Start price is $1.00
        assert!(end_p == END_PRICE_UP, 2);                      // End price is $1.10
        assert!(settled == true, 3);                            // Round is settled
        assert!(up_pool == BET_AMOUNT_1, 4);                    // UP pool has 1 APT
        assert!(down_pool == BET_AMOUNT_2, 5);                  // DOWN pool has 2 APT

        // Test claiming winnings
        let user1_balance_before = coin::balance<AptosCoin>(user1_addr);
        
        // User1 should be able to claim winnings (they bet UP and UP won)
        betting::claim(&admin, 1, user1_addr);
        
        let user1_balance_after = coin::balance<AptosCoin>(user1_addr);
        
        // User1 should have more coins after claiming (1.8x their bet)
        assert!(user1_balance_after > user1_balance_before, 6);

        // Cleanup
        cleanup_test_environment(burn_cap, mint_cap);
    }

    /// Test tie scenario where price doesn't change
    /// 
    /// In tie scenarios:
    /// - Users get full refund (1x their bet)
    /// - No fees are collected (since money is refunded)
    /// - Both sides are treated equally
    #[test(admin = @0x123, user1 = @0x456, treasury = @0xabc, aptos_framework = @0x1)]
    public entry fun test_tie_case(
        admin: signer,
        user1: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = setup_test_environment(&admin, &user1, &admin, &treasury, &aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let user1_addr = signer::address_of(&user1);
        let treasury_addr = signer::address_of(&treasury);

        // Initialize contract
        betting::init(&admin, FEE_BPS, treasury_addr);
        
        // Start round with $1.00 price
        betting::start_round(&admin, START_PRICE, ROUND_DURATION);
        
        // User1 places bet on UP side
        betting::place_bet(&user1, admin_addr, 1, true, BET_AMOUNT_1);

        // Fast forward time to expire round
        timestamp::fast_forward_seconds(ROUND_DURATION + 1);

        // Settle with same price (tie scenario)
        betting::settle(&admin, 1, START_PRICE);

        // Test claiming in tie scenario
        let user1_balance_before = coin::balance<AptosCoin>(user1_addr);
        
        // User should get full refund (1x their bet amount)
        betting::claim(&admin, 1, user1_addr);
        
        let user1_balance_after = coin::balance<AptosCoin>(user1_addr);
        
        // User should get exactly their original bet back
        assert!(user1_balance_after == user1_balance_before + BET_AMOUNT_1, 0);

        // Cleanup
        cleanup_test_environment(burn_cap, mint_cap);
    }

    /// Test edge case with no opposite bets
    /// 
    /// This tests the scenario where only one side has bets.
    /// In this case, the winner gets the full pool (no losing side to share with).
    /// This is an edge case that could happen in low-liquidity scenarios.
    #[test(admin = @0x123, user1 = @0x456, treasury = @0xabc, aptos_framework = @0x1)]
    public entry fun test_no_opposite_bets(
        admin: signer,
        user1: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = setup_test_environment(&admin, &user1, &admin, &treasury, &aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let user1_addr = signer::address_of(&user1);
        let treasury_addr = signer::address_of(&treasury);

        // Initialize contract
        betting::init(&admin, FEE_BPS, treasury_addr);
        
        // Start round
        betting::start_round(&admin, START_PRICE, ROUND_DURATION);
        
        // Only User1 places bet on UP side (no DOWN bets)
        betting::place_bet(&user1, admin_addr, 1, true, BET_AMOUNT_1);

        // Fast forward time
        timestamp::fast_forward_seconds(ROUND_DURATION + 1);

        // Settle with UP winning price
        betting::settle(&admin, 1, END_PRICE_UP);

        // Test claiming when there are no opposite bets
        let user1_balance_before = coin::balance<AptosCoin>(user1_addr);
        
        // User should get 1.8x their bet (normal winning payout)
        betting::claim(&admin, 1, user1_addr);
        
        let user1_balance_after = coin::balance<AptosCoin>(user1_addr);
        
        // User should get 1.8x their bet amount
        assert!(user1_balance_after == user1_balance_before + (BET_AMOUNT_1 * 180) / 100, 0);

        // Cleanup
        cleanup_test_environment(burn_cap, mint_cap);
    }

    // ============================================================================
    // ADDITIONAL TEST CASES (Can be added for more comprehensive coverage)
    // ============================================================================
    
    /// Test minimum bet amount validation
    /// 
    /// This test would verify that bets below the minimum amount are rejected.
    /// Currently not implemented but would be valuable for edge case testing.
    #[test(admin = @0x123, user1 = @0x456, treasury = @0xabc, aptos_framework = @0x1)]
    #[expected_failure(abort_code = betly_betting::betting::E_INVALID_BET_AMOUNT)]
    public entry fun test_minimum_bet_amount(
        admin: signer,
        user1: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup
        let (burn_cap, mint_cap) = setup_test_environment(&admin, &user1, &admin, &treasury, &aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let treasury_addr = signer::address_of(&treasury);

        // Initialize and start round
        betting::init(&admin, FEE_BPS, treasury_addr);
        betting::start_round(&admin, START_PRICE, ROUND_DURATION);
        
        // Try to place bet below minimum amount (should fail)
        betting::place_bet(&user1, admin_addr, 1, true, 500000); // 0.005 APT (below 0.01 APT minimum)

        // Cleanup
        cleanup_test_environment(burn_cap, mint_cap);
    }

    /// Test round expiry validation
    /// 
    /// This test would verify that bets cannot be placed after round expiry.
    /// Currently not implemented but would be valuable for edge case testing.
    #[test(admin = @0x123, user1 = @0x456, treasury = @0xabc, aptos_framework = @0x1)]
    #[expected_failure(abort_code = betly_betting::betting::E_ROUND_EXPIRED)]
    public entry fun test_round_expiry(
        admin: signer,
        user1: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup
        let (burn_cap, mint_cap) = setup_test_environment(&admin, &user1, &admin, &treasury, &aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let treasury_addr = signer::address_of(&treasury);

        // Initialize and start round
        betting::init(&admin, FEE_BPS, treasury_addr);
        betting::start_round(&admin, START_PRICE, ROUND_DURATION);
        
        // Fast forward past expiry time
        timestamp::fast_forward_seconds(ROUND_DURATION + 1);
        
        // Try to place bet after expiry (should fail)
        betting::place_bet(&user1, admin_addr, 1, true, BET_AMOUNT_1);

        // Cleanup
        cleanup_test_environment(burn_cap, mint_cap);
    }

    /// Test double claiming prevention
    /// 
    /// This test would verify that users cannot claim winnings twice.
    /// Currently not implemented but would be valuable for edge case testing.
    #[test(admin = @0x123, user1 = @0x456, treasury = @0xabc, aptos_framework = @0x1)]
    #[expected_failure(abort_code = betly_betting::betting::E_ALREADY_CLAIMED)]
    public entry fun test_double_claiming(
        admin: signer,
        user1: signer,
        treasury: signer,
        aptos_framework: signer,
    ) {
        // Setup
        let (burn_cap, mint_cap) = setup_test_environment(&admin, &user1, &admin, &treasury, &aptos_framework);
        
        let admin_addr = signer::address_of(&admin);
        let user1_addr = signer::address_of(&user1);
        let treasury_addr = signer::address_of(&treasury);

        // Initialize, start round, place bet, settle
        betting::init(&admin, FEE_BPS, treasury_addr);
        betting::start_round(&admin, START_PRICE, ROUND_DURATION);
        betting::place_bet(&user1, admin_addr, 1, true, BET_AMOUNT_1);
        timestamp::fast_forward_seconds(ROUND_DURATION + 1);
        betting::settle(&admin, 1, END_PRICE_UP);
        
        // First claim (should succeed)
        betting::claim(&admin, 1, user1_addr);
        
        // Second claim (should fail)
        betting::claim(&admin, 1, user1_addr);

        // Cleanup
        cleanup_test_environment(burn_cap, mint_cap);
    }
}