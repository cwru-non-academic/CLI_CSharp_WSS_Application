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

## WSS release compatibility testing

The repository contains `.github/workflows/wss-compatibility.yml` for validating this application against the published WSS `v0.3.0-rc.7` release candidate. The workflow is manually triggered with `workflow_dispatch` and pins that exact release.

The workflow:

- downloads the exact `WSS-Serial-<TAG>.zip` GitHub Release asset
- verifies the release archive against its published `SHA256SUMS.txt`
- builds the application against the downloaded release instead of the checked-in DLLs
- runs on Windows, Ubuntu, and macOS
- verifies the application build and help/CLI loading
- verifies Test transport startup through `--test` and `--transport=test`
- constructs and disposes the Serial transport through `--serial-smoke`
- runs the deterministic CLI conformance path on Ubuntu and checks its process exit code and PASS markers

These non-hardware checks prove release-package compatibility and transport assembly loading. They do not prove communication with physical serial hardware.

For example, trigger the workflow with GitHub CLI using a release candidate tag appropriate for the test:

```bash
gh workflow run wss-compatibility.yml \
  --ref main
```

Normal local development uses the DLLs tracked under the integration submodule. Compatibility CI sets `WSS_ARTIFACT_DIR` to the DLLs extracted from the selected WSS GitHub Release. The workflow also disables the checked-in integration DLL directory and verifies assembly hashes, preventing the compatibility test from silently validating only the checked-in DLL version.
