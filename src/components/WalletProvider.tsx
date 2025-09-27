'use client'

import { AptosWalletAdapterProvider } from '@aptos-labs/wallet-adapter-react'
import { Network } from '@aptos-labs/ts-sdk'
import { config } from '@/lib/config'

export function WalletProvider({ children }: { children: React.ReactNode }) {
  return (
    <AptosWalletAdapterProvider
      plugins={[]}
      autoConnect={true}
      dappConfig={{
        network: config.aptos.network as Network,
        aptosConnectDappId: 'orion-betting-dapp'
      }}
    >
      {children}
    </AptosWalletAdapterProvider>
  )
}
