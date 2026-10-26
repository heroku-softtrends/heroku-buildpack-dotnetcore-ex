#!/usr/bin/env bats
# Integration-style tests for bin/compile, run with every external dependency
# (dotnet, apt-get, dpkg, curl, the real dotnet-install.sh, /etc/os-release)
# stubbed out, so the test exercises only this buildpack's own control flow:
# OS/package selection, SDK-version resolution precedence, and the
# Procfile/.profile.d output it produces.

load test_helper.bash

setup() {
	make_tmp_dirs
	STUB_BIN="$(mktemp -d)"
	STUB_LOG="$(mktemp)"
	# bin/compile symlinks $BUILD_DIR/.dotnet into $HOME; give it a throwaway
	# $HOME so the test never touches the real one.
	FAKE_HOME="$(mktemp -d)"
	export STUB_BIN STUB_LOG FAKE_HOME

	# --- stub `dotnet` ---------------------------------------------------
	cat > "$STUB_BIN/dotnet" <<'EOF'
#!/usr/bin/env bash
echo "dotnet $*" >> "$STUB_LOG"
case "$1" in
	publish)
		# Emulate `dotnet publish -p:PublishDir=<dir> ...` by creating the
		# release dir and a fake assembly inside it.
		for arg in "$@"; do
			if [[ "$arg" == -p:PublishDir=* ]]; then
				publish_dir="${arg#-p:PublishDir=}"
				mkdir -p "$publish_dir"
				touch "$publish_dir/App.dll"
			fi
		done
		;;
	--list-runtimes) ;;
	nuget) ;;
esac
exit 0
EOF
	chmod +x "$STUB_BIN/dotnet"

	# --- stub the vendored dotnet-install.sh (bypassed entirely: bin/compile
	#     calls "$BP_DIR/bin/util/dotnet-install.sh" by its full path, not via
	#     PATH, so we overlay a stub copy for the duration of the test) -----
	ORIG_DOTNET_INSTALL="$BP_DIR/bin/util/dotnet-install.sh"
	BACKUP_DOTNET_INSTALL="$(mktemp)"
	cp "$ORIG_DOTNET_INSTALL" "$BACKUP_DOTNET_INSTALL"
	cat > "$ORIG_DOTNET_INSTALL" <<'EOF'
#!/usr/bin/env bash
echo "dotnet-install.sh $*" >> "$STUB_LOG"
# Create just enough of a .dotnet install for the rest of bin/compile to proceed.
install_dir=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
	if [[ "${args[$i]}" == "--install-dir" ]]; then
		install_dir="${args[$((i+1))]}"
	fi
done
mkdir -p "${install_dir:-.}"
exit 0
EOF
	chmod +x "$ORIG_DOTNET_INSTALL"

	# --- stub apt-get / dpkg / curl (no real package installs in tests) --
	for cmd in apt-get dpkg curl; do
		cat > "$STUB_BIN/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$STUB_LOG"
exit 0
EOF
		chmod +x "$STUB_BIN/$cmd"
	done

	# --- pin get_linux_platform_version to a fixed, overridable version for
	#     the test, so assertions don't depend on the OS this test suite
	#     happens to run on. bin/compile sources common.sh by path, so we
	#     temporarily patch the real file and restore it in teardown, same
	#     as dotnet-install.sh above. Defaults to "24.04"; individual tests
	#     can override by exporting FAKE_OS_VERSION before run_compile.
	ORIG_COMMON_SH="$BP_DIR/bin/util/common.sh"
	BACKUP_COMMON_SH="$(mktemp)"
	cp "$ORIG_COMMON_SH" "$BACKUP_COMMON_SH"
	cat >> "$ORIG_COMMON_SH" <<'EOF'

# --- test override, restored by tests/compile.bats's teardown ---
get_linux_platform_version() { echo "${FAKE_OS_VERSION:-24.04}"; }
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

# Runs bin/compile with stubs on PATH ahead of the real tools, an isolated
# $HOME so it doesn't touch the real one, and STACK set (Heroku always sets
# this; bin/compile reads it under `set -o nounset`). Export FAKE_OS_VERSION
# before calling this to exercise a different Ubuntu version.
run_compile() {
	PATH="$STUB_BIN:$PATH" \
	HOME="$FAKE_HOME" \
	STACK="heroku-24" \
	FAKE_OS_VERSION="${FAKE_OS_VERSION:-}" \
	run "$BP_DIR/bin/compile" "$BUILD_DIR" "$CACHE_DIR" "$ENV_DIR"
}

@test "compile resolves the SDK version from global.json when present" {
	copy_fixture_into_build_dir simple_app_global_json
	run_compile
	[ "$status" -eq 0 ]
	grep -q -- "--jsonfile .*global.json" "$STUB_LOG"
	! grep -q -- "--version" "$STUB_LOG"
}

@test "compile falls back to productVersion.txt when there is no global.json" {
	copy_fixture_into_build_dir simple_app_product_version
	run_compile
	[ "$status" -eq 0 ]
	grep -q -- "--version 8.0.100-rc.1.23463.5" "$STUB_LOG"
	! grep -q -- "--jsonfile" "$STUB_LOG"
}

@test "compile falls back to 'Latest' when neither global.json nor productVersion.txt are set" {
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -eq 0 ]
	grep -q -- "--version Latest" "$STUB_LOG"
}

@test "compile does NOT treat <RuntimeFrameworkVersion> as an SDK version" {
	# RuntimeFrameworkVersion specifies the .NET *runtime* version, not an
	# SDK version, and dotnet-install.sh installs the SDK here (no
	# --runtime flag is passed). Passing "6.0.25" as --version would ask it
	# to install a nonexistent SDK build, so this must still resolve to
	# "Latest" rather than picking up RuntimeFrameworkVersion's value.
	copy_fixture_into_build_dir runtime_version_app
	run_compile
	[ "$status" -eq 0 ]
	grep -q -- "--version Latest" "$STUB_LOG"
	! grep -q -- "--version 6.0.25" "$STUB_LOG"
}

@test "compile never creates a .dotnet symlink at all" {
	# NuGet opens its own mutex/migration files with O_NOFOLLOW and refuses
	# to traverse a symlink there at all — not just a broken or
	# self-referential one — failing with an ENOTDIR-style error ("cannot
	# open the device or file specified: 'NuGet-Migrations'"). So
	# bin/compile must reference $BUILD_DIR/.dotnet directly for
	# compile-time PATH, never symlink $HOME/.dotnet to it, regardless of
	# whether $HOME equals $BUILD_DIR (some Heroku build-phase environments
	# set HOME=BUILD_DIR) or is a distinct directory.
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -eq 0 ]
	[ ! -L "$BUILD_DIR/.dotnet" ]
	[ -d "$BUILD_DIR/.dotnet" ]
	[ ! -e "$FAKE_HOME/.dotnet" ]
}

@test "compile succeeds and installs a real (non-symlinked) .dotnet when HOME equals BUILD_DIR" {
	copy_fixture_into_build_dir simple_app
	PATH="$STUB_BIN:$PATH" \
	HOME="$BUILD_DIR" \
	STACK="heroku-24" \
	run "$BP_DIR/bin/compile" "$BUILD_DIR" "$CACHE_DIR" "$ENV_DIR"
	[ "$status" -eq 0 ]
	[ ! -L "$BUILD_DIR/.dotnet" ]
	[ -d "$BUILD_DIR/.dotnet" ]
}

@test "compile publishes a file-based app (.cs with no project) directly" {
	copy_fixture_into_build_dir file_based_app
	run_compile
	[ "$status" -eq 0 ]
	grep -q -- "dotnet publish .*app.cs" "$STUB_LOG"
	[ -f "$BUILD_DIR/Procfile" ]
	grep -q 'dotnet "./app.dll"' "$BUILD_DIR/Procfile"
	# No <TargetFramework> to read, so no --channel is passed; the SDK
	# install falls back to dotnet-install.sh's own default channel.
	! grep -q -- "--channel" "$STUB_LOG"
}

@test "compile resolves an .fsproj/.vbproj app the same way as a .csproj app" {
	copy_fixture_into_build_dir fsharp_app
	run_compile
	[ "$status" -eq 0 ]
	grep -q -- "--channel 8.0" "$STUB_LOG"
	grep -q -- "dotnet publish .*FSharpApp.fsproj" "$STUB_LOG"
}

@test "compile writes a Procfile with the resolved assembly name" {
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -eq 0 ]
	[ -f "$BUILD_DIR/Procfile" ]
	grep -q 'dotnet "./SimpleApp.dll"' "$BUILD_DIR/Procfile"
}

@test "compile writes .profile.d/dotnetcore.sh with APP_ASSEMBLY and RELEASE_DIR exports" {
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -eq 0 ]
	[ -f "$BUILD_DIR/.profile.d/dotnetcore.sh" ]
	grep -q 'export APP_ASSEMBLY="SimpleApp"' "$BUILD_DIR/.profile.d/dotnetcore.sh"
	grep -q 'export RELEASE_DIR="SimpleApp_Release"' "$BUILD_DIR/.profile.d/dotnetcore.sh"
}

@test "compile writes a single correct PATH export, not a dropped/overwritten one" {
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -eq 0 ]
	profile="$BUILD_DIR/.profile.d/dotnetcore.sh"
	[ "$(grep -c '^export PATH=' "$profile")" -eq 1 ]
	grep -q 'export PATH="\$PATH:\$DOTNET_ROOT:\$DOTNET_ROOT/tools:\$HOME/.apt/usr/bin"' "$profile"
}

@test "compile does not export compile-time-only variables into the runtime profile" {
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -eq 0 ]
	profile="$BUILD_DIR/.profile.d/dotnetcore.sh"
	! grep -q 'LIBRARY_PATH' "$profile"
	! grep -q 'CPATH' "$profile"
	! grep -q 'CPPPATH' "$profile"
	! grep -q 'INCLUDE_PATH' "$profile"
}

@test "compile resolves the startup project and solution name for a solution-based app" {
	copy_fixture_into_build_dir sln_app
	run_compile
	[ "$status" -eq 0 ]
	grep -q 'export APP_ASSEMBLY="WebApp"' "$BUILD_DIR/.profile.d/dotnetcore.sh"
	grep -q 'export RELEASE_DIR="MySolution_Release"' "$BUILD_DIR/.profile.d/dotnetcore.sh"
}

# --- fail-fast validation -----------------------------------------------------

@test "compile fails fast with no .csproj in the build directory" {
	copy_fixture_into_build_dir non_aspnet_app
	run_compile
	[ "$status" -ne 0 ]
	[[ "$output" == *"No .NET solution, project (.csproj, .fsproj, .vbproj) or file-based"* ]]
	# Must fail before ever reaching dotnet-install.sh (OS package install
	# happens earlier and unconditionally, so it's expected to have run).
	! grep -q -- "^dotnet-install.sh" "$STUB_LOG"
}

@test "compile fails fast for a solution with no usable startup project" {
	copy_fixture_into_build_dir sln_no_project
	run_compile
	[ "$status" -ne 0 ]
	[[ "$output" == *"No .NET solution, project (.csproj, .fsproj, .vbproj) or file-based"* ]]
}

@test "compile fails fast when the target framework cannot be determined" {
	copy_fixture_into_build_dir missing_framework_app
	run_compile
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unable to determine the target framework"* ]]
}

@test "compile removes source files after publishing (not a test build)" {
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -eq 0 ]
	[ ! -f "$BUILD_DIR/SimpleApp.csproj" ]
	[ ! -f "$BUILD_DIR/Program.cs" ]
}

@test "compile fails fast on an unsupported Ubuntu version" {
	FAKE_OS_VERSION="14.04"
	copy_fixture_into_build_dir simple_app
	run_compile
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unsupported Ubuntu version: 14.04"* ]]
	# Must fail before any package installs are attempted.
	! grep -q -- "^apt-get" "$STUB_LOG"
}
