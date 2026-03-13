import { Bot } from "grammy";
import { config } from "./config.js";
import { parseIntent, chat } from "./ai.js";
import {
  executeFullCycle,
  executeBuyback,
  executeBurnHoldings,
  getBurnEngineStatus,
  getTusdPrice,
  getTusdBurned,
  getTreasuryStatus,
} from "./contracts.js";
import { parseEther, formatEther } from "viem";

if (!config.botToken) {
  console.error("TELEGRAM_BOT_TOKEN not set. See .env.example");
  process.exit(1);
}

const bot = new Bot(config.botToken);

// Auth middleware: only allow owner
bot.use(async (ctx, next) => {
  if (config.ownerChatId && ctx.chat?.id.toString() !== config.ownerChatId) {
    await ctx.reply("⛔ Unauthorized. This is a private bot.");
    return;
  }
  await next();
});

// /start command
bot.command("start", async (ctx) => {
  await ctx.reply(
    "🏦 *₸USD Federal Meme Reserve Bot*\n\n" +
    "I manage the ₸USD burn engine and treasury.\n\n" +
    "Commands:\n" +
    "• *Burn everything* — Execute burn cycle\n" +
    "• *Status* — Get current status\n" +
    "• *Price* — Get ₸USD price\n" +
    "• *Buyback 0.1 ETH* — Treasury buyback\n" +
    "• *Statement* — Generate Fed statement\n" +
    "• Or just chat naturally!",
    { parse_mode: "Markdown" }
  );
});

// Handle all messages
bot.on("message:text", async (ctx) => {
  const text = ctx.message.text;
  const intent = parseIntent(text);

  try {
    switch (intent.action) {
      case "burn_cycle": {
        await ctx.reply("🔥 Executing burn cycle...");
        const result = await executeFullCycle();
        await ctx.reply(
          `✅ Burn cycle complete!\nTx: https://basescan.org/tx/${result.hash}\nStatus: ${result.status}`
        );
        break;
      }

      case "buyback": {
        const amountWei = parseEther(intent.amount);
        await ctx.reply(`💰 Executing buyback of ${intent.amount} WETH...`);
        const result = await executeBuyback(amountWei);
        await ctx.reply(
          `✅ Buyback complete!\nTx: https://basescan.org/tx/${result.hash}\nStatus: ${result.status}`
        );
        break;
      }

      case "burn_holdings": {
        await ctx.reply("🔥 Burning treasury ₸USD holdings...");
        const result = await executeBurnHoldings();
        await ctx.reply(
          `✅ Treasury burn complete!\nTx: https://basescan.org/tx/${result.hash}\nStatus: ${result.status}`
        );
        break;
      }

      case "status": {
        const [burnStatus, treasuryStatus, totalBurned] = await Promise.all([
          getBurnEngineStatus().catch(() => null),
          getTreasuryStatus().catch(() => null),
          getTusdBurned().catch(() => "N/A"),
        ]);

        let msg = "📊 *Status Report*\n\n";
        msg += `🔥 Total ₸USD Burned: ${totalBurned}\n`;

        if (burnStatus) {
          msg += `\n*Burn Engine:*\n`;
          msg += `• Cycles: ${burnStatus.cycleCount}\n`;
          msg += `• Engine burned: ${burnStatus.totalBurnedAllTime} ₸USD\n`;
          msg += `• Pending WETH: ${burnStatus.wethBalance}\n`;
        }

        if (treasuryStatus) {
          msg += `\n*Treasury:*\n`;
          msg += `• WETH: ${treasuryStatus.wethBalance}\n`;
          msg += `• ₸USD: ${treasuryStatus.tusdBalance}\n`;
          msg += `• Daily remaining: ${treasuryStatus.dailyRemaining} WETH\n`;
          msg += `• Cooldown: ${treasuryStatus.cooldownRemaining}s\n`;
        }

        await ctx.reply(msg, { parse_mode: "Markdown" });
        break;
      }

      case "price": {
        const price = await getTusdPrice();
        await ctx.reply(`📈 ₸USD Price: ${price.toFixed(6)} TUSD/WETH\n(from sqrtPriceX96 onchain)`);
        break;
      }

      case "statement": {
        await ctx.reply("📝 Drafting policy statement...");
        const statement = await chat(
          "Draft a formal FOMC-style press release about current ₸USD monetary policy. Include current data."
        );
        await ctx.reply(`🏛️ *FEDERAL MEME RESERVE — PRESS RELEASE*\n\n${statement}`, {
          parse_mode: "Markdown",
        });
        break;
      }

      default: {
        // Natural language chat with AI
        const response = await chat(text);
        await ctx.reply(response);
      }
    }
  } catch (error) {
    console.error("Error:", error);
    await ctx.reply(`❌ Error: ${error.message}`);
  }
});

bot.start();
console.log("🏦 ₸USD Federal Meme Reserve Bot is running");
