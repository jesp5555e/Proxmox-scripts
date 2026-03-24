#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026
# Author: YourName
# License: MIT
# Source: https://gns3.com

APP="GNS3 Server"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/gns3 ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD apt update
  $STD apt -y upgrade
  $STD pip3 install --upgrade gns3-server
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_info "Installing dependencies"

$STD apt update
$STD apt full-upgrade -y
$STD apt --fix-broken install -y

$STD apt install -y python3-pip python3-wheel qemu-system-x86 qemu-utils docker.io libpcap-dev pipx python3-full

msg_ok "Dependencies installed"

msg_info "Installing GNS3 Server"

$STD pip3 install gns3-server

mkdir -p /opt/gns3
mkdir -p /var/log/gns3

msg_ok "GNS3 installed"

msg_info "Creating service"

cat <<EOF >/etc/systemd/system/gns3.service
[Unit]
Description=GNS3 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gns3server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gns3
systemctl start gns3

msg_ok "GNS3 Server started"

msg_info "Cleaning up"

$STD apt autoremove -y
$STD apt clean

msg_ok "Completed successfully!"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
