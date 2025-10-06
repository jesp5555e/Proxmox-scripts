#!/bin/bash
# join-ad.sh - Join Proxmox (Debian) node to Active Directory med SSSD + realmd
# Kan køres direkte fra GitHub:
# bash -c "$(wget -qLO - https://github.com/jesp5555e/Proxmox-scripts/raw/refs/heads/main/Join-AD.sh)"

set -euo pipefail

# ===> Tjek om vi kører som root
if [[ $EUID -ne 0 ]]; then
    echo "Dette script skal køres som root."
    exit 1
fi

# ===> Spørg efter domain og AD-bruger
echo "=== Join Proxmox til Active Directory ==="
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

echo "===> Installerer nødvendige pakker..."
apt update -qq
DEBIAN_FRONTEND=noninteractive apt install -y \
    realmd sssd sssd-tools adcli samba-common-bin \
    oddjob oddjob-mkhomedir packagekit \
    libnss-sss libpam-sss krb5-user >/dev/null

systemctl enable --now oddjobd >/dev/null 2>&1 || true

echo "===> Tester DNS og tid..."
if ! host -t SRV _ldap._tcp."$DOMAIN_LOWER" >/dev/null; then
    echo "DNS lookup fejlede for domænet $DOMAIN_LOWER"
    exit 1
fi
timedatectl status | grep -q "System clock synchronized: yes" || \
    echo "ADVARSEL: Systemtid er måske ikke synkroniseret!"

echo "===> Joiner domæne $DOMAIN_LOWER som bruger $JOIN_USER"
realm join --verbose --user="$JOIN_USER" "$DOMAIN_LOWER" || {
    echo "Join fejlede! Tjek dine legitimationsoplysninger og DNS."
    exit 1
}

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

echo "===> Opdaterer /etc/nsswitch.conf"
sed -i 's/^passwd:.*/passwd:         compat sss/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:          compat sss/' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow:         compat sss/' /etc/nsswitch.conf

echo "===> Tilføjer pam_mkhomedir til /etc/pam.d/common-session hvis ikke allerede tilføjet"
grep -q pam_mkhomedir.so /etc/pam.d/common-session || \
    echo "session required pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session

echo "===> Tester brugeropslag..."
if ! id "$JOIN_USER@$DOMAIN_LOWER" >/dev/null 2>&1; then
    echo "OBS: id lookup fejlede - tjek sssd logs (journalctl -u sssd)"
fi

echo ""
echo "✅ Konfiguration færdig!"
echo "Backup gemt i: $BACKUP_DIR"
echo "Test med:"
echo "  id <AD-BRUGER>"
echo "  getent passwd <AD-BRUGER>"
echo "  getent group <AD-GRUPPE>"
echo ""
