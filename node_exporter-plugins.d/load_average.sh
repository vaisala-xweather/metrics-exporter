#!/bin/bash
set -euo pipefail
# Load Average Plugin
# Outputs load average and normalized load average (per CPU)

# Read metrics from stdin
NODE_METRICS=$(cat)

# Get CPU count
CPU_COUNT=$(echo "$NODE_METRICS" | grep -E '^node_cpu_seconds_total' | grep 'mode="idle"' | wc -l)

# Extract load averages
LOAD1=$(echo "$NODE_METRICS" | grep '^node_load1 ' | awk '{print $2}')
LOAD5=$(echo "$NODE_METRICS" | grep '^node_load5 ' | awk '{print $2}')
LOAD15=$(echo "$NODE_METRICS" | grep '^node_load15 ' | awk '{print $2}')

# Calculate normalized load (load per CPU)
if [ "$CPU_COUNT" -gt 0 ]; then
    NORM_LOAD1=$(awk -v load1="$LOAD1" -v cpus="$CPU_COUNT" 'BEGIN {printf "%.2f", load1 / cpus}')
    NORM_LOAD5=$(awk -v load5="$LOAD5" -v cpus="$CPU_COUNT" 'BEGIN {printf "%.2f", load5 / cpus}')
    NORM_LOAD15=$(awk -v load15="$LOAD15" -v cpus="$CPU_COUNT" 'BEGIN {printf "%.2f", load15 / cpus}')
else
    NORM_LOAD1=0
    NORM_LOAD5=0
    NORM_LOAD15=0
fi

# Output metrics in Prometheus format
cat <<EOF
# HELP node_load1 1m load average.
# TYPE node_load1 gauge
node_load1 $LOAD1
# HELP node_load5 5m load average.
# TYPE node_load5 gauge
node_load5 $LOAD5
# HELP node_load15 15m load average.
# TYPE node_load15 gauge
node_load15 $LOAD15
# HELP node_load_normalized_1 1m load average normalized per CPU.
# TYPE node_load_normalized_1 gauge
node_load_normalized_1 $NORM_LOAD1
# HELP node_load_normalized_5 5m load average normalized per CPU.
# TYPE node_load_normalized_5 gauge
node_load_normalized_5 $NORM_LOAD5
# HELP node_load_normalized_15 15m load average normalized per CPU.
# TYPE node_load_normalized_15 gauge
node_load_normalized_15 $NORM_LOAD15
EOF
