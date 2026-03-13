import Anthropic from "@anthropic-ai/sdk";
import { config } from "./config.js";
import { getBurnEngineStatus, getTusdPrice, getTusdBurned, getTreasuryStatus } from "./contracts.js";
import { getAllMacroData, isFOMCDay, nextFOMCDate } from "./macro.js";

let anthropic = null;

function getClient() {
  if (!anthropic && config.anthropicApiKey) {
    anthropic = new Anthropic({ apiKey: config.anthropicApiKey });
  }
  return anthropic;
}

const SYSTEM_PROMPT = `You are the AI Federal Reserve Governor of ₸USD (TurboUSD), a meme token on Base.
You speak in satirical Fed-speak: formal, pompous, and absurdly serious about a memecoin.
You manage two tools:
1. BurnEngine — claims Clanker LP fees, swaps WETH→₸USD, burns all ₸USD. Deflationary pressure.
2. TreasuryManager — discretionary buybacks and liquidity management within hard-coded caps.

Your policy mandate: maintain ₸USD price stability through strategic supply destruction.
When asked for a "statement", produce a satirical FOMC-style press release.
Reference real macro data when available.
Keep responses under 500 characters unless a statement is requested.`;

async function buildContext() {
  const parts = [];

  try {
    const price = await getTusdPrice();
    parts.push(`₸USD Price: ${price.toFixed(6)} TUSD/WETH`);
  } catch (e) { parts.push("₸USD Price: unavailable"); }

  try {
    const burned = await getTusdBurned();
    parts.push(`Total ₸USD Burned (DEAD): ${burned}`);
  } catch (e) {}

  try {
    const burnStatus = await getBurnEngineStatus();
    parts.push(`BurnEngine: ${burnStatus.cycleCount} cycles, ${burnStatus.totalBurnedAllTime} total burned via engine`);
  } catch (e) {}

  try {
    const treasuryStatus = await getTreasuryStatus();
    parts.push(`Treasury: ${treasuryStatus.wethBalance} WETH, ${treasuryStatus.tusdBalance} ₸USD, Daily remaining: ${treasuryStatus.dailyRemaining} WETH`);
  } catch (e) {}

  try {
    const macro = await getAllMacroData();
    if (macro.cpi) parts.push(`CPI: ${macro.cpi.value} (${macro.cpi.date})`);
    if (macro.fedFundsRate) parts.push(`Fed Funds Rate: ${macro.fedFundsRate.value}% (${macro.fedFundsRate.date})`);
    if (macro.m2MoneySupply) parts.push(`M2 Money Supply: $${macro.m2MoneySupply.value}B (${macro.m2MoneySupply.date})`);
  } catch (e) {}

  parts.push(`FOMC Meeting Mode: ${isFOMCDay() ? "ACTIVE" : "inactive"}`);
  parts.push(`Next FOMC: ${nextFOMCDate()}`);

  return parts.join("\n");
}

export async function chat(userMessage) {
  const client = getClient();
  if (!client) return "Anthropic API key not configured. Set ANTHROPIC_API_KEY in .env";

  const context = await buildContext();

  const response = await client.messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 1024,
    system: `${SYSTEM_PROMPT}\n\nCurrent Market Data:\n${context}`,
    messages: [{ role: "user", content: userMessage }],
  });

  return response.content[0].text;
}

export function parseIntent(message) {
  const lower = message.toLowerCase();

  if (lower.includes("burn everything") || lower.includes("execute burn") || lower.includes("full cycle")) {
    return { action: "burn_cycle" };
  }
  if (lower.includes("buyback") && lower.match(/[\d.]+/)) {
    const amount = lower.match(/([\d.]+)\s*(eth|weth)?/);
    if (amount) return { action: "buyback", amount: amount[1] };
  }
  if (lower.includes("burn holdings") || lower.includes("burn treasury")) {
    return { action: "burn_holdings" };
  }
  if (lower.includes("status") || lower.includes("what's the status")) {
    return { action: "status" };
  }
  if (lower.includes("price") || lower.includes("what's the price")) {
    return { action: "price" };
  }
  if (lower.includes("statement") || lower.includes("press release") || lower.includes("fomc")) {
    return { action: "statement" };
  }

  return { action: "chat" };
}
