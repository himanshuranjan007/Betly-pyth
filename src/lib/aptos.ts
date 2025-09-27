import { 
  Aptos, 
  AptosConfig, 
  Network,
  // InputSubmitTransactionData,
  // AccountAddress,
} from '@aptos-labs/ts-sdk'
import { config } from './config'

// Initialize Aptos client
const aptosConfig = new AptosConfig({ 
  network: config.aptos.network as Network,
  fullnode: config.aptos.nodeUrl,
  clientConfig: {
    HEADERS: {
      Authorization: `Bearer ${config.aptos.apiKey}`,
      Origin: 'http://localhost:3000',
      'Content-Type': 'application/json',
    }
  },
})

export const aptos = new Aptos(aptosConfig)

// Contract interaction functions
export const contractFunctions = {
  // Place a bet
  placeBet: (roundId: number, sideUp: boolean, amount: number) => ({
    function: `${config.aptos.moduleAddress}::betting::place_bet`,
    functionArguments: [
      config.aptos.moduleAddress,
      roundId,
      sideUp,
      amount,
    ],
  }),

  // Claim winnings (admin claims for user)
  claim: (roundId: number, userAddress: string) => ({
    function: `${config.aptos.moduleAddress}::betting::claim`,
    functionArguments: [
      roundId,
      userAddress,
    ],
  }),

  // Batch claim winnings for multiple users
  batchClaim: (roundId: number, userAddresses: string[]) => ({
    function: `${config.aptos.moduleAddress}::betting::batch_claim`,
    functionArguments: [
      roundId,
      userAddresses,
    ],
  }),

  // Start round (admin only)
  startRound: (startPrice: number, durationSecs: number) => ({
    function: `${config.aptos.moduleAddress}::betting::start_round`,
    functionArguments: [
      startPrice,
      durationSecs,
    ],
  }),

  // Settle round (admin only)
  settle: (roundId: number, endPrice: number) => ({
    function: `${config.aptos.moduleAddress}::betting::settle`,
    functionArguments: [
      roundId,
      endPrice,
    ],
  }),
}

// View functions
export const viewFunctions = {
  // Get round data
  async getRound(roundId: number) {
    try {
      const result = await aptos.view({
        payload: {
          function: `${config.aptos.moduleAddress}::betting::get_round`,
          functionArguments: [config.aptos.moduleAddress, roundId],
        },
      })
      
      const [id, startPrice, endPrice, expiryTimeSecs, settled, upPool, downPool] = result as [
        string, string, string, string, boolean, string, string
      ]
      
      return {
        id: parseInt(id),
        startPrice: parseInt(startPrice),
        endPrice: parseInt(endPrice),
        expiryTimeSecs: parseInt(expiryTimeSecs),
        settled,
        upPool: parseInt(upPool),
        downPool: parseInt(downPool),
        totalPool: parseInt(upPool) + parseInt(downPool),
      }
    } catch (error) {
      console.error('Error getting round:', error)
      return null
    }
  },

  // Get user bet
  async getUserBet(roundId: number, userAddress: string) {
    try {
      const result = await aptos.view({
        payload: {
          function: `${config.aptos.moduleAddress}::betting::get_user_bet`,
          functionArguments: [config.aptos.moduleAddress, roundId, userAddress],
        },
      })
      
      const [sideUp, amount, claimed] = result as [boolean, string, boolean]
      
      return {
        sideUp,
        amount: parseInt(amount),
        claimed,
      }
    } catch (error) {
      console.error('Error getting user bet:', error)
      return null
    }
  },

  // Get current round ID
  async getCurrentRoundId(): Promise<number> {
    try {
      const result = await aptos.view({
        payload: {
          function: `${config.aptos.moduleAddress}::betting::get_current_round_id`,
          functionArguments: [config.aptos.moduleAddress],
        },
      })
      
      return parseInt(result[0] as string)
    } catch (error) {
      console.error('Error getting current round ID:', error)
      return 0
    }
  },

  // Calculate potential payout for a user bet (1.8x system)
  async calculatePotentialPayout(roundId: number, userAddress: string): Promise<number> {
    try {
      const result = await aptos.view({
        payload: {
          function: `${config.aptos.moduleAddress}::betting::calculate_potential_payout`,
          functionArguments: [config.aptos.moduleAddress, roundId, userAddress],
        },
      })
      
      return parseInt(result[0] as string)
    } catch (error) {
      console.error('Error calculating potential payout:', error)
      return 0
    }
  },

  // Get account balance
  async getBalance(address: string): Promise<number> {
    try {
      const resources = await aptos.getAccountResources({
        accountAddress: address,
      })
      
      const coinStore = resources.find(
        (r) => r.type === '0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>'
      )
      
      if (coinStore && coinStore.data) {
        const data = coinStore.data as { coin: { value: string } }
        return parseInt(data.coin.value)
      }
      
      return 0
    } catch (error) {
      console.error('Error getting balance:', error)
      return 0
    }
  },
}

// Event types for type safety
export interface BetPlacedEvent {
  round_id: string
  user: string
  side_up: boolean
  amount: string
  timestamp: string
}

export interface RoundSettledEvent {
  round_id: string
  start_price: string
  end_price: string
  winning_side: number
  up_pool: string
  down_pool: string
  fee_collected: string
}

export interface WinningsClaimedEvent {
  round_id: string
  user: string
  amount: string
}
