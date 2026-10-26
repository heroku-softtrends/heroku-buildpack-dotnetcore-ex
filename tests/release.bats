#!/usr/bin/env bats
# Tests for bin/release's validation and output.

load test_helper.bash

setup() {
	make_tmp_dirs
}

teardown() {
	remove_tmp_dirs
}

@test "release fails with no build-dir argument" {
	run "$BP_DIR/bin/release"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Usage: bin/release"* ]]
}

@test "release fails when the build directory does not exist" {
	run "$BP_DIR/bin/release" "$BUILD_DIR/does-not-exist"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Build directory not found"* ]]
}

@test "release fails when .profile.d/dotnetcore.sh is missing" {
	run "$BP_DIR/bin/release" "$BUILD_DIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Runtime profile not found"* ]]
}

@test "release emits default_process_types from a compile-produced profile" {
	mkdir -p "$BUILD_DIR/.profile.d"
	cat > "$BUILD_DIR/.profile.d/dotnetcore.sh" <<'EOF'
export DOTNET_ROOT=$HOME/.dotnet
export APP_ASSEMBLY="SimpleApp"
export RELEASE_DIR="SimpleApp_Release"
EOF
	run "$BP_DIR/bin/release" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" == *"default_process_types:"* ]]
	[[ "$output" == *'web: cd $HOME/SimpleApp_Release && dotnet "./SimpleApp.dll" --urls http://+:$PORT'* ]]
}

@test "release omits default_process_types when a Procfile already exists" {
	mkdir -p "$BUILD_DIR/.profile.d"
	cat > "$BUILD_DIR/.profile.d/dotnetcore.sh" <<'EOF'
export APP_ASSEMBLY="SimpleApp"
export RELEASE_DIR="SimpleApp_Release"
EOF
	touch "$BUILD_DIR/Procfile"
	run "$BP_DIR/bin/release" "$BUILD_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" != *"default_process_types:"* ]]
}
