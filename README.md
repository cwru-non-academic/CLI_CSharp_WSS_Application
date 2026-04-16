# CLI_CSharp_WSS_Application

`CLI_CSharp_WSS_Application` is the standalone .NET CLI host for the HFI WSS stimulation stack.

Requires the .NET 9 SDK.

This repo owns:
- the CLI entrypoint and REPL
- the runtime `Config/` directory
- build and run instructions for the application

The integration library lives in the `HFI_WSS_Csharp_Implementation` git submodule. Reusable controller code and library-owned DLL/vendor dependencies stay there.

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

Install the .NET 9 SDK first. The CLI and the shared library now target `net9.0` so BLE can use the Linux provider shipped by `InTheHand.BluetoothLE`.

```bash
dotnet build CLI_CSharp_WSS_Application.sln
```

## Run

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- [options]
```

On Linux, BLE requires this `net9.0` build. Earlier `net8.0` builds can compile the BLE code but fail at runtime because the package does not provide the Linux backend on that target.

Example simulated startup:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --transport=test
```

Example serial startup:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --transport=serial --serial=/dev/ttyUSB0
```

Example BLE startup:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --transport=ble --ble-auto
```

## CLI options

- `--transport=serial|ble|test`: select the transport implementation; defaults to `serial`
- `--serial=NAME`: explicit serial device when `--transport=serial`; otherwise serial uses auto-detect
- `--ble-auto`: scan for compatible BLE devices and auto-select the best candidate
- `--ble-device-name=NAME`: connect to an exact BLE device name when `--transport=ble`
- `--ble-device-id=ID`: connect to an explicit BLE device id when `--transport=ble`
- `--config=PATH`: override the config directory
- `--max-retries=N`: max setup retries before startup fails
- `--tick=MS`: controller tick interval in milliseconds
- `--help`: print usage information

For BLE, provide at least one of `--ble-auto`, `--ble-device-name=NAME`, or `--ble-device-id=ID`.

WSS BLE uses an unpaired Nordic UART Service connection. The CLI does not require or request BLE pairing.

## Config behavior

By default, the CLI resolves the repository root explicitly and uses the app repo's `Config/` directory from there.

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
- `SubModules/HFI_WSS_Csharp_Implementation/src/HFI_WSS_Csharp_Implementation.csproj`
