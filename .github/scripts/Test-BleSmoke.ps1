param([Parameter(Mandatory)][string]$Cli,[Parameter(Mandatory)][string]$Scratch)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $Scratch) { throw 'BLE CLI regression scratch must be new.' }
$cliPath=(Resolve-Path -LiteralPath $Cli).Path
$null=New-Item -ItemType Directory -Path $Scratch
$sentinel=Join-Path $Scratch 'custom-config'
$null=New-Item -ItemType Directory -Path $sentinel
$config=Join-Path $sentinel 'stimConfig.json'
[IO.File]::WriteAllText($config,'{"wssTargets":["0x80"],"ownerSetting":"preserve"}')
$hash=(Get-FileHash -LiteralPath $config).Hash
$output=(& dotnet $cliPath --ble-smoke 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0 -or $output -notmatch 'no scan, connection or writes') { throw 'BLE smoke must construct/dispose without entering live startup.' }
$null=& dotnet $cliPath --ble-smoke "--config=$sentinel" 2>&1
if ($LASTEXITCODE -ne 2 -or (Get-FileHash -LiteralPath $config).Hash -cne $hash -or @(Get-ChildItem -LiteralPath $sentinel -File).Count -ne 1) { throw 'BLE smoke must reject configuration/live options and preserve custom target 0x80.' }
$copy=Join-Path $Scratch 'missing-backend'
Copy-Item -LiteralPath (Split-Path $cliPath) -Destination $copy -Recurse
$platform=if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$assembly=if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
Remove-Item -LiteralPath (Join-Path $copy "backends/$platform/WSS.Transport.BLE.$assembly.dll")
$output=(& dotnet (Join-Path $copy ([IO.Path]::GetFileName($cliPath))) --ble-smoke 2>&1) -join "`n"
if ($LASTEXITCODE -ne 1 -or $output -notmatch 'BLE construction failed') { throw 'Missing host BLE backend must fail, never report smoke success or fall back to hardware.' }
$outside=Join-Path $Scratch 'outside-checkout'
$null=New-Item -ItemType Directory -Path $outside
Push-Location $outside
try {
    $output=(& dotnet $cliPath --conformance 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'Result: PASS') { throw 'Published emulator conformance must work without a repository/config lookup.' }
} finally { Pop-Location }
if ((Get-FileHash -LiteralPath $config).Hash -cne $hash) { throw 'Emulator conformance changed the custom target configuration.' }
Write-Output 'PASS: disconnected BLE construction/disposal, missing-backend failure, and custom 0x80 configuration preservation; no hardware.'
