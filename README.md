# 🏦 ₸USD Federal Meme Reserve

Autonomous monetary policy for the memecoin of record. A permissionless burn engine + custodied treasury management system for ₸USD (TurboUSD) on Base.

## 🏗 Architecture

### Smart Contracts (Base Mainnet)

**BurnEngine** — `0x996A533AF55F6E7230f44D9a36B21E659509122c`
- Permissionless hyperstructure. No owner, no admin, no pause, no upgrade.
- Claims Clanker LP fees → swaps WETH→₸USD → burns all ₸USD to `0xdead`
- Anyone can call `executeFullCycle()`
- Uses on-chain sqrtPriceX96 for slippage protection (3% max)

**TreasuryManager** — `0x93461176eb7740665DE023602A775aF696f06910`
- Owner + authorized operator pattern with hard-coded caps
- `buyback()` — Market buy ₸USD with WETH (0.5 ETH/action, 2 ETH/day caps)
- `burnHoldings()` — Burn all ₸USD held by treasury
- `addLiquidity()` — Concentrated liquidity provision
- `removeLiquidity()` — Owner only
- 30-min TWAP oracle for price-based actions
- 10-min operator cooldown

### Telegram Bot
- Node.js + grammy + viem
- Claude Sonnet API for satirical Fed-speak AI responses
- Dual hot wallets: burn caller + treasury operator
- FRED API macro data integration (CPI, Fed Funds Rate, M2, US Debt)
- FOMC calendar awareness

### SE2 Dashboard
- Real-time ₸USD price from sqrtPriceX96
- Total burned, burn engine cycles, treasury balances
- Read-only — uses local burner wallet for wallet connection

## 🔑 Key Addresses

| Contract | Address |
|----------|---------|
| ₸USD Token | `0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07` |
| WETH/₸USD Pool (1%) | `0xd013725b904e76394A3aB0334Da306C505D778F8` |
| BurnEngine | `0x996A533AF55F6E7230f44D9a36B21E659509122c` |
| TreasuryManager | `0x93461176eb7740665DE023602A775aF696f06910` |
| ClankerFeeLocker | `0xF3622742b1E446D92e45E22923Ef11C2fcD55D68` |

### Hot Wallets (need funding)
| Wallet | Address | Purpose |
|--------|---------|---------|
| Burn Caller | `0x52b26dB29BC46160270941e301CF6f0ea67f84C7` | Signs BurnEngine.executeFullCycle |
| Treasury Operator | `0x4e89764184AF782889D7F6711F5548e27203652a` | Signs TreasuryManager buyback/burn |

## 🚀 Setup

### Prerequisites
- Node.js 18+
- Foundry (`curl -L https://foundry.paradigm.xyz | bash`)

### Install
```bash
yarn install
```

### Run Tests (Base Fork)
```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd packages/foundry
forge test --fork-url https://base-mainnet.g.alchemy.com/v2/YOUR_KEY -vvv
```

### Run Dashboard
```bash
yarn start
```

### Bot Setup
```bash
cp .env.example .env
# Fill in API keys and wallet keys
cd packages/bot
npm install
npm start
```

## 📊 IPFS Dashboard

CID: `bafybeictsychbik6g6dst22oombjq7fjfwrxkb5lpbqt7q33eowqjq22gy`

## 🔥 Post-Deployment Steps

1. **Set BurnEngine as feeOwner** — Transfer Clanker LP fee ownership to BurnEngine contract
2. **Set treasury operator** — Call `TreasuryManager.setOperator(0x4e89764184AF782889D7F6711F5548e27203652a)`
3. **Fund hot wallets** — Send ~0.005 ETH to burn caller, ~0.01 ETH to treasury operator
4. **Configure bot** — Set Telegram bot token, Anthropic API key, FRED API key

## 🏗 Built With

- [Scaffold-ETH 2](https://github.com/scaffold-eth/scaffold-eth-2)
- [Foundry](https://book.getfoundry.sh/)
- [Uniswap V3](https://docs.uniswap.org/)
- [Clanker](https://clanker.gitbook.io/)
- [grammy](https://grammy.dev/)

## 📜 License

MIT
