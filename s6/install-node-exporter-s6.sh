#!/bin/bash
set -eo pipefail

# Install node-exporter on a container using s6-overly instead of systemd

# Use existing value of $S6_DIR (if sourced from s6-install.sh)
: "${S6_DIR:=/etc/s6-overlay/s6-rc.d}"

echo "Installing node-exporter..."

NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.6.0}"

adduser -M -r -s /sbin/nologin node_exporter
cd "/usr/src/"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar -xf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"
cp "node_exporter" "/usr/bin/"

# Setup logging for service
mkdir -p $S6_DIR/node-exporter-log-prepare/dependencies.d
touch $S6_DIR/node-exporter-log-prepare/dependencies.d/base

echo "oneshot" > $S6_DIR/node-exporter-log-prepare/type
cat << EOF > $S6_DIR/node-exporter-log-prepare/up
if { mkdir -p /var/log/node-exporter }
if { chown nobody:nobody /var/log/node-exporter }
chmod 02755 /var/log/node-exporter
EOF

mkdir -p $S6_DIR/node-exporter-log/dependencies.d
touch $S6_DIR/node-exporter-log/dependencies.d/node-exporter-log-prepare
echo "longrun" > $S6_DIR/node-exporter-log/type
echo "node-exporter" > $S6_DIR/node-exporter-log/consumer-for

cat << EOF > $S6_DIR/node-exporter-log/run
#!/bin/sh
exec logutil-service /var/log/node-exporter
EOF
chmod 700 $S6_DIR/node-exporter-log/run

echo "node-exporter-pipeline" > $S6_DIR/node-exporter-log/pipeline-name
touch $S6_DIR/user/contents.d/node-exporter-pipeline


# Setup service
mkdir -p $S6_DIR/node-exporter/dependencies.d
touch $S6_DIR/node-exporter/dependencies.d/base
echo "longrun" > $S6_DIR/node-exporter/type
echo "node-exporter-log" > $S6_DIR/node-exporter/producer-for

cat << EOF > "$S6_DIR/node-exporter/run"
#!/bin/sh
exec 2>&1
exec /usr/sbin/runuser -u node_exporter -- /usr/bin/node_exporter --collector.textfile.directory=/tmp/node_exporter_collector --web.listen-address=:9101
EOF
chmod 700 "$S6_DIR/node-exporter/run"

mkdir "/tmp/node_exporter_collector"
chmod 777 "/tmp/node_exporter_collector"

echo "✓ node_exporter Installation complete"
echo ""
echo "Test with: curl http://localhost:9101"
