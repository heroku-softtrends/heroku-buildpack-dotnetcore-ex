#!/usr/bin/env bats
# Tests for bin/test-compile, the CI/test wrapper around bin/compile.

load test_helper.bash

setup() {
	make_tmp_dirs
	STUB_BIN="$(mktemp -d)"
	STUB_LOG="$(mktemp)"
	FAKE_HOME="$(mktemp -d)"
	export STUB_BIN STUB_LOG FAKE_HOME

	cat > "$STUB_BIN/dotnet" <<'EOF'
#!/usr/bin/env bash
echo "dotnet $*" >> "$STUB_LOG"
echo "ASPNETCORE_ENVIRONMENT=${ASPNETCORE_ENVIRONMENT:-}" >> "$STUB_LOG"
for arg in "$@"; do
	if [[ "$arg" == -p:PublishDir=* ]]; then
		pd="${arg#-p:PublishDir=}"; mkdir -p "$pd"; touch "$pd/App.dll"
	fi
done
exit 0
EOF
	chmod +x "$STUB_BIN/dotnet"

	for cmd in apt-get dpkg curl; do
		cat > "$STUB_BIN/$cmd" <<EOF
#!/usr/bin/env bash
exit 0
EOF
		chmod +x "$STUB_BIN/$cmd"
	done

	ORIG_DOTNET_INSTALL="$BP_DIR/bin/util/dotnet-install.sh"
	BACKUP_DOTNET_INSTALL="$(mktemp)"
	cp "$ORIG_DOTNET_INSTALL" "$BACKUP_DOTNET_INSTALL"
	cat > "$ORIG_DOTNET_INSTALL" <<'EOF'
#!/usr/bin/env bash
echo "dotnet-install.sh $*" >> "$STUB_LOG"
install_dir=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
	if [[ "${args[$i]}" == "--install-dir" ]]; then install_dir="${args[$((i+1))]}"; fi
done
mkdir -p "${install_dir:-.}"
exit 0
EOF
	chmod +x "$ORIG_DOTNET_INSTALL"

	ORIG_COMMON_SH="$BP_DIR/bin/util/common.sh"
	BACKUP_COMMON_SH="$(mktemp)"
	cp "$ORIG_COMMON_SH" "$BACKUP_COMMON_SH"
	cat >> "$ORIG_COMMON_SH" <<'EOF'

get_linux_platform_version() { echo "24.04"; }
EOF
}

teardown() {
	cp "$BACKUP_DOTNET_INSTALL" "$BP_DIR/bin/util/dotnet-install.sh"
	chmod +x "$BP_DIR/bin/util/dotnet-install.sh"
	cp "$BACKUP_COMMON_SH" "$BP_DIR/bin/util/common.sh"
	rm -f "$BACKUP_DOTNET_INSTALL" "$BACKUP_COMMON_SH" "$STUB_LOG"
	rm -rf "$STUB_BIN" "$FAKE_HOME"
	remove_tmp_dirs
}

run_test_compile() {
	PATH="$STUB_BIN:$PATH" \
	HOME="$FAKE_HOME" \
	STACK="heroku-24" \
	run "$BP_DIR/bin/test-compile" "$BUILD_DIR" "$CACHE_DIR" "$ENV_DIR"
}

@test "test-compile fails with no build-dir argument" {
	run "$BP_DIR/bin/test-compile"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Usage: bin/test-compile"* ]]
}

@test "test-compile exports ASPNETCORE_ENVIRONMENT=Staging before bin/compile runs" {
	copy_fixture_into_build_dir simple_app
	run_test_compile
	[ "$status" -eq 0 ]
	# The stubbed `dotnet` records the environment it was actually called
	# with, proving the export happens before (not after) bin/compile.
	grep -q "^ASPNETCORE_ENVIRONMENT=Staging$" "$STUB_LOG"
}

@test "test-compile succeeds end-to-end like bin/compile" {
	copy_fixture_into_build_dir simple_app
	run_test_compile
	[ "$status" -eq 0 ]
	[ -f "$BUILD_DIR/Procfile" ]
	grep -q 'export APP_ASSEMBLY="SimpleApp"' "$BUILD_DIR/.profile.d/dotnetcore.sh"
}

@test "test-compile preserves source files so bin/test can run afterward" {
	# bin/compile normally deletes .csproj/.sln after publish. test-compile
	# must suppress that (HEROKU_DOTNET_TEST_BUILD) so a subsequent bin/test
	# still has something to run `dotnet test` against.
	copy_fixture_into_build_dir sln_app_with_tests
	run_test_compile
	[ "$status" -eq 0 ]
	[ -f "$BUILD_DIR/MySolution.sln" ]
	[ -f "$BUILD_DIR/WebApp/WebApp.csproj" ]
	[ -f "$BUILD_DIR/WebApp.Tests/WebApp.Tests.csproj" ]
}

@test "test-compile records the test command for bin/test to run" {
	# bin/compile (invoked by test-compile) resolves the test command once,
	# while source files are still present, and writes it down — bin/test
	# just reads and runs it rather than re-discovering it itself.
	copy_fixture_into_build_dir sln_app_with_tests
	run_test_compile
	[ "$status" -eq 0 ]
	[ -f "$BUILD_DIR/.heroku/test_command" ]
	grep -q -- "dotnet test \"$BUILD_DIR/MySolution.sln\" --configuration Release" "$BUILD_DIR/.heroku/test_command"
}
