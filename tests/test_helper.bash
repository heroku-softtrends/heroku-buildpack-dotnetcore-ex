#!/usr/bin/env bash
# Shared setup for all bats test files in this directory.

# Absolute path to the repo root (one level up from tests/).
BP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$BP_DIR/tests/fixtures"

# Fresh, isolated BUILD_DIR/CACHE_DIR/ENV_DIR for a test. Call in `setup()`.
make_tmp_dirs() {
	BUILD_DIR="$(mktemp -d)"
	CACHE_DIR="$(mktemp -d)"
	ENV_DIR="$(mktemp -d)"
	export BUILD_DIR CACHE_DIR ENV_DIR
}

# Remove the dirs created by make_tmp_dirs. Call in `teardown()`.
remove_tmp_dirs() {
	[[ -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" ]] && rm -rf "$BUILD_DIR"
	[[ -n "${CACHE_DIR:-}" && -d "$CACHE_DIR" ]] && rm -rf "$CACHE_DIR"
	[[ -n "${ENV_DIR:-}" && -d "$ENV_DIR" ]] && rm -rf "$ENV_DIR"
}

# Copy a named fixture (tests/fixtures/<name>) into $BUILD_DIR so tests can
# exercise functions against a throwaway copy rather than the fixture itself.
copy_fixture_into_build_dir() {
	local fixture_name="$1"
	cp -r "$FIXTURES_DIR/$fixture_name/." "$BUILD_DIR/"
}
