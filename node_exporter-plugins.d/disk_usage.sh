#!/bin/bash
set -uo pipefail
# Disk Usage Plugin
# Outputs disk usage for root partition and other important partitions (/, /tmp, /var, /home)

# Read metrics from stdin
NODE_METRICS=$(cat)

# Partitions to monitor
PARTITIONS=("/" "/tmp" "/var" "/home")

# Output HELP and TYPE for size metrics
echo '# HELP node_filesystem_size_bytes Filesystem size in bytes.'
echo '# TYPE node_filesystem_size_bytes gauge'

# Output filesystem size
for partition in "${PARTITIONS[@]}"; do
    SIZE=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_size_bytes.*mountpoint=\"$partition\"" | awk '{print $2}')
    if [ -n "$SIZE" ]; then
        DEVICE=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_size_bytes.*mountpoint=\"$partition\"" | grep -oP 'device="[^"]*"')
        FSTYPE=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_size_bytes.*mountpoint=\"$partition\"" | grep -oP 'fstype="[^"]*"')
        echo "node_filesystem_size_bytes{$DEVICE,$FSTYPE,mountpoint=\"$partition\"} $SIZE"
    fi
done

# Output HELP and TYPE for available bytes
echo '# HELP node_filesystem_avail_bytes Filesystem space available to non-root users in bytes.'
echo '# TYPE node_filesystem_avail_bytes gauge'

# Output available space
for partition in "${PARTITIONS[@]}"; do
    AVAIL=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_avail_bytes.*mountpoint=\"$partition\"" | awk '{print $2}')
    if [ -n "$AVAIL" ]; then
        DEVICE=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_avail_bytes.*mountpoint=\"$partition\"" | grep -oP 'device="[^"]*"')
        FSTYPE=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_avail_bytes.*mountpoint=\"$partition\"" | grep -oP 'fstype="[^"]*"')
        echo "node_filesystem_avail_bytes{$DEVICE,$FSTYPE,mountpoint=\"$partition\"} $AVAIL"
    fi
done

# Calculate and output usage percentage
echo '# HELP node_filesystem_usage_percent Filesystem usage percentage.'
echo '# TYPE node_filesystem_usage_percent gauge'

for partition in "${PARTITIONS[@]}"; do
    SIZE=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_size_bytes.*mountpoint=\"$partition\"" | awk '{print $2}')
    AVAIL=$(echo "$NODE_METRICS" | grep -E "^node_filesystem_avail_bytes.*mountpoint=\"$partition\"" | awk '{print $2}')

    if [ -n "$SIZE" ] && [ -n "$AVAIL" ]; then
        # Use AWK to calculate percentage, handles scientific notation natively
        PERCENT=$(awk -v size="$SIZE" -v avail="$AVAIL" 'BEGIN {
            if (size > 0) {
                used = size - avail
                percent = (used / size) * 100
                printf "%.2f", percent
            }
        }')
        if [ -n "$PERCENT" ]; then
            echo "node_filesystem_usage_percent{mountpoint=\"$partition\"} $PERCENT"
        fi
    fi
done
