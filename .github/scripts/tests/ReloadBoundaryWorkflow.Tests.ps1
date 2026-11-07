# Source-only contract: no WSS payload is loaded or executed here.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$workflow = Get-Content (Join-Path $root '.github/workflows/cli-ci.yml') -Raw
$start = $workflow.IndexOf('      - name: Run additional production CLI reload boundaries')
if ($start -lt 0) { throw 'Missing additional reload workflow step.' }
$end = $workflow.IndexOf("`n      - ", $start + 1)
$body = if ($end -lt 0) { $workflow.Substring($start) } else { $workflow.Substring($start, $end - $start) }
$required = @(
    'Assert-CSharpProfileBootstrap',
    'Resolve-WssReviewedProfile $state.payload_root $state.profile.producer',
    '$profile.core_dll_sha256 -cne $state.profile.core_dll_sha256',
    "'legacy-v1' {", "'layered-v1' {",
    'this is not modern reload acceptance.',
    'default { throw ''Unknown reload capability profile.'' }',
    'dotnet test tests/Wss.Cli.Reload.Tests/Wss.Cli.Reload.Tests.csproj',
    'if ($LASTEXITCODE -ne 0) { throw',
    '$actual.Count -ne 4',
    'Compare-Object $expected @($actual.testName) -CaseSensitive',
    'Where-Object outcome -cne ''Passed'''
)
function Assert-ReloadStep([string]$Text) {
    foreach ($needle in $required) {
        if (!$Text.Contains($needle)) { throw "Missing reload invocation/profile guard: $needle" }
    }
    if ($Text -match 'continue-on-error:|(?m)^        if:') { throw 'Reload suite may not be bypassed by step conditions.' }
    if ($Text.IndexOf("'layered-v1' {") -ge $Text.IndexOf('dotnet test tests/Wss.Cli.Reload.Tests')) { throw 'Runtime discovery must be inside the modern branch.' }
}
Assert-ReloadStep $body
$count = 1
foreach ($needle in $required) {
    $rejected = $false
    try { Assert-ReloadStep ($body.Replace($needle, 'REMOVED')) } catch { $rejected = $true }
    if (!$rejected) { throw "Mutation accepted: $needle" }
    $count++
}
foreach ($injection in @("`n        if: false", "`n        continue-on-error: true")) {
    $rejected = $false
    try { Assert-ReloadStep ($body + $injection) } catch { $rejected = $true }
    if (!$rejected) { throw 'Bypassed reload step accepted.' }
    $count++
}
Write-Output "PASS: $count reload workflow invocation, profile, count and bypass source contracts."