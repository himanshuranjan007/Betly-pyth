import { NextResponse } from 'next/server'
import { Aptos, AptosConfig, Network, Ed25519PrivateKey, Account } from '@aptos-labs/ts-sdk'
import { config } from '@/lib/config'
import { pythPullOracle, getPythPrice } from '@/lib/pyth-pull-oracle'

export async function POST() {
  try {
    if (!config.keeper.privateKey) {
      return NextResponse.json(
        { error: 'Keeper private key not configured' },
        { status: 400 }
      )
    }

    console.log('🚀 Starting new round with Pyth pull oracle integration')

    // Step 1: Execute Pyth pull oracle flow
    // This implements the hackathon requirement: fetch -> update -> consume
    const pythResult = await getPythPrice(config.pyth.aptUsdPriceId)
    
    if (!pythResult.success || !pythResult.priceData) {
      console.error('❌ Pyth pull oracle failed:', pythResult.error)
      return NextResponse.json(
        { 
          error: 'Failed to get price via Pyth pull oracle',
          details: pythResult.error 
        },
        { status: 500 }
      )
    }

    const currentPrice = pythResult.priceData.price
    console.log(`✅ Pyth pull oracle successful: $${currentPrice.toFixed(6)}`)
    console.log(`📝 Transaction hash: ${pythResult.transactionHash}`)

    if (!currentPrice || currentPrice <= 0) {
      throw new Error('Invalid price data received from Pyth pull oracle')
    }

    // Convert price to micro-dollars (multiply by 1,000,000)
    const startPriceInMicroDollars = Math.floor(currentPrice * 1000000)

    console.log('🎯 Starting round with on-chain Pyth price:', currentPrice, 'micro-dollars:', startPriceInMicroDollars)

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
    const aptos = new Aptos(aptosConfig)

    // Create keeper account from private key
    const privateKey = new Ed25519PrivateKey(config.keeper.privateKey)
    const keeper = Account.fromPrivateKey({ privateKey })

    // Start a new round using the Pyth pull oracle integration
    const transaction = await aptos.transaction.build.simple({
      sender: keeper.accountAddress,
      data: {
        function: `${config.aptos.moduleAddress}::betting::start_round_with_pyth`,
        functionArguments: [
          config.keeper.roundDuration, // duration_secs (default: 300 = 5 minutes)
        ],
      },
    })

    const committedTxn = await aptos.signAndSubmitTransaction({
      signer: keeper,
      transaction,
    })

    const executedTxn = await aptos.waitForTransaction({
      transactionHash: committedTxn.hash,
    })

    console.log('✅ Round started successfully with Pyth pull oracle integration')

    return NextResponse.json({
      success: true,
      message: 'Round started successfully using Pyth pull oracle',
      transactionHash: committedTxn.hash,
      startPrice: currentPrice,
      startPriceInMicroDollars,
      duration: config.keeper.roundDuration,
      transaction: executedTxn,
      pythIntegration: {
        pullOracleUsed: true,
        pythTransactionHash: pythResult.transactionHash,
        priceSource: 'on-chain-pyth',
        confidence: pythResult.priceData.confidence,
        timestamp: pythResult.priceData.timestamp,
      },
    })
  } catch (error: unknown) {
    console.error('❌ Error starting round with Pyth pull oracle:', error)
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    const errorStack = error instanceof Error ? error.stack : undefined
    return NextResponse.json(
      { 
        error: 'Failed to start round with Pyth pull oracle',
        details: errorMessage,
        stack: errorStack,
      },
      { status: 500 }
    )
  }
}