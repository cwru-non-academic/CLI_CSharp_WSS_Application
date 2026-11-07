param([string]$ResultsDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('wss-cli-commands-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$project=Join-Path $PSScriptRoot '../../tests/Wss.Cli.Tests/Wss.Cli.Tests.csproj'
$argsList=@('test',$project,'-c','Release','-p:TreatWarningsAsErrors=true','--logger','trx;LogFileName=commands.trx','--results-directory',$ResultsDirectory)
if ($env:WSS_ARTIFACT_DIR) { $argsList+="-p:WSS_ARTIFACT_DIR=$env:WSS_ARTIFACT_DIR" }
if ($env:WSS_BLE_ARTIFACT_DIR) { $argsList+="-p:WSS_BLE_ARTIFACT_DIR=$env:WSS_BLE_ARTIFACT_DIR" }
& dotnet @argsList
if ($LASTEXITCODE -ne 0) { throw 'Production CLI command conformance failed.' }
[xml]$trx=Get-Content (Join-Path $ResultsDirectory 'commands.trx') -Raw
$expected=@('analog.multichannel-isolation','analog.multidevice-isolation')
foreach ($model in @('p','pd')) { foreach ($mode in @('pw','pa')) { foreach ($stage in @('single','multi')) { $expected+="modeled.$model.$mode.$stage" } } }
$results=@($trx.TestRun.Results.UnitTestResult)
if ($results.Count -ne 10 -or @(Compare-Object $expected @($results.testName) -CaseSensitive).Count -ne 0 -or @($results|Where-Object outcome -cne 'Passed').Count -ne 0) { throw 'Missing/duplicated/skipped/failed CLI command matrix.' }
