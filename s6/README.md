# Running in S6

We can use metric-exporter alongside existing codebases or Docker images.

## Installing

1. Ensure you have `s6` setup in your Docker image. See their [Quickstart](https://github.com/just-containers/s6-overlay?tab=readme-ov-file#quickstart)
1. Install `bash`, `curl` and `socat` from your package manager if not already installed:
    1. Debian/Ubuntu: `apt-get update && apt-get install -y curl socat && apt-get clean`
    1. RHEL/CentOS: `dnf install -y curl socat && dnf clean all`
    1. Alpine: `apk add --no-cache bash curl socat`
1. Copy this repo into your Docker image and run [./install.sh](./install.sh)
    1. This will also install `node_exporter` (amd64, arm64 or armv7; set `NODE_EXPORTER_VERSION` to choose a release),
       listening on `127.0.0.1:9101` only. Its textfile collector reads `/tmp/node_exporter_collector/*.prom`.
