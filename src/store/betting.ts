import { create } from 'zustand'

export interface Round {
  id: number
  startPrice: number
  endPrice?: number
  expiryTimeSecs: number
  settled: boolean
  upPool: number
  downPool: number
  totalPool: number
  winSide?: 'up' | 'down' | 'tie'
}

export interface Bet {
  roundId: number
  side: 'up' | 'down'
  amount: number
  timestamp: number
  claimed?: boolean
}

export interface BettingState {
  // Price data
  currentPrice: number
  priceHistory: Array<{ time: number; value: number }>
  
  // Current round
  currentRound?: Round
  timeRemaining: number
  
  // User data
  userBets: Bet[]
  balance: number
  
  // Past rounds
  pastRounds: Round[]
  
  // UI state
  betAmount: string
  isPlacingBet: boolean
  isClaiming: boolean
  
  // Actions
  setCurrentPrice: (price: number) => void
  addPricePoint: (price: number) => void
  setCurrentRound: (round: Round) => void
  setTimeRemaining: (time: number) => void
  addUserBet: (bet: Bet) => void
  setPastRounds: (rounds: Round[]) => void
  setBetAmount: (amount: string) => void
  setIsPlacingBet: (isPlacing: boolean) => void
  setIsClaiming: (isClaiming: boolean) => void
  setBalance: (balance: number) => void
}

export const useBettingStore = create<BettingState>((set) => ({
  // Initial state
  currentPrice: 0,
  priceHistory: [],
  timeRemaining: 0,
  userBets: [],
  balance: 0,
  pastRounds: [],
  betAmount: '0.1',
  isPlacingBet: false,
  isClaiming: false,
  
  // Actions
  setCurrentPrice: (price) => set({ currentPrice: price }),
  
  addPricePoint: (price) => {
    const now = Date.now()
    set((state) => {
      // Avoid duplicate timestamps by checking the last entry
      const lastEntry = state.priceHistory[state.priceHistory.length - 1]
      const timeKey = Math.floor(now / 1000) * 1000 // Round to nearest second
      
      if (lastEntry && Math.floor(lastEntry.time / 1000) * 1000 === timeKey) {
        // Update the last entry instead of adding a new one
        const updatedHistory = [...state.priceHistory.slice(0, -1), { time: now, value: price }]
        return {
          currentPrice: price,
          priceHistory: updatedHistory.slice(-1000), // Keep last 1000 points
        }
      } else {
        // Add new entry
        return {
          currentPrice: price,
          priceHistory: [
            ...state.priceHistory.slice(-1000), // Keep last 1000 points
            { time: now, value: price }
          ]
        }
      }
    })
  },
  
  setCurrentRound: (round) => set({ currentRound: round }),
  setTimeRemaining: (time) => set({ timeRemaining: time }),
  
  addUserBet: (bet) => set((state) => ({
    userBets: [...state.userBets, bet]
  })),
  
  setPastRounds: (rounds) => set({ pastRounds: rounds }),
  setBetAmount: (amount) => set({ betAmount: amount }),
  setIsPlacingBet: (isPlacing) => set({ isPlacingBet: isPlacing }),
  setIsClaiming: (isClaiming) => set({ isClaiming: isClaiming }),
  setBalance: (balance) => set({ balance: balance }),
}))
