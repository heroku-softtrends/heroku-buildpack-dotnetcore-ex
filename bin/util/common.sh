# shellcheck shell=bash
# This file is sourced by bin/compile, bin/detect, bin/release and bin/test-compile.

print() {
	echo "-----> $*"
}

indent() {
	c='s/^/       /'
	case $(uname) in
	Darwin) sed -l "$c";;
	*)      sed -u "$c";;
	esac
}

get_os() {
	uname | tr '[:upper:]' '[:lower:]'
}

get_cpu() {
	if [[ "$(uname -p)" = "i686" ]]; then
	echo "x86"
	else
	echo "x64"
	fi
}

get_platform() {
	os=$(get_os)
	cpu=$(get_cpu)
	echo "$os-$cpu"
}

get_linux_platform_version() {
	if [ -e /etc/os-release ]; then
	    . /etc/os-release
	    echo "${VERSION_ID//[a-z]/}"
	    return 0
	fi

	print "Linux specific platform version could not be detected: UName = $(uname)"
	return 1
}

# Returns 0 (true) if $1 is one of the Ubuntu versions this buildpack
# actually has package-install branches for in bin/compile, 1 otherwise.
# This is an exact allow-list match, not a numeric threshold: a loose
# "$version >= 16.04" check would accept a version bin/compile doesn't
# know how to install prerequisites for (e.g. a hypothetical 17.04, or a
# future stack newer than this buildpack has been updated for), only to
# have bin/compile reject it later with a less helpful, later-stage
# failure. Keep this list in sync with the branches in bin/compile.
# args:
# input - $1
is_supported_heroku_os_version() {
	case "$1" in
		16.04 | 18.04 | 20.04 | 22.04 | 24.04 | 26.04) return 0 ;;
		*) return 1 ;;
	esac
}

# Numeric "is $1 >= $2" for dotted version strings (e.g. "10.0" >= "2.1").
# Not for bash: `[[ "10.0" >= "2.1" ]]` and `awk 'BEGIN{print ("10.0">="2.1")}'`
# both do a *string* comparison when the operands are literal/quoted
# constants ("1" < "2" lexicographically, so "10.0" is wrongly judged less
# than "2.1"). Passing the values in via awk -v instead makes awk treat
# them as numeric strings, which compares them as numbers. Echoes "1" or
# "0" (not shell exit status), to match how callers already consume the
# awk-based checks this replaces.
# args:
# input - $1, $2
is_version_gte() {
	awk -v a="$1" -v b="$2" 'BEGIN { print (a >= b) ? 1 : 0 }'
}

error() {
	local c="2,999 s/^/ !     /"
	# send all of our output to stderr
	exec 1>&2

	echo -e "\033[1;31m" # bold; red
	echo -n " !     ERROR: "
	# this will be fed from stdin
	case $(uname) in
		Darwin) sed -l "$c";; # mac/bsd sed: -l buffers on line boundaries
		*)      sed -u "$c";; # unix/gnu sed: -u unbuffered (arbitrary) chunks of data
	esac
	echo -e "\033[0m" # reset style
	exit 1
}

export_env_dir() {
	local env_dir=$1
	if [ -d "$env_dir" ]; then
		local whitelist_regex=${2:-''}
		local blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH|LANG|BUILD_DIR)$'}
		# shellcheck disable=SC2164
		pushd "$env_dir" >/dev/null
		for e in *; do
			[ -e "$e" ] || continue
			echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
			export "$e=$(cat "$e")"
			:
		done
		# shellcheck disable=SC2164
		popd >/dev/null
	fi
}

# args:
# input - $1,$2
string_replace() {
    #DOC: "${string/match/replace}"
    string=$1
    echo "${string/$2/$3}"
}

# args:
# input - $1
remove_trailing_slash() {
    local input="${1:-}"
    echo "${input%/}"
    return 0
}

# args:
# input - $1
remove_beginning_slash() {
    local input="${1:-}"
    echo "${input#/}"
    return 0
}

# Matches both the classic .sln format and the newer .slnx (XML) format.
# args:
# input - $1
get_project_sln_file() {
	local search_dir="$1"
	local solutionfile
	solutionfile=$(
		local x
		x="$(dirname "$(find "$search_dir" -maxdepth 1 -type f | head -1)")"
		while [[ "$x" =~ $search_dir ]]; do
			find "$x" -maxdepth 1 \( -name "*.sln" -o -name "*.slnx" \)
			x="$(dirname "$x")"
		done
	)
	echo "$solutionfile"
}

# args:
# input - $1
get_project_sln_name() {
	local solution_name=""
	local solutionfile
	solutionfile="$(get_project_sln_file "$1")"
	if [[ $solutionfile ]]; then
		solution_name=$(basename "${solutionfile%.*}")
	fi
	echo "$solution_name"
}

# Matches C# (.csproj), F# (.fsproj) and VB.NET (.vbproj) project files alike.
# args:
# input - $1
get_project_file() {
	local search_dir="$1"
	local projectfile
	projectfile=$(
		local x
		x="$(dirname "$(find "$search_dir" -maxdepth 2 -type f | head -1)")"
		while [[ "$x" =~ $search_dir ]]; do
			find "$x" -maxdepth 1 \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" \)
			x="$(dirname "$x")"
		done
	)
	echo "$projectfile"
}

# args:
# input - $1
get_project_name() {
	local project_name=""
	local project_file
	project_file="$(get_project_file "$1")"
	if [[ $project_file ]]; then
		project_name=$(basename "${project_file%.*}")
	fi
	echo "$project_name"
}

# args:
# input - $1
get_start_project_name() {
	local search_dir="$1"
	local project_name=""
	local launchSettingsFile
	launchSettingsFile=$(
		local x
		x="$(dirname "$(find "$search_dir" -maxdepth 1 -type f | head -1)")"
		while [[ "$x" =~ $search_dir ]]; do
			find "$x" -maxdepth 3 -name "launchSettings.json"
			x="$(dirname "$x")"
		done
	)
	if [[ $launchSettingsFile ]]; then
		project_name=$(basename "$(dirname "$(dirname "${launchSettingsFile%.*}")")")
	fi
 	if [[ "$project_name" == build_* ]]; then
  		project_name="$(get_project_name "$search_dir")"
  	fi
	echo "$project_name"
}

# Looks for a 'global.json' file (the standard .NET SDK-version pinning file,
# e.g. { "sdk": { "version": "8.0.100" } }) from the build directory down
# through its project subdirectories. Returns the path to the first one found,
# or an empty string if none exists.
# args:
# input - $1
get_global_json_file() {
	local search_dir="$1"
	local globaljsonfile
	globaljsonfile=$(
		local x
		x="$(dirname "$(find "$search_dir" -maxdepth 1 -type f | head -1)")"
		while [[ "$x" =~ $search_dir ]]; do
			find "$x" -maxdepth 1 -name "global.json"
			x="$(dirname "$x")"
		done
	)
	echo "$globaljsonfile"
}

# args:
# input - $1
get_specific_version() {
	local search_dir="$1"
	local sVersion=""
	local productVersion
	productVersion=$(
		local x
		x="$(dirname "$(find "$search_dir" -maxdepth 1 -type f | head -1)")"
		while [[ "$x" =~ $search_dir ]]; do
			find "$x" -maxdepth 3 -name "productVersion.txt"
			x="$(dirname "$x")"
		done
	)
	if [[ $productVersion ]]; then
		sVersion=$(cat "$productVersion")
	fi
	echo "$sVersion"
}

# Reads <TargetFramework> from whichever project file (.csproj, .fsproj or
# .vbproj) exists at $1. Echoes nothing if no project file is found there.
# args:
# input - $1
get_framework_version() {
	local project_file target_framework
	project_file="$(find "$1" -maxdepth 1 \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" \) 2>/dev/null | head -1)"
	if [[ -z $project_file ]]; then
		return 0
	fi
	target_framework=$(grep -oPm1 "(?<=<TargetFramework>)[^<]+" "$project_file")
	if [[ $target_framework =~ ";" ]]; then
	 	echo "$(cut -d ';' -f 1 <<< "$target_framework")"
	else
		echo "${target_framework//[a-z]/}"
	fi
}

# Returns the directory containing the first project file (.csproj, .fsproj
# or .vbproj) found within $1, at the same search depth bin/compile uses to
# pick which project to install the SDK against (maxdepth 2: the build dir
# root or one level of subdirectory, which also covers a solution's project
# folders). Echoes nothing if none exists.
# Note: there is no get_runtime_framework_version() here. A .csproj's
# <RuntimeFrameworkVersion> specifies the .NET *runtime* version, not an SDK
# version, and dotnet-install.sh installs the SDK (not just the runtime)
# whenever it's run without --runtime, which is how bin/compile calls it.
# Passing a RuntimeFrameworkVersion value as dotnet-install.sh's --version
# would ask it to install a nonexistent SDK build. SDK version selection is
# global.json, then productVersion.txt, then "Latest" — see bin/compile.
# args:
# input - $1
get_first_csproj_dir() {
	local search_dir="$1"
	local first_csproj
	first_csproj="$(find "$search_dir" -maxdepth 2 \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" \) 2>/dev/null | head -1)"
	if [[ -n $first_csproj ]]; then
		dirname "$first_csproj"
	fi
}

# Returns the path to a root-level, project-less C# file (a "file-based
# app" — e.g. `dotnet run app.cs`, with no .csproj at all), for use only
# when no solution or project file exists anywhere relevant. Searches the
# build dir root only (maxdepth 1: file-based apps don't have subdirectory
# layouts the way solutions do). Echoes nothing if none exists.
# args:
# input - $1
get_file_based_app_file() {
	local search_dir="$1"
	find "$search_dir" -maxdepth 1 -name "*.cs" 2>/dev/null | head -1
}

# Resolves the single shell command bin/test should run to execute the
# app's .NET tests, so bin/compile can decide it once (during a
# bin/test-compile build, while source files are still present) and record
# it for bin/test to just run later, rather than bin/test re-discovering it
# itself.
#
# Priority (first match wins):
#   1. A solution (.sln/.slnx) - `dotnet test` on a solution runs every test
#      project it references.
#   2. Any .csproj/.fsproj/.vbproj named *Test.<ext>/*Tests.<ext>, or
#      referencing the Microsoft.NET.Test.Sdk package, within 3 directories
#      of $1 (joined with "&&" if there's more than one).
# Echoes the resolved command, or nothing if no test project was found.
# args:
# input - $1
resolve_test_command() {
	local build_dir="$1"
	local solution_file
	solution_file="$(get_project_sln_file "$build_dir")"
	if [[ -n $solution_file ]]; then
		echo "dotnet test \"${solution_file}\" --configuration Release"
		return 0
	fi

	local -a test_targets=()
	local csproj
	while IFS='' read -r -d '' csproj; do
		if [[ $csproj == *Test.csproj || $csproj == *Tests.csproj \
			|| $csproj == *Test.fsproj || $csproj == *Tests.fsproj \
			|| $csproj == *Test.vbproj || $csproj == *Tests.vbproj ]] \
			|| grep -q "Microsoft.NET.Test.Sdk" "$csproj" 2>/dev/null; then
			test_targets+=("$csproj")
		fi
	done < <(find "$build_dir" -maxdepth 3 \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" \) -print0 2>/dev/null)

	if [[ ${#test_targets[@]} -eq 0 ]]; then
		return 0
	fi

	local cmd="" target
	for target in "${test_targets[@]}"; do
		[[ -n $cmd ]] && cmd+=" && "
		cmd+="dotnet test \"${target}\" --configuration Release"
	done
	echo "$cmd"
}

# args:
# input - $1
is_postgres_used() {
	if find "$1" -maxdepth 1 \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" \) -exec grep -l "Npgsql" {} \; 2>/dev/null | grep -q .; then
		echo "yes"
	else
		echo "no"
	fi
}

# args:
# input - $1
# shellcheck disable=SC2046  # intentional word-splitting: each KEY=VALUE line becomes its own export
source_envfile() { export $(cat "$1" | sed -e /^$/d -e /^#/d | xargs); }

# args:
# input - $1, $2
decimal_compare() {
   awk -v n1="$1" -v n2="$2" 'BEGIN {printf "%s " "$3" " %s\n", n1, n2}'
}
