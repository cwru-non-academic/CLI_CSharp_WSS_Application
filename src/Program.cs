using System.Globalization;
using System.Linq;
using System.Text.Json;
using Wss.Testing;
using WssTransport = Wss.Transports;

namespace Wss.CSharpImplementation;

/// <summary>
/// Console bootstrap that wires the stimulation controller to simple CLI arguments.
/// Defaults target a local Config directory with live hardware (test mode off) unless overridden.
/// </summary>
internal static class Program
{
    private const int InitializationPollLimit = 3000;
    private const int StimulationPollLimit = 2000;

    /// <summary>
    /// Entry point: parse args, start the controller, and run the interactive REPL.
    /// </summary>
    private static async Task<int> Main(string[] args)
    {
        if (args.Any(a => a is "--help" or "-h" or "/?"))
        {
            PrintCliUsage();
            return 0;
        }

        if (args.Any(a => a.Equals("--serial-smoke", StringComparison.OrdinalIgnoreCase)))
        {
            using (var transport = new WssTransport.SerialPortTransport(new WssTransport.SerialPortTransportOptions
            {
                PortName = OperatingSystem.IsWindows() ? "COM1" : "/dev/ttyWssSmoke",
                AutoSelectPort = false
            }))
            {
            }

            Console.WriteLine("Serial transport constructed and disposed successfully.");
            return 0;
        }

        string? conformanceConfigPath = null;
        try
        {
            (StimulationOptions options, conformanceConfigPath) = ParseOptions(args);
            using var controller = new StimulationController(options);

            controller.Initialize();
            if (conformanceConfigPath != null)
                return await RunConformanceAsync(controller);

            Console.WriteLine("WSS C# stimulation controller ready.");
            Console.WriteLine($"Config: {options.ConfigPath}");
            Console.WriteLine($"Transport: {GetTransportLabel(options)}");
            Console.WriteLine($"Mode valid: {controller.isModeValid()}, Ready: {controller.Ready()}, Basic API: {controller.BasicSupported}");
            PrintCommandHelp();
            RunInteractiveLoop(controller);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Startup failed: {ex.Message}");
            return 1;
        }
        finally
        {
            if (conformanceConfigPath != null && Directory.Exists(conformanceConfigPath))
                Directory.Delete(conformanceConfigPath, recursive: true);
        }
    }

    /// <summary>
    /// Translates CLI switches into strong typed options.
    /// Defaults: test mode OFF, auto-serial, Config folder in current working dir, 5 retries, 10 ms tick.
    /// </summary>
    private static (StimulationOptions Options, string? ConformanceConfigPath) ParseOptions(string[] args)
    {
        var transport = StimulationTransportKind.Serial;
        string? serial = null;
        bool bleAuto = false;
        string? bleDeviceName = null;
        string? bleDeviceId = null;
        int maxTries = 5;
        string configPath = GetDefaultConfigPath();
        int tickInterval = 10; // milliseconds

        foreach (var arg in args)
        {
            if (arg.StartsWith("--transport=", StringComparison.OrdinalIgnoreCase))
            {
                transport = ParseTransport(arg[(arg.IndexOf('=') + 1)..]);
            }
            else if (arg.StartsWith("--serial=", StringComparison.OrdinalIgnoreCase))
            {
                serial = arg[(arg.IndexOf('=') + 1)..];
            }
            else if (arg.Equals("--ble-auto", StringComparison.OrdinalIgnoreCase))
            {
                bleAuto = true;
            }
            else if (arg.StartsWith("--ble-device-name=", StringComparison.OrdinalIgnoreCase))
            {
                bleDeviceName = arg[(arg.IndexOf('=') + 1)..];
            }
            else if (arg.StartsWith("--ble-device-id=", StringComparison.OrdinalIgnoreCase))
            {
                bleDeviceId = arg[(arg.IndexOf('=') + 1)..];
            }
            else if (arg.StartsWith("--config=", StringComparison.OrdinalIgnoreCase))
            {
                var value = arg[(arg.IndexOf('=') + 1)..];
                if (!string.IsNullOrWhiteSpace(value))
                    configPath = Path.GetFullPath(value);
            }
            else if (arg.StartsWith("--max-retries=", StringComparison.OrdinalIgnoreCase))
            {
                var value = arg[(arg.IndexOf('=') + 1)..];
                if (int.TryParse(value, out var parsed) && parsed > 0)
                    maxTries = parsed;
            }
            else if (arg.StartsWith("--tick=", StringComparison.OrdinalIgnoreCase))
            {
                var value = arg[(arg.IndexOf('=') + 1)..];
                if (int.TryParse(value, out var parsed) && parsed > 0)
                    tickInterval = parsed;
            }
            else if (arg.Equals("--test", StringComparison.OrdinalIgnoreCase))
            {
                transport = StimulationTransportKind.Test;
            }
            else if (arg.Equals("--conformance", StringComparison.OrdinalIgnoreCase))
            {
                transport = StimulationTransportKind.Conformance;
            }
        }

        string? conformanceConfigPath = transport == StimulationTransportKind.Conformance
            ? CreateConformanceConfigDirectory()
            : null;
        if (conformanceConfigPath != null)
            configPath = conformanceConfigPath;

        configPath = Path.GetFullPath(configPath);
        Directory.CreateDirectory(configPath);

        return (
            new StimulationOptions
            {
                Transport = transport,
                SerialPort = serial,
                BleAutoSelect = bleAuto,
                BleDeviceName = bleDeviceName,
                BleDeviceId = bleDeviceId,
                MaxSetupTries = maxTries,
                ConfigPath = configPath,
                TickIntervalMs = tickInterval
            },
            conformanceConfigPath);
    }

    private static StimulationTransportKind ParseTransport(string value) => value.ToLowerInvariant() switch
    {
        "serial" => StimulationTransportKind.Serial,
        "ble" => StimulationTransportKind.Ble,
        "test" => StimulationTransportKind.Test,
        "conformance" => StimulationTransportKind.Conformance,
        _ => throw new ArgumentException(
            $"Unsupported transport '{value}'. Expected serial, ble, test, or conformance.")
    };

    private static string GetTransportLabel(StimulationOptions options) => options.Transport switch
    {
        StimulationTransportKind.Test => "test",
        StimulationTransportKind.Conformance => "conformance",
        StimulationTransportKind.Ble => options.BleAutoSelect
            ? "ble (auto-select)"
            : $"ble ({(string.IsNullOrWhiteSpace(options.BleDeviceId) ? options.BleDeviceName : options.BleDeviceId)})",
        _ => $"serial ({(string.IsNullOrWhiteSpace(options.SerialPort) ? "auto-detect" : options.SerialPort)})"
    };

    private static string CreateConformanceConfigDirectory()
    {
        WssStimulationFixtureProfile fixture = WssBehaviorScenarios.StimulationFixture;
        string channel = WssBehaviorScenarios.DirectAnalog.Channel.ToString(CultureInfo.InvariantCulture);
        string directory = Path.Combine(Path.GetTempPath(), $"wss-cli-conformance-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);

        try
        {
            var stimulationConfig = new
            {
                maxWSS = 1,
                firmware = "J03",
                broadcastTarget = "0x8F",
                wssTargets = new[] { "0x81", "0x82", "0x83" },
                useConfigAmpCurves = true,
                ampCurves = new[]
                {
                    new
                    {
                        LowThreshold = fixture.CurveLowThreshold,
                        LowConst = fixture.CurveLowConstant,
                        ExpPower = fixture.CurveExponent,
                        LinearOffset = fixture.CurveLinearOffset,
                        LinearSlope = fixture.CurveLinearSlope
                    }
                }
            };
            var stimulationParameters = new
            {
                stim = new
                {
                    ch = new Dictionary<string, object>
                    {
                        [channel] = new
                        {
                            ampMode = fixture.AmplitudeMode,
                            minPW = fixture.MinimumPulseWidth,
                            maxPW = fixture.MaximumPulseWidth,
                            minPA = 0.0,
                            maxPA = 0.0,
                            defaultPA = fixture.DefaultAmplitudeMa,
                            defaultPW = 50,
                            IPI = fixture.InterPulseInterval
                        }
                    }
                }
            };

            File.WriteAllText(
                Path.Combine(directory, "stimConfig.json"),
                JsonSerializer.Serialize(stimulationConfig));
            File.WriteAllText(
                Path.Combine(directory, "stimParams.json"),
                JsonSerializer.Serialize(stimulationParameters));
            return directory;
        }
        catch
        {
            Directory.Delete(directory, recursive: true);
            throw;
        }
    }

    private static async Task<int> RunConformanceAsync(StimulationController controller)
    {
        Console.WriteLine("WSS conformance:");
        if (!controller.TryGetConformance(out IWssConformance conformance))
            return ReportConformanceFailure("Initialization", "The C# implementation did not expose IWssConformance.");

        WssInitializationScenario initializationScenario = WssBehaviorScenarios.Initialization;
        bool operationalStateObserved = false;
        bool streamObserved = false;
        for (int i = 0; i < InitializationPollLimit; i++)
        {
            operationalStateObserved = operationalStateObserved || controller.Started();
            streamObserved = streamObserved || conformance.StimulationHistory.Count > 0;
            if ((!initializationScenario.RequiresOperationalState || operationalStateObserved) &&
                (!initializationScenario.RequiresStreamObservation || streamObserved))
            {
                break;
            }

            await Task.Delay(1);
        }

        if (initializationScenario.RequiresOperationalState && !operationalStateObserved)
            return ReportConformanceFailure("Initialization", "Core did not reach operational state within the finite poll limit.");
        if (initializationScenario.RequiresStreamObservation && !streamObserved)
            return ReportConformanceFailure("Initialization", "Core did not emit a startup stream within the finite poll limit.");

        InitializationConformanceResult initialization = conformance.ValidateInitialization();
        if (!initialization.Passed)
            return ReportConformanceFailure("Initialization", initialization.Failures);

        Console.WriteLine("Initialization: PASS");

        WssAnalogStimulationScenario scenario = WssBehaviorScenarios.DirectAnalog;
        WssStimulationBaseline baseline = conformance.CaptureStimulationBaseline();
        int amplitude = checked((int)scenario.AmplitudeMa);
        if (amplitude != scenario.AmplitudeMa)
            return ReportConformanceFailure("Direct analog", "The shared amplitude is not supported by the integer CLI API.");

        controller.StimulateAnalog(
            $"ch{scenario.Channel.ToString(CultureInfo.InvariantCulture)}",
            scenario.PulseWidth,
            amplitude,
            scenario.InterPulseInterval);

        bool stimulationObserved = false;
        for (int i = 0; i < StimulationPollLimit; i++)
        {
            stimulationObserved = conformance.StimulationHistory.Any(
                observation => observation.SequenceNumber > baseline.SequenceNumber);
            if (stimulationObserved)
                break;

            await Task.Delay(1);
        }

        if (!stimulationObserved)
            return ReportConformanceFailure("Direct analog", "No new stimulation observation arrived within the finite poll limit.");

        StimulationConformanceResult stimulation = conformance.ValidateStimulation(scenario.Expectation, baseline);
        if (!stimulation.Passed)
            return ReportConformanceFailure("Direct analog", stimulation.Failures);

        Console.WriteLine("Direct analog: PASS");
        Console.WriteLine("Result: PASS");
        return 0;
    }

    private static int ReportConformanceFailure(string check, IEnumerable<string> failures)
    {
        Console.Error.WriteLine($"{check}: FAIL");
        foreach (string failure in failures)
            Console.Error.WriteLine(failure);
        Console.Error.WriteLine("Result: FAIL");
        return 1;
    }

    private static int ReportConformanceFailure(string check, string failure) =>
        ReportConformanceFailure(check, new[] { failure });

    private static string GetDefaultConfigPath()
    {
        var repoRoot = GetRepositoryRoot();
        return Path.Combine(repoRoot, "Config");
    }

    private static string GetRepositoryRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);

        while (current != null)
        {
            if (File.Exists(Path.Combine(current.FullName, "CLI_CSharp_WSS_Application.sln")) ||
                Directory.Exists(Path.Combine(current.FullName, ".git")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new InvalidOperationException("Unable to locate the application repository root.");
    }

    /// <summary>
    /// Simple blocking REPL that lets operators send quick commands to the controller.
    /// CTRL+C now triggers an immediate shutdown even while a ReadLine is pending.
    /// </summary>
    private static void RunInteractiveLoop(StimulationController controller)
    {
        var running = true;

        void OnCancel(object? sender, ConsoleCancelEventArgs e)
        {
            e.Cancel = true;
            Console.WriteLine();
            Console.WriteLine("Cancellation requested. Shutting down...");
            controller.StopStimulation();
            controller.Shutdown();
            Environment.Exit(0);
        }

        Console.CancelKeyPress += OnCancel;

        while (running)
        {
            Console.Write("> ");
            var input = Console.ReadLine();
            if (input == null) break;
            if (string.IsNullOrWhiteSpace(input)) continue;

            var parts = input.Split(' ', StringSplitOptions.RemoveEmptyEntries);

            try
            {
                var handled = ProcessCommand(parts, controller, ref running);
                if (!handled)
                    Console.WriteLine("Unknown command. Type 'help' to list options.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Command failed: {ex.Message}");
            }
        }

        Console.CancelKeyPress -= OnCancel;
        controller.StopStimulation();
        controller.Shutdown();
    }

    /// <summary>
    /// Interprets REPL tokens and dispatches to the relevant controller APIs.
    /// </summary>
    private static bool ProcessCommand(string[] parts, StimulationController controller, ref bool running)
    {
        var cmd = parts[0].ToLowerInvariant();
        switch (cmd)
        {
            case "help":
                PrintCommandHelp();
                return true;

            case "quit":
            case "exit":
                running = false;
                return true;

            case "start":
                controller.StartStimulation();
                Console.WriteLine("Stim start requested.");
                return true;

            case "stop":
                controller.StopStimulation();
                Console.WriteLine("Stim stop requested.");
                return true;

            case "status":
                Console.WriteLine($"Ready={controller.Ready()}, Started={controller.Started()}, ModeValid={controller.isModeValid()}, BasicSupported={controller.BasicSupported}");
                return true;

            case "reload-core":
                controller.LoadCoreConfigFile();
                Console.WriteLine("Core config reloaded.");
                return true;

            case "reload-params":
                if (parts.Length > 1)
                    controller.LoadParamsJson(parts[1]);
                else
                    controller.LoadParamsJson();
                Console.WriteLine("Params reloaded.");
                return true;

            case "save-params":
                controller.SaveParamsJson();
                Console.WriteLine("Params saved.");
                return true;

            case "stim":
                if (parts.Length < 3)
                {
                    Console.WriteLine("Usage: stim <finger|chX> <magnitude>");
                    return true;
                }
                if (!float.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out var mag))
                    throw new InvalidOperationException("Magnitude must be numeric.");
                controller.StimWithMode(parts[1], mag);
                return true;

            case "analog":
                if (parts.Length < 3)
                {
                    Console.WriteLine("Usage: analog <finger|chX> <pw> [amp] [ipi]");
                    return true;
                }

                if (!int.TryParse(parts[2], out var pw))
                    throw new InvalidOperationException("Pulse width must be numeric.");
                int amp = parts.Length > 3 && int.TryParse(parts[3], out var parsedAmp) ? parsedAmp : 3;
                int ipi = parts.Length > 4 && int.TryParse(parts[4], out var parsedIpi) ? parsedIpi : 10;
                controller.StimulateAnalog(parts[1], pw, amp, ipi);
                return true;

            default:
                return false;
        }
    }

    /// <summary>Prints command-line options along with their defaults.</summary>
    private static void PrintCliUsage()
    {
        Console.WriteLine("WSS C# stimulation console");
        Console.WriteLine("Usage: dotnet run -- [options]");
        Console.WriteLine("Options (defaults in parentheses):");
        Console.WriteLine("  --transport=serial|ble|test|conformance  Transport selection (serial).");
        Console.WriteLine("  --serial=NAME       Fully qualified serial device (auto-detect for serial).");
        Console.WriteLine("  --ble-auto          Auto-select a compatible BLE device.");
        Console.WriteLine("  --ble-device-name=NAME  Exact BLE device name.");
        Console.WriteLine("  --ble-device-id=ID  Explicit BLE device identifier.");
        Console.WriteLine("  --config=PATH       Config directory path (" + GetDefaultConfigPath() + ").");
        Console.WriteLine("  --max-retries=N     Max setup retries (5).");
        Console.WriteLine("  --tick=MS           Tick interval in milliseconds (10).");
        Console.WriteLine("  --test              Alias for --transport=test.");
        Console.WriteLine("  --conformance       Alias for --transport=conformance and run deterministic checks.");
        Console.WriteLine("  --serial-smoke      Construct and dispose the serial transport without opening hardware.");
        Console.WriteLine("  --help              Show this message.");
    }

    /// <summary>Prints command help.</summary>
    private static void PrintCommandHelp()
    {
        Console.WriteLine("Commands:");
        Console.WriteLine("  help                Show this help text.");
        Console.WriteLine("  start               Broadcast StartStim.");
        Console.WriteLine("  stop                Broadcast StopStim.");
        Console.WriteLine("  stim <finger> <v>  Stim with model/params layer (normalized magnitude).");
        Console.WriteLine("  analog <finger> <pw> [amp] [ipi]  Send direct analog request.");
        Console.WriteLine("  reload-core         Reload the core config JSON.");
        Console.WriteLine("  reload-params [p]   Reload params JSON (optionally from path).");
        Console.WriteLine("  save-params         Persist params JSON.");
        Console.WriteLine("  status              Print Ready/Started/mode state.");
        Console.WriteLine("  quit|exit           Terminate the program.");
    }
}
