# Metrics Exporter

A custom metrics exporter that extends node_exporter to run custom shell scripts at query time. Follows the best
practices of just-in-time metric generation. Great to run as a sidecar for systems with black box software that doesn't
output in [OpenMetrics](https://prometheus.io/docs/specs/om/open_metrics_spec/) format. Users can transform those outputs,
files, or logs into OpenMetrics format on-demand.

Thanks to [Vaisala Xweather](https://xweather.com) for sponsoring development.
<p><img src="https://www.xweather.com/assets/logos/vaisala-xweather-logo-light-example.svg" alt="Vaisala Xweather Logo" width="350"/></p>

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

## Self-monitoring metrics

The exporter builds the whole response before it sends any headers. When a plugin fails or node_exporter is
unreachable, the scrape still returns `200 OK` with everything else in it, and reports what failed with these metrics:

| Metric | Meaning |
| --- | --- |
| `metrics_exporter_node_exporter_up` | `1` if node_exporter answered on `localhost:9101`, `0` if not. When `0`, the node_exporter plugins are skipped and `plugins.d` still runs. |
| `metrics_exporter_plugin_success{plugin="<dir>/<file>"}` | `1` if the plugin exited 0. `0` if it failed: its output is dropped and a `[WARN]` line goes to stderr. |

Alert on these rather than on `up`, which stays `1` while the exporter itself answers. For example:
`metrics_exporter_plugin_success == 0 or metrics_exporter_node_exporter_up == 0`.

If the exporter itself cannot finish (it is killed, or it cannot write the response to `/tmp`), it sends nothing, so
Prometheus records a failed scrape (`up == 0`) rather than an empty one. node_exporter gets 3 seconds to answer, to stay
under the 5-second idle timeout socat uses on the s6 path.

Each plugin gets 2 seconds by default (`METRICS_EXPORTER_PLUGIN_TIMEOUT`). After that, `timeout` sends `TERM` to the
plugin's process group, then `KILL` 1 second later. This covers a `df` or `stat` that hangs on a stuck network mount. The
plugin then reports `metrics_exporter_plugin_success 0`, and a `timed out` warning goes to stderr. The two plugin
directories run one after the other, so a scrape takes at most about 3 + 2 × (timeout + 1) seconds: 9 s with the
defaults, under Prometheus' default 10 s scrape timeout. To change it under systemd, run
`systemctl edit metrics-exporter@.service` and add `Environment=METRICS_EXPORTER_PLUGIN_TIMEOUT=5` under `[Service]`.

## Tests

```bash
./test.sh
```

`tests/test_node_exporter_plugins.sh` checks each bundled plugin against a captured node_exporter fixture.
`tests/test_metrics_exporter.sh` checks the HTTP response of `metrics-exporter.sh` itself: a full scrape, a failing
plugin, a plugin that hangs past its timeout, an unreachable node_exporter, and the bundled plugins with a `grep` that
has no `-P` (as busybox on Alpine). It points the script at fake plugin directories through the
`METRICS_EXPORTER_NODE_EXPORTER_URL`, `METRICS_EXPORTER_NODE_EXPORTER_PLUGINS_DIR`, `METRICS_EXPORTER_PLUGINS_DIR` and
`METRICS_EXPORTER_PLUGIN_TIMEOUT` environment variables, which default to the installed locations.
