#!/bin/bash

# Contract Initialization Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Initializing Orion Betting Contract${NC}"
echo "======================================"

# Read module address from .env.local
if [ ! -f .env.local ]; then
    echo -e "${RED}❌ .env.local not found. Please deploy the contract first.${NC}"
    exit 1
fi

MODULE_ADDRESS=$(grep NEXT_PUBLIC_MODULE_ADDRESS .env.local | cut -d '=' -f2)

if [ -z "$MODULE_ADDRESS" ] || [ "$MODULE_ADDRESS" = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef" ]; then
    echo -e "${RED}❌ Module address not set in .env.local. Please deploy the contract first.${NC}"
    exit 1
fi

echo -e "${GREEN}📍 Using module address: ${MODULE_ADDRESS}${NC}"

# Get current account address
CURRENT_ACCOUNT=$(aptos config show-profiles --profile default | grep account | cut -d ':' -f2 | tr -d ' ')

if [ -z "$CURRENT_ACCOUNT" ]; then
    echo -e "${RED}❌ No default account found. Please run 'aptos init' first.${NC}"
    exit 1
fi

echo -e "${GREEN}👤 Admin account: ${CURRENT_ACCOUNT}${NC}"

# Prompt for treasury address (default to admin)
echo ""
echo -e "${YELLOW}💰 Treasury address (press Enter to use admin address):${NC}"
read -r TREASURY_ADDRESS

if [ -z "$TREASURY_ADDRESS" ]; then
    TREASURY_ADDRESS=$CURRENT_ACCOUNT
fi

# Prompt for fee percentage
echo ""
echo -e "${YELLOW}💸 Fee percentage (default 2%):${NC}"
read -r FEE_PERCENT

if [ -z "$FEE_PERCENT" ]; then
    FEE_PERCENT=2
fi

# Convert percentage to basis points
FEE_BPS=$((FEE_PERCENT * 100))

echo ""
echo -e "${BLUE}📋 Contract Configuration:${NC}"
echo -e "   Admin: ${CURRENT_ACCOUNT}"
echo -e "   Treasury: ${TREASURY_ADDRESS}"
echo -e "   Fee: ${FEE_PERCENT}% (${FEE_BPS} basis points)"

echo ""
echo -e "${YELLOW}❓ Proceed with initialization? [y/N]${NC}"
read -r CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}⏹️  Initialization cancelled.${NC}"
    exit 0
fi

echo -e "${BLUE}🚀 Initializing contract...${NC}"

# Initialize the contract
aptos move run \
  --function-id "${MODULE_ADDRESS}::betting::init" \
  --args address:"${CURRENT_ACCOUNT}" u64:"${FEE_BPS}" address:"${TREASURY_ADDRESS}"

echo ""
echo -e "${GREEN}✅ Contract initialized successfully!${NC}"
echo ""
echo -e "${YELLOW}📋 What's next:${NC}"
echo "1. Start the development server: bun dev"
echo "2. Connect your wallet in the UI"
echo "3. Start betting rounds (admin only)"
echo ""
echo -e "${GREEN}🎉 Your Orion Betting DApp is ready!${NC}"
