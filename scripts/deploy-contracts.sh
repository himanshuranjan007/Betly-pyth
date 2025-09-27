#!/bin/bash

# Orion Betting Contract Deployment Script
set -e

echo "🚀 Deploying Orion Betting Contracts to Aptos Testnet"
echo "====================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if aptos CLI is installed
if ! command -v aptos &> /dev/null; then
    echo -e "${RED}❌ Aptos CLI not found. Please install it first:${NC}"
    echo "   curl -fsSL https://aptos.dev/scripts/install_cli.py | python3"
    exit 1
fi

# Navigate to move directory
cd move

echo -e "${BLUE}📋 Checking Aptos CLI configuration...${NC}"
aptos config show-profiles

echo -e "${BLUE}🔨 Compiling Move contract...${NC}"
aptos move compile

echo -e "${BLUE}📦 Publishing contract to testnet...${NC}"
DEPLOY_OUTPUT=$(aptos move publish --named-addresses orion_betting=default --json)

# Extract deployed address from output
DEPLOYED_ADDRESS=$(echo $DEPLOY_OUTPUT | jq -r '.Result.changes[] | select(.type == "write_module") | .address' | head -1)

if [ "$DEPLOYED_ADDRESS" = "null" ] || [ -z "$DEPLOYED_ADDRESS" ]; then
    echo -e "${RED}❌ Failed to extract deployed address from output${NC}"
    echo "Deploy output: $DEPLOY_OUTPUT"
    exit 1
fi

echo -e "${GREEN}✅ Contract deployed successfully!${NC}"
echo -e "${GREEN}📍 Contract Address: ${DEPLOYED_ADDRESS}${NC}"

# Update .env.local
cd ..
echo -e "${BLUE}🔧 Updating .env.local...${NC}"

if [ ! -f .env.local ]; then
    cp env.example .env.local
    echo -e "${YELLOW}📄 Created .env.local from template${NC}"
fi

# Update the module address in .env.local
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/NEXT_PUBLIC_MODULE_ADDRESS=.*/NEXT_PUBLIC_MODULE_ADDRESS=${DEPLOYED_ADDRESS}/" .env.local
else
    # Linux
    sed -i "s/NEXT_PUBLIC_MODULE_ADDRESS=.*/NEXT_PUBLIC_MODULE_ADDRESS=${DEPLOYED_ADDRESS}/" .env.local
fi

echo -e "${GREEN}✅ Updated .env.local with deployed address${NC}"

echo ""
echo -e "${YELLOW}📋 Next steps:${NC}"
echo "1. Initialize the contract:"
echo -e "   ${BLUE}aptos move run --function-id \"${DEPLOYED_ADDRESS}::betting::init\" \\${NC}"
echo -e "   ${BLUE}     --args address:YOUR_ADMIN_ADDRESS u64:200 address:YOUR_TREASURY_ADDRESS${NC}"
echo ""
echo "2. Start the development server:"
echo -e "   ${BLUE}bun dev${NC}"
echo ""
echo -e "${GREEN}🎉 Deployment complete! Your DApp is ready to use.${NC}"
