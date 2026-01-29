#!/bin/bash
set -euo pipefail
# Memory Plugin
# Outputs memory usage (used, free, cached, buffers, swap)

# Read metrics from stdin
NODE_METRICS=$(cat)

# Extract memory metrics
MEM_TOTAL=$(echo "$NODE_METRICS" | grep '^node_memory_MemTotal_bytes ' | awk '{print $2}')
MEM_FREE=$(echo "$NODE_METRICS" | grep '^node_memory_MemFree_bytes ' | awk '{print $2}')
MEM_AVAILABLE=$(echo "$NODE_METRICS" | grep '^node_memory_MemAvailable_bytes ' | awk '{print $2}')
MEM_BUFFERS=$(echo "$NODE_METRICS" | grep '^node_memory_Buffers_bytes ' | awk '{print $2}')
MEM_CACHED=$(echo "$NODE_METRICS" | grep '^node_memory_Cached_bytes ' | awk '{print $2}')
SWAP_TOTAL=$(echo "$NODE_METRICS" | grep '^node_memory_SwapTotal_bytes ' | awk '{print $2}')
SWAP_FREE=$(echo "$NODE_METRICS" | grep '^node_memory_SwapFree_bytes ' | awk '{print $2}')

# Calculate used memory (Total - Free - Buffers - Cached)
if [ -n "$MEM_TOTAL" ] && [ -n "$MEM_FREE" ] && [ -n "$MEM_BUFFERS" ] && [ -n "$MEM_CACHED" ]; then
    MEM_USED=$(awk "BEGIN {print $MEM_TOTAL - $MEM_FREE - $MEM_BUFFERS - $MEM_CACHED}")
else
    MEM_USED=0
fi

# Calculate swap used
if [ -n "$SWAP_TOTAL" ] && [ -n "$SWAP_FREE" ]; then
    SWAP_USED=$(awk "BEGIN {print $SWAP_TOTAL - $SWAP_FREE}")
else
    SWAP_USED=0
fi

# Output metrics
cat <<EOF
# HELP node_memory_MemTotal_bytes Total memory in bytes.
# TYPE node_memory_MemTotal_bytes gauge
node_memory_MemTotal_bytes ${MEM_TOTAL:-0}
# HELP node_memory_MemFree_bytes Free memory in bytes.
# TYPE node_memory_MemFree_bytes gauge
node_memory_MemFree_bytes ${MEM_FREE:-0}
# HELP node_memory_MemAvailable_bytes Available memory in bytes.
# TYPE node_memory_MemAvailable_bytes gauge
node_memory_MemAvailable_bytes ${MEM_AVAILABLE:-0}
# HELP node_memory_MemUsed_bytes Used memory in bytes (Total - Free - Buffers - Cached).
# TYPE node_memory_MemUsed_bytes gauge
node_memory_MemUsed_bytes $MEM_USED
# HELP node_memory_Buffers_bytes Memory used for buffers in bytes.
# TYPE node_memory_Buffers_bytes gauge
node_memory_Buffers_bytes ${MEM_BUFFERS:-0}
# HELP node_memory_Cached_bytes Memory used for cache in bytes.
# TYPE node_memory_Cached_bytes gauge
node_memory_Cached_bytes ${MEM_CACHED:-0}
# HELP node_memory_SwapTotal_bytes Total swap space in bytes.
# TYPE node_memory_SwapTotal_bytes gauge
node_memory_SwapTotal_bytes ${SWAP_TOTAL:-0}
# HELP node_memory_SwapFree_bytes Free swap space in bytes.
# TYPE node_memory_SwapFree_bytes gauge
node_memory_SwapFree_bytes ${SWAP_FREE:-0}
# HELP node_memory_SwapUsed_bytes Used swap space in bytes.
# TYPE node_memory_SwapUsed_bytes gauge
node_memory_SwapUsed_bytes $SWAP_USED
EOF
