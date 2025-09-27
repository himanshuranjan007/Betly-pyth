#!/bin/bash

# Complete Betly DApp Setup Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}🚀 Betly Betting DApp - Complete Setup${NC}"
echo "======================================"
echo ""

# Step 1: Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"

if ! command -v aptos &> /dev/null; then
    echo -e "${RED}❌ Aptos CLI not found. Installing...${NC}"
    curl -fsSL https://aptos.dev/scripts/install_cli.py | python3
    echo -e "${GREEN}✅ Aptos CLI installed${NC}"
fi

if ! command -v bun &> /dev/null && ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ Neither Bun nor npm found. Please install one of them.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites checked${NC}"
echo ""

# Step 2: Setup Aptos accounts
echo -e "${BLUE}Step 2: Setting up Aptos accounts...${NC}"

# Check if default profile exists
if ! aptos config show-profiles --profile default &> /dev/null; then
    echo -e "${YELLOW}🔧 Creating default account for admin...${NC}"
    aptos init --profile default --network testnet
    echo -e "${GREEN}✅ Admin account created${NC}"
else
    echo -e "${GREEN}✅ Admin account already exists${NC}"
fi

# Ask if user wants automated keeper
echo ""
echo -e "${YELLOW}❓ Do you want to set up automated round management (keeper)? [y/N]${NC}"
read -r SETUP_KEEPER

KEEPER_PRIVATE_KEY=""
if [[ $SETUP_KEEPER =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🔧 Creating keeper account...${NC}"
    aptos init --profile keeper --network testnet
    
    # Extract keeper private key
    KEEPER_PRIVATE_KEY=$(aptos config show-profiles --profile keeper | grep private_key | cut -d '"' -f 4)
    echo -e "${GREEN}✅ Keeper account created${NC}"
    echo -e "${BLUE}🔑 Keeper private key: ${KEEPER_PRIVATE_KEY}${NC}"
else
    echo -e "${YELLOW}⏭️  Skipping keeper setup (you can set up manual round management later)${NC}"
fi

echo ""

# Step 3: Deploy contract
echo -e "${BLUE}Step 3: Deploying Move contract...${NC}"

cd move
echo -e "${YELLOW}🔨 Compiling contract...${NC}"
aptos move compile

echo -e "${YELLOW}📦 Publishing to testnet...${NC}"
DEPLOY_OUTPUT=$(aptos move publish --named-addresses betly_betting=default --json)

# Extract deployed address
DEPLOYED_ADDRESS=$(echo $DEPLOY_OUTPUT | jq -r '.Result.changes[] | select(.type == "write_module") | .address' | head -1)

if [ "$DEPLOYED_ADDRESS" = "null" ] || [ -z "$DEPLOYED_ADDRESS" ]; then
    echo -e "${RED}❌ Failed to extract deployed address${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Contract deployed at: ${DEPLOYED_ADDRESS}${NC}"
cd ..

# Step 4: Create .env.local
echo -e "${BLUE}Step 4: Creating configuration...${NC}"

cat > .env.local << EOF
# Aptos Network Configuration
NEXT_PUBLIC_APTOS_NETWORK=testnet
NEXT_PUBLIC_APTOS_NODE_URL=https://fullnode.testnet.aptoslabs.com/v1

# Move Module Configuration
NEXT_PUBLIC_MODULE_ADDRESS=${DEPLOYED_ADDRESS}

# Pyth Configuration
NEXT_PUBLIC_PYTH_ENDPOINT=https://hermes.pyth.network
NEXT_PUBLIC_PYTH_APT_USD_PRICE_ID=0x03ae4db29ed4ae33d323568895aa00337e658e348b37509f5372ae51f0af00d5

# Keeper Configuration
KEEPER_PRIVATE_KEY=${KEEPER_PRIVATE_KEY}
ROUND_DURATION_SECONDS=300
EOF

echo -e "${GREEN}✅ Configuration created in .env.local${NC}"

# Step 5: Initialize contract
echo -e "${BLUE}Step 5: Initializing contract...${NC}"

ADMIN_ADDRESS=$(aptos config show-profiles --profile default | grep account | cut -d ':' -f 2 | tr -d ' ')

echo -e "${YELLOW}💰 Treasury address (press Enter to use admin address): ${ADMIN_ADDRESS}${NC}"
read -r TREASURY_ADDRESS

if [ -z "$TREASURY_ADDRESS" ]; then
    TREASURY_ADDRESS=$ADMIN_ADDRESS
fi

echo -e "${YELLOW}💸 Fee percentage (default 2%):${NC}"
read -r FEE_PERCENT

if [ -z "$FEE_PERCENT" ]; then
    FEE_PERCENT=2
fi

FEE_BPS=$((FEE_PERCENT * 100))

echo -e "${YELLOW}🚀 Initializing contract...${NC}"
aptos move run \
  --function-id "${DEPLOYED_ADDRESS}::betting::init" \
  --args address:"${ADMIN_ADDRESS}" u64:"${FEE_BPS}" address:"${TREASURY_ADDRESS}" \
  --profile default

echo -e "${GREEN}✅ Contract initialized${NC}"

# Step 6: Fund keeper account (if created)
if [[ $SETUP_KEEPER =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Step 6: Funding keeper account...${NC}"
    
    KEEPER_ADDRESS=$(aptos config show-profiles --profile keeper | grep account | cut -d ':' -f 2 | tr -d ' ')
    
    echo -e "${YELLOW}💰 The keeper account needs APT for gas fees.${NC}"
    echo -e "${YELLOW}   Keeper address: ${KEEPER_ADDRESS}${NC}"
    echo -e "${YELLOW}   Please send some APT to this address using the faucet or transfer from your main account.${NC}"
    echo ""
    echo -e "${BLUE}🚰 Aptos Testnet Faucet: https://faucet.testnet.aptoslabs.com${NC}"
    echo ""
    echo -e "${YELLOW}Press Enter when you've funded the keeper account...${NC}"
    read -r
fi

# Final summary
echo ""
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo "=================="
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo -e "   Admin Account: ${ADMIN_ADDRESS}"
echo -e "   Contract Address: ${DEPLOYED_ADDRESS}"
echo -e "   Treasury: ${TREASURY_ADDRESS}"
echo -e "   Fee: ${FEE_PERCENT}%"
if [[ $SETUP_KEEPER =~ ^[Yy]$ ]]; then
    echo -e "   Keeper: ${KEEPER_ADDRESS} (automated)"
else
    echo -e "   Keeper: Manual management"
fi
echo ""
echo -e "${YELLOW}🚀 Next steps:${NC}"
echo "1. Start the development server:"
echo -e "   ${BLUE}bun dev${NC}"
echo ""
echo "2. Open your browser:"
echo -e "   ${BLUE}http://localhost:3000${NC}"
echo ""
echo "3. Connect your wallet and start betting!"
echo ""
if [[ $SETUP_KEEPER =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}🤖 Your keeper will automatically manage rounds!${NC}"
else
    echo -e "${YELLOW}📝 To start rounds manually, use the admin functions in the UI${NC}"
fi
echo ""
echo -e "${PURPLE}Happy betting! 🎲${NC}"
