#!/bin/bash

# Betly Betting Contract Deployment Script
set -e

echo "🚀 Deploying Betly Betting Contract to Aptos Testnet"
echo "================================================="

# Check if aptos CLI is installed
if ! command -v aptos &> /dev/null; then
    echo "❌ Aptos CLI not found. Please install it first:"
    echo "   curl -fsSL https://aptos.dev/scripts/install_cli.py | python3"
    exit 1
fi

# Navigate to move directory
cd move

# Check if Move.toml exists
if [ ! -f "Move.toml" ]; then
    echo "❌ Move.toml not found. Make sure you're in the project root."
    exit 1
fi

echo "📋 Checking Aptos CLI configuration..."
aptos config show-profiles

echo ""
echo "🔨 Compiling Move contract..."
aptos move compile

echo ""
echo "📦 Publishing contract to testnet..."
aptos move publish --named-addresses betly_betting=default

echo ""
echo "✅ Contract deployed successfully!"
echo ""
echo "📝 Next steps:"
echo "1. Copy the deployed address from the output above"
echo "2. Update NEXT_PUBLIC_MODULE_ADDRESS in your .env.local file"
echo "3. Initialize the contract with:"
echo "   aptos move run --function-id \"YOUR_ADDRESS::betting::init\" --args address:YOUR_ADMIN_ADDRESS u64:200 address:YOUR_TREASURY_ADDRESS"
echo ""
echo "🎉 Happy betting!"
