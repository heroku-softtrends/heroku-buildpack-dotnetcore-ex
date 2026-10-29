# .NET Core Buildpack for Heroku

### Supports .NET Core / .NET 3.1 LTS through the latest release
### by Softtrends LLC

A custom [Heroku buildpack](https://devcenter.heroku.com/articles/buildpacks) that
detects, compiles, and deploys .NET Core / ASP.NET Core applications
(including ASP.NET Core MVC apps) to Heroku. It downloads the matching .NET
SDK/runtime from Microsoft, publishes your app with `dotnet publish`, and wires
up a `Procfile` so `git push heroku master` just works.

Any editor works — Visual Studio Code up through the fully-featured Visual
Studio — but Visual Studio 2019 or later is recommended for best
compatibility.

## Usage

Add this buildpack to your Heroku app, then deploy as usual:

```bash
heroku buildpacks:add https://github.com/<org>/heroku-buildpack-dotnetcore-ex
git push heroku master
```

The buildpack supports any of the following at the root of your repo:
- a single project (`.csproj`, `.fsproj` or `.vbproj`) at the root,
- a solution (`.sln` or `.slnx`) with one or more projects, where the startup
  project is resolved from its `Properties/launchSettings.json`, or
- a file-based app: a standalone `.cs` file with no project at all (e.g.
  `dotnet run app.cs`). The published assembly is named after the file.

## Supported Heroku stacks

Package names are selected per Ubuntu release, matching the
[Microsoft .NET runtime dependency list](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu):

| Heroku stack | Ubuntu version | Status                     |
|--------------|-----------------|-----------------------------|
| heroku-26    | 26.04           | Supported                  |
| heroku-24    | 24.04           | Supported (default stack)  |
| heroku-22    | 22.04           | Supported (deprecated)      |
| heroku-20    | 20.04           | Supported (end-of-life)     |
| heroku-18    | 18.04           | Supported (end-of-life)     |
| heroku-16    | 16.04           | Supported (end-of-life)     |

Stack status (deprecated/end-of-life) reflects Heroku's own lifecycle for that
stack, not a limitation of this buildpack; check `heroku stack` and the
[Heroku Stack docs](https://devcenter.heroku.com/articles/stack) for the
current status of your app's stack.

Any other Ubuntu version (i.e. any stack not listed above) fails the build
immediately with an explicit "Unsupported Ubuntu version" error, rather than
silently skipping prerequisite package installation.

## .NET version support

This buildpack's `bin/detect` only rejects a project whose
`<TargetFramework>` resolves below `2.1` — it does **not** check whether a
version is still supported by Microsoft. That's a separate, independent
concern: you can deploy an out-of-support `<TargetFramework>` and the build
will still succeed, but the app runs on an SDK/runtime that no longer
receives security patches. Current status, per
[Microsoft's .NET support policy](https://dotnet.microsoft.com/platform/support/policy/dotnet-core)
(checked October 2026):

| Version        | Release type | End of support     | Status           |
|-----------------|---------------|----------------------|-------------------|
| .NET 10         | LTS           | November 14, 2028   | In support        |
| .NET 9          | STS           | November 10, 2026   | **Maintenance — ends in days** |
| .NET 8          | LTS           | November 10, 2026   | **Maintenance — ends in days** |
| .NET 7          | STS           | May 14, 2024        | Out of support    |
| .NET 6          | LTS           | November 12, 2024   | Out of support    |
| .NET 5          | STS           | May 10, 2022        | Out of support    |
| .NET Core 3.1   | LTS           | December 13, 2022   | Out of support    |

"Maintenance" means the final 6 months of a release's support window:
security-only fixes, no new features. **.NET 8 and .NET 9 both leave support
on November 10, 2026** — if your `<TargetFramework>` targets either, plan a
move to .NET 10 (LTS, supported through November 2028) soon. Within an
in-support major version, always build against its latest patch (e.g.
10.0.14 as of this check) — this buildpack's `"Latest"` SDK fallback (see
below) already does this for you when no exact version is pinned.

## Configuring the .NET SDK version

By default, the buildpack picks up the target framework from your project's
`<TargetFramework>` and installs the **latest matching SDK** for that
channel. To pin an exact SDK version, use one of the following (checked in
this order — the first one found wins):

1. **`global.json`** (recommended) — the standard .NET mechanism for pinning
   an SDK version, honored by the `dotnet` CLI, Visual Studio, and this
   buildpack alike. Place it at the root of your repo (or solution):

   ```json
   {
     "sdk": {
       "version": "8.0.100"
     }
   }
   ```

2. **`productVersion.txt`** — a buildpack-specific override, useful for
   version strings `global.json` doesn't cover (e.g. unlisted
   prerelease/RC builds). Place it at the root of any folder; its contents
   are used verbatim as the SDK version:

   ```
   8.0.100-rc.1.23463.5
   ```

3. Otherwise, the latest available SDK for the detected `<TargetFramework>`
   channel is installed.

> **Note:** a `.csproj`'s `<RuntimeFrameworkVersion>` is **not** used for SDK
> selection, and setting it has no effect on which SDK this buildpack
> installs. `RuntimeFrameworkVersion` specifies the .NET *runtime* version
> (e.g. `6.0.25`), which is a different, and differently-numbered, thing
> from an SDK version (e.g. `6.0.425`). This buildpack always installs the
> SDK (it never passes `--runtime` to `dotnet-install.sh`), so use
> `global.json` or `productVersion.txt` above if you need an exact SDK
> version.

## Environment variables

| Variable                            | Default        | Purpose                                                         |
|--------------------------------------|----------------|-------------------------------------------------------------------|
| `ASPNETCORE_ENVIRONMENT`             | `production`   | Passed through to the published app via `.profile.d`.           |
| `DOTNET_CLI_TELEMETRY_OPTOUT`        | `1`            | Disables the `dotnet` CLI's telemetry collection.                |
| `DOTNET_SKIP_FIRST_TIME_EXPERIENCE`  | `1`            | Skips the SDK's first-run NuGet package cache warm-up.           |

Any of these can be overridden by setting a Heroku config var of the same
name (`heroku config:set ASPNETCORE_ENVIRONMENT=staging`).

## How it works

This buildpack implements the standard Heroku buildpack interface
(`bin/detect`, `bin/compile`, `bin/release`):

- **`bin/detect`** — confirms the app is a solution (`.sln`/`.slnx`)
  referencing a project, a project (`.csproj`/`.fsproj`/`.vbproj`) at the
  root, or a file-based app (a standalone `.cs` file), and that the Heroku
  stack's Ubuntu version and the detected `<TargetFramework>` are supported
  (file-based apps have no `<TargetFramework>` to check, so only the
  Ubuntu-version check applies to them).
- **`bin/compile`** — validates that a usable project or file-based app
  exists (independently of `bin/detect`, since `bin/test-compile` calls it
  directly), installs OS-level prerequisites via `apt` from Ubuntu's own
  repositories (no unauthenticated or essential-package-removing installs),
  downloads and installs the resolved .NET SDK (via the vendored
  [`dotnet-install.sh`](bin/util/dotnet-install.sh)), runs `dotnet publish`,
  and writes a `Procfile` and `.profile.d/dotnetcore.sh` with the app's
  runtime environment. Any unsupported Ubuntu version, missing project, or
  undetectable target framework/startup project fails the build immediately
  with an explicit error rather than continuing partway.
- **`bin/release`** — validates the build directory and
  `.profile.d/dotnetcore.sh` exist, then emits the release-phase config used
  by `heroku releases`.
- **`bin/util/common.sh`** — shared shell helpers for locating project/
  solution files and resolving version information.

## Heroku CI (Testpack API)

`bin/test-compile` and `bin/test` implement Heroku's
[Testpack API](https://devcenter.heroku.com/articles/testpack-api), the pair
of hooks Heroku CI uses instead of `bin/compile`/`bin/release` when running
`heroku ci` (or a pipeline's CI stage) against a `.sln`/`.csproj`-using app:

- **`bin/test-compile <build-dir> <cache-dir> <env-dir>`** — builds the app
  like `bin/compile`, but for testing rather than deployment: it sets
  `ASPNETCORE_ENVIRONMENT=Staging`, and — unlike a normal build — tells
  `bin/compile` (via `HEROKU_DOTNET_TEST_BUILD=1`) to skip its slug-size
  "productionization" cleanup step and, while the source `.csproj`/`.sln`
  files are still present, resolve the test command and record it to
  `.heroku/test_command` for `bin/test` to run afterward.
- **`bin/test <build-dir> <env-dir>`** — runs whatever command
  `bin/compile` recorded in `.heroku/test_command` during the
  `bin/test-compile` build. It does no project discovery of its own.
  Resolution itself (done in `bin/compile`, see `resolve_test_command` in
  `bin/util/common.sh`) looks for, in order: a solution (`dotnet test` on a
  `.sln` runs every test project it references), then any `.csproj` named
  `*Test.csproj`/`*Tests.csproj` or referencing `Microsoft.NET.Test.Sdk`,
  within 3 directories of the build root. If no test command was recorded,
  `bin/test` exits 1 with an actionable message rather than reporting a
  false pass. Its exit code is whatever the recorded command returned.

To override test discovery entirely, set a `test` command in your
[app.json's `scripts`](https://devcenter.heroku.com/articles/app-json-schema#scripts)
— Heroku CI runs that instead of `bin/test`.

## Running the tests

The test suite uses [bats-core](https://github.com/bats-core/bats-core):

```bash
# Ubuntu/Debian
sudo apt-get install -y bats
# macOS
brew install bats-core

tests/run_tests.sh
# or directly:
bats tests/*.bats
```

- `tests/common.bats` — unit tests for the helper functions in
  `bin/util/common.sh` (project/solution discovery across `.csproj`/
  `.fsproj`/`.vbproj` and `.sln`/`.slnx`, file-based-app discovery, SDK
  version resolution, Npgsql detection, etc.) against fixture apps in
  `tests/fixtures/`.
- `tests/detect.bats` — exercises `bin/detect` against valid and invalid
  fixture apps (single-project, solution, `.slnx`, F#, VB.NET, and
  file-based apps), including unsupported Ubuntu versions and solutions
  with no usable startup project.
- `tests/compile.bats` — runs `bin/compile` end-to-end with `dotnet`,
  `apt-get`, `dpkg`, `curl`, and `dotnet-install.sh` stubbed out, verifying
  the SDK version resolution precedence (including that
  `<RuntimeFrameworkVersion>` is correctly *not* treated as an SDK version),
  the fail-fast validations (missing project, undetectable target
  framework, unsupported Ubuntu version), the file-based-app and
  F#/VB.NET publish paths, and the generated `Procfile` /
  `.profile.d/dotnetcore.sh`.
- `tests/release.bats` — exercises `bin/release`'s validation (missing
  build-dir argument, missing build directory, missing runtime profile) and
  its `default_process_types` output.
- `tests/test_compile.bats` — exercises `bin/test-compile`: that
  `ASPNETCORE_ENVIRONMENT=Staging` is exported before `bin/compile` runs
  (not after), that source files are preserved afterward, and that the test
  command is recorded to `.heroku/test_command`.
- `tests/test.bats` — exercises `bin/test` running the command recorded in
  `.heroku/test_command` (never discovering it itself), propagating its
  exit code, and failing with an actionable message when no command was
  recorded.

## References

- .NET Core — [Learn what's new](https://docs.microsoft.com/en-us/dotnet/core/)
- ASP.NET Core — [Learn what's new](https://go.microsoft.com/fwlink/?LinkId=518016)
- Visual Studio — [Learn and download](https://www.visualstudio.com/)
- Heroku Buildpacks — [How to use](https://devcenter.heroku.com/articles/buildpacks#setting-a-buildpack-on-an-application)
- Heroku Stack — [Current stack support and lifecycle](https://devcenter.heroku.com/articles/stack)
- .NET Support Policy — [Microsoft's lifecycle page](https://dotnet.microsoft.com/platform/support/policy/dotnet-core)
