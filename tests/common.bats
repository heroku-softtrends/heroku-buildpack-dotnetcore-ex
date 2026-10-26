#!/usr/bin/env bats
# Unit tests for bin/util/common.sh helper functions.

load test_helper.bash

setup() {
	# shellcheck source=../bin/util/common.sh
	source "$BP_DIR/bin/util/common.sh"
	make_tmp_dirs
}

teardown() {
	remove_tmp_dirs
}

# --- get_project_name / get_project_file -----------------------------------

@test "get_project_name finds the .csproj at the build dir root" {
	copy_fixture_into_build_dir simple_app
	run get_project_name "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "SimpleApp" ]
}

@test "get_project_name returns empty when no .csproj exists" {
	copy_fixture_into_build_dir non_aspnet_app
	run get_project_name "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

# --- get_framework_version ---------------------------------------------------

@test "get_framework_version reads a single <TargetFramework> and strips the 'net' prefix" {
	# get_framework_version feeds dotnet-install.sh's --channel flag, which
	# expects a bare "8.0" rather than the TFM's "net8.0".
	copy_fixture_into_build_dir simple_app
	run get_framework_version "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "8.0" ]
}

@test "get_framework_version reads an .fsproj's <TargetFramework>" {
	copy_fixture_into_build_dir fsharp_app
	run get_framework_version "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "8.0" ]
}

@test "get_framework_version reads a .vbproj's <TargetFramework>" {
	copy_fixture_into_build_dir vb_app
	run get_framework_version "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "8.0" ]
}

# --- get_first_csproj_dir ----------------------------------------------------
# Note: there is deliberately no get_runtime_framework_version() to test. A
# .csproj's <RuntimeFrameworkVersion> specifies the .NET *runtime* version,
# not an SDK version, and is not a valid value for dotnet-install.sh's
# --version when installing the SDK (the default, used throughout
# bin/compile). See tests/compile.bats for coverage of that distinction.

@test "get_first_csproj_dir finds the .csproj at the build dir root" {
	copy_fixture_into_build_dir simple_app
	run get_first_csproj_dir "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR" ]
}

@test "get_first_csproj_dir finds a nested project's directory for a solution-based app" {
	copy_fixture_into_build_dir sln_app
	run get_first_csproj_dir "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR/WebApp" ]
}

@test "get_first_csproj_dir is empty when no .csproj exists" {
	copy_fixture_into_build_dir non_aspnet_app
	run get_first_csproj_dir "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "get_first_csproj_dir is empty for a solution with no usable project" {
	copy_fixture_into_build_dir sln_no_project
	run get_first_csproj_dir "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "get_first_csproj_dir finds an .fsproj at the build dir root" {
	copy_fixture_into_build_dir fsharp_app
	run get_first_csproj_dir "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR" ]
}

@test "get_first_csproj_dir finds a .vbproj at the build dir root" {
	copy_fixture_into_build_dir vb_app
	run get_first_csproj_dir "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR" ]
}

@test "get_first_csproj_dir finds a nested project's directory for a .slnx-based app" {
	copy_fixture_into_build_dir slnx_app
	run get_first_csproj_dir "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR/WebApp" ]
}

# --- get_file_based_app_file -------------------------------------------------

@test "get_file_based_app_file finds a root-level .cs file" {
	copy_fixture_into_build_dir file_based_app
	run get_file_based_app_file "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR/app.cs" ]
}

@test "get_file_based_app_file is empty when no .cs file exists" {
	copy_fixture_into_build_dir non_aspnet_app
	run get_file_based_app_file "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

# --- get_specific_version (productVersion.txt override) ---------------------

@test "get_specific_version is empty when no productVersion.txt is present" {
	copy_fixture_into_build_dir simple_app
	run get_specific_version "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "get_specific_version reads productVersion.txt when present" {
	copy_fixture_into_build_dir simple_app_product_version
	run get_specific_version "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "8.0.100-rc.1.23463.5" ]
}

# --- get_global_json_file ----------------------------------------------------

@test "get_global_json_file is empty when no global.json is present" {
	copy_fixture_into_build_dir simple_app
	run get_global_json_file "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "get_global_json_file finds global.json at the build dir root" {
	copy_fixture_into_build_dir simple_app_global_json
	run get_global_json_file "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR/global.json" ]
}

@test "get_global_json_file finds global.json alongside a solution with a nested project" {
	copy_fixture_into_build_dir sln_app_global_json
	run get_global_json_file "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BUILD_DIR/global.json" ]
}

# --- solution-based helpers ---------------------------------------------------

@test "get_project_sln_name finds the .sln name at the build dir root" {
	copy_fixture_into_build_dir sln_app
	run get_project_sln_name "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "MySolution" ]
}

@test "get_project_sln_name is empty for a single-project (non-solution) app" {
	copy_fixture_into_build_dir simple_app
	run get_project_sln_name "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "get_project_sln_name finds the .slnx name at the build dir root" {
	copy_fixture_into_build_dir slnx_app
	run get_project_sln_name "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "MySolution" ]
}

@test "get_start_project_name resolves the startup project from launchSettings.json" {
	copy_fixture_into_build_dir sln_app
	run get_start_project_name "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "WebApp" ]
}

# --- is_postgres_used --------------------------------------------------------

@test "is_postgres_used is 'no' when Npgsql isn't referenced" {
	copy_fixture_into_build_dir simple_app
	run is_postgres_used "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "no" ]
}

@test "is_postgres_used is 'yes' when Npgsql is referenced" {
	copy_fixture_into_build_dir npgsql_app
	run is_postgres_used "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "yes" ]
}

# --- resolve_test_command ----------------------------------------------------

@test "resolve_test_command picks the solution when one exists" {
	copy_fixture_into_build_dir sln_app_with_tests
	run resolve_test_command "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "dotnet test \"$BUILD_DIR/MySolution.sln\" --configuration Release" ]
}

@test "resolve_test_command falls back to a standalone test project when there is no solution" {
	copy_fixture_into_build_dir standalone_tests_app
	run resolve_test_command "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "dotnet test \"$BUILD_DIR/MyApp.Tests.csproj\" --configuration Release" ]
}

@test "resolve_test_command is empty when no test project exists" {
	copy_fixture_into_build_dir simple_app
	run resolve_test_command "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

# --- is_supported_heroku_os_version -----------------------------------------

@test "is_supported_heroku_os_version accepts every allow-listed stack" {
	for v in 16.04 18.04 20.04 22.04 24.04 26.04; do
		run is_supported_heroku_os_version "$v"
		[ "$status" -eq 0 ]
	done
}

@test "is_supported_heroku_os_version rejects a non-allow-listed version even if numerically in range" {
	run is_supported_heroku_os_version "17.04"
	[ "$status" -ne 0 ]
}

@test "is_supported_heroku_os_version rejects a pre-16.04 version" {
	run is_supported_heroku_os_version "14.04"
	[ "$status" -ne 0 ]
}

# --- is_version_gte -----------------------------------------------------------
# Regression coverage: `[[ "10.0" >= "2.1" ]]` and
# `awk 'BEGIN{print("10.0">="2.1")}'` both do a *string* comparison on
# quoted literals ("1" < "2" lexicographically), wrongly judging "10.0"
# less than "2.1". is_version_gte must compare numerically instead.

@test "is_version_gte compares net10.0+ versions numerically, not lexicographically" {
	run is_version_gte "10.0" "2.1"
	[ "$output" = "1" ]
}

@test "is_version_gte correctly rejects a version below the floor" {
	run is_version_gte "2.0" "2.1"
	[ "$output" = "0" ]
}

@test "is_version_gte treats an exact match as >=" {
	run is_version_gte "2.1" "2.1"
	[ "$output" = "1" ]
}

# --- misc string helpers -----------------------------------------------------

@test "remove_trailing_slash strips exactly one trailing slash" {
	run remove_trailing_slash "/app/release/"
	[ "$status" -eq 0 ]
	[ "$output" = "/app/release" ]
}

@test "remove_beginning_slash strips exactly one leading slash" {
	run remove_beginning_slash "/app/release"
	[ "$status" -eq 0 ]
	[ "$output" = "app/release" ]
}

@test "string_replace substitutes the first match" {
	run string_replace "hello-world" "world" "there"
	[ "$status" -eq 0 ]
	[ "$output" = "hello-there" ]
}
