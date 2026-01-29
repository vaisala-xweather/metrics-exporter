# Plugins

These are where other custom plugins that aren't `node_exporter` related (those should go in `node_exporter-plugins.d`)

> [!Note]
> These do not get installed by default. You must manually copy them to your metrics-exporter `plugins.d` directory if you wish to use them.

## Interface

1. Files must be executable scripts
1. Each script must output valid OpenMetrics formatted data to stdout
