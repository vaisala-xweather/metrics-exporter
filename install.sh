#!/bin/bash
# Install the metrics exporter systemd socket-activated service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/metrics-exporter"
INSTALL_DIR="/opt/metrics-exporter"

echo "Installing metrics exporter..."

sudo mkdir -p "$INSTALL_DIR"
sudo cp "$SCRIPT_DIR/metrics-exporter.sh" "$INSTALL_DIR/metrics-exporter.sh"
sudo chmod +x "$INSTALL_DIR/metrics-exporter.sh"

sudo mkdir -p "$CONFIG_DIR"
sudo mkdir -p "$CONFIG_DIR/node_exporter-plugins.d"
sudo cp "$SCRIPT_DIR/node_exporter-plugins.d/"* "$CONFIG_DIR/node_exporter-plugins.d"
sudo mkdir -p "$CONFIG_DIR/plugins.d"

# Systemd init
sudo cp "$SCRIPT_DIR/metrics-exporter.socket" "$SYSTEMD_DIR/metrics-exporter.socket"
sudo cp "$SCRIPT_DIR/metrics-exporter@.service" "$SYSTEMD_DIR/metrics-exporter@.service"
sudo systemctl daemon-reload

sudo systemctl enable metrics-exporter.socket
sudo systemctl start metrics-exporter.socket

echo "✓ Installation complete"
echo ""
echo "Check status with: sudo systemctl status metrics-exporter.socket"
echo "Test with: curl http://localhost:9100"
