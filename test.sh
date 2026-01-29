#!/bin/bash
set -xeuo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
for test_file in "$DIR/tests"/test_*.sh; do
	"$test_file"
done
