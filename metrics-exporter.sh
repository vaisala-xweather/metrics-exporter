#!/bin/bash
set -xeo pipefail
# Metrics exporter script - outputs hello world with HTTP headers
# Read the HTTP request (optional, but good practice)
while read -r line; do
    line=$(echo "$line" | tr -d '\r')
    [ -z "$line" ] && break
done

# Send HTTP response
echo -ne "HTTP/1.1 200 OK\r\n"
echo -ne "Content-Type: text/plain; charset=utf-8\r\n"
echo -ne "Connection: close\r\n"
echo -ne "\r\n"

# Get the directory where this script is located
NODE_EXPORTER_PLUGINS_DIR="/etc/metrics-exporter/node_exporter-plugins.d"
PLUGINS_DIR="/etc/metrics-exporter/plugins.d"

function run_node_exporter_plugins() {
	# Create/clean temporary directory for outputs
	local tmp_dir="/tmp/metrics-exporter-$$"
	local metrics_output="$tmp_dir/node_metrics_out.txt"
	rm -rf "$tmp_dir"
	mkdir -p "$tmp_dir"

	# Query node_exporter once and save to a variable for reuse
	curl -s 'http://localhost:9101/metrics' > "$metrics_output"

	# Set up trap to clean up temp dir on exit
	trap 'rm -rf "$tmp_dir"' EXIT INT TERM	# Run each node_exporter plugin in parallel, writing output to temp files
	local pids=()
	local count=0

	for node_exporter_plugin in "$NODE_EXPORTER_PLUGINS_DIR"/*; do
		if [ -f "$node_exporter_plugin" ] && [ -x "$node_exporter_plugin" ]; then
			# Run plugin in background and write output to temp file
			echo "[INFO] Running node_exporter plugin: $node_exporter_plugin" >&2
			(cat "$metrics_output" | "$node_exporter_plugin" > "$tmp_dir/node_exporter_$count.txt") &
			pids+=($!)
			count=$((count + 1))
		fi
	done

	# Wait for all background processes to complete
	for pid in "${pids[@]}"; do
		wait "$pid"
	done

	# Cat all outputs together
	cat "$tmp_dir"/node_exporter_*.txt 2>/dev/null || true

	# Cleanup
	rm -rf "$tmp_dir"
}

function run_plugins() {
	# Create/clean temporary directory for outputs
	local tmp_dir="/tmp/metrics-exporter-plugins-$$"
	rm -rf "$tmp_dir"
	mkdir -p "$tmp_dir"

	# Set up trap to clean up temp dir on exit
	trap 'rm -rf "$tmp_dir"' EXIT INT TERM

	# Run each custom plugin in parallel, writing output to temp files
	local pids=()
	local count=0

	for plugin in "$PLUGINS_DIR"/*; do
		if [ -f "$plugin" ] && [ -x "$plugin" ]; then
			# Run plugin in background and write output to temp file
			("$plugin" > "$tmp_dir/plugin_$count.txt") &
			pids+=($!)
			count=$((count + 1))
		fi
	done

	# Wait for all background processes to complete
	for pid in "${pids[@]}"; do
		wait "$pid"
	done

	# Cat all outputs together
	cat "$tmp_dir"/plugin_*.txt 2>/dev/null || true

	# Cleanup
	rm -rf "$tmp_dir"
}

run_node_exporter_plugins
run_plugins
