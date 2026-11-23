#!/bin/bash
# No -e: a failing plugin or an unreachable node_exporter must not cut the
# response short. Each step handles its own failure and reports it as a metric.
# No -x: this runs on every scrape, and the trace would flood the logs.
set -uo pipefail

NODE_EXPORTER_URL="${METRICS_EXPORTER_NODE_EXPORTER_URL:-http://localhost:9101/metrics}"
NODE_EXPORTER_PLUGINS_DIR="${METRICS_EXPORTER_NODE_EXPORTER_PLUGINS_DIR:-/etc/metrics-exporter/node_exporter-plugins.d}"
PLUGINS_DIR="${METRICS_EXPORTER_PLUGINS_DIR:-/etc/metrics-exporter/plugins.d}"

# Consume the HTTP request headers.
while IFS= read -r line; do
	line="${line%$'\r'}"
	[ -z "$line" ] && break
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/metrics-exporter.XXXXXX")" || exit 1
body="$tmp_dir/body.txt"
status_metrics="$tmp_dir/status.txt"
plugin_pids=()

# On INT/TERM, stop the plugins and exit without sending anything: a killed
# scrape must read as a failed one, never as an empty 200.
on_signal() {
	trap - INT TERM
	[ ${#plugin_pids[@]} -gt 0 ] && kill "${plugin_pids[@]}" 2>/dev/null
	exit 143
}
trap 'rm -rf "$tmp_dir"' EXIT
trap on_signal INT TERM

# If the response cannot be written in full (e.g. /tmp is full), send nothing,
# so Prometheus marks the scrape failed rather than publishing a short body.
abort() {
	echo "[ERROR] $1; sending no response" >&2
	exit 1
}

: > "$body" || abort "cannot create response body in $tmp_dir"
: > "$status_metrics" || abort "cannot create $status_metrics"

# Run every executable in a directory in parallel, then append the output of
# each one that exited 0 to the body, in glob order. A plugin that fails is
# logged and its output dropped; every plugin gets a success metric.
# $1: plugin directory. $2: file to use as each plugin's stdin (optional).
run_plugin_dir() {
	local dir="$1" input="${2:-}"
	local dir_name plugins=() pids=() i plugin out rc label
	dir_name="$(basename "$dir")"

	for plugin in "$dir"/*; do
		[ -f "$plugin" ] && [ -x "$plugin" ] || continue
		i=${#plugins[@]}
		if [ -n "$input" ]; then
			"$plugin" < "$input" > "$tmp_dir/$dir_name.$i.out" &
		else
			"$plugin" > "$tmp_dir/$dir_name.$i.out" &
		fi
		plugins+=("$plugin")
		pids+=($!)
		plugin_pids+=($!)
	done

	for i in "${!plugins[@]}"; do
		plugin="${plugins[$i]}"
		out="$tmp_dir/$dir_name.$i.out"
		rc=0
		wait "${pids[$i]}" || rc=$?
		if [ "$rc" -eq 0 ]; then
			cat "$out" >> "$body" || abort "cannot append output of $plugin"
			# Keep the next plugin's first line off this one's last line.
			if [ -s "$out" ] && [ -n "$(tail -c1 "$out")" ]; then
				echo >> "$body" || abort "cannot append output of $plugin"
			fi
		else
			echo "[WARN] plugin $plugin exited $rc; output dropped" >&2
		fi
		label="$dir_name/$(basename "$plugin")"
		label="${label//\\/\\\\}"
		label="${label//\"/\\\"}"
		label="${label//$'\n'/\\n}"
		printf 'metrics_exporter_plugin_success{plugin="%s"} %d\n' "$label" "$((rc == 0))" \
			>> "$status_metrics" || abort "cannot write $status_metrics"
	done
}

# Keep this well under socat's -T 5 idle timeout (s6/install.sh): nothing is
# written to the client until the body is complete.
node_metrics="$tmp_dir/node_exporter.txt"
if curl -sf --connect-timeout 1 --max-time 3 "$NODE_EXPORTER_URL" > "$node_metrics"; then
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
} >> "$body" || abort "cannot append exporter metrics"

content_length="$(wc -c < "$body")" && [ -n "$content_length" ] || abort "cannot measure response body"

# Headers go out only now, once the whole body is known.
printf 'HTTP/1.1 200 OK\r\n'
printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf 'Content-Length: %d\r\n' "$content_length"
printf 'Connection: close\r\n'
printf '\r\n'
cat "$body"
