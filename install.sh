#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$USER_SYSTEMD_DIR/backup-gdrive.service"

echo "[1/6] Preparando .env"
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "- .env criado a partir de .env.example"
else
    echo "- .env ja existe"
fi

echo "[2/6] Ajustando permissoes"
chmod +x \
    "$SCRIPT_DIR/backup-gdrive.sh" \
    "$SCRIPT_DIR/backup-wrapper.sh" \
    "$SCRIPT_DIR/backup-notifier.sh" \
    "$SCRIPT_DIR/backup-gdrive-daemon.sh" \
    "$SCRIPT_DIR/install.sh"

echo "[3/6] Instalando unit do systemd --user"
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

echo "[4/6] Recarregando systemd do usuario"
systemctl --user daemon-reload

echo "[5/6] Importando ambiente grafico para notificacoes"
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY XDG_RUNTIME_DIR || true

echo "[6/6] Ativando servico"
systemctl --user disable --now backup-gdrive.timer >/dev/null 2>&1 || true
systemctl --user enable --now backup-gdrive.service

echo ""
echo "Instalacao concluida."
echo "Projeto: $SCRIPT_DIR"
echo "Serviço: backup-gdrive.service"
echo ""
systemctl --user --no-pager --full status backup-gdrive.service | head -n 20
