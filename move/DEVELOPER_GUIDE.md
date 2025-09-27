# Betly Smart Contract Developer Guide

## Overview

The Betly smart contract is a decentralized binary options platform built on Aptos using the Move language. This guide provides comprehensive documentation for developers working with the contract.

## Contract Architecture

### Core Components

1. **State Management**: Global state stored at admin address
2. **Round System**: Time-based betting rounds with automatic expiry
3. **Betting Mechanism**: UP/DOWN binary options with 1.8x payout
4. **Fee System**: Protocol fees collected from losing bets
5. **Claiming System**: Admin-distributed winnings with batch support

### Data Structures

#### State
```move
struct State has key {
    admin: address,           // Contract admin
    current_id: u64,          // Current round counter
    rounds: Table<u64, Round>, // All rounds
    fee_bps: u64,            // Fee in basis points
    treasury: address,        // Fee recipient
}
```

#### Round
```move
struct Round has store {
    id: u64,                          // Round ID
    start_price: u64,                 // Starting price (micro-dollars)
    end_price: u64,                   // Ending price (micro-dollars)
    expiry_time_secs: u64,           // Expiry timestamp
    settled: bool,                    // Settlement status
    up_pool: u64,                     // Total UP bets
    down_pool: u64,                   // Total DOWN bets
    user_bets: Table<address, UserBet>, // User bets
}
```

#### UserBet
```move
struct UserBet has store {
    side_up: bool,    // true = UP, false = DOWN
    amount: u64,      // Bet amount (octas)
    claimed: bool,    // Claim status
}
```

## Price Precision

### Micro-Dollars (6 decimals)
- All prices stored as micro-dollars
- Example: $12.345678 = 12345678
- Conversion: `price * 1,000,000`

### Octas (8 decimals)
- All bet amounts in octas
- Example: 1 APT = 100000000 octas
- Conversion: `amount * 100,000,000`

## Function Reference

### Initialization

#### `init(admin: &signer, fee_bps: u64, treasury: address)`
- **Purpose**: Initialize the contract
- **Access**: Admin only
- **Parameters**:
  - `fee_bps`: Fee in basis points (max 500 = 5%)
  - `treasury`: Address to receive fees
- **Events**: None

### Round Management

#### `start_round(admin: &signer, start_price: u64, duration_secs: u64)`
- **Purpose**: Start a new betting round
- **Access**: Admin only
- **Parameters**:
  - `start_price`: Starting price in micro-dollars
  - `duration_secs`: Round duration in seconds
- **Events**: None
- **Side Effects**: Increments `current_id`

#### `settle(admin: &signer, round_id: u64, end_price: u64)`
- **Purpose**: Settle a round with final price
- **Access**: Admin only
- **Parameters**:
  - `round_id`: Round to settle
  - `end_price`: Final price in micro-dollars
- **Events**: `RoundSettled`
- **Side Effects**: Collects fees, marks round as settled

### Betting

#### `place_bet(user: &signer, admin_addr: address, round_id: u64, side_up: bool, amount: u64)`
- **Purpose**: Place a bet on a round
- **Access**: Public
- **Parameters**:
  - `admin_addr`: Admin address (where state is stored)
  - `round_id`: Round to bet on
  - `side_up`: true = UP bet, false = DOWN bet
  - `amount`: Bet amount in octas (min 1,000,000)
- **Events**: `BetPlaced`
- **Side Effects**: Transfers coins, updates pools

### Claiming

#### `claim(admin: &signer, round_id: u64, user_addr: address)`
- **Purpose**: Claim winnings for a user
- **Access**: Admin only
- **Parameters**:
  - `round_id`: Round to claim from
  - `user_addr`: User to claim for
- **Events**: `WinningsClaimed`
- **Side Effects**: Transfers winnings, marks as claimed

#### `batch_claim(admin: &signer, round_id: u64, user_addresses: vector<address>)`
- **Purpose**: Batch claim for multiple users
- **Access**: Admin only
- **Parameters**:
  - `user_addresses`: Vector of user addresses
- **Events**: Multiple `WinningsClaimed`
- **Side Effects**: Multiple transfers

### View Functions

#### `get_round(admin_addr: address, round_id: u64): (u64, u64, u64, u64, bool, u64, u64)`
- **Returns**: (id, start_price, end_price, expiry_time, settled, up_pool, down_pool)

#### `get_user_bet(admin_addr: address, round_id: u64, user_addr: address): (bool, u64, bool)`
- **Returns**: (side_up, amount, claimed)

#### `get_current_round_id(admin_addr: address): u64`
- **Returns**: Current round ID

#### `calculate_potential_payout(admin_addr: address, round_id: u64, user_addr: address): u64`
- **Returns**: Potential payout amount

## Payout System

### Winning Conditions
- **UP Wins**: `end_price > start_price`
- **DOWN Wins**: `end_price < start_price`
- **Tie**: `end_price == start_price`

### Payout Calculation
```move
// Winners: 1.8x multiplier
payout = (bet_amount * 180) / 100

// Losers: 0
payout = 0

// Ties: Full refund
payout = bet_amount
```

### Fee Collection
```move
// Fee calculation (only for non-tie rounds)
fee = (total_pool * fee_bps) / 10000

// Fee goes to treasury
// Remaining pool distributed to winners
```

## Error Handling

### Error Codes
- `E_NOT_ADMIN` (1): Admin-only function called by non-admin
- `E_ROUND_NOT_FOUND` (2): Round ID doesn't exist
- `E_ROUND_EXPIRED` (3): Round has expired
- `E_ROUND_NOT_EXPIRED` (4): Round hasn't expired yet
- `E_ROUND_ALREADY_SETTLED` (5): Round already settled
- `E_INVALID_BET_AMOUNT` (6): Bet below minimum
- `E_NO_WINNINGS_TO_CLAIM` (7): No bet found
- `E_ALREADY_CLAIMED` (8): Already claimed
- `E_INVALID_FEE_BPS` (9): Fee too high

### Validation Rules
- Minimum bet: 1,000,000 octas (0.01 APT)
- Maximum fee: 500 basis points (5%)
- Round must be active to accept bets
- Round must be expired to settle
- User can only claim once per round

## Events

### BetPlaced
```move
struct BetPlaced {
    round_id: u64,
    user: address,
    side_up: bool,
    amount: u64,
    timestamp: u64,
}
```

### RoundSettled
```move
struct RoundSettled {
    round_id: u64,
    start_price: u64,
    end_price: u64,
    winning_side: u8,  // 0=DOWN, 1=UP, 2=TIE
    up_pool: u64,
    down_pool: u64,
    fee_collected: u64,
}
```

### WinningsClaimed
```move
struct WinningsClaimed {
    round_id: u64,
    user: address,
    amount: u64,
}
```

## Integration with Pyth Network

### Price Feed Integration
- Prices fetched from Pyth Network via API
- Converted to micro-dollars for storage
- Real-time price updates via WebSocket
- Fallback mechanisms for reliability

### Keeper Service
- Automated round management
- Price fetching and settlement
- Batch operations for efficiency
- Error handling and retry logic

## Security Considerations

### Access Control
- Admin-only functions properly protected
- State access controlled by admin address
- No unauthorized modifications possible

### Economic Security
- Minimum bet amounts prevent dust attacks
- Fee limits prevent excessive charges
- Payout calculations are deterministic
- No rounding errors in calculations

### Time-based Security
- Rounds expire automatically
- No indefinite betting periods
- Timestamp validation on all operations

## Testing

### Test Coverage
- Full betting flow with multiple users
- Tie scenarios and edge cases
- Error conditions and validations
- Batch operations
- Fee collection verification

### Running Tests
```bash
cd move
aptos move test
```

### Test Structure
- Setup/teardown helpers
- Comprehensive assertions
- Edge case coverage
- Error condition testing

## Deployment

### Prerequisites
- Aptos CLI installed
- Admin account configured
- Sufficient APT for gas fees

### Deployment Steps
```bash
# Compile contract
aptos move compile

# Publish contract
aptos move publish --named-addresses betly_betting=default

# Initialize contract
aptos move run --function-id <ADDRESS>::betting::init --args address:<ADMIN> u64:200 address:<TREASURY>
```

### Configuration
- Set appropriate fee percentage
- Configure treasury address
- Set up keeper service
- Configure Pyth price feeds

## Best Practices

### Development
- Always test with multiple scenarios
- Use proper error handling
- Validate all inputs
- Follow Move best practices

### Operations
- Monitor round expiry times
- Ensure reliable price feeds
- Handle edge cases gracefully
- Maintain proper backups

### Security
- Regular security audits
- Monitor for unusual activity
- Keep admin keys secure
- Implement proper access controls

## Troubleshooting

### Common Issues
- Round not found: Check round ID
- Insufficient balance: Check user funds
- Round expired: Check timing
- Already claimed: Check claim status

### Debug Tools
- View functions for state inspection
- Event logs for transaction tracking
- Test framework for validation
- Error codes for issue identification

## Future Enhancements

### Potential Improvements
- Multi-asset support
- Dynamic fee structures
- Advanced betting options
- Governance mechanisms
- Cross-chain integration

### Scalability
- Batch operations
- Gas optimization
- State management
- Event filtering
- Indexing support
