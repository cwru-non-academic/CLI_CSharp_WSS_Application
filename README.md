# CLI_CSharp_WSS_Application

`CLI_CSharp_WSS_Application` is the standalone .NET CLI host for the WSS C# stimulation implementation.

This repo owns:
- the CLI entrypoint and REPL
- the runtime `Config/` directory
- build and run instructions for the application

The integration library lives in the `HFI_WSS_Csharp_Implementation` git submodule. Reusable C# implementation code and library-owned DLL/vendor dependencies stay there.

## Repository layout

- `src/CLI_CSharp_WSS_Application.csproj`: app project
- `src/Program.cs`: CLI entrypoint and REPL
- `Config/`: app-owned runtime configuration
- `SubModules/HFI_WSS_Csharp_Implementation/`: library submodule

## Clone with submodules

Clone the application repo and initialize the library in one step:

```bash
git clone --recurse-submodules git@github.com:cwru-non-academic/CLI_CSharp_WSS_Application.git
```

If you already cloned the app repo without submodules:

```bash
git submodule update --init --recursive
```

To update the submodule later:

```bash
git submodule update --init --recursive --remote
```

## Build

Install the .NET 9 SDK, which is required by the library's cross-platform BLE transport.

```bash
dotnet build CLI_CSharp_WSS_Application.sln
```

## Run

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- [options]
```

Example simulated startup:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --test
```

`--test` is an alias for `--transport=test`.

Run the deterministic, hardware-independent consumer conformance check:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --conformance
```

Verify that the Serial transport can be loaded and constructed without opening a serial device or requiring hardware:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --serial-smoke
```

Connect using a Nordic UART Service-compatible BLE device by name, identifier, or auto-selection:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --transport=ble --ble-auto
```

## CLI options

- `--transport=serial|ble|test|conformance`: select exactly one transport; defaults to Serial
- `--serial=NAME`: explicit serial device used by the Serial transport
- `--ble-auto`: scan for and auto-select a compatible BLE device
- `--ble-device-name=NAME`: select an exact BLE device name
- `--ble-device-id=ID`: select an explicit BLE device identifier
- `--config=PATH`: override the config directory
- `--max-retries=N`: max setup retries before startup fails
- `--tick=MS`: controller tick interval in milliseconds
- `--test`: alias for `--transport=test`
- `--conformance`: alias for `--transport=conformance`; initialize the WSS emulator and validate initialization plus one direct analog scenario
- `--serial-smoke`: construct and dispose the Serial transport without connecting to hardware; used for release compatibility testing
- `--help`: print usage information

## Config behavior

By default, the CLI resolves the repository root explicitly and uses the app repo's `Config/` directory from there. Conformance mode instead creates and removes a temporary deterministic configuration from the shared WSS stimulation fixture.

- default config path: `<repo-root>/Config`
- override: `--config=PATH`
- the resolved config path is converted to an absolute path before constructing `StimulationController`
- the config directory is created if it does not already exist

This is app-owned behavior. The controller and lower-level library layers consume the final resolved `ConfigPath` during construction/initialization.

## Ownership split

Application repo responsibilities:
- CLI entrypoint and command parsing
- runtime `Config/`
- solution/project wiring for the app

Library submodule responsibilities:
- `StimulationController`
- reusable WSS integration code
- library-owned DLL/vendor dependencies under the submodule

## Project reference

The CLI project references the library project directly with a `ProjectReference`:

- `src/CLI_CSharp_WSS_Application.csproj`
- `SubModules/HFI_WSS_Csharp_Implementation/src/Wss.CSharpImplementation.csproj`

## CI and WSS release compatibility testing

Normal pull-request CI separates shared behavior from operating-system compatibility:

- `CLI general conformance` runs hardware-independent Test transport, CLI conformance, and shared Integration conformance scenarios once.
- `CLI platform compatibility (Windows)`, `CLI platform compatibility (Ubuntu)`, and `CLI platform compatibility (macOS)` build and run platform loading and Serial construction smoke checks on each operating system.

The manually triggered `.github/workflows/wss-preflight.yml` validates the CLI against an
exact universal WSS candidate. Supply `wss_producer_repository=cwru-non-academic/WSSCore`,
`wss_run_id`, `wss_commit` (full SHA), `wss_archive=WSS-Universal-ci.zip`, and `wss_sha256`.
Use the **same tuple** for Integration preflight. The selected Integration source owns the
shared resolver: it rejects failed/wrong-commit/wrong-workflow runs and PR merge-ref artifacts,
verifies the archive against both the pinned hash and `SHA256SUMS.txt`, and validates the
exact nested universal inventory before extraction. A published universal release can be
selected with `wss_release_tag` instead of `wss_run_id`, with its matching archive/hash/commit.
It must resolve to one successful tag-push producer run with retained Actions assets; the
archive is downloaded from that run, not from manually attached release assets.
There is no default release or old two-archive fallback.

Set `integration_sha` to the full SHA of updated Integration source for preflight only.
If omitted, the committed gitlink is used exactly as before; obsolete pinned source fails
explicitly rather than silently selecting a newer branch. Test jobs disable committed `lib/`,
use the one verified universal root, and check complete build/publish propagation, including
both backends, the production Windows native library, and all runtime assets. The root
net462 Ports alternate is deliberately not copied over NuGet's Ports 8 host implementation.
The workflow retains `wss-candidate-provenance` and reports the tested Integration/CLI SHAs.

Normal CLI CI still tests the committed submodule and its committed binaries. The conditional
direct Serial reference leaves that old committed state untouched while adding a direct
reference for universal inputs. No gitlink update is part of preflight development.

The platform checks cover Windows, Ubuntu, and macOS build/runtime and Serial compatibility. They verify packaged backend and runtime trees where applicable, but the macOS check does not establish BLE runtime support. These non-hardware checks do not prove communication with physical hardware.

After the updated source is available remotely and a verified producer run exists, use:

```bash
gh workflow run wss-preflight.yml --ref <CLI_PREFLIGHT_REF> \
  -f integration_sha=<UPDATED_INTEGRATION_SHA> \
  -f wss_run_id=<SUCCESSFUL_PRODUCER_RUN_ID> \
  -f wss_commit=378a489423cac6e812327da52e5031922d4ed7e7 \
  -f wss_archive=WSS-Universal-ci.zip \
  -f wss_sha256=<ARCHIVE_SHA256>
```

## Universal promotion bootstrap

Routine `promote-integration.yml` remains gitlink-only. Dispatch on `dev` with
`integration_sha`, `integration_pr`, schema-2 `approval_json`, and `correlation_id`.
Validation uses trusted Integration **dev** tooling, not scripts from a caller-nominated commit.
It requires matching successful preflights, the actual Integration PR merge SHA contained in
`dev`, latest successful normal Integration CI, matching committed provenance, exact universal
bytes and source compatibility. Write credentials are created only after these checks.
Existing PR reuse remains exact-gitlink/metadata-only; branch lookup errors are not absence.
Normal CLI CI verifies complete build/publish propagation from the committed Integration `lib/`.

The first migration cannot use ordinary gitlink-only promotion because CLI source changes
must accompany adoption. Use the explicitly pinned `Prepare-UniversalBootstrap.ps1` in the
Integration automation worktree, with `-Repository CLI`, a clean separate CLI worktree containing
the validated source plus reviewed automation, a new scratch directory, the **merged Integration
PR number**, and `-Stage`. It never commits, pushes or creates PRs. Full instructions and the
fixed approval/proof records are in Integration's README and `.github/universal-bootstrap.json`.

Do not target Integration's preflight-only SHA. After the coordinated Integration PR passes
normal CI and is manually merged, prepare the CLI source-plus-final-gitlink PR, obtain publication
authorization, and require normal CLI CI and review before manual merge. This one-time manual
initiation leaves the permanent Integration bot/lib-only dispatch trigger unchanged. Subsequent
Integration merges return to that automatic dispatch and ordinary gitlink-only CLI promotion.
