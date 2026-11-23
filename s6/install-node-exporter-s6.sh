#!/bin/bash
set -euo pipefail

# Install node_exporter in a container that uses s6-overlay instead of systemd.
# Works on Debian/Ubuntu, RHEL-like and Alpine images, on amd64 and arm64.

# Use existing value of $S6_DIR (if sourced from s6/install.sh)
: "${S6_DIR:=/etc/s6-overlay/s6-rc.d}"

echo "Installing node-exporter..."

NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.6.0}"
TEXTFILE_DIR="/tmp/node_exporter_collector"

case "$(uname -m)" in
	x86_64) arch=amd64 ;;
	aarch64 | arm64) arch=arm64 ;;
	armv7l) arch=armv7 ;;
	*)
		echo "Error: no node_exporter build for architecture $(uname -m)" >&2
		exit 1
		;;
esac

# System user without a home directory or login shell. Alpine has only busybox
# adduser, whose options differ from the shadow-utils useradd elsewhere.
if ! id node_exporter > /dev/null 2>&1; then
	if command -v useradd > /dev/null 2>&1; then
		useradd -M -r -s /sbin/nologin node_exporter
	else
		adduser -S -D -H -s /sbin/nologin node_exporter
	fi
fi

# Download and check the release against its published SHA-256 sums. That
# catches a corrupt or truncated download; authenticity rests on HTTPS to GitHub.
tarball="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
release_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}"
download_dir="$(mktemp -d)"
curl -fsSL -o "$download_dir/$tarball" "$release_url/$tarball"
curl -fsSL -o "$download_dir/sha256sums.txt" "$release_url/sha256sums.txt"
(cd "$download_dir" && grep " ${tarball}\$" sha256sums.txt | sha256sum -c -)
tar -xzf "$download_dir/$tarball" -C "$download_dir"
cp "$download_dir/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" /usr/bin/node_exporter
rm -rf "$download_dir"

# Setup logging for service
mkdir -p $S6_DIR/node-exporter-log-prepare/dependencies.d
touch $S6_DIR/node-exporter-log-prepare/dependencies.d/base

echo "oneshot" > $S6_DIR/node-exporter-log-prepare/type
cat << EOF > $S6_DIR/node-exporter-log-prepare/up
if { mkdir -p /var/log/node-exporter }
if { chown nobody /var/log/node-exporter }
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
mkdir -p $S6_DIR/user/contents.d
touch $S6_DIR/user/contents.d/node-exporter-pipeline


# Setup service
mkdir -p $S6_DIR/node-exporter/dependencies.d
touch $S6_DIR/node-exporter/dependencies.d/base
echo "longrun" > $S6_DIR/node-exporter/type
echo "node-exporter-log" > $S6_DIR/node-exporter/producer-for

# The textfile directory is made at start, not at build time: /tmp may be a
# fresh tmpfs or volume when the container runs. The sticky bit lets any
# process drop .prom files in it, but not delete or replace another's.
# node_exporter listens on loopback only: metrics-exporter on :9100 is the
# public endpoint.
cat << EOF > "$S6_DIR/node-exporter/run"
#!/bin/sh
exec 2>&1
mkdir -p $TEXTFILE_DIR
chmod 1777 $TEXTFILE_DIR
exec s6-setuidgid node_exporter /usr/bin/node_exporter --collector.textfile.directory=$TEXTFILE_DIR --web.listen-address=127.0.0.1:9101
EOF
chmod 700 "$S6_DIR/node-exporter/run"

echo "✓ node_exporter Installation complete"
echo ""
echo "Test with: curl http://localhost:9101/metrics"
