#!/bin/bash

echo "=== Proxmox VM ID Ændrer ==="
read -p "Indtast nuværende VM ID: " OLD_ID
read -p "Indtast ønsket NY VM ID: " NEW_ID

CONF_DIR="/etc/pve/qemu-server"
OLD_CONF="$CONF_DIR/$OLD_ID.conf"
NEW_CONF="$CONF_DIR/$NEW_ID.conf"

# Tjek at gammel VM findes
if [ ! -f "$OLD_CONF" ]; then
    echo "❌ VM med ID $OLD_ID findes ikke."
    exit 1
fi

# Tjek at ny VM ikke allerede findes
if [ -f "$NEW_CONF" ]; then
    echo "❌ En VM med ID $NEW_ID eksisterer allerede."
    exit 1
fi

# Forsøg at lukke VM korrekt ned
echo "🔻 Forsøger at lukke VM $OLD_ID ned..."
qm shutdown "$OLD_ID"

# Vent op til 10 minutter (600 sekunder) på at VM er slukket
WAIT_TIME=0
TIMEOUT=600
while qm status "$OLD_ID" | grep -q "status: running"; do
    if [ "$WAIT_TIME" -ge "$TIMEOUT" ]; then
        echo "⏱️ Timeout! VM $OLD_ID lukker ikke ned – tvinger stop med 'qm stop'..."
        qm stop "$OLD_ID"
        break
    fi
    echo "⏳ Venter på at VM lukker ned... (${WAIT_TIME}s)"
    sleep 1
    WAIT_TIME=$((WAIT_TIME + 1))
done

echo "✅ VM er nu stoppet."

# Flyt konfigurationsfil
echo "📄 Flytter konfiguration..."
mv "$OLD_CONF" "$NEW_CONF"

# Omdøb logiske volumener (LVM)
echo "🔄 Finder og omdøber LVM-diske..."
DISKS=$(grep -oP "vm-$OLD_ID-\K[^\s,]+" "$NEW_CONF")

for DISK in $DISKS; do
    OLD_LV="vm-$OLD_ID-$DISK"
    NEW_LV="vm-$NEW_ID-$DISK"

    # Find volumegroup for denne disk
    VG=$(lvs --noheadings -o vg_name /dev/*/$OLD_LV 2>/dev/null | awk '{print $1}')

    if [ -n "$VG" ]; then
        echo "🧠 Omdøber /dev/$VG/$OLD_LV → /dev/$VG/$NEW_LV"
        lvrename "$VG" "$OLD_LV" "$NEW_LV"

        # Opdater sti i configfilen
        sed -i "s/$OLD_LV/$NEW_LV/g" "$NEW_CONF"
    else
        echo "⚠️  Disk $OLD_LV blev ikke fundet som LVM. Springes over."
    fi
done

# Omdøb diskmappe hvis den findes (for lokal storage som 'images/ID')
if [ -d "/var/lib/vz/images/$OLD_ID" ]; then
    echo "📦 Flytter diskmappe: /var/lib/vz/images/$OLD_ID → $NEW_ID"
    mv "/var/lib/vz/images/$OLD_ID" "/var/lib/vz/images/$NEW_ID"
fi

# Start VM med nyt ID
echo "✅ Starter VM $NEW_ID..."
qm start "$NEW_ID"

echo "🎉 VM ID er ændret fra $OLD_ID til $NEW_ID!"
