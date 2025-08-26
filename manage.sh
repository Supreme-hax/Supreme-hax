#!/bin/bash
# manage.sh — Smart Auto-Register + Server & Bot Manager
# Author: Ah + Copilot

SERVER_NAME="localengine"
SERVER_FILE="server.js"          # তোমার সার্ভারের এন্ট্রি ফাইল
BOT_PM2_NAME="telegram-bot"
BOT_FILE="bot.js"                # তোমার বটের এন্ট্রি ফাইল

BOT_NAME="S I G N A L Paid 📡"
BOTUSERNAME="@signalphaxosbot"
API_TOKEN="8487342536:AAEJGmLxNnUr560dDdTzlnZttubwLAJck"

BACKUP_DIR="backup"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

# .env ফাইল আপডেট
update_env() {
  echo "BOT_NAME=\"$BOT_NAME\"" > .env
  echo "BOTUSERNAME=\"$BOTUSERNAME\"" >> .env
  echo "API_TOKEN=\"$API_TOKEN\"" >> .env
  echo "✅ .env ফাইল আপডেট হয়েছে"
}

# প্রসেস আছে কিনা চেক
process_exists() {
  pm2 describe "$1" > /dev/null 2>&1
}

case "$1" in
  start)
    update_env
    echo "🚀 সার্ভার ও বট চালু হচ্ছে..."
    if ! process_exists "$SERVER_NAME"; then
      pm2 start "$SERVER_FILE" --name "$SERVER_NAME"
    else
      pm2 start "$SERVER_NAME"
    fi
    if ! process_exists "$BOT_PM2_NAME"; then
      pm2 start "$BOT_FILE" --name "$BOT_PM2_NAME" --update-env
    else
      pm2 start "$BOT_PM2_NAME" --update-env
    fi
    pm2 save
    ;;
  stop)
    echo "🛑 সার্ভার ও বট বন্ধ হচ্ছে..."
    pm2 stop "$SERVER_NAME" 2>/dev/null
    pm2 stop "$BOT_PM2_NAME" 2>/dev/null
    ;;
  restart)
    update_env
    echo "♻️ সার্ভার ও বট রিস্টার্ট হচ্ছে..."
    if process_exists "$SERVER_NAME"; then
      pm2 restart "$SERVER_NAME"
    else
      pm2 start "$SERVER_FILE" --name "$SERVER_NAME"
    fi
    if process_exists "$BOT_PM2_NAME"; then
      pm2 restart "$BOT_PM2_NAME" --update-env
    else
      pm2 start "$BOT_FILE" --name "$BOT_PM2_NAME" --update-env
    fi
    pm2 save
    ;;
  logs)
    echo "📜 লাইভ লগ দেখা হচ্ছে..."
    pm2 logs
    ;;
  status)
    echo "📊 প্রসেস স্ট্যাটাস:"
    pm2 status
    ;;
  backup)
    echo "💾 ব্যাকআপ তৈরি হচ্ছে..."
    mkdir -p "$BACKUP_DIR"
    zip -r "$BACKUP_DIR/project_$DATE.zip" . -x "$BACKUP_DIR/*"
    echo "✅ ব্যাকআপ সংরক্ষিত: $BACKUP_DIR/project_$DATE.zip"
    ;;
  restore)
    if [ -z "$2" ]; then
      echo "❌ রিস্টোর করতে ব্যাকআপ ফাইলের নাম দিন"
      echo "উদাহরণ: ./manage.sh restore backup/project_2025-08-26_21-44-00.zip"
    else
      echo "♻️ ব্যাকআপ রিস্টোর হচ্ছে..."
      unzip -o "$2" -d .
      echo "✅ রিস্টোর সম্পন্ন"
    fi
    ;;
  *)
    echo "ব্যবহার: ./manage.sh {start|stop|restart|logs|status|backup|restore <file>}"
    ;;
esac
