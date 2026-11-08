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
- `--ble-smoke`: use alone to construct and dispose the platform BLE facade twice without scanning, connecting, reading configuration or writing to a device. Native ABI checks remain in the Integration platform tests.
- `--help`: print usage information

## Interactive commands

Enter these commands at the application's `>` prompt after startup; they are
separate from startup options such as `--test`. Command names and finger/channel
aliases are case-insensitive. In the syntax below, `<...>` is required and
`[...]` is optional; do not type the brackets.

| Command | What it does and inputs | Example at the prompt |
| --- | --- | --- |
| `help` | Show interactive command syntax, units and defaults. | `help` |
| `status` | Query controller state and available API support. See the state explanation below. | `status` |
| `start` | Request a broadcast start for the configured devices; takes no channel or magnitude. | `start` |
| `stop` | Request a broadcast stop; takes no channel argument. | `stop` |
| `stim <finger\|chN> <magnitude>` | Update one logical channel using the active model and stimulation parameters. Intended magnitude input is a finite number from `0.0` to `1.0`. | `stim ch1 1.0` |
| `analog <finger\|chN> <pw> [amp] [ipi]` | Update one channel directly, bypassing model/parameter mapping. Pulse width is in microseconds, amplitude is in the mA domain (mapped to device scale), and inter-pulse interval is in milliseconds. Use integers; omitted `amp` is `3`, omitted `ipi` is `10`. | `analog ch1 50 1 10` |
| `reload-core` | Reload the active `stimConfig.json` through the host reset path, retaining current calibration/model values. Reconstructs Core, including receiver addressing. | `reload-core` |
| `reload-params [path]` | Reload all three startup-default JSON files. A directory selects all three standard filenames. An explicit file overrides the calibration path only; Core/model files are reread from startup defaults. | `reload-params ./Config/stimParams.json` |
| `save-params` | Write active stimulation parameters to their current JSON file. This is host-side persistence, not a device configuration save. | `save-params` |
| `quit` or `exit` | Leave the console and clean up the controller. | `quit` |

### Channels, values and state

`chN` selects a 1-based logical channel. Finger aliases map to `thumb` = `ch1`,
`index` = `ch2`, `middle` = `ch3`, `ring` = `ch4`, and `pinky`/`little` = `ch5`.
Use a channel available in your configuration; recognizing a name does not make
that channel available. For example, a one-device configuration has three
logical channels, so `ring` and `pinky` are outside its range.

`stim ch1 1.0` supplies normalized input **1.0**, not 1 mA. The active P/PD model
and per-channel `stimParams.json` settings determine the resulting pulse width
and amplitude. `stim thumb 0.25` supplies 0.25 to the same channel. The intended
input interval is `0.0` through `1.0`; this is not a claim that the command parser
rejects every value outside that interval. Model mapping can change the output,
so even input `0` is not a substitute for the broadcast `stop` command.

`analog ch1 50` uses pulse width 50, amplitude 3 and IPI 10. To choose an IPI,
supply the amplitude too: `analog ch1 50 1 20`. These are syntax examples, not
recommended settings for a person or device. Direct analog values do not use
the normalized calibration mapping. The CLI does not impose a universal
calibrated operating range; use settings appropriate to your firmware, device
and calibration. A successfully parsed request does not establish valid physical
output. Stimulation commands update runtime values; `save-params` does not turn
an analog request into new calibration settings.

Setup continues asynchronously. `Ready` describes the Core state in which a
start can be accepted, while `Started` describes started/streaming state;
`Ready` need not remain true while streaming. `ModeValid` reports model-mode
support, and `BasicSupported` reports availability of the optional Basic API.
These flags and printed request messages do not prove physical stimulation.

### Parsing and paths

Magnitude uses invariant-culture floating-point syntax: use `1.0`, not a
locale-specific decimal comma. Analog values are signed 32-bit integers
(`50`, not `50.0`). Missing required `stim`/`analog` arguments print usage.
Invalid magnitude or pulse-width text prints `Command failed`. **Invalid optional
amplitude or IPI text falls back to 3 or 10 respectively**, just as omission does;
enter explicit valid integers. Extra arguments are ignored by current handlers.
Magnitude parsing does not explicitly reject all non-finite values.

Interactive input is split on spaces. `reload-params` accepts a single path
token: quotes do **not** enable spaces in paths. For example, use
`reload-params C:/WSS/Config/stimParams.json`; select a location without spaces.

For default, directory and explicit-file selection, reconstruction and retained
values, see [Coordinated configuration reload](#coordinated-configuration-reload).

### Practice without hardware

After building the app, create a temporary copy of `Config` and start
the simulated transport. From the repository root in PowerShell:

```powershell
$practiceConfig = Join-Path ([System.IO.Path]::GetTempPath()) ("wss-practice-" + [guid]::NewGuid())
Copy-Item -LiteralPath ./Config -Destination $practiceConfig -Recurse
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --test --config="$practiceConfig"
```

`--conformance` runs finite diagnostics and exits; it does not open this prompt.

In that simulated session, try these commands one at a time. Inspect `status`
and let setup progress before requesting a start. After `start`, wait for
`Started` before the stimulation examples. These commands demonstrate syntax;
the configured model and parameters still control the simulated values.

```text
help
status
start
status
stim ch1 1.0
stim thumb 0.25
analog ch1 50 1 10
stop
reload-core
reload-params
save-params
quit
```

The copy isolates configuration writes, not just the log file. Serial/BLE startup
selects live transports; keep `--test` for this exercise. A simulated session
does not validate physical communication or output.

## Coordinated configuration reload

These commands use the coordinated reload support in the wrapper pinned by this
MAIN checkout. Older checkouts must be checked against their own wrapper
source and Core payload; updating Core alone does not add the host reset behavior.

Enter `reload-core`, `reload-params [path]`, or `save-params` at the interactive
prompt. Do not type the brackets. The commands call `LoadCoreConfigFile()`,
`LoadParamsJson()` / `LoadParamsJson(path)`, and `SaveParamsJson()` respectively.

- `reload-params` rereads all three startup-default files: `stimConfig.json`,
  `stimParams.json`, and `modelConfig.json`. It returns to those defaults even
  after selecting another profile.
- `reload-params ./Config/profile` selects all three standard filenames in that
  directory.
- `reload-params ./Config/customParams.json` selects that calibration file with
  the startup-default Core and model files, **not sibling files** next to the
  selected calibration file. All three JSON files are still read and validated.
- `reload-core` reads the active Core file, retains currently applied in-memory
  calibration/model values and paths (including unsaved edits), and reconstructs
  Core through the host reset path, including its receiver address map. It
  reconstructs even if Core values are unchanged. Before initialization this
  Core reset is a no-op.
- `save-params` writes active stimulation parameters to the selected calibration
  file. It does not save device configuration or persist the Core/model files.

The startup defaults come from the application's resolved configuration directory
(`Config/` in the app repository unless overridden at startup). Startup paths
remain anchored even if the process working directory changes. Relative explicit
reload paths are resolved against the process working directory.

Reload stages and validates files before changing the active stack. Any effective
Core configuration change uses the existing reset path: stop ticking, dispose the
old stack (Core zeros output and disconnects), construct the validated replacement,
and resume initialization/ticking. Unchanged Core permits calibration/model
updates without reconnecting. A reset does not replay previous stimulation values.
`reload-core` retains applied calibration/model values; `reload-params` rereads them.
Use `status` to check asynchronous setup and wait for `Started` before sending new
stimulation commands after reconstruction. A printed reload message does not
establish device readiness or physical output.

Invalid JSON leaves the active stack unchanged. Cleanup or construction failure
can leave the controller unavailable; inspect the reported error rather than
assuming the replacement is ready. Use a disposable configuration copy with the
simulated transport when practicing reloads or `save-params`.

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

The platform checks cover Windows, Ubuntu, and macOS package/runtime and Serial compatibility. BLE facade loading is checked without hardware; Integration tests additionally validate the declared macOS managed/native pair, ABI `0x00010000`, registration and disconnected construction. macOS requires a 64-bit macOS 11 or newer host. These checks do not prove Bluetooth authorization, adapter availability or communication with a peripheral.

Published `--conformance` runs from any working directory using its own temporary canonical configuration. `--ble-smoke` also works without locating a repository. Live modes retain the existing repository configuration default or explicit `--config=PATH`; custom targets such as `0x80` are not rewritten by these checks.

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

For routine automatic updates, no operator dispatch or provenance entry is needed:
WSSCore's trusted `dev` push runs the universal producer and all consumers, then automatically
hands its exact run/artifact/commit/checksum to Integration's existing promotion workflow.
That workflow runs both existing downstream preflights against the same candidate, pins
CLI's Integration source, validates schema-2 approval, and opens a lib-only Integration PR.
Its reviewed merge invokes the existing dispatcher above with the **actual merged**
Integration revision, producing the gitlink-only CLI PR. Reviewed merges and normal CI
remain mandatory; no bootstrap, auto-merge, release or manual DLL copying is involved.
Missing/expired/mismatched evidence stops the cascade. The automatic implementation still
requires an authorized real run to establish end-to-end acceptance; hosted CI does not
prove physical BLE or stimulation operation.

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

## Independent selected test bundle

The additional selected-test runner keeps product checkout SHAs and the selected
payload fixed. Core must authenticate the frozen test selection before invoking
it. A syntactically valid selection ID is only a local binding, not approval.

For C#, invoke the trusted `.github/scripts/Invoke-SelectedCSharpTests.ps1` with
`Role`, `ProductRoot`, `ProductSha`, `PayloadRoot`, a new `WorkRoot`, and the complete
`TestRoot`, `TestSha`, `TestRepository`, `TestSelectionId` tuple. The CLI also takes
its unchanged `IntegrationRoot` and `IntegrationSha`. The selected checkout must
contain `tests/test-contract.json` and be clean. The trusted generated project
compiles selected C# test files against explicit product sources; selected
projects, build overrides and release validators are never executed.

This suite is additional to the existing mandatory CI gates. It does not change
product readiness, package provenance, native-platform requirements, release
approval or receipt verification. The wrapper retains the reviewed canonical
assertions and both 16-case stages; the CLI retains its ten command cases.
`test-source-evidence.json` records the selected source, contract hash and product
identities only after source and payload postchecks pass. Workflow selection and
campaign evidence adoption must land separately before repository variables are
advertised as active.
Selected C# runs require fresh product checkouts without prior bin/obj outputs. This prevents stale NuGet intermediate imports from affecting the build; generated outputs from this run are allowed only during postchecks.
The product project is built from a trusted git archive at the declared integration SHA in the new work directory. Original product checkouts remain pristine for Core evidence verification; staged source hashes are rechecked after execution.
