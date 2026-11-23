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
test_sigterm_sends_nothing
test_bundled_plugins_without_grep_P
echo ""
echo "Total: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
