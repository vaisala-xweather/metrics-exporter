# node_exporter Plugins

Each of these plugins will receive `node_exporter` data via stdin. They should return
[OpenMetrics](https://prometheus.io/docs/specs/om/open_metrics_spec/) formatted data on stdout.

## Plugins

1. CPU - output aggregated over all cores CPU usage by type (user, system, idle, iowait)
1. Disk Usage - output disk usage for root partition and any other important partitions (only care about /, /tmp, /var, /home)
1. Load Average - output load average and normalized load average (per CPU)
1. Memory - output memory usage (used, free, cached, buffers, swap)
1. Network - output network stats (rx/tx bytes, errors, drops) for non-loopback and non-docker interfaces
