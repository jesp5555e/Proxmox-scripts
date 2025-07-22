#!/bin/bash

echo "=== Proxmox VM ID Ændrer ==="
read -p "Indtast nuværende VM ID: " OLD_ID
read -p "Indtast nyt ønsket VM ID: " NEW_ID

CONF_DIR="/etc/pve/qemu-server"
OLD_CONF="$CONF_DIR/$OLD_ID.conf"
NEW_CONF="$CONF_DIR/$NEW_ID.conf"

# Tjek om gamle konfiguration findes
if [ ! -f "$OLD_CONF" ]; then
    echo "❌ VM med ID $OLD_ID findes ikke."
    exit 1
fi

# Tjek om nyt ID allerede er i brug
if [ -f "$NEW_CONF" ]; then
    echo "❌ En VM med ID $NEW_ID eksisterer allerede."
    exit 1
fi

echo "▶ Stopper VM $OLD_ID ..."
qm stop "$OLD_ID"

echo "▶ Flytter konfigurationsfil ..."
mv "$OLD_CONF" "$NEW_CONF"

# Find og flyt diskfiler
# Kig i alle mulige lagringsmapper
STORAGE_PATHS=("/var/lib/vz/images" "/mnt/pve" "/dev/pve") # Udvid evt. disse

for STORAGE_BASE in "${STORAGE_PATHS[@]}"; do
    if [ -d "$STORAGE_BASE/$OLD_ID" ]; then
        echo "▶ Flytter diske fra $STORAGE_BASE/$OLD_ID til $STORAGE_BASE/$NEW_ID"
        mv "$STORAGE_BASE/$OLD_ID" "$STORAGE_BASE/$NEW_ID"

        # Omdøb alle diskfiler til nyt ID
        for FILE in "$STORAGE_BASE/$NEW_ID"/*; do
            BASENAME=$(basename "$FILE")
            NEWNAME=$(echo "$BASENAME" | sed "s/$OLD_ID/$NEW_ID/g")
            if [ "$BASENAME" != "$NEWNAME" ]; then
                mv "$FILE" "$STORAGE_BASE/$NEW_ID/$NEWNAME"
                echo "▶ Omdøbt disk: $BASENAME → $NEWNAME"
            fi
        done
    fi
done

# Opdater disk-ID'er i konfigurationsfil
echo "▶ Opdaterer konfigurationsfil med nyt ID..."
sed -i "s/$OLD_ID/$NEW_ID/g" "$NEW_CONF"

echo "✅ VM ID ændret fra $OLD_ID til $NEW_ID!"
echo "ℹ️ Start VM med: qm start $NEW_ID"
