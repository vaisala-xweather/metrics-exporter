#!/bin/bash
set -euo pipefail

# Test runner for node_exporter plugins
# Usage: ./test_node_exporter_plugins.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/../node_exporter-plugins.d"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
FIXTURE_FILE="$FIXTURES_DIR/node_exporter.example.txt"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to print test result
print_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"

    if [ "$result" == "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        if [ -n "$message" ]; then
            echo "  Error: $message"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Helper function to check if output contains expected metric
check_metric_exists() {
    local output="$1"
    local metric_name="$2"

    if echo "$output" | grep -q "^$metric_name"; then
        return 0
    else
        return 1
    fi
}

# Helper function to check if output is valid Prometheus format
check_prometheus_format() {
    local output="$1"

    # Check for HELP and TYPE comments
    if ! echo "$output" | grep -q "^# HELP"; then
        return 1
    fi

    if ! echo "$output" | grep -q "^# TYPE"; then
        return 1
    fi

    # Check for at least one metric line (not a comment)
    if ! echo "$output" | grep -qE "^[^#]"; then
        return 1
    fi

    return 0
}

# Helper function to run a plugin and capture output (stderr discarded for clean output)
run_plugin() {
    local plugin="$1"
    local exit_code=0
    local output
    output=$(cat "$FIXTURE_FILE" | "$plugin" 2>/dev/null) || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        return $exit_code
    fi

    echo "$output"
    return 0
}

# Test CPU plugin
test_cpu_plugin() {
    local plugin="$PLUGINS_DIR/cpu.sh"
    local test_name="cpu.sh"

    if [ ! -x "$plugin" ]; then
        print_result "$test_name - executable" "FAIL" "Plugin is not executable"
        return
    fi
    print_result "$test_name - executable" "PASS"

    # Run plugin
    local output
    if ! output=$(run_plugin "$plugin"); then
        print_result "$test_name - runs without error" "FAIL" "Plugin exited with non-zero status"
        return
    fi
    print_result "$test_name - runs without error" "PASS"

    # Check Prometheus format
    if ! check_prometheus_format "$output"; then
        print_result "$test_name - valid Prometheus format" "FAIL" "Output is not valid Prometheus format"
        return
    fi
    print_result "$test_name - valid Prometheus format" "PASS"

    # Check for expected metrics
    if ! check_metric_exists "$output" "node_cpu_seconds_total"; then
        print_result "$test_name - contains node_cpu_seconds_total" "FAIL"
        return
    fi
    print_result "$test_name - contains node_cpu_seconds_total" "PASS"

    if ! check_metric_exists "$output" "node_cpu_count"; then
        print_result "$test_name - contains node_cpu_count" "FAIL"
        return
    fi
    print_result "$test_name - contains node_cpu_count" "PASS"

    # Check that CPU modes are present
    local modes=("user" "system" "idle" "iowait")
    for mode in "${modes[@]}"; do
        if ! echo "$output" | grep -q "mode=\"$mode\""; then
            print_result "$test_name - contains mode=$mode" "FAIL"
            return
        fi
    done
    print_result "$test_name - contains all CPU modes" "PASS"
}

# Test Memory plugin
test_memory_plugin() {
    local plugin="$PLUGINS_DIR/memory.sh"
    local test_name="memory.sh"

    if [ ! -x "$plugin" ]; then
        print_result "$test_name - executable" "FAIL" "Plugin is not executable"
        return
    fi
    print_result "$test_name - executable" "PASS"

    # Run plugin
    local output
    if ! output=$(run_plugin "$plugin"); then
        print_result "$test_name - runs without error" "FAIL" "Plugin exited with non-zero status"
        return
    fi
    print_result "$test_name - runs without error" "PASS"

    # Check Prometheus format
    if ! check_prometheus_format "$output"; then
        print_result "$test_name - valid Prometheus format" "FAIL" "Output is not valid Prometheus format"
        return
    fi
    print_result "$test_name - valid Prometheus format" "PASS"

    # Check for expected metrics
    local metrics=("node_memory_MemTotal_bytes" "node_memory_MemFree_bytes" "node_memory_MemAvailable_bytes" "node_memory_MemUsed_bytes")
    for metric in "${metrics[@]}"; do
        if ! check_metric_exists "$output" "$metric"; then
            print_result "$test_name - contains $metric" "FAIL"
            return
        fi
    done
    print_result "$test_name - contains all memory metrics" "PASS"
}

# Test Disk Usage plugin
test_disk_usage_plugin() {
    local plugin="$PLUGINS_DIR/disk_usage.sh"
    local test_name="disk_usage.sh"

    if [ ! -x "$plugin" ]; then
        print_result "$test_name - executable" "FAIL" "Plugin is not executable"
        return
    fi
    print_result "$test_name - executable" "PASS"

    # Run plugin
    local output
    if ! output=$(run_plugin "$plugin"); then
        print_result "$test_name - runs without error" "FAIL" "Plugin exited with non-zero status"
        return
    fi
    print_result "$test_name - runs without error" "PASS"

    # Check Prometheus format
    if ! check_prometheus_format "$output"; then
        print_result "$test_name - valid Prometheus format" "FAIL" "Output is not valid Prometheus format"
        return
    fi
    print_result "$test_name - valid Prometheus format" "PASS"

    # Check for expected metrics
    local metrics=("node_filesystem_size_bytes" "node_filesystem_avail_bytes" "node_filesystem_usage_percent")
    for metric in "${metrics[@]}"; do
        if ! check_metric_exists "$output" "$metric"; then
            print_result "$test_name - contains $metric" "FAIL"
            return
        fi
    done
    print_result "$test_name - contains all disk metrics" "PASS"
}

# Test Load Average plugin
test_load_average_plugin() {
    local plugin="$PLUGINS_DIR/load_average.sh"
    local test_name="load_average.sh"

    if [ ! -x "$plugin" ]; then
        print_result "$test_name - executable" "FAIL" "Plugin is not executable"
        return
    fi
    print_result "$test_name - executable" "PASS"

    # Run plugin
    local output
    if ! output=$(run_plugin "$plugin"); then
        print_result "$test_name - runs without error" "FAIL" "Plugin exited with non-zero status"
        return
    fi
    print_result "$test_name - runs without error" "PASS"

    # Check Prometheus format
    if ! check_prometheus_format "$output"; then
        print_result "$test_name - valid Prometheus format" "FAIL" "Output is not valid Prometheus format"
        return
    fi
    print_result "$test_name - valid Prometheus format" "PASS"

    # Check for expected metrics
    local metrics=("node_load1" "node_load5" "node_load15" "node_load_normalized_1" "node_load_normalized_5" "node_load_normalized_15")
    for metric in "${metrics[@]}"; do
        if ! check_metric_exists "$output" "$metric"; then
            print_result "$test_name - contains $metric" "FAIL"
            return
        fi
    done
    print_result "$test_name - contains all load average metrics" "PASS"
}

# Test Network plugin
test_network_plugin() {
    local plugin="$PLUGINS_DIR/network.sh"
    local test_name="network.sh"

    if [ ! -x "$plugin" ]; then
        print_result "$test_name - executable" "FAIL" "Plugin is not executable"
        return
    fi
    print_result "$test_name - executable" "PASS"

    # Run plugin
    local output
    if ! output=$(run_plugin "$plugin"); then
        print_result "$test_name - runs without error" "FAIL" "Plugin exited with non-zero status"
        return
    fi
    print_result "$test_name - runs without error" "PASS"

    # Check Prometheus format
    if ! check_prometheus_format "$output"; then
        print_result "$test_name - valid Prometheus format" "FAIL" "Output is not valid Prometheus format"
        return
    fi
    print_result "$test_name - valid Prometheus format" "PASS"

    # Check for expected metrics
    local metrics=("node_network_receive_bytes_total" "node_network_transmit_bytes_total" "node_network_receive_errs_total" "node_network_transmit_errs_total")
    for metric in "${metrics[@]}"; do
        if ! check_metric_exists "$output" "$metric"; then
            print_result "$test_name - contains $metric" "FAIL"
            return
        fi
    done
    print_result "$test_name - contains all network metrics" "PASS"
}

# True if every sample line is "name[{labels}] value" and no series repeats.
# Prometheus rejects the whole scrape when either rule breaks.
valid_exposition() {
    local samples
    samples="$(grep -v '^#' <<< "$1" | grep -v '^$' || true)"
    [ -z "$samples" ] && return 0
    grep -qvE '^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[^}]*\})? [^ ]+$' <<< "$samples" && return 1
    [ -z "$(awk '{$NF=""; print}' <<< "$samples" | sort | uniq -d)" ]
}

# Run a plugin on given input. Sets OUT and RC.
run_on() {
    RC=0
    OUT="$("$PLUGINS_DIR/$1" <<< "$2" 2>/dev/null)" || RC=$?
}

check_case() {
    local name="$1"
    shift
    if "$@"; then print_result "$name" "PASS"; else print_result "$name" "FAIL"; fi
}

# Every bundled plugin on the full fixture, on empty input, and on input that
# lacks the metrics it reads: always exit 0 with a valid exposition.
test_all_plugins_partial_input() {
    local plugin name
    for plugin in "$PLUGINS_DIR"/*.sh; do
        name="$(basename "$plugin")"
        run_on "$name" "$(cat "$FIXTURE_FILE")"
        check_case "$name - fixture output is a valid exposition" valid_exposition "$OUT"
        run_on "$name" ""
        check_case "$name - empty input exits 0" [ "$RC" -eq 0 ]
        check_case "$name - empty input gives a valid exposition" valid_exposition "$OUT"
        run_on "$name" 'node_unrelated_metric 1'
        check_case "$name - unrelated input exits 0" [ "$RC" -eq 0 ]
    done
}

test_disk_usage_duplicate_mountpoint() {
    run_on disk_usage.sh 'node_filesystem_size_bytes{device="overlay",fstype="overlay",mountpoint="/"} 100
node_filesystem_size_bytes{device="/dev/sda1",fstype="ext4",mountpoint="/"} 200
node_filesystem_avail_bytes{device="overlay",fstype="overlay",mountpoint="/"} 25
node_filesystem_avail_bytes{device="/dev/sda1",fstype="ext4",mountpoint="/"} 50'
    check_case "disk_usage.sh - two / mounts exit 0" [ "$RC" -eq 0 ]
    check_case "disk_usage.sh - two / mounts give a valid exposition" valid_exposition "$OUT"
    check_case "disk_usage.sh - first / mount is reported" grep -qxF \
        'node_filesystem_size_bytes{device="overlay",fstype="overlay",mountpoint="/"} 100' <<< "$OUT"
    check_case "disk_usage.sh - usage percent from the same mount" grep -qxF \
        'node_filesystem_usage_percent{mountpoint="/"} 75.00' <<< "$OUT"
}

test_memory_missing_metric() {
    run_on memory.sh 'node_memory_MemTotal_bytes 1000
node_memory_MemFree_bytes 400'
    check_case "memory.sh - missing metrics exit 0" [ "$RC" -eq 0 ]
    check_case "memory.sh - present metric still reported" grep -qxF 'node_memory_MemTotal_bytes 1000' <<< "$OUT"
    check_case "memory.sh - missing metric left out, not faked as 0" \
        bash -c '! grep -q "^node_memory_MemAvailable_bytes" <<< "$1"' _ "$OUT"
}

test_load_average_without_cpu() {
    run_on load_average.sh 'node_load1 0.5
node_load5 0.25
node_load15 0.1'
    check_case "load_average.sh - no cpu metrics exits 0" [ "$RC" -eq 0 ]
    check_case "load_average.sh - load still reported" grep -qxF 'node_load1 0.5' <<< "$OUT"
    check_case "load_average.sh - no normalized load without a CPU count" \
        bash -c '! grep -q "^node_load_normalized" <<< "$1"' _ "$OUT"
}

test_network_edge_cases() {
    run_on network.sh 'node_network_receive_bytes_total{device="lo"} 10'
    check_case "network.sh - only lo exits 0" [ "$RC" -eq 0 ]
    check_case "network.sh - only lo reports no device" bash -c '! grep -q "device=" <<< "$1"' _ "$OUT"

    run_on network.sh 'node_network_receive_bytes_total{device="eth0.100"} 1
node_network_receive_bytes_total{device="eth0x100"} 2'
    check_case "network.sh - dotted device name gives a valid exposition" valid_exposition "$OUT"
    check_case "network.sh - dotted device keeps its own value" grep -qxF \
        'node_network_receive_bytes_total{device="eth0.100"} 1' <<< "$OUT"
}

# Main test execution
main() {
    echo "========================================"
    echo "Testing node_exporter plugins"
    echo "========================================"
    echo ""

    # Check if fixture file exists
    if [ ! -f "$FIXTURE_FILE" ]; then
        echo -e "${RED}Error: Fixture file not found: $FIXTURE_FILE${NC}"
        exit 1
    fi

    # Run tests for each plugin
    echo "Testing cpu.sh..."
    test_cpu_plugin
    echo ""

    echo "Testing memory.sh..."
    test_memory_plugin
    echo ""

    echo "Testing disk_usage.sh..."
    test_disk_usage_plugin
    echo ""

    echo "Testing load_average.sh..."
    test_load_average_plugin
    echo ""

    echo "Testing network.sh..."
    test_network_plugin
    echo ""

    echo "Testing partial and unusual input..."
    test_all_plugins_partial_input
    test_disk_usage_duplicate_mountpoint
    test_memory_missing_metric
    test_load_average_without_cpu
    test_network_edge_cases
    echo ""

    # Print summary
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Total tests run: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Run main function
main
