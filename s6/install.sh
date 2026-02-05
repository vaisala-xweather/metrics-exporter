#!/bin/bash
# Install the metrics exporter for s6-overlay on docker/ecs

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../"

S6_DIR="/etc/s6-overlay/s6-rc.d"
CONFIG_DIR="/etc/metrics-exporter"
INSTALL_DIR="/opt/metrics-exporter"

echo "Installing metrics exporter..."
# Check for required binaries
if ! command -v socat &> /dev/null; then
	echo "Error: socat is not installed. Please install socat and try again."
	exit 1
fi
if [ ! -d "/etc/s6-overlay" ]; then
	echo "Error: s6-overlay is not installed. Please install s6-overlay and try again."
	exit 1
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy the main script
cp "$PROJECT_DIR/metrics-exporter.sh" "$INSTALL_DIR/metrics-exporter.sh"

chmod +x "$INSTALL_DIR/metrics-exporter.sh"

# Create config directory
mkdir -p "$CONFIG_DIR"

mkdir -p "$CONFIG_DIR/node_exporter-plugins.d"
cp "$PROJECT_DIR/node_exporter-plugins.d/"* "$CONFIG_DIR/node_exporter-plugins.d"
mkdir -p "$CONFIG_DIR/plugins.d"

# Setup logging for service
mkdir -p $S6_DIR/metrics-exporter-log-prepare/dependencies.d
touch $S6_DIR/metrics-exporter-log-prepare/dependencies.d/base

echo "oneshot" > $S6_DIR/metrics-exporter-log-prepare/type
cat << EOF > $S6_DIR/metrics-exporter-log-prepare/up
if { mkdir -p /var/log/metrics-exporter }
if { chown nobody:nobody /var/log/metrics-exporter }
chmod 02755 /var/log/metrics-exporter
EOF

mkdir -p $S6_DIR/metrics-exporter-log/dependencies.d
touch $S6_DIR/metrics-exporter-log/dependencies.d/metrics-exporter-log-prepare
echo "longrun" > $S6_DIR/metrics-exporter-log/type
echo "metrics-exporter" > $S6_DIR/metrics-exporter-log/consumer-for

cat << EOF > $S6_DIR/metrics-exporter-log/run
#!/bin/sh
exec logutil-service /var/log/metrics-exporter
EOF
chmod 700 $S6_DIR/metrics-exporter-log/run

echo "metrics-exporter-pipeline" > $S6_DIR/metrics-exporter-log/pipeline-name
touch $S6_DIR/user/contents.d/metrics-exporter-pipeline

# Setup service
mkdir -p $S6_DIR/metrics-exporter/dependencies.d
touch $S6_DIR/metrics-exporter/dependencies.d/base
echo "longrun" > $S6_DIR/metrics-exporter/type
echo "metrics-exporter-log" > $S6_DIR/metrics-exporter/producer-for

# Define command for service
cat << EOF > $S6_DIR/metrics-exporter/run
#!/bin/sh
exec 2>&1
exec /usr/bin/socat -T 5 TCP-LISTEN:9100,reuseaddr,fork EXEC:/opt/metrics-exporter/metrics-exporter.sh
EOF
chmod 700 $S6_DIR/metrics-exporter/run

# Install node exporter and configure it to listen on port 9101
source "${SCRIPT_DIR}/install-node-exporter-s6.sh"

echo "✓ Installation complete"
echo ""
echo "Test with: curl http://localhost:9100"
