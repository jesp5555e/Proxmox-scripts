#!/bin/bash
# leave-ad.sh - Fjern AD integration og gendan backups

BACKUP_DIR=$(ls -td /root/ad-backup-* | head -1)
echo "===> Bruger backup fra $BACKUP_DIR"

echo "===> Forlader domæne (hvis joined)..."
realm leave || true

echo "===> Stopper services"
systemctl stop sssd oddjobd
systemctl disable sssd oddjobd

echo "===> Gendanner filer"
for f in sssd.conf krb5.conf nsswitch.conf common-auth common-session; do
    [ -f "$BACKUP_DIR/$f" ] && cp "$BACKUP_DIR/$f" "/etc/${f}" || true
done

echo "===> (Valgfrit) Fjern pakker med:"
echo "apt remove --purge -y realmd adcli sssd sssd-tools libnss-sss libpam-sss oddjob oddjob-mkhomedir packagekit samba-common-bin krb5-user"
echo "apt autoremove -y"

echo "===> Reboot anbefales nu"
