#!/bin/bash
# No -e: a failing plugin or an unreachable node_exporter must not cut the
# response short. Each step handles its own failure and reports it as a metric.
# No -x: this runs on every scrape, and the trace would flood the logs.
set -uo pipefail

NODE_EXPORTER_URL="${NODE_EXPORTER_URL:-http://localhost:9101/metrics}"
NODE_EXPORTER_PLUGINS_DIR="${NODE_EXPORTER_PLUGINS_DIR:-/etc/metrics-exporter/node_exporter-plugins.d}"
PLUGINS_DIR="${PLUGINS_DIR:-/etc/metrics-exporter/plugins.d}"

# Consume the HTTP request headers.
while IFS= read -r line; do
	line="${line%$'\r'}"
	[ -z "$line" ] && break
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/metrics-exporter.XXXXXX")" || exit 1
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
body="$tmp_dir/body.txt"
status_metrics="$tmp_dir/status.txt"
: > "$body"
: > "$status_metrics"

# Run every executable in a directory in parallel, then append the output of
# each one that exited 0 to the body, in glob order. A plugin that fails is
# logged and its output dropped; every plugin gets a success metric.
# $1: plugin directory. $2: file to use as each plugin's stdin (optional).
run_plugin_dir() {
	local dir="$1" input="${2:-}"
	local label_prefix plugins=() pids=() i plugin rc
	label_prefix="$(basename "$dir")"

	for plugin in "$dir"/*; do
		[ -f "$plugin" ] && [ -x "$plugin" ] || continue
		i=${#plugins[@]}
		if [ -n "$input" ]; then
			"$plugin" < "$input" > "$tmp_dir/$label_prefix.$i.out" &
		else
			"$plugin" > "$tmp_dir/$label_prefix.$i.out" &
		fi
		plugins+=("$plugin")
		pids+=($!)
	done

	for i in "${!plugins[@]}"; do
		plugin="${plugins[$i]}"
		rc=0
		wait "${pids[$i]}" || rc=$?
		if [ "$rc" -eq 0 ]; then
			cat "$tmp_dir/$label_prefix.$i.out" >> "$body"
		else
			echo "[WARN] plugin $plugin exited $rc; output dropped" >&2
		fi
		printf 'metrics_exporter_plugin_success{plugin="%s/%s"} %d\n' \
			"$label_prefix" "$(basename "$plugin")" "$((rc == 0))" >> "$status_metrics"
	done
}

node_metrics="$tmp_dir/node_exporter.txt"
if curl -sf --max-time 5 "$NODE_EXPORTER_URL" > "$node_metrics"; then
	node_exporter_up=1
	run_plugin_dir "$NODE_EXPORTER_PLUGINS_DIR" "$node_metrics"
else
	node_exporter_up=0
	echo "[WARN] node_exporter not reachable at $NODE_EXPORTER_URL; skipping node_exporter plugins" >&2
fi

run_plugin_dir "$PLUGINS_DIR"

{
	echo '# HELP metrics_exporter_node_exporter_up Whether node_exporter answered this scrape (1) or not (0).'
	echo '# TYPE metrics_exporter_node_exporter_up gauge'
	echo "metrics_exporter_node_exporter_up $node_exporter_up"
	if [ -s "$status_metrics" ]; then
		echo '# HELP metrics_exporter_plugin_success Whether the plugin exited 0 (1) or failed and its output was dropped (0).'
		echo '# TYPE metrics_exporter_plugin_success gauge'
		cat "$status_metrics"
	fi
} >> "$body"

# Headers go out only now, once the whole body is known.
printf 'HTTP/1.1 200 OK\r\n'
printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf 'Content-Length: %d\r\n' "$(wc -c < "$body")"
printf 'Connection: close\r\n'
printf '\r\n'
cat "$body"
