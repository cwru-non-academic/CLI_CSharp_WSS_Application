# CLI_CSharp_WSS_Application

`CLI_CSharp_WSS_Application` is the standalone .NET CLI host for the HFI WSS stimulation stack.

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

## CLI options

- `--serial=NAME`: explicit serial device; ignored when `--test` is set
- `--config=PATH`: override the config directory
- `--max-retries=N`: max setup retries before startup fails
- `--tick=MS`: controller tick interval in milliseconds
- `--test`: use simulated transport instead of hardware
- `--help`: print usage information

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
