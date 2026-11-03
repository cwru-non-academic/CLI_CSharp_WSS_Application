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
$legacyMac=$false
if ($IsMacOS) {
    # Match the Integration capability contract; missing files alone cannot imply legacy support.
    $facade=[Reflection.Assembly]::LoadFrom((Join-Path (Split-Path $cliPath) 'WSS.Transport.BLE.dll'))
    $loader=$facade.GetType('Wss.Transports.Backends.BleBackendLoader',$true)
    $identity=$loader.GetMethod('GetBackendIdentity',[Reflection.BindingFlags]'NonPublic,Static')
    if (!$identity) { throw 'Unknown BLE facade capability contract.' }
    try {
        $mapping=$identity.Invoke($null,@('macos'))
        if ($mapping.Item1 -cne 'WSS.Transport.BLE.MacOS' -or $mapping.Item2 -cne 'Wss.Transports.Backends.MacOS.MacBleNusBackendFactory') { throw 'Unknown macOS backend mapping.' }
    } catch [Reflection.TargetInvocationException] {
        if ($_.Exception.InnerException -isnot [ArgumentOutOfRangeException] -or $_.Exception.InnerException.ParamName -cne 'platform') { throw }
        $legacyMac=$true
    }
    $macRoot=Join-Path (Split-Path $cliPath) 'backends/macos'
    $macFiles=@(if (Test-Path -LiteralPath $macRoot) { Get-ChildItem -LiteralPath $macRoot -File -Recurse })
    $expected=if ($legacyMac) { @() } else { @('WSS.Transport.BLE.MacOS.dll','libwss_macos_ble.dylib') }
    if ((@($macFiles | ForEach-Object { [IO.Path]::GetRelativePath($macRoot,$_.FullName) } | Sort-Object) -join ',') -cne (@($expected | Sort-Object) -join ',')) { throw 'macOS payload must match its declared backend capability.' }
}
$output=(& dotnet $cliPath --ble-smoke 2>&1) -join "`n"
if ($legacyMac) {
    if ($LASTEXITCODE -ne 1 -or $output -notmatch 'BLE construction failed' -or $output -notmatch 'not supported') { throw 'Legacy macOS BLE must fail explicitly as unsupported.' }
} elseif ($LASTEXITCODE -ne 0 -or $output -notmatch 'no scan, connection or writes') { throw 'BLE smoke must construct/dispose without entering live startup.' }
$null=& dotnet $cliPath --ble-smoke "--config=$sentinel" 2>&1
if ($LASTEXITCODE -ne 2 -or (Get-FileHash -LiteralPath $config).Hash -cne $hash -or @(Get-ChildItem -LiteralPath $sentinel -File).Count -ne 1) { throw 'BLE smoke must reject configuration/live options and preserve custom target 0x80.' }
$copy=Join-Path $Scratch 'missing-backend'
Copy-Item -LiteralPath (Split-Path $cliPath) -Destination $copy -Recurse
$platform=if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$assembly=if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
if (!$legacyMac) { Remove-Item -LiteralPath (Join-Path $copy "backends/$platform/WSS.Transport.BLE.$assembly.dll") }
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
if ($legacyMac) { Write-Output 'PASS: legacy macOS BLE explicitly unsupported; native BLE operation NOT EXECUTED.' }
Write-Output 'PASS: BLE capability smoke, missing/unsupported-backend failure, and custom 0x80 configuration preservation; no hardware.'
