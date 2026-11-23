#!/bin/bash
# No -e: a failing plugin or an unreachable node_exporter must not cut the
# response short. Each step handles its own failure and reports it as a metric.
# No -x: this runs on every scrape, and the trace would flood the logs.
set -uo pipefail

NODE_EXPORTER_URL="${METRICS_EXPORTER_NODE_EXPORTER_URL:-http://localhost:9101/metrics}"
NODE_EXPORTER_PLUGINS_DIR="${METRICS_EXPORTER_NODE_EXPORTER_PLUGINS_DIR:-/etc/metrics-exporter/node_exporter-plugins.d}"
PLUGINS_DIR="${METRICS_EXPORTER_PLUGINS_DIR:-/etc/metrics-exporter/plugins.d}"
PLUGIN_TIMEOUT="${METRICS_EXPORTER_PLUGIN_TIMEOUT:-2}"
REQUEST_TIMEOUT=5

# Consume the HTTP request headers. A client that does not finish its request
# in REQUEST_TIMEOUT seconds gets nothing: under systemd nothing else would
# ever end this instance.
request_deadline=$((SECONDS + REQUEST_TIMEOUT))
while :; do
	remaining=$((request_deadline - SECONDS))
	rc=0
	[ "$remaining" -gt 0 ] && IFS= read -r -t "$remaining" line || rc=$?
	if [ "$remaining" -le 0 ] || [ "$rc" -gt 128 ]; then
		echo "[WARN] client did not finish its request in ${REQUEST_TIMEOUT}s; sending no response" >&2
		exit 1
	fi
	[ "$rc" -ne 0 ] && break # EOF: the client sent all it will
	line="${line%$'\r'}"
	[ -z "$line" ] && break
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/metrics-exporter.XXXXXX")" || exit 1
body="$tmp_dir/body.txt"
status_metrics="$tmp_dir/status.txt"

# One entry per started plugin, across both directories.
plugin_paths=()
plugin_dirs=()
plugin_pgids=()
declare -A watchdogs

# On INT/TERM, stop the plugins and exit without sending anything: a killed
# scrape must read as a failed one, never as an empty 200.
on_signal() {
	trap - INT TERM
	[ ${#plugin_pgids[@]} -gt 0 ] && kill -TERM -- "${plugin_pgids[@]}" 2> /dev/null
	[ ${#watchdogs[@]} -gt 0 ] && kill "${watchdogs[@]}" 2> /dev/null
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

# Start every executable in a directory in the background, all at once.
# setsid puts each plugin in its own process group, so a watchdog can stop the
# plugin and everything it started (e.g. a df hung on a stuck network mount):
# after PLUGIN_TIMEOUT seconds it sends TERM to each group, then KILL 1 second
# later. This does not rely on timeout(1): busybox's only signals one pid.
# $1: plugin directory. $2: file to use as each plugin's stdin (optional).
start_plugins() {
	local dir="$1" input="${2:-/dev/null}"
	local dir_name plugin i pgids=()
	dir_name="$(basename "$dir")"

	for plugin in "$dir"/*; do
		[ -f "$plugin" ] && [ -x "$plugin" ] || continue
		i=${#plugin_paths[@]}
		# A background job of a script is not a group leader, so setsid execs
		# the plugin in place and $! is the plugin's pid and process group.
		setsid "$plugin" < "$input" > "$tmp_dir/plugin.$i.out" &
		plugin_paths+=("$plugin")
		plugin_dirs+=("$dir_name")
		plugin_pgids+=("-$!")
		pgids+=("-$!")
	done
	[ ${#pgids[@]} -gt 0 ] || return 0

	# Unreaped plugins stay zombies, so their group ids cannot be reused
	# before collect_plugins waits for them.
	(
		sleep "$PLUGIN_TIMEOUT"
		: > "$tmp_dir/$dir_name.timed_out"
		kill -TERM -- "${pgids[@]}"
		sleep 1
		kill -KILL -- "${pgids[@]}"
	) > /dev/null 2>&1 &
	watchdogs[$dir_name]=$!
}

# Wait for the plugins start_plugins started from a directory, then append the
# output of each one that exited 0 to the body, in glob order. A plugin that
# fails or times out is logged and its output dropped; every plugin gets a
# success metric.
# $1: plugin directory.
collect_plugins() {
	local dir_name i plugin out rc label
	dir_name="$(basename "$1")"

	for i in "${!plugin_paths[@]}"; do
		[ "${plugin_dirs[$i]}" = "$dir_name" ] || continue
		plugin="${plugin_paths[$i]}"
		out="$tmp_dir/plugin.$i.out"
		rc=0
		wait "${plugin_pgids[$i]#-}" || rc=$?
		if [ "$rc" -eq 0 ]; then
			cat "$out" >> "$body" || abort "cannot append output of $plugin"
			# Keep the next plugin's first line off this one's last line.
			if [ -s "$out" ] && [ -n "$(tail -c1 "$out")" ]; then
				echo >> "$body" || abort "cannot append output of $plugin"
			fi
		elif [ -e "$tmp_dir/$dir_name.timed_out" ] && { [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; }; then
			echo "[WARN] plugin $plugin timed out after ${PLUGIN_TIMEOUT}s; output dropped" >&2
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

	if [ -n "${watchdogs[$dir_name]:-}" ]; then
		kill "${watchdogs[$dir_name]}" 2> /dev/null
		unset "watchdogs[$dir_name]"
	fi
}

# plugins.d does not read node_exporter's output, so it runs while node_exporter
# is fetched and its plugins run. Worst case is about
# 3 + PLUGIN_TIMEOUT + 1 seconds: 6 s with the defaults.
start_plugins "$PLUGINS_DIR"

node_metrics="$tmp_dir/node_exporter.txt"
if curl -sf --connect-timeout 1 --max-time 3 "$NODE_EXPORTER_URL" > "$node_metrics"; then
	node_exporter_up=1
	start_plugins "$NODE_EXPORTER_PLUGINS_DIR" "$node_metrics"
	collect_plugins "$NODE_EXPORTER_PLUGINS_DIR"
else
	node_exporter_up=0
	echo "[WARN] node_exporter not reachable at $NODE_EXPORTER_URL; skipping node_exporter plugins" >&2
fi

collect_plugins "$PLUGINS_DIR"

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
