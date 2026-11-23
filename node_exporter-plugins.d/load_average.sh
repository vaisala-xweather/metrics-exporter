#!/bin/bash
set -euo pipefail
# Load Average Plugin
# Outputs the 1, 5 and 15 minute load averages, and each one divided by the
# number of cores. Reads node_exporter metrics on stdin. A missing load average
# is left out, and so are the normalized values when there is no core count
# (node_exporter's cpu collector is off).

awk '
/^node_cpu_seconds_total\{/ && /[{,]mode="idle"/ { cpus++ }
$1 == "node_load1" || $1 == "node_load5" || $1 == "node_load15" { load[substr($1, 10)] = $2 }
END {
	split("1 5 15", periods, " ")
	for (i = 1; i <= 3; i++) {
		p = periods[i]
		if (!(p in load)) continue
		print "# HELP node_load" p " " p "m load average."
		print "# TYPE node_load" p " gauge"
		print "node_load" p " " load[p]
	}
	if (cpus == 0) exit
	for (i = 1; i <= 3; i++) {
		p = periods[i]
		if (!(p in load)) continue
		print "# HELP node_load_normalized_" p " " p "m load average normalized per CPU."
		print "# TYPE node_load_normalized_" p " gauge"
		printf "node_load_normalized_%s %.2f\n", p, load[p] / cpus
	}
}'
