#!/bin/bash
set -euo pipefail
# CPU Plugin
# Outputs aggregated CPU usage by type (user, system, idle, iowait) across all cores

# Read metrics from stdin
NODE_METRICS=$(cat)

# CPU modes to track
MODES=("user" "system" "idle" "iowait" "nice" "irq" "softirq" "steal")

# Output HELP and TYPE
echo '# HELP node_cpu_seconds_total Seconds the CPUs spent in each mode.'
echo '# TYPE node_cpu_seconds_total counter'

# For each mode, sum across all CPUs
for mode in "${MODES[@]}"; do
    TOTAL=$(echo "$NODE_METRICS" | grep -E "^node_cpu_seconds_total.*mode=\"$mode\"" | \
        awk '{sum += $2} END {printf "%.2f", sum}')

    if [ -n "$TOTAL" ] && [ "$TOTAL" != "" ]; then
        echo "node_cpu_seconds_total{mode=\"$mode\"} $TOTAL"
    fi
done

# Calculate CPU usage percentages (requires two samples, so we'll provide raw counters)
# The monitoring system (like Prometheus) will use rate() to calculate percentages

# Output CPU count for reference
CPU_COUNT=$(echo "$NODE_METRICS" | grep -E '^node_cpu_seconds_total' | grep 'mode="idle"' | wc -l)
echo "# HELP node_cpu_count Number of CPU cores."
echo "# TYPE node_cpu_count gauge"
echo "node_cpu_count $CPU_COUNT"
