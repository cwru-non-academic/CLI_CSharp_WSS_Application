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
$argsList=@('test',$project,'-c','Release','-p:TreatWarningsAsErrors=true','-p:ImportDirectoryBuildProps=false','-p:ImportDirectoryBuildTargets=false','--logger','trx;LogFileName=commands.trx','--results-directory',$ResultsDirectory)
if ($env:WSS_ARTIFACT_DIR) { $argsList+="-p:WSS_ARTIFACT_DIR=$env:WSS_ARTIFACT_DIR" }
if ($env:WSS_BLE_ARTIFACT_DIR) { $argsList+="-p:WSS_BLE_ARTIFACT_DIR=$env:WSS_BLE_ARTIFACT_DIR" }
& dotnet @argsList
if ($LASTEXITCODE -ne 0) { throw 'Production CLI command conformance failed.' }
[xml]$trx=Get-Content (Join-Path $ResultsDirectory 'commands.trx') -Raw
$expected=@('analog.multichannel-isolation','analog.multidevice-isolation')
foreach ($model in @('p','pd')) { foreach ($mode in @('pw','pa')) { foreach ($stage in @('single','multi')) { $expected+="modeled.$model.$mode.$stage" } } }
$results=@($trx.TestRun.Results.UnitTestResult)
if ($results.Count -ne 10 -or @(Compare-Object $expected @($results.testName) -CaseSensitive).Count -ne 0 -or @($results|Where-Object outcome -cne 'Passed').Count -ne 0) { throw 'Missing/duplicated/skipped/failed CLI command matrix.' }
