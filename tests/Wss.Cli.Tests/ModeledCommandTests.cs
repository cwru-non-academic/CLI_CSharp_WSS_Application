using System.Globalization;
using System.Reflection;
using NUnit.Framework;
using Wss.CSharpImplementation;
using Wss.Testing;

namespace Wss.Cli.Tests;

public sealed class ModeledCommandTests
{
    private static IEnumerable<TestCaseData> CommandScenarios =>
        WssStimulationSequences.LayeredSingleDevice.Concat(WssStimulationSequences.LayeredMultipleDevices)
            .Concat(WssStimulationSequences.SingleDevice.Where(s => s.Id.StartsWith("analog.")))
            .Concat(WssStimulationSequences.MultipleDevices.Where(s => s.Id.StartsWith("analog.")))
            .Select(s => new TestCaseData(s).SetName(s.Id));

    [TestCaseSource(nameof(CommandScenarios))]
    public async Task CommandsReachConfiguredChannelsThroughProductionDispatcher(WssStimulationSequence scenario)
    {
        string directory = Path.Combine(Path.GetTempPath(), "wss-cli-modeled-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            scenario.WriteFixture(directory);
            using var controller = new StimulationController(new StimulationOptions
            { ConfigPath = directory, Transport = StimulationTransportKind.Conformance, TickIntervalMs = 1, MaxSetupTries = 1 });
            controller.Initialize();
            Assert.That(controller.TryGetConformance(out var conformance), Is.True);
            bool started = false;
            for (int poll = 0; poll < 3000; poll++)
            {
                started = controller.Started() && Enumerable.Range(0, scenario.DeviceCount)
                    .All(unit => conformance.StimulationHistory.Any(frame => frame.Target == 0x81 + unit));
                if (started) break;
                await Task.Delay(1);
            }
            Assert.That(started, Is.True);
            var dispatcher = typeof(Program).GetMethod("ProcessCommand", BindingFlags.NonPublic | BindingFlags.Static);
            Assert.That(dispatcher, Is.Not.Null, "Production command dispatcher was not found.");
            void Dispatch(params string[] parts) => dispatcher!.Invoke(null, new object[] { parts, controller, true });
            string[] aliases = { "thumb", "index", "middle", "ring", "pinky" };
            foreach (var step in scenario.Steps)
            {
                step.PrepareReload(directory);
                if (step.ReloadParameters) Dispatch("reload-params");
                // Current CLI does not expose a model-only reload command.
                if (step.ReloadModel) controller.GetModelConfigCTRL().LoadModelJson();
                var baseline = conformance.CaptureStimulationBaseline();
                string channel = scenario.ModelMode == "P" && step.GlobalChannel <= aliases.Length
                    ? aliases[step.GlobalChannel - 1] : $"ch{step.GlobalChannel}";
                if (step.Modeled) Dispatch("stim", channel, step.Input.ToString(CultureInfo.InvariantCulture));
                else Dispatch("analog", channel, step.Expectation.PulseWidth.ToString(CultureInfo.InvariantCulture),
                    step.Expectation.PulseAmplitude.ToString(CultureInfo.InvariantCulture), step.Expectation.InterPulseInterval.ToString(CultureInfo.InvariantCulture));
                WssStimulationWindowResult result = WssStimulationWindow.Evaluate(conformance, baseline, step.Expectation, scenario.DeviceCount);
                for (int poll = 0; poll < 2000 && !result.Settled && result.Failures.Count == 0; poll++)
                {
                    await Task.Delay(1);
                    result = WssStimulationWindow.Evaluate(conformance, baseline, step.Expectation, scenario.DeviceCount);
                }
                Assert.That(result.Passed, Is.True, scenario.Id + "/" + step.Id + ": " + result.Diagnostics);
            }
        }
        finally { Directory.Delete(directory, true); }
    }
}
