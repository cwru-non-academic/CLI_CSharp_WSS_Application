# C# CLI maintenance

[README](../README.md) | [Shared CI guides](https://cwru-non-academic.github.io/WSS_Documentation/apiDocs/ci.html)

Normal CI validates the committed integration gitlink and its complete committed
universal distribution. General conformance exercises shared behavior once;
platform compatibility jobs check build/runtime loading and Serial construction
on Windows, Linux and macOS. Physical communication is a separate validation.

## Exact candidate preflight

[`wss-preflight.yml`](../.github/workflows/wss-preflight.yml) accepts an exact
successful Core producer run or release tag, full commit, archive name and
SHA-256. Use the same candidate tuple as Integration preflight. The optional
`integration_sha` selects the exact Integration source for preflight; otherwise
the committed gitlink is used. The selected Integration owns the resolver.
It validates provenance, archive checksum and inventory before extraction.
There is no old two-archive or default-release fallback.

All jobs consume one verified distribution. Build/publish checks cover backend
and runtime propagation. The normal .NET runtime-selected System.IO.Ports
assembly must not be overwritten by the portable root net462 alternate.

## Dependency promotion

[`promote-integration.yml`](../.github/workflows/promote-integration.yml)
creates a gitlink-only PR after validating the actual reviewed Integration merge,
normal CI, schema-2 approval, matching preflights and exact universal bytes.
Validation uses trusted Integration dev tooling before write credentials are
created. Existing PR reuse requires identical inputs.

The coordinated first-migration helper and retained historical proof records
live in the Integration repository. They are not the normal update path.
See [Integration maintenance](https://github.com/cwru-non-academic/CSharp_WSS_Integration_Lib/blob/main/docs/maintenance.md)
and the shared CI guides for the ownership split and workflow contracts.

## Safe local checks

```bash
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --conformance
dotnet run --project src/CLI_CSharp_WSS_Application.csproj -- --serial-smoke
```

These checks use the deterministic emulator or construct Serial without opening
a device. Release sign-off belongs to the shared
[1.0 readiness checklist](https://github.com/cwru-non-academic/WSS_Documentation/blob/main/apiDocs/conceptual/release-readiness.md).
