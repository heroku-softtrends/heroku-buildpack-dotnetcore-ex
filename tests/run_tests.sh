#!/usr/bin/env bash
# Runs the full bats test suite for this buildpack.
#
# Usage: tests/run_tests.sh
#
# Requires bats-core (https://github.com/bats-core/bats-core):
#   Ubuntu/Debian: sudo apt-get install -y bats
#   macOS:         brew install bats-core
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
	echo "error: bats is not installed. See the comment at the top of this script." >&2
	exit 1
fi

exec bats "$SCRIPT_DIR"/*.bats
