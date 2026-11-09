param([string]$ResultsDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('wss-cli-commands-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
. "$PSScriptRoot/CSharpProfilesBootstrap.ps1"
Assert-CSharpProfileBootstrap
. "$PSScriptRoot/../../tools/CSharpProfiles/Profile.ps1"
if(!$env:WSS_PROFILE_EVIDENCE){throw 'CLI command tests require authenticated profile preparation.'}
$state=Get-Content -LiteralPath $env:WSS_PROFILE_EVIDENCE -Raw | ConvertFrom-Json
$profile=Resolve-WssReviewedProfile $state.payload_root $state.profile.producer
if($profile.profile -cne $state.profile.profile -or $profile.core_dll_sha256 -cne $state.profile.core_dll_sha256){throw 'CLI profile differs from verified preparation.'}
if($profile.profile -ceq 'legacy-v1') {
 # Preserve the actual old producer's complete CLI smoke contract; layered command
 # APIs are mandatory only for a complete modern payload, never inferred from TRX.
 $cli=Join-Path $PSScriptRoot '../../src/bin/Release/net9.0/CLI_CSharp_WSS_Application.dll'
 $actualCore=Join-Path (Split-Path $cli) 'WSS_Core_Interface.dll'
 if((Get-FileHash $actualCore -Algorithm SHA256).Hash.ToLowerInvariant() -cne $profile.core_dll_sha256){throw 'CLI output differs from verified legacy payload.'}
 $output=& dotnet $cli --conformance
 if($LASTEXITCODE -ne 0){throw 'Legacy CLI behavioral conformance failed.'}
 foreach($line in @('Initialization: PASS','Direct analog: PASS','Result: PASS')){if($output -cnotcontains $line){throw "Missing legacy CLI conformance: $line"}}
 New-Item -ItemType Directory -Force $ResultsDirectory | Out-Null
 @{profile=$profile;contract='legacy-cli-conformance';passed=$true} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $ResultsDirectory 'legacy-command-profile.json')
 return
}

$project=Join-Path $PSScriptRoot '../../tests/Wss.Cli.Tests/Wss.Cli.Tests.csproj'
. "$PSScriptRoot/wss-ci/restored-assets/RestoredAssets.ps1"
. "$PSScriptRoot/wss-ci/compiled-tests/CompiledCSharpTests.ps1"
$properties=@('-p:DisablePackageAssetsCache=true','-p:TreatWarningsAsErrors=true','-p:ImportDirectoryBuildProps=false','-p:ImportDirectoryBuildTargets=false',"-p:WSS_ARTIFACT_DIR=$($state.payload_root)","-p:WSS_BLE_ARTIFACT_DIR=$($state.payload_root)")
& dotnet restore $project @properties
if($LASTEXITCODE -ne 0){throw 'CLI command restore failed.'}
$assets=Join-Path (Split-Path $project) 'obj/project.assets.json'
$restoreProof=New-WssRestoredAssetsProof -ProjectAssetsFile $assets -ProjectPath $project
& dotnet build $project -c Release --no-restore @properties
if($LASTEXITCODE -ne 0){throw 'CLI command build failed.'}
$output=Join-Path (Split-Path $project) 'bin/Release/net9.0'
& "$PSScriptRoot/Verify-WssOutput.ps1" -ArtifactRoot $state.payload_root -OutputRoot $output -ProjectPath $project -ProjectAssetsFile $assets -RestoreProof $restoreProof
$restoreSnapshot=New-TrustedBaselineSnapshot @($project,$assets,$restoreProof.NeutralAssetPath,(Join-Path $PSScriptRoot 'wss-ci/restored-assets'),(Join-Path $PSScriptRoot 'Verify-WssOutput.ps1'))
$compiledProof=New-CompiledCSharpTestProof -OutputRoot $output -AssemblyName 'Wss.Cli.Tests.dll'
Invoke-CompiledCSharpTests -Proof $compiledProof -ResultsDirectory $ResultsDirectory -TrxFileName 'commands.trx'
Assert-TrustedBaselineSnapshot $restoreSnapshot
Assert-WssRestoredAssetsProof -Proof $restoreProof -ProjectAssetsFile $assets -ProjectPath $project
& "$PSScriptRoot/Verify-WssOutput.ps1" -ArtifactRoot $state.payload_root -OutputRoot $output -ProjectPath $project -ProjectAssetsFile $assets -RestoreProof $restoreProof
[xml]$trx=Get-Content (Join-Path $ResultsDirectory 'commands.trx') -Raw
$expected=@('analog.multichannel-isolation','analog.multidevice-isolation')
foreach ($model in @('p','pd')) { foreach ($mode in @('pw','pa')) { foreach ($stage in @('single','multi')) { $expected+="modeled.$model.$mode.$stage" } } }
$results=@($trx.TestRun.Results.UnitTestResult)
if ($results.Count -ne 10 -or @(Compare-Object $expected @($results.testName) -CaseSensitive).Count -ne 0 -or @($results|Where-Object outcome -cne 'Passed').Count -ne 0) { throw 'Missing/duplicated/skipped/failed CLI command matrix.' }
