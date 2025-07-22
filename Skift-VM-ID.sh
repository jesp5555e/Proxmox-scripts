#!/bin/bash

echo "Indtast nuværende VM ID:"
read OLD_ID

echo "Indtast nyt ønsket VM ID:"
read NEW_ID

OLD_CONF="/etc/pve/qemu-server/$OLD_ID.conf"
NEW_CONF="/etc/pve/qemu-server/$NEW_ID.conf"

# Tjek om gammel VM findes
if [ ! -f "$OLD_CONF" ]; then
    echo "❌ VM med ID $OLD_ID findes ikke!"
    exit 1
fi

# Tjek om ny VM ID allerede er i brug
if [ -f "$NEW_CONF" ]; then
    echo "❌ En VM med ID $NEW_ID eksisterer allerede!"
    exit 1
fi

# Stop VM
echo "🛑 Stopper VM $OLD_ID..."
qm stop "$OLD_ID"

# Flyt konfiguration
echo "📁 Flytter konfigurationsfil..."
mv "$OLD_CONF" "$NEW_CONF"

# Find og omdøb diske
echo "🔍 Søger efter diskfiler..."
DISKS=$(grep -oP "vm-${OLD_ID}-\S+" "$NEW_CONF" | sort -u)

for DISK_PATH in $DISKS; do
    # Find absolut sti til disken
    STORAGE_PATH=$(find / -type f -name "$DISK_PATH" 2>/dev/null | head -n 1)

    if [ -n "$STORAGE_PATH" ]; then
        echo "🔄 Omdøber disk: $STORAGE_PATH"

        # Ny disksti
        NEW_DISK_NAME=$(echo "$DISK_PATH" | sed "s/$OLD_ID/$NEW_ID/")
        NEW_STORAGE_PATH=$(echo "$STORAGE_PATH" | sed "s/$DISK_PATH/$NEW_DISK_NAME/")

        # Omdøb diskfil
        mv "$STORAGE_PATH" "$NEW_STORAGE_PATH"

        # Opdater sti i .conf
        sed -i "s|$DISK_PATH|$NEW_DISK_NAME|g" "$NEW_CONF"
    else
        echo "⚠️ Kunne ikke finde disk: $DISK_PATH (måske ekstern storage?)"
    fi
done

# Flyt diskmappe hvis den findes
if [ -d "/var/lib/vz/images/$OLD_ID" ]; then
    echo "📦 Flytter diskmappe fra $OLD_ID til $NEW_ID..."
    mv "/var/lib/vz/images/$OLD_ID" "/var/lib/vz/images/$NEW_ID"
fi

# Start ny VM
echo "🚀 Starter VM med ID $NEW_ID..."
qm start "$NEW_ID"

echo "✅ Færdig! VM $OLD_ID er nu flyttet til $NEW_ID."
