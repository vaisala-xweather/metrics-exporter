#!/bin/bash
# Install the metrics exporter systemd socket-activated service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/metrics-exporter"
INSTALL_DIR="/opt/metrics-exporter"

echo "Installing metrics exporter..."

# The exporter takes port 9100, node_exporter's default, and reads
# node_exporter on 9101. Fail early if something else already holds 9100.
if ! systemctl is-active --quiet metrics-exporter.socket && [ -n "$(ss -Hltn 'sport = :9100')" ]; then
	echo "Error: port 9100 is already in use, probably by node_exporter." >&2
	echo "Move node_exporter to port 9101 (--web.listen-address=127.0.0.1:9101) and run this again." >&2
	exit 1
fi

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

if ! curl -sf --max-time 3 -o /dev/null http://localhost:9101/metrics; then
	echo "[WARN] node_exporter is not answering on localhost:9101." >&2
	echo "       Until it does, metrics_exporter_node_exporter_up is 0 and the node_exporter plugins do not run." >&2
	echo "       Start node_exporter with --web.listen-address=127.0.0.1:9101." >&2
fi

echo "✓ Installation complete"
echo ""
echo "Check status with: sudo systemctl status metrics-exporter.socket"
echo "Test with: curl http://localhost:9100"
