/**
 * Pyth Price Feed Updater Service
 * 
 * Implements the Pyth pull oracle pattern:
 * 1. Fetch price data from Hermes API
 * 2. Update on-chain price feeds using updatePriceFeeds method
 * 3. Consume updated prices for settlement
 * 
 * This service enables Betly to qualify for the Pyth Network hackathon
 * "Most Innovative use of Pyth pull oracle" track.
 */

import { PriceServiceConnection } from '@pythnetwork/pyth-sdk-js'
import { PythPriceService } from '@pythnetwork/pyth-evm-js'
import { Aptos, AptosConfig, Network, Ed25519PrivateKey, Account } from '@aptos-labs/ts-sdk'
import { config } from '@/lib/config'

export interface PythPriceData {
  price: number
  confidence: number
  timestamp: number
  expo: number
  priceId: string
}

export interface PriceUpdateResult {
  success: boolean
  priceData?: PythPriceData
  transactionHash?: string
  error?: string
}

export class PythPullOracleService {
  private connection: PriceServiceConnection
  private aptos: Aptos
  private keeper: Account
  private pythContractAddress: string

  constructor() {
    // Initialize Pyth connection
    this.connection = new PriceServiceConnection(
      config.pyth.endpoint,
      {
        priceFeedRequestConfig: {
          binary: true,
        },
      }
    )

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
    this.aptos = new Aptos(aptosConfig)

    // Create keeper account
    const privateKey = new Ed25519PrivateKey(config.keeper.privateKey)
    this.keeper = Account.fromPrivateKey({ privateKey })

    // Pyth contract address on Aptos testnet
    // This would need to be deployed or use existing Pyth contract
    this.pythContractAddress = '0x1::pyth'
  }

  /**
   * Fetch latest price data from Pyth Hermes API
   * Step 1 of pull oracle pattern
   */
  async fetchPriceFromHermes(priceId: string): Promise<PythPriceData | null> {
    try {
      console.log(`🔍 Fetching price data from Hermes for ${priceId}`)
      
      const response = await fetch(
        `${config.pyth.endpoint}/api/latest_price_feeds?ids[]=${priceId}`,
        {
          next: { revalidate: 1 }, // Cache for 1 second
        }
      )

      if (!response.ok) {
        throw new Error(`Pyth API error: ${response.status}`)
      }

      const data = await response.json()
      
      if (!data || !Array.isArray(data) || data.length === 0) {
        throw new Error('No price data received from Pyth')
      }

      const priceFeed = data[0]
      if (!priceFeed || !priceFeed.price) {
        throw new Error('Invalid price feed data')
      }

      const priceData = priceFeed.price
      const price = parseFloat(priceData.price) * Math.pow(10, priceData.expo)
      const confidence = parseFloat(priceData.conf) * Math.pow(10, priceData.expo)
      const timestamp = parseInt(priceData.publish_time)

      console.log(`✅ Fetched price: $${price.toFixed(6)} (confidence: $${confidence.toFixed(6)})`)

      return {
        price,
        confidence,
        timestamp,
        expo: priceData.expo,
        priceId,
      }
    } catch (error) {
      console.error('❌ Error fetching price from Hermes:', error)
      return null
    }
  }

  /**
   * Update price feeds on-chain using updatePriceFeeds method
   * Step 2 of pull oracle pattern
   */
  async updatePriceFeedsOnChain(priceIds: string[]): Promise<string | null> {
    try {
      console.log(`🔄 Updating price feeds on-chain for ${priceIds.length} feeds`)

      // Fetch price update data from Pyth
      const priceUpdateData = await this.connection.getPriceUpdateData(priceIds)
      
      if (!priceUpdateData || priceUpdateData.length === 0) {
        throw new Error('No price update data received from Pyth')
      }

      // Convert price update data to hex format for Aptos
      const priceUpdateDataHex = priceUpdateData.map(data => 
        Buffer.from(data, 'base64').toString('hex')
      )

      // Build transaction to update price feeds
      const transaction = await this.aptos.transaction.build.simple({
        sender: this.keeper.accountAddress,
        data: {
          function: `${this.pythContractAddress}::update_price_feeds`,
          functionArguments: [
            priceUpdateDataHex,
          ],
        },
      })

      // Submit transaction
      const committedTxn = await this.aptos.signAndSubmitTransaction({
        signer: this.keeper,
        transaction,
      })

      // Wait for transaction to be executed
      const executedTxn = await this.aptos.waitForTransaction({
        transactionHash: committedTxn.hash,
      })

      console.log(`✅ Price feeds updated on-chain: ${committedTxn.hash}`)
      return committedTxn.hash

    } catch (error) {
      console.error('❌ Error updating price feeds on-chain:', error)
      return null
    }
  }

  /**
   * Get latest price from on-chain Pyth contract
   * Step 3 of pull oracle pattern
   */
  async getPriceFromOnChain(priceId: string): Promise<number | null> {
    try {
      console.log(`📊 Getting price from on-chain contract for ${priceId}`)

      // Call view function to get latest price
      const response = await this.aptos.view({
        payload: {
          function: `${this.pythContractAddress}::get_price`,
          functionArguments: [priceId],
        },
      })

      if (!response || response.length === 0) {
        throw new Error('No price data returned from contract')
      }

      // Parse price from response (assuming it returns price in micro-dollars)
      const price = parseFloat(response[0] as string) / 1000000 // Convert from micro-dollars
      
      console.log(`✅ On-chain price: $${price.toFixed(6)}`)
      return price

    } catch (error) {
      console.error('❌ Error getting price from on-chain contract:', error)
      return null
    }
  }

  /**
   * Complete pull oracle flow: fetch -> update -> consume
   * This is the main method that implements the full pull oracle pattern
   */
  async executePullOracleFlow(priceId: string): Promise<PriceUpdateResult> {
    try {
      console.log(`🚀 Starting Pyth pull oracle flow for ${priceId}`)

      // Step 1: Fetch price data from Hermes
      const priceData = await this.fetchPriceFromHermes(priceId)
      if (!priceData) {
        return {
          success: false,
          error: 'Failed to fetch price data from Hermes'
        }
      }

      // Step 2: Update price feeds on-chain
      const transactionHash = await this.updatePriceFeedsOnChain([priceId])
      if (!transactionHash) {
        return {
          success: false,
          error: 'Failed to update price feeds on-chain'
        }
      }

      // Step 3: Get updated price from on-chain contract
      const onChainPrice = await this.getPriceFromOnChain(priceId)
      if (!onChainPrice) {
        return {
          success: false,
          error: 'Failed to get price from on-chain contract'
        }
      }

      console.log(`🎉 Pull oracle flow completed successfully!`)
      console.log(`   Hermes price: $${priceData.price.toFixed(6)}`)
      console.log(`   On-chain price: $${onChainPrice.toFixed(6)}`)
      console.log(`   Transaction: ${transactionHash}`)

      return {
        success: true,
        priceData: {
          ...priceData,
          price: onChainPrice, // Use on-chain price as final result
        },
        transactionHash,
      }

    } catch (error) {
      console.error('❌ Error in pull oracle flow:', error)
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }
    }
  }

  /**
   * Batch update multiple price feeds
   * Useful for updating multiple assets at once
   */
  async batchUpdatePriceFeeds(priceIds: string[]): Promise<PriceUpdateResult> {
    try {
      console.log(`🔄 Batch updating ${priceIds.length} price feeds`)

      // Step 1: Fetch all price data
      const priceDataPromises = priceIds.map(id => this.fetchPriceFromHermes(id))
      const priceDataResults = await Promise.all(priceDataPromises)
      
      const validPriceIds = priceIds.filter((_, index) => priceDataResults[index] !== null)
      
      if (validPriceIds.length === 0) {
        return {
          success: false,
          error: 'No valid price data found'
        }
      }

      // Step 2: Update all price feeds on-chain
      const transactionHash = await this.updatePriceFeedsOnChain(validPriceIds)
      if (!transactionHash) {
        return {
          success: false,
          error: 'Failed to update price feeds on-chain'
        }
      }

      // Step 3: Get all updated prices
      const onChainPrices = await Promise.all(
        validPriceIds.map(id => this.getPriceFromOnChain(id))
      )

      console.log(`✅ Batch update completed: ${transactionHash}`)

      return {
        success: true,
        transactionHash,
      }

    } catch (error) {
      console.error('❌ Error in batch update:', error)
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }
    }
  }

  /**
   * Get price update data for manual transaction building
   * Useful for custom transaction scenarios
   */
  async getPriceUpdateData(priceIds: string[]): Promise<string[] | null> {
    try {
      const priceUpdateData = await this.connection.getPriceUpdateData(priceIds)
      return priceUpdateData.map(data => 
        Buffer.from(data, 'base64').toString('hex')
      )
    } catch (error) {
      console.error('❌ Error getting price update data:', error)
      return null
    }
  }
}

// Export singleton instance
export const pythPullOracle = new PythPullOracleService()

// Export utility functions
export async function updatePythPriceFeeds(priceIds: string[]): Promise<PriceUpdateResult> {
  return pythPullOracle.batchUpdatePriceFeeds(priceIds)
}

export async function getPythPrice(priceId: string): Promise<PriceUpdateResult> {
  return pythPullOracle.executePullOracleFlow(priceId)
}
