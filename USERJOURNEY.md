# User Journey — TurboUSD AI Federal Meme Reserve Agent

---

## Actors

- **Austin (Owner):** Controls TreasuryManager via personal wallet. Interacts via Telegram bot.
- **Anyone (Public):** Can call BurnEngine.executeFullCycle() permissionlessly. Views dashboard.
- **Agent (Hot Wallets):** Wallet #1 calls BurnEngine. Wallet #2 calls TreasuryManager as operator.

---

## Journey 1: Owner — First-Time Setup

**Goal:** Get the whole system running from zero.

1. Austin deploys BurnEngine.sol → gets contract address
2. Austin sets BurnEngine as `feeOwner` in ClankerFeeLocker for the ₸USD/WETH pool
3. Austin deploys TreasuryManager.sol with:
   - `owner` = personal wallet
   - `authorizedOperator` = Wallet #2 (hot wallet address)
4. Austin funds TreasuryManager with WETH for buybacks
5. Austin starts the Telegram bot (env vars: bot token, Wallet #1 key, Wallet #2 key, Anthropic API key, FRED API key)
6. Austin sends `/start` or any message in the private Telegram chat
7. Bot responds with system status: BurnEngine state, TreasuryManager balances, ₸USD price

**Edge cases:**
- If BurnEngine is not set as feeOwner yet → `executeFullCycle()` will succeed but claim 0 WETH (no-op cycle, reverts with "no TUSD to burn")
- If TreasuryManager has no WETH → buyback reverts with "insufficient balance"
- If bot env vars missing → bot fails to start, error logged to console

---

## Journey 2: Owner — Manual Burn Cycle via Telegram

**Goal:** Claim LP fees and burn ₸USD in one atomic transaction.

1. Austin types in Telegram: *"Burn everything"* (or similar intent)
2. Bot sends current status as context to Claude Sonnet: BurnEngine.getStatus(), ₸USD price from sqrtPriceX96, WETH balance in BurnEngine
3. Claude interprets intent → routes to `executeFullCycle()`
4. Bot broadcasts tx via Wallet #1, waits for confirmation
5. Bot responds with:
   - WETH claimed from fees
   - ₸USD claimed from fees
   - WETH swapped → ₸USD amount received
   - Total ₸USD burned this cycle
   - New `totalBurnedAllTime`
   - BaseScan tx link
6. Bot generates satirical Fed-speak statement: *"The Federal Meme Reserve has executed a historic tightening cycle..."*

**Edge cases:**
- No fees accumulated yet → `executeFullCycle()` reverts: "No TUSD to burn". Bot replies: *"No fees available yet. The market needs more time to generate liquidity revenue."*
- Slippage exceeded (price moved >3%) → swap reverts. Bot retries once; if still fails, reports: *"Slippage tolerance exceeded. Pool conditions unfavorable — try again shortly."*
- Wallet #1 has insufficient ETH for gas → tx fails. Bot alerts Austin: *"Wallet #1 needs gas funding."*
- Network congestion → tx pending >30s: Bot acknowledges the tx is submitted and shows hash

---

## Journey 3: Owner — Check System Status

**Goal:** Get a snapshot of the whole system.

1. Austin types: *"What's the status?"* or *"Give me a report"*
2. Bot assembles context:
   - BurnEngine: totalBurnedAllTime, cycleCount, lastCycleTimestamp
   - TreasuryManager: WETH balance, ₸USD balance, LP positions, dailySpent, cooldown remaining
   - Market: ₸USD price (sqrtPriceX96), pool depth, 24h price change
   - Macro: latest CPI, Federal Funds Rate, days until next FOMC meeting
3. Claude formats as satirical Fed statement:
   *"Reserve balance: 0.5 WETH. Monetary base: 47B ₸USD burned to date. CPI running hot at 3.2% — hawkish posture maintained."*

**Edge cases:**
- FRED API down → bot uses cached last-known values, notes *"Macro data unavailable — using last known figures"*
- Pool call fails → price shown as "unavailable"

---

## Journey 4: Owner — Treasury Buyback

**Goal:** Buy ₸USD with treasury WETH and hold (or burn it).

1. Austin types: *"Buy back 0.5 ETH worth of ₸USD"*
2. Bot identifies amount (0.5 WETH), passes to Claude with current caps + dailySpent context
3. Claude confirms intent → routes to `TreasuryManager.buyback(0.5 WETH)`
4. Bot calls `buyback` via Wallet #2
5. ₸USD received, held in TreasuryManager
6. Bot reports: bought amount, price, dailySpent updated, remaining daily cap
7. Austin can follow up: *"Burn the holdings"* → Bot calls `burnHoldings()`

**Edge cases:**
- Exceeds `MAX_SPEND_PER_ACTION` cap → contract reverts. Bot explains cap limit.
- Exceeds `MAX_SPEND_PER_DAY` → contract reverts. Bot explains daily limit + resets in X hours.
- Cooldown active → contract reverts. Bot says: *"Cooldown period active. Try again in X minutes."*
- Slippage too high → swap reverts. Bot reports and suggests trying later.
- Wallet #2 unauthorized (revokeOperator called) → tx reverts. Bot alerts: *"Operator access revoked — owner action required."*

---

## Journey 5: Owner — Add Liquidity

**Goal:** Deploy treasury WETH+₸USD as concentrated liquidity.

1. Austin types: *"Add liquidity around the current price"*
2. Bot reads current sqrtPriceX96, suggests tick range
3. Austin confirms or adjusts: *"Yeah, do it"*
4. Bot calls `TreasuryManager.addLiquidity(tickLower, tickUpper, amount0, amount1)` via Wallet #2
5. LP position minted, tokenId stored
6. Bot reports: tokenId, WETH+₸USD amounts added, price range

**Edge cases:**
- Insufficient token balance in TreasuryManager → reverts. Bot reports.
- Invalid tick range → reverts with Uniswap error. Bot: *"Invalid tick range — check price alignment."*
- Cap exceeded → reverts. Bot explains.

---

## Journey 6: Owner — Emergency: Freeze Agent

**Goal:** Immediately stop all agent activity if something goes wrong.

1. Austin types: *"Kill the agent"* or calls `revokeOperator()` directly from personal wallet via Basescan/Etherscan
2. Wallet #2 is now unauthorized — all future operator calls will revert
3. Austin can call `withdrawFunds()` to recover all WETH + ₸USD to personal wallet
4. Austin restarts with a fresh Wallet #2 via `setOperator(newAddress)`

**Edge cases:**
- Bot still running but can't execute → all write commands fail, bot reports reverts. This is expected.
- Austin recovers funds first, then reboots.

---

## Journey 7: Automated Policy Rule Trigger

**Goal:** Bot autonomously executes a burn based on macro data.

1. Bot polls FRED API — detects CPI release: actual > expected
2. Policy playbook rule: `cpi_above_expectations` → `burn_cycle + hawkish_statement`
3. Bot calls `BurnEngine.executeFullCycle()` via Wallet #1 automatically
4. Bot sends Telegram message to Austin: *"[AUTO] CPI came in hot at 3.8% (exp 3.2%). Tightening cycle executed. 12.4M ₸USD burned. See tx: [hash]"*
5. Bot generates and sends full satirical FOMC-style statement

**Edge cases:**
- FRED API returns stale data → bot checks timestamp, skips if data >24h old
- Rule fires but no fees accumulated → executeFullCycle reverts. Bot logs and moves on.
- Austin has disabled auto-rules in config → bot sends notification only, no tx

---

## Journey 8: Public User — View Dashboard (Phase 2)

**Goal:** Anyone visits the public dashboard to check burn stats.

1. User visits `reserve.turbousd.eth.link` (or ENS subdomain)
2. Page loads (no wallet needed):
   - **Total burned:** live read from `BurnEngine.totalBurnedAllTime`
   - **Burn rate:** derived from event history or cycleCount + timestamps
   - **Treasury:** WETH balance, ₸USD balance, LP value (via NonfungiblePositionManager position reads)
   - **₸USD price:** real-time from pool sqrtPriceX96
   - **Policy feed:** chronological list of agent statements with BaseScan tx links
3. User clicks a policy statement → opens BaseScan tx

**Edge cases:**
- Wrong network in wallet (if they connect) → RainbowKit shows "Switch to Base" prompt
- No wallet → all reads work fine (read-only)
- RPC rate limit → page falls back to cached last-known values with "data may be delayed" notice
- BGIPFS node slow → page loads slowly; no impact on contract data

---

## Journey 9: Public User — Permissionless Burn

**Goal:** Anyone triggers a burn cycle (hyperstructure guarantee).

1. User finds BurnEngine contract address (README, dashboard, BaseScan)
2. User calls `executeFullCycle()` directly on BaseScan or via their own script
3. Fees claimed, WETH swapped, ₸USD burned — atomic, no trust required
4. User gets gas refund equivalent in MEV (if they're a bot) or just does it for the ecosystem

**Edge cases:**
- No fees to claim → reverts with "No TUSD to burn". User pays gas for revert.
- Slippage >3% at moment of call → reverts. User retries when pool conditions normalize.
- Front-run sandwich attack → bounded by 3% slippage. Burn still executes (slightly less efficient).

---

## Happy Path Summary

```
Setup:     Deploy BurnEngine → set feeOwner → Deploy TreasuryManager → fund → start bot
Daily:     Telegram: "burn" → bot calls executeFullCycle() → reports + Fed statement
Weekly:    Bot auto-executes burn on schedule regardless of macro events
Policy:    CPI/FOMC data triggers burns/buybacks per playbook rules
Emergency: revokeOperator() → withdrawFunds() → system safe
Dashboard: Anyone views live stats at reserve.turbousd.eth.link
```
