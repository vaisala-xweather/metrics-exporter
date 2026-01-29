#!/bin/bash
set -eo pipefail

# Install node-exporter on a container using s6-overly instead of systemd

# Use existing value of $S6_DIR (if sourced from s6-install.sh)
: "${S6_DIR:=/etc/s6-overlay/s6-rc.d}"

echo "Installing node-exporter..."

NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.6.0}"

adduser -M -r -s "/sbin/nologin node_exporter"
cd "/usr/src/"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar -xf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"
cp "node_exporter" "/usr/bin/"

mkdir -p "$S6_DIR/node-exporter"
echo "longrun" > "$S6_DIR/node-exporter/type"

cat << EOF > "$S6_DIR/node-exporter/run"
#!/bin/sh
/usr/sbin/runuser -u node_exporter -- /usr/bin/node_exporter --collector.textfile.directory=/tmp/node_exporter_collector --web.listen-address=:9101
EOF
chmod 700 "$S6_DIR/node-exporter/run"

touch "$S6_DIR/user/contents.d/node-exporter"

mkdir "/tmp/node_exporter_collector"
chmod 777 "/tmp/node_exporter_collector"

echo "✓ node_exporter Installation complete"
echo ""
echo "Test with: curl http://localhost:9101"
