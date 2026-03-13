import { createPublicClient, createWalletClient, http, formatEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { base } from "viem/chains";
import { config } from "./config.js";

// ABIs
const burnEngineAbi = [
  { name: "executeFullCycle", type: "function", stateMutability: "nonpayable", inputs: [], outputs: [] },
  {
    name: "getStatus", type: "function", stateMutability: "view", inputs: [],
    outputs: [
      { name: "_totalBurnedAllTime", type: "uint256" },
      { name: "_lastCycleTimestamp", type: "uint256" },
      { name: "_cycleCount", type: "uint256" },
      { name: "_wethBalance", type: "uint256" },
      { name: "_tusdBalance", type: "uint256" },
    ],
  },
  {
    name: "getCurrentPrice", type: "function", stateMutability: "view", inputs: [],
    outputs: [{ name: "price", type: "uint256" }],
  },
];

const treasuryManagerAbi = [
  {
    name: "buyback", type: "function", stateMutability: "nonpayable",
    inputs: [{ name: "amountIn", type: "uint256" }], outputs: [],
  },
  { name: "burnHoldings", type: "function", stateMutability: "nonpayable", inputs: [], outputs: [] },
  {
    name: "getStatus", type: "function", stateMutability: "view", inputs: [],
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
];

const erc20Abi = [
  {
    name: "balanceOf", type: "function", stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
];

const poolAbi = [
  {
    name: "slot0", type: "function", stateMutability: "view", inputs: [],
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
];

// Clients
export const publicClient = createPublicClient({
  chain: base,
  transport: http(config.rpcUrl),
});

export function createBurnWallet() {
  if (!config.burnCallerPrivateKey) return null;
  const account = privateKeyToAccount(config.burnCallerPrivateKey);
  return createWalletClient({ account, chain: base, transport: http(config.rpcUrl) });
}

export function createTreasuryWallet() {
  if (!config.treasuryOperatorPrivateKey) return null;
  const account = privateKeyToAccount(config.treasuryOperatorPrivateKey);
  return createWalletClient({ account, chain: base, transport: http(config.rpcUrl) });
}

// Read functions
export async function getBurnEngineStatus() {
  const status = await publicClient.readContract({
    address: config.burnEngineAddress,
    abi: burnEngineAbi,
    functionName: "getStatus",
  });
  return {
    totalBurnedAllTime: formatEther(status[0]),
    lastCycleTimestamp: Number(status[1]),
    cycleCount: Number(status[2]),
    wethBalance: formatEther(status[3]),
    tusdBalance: formatEther(status[4]),
  };
}

export async function getTusdPrice() {
  const slot0 = await publicClient.readContract({
    address: config.poolAddress,
    abi: poolAbi,
    functionName: "slot0",
  });
  const sqrtPriceX96 = slot0[0];
  // Pool: token0=TUSD, token1=WETH
  // sqrtPriceX96 = sqrt(WETH/TUSD) * 2^96
  // TUSD/WETH = 2^192 / sqrtPriceX96^2  (always invert)
  const Q192 = 2n ** 192n;
  const scale = 10n ** 18n;
  const priceScaled = (Q192 * scale) / (sqrtPriceX96 * sqrtPriceX96);
  return Number(priceScaled) / 1e18; // TUSD per WETH
}

export async function getTusdBurned() {
  const balance = await publicClient.readContract({
    address: config.tusdAddress,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [config.deadAddress],
  });
  return formatEther(balance);
}

export async function getTreasuryStatus() {
  const status = await publicClient.readContract({
    address: config.treasuryManagerAddress,
    abi: treasuryManagerAbi,
    functionName: "getStatus",
  });
  return {
    wethBalance: formatEther(status[0]),
    tusdBalance: formatEther(status[1]),
    dailySpent: formatEther(status[2]),
    dailyRemaining: formatEther(status[3]),
    cooldownRemaining: Number(status[4]),
    operator: status[5],
    lpCount: Number(status[6]),
  };
}

// Write functions
export async function executeFullCycle() {
  const wallet = createBurnWallet();
  if (!wallet) throw new Error("Burn wallet not configured");
  const hash = await wallet.writeContract({
    address: config.burnEngineAddress,
    abi: burnEngineAbi,
    functionName: "executeFullCycle",
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return { hash, status: receipt.status };
}

export async function executeBuyback(amountInWei) {
  const wallet = createTreasuryWallet();
  if (!wallet) throw new Error("Treasury wallet not configured");
  const hash = await wallet.writeContract({
    address: config.treasuryManagerAddress,
    abi: treasuryManagerAbi,
    functionName: "buyback",
    args: [amountInWei],
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return { hash, status: receipt.status };
}

export async function executeBurnHoldings() {
  const wallet = createTreasuryWallet();
  if (!wallet) throw new Error("Treasury wallet not configured");
  const hash = await wallet.writeContract({
    address: config.treasuryManagerAddress,
    abi: treasuryManagerAbi,
    functionName: "burnHoldings",
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return { hash, status: receipt.status };
}
