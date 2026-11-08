using System.Reflection;
using System.Text.Json;
using NUnit.Framework;
using Wss.CSharpImplementation;
using Wss.CoreModule;
using Wss.Testing;

namespace Wss.Cli.Tests;

// Fixture JSON and wire observation reuse the wrapper ConfigurationReloadTests pattern.
// These are additional application tests, not additions to the canonical ten-case matrix.
[TestFixture, NonParallelizable]
public sealed class CommandReloadBoundaryTests
{
    private string root = null!;
    private StimulationController controller = null!;
    private string previousDirectory = null!;

    [SetUp]
    public void SetUp()
    {
        previousDirectory = Environment.CurrentDirectory;
        root = Path.Combine(Path.GetTempPath(), "wss-cli-reload-" + Guid.NewGuid().ToString("N"));
        WriteProfile(root, 1, 50, 150, 2, 1);
        controller = new StimulationController(new StimulationOptions
        { ConfigPath = root, Transport = StimulationTransportKind.Conformance, TickIntervalMs = 1, MaxSetupTries = 1 });
        controller.Initialize();
        Await(() => controller.Started());
        // Relative single-token paths exercise the supported whitespace parser contract
        // even on machines whose temporary parent directory contains spaces.
        Environment.CurrentDirectory = root;
    }

    [TearDown]
    public void TearDown()
    {
        Environment.CurrentDirectory = previousDirectory;
        controller.Dispose();
        Directory.Delete(root, true);
    }

    private void Dispatch(params string[] parts)
    {
        var method = typeof(Program).GetMethod("ProcessCommand", BindingFlags.NonPublic | BindingFlags.Static);
        Assert.That(method, Is.Not.Null);
        Assert.That(method!.Invoke(null, new object[] { parts, controller, true }), Is.EqualTo(true));
    }

    private void Stim(int width, int amplitude) =>
        ObserveOutput(() => Dispatch("stim", "ch2", "0.5"), width, amplitude);

    private void Rebuilt(IWssConformance retired)
    {
        Await(() => controller.Started());
        Assert.That(Conformance(), Is.Not.SameAs(retired));
        Assert.That(Conformance().MessageHistory.Any(x => x.MessageId == (byte)WSSMessageIDs.Clear), Is.True,
            "The replacement must perform real emulator setup.");
        var final = retired.StimulationHistory.Last(x => x.Channel == 2);
        Assert.That(final.PulseWidth, Is.Zero);
        Assert.That(final.PulseAmplitude, Is.Zero);
    }

    [Test]
    public void AllJsonReloadWithoutCoreChangeAppliesModelAndDefaultPaWithoutReconnect()
    {
        var original = Conformance();
        WriteProfile(root, 1, 100, 200, 4, .5);
        Dispatch("reload-params");
        Assert.That(Conformance(), Is.SameAs(original));
        Stim(125, 4);
    }

    [Test]
    public void DirectoryFileAndParameterlessCommandsUseStartupDefaultsAndRetireOldStack()
    {
        Stim(100, 2);
        string profile = Path.Combine(root, "profile");
        WriteProfile(profile, 2, 100, 200, 4, .5);
        var original = Conformance();
        Dispatch("reload-params", "profile");
        Rebuilt(original);
        Assert.That(controller.GetCoreConfigCTRL().MaxWss, Is.EqualTo(2));
        long retiredCount = original.MessageHistory.Count;
        Stim(125, 4);
        Assert.That(original.MessageHistory.Count, Is.EqualTo(retiredCount));

        File.Copy(Path.Combine(profile, "stimParams.json"), Path.Combine(profile, "specific.json"));
        var directoryStack = Conformance();
        Dispatch("reload-params", Path.Combine("profile", "specific.json"));
        Rebuilt(directoryStack);
        Assert.That(controller.GetCoreConfigCTRL().MaxWss, Is.EqualTo(1), "File reload uses startup Core, not sibling Core.");
        Stim(150, 4); // Startup model gain, explicit calibration/defaultPA.
        var fileStack = Conformance();
        Environment.CurrentDirectory = profile;
        Dispatch("reload-params");
        Assert.That(Conformance(), Is.SameAs(fileStack));
        Stim(100, 2);

        Environment.CurrentDirectory = root;
        Dispatch("reload-params", "profile");
        Await(() => controller.Started());
        Stim(125, 4);
        var beforeDefaults = Conformance();
        Environment.CurrentDirectory = profile;
        Dispatch("reload-params");
        Rebuilt(beforeDefaults);
        Assert.That(controller.GetCoreConfigCTRL().MaxWss, Is.EqualTo(1));
        Stim(100, 2);
    }

    [Test]
    public void CoreOnlyCommandRebuildsEvenUnchangedAndRetainsAppliedModelAndCalibration()
    {
        WriteProfile(root, 1, 100, 200, 4, .5);
        Dispatch("reload-params");
        Stim(125, 4);
        // Invalid on-disk model/calibration must not be read by a Core-only command.
        File.WriteAllText(Path.Combine(root, "modelConfig.json"), "invalid");
        File.WriteAllText(Path.Combine(root, "stimParams.json"), "invalid");
        WriteCore(root, 2);
        for (int reset = 0; reset < 2; reset++)
        {
            var retired = Conformance();
            Dispatch("reload-core");
            Rebuilt(retired);
            Assert.That(controller.GetCoreConfigCTRL().MaxWss, Is.EqualTo(2));
            long count = retired.MessageHistory.Count;
            Stim(125, 4);
            Assert.That(retired.MessageHistory.Count, Is.EqualTo(count));
        }
        var working = Conformance();
        File.WriteAllText(Path.Combine(root, "stimConfig.json"), "invalid");
        var error = Assert.Throws<TargetInvocationException>(() => Dispatch("reload-core"));
        Assert.That(error!.InnerException, Is.TypeOf<InvalidDataException>());
        Assert.That(Conformance(), Is.SameAs(working));
        Stim(125, 4);
    }

    [Test]
    public void CoreCommandOnInactiveControllerDoesNotInitializeOrReadInvalidCore()
    {
        controller.Shutdown();
        controller.Dispose();
        controller = new StimulationController(new StimulationOptions
        { ConfigPath = root, Transport = StimulationTransportKind.Conformance, TickIntervalMs = 1 });
        File.WriteAllText(Path.Combine(root, "stimConfig.json"), "invalid");
        Dispatch("reload-core");
        Assert.That(controller.Started(), Is.False);
        Assert.That(controller.TryGetConformance(out _), Is.False);
        WriteCore(root, 1);
        controller.Initialize();
        Await(() => controller.Started());
        controller.Shutdown();
        File.WriteAllText(Path.Combine(root, "stimConfig.json"), "invalid");
        Dispatch("reload-core");
        Assert.That(controller.Started(), Is.False);
        Assert.That(controller.TryGetConformance(out _), Is.False);
    }

    private IWssConformance Conformance()
    {
        Assert.That(controller.TryGetConformance(out var result), Is.True);
        return result;
    }

    private void ObserveOutput(Action operation, int pw, int amplitude)
    {
        var trace = Conformance();
        long baseline = trace.MessageHistory.Last().SequenceNumber;
        operation();
        Await(() => trace.StimulationHistory.Any(x => x.SequenceNumber > baseline && x.Channel == 2 &&
            x.PulseWidth == pw && x.PulseAmplitude == amplitude && x.InterPulseInterval == 13));
    }

    private static void Await(Func<bool> condition) =>
        Assert.That(SpinWait.SpinUntil(condition, 5000), Is.True, "Emulator did not observe the requested state/output.");

    private static void WriteProfile(string directory, int devices, int min, int max, int amplitude, double gain)
    {
        Directory.CreateDirectory(directory);
        WriteCore(directory, devices);
        var channels = Enumerable.Range(1, 9).ToDictionary(x => x.ToString(), _ => new
        { ampMode = "PW", minPW = min, maxPW = max, defaultPA = amplitude, IPI = 13 });
        File.WriteAllText(Path.Combine(directory, "stimParams.json"), JsonSerializer.Serialize(new { stim = new { ch = channels } }));
        File.WriteAllText(Path.Combine(directory, "modelConfig.json"), JsonSerializer.Serialize(new
        { calib = new { mode = "P" }, constants = new { PModeProportional = gain } }));
    }

    private static void WriteCore(string directory, int devices) => File.WriteAllText(Path.Combine(directory, "stimConfig.json"),
        JsonSerializer.Serialize(new
        {
            maxWSS = devices,
            firmware = "J03",
            useConfigAmpCurves = true,
            ampCurves = new[] { new { LowThreshold = 0, LowConst = 1, ExpPower = 1, LinearOffset = -1, LinearSlope = 1 } }
        }));
}
