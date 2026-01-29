#!/bin/bash
set -euo pipefail
# Network Plugin
# Outputs network stats (rx/tx bytes, errors, drops) for non-loopback and non-docker interfaces

# Read metrics from stdin
NODE_METRICS=$(cat)

# Get list of all network devices, excluding loopback (lo) and docker interfaces
DEVICES=$(echo "$NODE_METRICS" | grep -E '^node_network_receive_bytes_total' | \
    grep -oP 'device="[^"]*"' | cut -d'"' -f2 | \
    grep -v '^lo$' | grep -v '^docker' | grep -v '^br-' | grep -v '^veth' | sort -u)

# Receive bytes
echo '# HELP node_network_receive_bytes_total Network device statistic receive_bytes.'
echo '# TYPE node_network_receive_bytes_total counter'
for dev in $DEVICES; do
    VALUE=$(echo "$NODE_METRICS" | grep -E "^node_network_receive_bytes_total.*device=\"$dev\"" | awk '{print $2}')
    if [ -n "$VALUE" ]; then
        echo "node_network_receive_bytes_total{device=\"$dev\"} $VALUE"
    fi
done

# Transmit bytes
echo '# HELP node_network_transmit_bytes_total Network device statistic transmit_bytes.'
echo '# TYPE node_network_transmit_bytes_total counter'
for dev in $DEVICES; do
    VALUE=$(echo "$NODE_METRICS" | grep -E "^node_network_transmit_bytes_total.*device=\"$dev\"" | awk '{print $2}')
    if [ -n "$VALUE" ]; then
        echo "node_network_transmit_bytes_total{device=\"$dev\"} $VALUE"
    fi
done

# Receive errors
echo '# HELP node_network_receive_errs_total Network device statistic receive_errs.'
echo '# TYPE node_network_receive_errs_total counter'
for dev in $DEVICES; do
    VALUE=$(echo "$NODE_METRICS" | grep -E "^node_network_receive_errs_total.*device=\"$dev\"" | awk '{print $2}')
    if [ -n "$VALUE" ]; then
        echo "node_network_receive_errs_total{device=\"$dev\"} $VALUE"
    fi
done

# Transmit errors
echo '# HELP node_network_transmit_errs_total Network device statistic transmit_errs.'
echo '# TYPE node_network_transmit_errs_total counter'
for dev in $DEVICES; do
    VALUE=$(echo "$NODE_METRICS" | grep -E "^node_network_transmit_errs_total.*device=\"$dev\"" | awk '{print $2}')
    if [ -n "$VALUE" ]; then
        echo "node_network_transmit_errs_total{device=\"$dev\"} $VALUE"
    fi
done

# Receive drops
echo '# HELP node_network_receive_drop_total Network device statistic receive_drop.'
echo '# TYPE node_network_receive_drop_total counter'
for dev in $DEVICES; do
    VALUE=$(echo "$NODE_METRICS" | grep -E "^node_network_receive_drop_total.*device=\"$dev\"" | awk '{print $2}')
    if [ -n "$VALUE" ]; then
        echo "node_network_receive_drop_total{device=\"$dev\"} $VALUE"
    fi
done

# Transmit drops
echo '# HELP node_network_transmit_drop_total Network device statistic transmit_drop.'
echo '# TYPE node_network_transmit_drop_total counter'
for dev in $DEVICES; do
    VALUE=$(echo "$NODE_METRICS" | grep -E "^node_network_transmit_drop_total.*device=\"$dev\"" | awk '{print $2}')
    if [ -n "$VALUE" ]; then
        echo "node_network_transmit_drop_total{device=\"$dev\"} $VALUE"
    fi
done
