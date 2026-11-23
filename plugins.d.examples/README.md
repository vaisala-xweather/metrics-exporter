# Plugins

These are where other custom plugins that aren't `node_exporter` related (those should go in `node_exporter-plugins.d`)

> [!Note]
> These do not get installed by default. You must manually copy them to your metrics-exporter `plugins.d` directory if you wish to use them.

## Interface

1. Files must be executable scripts
1. Each script must output valid OpenMetrics formatted data to stdout
1. Scripts get nothing on stdin. They run at the same time as node_exporter is fetched, so they cannot read its output
1. Each script must finish within `METRICS_EXPORTER_PLUGIN_TIMEOUT` seconds (default 2), or it is stopped and its output dropped
