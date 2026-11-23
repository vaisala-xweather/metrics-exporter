#!/bin/bash
set -euo pipefail

# Tests for metrics-exporter.sh itself: the HTTP response it writes to stdout
# for one scrape, given fake plugin directories and a fake node_exporter.
# Usage: ./test_metrics_exporter.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORTER="$SCRIPT_DIR/../metrics-exporter.sh"
FIXTURE_FILE="$SCRIPT_DIR/fixtures/node_exporter.example.txt"

TESTS_RUN=0
TESTS_FAILED=0
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

check() {
	local name="$1"
	shift
	TESTS_RUN=$((TESTS_RUN + 1))
	if "$@"; then
		echo -e "${GREEN}✓${NC} $name"
	else
		echo -e "${RED}✗${NC} $name"
		TESTS_FAILED=$((TESTS_FAILED + 1))
	fi
}

# Write an executable plugin script into a directory.
make_plugin() {
	local path="$1" body="$2"
	mkdir -p "$(dirname "$path")"
	printf '#!/bin/bash\n%s\n' "$body" > "$path"
	chmod +x "$path"
}

# Run one scrape. Sets RESPONSE, BODY, STDERR and STATUS.
# $1: node_exporter URL. Plugin dirs come from $WORK_DIR/case.
scrape() {
	local url="$1"
	STATUS=0
	printf 'GET /metrics HTTP/1.1\r\nHost: localhost\r\n\r\n' |
		METRICS_EXPORTER_NODE_EXPORTER_URL="$url" \
		METRICS_EXPORTER_NODE_EXPORTER_PLUGINS_DIR="$WORK_DIR/case/node_exporter-plugins.d" \
		METRICS_EXPORTER_PLUGINS_DIR="$WORK_DIR/case/plugins.d" \
		"$EXPORTER" > "$WORK_DIR/response" 2> "$WORK_DIR/stderr" || STATUS=$?
	RESPONSE="$(cat "$WORK_DIR/response")"
	STDERR="$(cat "$WORK_DIR/stderr")"
	# Body is everything after the first blank (\r\n\r\n) line.
	BODY="$(awk 'body {print} /^\r?$/ && !body {body=1}' "$WORK_DIR/response")"
}

new_case() {
	rm -rf "$WORK_DIR/case"
	mkdir -p "$WORK_DIR/case/node_exporter-plugins.d" "$WORK_DIR/case/plugins.d"
}

has_line() { grep -qxF -- "$2" <<< "$1"; }
lacks_line() { ! grep -qF -- "$2" <<< "$1"; }

# Content-Length must equal the byte count of what follows the headers.
content_length_matches() {
	local declared actual
	declared="$(grep -i '^Content-Length:' "$WORK_DIR/response" | tr -dc '0-9')"
	actual="$(awk 'BEGIN{RS="\r\n\r\n"} NR==1{print length($0)+4; exit}' "$WORK_DIR/response")"
	actual=$(( $(wc -c < "$WORK_DIR/response") - actual ))
	[ -n "$declared" ] && [ "$declared" -eq "$actual" ]
}

test_happy_path() {
	echo "Happy path..."
	new_case
	make_plugin "$WORK_DIR/case/node_exporter-plugins.d/ne.sh" \
		'grep -q "^node_load1 " && echo "ne_metric 1"'
	make_plugin "$WORK_DIR/case/plugins.d/custom.sh" 'echo "custom_metric 2"'
	scrape "file://$FIXTURE_FILE"

	check "exits 0" [ "$STATUS" -eq 0 ]
	check "status line is 200" has_line "$(head -n1 <<< "$RESPONSE")" $'HTTP/1.1 200 OK\r'
	check "node_exporter plugin output present" has_line "$BODY" "ne_metric 1"
	check "custom plugin output present" has_line "$BODY" "custom_metric 2"
	check "node_exporter_up is 1" has_line "$BODY" "metrics_exporter_node_exporter_up 1"
	check "ne.sh success is 1" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="node_exporter-plugins.d/ne.sh"} 1'
	check "custom.sh success is 1" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="plugins.d/custom.sh"} 1'
	check "Content-Length matches body" content_length_matches
	check "no xtrace on stderr" lacks_line "$STDERR" "+ "
}

test_failing_plugin() {
	echo "One plugin fails..."
	new_case
	make_plugin "$WORK_DIR/case/node_exporter-plugins.d/good.sh" 'cat > /dev/null; echo "good_metric 1"'
	make_plugin "$WORK_DIR/case/node_exporter-plugins.d/bad.sh" 'cat > /dev/null; echo "half_written 1"; exit 3'
	make_plugin "$WORK_DIR/case/plugins.d/custom.sh" 'echo "custom_metric 2"'
	scrape "file://$FIXTURE_FILE"

	check "exits 0" [ "$STATUS" -eq 0 ]
	check "status line is 200" has_line "$(head -n1 <<< "$RESPONSE")" $'HTTP/1.1 200 OK\r'
	check "other node_exporter plugin still published" has_line "$BODY" "good_metric 1"
	check "custom plugin still published" has_line "$BODY" "custom_metric 2"
	check "failed plugin's partial output dropped" lacks_line "$BODY" "half_written"
	check "bad.sh success is 0" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="node_exporter-plugins.d/bad.sh"} 0'
	check "good.sh success is 1" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="node_exporter-plugins.d/good.sh"} 1'
	check "failure logged on stderr" grep -q 'bad.sh' <<< "$STDERR"
	check "Content-Length matches body" content_length_matches
}

test_node_exporter_down() {
	echo "node_exporter unreachable..."
	new_case
	make_plugin "$WORK_DIR/case/node_exporter-plugins.d/ne.sh" 'cat > /dev/null; echo "ne_metric 1"'
	make_plugin "$WORK_DIR/case/plugins.d/custom.sh" 'echo "custom_metric 2"'
	scrape "file://$WORK_DIR/does-not-exist"

	check "exits 0" [ "$STATUS" -eq 0 ]
	check "status line is 200" has_line "$(head -n1 <<< "$RESPONSE")" $'HTTP/1.1 200 OK\r'
	check "node_exporter_up is 0" has_line "$BODY" "metrics_exporter_node_exporter_up 0"
	check "node_exporter plugins skipped" lacks_line "$BODY" "ne_metric"
	check "custom plugin still published" has_line "$BODY" "custom_metric 2"
	check "Content-Length matches body" content_length_matches
}

test_output_without_trailing_newline() {
	echo "Plugin output without a trailing newline..."
	new_case
	make_plugin "$WORK_DIR/case/plugins.d/a.sh" "printf 'no_newline_metric 1'"
	make_plugin "$WORK_DIR/case/plugins.d/b.sh" 'echo "next_metric 2"'
	scrape "file://$FIXTURE_FILE"

	check "unterminated line stays on its own line" has_line "$BODY" "no_newline_metric 1"
	check "next plugin starts on a new line" has_line "$BODY" "next_metric 2"
	check "exporter metrics start on a new line" has_line "$BODY" \
		'# HELP metrics_exporter_node_exporter_up Whether node_exporter answered this scrape (1) or not (0).'
}

test_label_escaping() {
	echo "Plugin filename that needs escaping..."
	new_case
	make_plugin "$WORK_DIR/case/plugins.d/we\"ird.sh" 'echo "weird_metric 1"'
	scrape "file://$FIXTURE_FILE"

	check "quote in plugin label is escaped" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="plugins.d/we\"ird.sh"} 1'
}

# A hung plugin (e.g. df on a stuck network mount) must not hold up the
# scrape: it is stopped after METRICS_EXPORTER_PLUGIN_TIMEOUT seconds and
# reported as failed, and everything else is still published.
test_hung_plugin_times_out() {
	echo "Plugin hangs past the timeout..."
	new_case
	# A child that hangs: bash only acts on TERM after sleep returns, so the
	# signal must reach the whole process group.
	make_plugin "$WORK_DIR/case/plugins.d/hung.sh" 'sleep 30; echo "hung_metric 1"'
	# A plugin that ignores TERM needs the KILL that follows it.
	make_plugin "$WORK_DIR/case/plugins.d/stubborn.sh" 'trap "" TERM; sleep 30; echo "stubborn_metric 1"'
	make_plugin "$WORK_DIR/case/plugins.d/custom.sh" 'echo "custom_metric 2"'
	local start=$EPOCHSECONDS
	METRICS_EXPORTER_PLUGIN_TIMEOUT=1 scrape "file://$FIXTURE_FILE"
	local elapsed=$((EPOCHSECONDS - start))

	check "exits 0" [ "$STATUS" -eq 0 ]
	check "finishes within timeout + kill grace (took ${elapsed}s)" [ "$elapsed" -le 3 ]
	check "status line is 200" has_line "$(head -n1 <<< "$RESPONSE")" $'HTTP/1.1 200 OK\r'
	check "other plugin still published" has_line "$BODY" "custom_metric 2"
	check "hung.sh success is 0" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="plugins.d/hung.sh"} 0'
	check "stubborn.sh success is 0" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="plugins.d/stubborn.sh"} 0'
	check "timeout logged on stderr" grep -q 'hung.sh timed out' <<< "$STDERR"
	check "Content-Length matches body" content_length_matches
}

# busybox timeout (Alpine) signals only the plugin's own pid, not its children.
# With such a timeout first on PATH, a timed-out plugin must still leave no
# descendants behind, and must still be logged as timed out.
test_timeout_kills_descendants_without_gnu_timeout() {
	echo "Timed-out plugin's children, with a busybox-style timeout..."
	new_case
	local shim_dir="$WORK_DIR/busybox-timeout"
	mkdir -p "$shim_dir"
	cat > "$shim_dir/timeout" <<-'EOF'
		#!/bin/bash
		[ "$1" = -k ] && { echo "timeout: unrecognized option: k" >&2; exit 1; }
		secs="$1"; shift
		"$@" & pid=$!
		( sleep "$secs"; kill -TERM "$pid" ) 2> /dev/null &
		wait "$pid"
	EOF
	chmod +x "$shim_dir/timeout"
	make_plugin "$WORK_DIR/case/plugins.d/hung.sh" 'sleep 31337; echo "hung_metric 1"'
	PATH="$shim_dir:$PATH" METRICS_EXPORTER_PLUGIN_TIMEOUT=1 scrape "file://$FIXTURE_FILE"
	sleep 0.5
	local left=0
	pgrep -f 'sleep 31337' > /dev/null && left=1
	pkill -f 'sleep 31337' 2> /dev/null || true

	check "no plugin descendants left behind" [ "$left" -eq 0 ]
	check "hung.sh success is 0" has_line "$BODY" \
		'metrics_exporter_plugin_success{plugin="plugins.d/hung.sh"} 0'
	check "timeout logged on stderr" grep -q 'hung.sh timed out' <<< "$STDERR"
}

# plugins.d does not need node_exporter's output, so it runs while node_exporter
# is fetched and its plugins run: a slow plugin in each costs one wait, not two.
test_plugin_dirs_run_together() {
	echo "Slow plugins in both directories..."
	new_case
	make_plugin "$WORK_DIR/case/node_exporter-plugins.d/slow.sh" 'cat > /dev/null; sleep 1.5; echo "ne_metric 1"'
	make_plugin "$WORK_DIR/case/plugins.d/slow.sh" 'sleep 1.5; echo "custom_metric 2"'
	local start=$EPOCHREALTIME
	METRICS_EXPORTER_PLUGIN_TIMEOUT=5 scrape "file://$FIXTURE_FILE"
	local elapsed_ms=$(( (${EPOCHREALTIME/./} - ${start/./}) / 1000 ))

	check "both directories finish in one wait (took ${elapsed_ms}ms)" [ "$elapsed_ms" -lt 2500 ]
	check "node_exporter plugin output present" has_line "$BODY" "ne_metric 1"
	check "custom plugin output present" has_line "$BODY" "custom_metric 2"
	check "node_exporter plugin output comes first" \
		[ "$(grep -n 'ne_metric 1' <<< "$BODY" | cut -d: -f1)" -lt "$(grep -n 'custom_metric 2' <<< "$BODY" | cut -d: -f1)" ]
}

# A client that connects and never finishes its request must not hold an
# exporter (and, under systemd, a service instance) forever.
test_stalled_request_gives_up() {
	echo "Client never finishes its request..."
	new_case
	local start=$EPOCHSECONDS rc=0
	# Process substitution: unlike a pipe, bash does not wait for the writer.
	METRICS_EXPORTER_NODE_EXPORTER_URL="file://$FIXTURE_FILE" \
		METRICS_EXPORTER_NODE_EXPORTER_PLUGINS_DIR="$WORK_DIR/case/node_exporter-plugins.d" \
		METRICS_EXPORTER_PLUGINS_DIR="$WORK_DIR/case/plugins.d" \
		timeout 20 "$EXPORTER" < <(printf 'GET /metrics HTTP/1.1\r\n'; sleep 30) \
		> "$WORK_DIR/response" 2> "$WORK_DIR/stderr" || rc=$?
	local elapsed=$((EPOCHSECONDS - start))
	pkill -f 'sleep 30$' 2> /dev/null || true

	check "gives up within 7s (took ${elapsed}s)" [ "$elapsed" -le 7 ]
	check "exits non-zero on its own (not killed by the test)" [ "$rc" -ne 0 -a "$rc" -ne 124 ]
	check "sends no response" [ ! -s "$WORK_DIR/response" ]
	check "logs the stalled request" grep -q 'request' "$WORK_DIR/stderr"
}

test_sigterm_sends_nothing() {
	echo "Exporter gets SIGTERM mid-scrape..."
	new_case
	make_plugin "$WORK_DIR/case/plugins.d/slow.sh" 'sleep 3; echo "slow_metric 1"'
	printf 'GET /metrics HTTP/1.1\r\n\r\n' > "$WORK_DIR/request"
	METRICS_EXPORTER_NODE_EXPORTER_URL="file://$FIXTURE_FILE" \
		METRICS_EXPORTER_NODE_EXPORTER_PLUGINS_DIR="$WORK_DIR/case/node_exporter-plugins.d" \
		METRICS_EXPORTER_PLUGINS_DIR="$WORK_DIR/case/plugins.d" \
		"$EXPORTER" < "$WORK_DIR/request" > "$WORK_DIR/response" 2> /dev/null &
	local pid=$! rc=0
	sleep 0.5
	kill -TERM "$pid"
	wait "$pid" || rc=$?

	check "exits non-zero" [ "$rc" -ne 0 ]
	check "sends no response at all" [ ! -s "$WORK_DIR/response" ]
}

# busybox grep (Alpine, the s6/Docker path) has no -P. Put a grep first on
# PATH that rejects -P the way busybox does, and run the bundled plugins.
test_bundled_plugins_without_grep_P() {
	echo "Bundled plugins with a grep that has no -P (busybox)..."
	local real_grep shim_dir="$WORK_DIR/busybox-grep"
	real_grep="$(command -v grep)"
	mkdir -p "$shim_dir"
	cat > "$shim_dir/grep" <<-EOF
		#!/bin/bash
		for arg in "\$@"; do
		    case "\$arg" in
		        --) break ;;
		        -*P*) [[ "\$arg" != --* ]] && { echo "grep: unrecognized option: P" >&2; exit 2; } ;;
		    esac
		done
		exec "$real_grep" "\$@"
	EOF
	chmod +x "$shim_dir/grep"

	local plugin out
	for plugin in "$SCRIPT_DIR/../node_exporter-plugins.d"/*.sh; do
		out="$(PATH="$shim_dir:$PATH" "$plugin" < "$FIXTURE_FILE" 2>&1)" && rc=0 || rc=$?
		check "$(basename "$plugin") exits 0" [ "$rc" -eq 0 ]
		check "$(basename "$plugin") prints no grep error" lacks_line "$out" "unrecognized option"
	done
	out="$(PATH="$shim_dir:$PATH" "$SCRIPT_DIR/../node_exporter-plugins.d/disk_usage.sh" < "$FIXTURE_FILE")"
	check "disk_usage.sh keeps device/fstype labels" grep -qE '^node_filesystem_size_bytes\{device="[^"]+",fstype="[^"]+",mountpoint="/"\} ' <<< "$out"
	out="$(PATH="$shim_dir:$PATH" "$SCRIPT_DIR/../node_exporter-plugins.d/network.sh" < "$FIXTURE_FILE")"
	check "network.sh still finds devices" grep -qE '^node_network_receive_bytes_total\{device="[^"]+"\} ' <<< "$out"
}

echo "========================================"
echo "Testing metrics-exporter.sh"
echo "========================================"
test_happy_path
test_failing_plugin
test_node_exporter_down
test_output_without_trailing_newline
test_label_escaping
test_hung_plugin_times_out
test_timeout_kills_descendants_without_gnu_timeout
test_plugin_dirs_run_together
test_stalled_request_gives_up
test_sigterm_sends_nothing
test_bundled_plugins_without_grep_P
echo ""
echo "Total: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
