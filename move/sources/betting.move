module orion_betting::betting {
    use std::signer;
    use std::timestamp;
    use std::error;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};

    // Error codes
    const E_NOT_ADMIN: u64 = 1;
    const E_ROUND_NOT_FOUND: u64 = 2;
    const E_ROUND_EXPIRED: u64 = 3;
    const E_ROUND_NOT_EXPIRED: u64 = 4;
    const E_ROUND_ALREADY_SETTLED: u64 = 5;
    const E_INVALID_BET_AMOUNT: u64 = 6;
    const E_NO_WINNINGS_TO_CLAIM: u64 = 7;
    const E_ALREADY_CLAIMED: u64 = 8;
    const E_INVALID_FEE_BPS: u64 = 9;

    // Constants
    const MAX_FEE_BPS: u64 = 500; // 5%
    const MIN_BET_AMOUNT: u64 = 1000000; // 0.01 APT (8 decimals)
    const WIN_MULTIPLIER: u64 = 180; // 1.8x multiplier (stored as 180/100)
    const MULTIPLIER_BASE: u64 = 100;

    // Structs
    struct State has key {
        admin: address,
        current_id: u64,
        rounds: Table<u64, Round>,
        fee_bps: u64, // basis points (100 = 1%)
        treasury: address,
    }

    struct Round has store {
        id: u64,
        start_price: u64, // Price in micro-dollars (6 decimals)
        end_price: u64,
        expiry_time_secs: u64,
        settled: bool,
        up_pool: u64,
        down_pool: u64,
        user_bets: Table<address, UserBet>,
    }

    struct UserBet has store {
        side_up: bool,
        amount: u64,
        claimed: bool,
    }

    // Events
    #[event]
    struct BetPlaced has drop, store {
        round_id: u64,
        user: address,
        side_up: bool,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    struct RoundSettled has drop, store {
        round_id: u64,
        start_price: u64,
        end_price: u64,
        winning_side: u8, // 0 = down, 1 = up, 2 = tie
        up_pool: u64,
        down_pool: u64,
        fee_collected: u64,
    }

    #[event]
    struct WinningsClaimed has drop, store {
        round_id: u64,
        user: address,
        amount: u64,
    }

    // Initialize the betting contract
    public entry fun init(admin: &signer, fee_bps: u64, treasury: address) {
        let admin_addr = signer::address_of(admin);
        assert!(fee_bps <= MAX_FEE_BPS, error::invalid_argument(E_INVALID_FEE_BPS));
        
        move_to(admin, State {
            admin: admin_addr,
            current_id: 0,
            rounds: table::new(),
            fee_bps,
            treasury,
        });
    }

    // Start a new betting round
    public entry fun start_round(
        admin: &signer,
        start_price: u64,
        duration_secs: u64
    ) acquires State {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<State>(admin_addr);
        assert!(state.admin == admin_addr, error::permission_denied(E_NOT_ADMIN));

        let round_id = state.current_id + 1;
        state.current_id = round_id;

        let round = Round {
            id: round_id,
            start_price,
            end_price: 0,
            expiry_time_secs: timestamp::now_seconds() + duration_secs,
            settled: false,
            up_pool: 0,
            down_pool: 0,
            user_bets: table::new(),
        };

        table::add(&mut state.rounds, round_id, round);
    }

    // Place a bet on the current round
    public entry fun place_bet(
        user: &signer,
        admin_addr: address,
        round_id: u64,
        side_up: bool,
        amount: u64
    ) acquires State {
        assert!(amount >= MIN_BET_AMOUNT, error::invalid_argument(E_INVALID_BET_AMOUNT));
        
        let user_addr = signer::address_of(user);
        let state = borrow_global_mut<State>(admin_addr);
        
        assert!(table::contains(&state.rounds, round_id), error::not_found(E_ROUND_NOT_FOUND));
        let round = table::borrow_mut(&mut state.rounds, round_id);
        
        assert!(timestamp::now_seconds() < round.expiry_time_secs, error::invalid_state(E_ROUND_EXPIRED));
        assert!(!round.settled, error::invalid_state(E_ROUND_ALREADY_SETTLED));

        // Transfer coins from user to admin (who holds the pool)
        let coins = coin::withdraw<AptosCoin>(user, amount);
        coin::deposit(admin_addr, coins);

        // Update pools
        if (side_up) {
            round.up_pool = round.up_pool + amount;
        } else {
            round.down_pool = round.down_pool + amount;
        };

        // Record user bet
        let user_bet = UserBet {
            side_up,
            amount,
            claimed: false,
        };
        table::add(&mut round.user_bets, user_addr, user_bet);

        // Emit event
        event::emit(BetPlaced {
            round_id,
            user: user_addr,
            side_up,
            amount,
            timestamp: timestamp::now_seconds(),
        });
    }

    // Settle a round with the end price
    public entry fun settle(
        admin: &signer,
        round_id: u64,
        end_price: u64
    ) acquires State {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<State>(admin_addr);
        assert!(state.admin == admin_addr, error::permission_denied(E_NOT_ADMIN));

        assert!(table::contains(&state.rounds, round_id), error::not_found(E_ROUND_NOT_FOUND));
        let round = table::borrow_mut(&mut state.rounds, round_id);
        
        assert!(timestamp::now_seconds() >= round.expiry_time_secs, error::invalid_state(E_ROUND_NOT_EXPIRED));
        assert!(!round.settled, error::invalid_state(E_ROUND_ALREADY_SETTLED));

        round.end_price = end_price;
        round.settled = true;

        // Determine winning side
        let winning_side = if (end_price > round.start_price) {
            1 // up wins
        } else if (end_price < round.start_price) {
            0 // down wins  
        } else {
            2 // tie
        };

        // Calculate and collect fee
        let total_pool = round.up_pool + round.down_pool;
        let fee_amount = if (winning_side == 2) {
            0 // No fee on ties since money is refunded
        } else {
            (total_pool * state.fee_bps) / 10000
        };

        if (fee_amount > 0) {
            let fee_coins = coin::withdraw<AptosCoin>(admin, fee_amount);
            coin::deposit(state.treasury, fee_coins);
        };

        // Emit settlement event
        event::emit(RoundSettled {
            round_id,
            start_price: round.start_price,
            end_price,
            winning_side,
            up_pool: round.up_pool,
            down_pool: round.down_pool,
            fee_collected: fee_amount,
        });
    }

    // Claim winnings from a settled round - admin distributes winnings
    public entry fun claim(
        admin: &signer,
        round_id: u64,
        user_addr: address
    ) acquires State {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<State>(admin_addr);
        assert!(state.admin == admin_addr, error::permission_denied(E_NOT_ADMIN));
        
        assert!(table::contains(&state.rounds, round_id), error::not_found(E_ROUND_NOT_FOUND));
        let round = table::borrow_mut(&mut state.rounds, round_id);
        
        assert!(round.settled, error::invalid_state(E_ROUND_ALREADY_SETTLED));
        assert!(table::contains(&round.user_bets, user_addr), error::not_found(E_NO_WINNINGS_TO_CLAIM));
        
        let user_bet = table::borrow(&round.user_bets, user_addr);
        assert!(!user_bet.claimed, error::invalid_state(E_ALREADY_CLAIMED));

        // Calculate payout
        let payout = calculate_payout(round, user_bet, state.fee_bps);
        
        if (payout > 0) {
            let user_bet_mut = table::borrow_mut(&mut round.user_bets, user_addr);
            user_bet_mut.claimed = true;
            
            // Transfer winnings from admin to user
            let coins = coin::withdraw<AptosCoin>(admin, payout);
            coin::deposit(user_addr, coins);

            // Emit event
            event::emit(WinningsClaimed {
                round_id,
                user: user_addr,
                amount: payout,
            });
        };
    }

    // Helper function to calculate payout with 1.8x multiplier
    fun calculate_payout(round: &Round, user_bet: &UserBet, _fee_bps: u64): u64 {
        // Handle tie case - refund original bet
        if (round.start_price == round.end_price) {
            return user_bet.amount
        };

        // Determine if user won
        let user_won = if (round.end_price > round.start_price) {
            user_bet.side_up
        } else {
            !user_bet.side_up
        };

        if (!user_won) {
            return 0
        };

        // Winner gets 1.8x their bet amount
        (user_bet.amount * WIN_MULTIPLIER) / MULTIPLIER_BASE
    }

    // View functions
    #[view]
    public fun get_round(admin_addr: address, round_id: u64): (u64, u64, u64, u64, bool, u64, u64) acquires State {
        let state = borrow_global<State>(admin_addr);
        assert!(table::contains(&state.rounds, round_id), error::not_found(E_ROUND_NOT_FOUND));
        
        let round = table::borrow(&state.rounds, round_id);
        (
            round.id,
            round.start_price,
            round.end_price,
            round.expiry_time_secs,
            round.settled,
            round.up_pool,
            round.down_pool
        )
    }

    #[view]
    public fun get_user_bet(admin_addr: address, round_id: u64, user_addr: address): (bool, u64, bool) acquires State {
        let state = borrow_global<State>(admin_addr);
        assert!(table::contains(&state.rounds, round_id), error::not_found(E_ROUND_NOT_FOUND));
        
        let round = table::borrow(&state.rounds, round_id);
        assert!(table::contains(&round.user_bets, user_addr), error::not_found(E_NO_WINNINGS_TO_CLAIM));
        
        let user_bet = table::borrow(&round.user_bets, user_addr);
        (user_bet.side_up, user_bet.amount, user_bet.claimed)
    }

    #[view]
    public fun get_current_round_id(admin_addr: address): u64 acquires State {
        let state = borrow_global<State>(admin_addr);
        state.current_id
    }

    // View function to calculate potential payout for a user bet
    #[view]
    public fun calculate_potential_payout(admin_addr: address, round_id: u64, user_addr: address): u64 acquires State {
        let state = borrow_global<State>(admin_addr);
        assert!(table::contains(&state.rounds, round_id), error::not_found(E_ROUND_NOT_FOUND));
        
        let round = table::borrow(&state.rounds, round_id);
        if (!table::contains(&round.user_bets, user_addr)) {
            return 0
        };
        
        let user_bet = table::borrow(&round.user_bets, user_addr);
        if (!round.settled) {
            // Return potential 1.8x payout for active bets
            return (user_bet.amount * WIN_MULTIPLIER) / MULTIPLIER_BASE
        } else {
            // Return actual calculated payout for settled rounds
            return calculate_payout(round, user_bet, state.fee_bps)
        }
    }

    // Batch claim winnings for multiple users in a round
    public entry fun batch_claim(
        admin: &signer,
        round_id: u64,
        user_addresses: vector<address>
    ) acquires State {
        let i = 0;
        let len = vector::length(&user_addresses);
        
        while (i < len) {
            let user_addr = *vector::borrow(&user_addresses, i);
            claim(admin, round_id, user_addr);
            i = i + 1;
        };
    }
}