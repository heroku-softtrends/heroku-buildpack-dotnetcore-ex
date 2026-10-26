#!/usr/bin/env bats
# Tests for bin/test: runs the test command bin/compile already recorded in
# $BUILD_DIR/.heroku/test_command (no discovery logic in bin/test itself).

load test_helper.bash

setup() {
	make_tmp_dirs
	STUB_BIN="$(mktemp -d)"
	STUB_LOG="$(mktemp)"
	export STUB_BIN STUB_LOG

	cat > "$STUB_BIN/dotnet" <<'EOF'
#!/usr/bin/env bash
echo "dotnet $*" >> "$STUB_LOG"
if [[ "$1" == "test" ]]; then
	exit "${FAKE_DOTNET_TEST_EXIT:-0}"
fi
exit 0
EOF
	chmod +x "$STUB_BIN/dotnet"
}

teardown() {
	rm -f "$STUB_LOG"
	rm -rf "$STUB_BIN"
	remove_tmp_dirs
}

write_test_command() {
	mkdir -p "$BUILD_DIR/.heroku"
	echo "$1" > "$BUILD_DIR/.heroku/test_command"
}

run_test() {
	PATH="$STUB_BIN:$PATH" \
	FAKE_DOTNET_TEST_EXIT="${FAKE_DOTNET_TEST_EXIT:-}" \
	run "$BP_DIR/bin/test" "$BUILD_DIR" "$ENV_DIR"
}

@test "test fails with no build-dir argument" {
	run "$BP_DIR/bin/test"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Usage: bin/test"* ]]
}

@test "test fails when the build directory does not exist" {
	run "$BP_DIR/bin/test" "$BUILD_DIR/does-not-exist" "$ENV_DIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Build directory not found"* ]]
}

@test "test runs the command recorded in .heroku/test_command" {
	write_test_command "dotnet test \"$BUILD_DIR/MySolution.sln\" --configuration Release"
	run_test
	[ "$status" -eq 0 ]
	grep -q -- "dotnet test $BUILD_DIR/MySolution.sln --configuration Release" "$STUB_LOG"
}

@test "test does not re-discover test projects itself" {
	# Even with a fixture full of test projects on disk, bin/test must only
	# ever run what .heroku/test_command says — never its own discovery.
	copy_fixture_into_build_dir sln_app_with_tests
	write_test_command "dotnet test \"$BUILD_DIR/WebApp.Tests/WebApp.Tests.csproj\" --configuration Release"
	run_test
	[ "$status" -eq 0 ]
	grep -q -- "dotnet test $BUILD_DIR/WebApp.Tests/WebApp.Tests.csproj --configuration Release" "$STUB_LOG"
	! grep -q -- "MySolution.sln" "$STUB_LOG"
}

@test "test fails with an actionable message when no test command was recorded" {
	run_test
	[ "$status" -ne 0 ]
	[[ "$output" == *"No test command found"* ]]
	[[ "$output" == *"bin/test-compile"* ]]
	[[ "$output" == *"app.json"* ]]
	[ ! -s "$STUB_LOG" ]
}

@test "test propagates a failing 'dotnet test' exit code" {
	FAKE_DOTNET_TEST_EXIT=1
	write_test_command "dotnet test \"$BUILD_DIR/MySolution.sln\" --configuration Release"
	run_test
	[ "$status" -eq 1 ]
}

@test "test sources .profile.d/dotnetcore.sh when present" {
	mkdir -p "$BUILD_DIR/.profile.d"
	# A canary env var export: if bin/test sources this, PROBE_VALUE will
	# be visible to the stubbed dotnet process below.
	echo 'export PROBE_VALUE="from-profile-d"' > "$BUILD_DIR/.profile.d/dotnetcore.sh"
	cat > "$STUB_BIN/dotnet" <<'EOF'
#!/usr/bin/env bash
echo "PROBE_VALUE=${PROBE_VALUE:-}" >> "$STUB_LOG"
exit 0
EOF
	chmod +x "$STUB_BIN/dotnet"
	write_test_command "dotnet test \"$BUILD_DIR/MySolution.sln\" --configuration Release"
	run_test
	[ "$status" -eq 0 ]
	grep -q "^PROBE_VALUE=from-profile-d$" "$STUB_LOG"
}
