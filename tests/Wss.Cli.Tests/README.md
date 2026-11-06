# CLI command regression

This test compiles the production command dispatcher and invokes `analog ch2 ...` followed by `stim ch2 ...` through it. The controller uses Core's emulator and shared fixture/evaluator. It does not duplicate JSON lookup tests or select physical hardware.

Run with the reviewed integration checkout and payload:

```powershell
dotnet test tests/Wss.Cli.Tests/Wss.Cli.Tests.csproj -c Release -p:WssIntegrationRoot=/path/to/CSharp_WSS_Integration_Lib -p:WssArtifactDir=/path/to/payload -p:WssBleArtifactDir=/path/to/payload
```

The payload must contain the shared layered scenario API. Hosted adoption requires updated integration/payload pins.
