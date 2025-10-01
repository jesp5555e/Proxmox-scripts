#!/bin/bash
# join-ad.sh - Join Proxmox (Debian) node to Active Directory with SSSD + realmd
# Usage: ./join-ad.sh <DOMAIN> <AD-USER>

set -euo pipefail
# ===> Spørg efter DOMAIN og AD-USER
read -rp "Indtast AD DOMAIN (fx ad.example.com): " DOMAIN_INPUT
read -rp "Indtast AD bruger (fx administrator): " USER_INPUT

DOMAIN_LOWER=$(echo "$DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]')
DOMAIN_UPPER=$(echo "$DOMAIN_INPUT" | tr '[:lower:]' '[:upper:]')
JOIN_USER="$USER_INPUT"

BACKUP_DIR="/root/ad-backup-$(date +%F-%H%M%S)"

echo "===> Backup af filer til $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
for f in /etc/sssd/sssd.conf /etc/krb5.conf /etc/nsswitch.conf /etc/pam.d/common-auth /etc/pam.d/common-session; do
    [ -f "$f" ] && cp "$f" "$BACKUP_DIR/"
done

echo "===> Installerer pakker..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
    realmd sssd sssd-tools adcli samba-common-bin \
    oddjob oddjob-mkhomedir packagekit \
    libnss-sss libpam-sss krb5-user

systemctl enable --now oddjobd

echo "===> Tester DNS og tid..."
host -t SRV _ldap._tcp."$DOMAIN_LOWER" || { echo "DNS lookup fejlede"; exit 1; }
timedatectl status | grep "System clock synchronized: yes" || echo "ADVARSEL: Tid er måske ikke synkroniseret!"

echo "===> Joiner domæne $DOMAIN_LOWER som bruger $JOIN_USER"
realm join --verbose --user="$JOIN_USER" "$DOMAIN_LOWER" || { echo "Join fejlede"; exit 1; }

echo "===> Opretter /etc/sssd/sssd.conf"
cat >/etc/sssd/sssd.conf <<EOF
[sssd]
config_file_version = 2
services = nss, pam
domains = $DOMAIN_LOWER

[domain/$DOMAIN_LOWER]
ad_domain = $DOMAIN_LOWER
krb5_realm = $DOMAIN_UPPER
realmd_tags = manages-system joined-with-samba
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
use_fully_qualified_names = False
fallback_homedir = /home/%u
access_provider = ad
enumerate = False
EOF

chmod 600 /etc/sssd/sssd.conf
systemctl restart sssd

echo "===> Tilføjer sss til /etc/nsswitch.conf"
sed -i 's/^passwd:.*/passwd:         compat sss/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:          compat sss/' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow:         compat sss/' /etc/nsswitch.conf

echo "===> Tilføjer pam_mkhomedir til /etc/pam.d/common-session hvis ikke allerede tilføjet"
grep -q pam_mkhomedir.so /etc/pam.d/common-session || \
    echo "session required pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session

echo "===> Tester brugeropslag..."
id "$JOIN_USER@$DOMAIN_LOWER" || echo "OBS: id lookup fejlede - tjek sssd logs"

echo "===> Konfiguration færdig!"
echo "Backup gemt i: $BACKUP_DIR"
echo "Test med: id <AD-BRUGER>, getent passwd <AD-BRUGER>, getent group <AD-GRUPPE>"
