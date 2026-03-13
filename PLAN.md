# TurboUSD AI Federal Meme Reserve Agent
## Build Plan — Job #cv-1773321831954

> **Gist source:** https://gist.github.com/clawdbotatg/9daa051bd5b81c47151d511a27b02a82  
> **Build methodology:** [ethskills.com](https://ethskills.com) — fetch SKILL.md files at each phase, follow every step

---

## Overview

An autonomous AI agent on Base that manages a trustless ₸USD burn engine and a custodied treasury, connected via private Telegram. 

- **BurnEngine** — permissionless hyperstructure. Claims Clanker LP fees, swaps 100% WETH → ₸USD, burns all ₸USD in one atomic transaction. No owner, no admin, immutable forever.
- **TreasuryManager** — custodied treasury for discretionary monetary policy (buybacks, liquidity), with the agent operating within hard-coded onchain caps.
- **Telegram Bot** — private AI agent interface. Natural language → contract calls. Dual hot wallets. Claude Sonnet + real macro data (CPI, FOMC, stablecoin flows).
- **Public Dashboard** (Phase 2) — SE2 frontend showing burn stats, treasury state, policy feed.

---

## Token Reference

- **₸USD (TUSD):** `0x3d5e487b21e0569048c4d1a60e98c36e1b09db07` on Base
- **WETH (Base):** `0x4200000000000000000000000000000000000006`
- **DEAD address:** `0x000000000000000000000000000000000000dEaD`
- **Uniswap SwapRouter02 (Base):** per ethskills.com/addresses
- **Uniswap V3 NonfungiblePositionManager (Base):** per ethskills.com/addresses
- **ClankerFeeLocker (Base):** verify from Clanker docs at phase start
- **Pool fee tier:** 10000 (1%)

---

## Phase 1 — BurnEngine + Telegram Bot (3 CLAWD days)

### CLAWD Day 1 — BurnEngine.sol

**Skills:** `ethskills.com/ship/SKILL.md`, `ethskills.com/security/SKILL.md`, `ethskills.com/testing/SKILL.md`, `ethskills.com/addresses/SKILL.md`, `ethskills.com/building-blocks/SKILL.md`

#### BurnEngine.sol Spec

```
Immutable state (set at construction, never changeable):
- CLANKER_FEE_LOCKER: ClankerFeeLocker address on Base
- UNISWAP_ROUTER: SwapRouter02 address on Base
- WETH: 0x4200000000000000000000000000000000000006
- TUSD: 0x3d5e487b21e0569048c4d1a60e98c36e1b09db07
- DEAD: 0x000000000000000000000000000000000000dEaD
- POOL_FEE: 10000
- MAX_SLIPPAGE_BPS: 300 (3%)

Storage:
- uint256 public totalBurnedAllTime
- uint256 public lastCycleTimestamp
- uint256 public cycleCount

Access control: NONE. Pure hyperstructure.

Functions:
- executeFullCycle() — permissionless, atomic:
  1. claim(address(this), WETH) from ClankerFeeLocker
  2. claim(address(this), TUSD) from ClankerFeeLocker
  3. If WETH > 0: calculate minAmountOut from sqrtPriceX96 minus slippage, approve WETH to router, exactInputSingle() → TUSD
  4. Read total TUSD balance, transfer all to DEAD
  5. Update counters, emit CycleExecuted
  6. If WETH == 0 after claim: skip swap, only burn TUSD fees
  7. If total TUSD == 0 after all steps: revert (no-op protection)
- getStatus() view → (totalBurnedAllTime, lastCycleTimestamp, cycleCount, wethBalance, tusdBalance)

Events:
- CycleExecuted(wethClaimed, tusdClaimed, wethSwapped, tusdFromSwap, totalTusdBurned, totalBurnedAllTime, timestamp)

Security patterns:
- ReentrancyGuard + CEI on executeFullCycle()
- minAmountOut calculated ONCHAIN from pool sqrtPriceX96 (NOT passed by caller)
- No rescue function — hyperstructure guarantee
- No owner/admin/pause/upgrade/selfdestruct/delegatecall
```

#### Tasks
- [ ] Verify ClankerFeeLocker address + interface from Clanker docs
- [ ] Fetch verified Uniswap V3 addresses from ethskills.com/addresses
- [ ] Write BurnEngine.sol with full spec above
- [ ] Foundry unit tests: happy path, no WETH path, no TUSD path (revert), reentrancy
- [ ] Foundry fork tests against Base mainnet: real fee claim, real swap, real burn
- [ ] Deploy to Base mainnet with forge script
- [ ] Verify on Basescan (Sourcify exact_match preferred)
- [ ] Set BurnEngine as fee recipient (feeOwner) in ClankerFeeLocker
- [ ] Run live executeFullCycle() and confirm end-to-end
- [ ] Log deployment to nerve cord activity log

---

### CLAWD Day 2 — Telegram Bot Core

**Skills:** `ethskills.com/tools/SKILL.md`

#### Bot Architecture
- Framework: Node.js + grammy
- Auth: private chat, whitelisted by Telegram chat ID (owner only)
- Dual wallet setup via viem:
  - **Wallet #1** (burn caller) — signs BurnEngine.executeFullCycle() txs only
  - **Wallet #2** (treasury operator) — signs TreasuryManager txs (Phase 2)
  - Both funded with minimal ETH for gas
- LLM: Anthropic Claude Sonnet API, full context on every message
- Context injected per message: BurnEngine state, ₸USD price (sqrtPriceX96), pool depth, upcoming macro events

#### Command Routing
```
"Burn everything" → Wallet #1 calls BurnEngine.executeFullCycle()
"What's the status?" → getStatus(), format in Fed-speak
"What's the price?" → read sqrtPriceX96 from pool, compute (sqrtPriceX96/2^96)^2
"Draft a CPI statement" → generate satirical central bank commentary
```

#### Tasks
- [ ] grammy bot scaffold with private chat auth (whitelist by chat ID)
- [ ] viem wallet setup for Wallet #1 (generate + fund)
- [ ] BurnEngine read integration (getStatus, pool sqrtPriceX96 read)
- [ ] BurnEngine write integration (executeFullCycle via Wallet #1)
- [ ] Claude Sonnet integration with onchain context injection
- [ ] Natural language → intent routing
- [ ] End-to-end test: Telegram message → contract call → confirmed tx

---

### CLAWD Day 3 — Macro Data Feeds + Policy Engine

**Skills:** `ethskills.com/orchestration/SKILL.md`

#### Macro Integrations
- **FRED API** (free): CPI, Federal Funds Rate, M2 money supply, US debt
- **FOMC calendar**: pre-loaded schedule, "meeting mode" on FOMC days
- **Onchain**: ₸USD price via sqrtPriceX96, stablecoin TVL via DeFiLlama, holder count via Basescan API

#### Policy Playbook Config (off-chain JSON/YAML)
```yaml
rules:
  - trigger: cpi_above_expectations
    action: burn_cycle + hawkish_statement
  - trigger: cpi_below_expectations
    action: dovish_statement_only
  - trigger: fed_rate_cut
    action: treasury_buyback + easing_statement
  - trigger: fed_rate_hike
    action: treasury_buyback + tightening_statement
  - trigger: tusd_price_drop_20pct_24h
    action: emergency_stabilization_buyback (capped)
  - trigger: weekly_default
    action: burn_cycle
```
All rules respect TreasuryManager onchain caps — config cannot override contract limits.

#### Tasks
- [ ] FRED API integration (CPI, FFR, M2, debt)
- [ ] FOMC calendar loader + meeting mode detection
- [ ] DeFiLlama + Basescan API integration for onchain stats
- [ ] Policy playbook YAML config structure
- [ ] Agent context assembler (macro + onchain → system prompt context)
- [ ] Satirical statement generator (Fed-speak templates + Claude)
- [ ] End-to-end bot → macro data → statement generation test
- [ ] Manual policy trigger test: CPI event → burn cycle

---

## Phase 2 — TreasuryManager + Dashboard (5 CLAWD days)

### CLAWD Day 4 — TreasuryManager.sol

**Skills:** `ethskills.com/security/SKILL.md`, `ethskills.com/testing/SKILL.md`, `ethskills.com/building-blocks/SKILL.md`

#### TreasuryManager.sol Spec

```
State:
- owner: personal wallet (Ownable2Step for safe transfer)
- authorizedOperator: agent hot wallet #2 (swappable by owner)
- MAX_SPEND_PER_ACTION: hard-coded WETH cap per operation (immutable)
- MAX_SPEND_PER_DAY: hard-coded daily aggregate cap (immutable)
- COOLDOWN_PERIOD: minimum time between actions (immutable)
- dailySpent: rolling 24h spend tracker
- lastActionTimestamp: cooldown enforcement

Functions:
- buyback(uint256 amountIn) — operator/owner. Market buys TUSD with WETH. Enforces caps + cooldown.
- burnHoldings() — operator/owner. Sends all TUSD held by TreasuryManager to DEAD.
- addLiquidity(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) — operator/owner. Concentrated liquidity via NonfungiblePositionManager. Enforces caps.
- removeLiquidity(uint256 tokenId) — owner only. Withdraw LP position.
- withdrawFunds(address token, uint256 amount) — owner only. Emergency.
- setOperator(address newOperator) — owner only.
- revokeOperator() — owner only. Emergency disable.

Security:
- Hard-coded caps — compromised agent wallet damage is bounded
- 30-minute TWAP for all price-triggered actions (NOT spot price)
- revokeOperator() instant freeze
- LP removal is owner-only
- ReentrancyGuard + CEI on all external calls
```

#### Tasks
- [ ] TreasuryManager.sol full implementation
- [ ] Foundry unit tests: buyback, burnHoldings, addLiquidity, removeLiquidity, caps, cooldowns, operator access control, TWAP oracle
- [ ] Fork tests against Base mainnet: real WETH/TUSD swap, real LP add
- [ ] Deploy to Base mainnet

---

### CLAWD Day 5 — TreasuryManager Bot Integration

**Skills:** `ethskills.com/tools/SKILL.md`

#### Tasks
- [ ] Fund Wallet #2, set as authorizedOperator on TreasuryManager
- [ ] Bot commands for TreasuryManager: buyback, burnHoldings, addLiquidity, status
- [ ] Full operator flow test: Telegram → TreasuryManager tx via Wallet #2
- [ ] Emergency flow test: revokeOperator from owner wallet

---

### CLAWD Day 6 — SE2 Dashboard (Layout + Reads)

**Skills:** `ethskills.com/frontend-ux/SKILL.md`, `ethskills.com/frontend-playbook/SKILL.md`

#### Dashboard Pages
- **Main stats:** Total burned all time, burn rate (daily/weekly), last cycle, cycle count
- **Treasury:** WETH balance, TUSD balance, LP value, operator status
- **Price:** ₸USD price from sqrtPriceX96, pool depth
- Read-only — no wallet connection needed for viewers
- `onlyLocalBurnerWallet: true` — ALWAYS

#### Tasks
- [ ] SE2 scaffold setup, configure targetNetworks: [chains.base]
- [ ] BurnEngine contract reads (useScaffoldReadContract)
- [ ] TreasuryManager contract reads
- [ ] ₸USD price from sqrtPriceX96 display with USD conversion
- [ ] Dashboard layout: stats cards, burn counter

---

### CLAWD Day 7 — Policy Feed + BGIPFS Deploy

**Skills:** `ethskills.com/frontend-playbook/SKILL.md`, `ethskills.com/indexing/SKILL.md`, `ethskills.com/qa/SKILL.md`

#### Tasks
- [ ] Policy feed: chronological agent statements with BaseScan tx links
- [ ] Live holder count via Basescan API or The Graph
- [ ] OG card (1200x630, nothing clipped)
- [ ] BGIPFS build + upload: `NEXT_PUBLIC_IPFS_BUILD=true NEXT_PUBLIC_IGNORE_BUILD_ERROR=true yarn build && yarn bgipfs upload config init -u https://upload.bgipfs.com -k 4953f019-8b5d-4fb8-b799-f60417fe3197 && yarn bgipfs upload out`
- [ ] ENS subdomain setup (e.g. reserve.turbousd.eth)

---

### CLAWD Day 8 — TWAP + Automation + Docs

**Skills:** `ethskills.com/security/SKILL.md`, `ethskills.com/testing/SKILL.md`

#### Tasks
- [ ] 30-minute TWAP implementation for price-triggered policy rules
- [ ] Automated rule end-to-end test: CPI event → bot decision → contract tx
- [ ] Policy playbook final review
- [ ] Full README
- [ ] Log all deployed addresses + CIDs

---

## Deployed Addresses (fill as we go)

| Contract | Address | Network | Verified |
|---|---|---|---|
| BurnEngine | TBD | Base | — |
| TreasuryManager | TBD | Base | — |

---

## Hot Wallets

| Wallet | Role | Max Exposure |
|---|---|---|
| Wallet #1 (burn caller) | BurnEngine.executeFullCycle() only | ~$5 gas |
| Wallet #2 (treasury operator) | TreasuryManager within onchain caps | Bounded by caps |
| Personal wallet (Austin) | TreasuryManager owner only | Never touches bot |

---

## Key Ethskills References

Fetch fresh at each phase — don't use cached versions:

```
https://ethskills.com/ship/SKILL.md       — start here every phase
https://ethskills.com/security/SKILL.md   — before every deploy
https://ethskills.com/testing/SKILL.md    — Foundry testing patterns
https://ethskills.com/addresses/SKILL.md  — verified contract addresses
https://ethskills.com/building-blocks/SKILL.md — Uniswap V3 integration
https://ethskills.com/frontend-ux/SKILL.md — SE2 UX rules
https://ethskills.com/frontend-playbook/SKILL.md — IPFS + ENS deploy
https://ethskills.com/qa/SKILL.md         — pre-ship audit
```

---

## Notes

- **ENS:** Always use `.eth.link` — never `.eth.limo`
- **BGIPFS auth:** `X-API-Key` header (NOT Bearer)
- **Foundry PATH:** `export PATH="$HOME/.foundry/bin:$PATH"` before any forge/cast commands
- **useScaffoldWriteContract:** object form `{ contractName: "..." }` not string form
- **Uniswap V3 price:** ALWAYS sqrtPriceX96, NEVER pool balanceOf()
