# Metrics Exporter

A custom metrics exporter that extends node_exporter to run custom shell scripts at query time. Follows the best
practices of just-in-time metric generation. Great to run as a sidecar for systems with black box software that doesn't
output in [OpenMetrics](https://prometheus.io/docs/specs/om/open_metrics_spec/) format. Users can transform those outputs,
files, or logs into OpenMetrics format on-demand.

Thanks to [Vaisala Xweather](https://xweather.com) for sponsoring development.


## Quickstart

If you're running on a system with `systemd`:

```bash
git clone https://github.com/vaisala-xweather/metrics-exporter.git
sudo ./metrics-exporter/install.sh

# Test
curl http://localhost:9100/metrics
```

## How It Works

1. systemd listens on port 9100 via the `.socket` unit
1. When a connection arrives, systemd spawns an instance of the `.service` unit
1. The service runs `metrics-exporter.sh` with stdin/stdout connected to the socket
    1. The service reads once from node_exporter on localhost:9101 and sends that output to be filtered by each plugin in `/etc/metrics-exporter/node_exporter-plugins.d/`. Each plugin reads from stdin and outputs its own metrics to stdout.
    1. Next, the service runs each script in `/etc/metrics-exporter/plugins.d/`, appending the metrics to stdin for each script to process and output its own metrics to stdout. See plugins.d.examples for some sample scripts.
1. The OpenMetrics formatted response is sent back to the client
1. After the response is sent, the script exits and the service instance terminates

### In Docker

1. When running in a Docker container, we can leverage the [s6](https://skarnet.org/software/s6-linux-init/) init system
1. `s6-overlay` manages a `socat` process that listens on port `9100`
1. When a connection arrives, `socat` forks a child process that runs `metrics-exporter.sh` with stdin/stdout connected to the socket
    1. node-exporter behaves the same, with the only difference being that it runs under s6-overlay instead of systemd when listening for connections
1. The OpenMetrics formatted response is sent back to the client
1. Any logs or errors sent from `metrics-exporter.sh` over stderr are sent to `/var/log/metrics-exporter/` via s6-overlay's logutil-service
1. After the response is sent, the script exits and the socat child process terminates
