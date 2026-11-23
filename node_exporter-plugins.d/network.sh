#!/bin/bash
set -euo pipefail
# Network Plugin
# Outputs rx/tx bytes, errors and drops per network device, leaving out
# loopback (lo) and container interfaces (docker*, br-*, veth*). Reads
# node_exporter metrics on stdin. A host with no other interfaces gets the
# HELP/TYPE lines and no samples.

awk '
/^node_network_(receive|transmit)_(bytes|errs|drop)_total\{/ && match($0, /[{,]device="[^"]*"/) {
	dev = substr($0, RSTART + 9, RLENGTH - 10)
	if (dev == "lo" || dev ~ /^(docker|br-|veth)/) next
	name = substr($0, 1, index($0, "{") - 1)
	value[name, dev] = $NF
	# Devices in the order node_exporter lists them (sorted).
	if (name == "node_network_receive_bytes_total" && !(dev in seen)) {
		seen[dev] = 1
		devs[++ndev] = dev
	}
}
END {
	n = split("receive_bytes transmit_bytes receive_errs transmit_errs receive_drop transmit_drop", stats, " ")
	for (i = 1; i <= n; i++) {
		name = "node_network_" stats[i] "_total"
		print "# HELP " name " Network device statistic " stats[i] "."
		print "# TYPE " name " counter"
		for (d = 1; d <= ndev; d++)
			if ((name, devs[d]) in value)
				printf "%s{device=\"%s\"} %s\n", name, devs[d], value[name, devs[d]]
	}
}'
