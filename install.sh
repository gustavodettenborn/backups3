#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$USER_SYSTEMD_DIR/backup-gdrive.service"

echo "[1/7] Preparando .env"
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "- .env criado a partir de .env.example"
else
    echo "- .env ja existe"
fi

echo "[2/7] Ajustando permissoes"
chmod +x \
    "$SCRIPT_DIR/backup-gdrive.sh" \
    "$SCRIPT_DIR/backup-wrapper.sh" \
    "$SCRIPT_DIR/backup-notifier.sh" \
    "$SCRIPT_DIR/backup-gdrive-daemon.sh" \
    "$SCRIPT_DIR/install.sh"

echo "[3/7] Preparando diretorio de logs em /var/log/backups3"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/.env"
LOG_DIR="${BACKUP_LOG_DIR:-/var/log/backups3}"
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
    echo "- criando $LOG_DIR (requer sudo, pois /var/log e' de root)"
    sudo install -d -m 755 -o "$(whoami)" -g "$(whoami)" "$LOG_DIR"
else
    echo "- $LOG_DIR ja existe e e' gravavel"
fi

echo "[4/7] Instalando unit do systemd --user"
mkdir -p "$USER_SYSTEMD_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Backup Google Drive session daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/backup-gdrive-daemon.sh
Environment=HOME=%h
Environment=XDG_RUNTIME_DIR=/run/user/%U
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

echo "[5/7] Recarregando systemd do usuario"
systemctl --user daemon-reload

echo "[6/7] Importando ambiente grafico para notificacoes"
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY XDG_RUNTIME_DIR || true

echo "[7/7] Ativando servico"
systemctl --user disable --now backup-gdrive.timer >/dev/null 2>&1 || true
systemctl --user enable --now backup-gdrive.service

echo ""
echo "Instalacao concluida."
echo "Projeto: $SCRIPT_DIR"
echo "Serviço: backup-gdrive.service"
echo ""
systemctl --user --no-pager --full status backup-gdrive.service | head -n 20
