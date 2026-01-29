#!/bin/bash
# Uninstall the metrics exporter systemd socket-activated service

set -e

SYSTEMD_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/metrics-exporter"
INSTALL_DIR="/opt/metrics-exporter"

echo "Uninstalling metrics exporter..."

# Stop and disable the socket
sudo systemctl stop metrics-exporter.socket 2>/dev/null || true
sudo systemctl disable metrics-exporter.socket 2>/dev/null || true

# Remove systemd unit files
sudo rm -f "$SYSTEMD_DIR/metrics-exporter.socket"
sudo rm -f "$SYSTEMD_DIR/metrics-exporter@.service"

# Remove config directory (including symlinks)
sudo rm -rf "$CONFIG_DIR"

# Remove install directory
sudo rm -rf "$INSTALL_DIR"

# Reload systemd
sudo systemctl daemon-reload

echo "✓ Uninstallation complete"
