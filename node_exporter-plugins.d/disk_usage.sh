#!/bin/bash
set -euo pipefail
# Disk Usage Plugin
# Outputs size, available bytes and usage percent for /, /tmp, /var and /home.
# Reads node_exporter metrics on stdin. When node_exporter reports more than one
# filesystem on a mount point (e.g. stacked or overlay mounts in a container),
# only the first one is reported, so each series appears once.

awk '
BEGIN {
	n = split("/ /tmp /var /home", parts, " ")
	for (i = 1; i <= n; i++) wanted[parts[i]] = 1
}
/^node_filesystem_(size|avail)_bytes\{/ && match($0, /[{,]mountpoint="[^"]*"/) {
	mp = substr($0, RSTART + 13, RLENGTH - 14)
	kind = ($0 ~ /^node_filesystem_size/) ? "size" : "avail"
	if (!(mp in wanted) || ((kind, mp) in value)) next
	labels = ""
	if (match($0, /[{,]device="[^"]*"/)) labels = substr($0, RSTART + 1, RLENGTH - 1) ","
	if (match($0, /[{,]fstype="[^"]*"/)) labels = labels substr($0, RSTART + 1, RLENGTH - 1) ","
	value[kind, mp] = $NF
	label[kind, mp] = labels
}
function series(kind, help) {
	print "# HELP node_filesystem_" kind "_bytes " help
	print "# TYPE node_filesystem_" kind "_bytes gauge"
	for (i = 1; i <= n; i++)
		if ((kind, parts[i]) in value)
			printf "node_filesystem_%s_bytes{%smountpoint=\"%s\"} %s\n",
				kind, label[kind, parts[i]], parts[i], value[kind, parts[i]]
}
END {
	series("size", "Filesystem size in bytes.")
	series("avail", "Filesystem space available to non-root users in bytes.")
	print "# HELP node_filesystem_usage_percent Filesystem usage percentage."
	print "# TYPE node_filesystem_usage_percent gauge"
	for (i = 1; i <= n; i++) {
		mp = parts[i]
		if (!(("size", mp) in value) || !(("avail", mp) in value) || value["size", mp] <= 0) continue
		printf "node_filesystem_usage_percent{mountpoint=\"%s\"} %.2f\n",
			mp, (value["size", mp] - value["avail", mp]) / value["size", mp] * 100
	}
}'
