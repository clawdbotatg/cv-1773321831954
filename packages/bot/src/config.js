import "dotenv/config";

export const config = {
  // Telegram
  botToken: process.env.TELEGRAM_BOT_TOKEN,
  ownerChatId: process.env.OWNER_CHAT_ID,

  // RPC
  rpcUrl: process.env.RPC_URL || "https://base-mainnet.g.alchemy.com/v2/YOUR_KEY",

  // Wallets
  burnCallerPrivateKey: process.env.BURN_CALLER_PRIVATE_KEY,
  treasuryOperatorPrivateKey: process.env.TREASURY_OPERATOR_PRIVATE_KEY,

  // Contracts (defaults to deployed Base mainnet addresses)
  burnEngineAddress: process.env.BURN_ENGINE_ADDRESS || "0x996A533AF55F6E7230f44D9a36B21E659509122c",
  treasuryManagerAddress: process.env.TREASURY_MANAGER_ADDRESS || "0x93461176eb7740665DE023602A775aF696f06910",
  tusdAddress: "0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07",
  wethAddress: "0x4200000000000000000000000000000000000006",
  poolAddress: "0xd013725b904e76394A3aB0334Da306C505D778F8",
  deadAddress: "0x000000000000000000000000000000000000dEaD",

  // AI
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,

  // Macro data
  fredApiKey: process.env.FRED_API_KEY,
};
