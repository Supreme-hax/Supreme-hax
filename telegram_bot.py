import asyncio
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes

BOT_NAME = "S I G N A L Paid 📡"
BOTUSERNAME = "@signalphaxosbot"
API_TOKEN = "8487342536:AAEJGmLxNnUr560dDdTzlnZttubwLAJck"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"👋 স্বাগতম {BOT_NAME}-এ!\nআমার ইউজারনেম: {BOTUSERNAME}\nআমি তোমার সিগন্যাল পাঠানোর জন্য প্রস্তুত 📡"
    )

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("ℹ️ কমান্ড লিস্ট:\n/start - বট শুরু করো\n/help - সাহায্য দেখো")

if __name__ == "__main__":
    app = ApplicationBuilder().token(API_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    print(f"🚀 {BOT_NAME} চালু হয়েছে...")
    app.run_polling()
