#!/bin/bash
set -euo pipefail
# Memory Plugin
# Outputs memory and swap usage (total, free, available, used, buffers,
# cached). Reads node_exporter metrics on stdin. A metric node_exporter does not
# report is left out rather than reported as 0, and so is a used value that
# depends on it.

awk '
/^node_memory_[A-Za-z]+_bytes / { v[substr($1, 13, length($1) - 18)] = $2 }
function out(name, help, value) {
	print "# HELP node_memory_" name "_bytes " help
	print "# TYPE node_memory_" name "_bytes gauge"
	print "node_memory_" name "_bytes " value
}
function report(name, help) { if (name in v) out(name, help, v[name]) }
END {
	report("MemTotal", "Total memory in bytes.")
	report("MemFree", "Free memory in bytes.")
	report("MemAvailable", "Available memory in bytes.")
	if (("MemTotal" in v) && ("MemFree" in v) && ("Buffers" in v) && ("Cached" in v))
		out("MemUsed", "Used memory in bytes (Total - Free - Buffers - Cached).",
			v["MemTotal"] - v["MemFree"] - v["Buffers"] - v["Cached"])
	report("Buffers", "Memory used for buffers in bytes.")
	report("Cached", "Memory used for cache in bytes.")
	report("SwapTotal", "Total swap space in bytes.")
	report("SwapFree", "Free swap space in bytes.")
	if (("SwapTotal" in v) && ("SwapFree" in v))
		out("SwapUsed", "Used swap space in bytes.", v["SwapTotal"] - v["SwapFree"])
}'
