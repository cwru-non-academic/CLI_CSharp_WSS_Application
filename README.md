# WSS C# CLI

An interactive .NET application for WSS. The application owns its `Config/`
directory and consumes the [C# integration library](https://github.com/cwru-non-academic/CSharp_WSS_Integration_Lib#readme)
as a pinned submodule.

## Set up

Install the .NET 9 SDK. The first build restores NuGet dependencies.

```bash
git clone --recurse-submodules https://github.com/cwru-non-academic/CLI_CSharp_WSS_Application.git
cd CLI_CSharp_WSS_Application
dotnet build CLI_CSharp_WSS_Application.sln
```

For an existing clone, run `git submodule update --init --recursive` first.
Keep the pinned submodule and its complete `lib/` payload together.

## Start without hardware

Run commands from the repository root:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --test
```

`--test` selects the simulated Test transport. At the prompt, use `help` for
commands, `status` for state, and `quit` or `exit` to shut down. Test mode uses the
application's `Config/` directory; choose another directory with `--config=PATH`.

For a deterministic emulator check that validates initialization and one analog
scenario, prints the result and exits:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --conformance
```

Conformance mode creates and removes its own temporary configuration and does
not connect to hardware.

## Connect a device

Serial and BLE are supported on Windows, Linux and macOS. Windows BLE requires
an x64 process; Linux BLE requires BlueZ and system D-Bus. Give the application
access to the intended device using your operating system's settings.

After reviewing `Config/` for the intended device, select a transport explicitly:

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --transport=serial --serial=COM3
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --transport=ble --ble-device-name=YOUR_DEVICE_NAME
```

Replace `COM3` with the intended port (for example `/dev/ttyUSB0` on Linux).
BLE also accepts `--ble-device-id=ID` or `--ble-auto` for a compatible Nordic UART
Service device. Running without options selects live Serial with auto-detection.

## Useful options

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --help
```

| Option | Purpose |
| --- | --- |
| `--config=PATH` | Application configuration directory; defaults to the repository's `Config/` |
| `--transport=serial\|ble\|test\|conformance` | Transport selection |
| `--max-retries=N` | Setup retry limit |
| `--tick=MS` | Background controller tick interval in milliseconds |
| `--serial-smoke` | Construct and dispose Serial without opening a device, then exit |

The CLI resolves configuration to an absolute path before creating the
controller. Missing directories are created. `reload-core` and `reload-params`
reload configuration through the interactive prompt; use `help` for available
commands and argument syntax.

## Further guidance

- [Shared documentation](https://cwru-non-academic.github.io/WSS_Documentation/): configuration, setup order, transport concepts and protocol reference.
- [C# library README](https://github.com/cwru-non-academic/CSharp_WSS_Integration_Lib#readme): integrate WSS into your own application.
- [Maintainer validation](docs/maintenance.md): CI, candidate preflight and dependency updates.
