# Node Exporter Plugins Tests

This directory contains tests for the node_exporter plugins.

## Structure

```
tests/
├── fixtures/
│   └── node_exporter.example.txt    # Sample node_exporter metrics data
└── test_node_exporter_plugins.sh    # Test runner
```

## Running Tests

Execute the test suite:

```bash
./test_node_exporter_plugins.sh
```

## What Gets Tested

For each plugin in `node_exporter-plugins.d/`, the test suite verifies:

1. **Executable**: Plugin file has execute permissions
2. **Runs without error**: Plugin executes successfully with fixture data
3. **Valid Prometheus format**: Output contains proper `# HELP` and `# TYPE` comments and metric lines
4. **Contains expected metrics**: Plugin outputs the expected metric names

### Plugins Tested

- **cpu.sh**: CPU usage metrics aggregated across all cores
  - `node_cpu_seconds_total` with modes (user, system, idle, iowait, etc.)
  - `node_cpu_count`

- **memory.sh**: Memory usage statistics
  - `node_memory_MemTotal_bytes`
  - `node_memory_MemFree_bytes`
  - `node_memory_MemAvailable_bytes`
  - `node_memory_MemUsed_bytes`

- **disk_usage.sh**: Filesystem usage for monitored partitions
  - `node_filesystem_size_bytes`
  - `node_filesystem_avail_bytes`
  - `node_filesystem_usage_percent`

- **load_average.sh**: System load averages
  - `node_load1`, `node_load5`, `node_load15`
  - `node_load_normalized_1`, `node_load_normalized_5`, `node_load_normalized_15`

- **network.sh**: Network interface statistics
  - `node_network_receive_bytes_total`
  - `node_network_transmit_bytes_total`
  - `node_network_receive_errs_total`
  - `node_network_transmit_errs_total`

## Test Fixture

The test fixture (`fixtures/node_exporter.example.txt`) contains real node_exporter metrics output captured from a running system. This ensures plugins are tested with realistic data.

To update the fixture with current metrics:

```bash
curl -s http://localhost:9101/metrics > fixtures/node_exporter.example.txt
```

## Exit Codes

- **0**: All tests passed
- **1**: One or more tests failed

## Adding New Tests

To add tests for a new plugin:

1. Add the plugin to `../node_exporter-plugins.d/`
2. Create a test function in `test_node_exporter_plugins.sh`:
   ```bash
   test_<plugin_name>() {
       local plugin="$PLUGINS_DIR/<plugin>.sh"
       local test_name="<plugin>.sh"

       # Test executable
       if [ ! -x "$plugin" ]; then
           print_result "$test_name - executable" "FAIL" "Plugin is not executable"
           return
       fi
       print_result "$test_name - executable" "PASS"

       # Run plugin and check output
       local output
       if ! output=$(run_plugin "$plugin"); then
           print_result "$test_name - runs without error" "FAIL" "Plugin exited with non-zero status"
           return
       fi
       print_result "$test_name - runs without error" "PASS"

       # Add more specific tests...
   }
   ```
3. Call the test function from `main()`
4. Update this README with the new plugin's tested metrics
