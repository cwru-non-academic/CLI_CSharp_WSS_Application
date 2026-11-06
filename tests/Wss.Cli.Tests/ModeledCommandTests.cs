using System.Reflection;
using NUnit.Framework;
using Wss.CSharpImplementation;
using Wss.Testing;

namespace Wss.Cli.Tests;

public sealed class ModeledCommandTests
{
    [Test]
    public async Task AnalogAndModeledCommandsReachChannelTwoThroughProductionDispatcher()
    {
        string directory = Path.Combine(Path.GetTempPath(), "wss-cli-modeled-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var scenario = WssStimulationSequences.LayeredSingleDevice[0];
            scenario.WriteFixture(directory);
            using var controller = new StimulationController(new StimulationOptions
            { ConfigPath = directory, Transport = StimulationTransportKind.Conformance, TickIntervalMs = 1, MaxSetupTries = 1 });
            controller.Initialize();
            Assert.That(controller.TryGetConformance(out var conformance), Is.True);
            bool started = false;
            for (int poll = 0; poll < 3000; poll++)
            {
                started = controller.Started() && conformance.StimulationHistory.Count > 0;
                if (started) break;
                await Task.Delay(1);
            }
            Assert.That(started, Is.True);
            var dispatcher = typeof(Program).GetMethod("ProcessCommand", BindingFlags.NonPublic | BindingFlags.Static);
            Assert.That(dispatcher, Is.Not.Null, "Production command dispatcher was not found.");
            var baseline = conformance.CaptureStimulationBaseline();
            dispatcher!.Invoke(null, new object[] { new[] { "analog", "ch2", "10", "10", "10" }, controller, true });
            await AssertWindow(conformance, baseline, new WssStimulationExpectation(0x81, 2, 10, 10, 10, 0x30));
            baseline = conformance.CaptureStimulationBaseline();
            dispatcher.Invoke(null, new object[] { new[] { "stim", "ch2", "0.5" }, controller, true });
            var modeled = scenario.Steps.Single(step => step.Id == "modeled.2");
            await AssertWindow(conformance, baseline, modeled.Expectation);
        }
        finally { Directory.Delete(directory, true); }
    }

    private static async Task AssertWindow(IWssConformance conformance, WssStimulationBaseline baseline,
        WssStimulationExpectation expected)
    {
        WssStimulationWindowResult result = WssStimulationWindow.Evaluate(conformance, baseline, expected, 1);
        for (int poll = 0; poll < 2000 && !result.Settled && result.Failures.Count == 0; poll++)
        {
            await Task.Delay(1);
            result = WssStimulationWindow.Evaluate(conformance, baseline, expected, 1);
        }
        Assert.That(result.Passed, Is.True, result.Diagnostics);
    }
}
