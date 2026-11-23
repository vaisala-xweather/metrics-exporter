#!/bin/bash
set -euo pipefail
# CPU Plugin
# Outputs CPU seconds per mode (user, system, idle, iowait, ...) summed across
# all cores, and the number of cores. Reads node_exporter metrics on stdin.
# A mode with no samples, or the core count when node_exporter's cpu collector
# is off, is left out rather than reported as 0.
# Prometheus computes usage percentages from these counters with rate().

awk '
/^node_cpu_seconds_total\{/ && match($0, /[{,]mode="[^"]*"/) {
	mode = substr($0, RSTART + 7, RLENGTH - 8)
	sum[mode] += $NF
	if (mode == "idle") cpus++
}
END {
	n = split("user system idle iowait nice irq softirq steal", modes, " ")
	print "# HELP node_cpu_seconds_total Seconds the CPUs spent in each mode."
	print "# TYPE node_cpu_seconds_total counter"
	for (i = 1; i <= n; i++)
		if (modes[i] in sum)
			printf "node_cpu_seconds_total{mode=\"%s\"} %.2f\n", modes[i], sum[modes[i]]
	if (cpus > 0) {
		print "# HELP node_cpu_count Number of CPU cores."
		print "# TYPE node_cpu_count gauge"
		print "node_cpu_count " cpus
	}
}'
