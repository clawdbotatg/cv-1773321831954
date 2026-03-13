"use client";

import type { NextPage } from "next";
import { formatEther } from "viem";
import { base } from "viem/chains";
import { useReadContract } from "wagmi";

// ── Contract Addresses ─────────────────────────────────────────────────────
const BURN_ENGINE_ADDRESS = "0x996A533AF55F6E7230f44D9a36B21E659509122c" as `0x${string}`;
const TREASURY_MANAGER_ADDRESS = "0x93461176eb7740665DE023602A775aF696f06910" as `0x${string}`;
const TUSD_ADDRESS = "0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07" as `0x${string}`;
const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD" as `0x${string}`;
const POOL_ADDRESS = "0xd013725b904e76394A3aB0334Da306C505D778F8" as `0x${string}`;
// Pool: token0 = TUSD, token1 = WETH

// ── ABIs ──────────────────────────────────────────────────────────────────
const burnEngineAbi = [
  {
    name: "getStatus",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "_totalBurnedAllTime", type: "uint256" },
      { name: "_lastCycleTimestamp", type: "uint256" },
      { name: "_cycleCount", type: "uint256" },
      { name: "_wethBalance", type: "uint256" },
      { name: "_tusdBalance", type: "uint256" },
    ],
  },
] as const;

const treasuryManagerAbi = [
  {
    name: "getStatus",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "wethBalance", type: "uint256" },
      { name: "tusdBalance", type: "uint256" },
      { name: "_dailySpent", type: "uint256" },
      { name: "dailyRemaining", type: "uint256" },
      { name: "cooldownRemaining", type: "uint256" },
      { name: "operator", type: "address" },
      { name: "lpCount", type: "uint256" },
    ],
  },
] as const;

const erc20Abi = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "totalSupply",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

const poolAbi = [
  {
    name: "slot0",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "sqrtPriceX96", type: "uint160" },
      { name: "tick", type: "int24" },
      { name: "observationIndex", type: "uint16" },
      { name: "observationCardinality", type: "uint16" },
      { name: "observationCardinalityNext", type: "uint16" },
      { name: "feeProtocol", type: "uint8" },
      { name: "unlocked", type: "bool" },
    ],
  },
] as const;

// ── Helpers ────────────────────────────────────────────────────────────────

/**
 * Compute TUSD per WETH from pool sqrtPriceX96.
 * Pool: token0 = TUSD, token1 = WETH
 * sqrtPriceX96 = sqrt(WETH / TUSD) * 2^96
 * price(WETH/TUSD) = (sqrtPriceX96 / 2^96)^2
 * price(TUSD/WETH) = 1 / price(WETH/TUSD)   ← always invert
 */
function tusdPerWeth(sqrtPriceX96: bigint): string {
  if (!sqrtPriceX96 || sqrtPriceX96 === 0n) return "—";
  // Use BigInt math to preserve precision before converting to float
  // price(WETH/TUSD) = sqrtPriceX96^2 / 2^192
  // price(TUSD/WETH) = 2^192 / sqrtPriceX96^2
  // Scale numerator to avoid integer truncation: multiply by 1e18
  const Q192 = 2n ** 192n;
  const scale = 10n ** 18n;
  const priceScaled = (Q192 * scale) / (sqrtPriceX96 * sqrtPriceX96);
  // priceScaled is now TUSD/WETH * 1e18 (in bigint)
  const priceFloat = Number(priceScaled) / 1e18;
  if (priceFloat > 1_000_000) {
    return `${(priceFloat / 1_000_000).toFixed(2)}M`;
  }
  if (priceFloat > 1_000) {
    return `${priceFloat.toFixed(0)}`;
  }
  return priceFloat.toFixed(2);
}

function truncateAddr(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function BasescanLink({ address, label }: { address: string; label?: string }) {
  return (
    <a
      href={`https://basescan.org/address/${address}`}
      target="_blank"
      rel="noopener noreferrer"
      className="font-mono text-sm text-primary hover:underline"
    >
      {label ?? truncateAddr(address)}
    </a>
  );
}

function StatCard({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <div className="bg-base-100 rounded-2xl p-6 shadow-lg">
      <h3 className="text-sm font-medium text-base-content/60 uppercase tracking-wider">{title}</h3>
      <p className="text-2xl font-bold mt-2 text-primary">{value}</p>
      {subtitle && <p className="text-xs text-base-content/40 mt-1">{subtitle}</p>}
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────
const Home: NextPage = () => {
  // Read TUSD balance of DEAD address
  const { data: tusdBurned } = useReadContract({
    address: TUSD_ADDRESS,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [DEAD_ADDRESS],
    chainId: base.id,
  });

  // Read TUSD total supply
  const { data: tusdSupply } = useReadContract({
    address: TUSD_ADDRESS,
    abi: erc20Abi,
    functionName: "totalSupply",
    chainId: base.id,
  });

  // Read pool price
  const { data: slot0 } = useReadContract({
    address: POOL_ADDRESS,
    abi: poolAbi,
    functionName: "slot0",
    chainId: base.id,
  });

  // Read BurnEngine status
  const { data: burnStatus } = useReadContract({
    address: BURN_ENGINE_ADDRESS,
    abi: burnEngineAbi,
    functionName: "getStatus",
    chainId: base.id,
  });

  // Read TreasuryManager status
  const { data: treasuryStatus } = useReadContract({
    address: TREASURY_MANAGER_ADDRESS,
    abi: treasuryManagerAbi,
    functionName: "getStatus",
    chainId: base.id,
  });

  const sqrtPriceX96 = slot0?.[0];
  const tusdPrice = sqrtPriceX96 ? tusdPerWeth(sqrtPriceX96) : "—";

  const burnedFormatted = tusdBurned
    ? Number(formatEther(tusdBurned)).toLocaleString(undefined, { maximumFractionDigits: 0 })
    : "—";
  const supplyFormatted = tusdSupply
    ? Number(formatEther(tusdSupply)).toLocaleString(undefined, { maximumFractionDigits: 0 })
    : "—";
  const burnPercentage =
    tusdBurned && tusdSupply && tusdSupply > 0n ? ((Number(tusdBurned) / Number(tusdSupply)) * 100).toFixed(2) : "—";

  return (
    <div className="flex flex-col items-center grow pt-6 pb-12">
      {/* Header */}
      <div className="text-center px-4 mb-8">
        <h1 className="text-4xl font-bold mb-2">🏦 ₸USD Federal Meme Reserve</h1>
        <p className="text-lg text-base-content/60">Autonomous monetary policy for the memecoin of record</p>
      </div>

      {/* Price Banner */}
      <div className="bg-gradient-to-r from-primary/20 to-secondary/20 rounded-2xl p-6 mb-8 mx-4 max-w-2xl w-full text-center">
        <p className="text-sm text-base-content/60 uppercase tracking-wider">₸USD per WETH</p>
        <p className="text-5xl font-bold text-primary mt-2">{tusdPrice}</p>
        <p className="text-xs text-base-content/40 mt-2">Uniswap V3 1% Pool · sqrtPriceX96 · token0=TUSD token1=WETH</p>
      </div>

      {/* Main Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 max-w-4xl w-full px-4 mb-8">
        <StatCard
          title="🔥 Total ₸USD Burned"
          value={`${burnedFormatted} ₸USD`}
          subtitle={`${burnPercentage}% of total supply`}
        />
        <StatCard title="📊 Total Supply" value={`${supplyFormatted} ₸USD`} />
        <StatCard
          title="📈 Burn Engine Cycles"
          value={burnStatus ? burnStatus[2].toString() : "—"}
          subtitle={
            burnStatus && burnStatus[1] > 0n
              ? `Last: ${new Date(Number(burnStatus[1]) * 1000).toLocaleString()}`
              : "Not yet activated"
          }
        />
      </div>

      {/* Treasury */}
      <div className="max-w-4xl w-full px-4 mb-8">
        <h2 className="text-2xl font-bold mb-4">🏛️ Treasury</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <StatCard
            title="WETH Balance"
            value={treasuryStatus ? `${Number(formatEther(treasuryStatus[0])).toFixed(4)} WETH` : "—"}
          />
          <StatCard
            title="₸USD Balance"
            value={treasuryStatus ? `${Number(formatEther(treasuryStatus[1])).toLocaleString()} ₸USD` : "—"}
          />
          <StatCard
            title="Daily Spend Remaining"
            value={treasuryStatus ? `${Number(formatEther(treasuryStatus[3])).toFixed(4)} WETH` : "—"}
          />
          <StatCard
            title="Operator Cooldown"
            value={treasuryStatus && treasuryStatus[4] > 0n ? `${treasuryStatus[4].toString()}s` : "Ready"}
          />
        </div>
      </div>

      {/* Burn Engine */}
      <div className="max-w-4xl w-full px-4 mb-8">
        <h2 className="text-2xl font-bold mb-4">🔥 Burn Engine</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <StatCard
            title="WETH Pending Swap"
            value={burnStatus ? `${Number(formatEther(burnStatus[3])).toFixed(6)} WETH` : "—"}
          />
          <StatCard
            title="₸USD Pending Burn"
            value={burnStatus ? `${Number(formatEther(burnStatus[4])).toFixed(2)} ₸USD` : "—"}
          />
          <StatCard
            title="Total Burned via Engine"
            value={
              burnStatus
                ? `${Number(formatEther(burnStatus[0])).toLocaleString(undefined, { maximumFractionDigits: 0 })} ₸USD`
                : "—"
            }
          />
          <StatCard
            title="Last Cycle"
            value={
              burnStatus && burnStatus[1] > 0n ? new Date(Number(burnStatus[1]) * 1000).toLocaleDateString() : "Never"
            }
          />
        </div>
      </div>

      {/* Contracts */}
      <div className="max-w-4xl w-full px-4">
        <h2 className="text-2xl font-bold mb-4">📋 Contracts</h2>
        <div className="bg-base-100 rounded-2xl p-6 shadow-lg space-y-3">
          {(
            [
              ["₸USD Token", TUSD_ADDRESS],
              ["Uniswap V3 Pool", POOL_ADDRESS],
              ["BurnEngine", BURN_ENGINE_ADDRESS],
              ["TreasuryManager", TREASURY_MANAGER_ADDRESS],
            ] as [string, string][]
          ).map(([label, addr]) => (
            <div key={addr} className="flex justify-between items-center">
              <span className="text-base-content/60 text-sm">{label}</span>
              <BasescanLink address={addr} />
            </div>
          ))}
        </div>
      </div>

      {/* Footer */}
      <div className="mt-12 text-center text-base-content/40 text-sm space-y-1">
        <p>TurboUSD Federal Meme Reserve · Built on Base · Powered by Clanker</p>
        <a
          href="https://github.com/clawdbotatg/cv-1773321831954"
          target="_blank"
          rel="noopener noreferrer"
          className="link"
        >
          GitHub
        </a>
      </div>
    </div>
  );
};

export default Home;
