export const config = {
  aptos: {
    network: (process.env.NEXT_PUBLIC_APTOS_NETWORK as 'testnet' | 'mainnet') || 'testnet',
    nodeUrl: process.env.NEXT_PUBLIC_APTOS_NODE_URL || 'https://api.testnet.aptoslabs.com/v1',
    apiKey: process.env.NEXT_PUBLIC_APTOS_API_KEY || 'AG-2MB32AJQVQZDCSGYFRMTOZC1GKAHEGUSW',
    moduleAddress: process.env.NEXT_PUBLIC_MODULE_ADDRESS || '0x521ede792ad5eee5aece4e9e14bdf3c931f5e8d54939efc39b38afd7dd872cea',
  },
  pyth: {
    endpoint: process.env.NEXT_PUBLIC_PYTH_ENDPOINT || 'https://hermes.pyth.network',
    aptUsdPriceId: process.env.NEXT_PUBLIC_PYTH_APT_USD_PRICE_ID || '0x03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5',
  },
  keeper: {
    privateKey: process.env.KEEPER_PRIVATE_KEY || '',
    roundDuration: parseInt(process.env.ROUND_DURATION_SECONDS || '300'),
  },
} as const
