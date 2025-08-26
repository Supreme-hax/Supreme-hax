pkg install root-repo pkg install x11-repo
pkg install x11-repo
apt list --upgradable
ifconfig
modules/
#!/bin/bash
# Auto-Check + Auto-Fix Script for Local Trading Dashboard
echo "🔍 Starting Project Feature Check & Auto-Fix..."
echo "-----------------------------------"
PORT=8787
MODULES=("signal_engine" "telegram_bot" "indicators" "dashboard")
# 1. Server check
if lsof -i :$PORT >/dev/null 2>&1; then     echo "✅ Server running on port $PORT"; else     echo "❌ Server not running on port $PORT";     echo "   ⚙️ Attempting to start server...";     if [ -f "start.sh" ]; then         bash start.sh &         sleep 3;         lsof -i :$PORT >/dev/null && echo "   ✅ Server started" || echo "   ❌ Failed to start server";     else         echo "   ⚠️ No start.sh found, please start manually";     fi; fi
# 2. .env check
if [ -f ".env" ]; then     echo "✅ .env file found"; else     echo "❌ .env file missing";     echo "   ⚙️ Creating .env template..."
    cat <<EOL > .env
API_KEY=your_api_key_here
SECRET_KEY=your_secret_here
TOKEN=your_telegram_token_here
EOL
     echo "   ✅ .env template created"; fi
# 3. Core modules check
for mod in "${MODULES[@]}"; do     if find . -type f -name "${mod}.*" | grep -q .; then         echo "✅ Module '${mod}' found";     else         echo "❌ Module '${mod}' missing";         echo "   ⚙️ Creating placeholder for ${mod}.py";         echo "# ${mod} module placeholder" > "${mod}.py";     fi; done
# 4. PM2 check
if command -v pm2 >/dev/null 2>&1; then     echo "✅ PM2 installed"; else     echo "❌ PM2 not installed";     echo "   ⚙️ Installing PM2...";     pkg install -y nodejs >/dev/null 2>&1;     npm install -g pm2;     command -v pm2 >/dev/null && echo "   ✅ PM2 installed" || echo "   ❌ PM2 install failed"; fi
# 5. Git backup check
if [ -d ".git" ]; then     echo "✅ Git repository initialized"; else     echo "❌ Git not initialized";     echo "   ⚙️ Initializing Git...";     git init;     git add .;     git commit -m "Initial auto-backup"; fi
# 6. WebSocket / real-time data check
if grep -R "websocket" . >/dev/null 2>&1; then     echo "✅ WebSocket/real-time data code found"; else     echo "⚠️ No WebSocket/real-time code detected"; fi
echo "-----------------------------------"
echo "📋 Auto-check & fix complete."
pkg update -y && pkg install -y python nodejs && npm i -g pm2 http-server && ([ -d "$HOME/crypto-localengine" ] && cd "$HOME/crypto-localengine" || cd "$HOME") && pm2 delete localengine >/dev/null 2>&1 || true && pm2 delete telegram-bot >/dev/null 2>&1 || true && cat > telegram_bot.py <<'PY'
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
PY

pm2 start "http-server . -p 8787 --cors --host 0.0.0.0" --name localengine && pip install --upgrade pip >/dev/null 2>&1 && pip install python-telegram-bot==20.3 >/dev/null 2>&1 && pm2 start telegram_bot.py --name telegram-bot --interpreter python3 && pm2 save && pm2 status
pm2 start "http-server . -p 8787 --cors" --name localengine
http-server . -p 8787 --cors
pm2 start "http-server . -p 8787 --cors" --name localengine
bash start.sh
pkg update -y && pkg install -y python nodejs && npm i -g pm2 http-server && ([ -d "$HOME/crypto-localengine" ] && cd "$HOME/crypto-localengine" || cd "$HOME") && pm2 delete localengine >/dev/null 2>&1 || true && pm2 delete telegram-bot >/dev/null 2>&1 || true && cat > telegram_bot.py <<'PY'
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
PY

pm2 start "http-server . -p 8787 --cors --host 0.0.0.0" --name localengine && pip install --upgrade pip >/dev/null 2>&1 && pip install python-telegram-bot==20.3 >/dev/null 2>&1 && pm2 start telegram_bot.py --name telegram-bot --interpreter python3 && pm2 save && pm2 status
pm2 delete all && npm i -g http-server pm2 && pip install python-telegram-bot==20.3 && mkdir -p ~/crypto-localengine && cd ~/crypto-localengine && cat > telegram_bot.py <<'PY'
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes

BOT_NAME = "S I G N A L Paid 📡"
BOTUSERNAME = "@signalphaxosbot"
API_TOKEN = "8487342536:AAEJGmLxNnUr560dDdTzlnZttubwLAJck"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(f"👋 স্বাগতম {BOT_NAME}-এ!\nআমার ইউজারনেম: {BOTUSERNAME}\nআমি তোমার সিগন্যাল পাঠানোর জন্য প্রস্তুত 📡")

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("ℹ️ কমান্ড লিস্ট:\n/start - বট শুরু করো\n/help - সাহায্য দেখো")

if __name__ == "__main__":
    app = ApplicationBuilder().token(API_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    print(f"🚀 {BOT_NAME} চালু হয়েছে...")
    app.run_polling()
PY

pm2 start "http-server . -p 8787 --cors --host 0.0.0.0" --name localengine && pm2 start telegram_bot.py --name telegram-bot --interpreter python3 && pm2 save && pm2 status
pm2 status
pm2 logs telegram-bot
pm2 delete all && npm i -g http-server pm2 && pip install python-telegram-bot==20.3 && mkdir -p ~/crypto-localengine && cd ~/crypto-localengine && cat > telegram_bot.py <<'PY'
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes

BOT_NAME = "S I G N A L Paid 📡"
BOTUSERNAME = "@signalphaxosbot"
API_TOKEN = "8487342536:AAEJGmLxNnUr560dDdTzlnZttubwLAJck"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(f"👋 স্বাগতম {BOT_NAME}-এ!\nআমার ইউজারনেম: {BOTUSERNAME}\nআমি তোমার সিগন্যাল পাঠানোর জন্য প্রস্তুত 📡")

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("ℹ️ কমান্ড লিস্ট:\n/start - বট শুরু করো\n/help - সাহায্য দেখো")

if __name__ == "__main__":
    app = ApplicationBuilder().token(API_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    print(f"🚀 {BOT_NAME} চালু হয়েছে...")
    app.run_polling()
PY

pm2 start "http-server . -p 8787 --cors --host 0.0.0.0" --name localengine && pm2 start telegram_bot.py --name telegram-bot --interpreter python3 && pm2 save && pm2 status
pm2 status
pm2 logs telegram-bot
