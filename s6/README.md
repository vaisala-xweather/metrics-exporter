# Running in S6

We can use metric-exporter alongside existing codebases or Docker images.

## Installing

1. Ensure you have `s6` setup in your Docker image. See their [Quickstart](https://github.com/just-containers/s6-overlay?tab=readme-ov-file#quickstart)
1. Install the `socat` binary from your package manager if not already installed:
    1. Debian/Ubuntu: `apt-get update && apt-get install -y socat && apt-get clean`
    1. RHEL/CentOS: `dnf install -y socat && yum clean all`
    1. Alpine: `apk add --no-cache socat`
1. Copy this repo into your Docker image and run [./install.sh](./install.sh)
    1. This will also install `node_exporter`
