#!/bin/bash

# Prompt for old and new VM ID
read -p "Indtast den gamle VM ID: " OLD_ID
read -p "Indtast den nye VM ID: " NEW_ID

CONFIG_DIR="/etc/pve/qemu-server"
OLD_CONF="$CONFIG_DIR/$OLD_ID.conf"
NEW_CONF="$CONFIG_DIR/$NEW_ID.conf"

# Tjek om gammel VM eksisterer
if [ ! -f "$OLD_CONF" ]; then
  echo "❌ VM med ID $OLD_ID findes ikke."
  exit 1
fi

# Tjek om ny ID allerede er i brug
if [ -f "$NEW_CONF" ]; then
  echo "❌ En VM med ID $NEW_ID eksisterer allerede."
  exit 1
fi

# Stop VM
echo "🛑 Stopper VM $OLD_ID..."
qm stop "$OLD_ID"

# Flyt konfigurationsfil
echo "📁 Flytter konfigurationsfil til ny ID..."
mv "$OLD_CONF" "$NEW_CONF"

# Find og flyt diske
echo "🔍 Finder og flytter diskfiler..."
DISK_PATHS=$(grep -oP '(?<=file=)[^,]+' "$NEW_CONF")

for PATH in $DISK_PATHS; do
  if [[ "$PATH" == *"$OLD_ID"* ]]; then
    NEW_PATH="${PATH/$OLD_ID/$NEW_ID}"
    NEW_DIR=$(dirname "$NEW_PATH")

    echo "📂 Flytter $PATH til $NEW_PATH"
    mkdir -p "$NEW_DIR"
    mv "$PATH" "$NEW_PATH"

    # Opdater sti i config
    sed -i "s|$PATH|$NEW_PATH|g" "$NEW_CONF"
  fi
done

# Start den nye VM
echo "✅ Starter VM $NEW_ID..."
qm start "$NEW_ID"

echo "🎉 VM ID ændret fra $OLD_ID til $NEW_ID."
