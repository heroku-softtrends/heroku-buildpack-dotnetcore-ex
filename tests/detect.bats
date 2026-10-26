#!/usr/bin/env bats
# Tests for bin/detect against fixture app directories.

load test_helper.bash

setup() {
	make_tmp_dirs

	# Pin get_linux_platform_version to a fixed, overridable version so
	# assertions don't depend on the OS this test suite happens to run on
	# (e.g. there's no /etc/os-release at all on Windows/Git Bash). bin/detect
	# sources common.sh by path, so we temporarily patch the real file and
	# restore it in teardown. Defaults to "24.04"; individual tests can
	# override by exporting FAKE_OS_VERSION before invoking bin/detect.
	ORIG_COMMON_SH="$BP_DIR/bin/util/common.sh"
	BACKUP_COMMON_SH="$(mktemp)"
	cp "$ORIG_COMMON_SH" "$BACKUP_COMMON_SH"
	cat >> "$ORIG_COMMON_SH" <<'EOF'

# --- test override, restored by tests/detect.bats's teardown ---
get_linux_platform_version() { echo "${FAKE_OS_VERSION:-24.04}"; }
EOF
}

teardown() {
	cp "$BACKUP_COMMON_SH" "$BP_DIR/bin/util/common.sh"
	rm -f "$BACKUP_COMMON_SH"
	remove_tmp_dirs
}

@test "detect succeeds for a valid single-project ASP.NET Core app" {
	copy_fixture_into_build_dir simple_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "ASP.NET Core" ]
}

@test "detect succeeds for a solution-based ASP.NET Core app" {
	copy_fixture_into_build_dir sln_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "ASP.NET Core" ]
}

@test "detect succeeds for a .slnx solution-based app" {
	copy_fixture_into_build_dir slnx_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "ASP.NET Core" ]
}

@test "detect succeeds for an F# (.fsproj) app" {
	copy_fixture_into_build_dir fsharp_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "ASP.NET Core" ]
}

@test "detect succeeds for a VB.NET (.vbproj) app" {
	copy_fixture_into_build_dir vb_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "ASP.NET Core" ]
}

@test "detect succeeds for a net10.0+ app (regression: awk string vs numeric comparison)" {
	# awk 'BEGIN{print ("10.0" >= "2.1")}' with quoted literals does a
	# *string* comparison ("1" < "2" lexicographically) and wrongly says
	# false. bin/detect must compare these as numbers, not strings, or
	# every net10.0+ app gets incorrectly rejected as an unsupported
	# framework version.
	copy_fixture_into_build_dir net10_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "ASP.NET Core" ]
}

@test "detect rejects a non-allow-listed Ubuntu version even if numerically >= 16.04" {
	# A loose "$version >= 16.04" numeric/string threshold would wrongly
	# accept a version bin/compile has no package-install branch for (e.g.
	# a hypothetical 17.04, or a future stack this buildpack hasn't been
	# updated for yet), only for bin/compile to reject it later. detect's
	# OS check must match bin/compile's exact allow-list instead.
	copy_fixture_into_build_dir simple_app
	FAKE_OS_VERSION="17.04" run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"is not supported"* ]]
}

@test "detect succeeds for a file-based app (.cs with no project)" {
	copy_fixture_into_build_dir file_based_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "ASP.NET Core" ]
}

@test "detect fails for a file-based app on an unsupported Ubuntu version" {
	copy_fixture_into_build_dir file_based_app
	FAKE_OS_VERSION="14.04" run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"is not supported"* ]]
}

@test "detect fails for a directory with no .csproj/Program.cs" {
	copy_fixture_into_build_dir non_aspnet_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Application not supported by this buildpack"* ]]
}

@test "detect fails for an empty directory" {
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 1 ]
}

@test "detect fails for a solution with no usable startup project" {
	copy_fixture_into_build_dir sln_no_project
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"does not reference a usable project"* ]]
}

@test "detect fails when the project has no detectable target framework" {
	copy_fixture_into_build_dir missing_framework_app
	run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Unable to determine the target framework"* ]]
}

@test "detect fails on an unsupported (pre-16.04) Ubuntu version" {
	copy_fixture_into_build_dir simple_app
	FAKE_OS_VERSION="14.04" run "$BP_DIR/bin/detect" "$BUILD_DIR"
	[ "$status" -eq 1 ]
	[[ "$output" == *"is not supported"* ]]
}
