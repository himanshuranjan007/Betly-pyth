'use client'

import { useEffect, useState } from 'react'
import { useWallet } from '@aptos-labs/wallet-adapter-react'
import { Button } from '@/components/ui/Button'
import { useBettingStore } from '@/store/betting'
import { viewFunctions } from '@/lib/aptos'
// import { contractFunctions, aptos } from '@/lib/aptos'
import { formatCurrency, cn } from '@/lib/utils'
import { Trophy, Clock, TrendingUp, TrendingDown, Gift } from 'lucide-react'

interface PastRoundWithBet {
  id: number
  startPrice: number
  endPrice?: number
  expiryTimeSecs: number
  settled: boolean
  upPool: number
  downPool: number
  totalPool: number
  winSide?: 'up' | 'down' | 'tie'
  userBet?: {
    side: 'up' | 'down'
    amount: number
    claimed: boolean
    canClaim: boolean
    payout: number
  }
}

export function PastRounds() {
  const { connected, account } = useWallet()
  const { pastRounds, isClaiming, setIsClaiming } = useBettingStore()
  const [roundsWithBets, setRoundsWithBets] = useState<PastRoundWithBet[]>([])
  const [claimingRoundId, setClaimingRoundId] = useState<number | null>(null)

  // Load user bets for past rounds
  useEffect(() => {
    const loadUserBets = async () => {
      if (!connected || !account || pastRounds.length === 0) {
        setRoundsWithBets(pastRounds.map(round => ({ ...round })))
        return
      }

      const roundsWithUserBets = await Promise.all(
        pastRounds.map(async (round) => {
          try {
            const userBet = await viewFunctions.getUserBet(round.id, account.address)
            
            if (userBet) {
              // Calculate potential payout
              let payout = 0
              let canClaim = false

              if (round.settled && !userBet.claimed) {
                if (round.winSide === 'tie') {
                  // Tie case - refund original bet
                  payout = userBet.amount
                  canClaim = true
                } else if (
                  (round.winSide === 'up' && userBet.sideUp) ||
                  (round.winSide === 'down' && !userBet.sideUp)
                ) {
                  // User won - calculate proportional share
                  const totalPool = round.upPool + round.downPool
                  const winningPool = userBet.sideUp ? round.upPool : round.downPool
                  const losingPool = userBet.sideUp ? round.downPool : round.upPool
                  
                  if (losingPool === 0) {
                    // No losing bets - 2x payout
                    payout = userBet.amount * 2
                  } else {
                    // Proportional share after fees (assuming 2% fee)
                    const feeAmount = Math.floor(totalPool * 0.02)
                    const distributableAmount = totalPool - feeAmount
                    payout = Math.floor((userBet.amount * distributableAmount) / winningPool)
                  }
                  canClaim = true
                }
              }

              return {
                ...round,
                userBet: {
                  side: userBet.sideUp ? 'up' as const : 'down' as const,
                  amount: userBet.amount,
                  claimed: userBet.claimed,
                  canClaim,
                  payout,
                },
              }
            }
          } catch (error) {
            console.error(`Error loading user bet for round ${round.id}:`, error)
          }

          return { ...round }
        })
      )

      setRoundsWithBets(roundsWithUserBets)
    }

    loadUserBets()
  }, [connected, account, pastRounds])

  // Handle claim winnings
  const handleClaim = async (roundId: number) => {
    if (!connected || !account || isClaiming) return

    setIsClaiming(true)
    setClaimingRoundId(roundId)

    try {
      // TODO: Implement transaction after Move contract deployment
      // For now, simulate the claim process
      console.log(`Claiming winnings for round ${roundId}`)
      
      // Simulate transaction delay
      await new Promise(resolve => setTimeout(resolve, 2000))

      // Update local state
      setRoundsWithBets(prev => 
        prev.map(round => 
          round.id === roundId && round.userBet
            ? { ...round, userBet: { ...round.userBet, claimed: true, canClaim: false } }
            : round
        )
      )

      console.log('Demo claim successful')
    } catch (error) {
      console.error('Error claiming winnings:', error)
    } finally {
      setIsClaiming(false)
      setClaimingRoundId(null)
    }
  }

  if (roundsWithBets.length === 0) {
    return (
      <div className="bg-gray-900 rounded-lg p-6">
        <div className="text-center text-gray-400">
          <Clock className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p>No past rounds yet</p>
          <p className="text-sm">Past rounds will appear here once they&apos;re completed</p>
        </div>
      </div>
    )
  }

  return (
    <div className="bg-gray-900 rounded-lg p-6">
      <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
        <Trophy className="w-5 h-5" />
        Past Rounds
      </h3>
      
      <div className="space-y-4 max-h-96 overflow-y-auto">
        {roundsWithBets.map((round) => {
          const hasUserBet = !!round.userBet
          const userWon = hasUserBet && round.settled && (
            (round.winSide === 'up' && round.userBet!.side === 'up') ||
            (round.winSide === 'down' && round.userBet!.side === 'down') ||
            round.winSide === 'tie'
          )

          return (
            <div
              key={round.id}
              className={cn(
                "border rounded-lg p-4 transition-all duration-200",
                hasUserBet
                  ? userWon
                    ? "border-green-500/30 bg-green-500/5"
                    : round.settled
                    ? "border-red-500/30 bg-red-500/5"
                    : "border-yellow-500/30 bg-yellow-500/5"
                  : "border-gray-700 bg-gray-800/50"
              )}
            >
              <div className="flex items-start justify-between mb-3">
                <div>
                  <h4 className="font-semibold text-white">Round #{round.id}</h4>
                  <div className="text-sm text-gray-400 space-y-1">
                    <div>Start: ${(round.startPrice / 1000000).toFixed(4)}</div>
                    {round.settled && (
                      <div>End: ${(round.endPrice! / 1000000).toFixed(4)}</div>
                    )}
                  </div>
                </div>
                
                <div className="text-right">
                  {round.settled ? (
                    <div className="flex items-center gap-1 text-sm">
                      {round.winSide === 'up' && <TrendingUp className="w-4 h-4 text-green-500" />}
                      {round.winSide === 'down' && <TrendingDown className="w-4 h-4 text-red-500" />}
                      <span className={cn(
                        "font-semibold",
                        round.winSide === 'up' && "text-green-500",
                        round.winSide === 'down' && "text-red-500",
                        round.winSide === 'tie' && "text-yellow-500"
                      )}>
                        {round.winSide === 'tie' ? 'TIE' : round.winSide!.toUpperCase()} WINS
                      </span>
                    </div>
                  ) : (
                    <span className="text-sm text-yellow-500">Pending Settlement</span>
                  )}
                </div>
              </div>

              {/* Pool Information */}
              <div className="grid grid-cols-2 gap-4 mb-3 text-sm">
                <div>
                  <span className="text-gray-400">UP Pool:</span>
                  <span className="ml-2 text-green-400 font-mono">
                    {formatCurrency(round.upPool)} APT
                  </span>
                </div>
                <div>
                  <span className="text-gray-400">DOWN Pool:</span>
                  <span className="ml-2 text-red-400 font-mono">
                    {formatCurrency(round.downPool)} APT
                  </span>
                </div>
              </div>

              {/* User Bet Information */}
              {hasUserBet && (
                <div className="border-t border-gray-700 pt-3">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      {round.userBet!.side === 'up' ? (
                        <TrendingUp className="w-4 h-4 text-green-500" />
                      ) : (
                        <TrendingDown className="w-4 h-4 text-red-500" />
                      )}
                      <span className="text-sm text-white">
                        Your bet: {round.userBet!.side.toUpperCase()} {formatCurrency(round.userBet!.amount)} APT
                      </span>
                    </div>
                    
                    {round.userBet!.canClaim && !round.userBet!.claimed && (
                      <Button
                        size="sm"
                        onClick={() => handleClaim(round.id)}
                        disabled={isClaiming}
                        className="bg-green-600 hover:bg-green-700"
                      >
                        <Gift className="w-4 h-4 mr-1" />
                        {claimingRoundId === round.id ? 'Claiming...' : 'Claim'}
                      </Button>
                    )}
                  </div>
                  
                  {round.settled && (
                    <div className="text-sm">
                      {userWon ? (
                        <span className="text-green-400">
                          {round.userBet!.claimed 
                            ? `✓ Claimed ${formatCurrency(round.userBet!.payout)} APT`
                            : `Winnings: ${formatCurrency(round.userBet!.payout)} APT`
                          }
                        </span>
                      ) : (
                        <span className="text-red-400">Lost bet</span>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
