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

The manually triggered `.github/workflows/wss-preflight.yml` validates the CLI against an exact WSS release candidate. Its `WSS release artifact provenance` job downloads `WSS-Core-<TAG>.zip`, `WSS-BLE-Unified-<TAG>.zip`, and `SHA256SUMS.txt`, verifies the published checksums and required layout, and supplies the verified trees to the general and platform jobs. Those jobs disable the checked-in Integration `lib/` fallback, build against the downloaded release, and verify propagation into the CLI output.

The platform checks cover Windows, Ubuntu, and macOS build/runtime and Serial compatibility. They verify packaged backend and runtime trees where applicable, but the macOS check does not establish BLE runtime support. These non-hardware checks do not prove communication with physical hardware.

For example, trigger preflight with GitHub CLI using the workflow's configured default release candidate:

```bash
gh workflow run wss-preflight.yml \
  --ref main
```
