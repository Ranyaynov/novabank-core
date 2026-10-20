#!/bin/bash
# Installe PostgreSQL, limite les connexions (pg_hba.conf) et ferme le réseau (ufw)
set -euo pipefail
cd /tmp
sudo apt update
sudo apt install -y postgresql postgresql-contrib ufw
sudo systemctl enable --now postgresql

HBA=$(sudo -u postgres psql -tAc "SHOW hba_file")
[ -f "$HBA.bak" ] || sudo cp "$HBA" "$HBA.bak"
sudo tee "$HBA" > /dev/null <<'HBA_EOF'
# TYPE  DATABASE   USER       ADDRESS         METHOD
local   all        postgres                   peer
local   all        all                        scram-sha-256
host    novabank   all        127.0.0.1/32    scram-sha-256
host    novabank   all        ::1/128         scram-sha-256
HBA_EOF
sudo systemctl reload postgresql

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw --force enable
