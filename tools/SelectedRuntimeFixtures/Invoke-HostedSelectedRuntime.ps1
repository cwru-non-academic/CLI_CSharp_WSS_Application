param([Parameter(Mandatory)][ValidateSet('Prepare','Run')][string]$Stage,[Parameter(Mandatory)][string]$FixtureRoot,[string]$BootstrapRoot=(Join-Path $PSScriptRoot '../..'),[string]$AdapterRoot='',[string]$TestSeedRoot='',[string]$VerifiedInputRoot='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$BootstrapRoot=[IO.Path]::GetFullPath($BootstrapRoot)
if(!$AdapterRoot){$AdapterRoot=$BootstrapRoot}
if(!$TestSeedRoot){$TestSeedRoot=$BootstrapRoot}
$AdapterRoot=[IO.Path]::GetFullPath($AdapterRoot)
$TestSeedRoot=[IO.Path]::GetFullPath($TestSeedRoot)
function Invoke-FixtureGit([string]$Root,[string[]]$Arguments){$result=& git -C $Root @Arguments;if($LASTEXITCODE -ne 0){throw 'Fixture git operation failed'};@($result)}
function Require([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
if($Stage -ceq 'Prepare'){
 Require (!(Test-Path -LiteralPath $FixtureRoot)) 'Fixture directory must be new.'
 $null=New-Item -ItemType Directory -Path $FixtureRoot
 if(!$IsWindows){Push-Location $FixtureRoot;try{$FixtureRoot=(& /bin/pwd -P).Trim()}finally{Pop-Location}}
 $FixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
 $product=Join-Path $FixtureRoot 'product';$tests=Join-Path $FixtureRoot 'selected-tests'
 $baselineTests=Join-Path $FixtureRoot 'baseline-cli-tests'
 $integration=Join-Path $FixtureRoot 'integration'
 $identity=Get-Content (Join-Path $VerifiedInputRoot 'integration-source.json') -Raw | ConvertFrom-Json
 Require ($identity.repository -ceq 'cwru-non-academic/CSharp_WSS_Integration_Lib' -and $identity.commit -cmatch '^[a-f0-9]{40}$') 'Invalid trusted fixture integration identity.'
 $null=Invoke-FixtureGit $BootstrapRoot @('clone','--quiet','--no-checkout',(Join-Path $VerifiedInputRoot 'integration.bundle'),$integration)
 $null=Invoke-FixtureGit $integration @('checkout','--quiet','--detach',$identity.commit)
 $integrationSha=(Invoke-FixtureGit $integration @('rev-parse','HEAD') -join '').Trim()
 Require ($integrationSha -ceq $identity.commit) 'Integration bundle checkout changed identity.'
 $sha=(Invoke-FixtureGit $BootstrapRoot @('rev-parse','HEAD') -join '').Trim()
 $seedSha=(Invoke-FixtureGit $TestSeedRoot @('rev-parse','HEAD') -join '').Trim()
 foreach($clone in @(@{source=$BootstrapRoot;target=$product;sha=$sha},@{source=$TestSeedRoot;target=$tests;sha=$seedSha},@{source=$BootstrapRoot;target=$baselineTests;sha=$sha})){
  $null=Invoke-FixtureGit $BootstrapRoot @('clone','--quiet','--no-hardlinks','--no-checkout',$clone.source,$clone.target)
  $null=Invoke-FixtureGit $clone.target @('checkout','--quiet','--detach',$clone.sha)
 }
 $contract=Get-Content (Join-Path $tests 'tests/test-contract.json') -Raw | ConvertFrom-Json
 Require ($contract.schema -ceq 'wss-csharp-tests/v1' -and $contract.role -ceq 'cli' -and $contract.test_directory -ceq 'tests/Wss.Cli.Tests') 'Unexpected fixture source directory.'
 $directory=Join-Path $tests $contract.test_directory
 $extra=@"
using System;
using System.IO;
using NUnit.Framework;
namespace Wss.Cli.Tests;
public sealed class HostedSelectedFixtureTests {
 [Test] public void SelectedOnlyFixtureChecksIsolationAndOptionalMutation() {
  foreach(var name in new[]{"GH_TOKEN","GITHUB_TOKEN","WSS_TEST_VARIABLE_READ_TOKEN","WSS_EVIDENCE_READ_TOKEN","GITHUB_ENV","GITHUB_OUTPUT","GITHUB_PATH","GITHUB_STATE"})
   Assert.That(Environment.GetEnvironmentVariable(name), Is.Null.Or.Empty, "Credential/command handle leaked: "+name);
  var target=Environment.GetEnvironmentVariable("WSS_FIXTURE_MUTATION_PATH");
  if(!string.IsNullOrEmpty(target)) File.AppendAllText(target, " ");
 }
}
"@
 [IO.File]::WriteAllText((Join-Path $directory 'HostedSelectedFixtureTests.cs'),$extra)
 [IO.File]::WriteAllText((Join-Path $tests 'src/Program.cs'),'INVALID SELECTED PRODUCT SOURCE MUST NEVER COMPILE')
 [IO.File]::WriteAllText((Join-Path $tests '.github/scripts/Invoke-CliCommandConformance.ps1'),"throw 'SELECTED VALIDATOR EXECUTED'")
 $poison='<Project><Target Name="Poison" BeforeTargets="PrepareForBuild;Build;VSTest"><Error Text="UNTRUSTED BUILD INPUT EXECUTED" /></Target></Project>'
 [IO.File]::WriteAllText((Join-Path $directory 'Wss.Cli.Tests.csproj'),$poison)
 foreach($base in @($tests,$directory,$FixtureRoot)){foreach($name in @('Directory.Build.props','Directory.Build.targets')){[IO.File]::WriteAllText((Join-Path $base $name),$poison)}}
 $null=Invoke-FixtureGit $tests @('add','--all')
 $null=Invoke-FixtureGit $tests @('-c','user.name=Synthetic Runtime Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','Synthetic runtime fixture, never acceptance evidence')
 $testSha=(Invoke-FixtureGit $tests @('rev-parse','HEAD') -join '').Trim()
 Require ($testSha -cne $sha) 'Selected fixture must differ from product.'
 $payload=Join-Path $FixtureRoot 'payload';Copy-Item -LiteralPath (Join-Path $VerifiedInputRoot 'extracted/WSS-Universal') -Destination $payload -Recurse
 @{candidate=(Get-Content (Join-Path $VerifiedInputRoot 'candidate.json') -Raw | ConvertFrom-Json)} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $payload 'wss-candidate.json')
 Require ((Get-FileHash (Join-Path $integration 'lib/WSS_Core_Interface.dll')).Hash -cne (Get-FileHash (Join-Path $payload 'WSS_Core_Interface.dll')).Hash) 'Collision regression requires different archived and authenticated candidate bytes.'
 @{schema='wss-synthetic-selected-runtime-fixture/v1';acceptance=$false;product_root=$product;product_sha=$sha;integration_root=$integration;integration_sha=$integrationSha;baseline_test_root=$baselineTests;test_root=$tests;test_sha=$testSha;test_seed_sha=$seedSha;payload_root=$payload;selection_id=('a'*64)} | ConvertTo-Json | Set-Content (Join-Path $FixtureRoot 'fixture.json')
 foreach($entry in @{WSS_FIXTURE_ROOT=$FixtureRoot;WSS_FIXTURE_PRODUCT=$product;WSS_FIXTURE_INTEGRATION=$integration;WSS_FIXTURE_PAYLOAD=$payload}.GetEnumerator()){
  Require ($entry.Value -notmatch '[\r\n]') 'Invalid fixture workflow path.'
  "$($entry.Key)=$($entry.Value)" | Add-Content -LiteralPath $env:GITHUB_ENV
 }
 return
}
$FixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
$state=Get-Content (Join-Path $FixtureRoot 'fixture.json') -Raw | ConvertFrom-Json
Require ($state.acceptance -eq $false) 'Only explicitly synthetic fixtures may run.'
$scripts=Join-Path $AdapterRoot '.github/scripts'
. "$scripts/SelectedProcessIsolation.ps1"
. "$scripts/CSharpProfilesBootstrap.ps1"
. "$scripts/CSharpTestSource.ps1"
. "$scripts/PreparedProfileProof.ps1"
. "$scripts/TrustedBaseline.ps1"
$profilePath=Join-Path $FixtureRoot 'profile/profile.json'
$proof=New-PreparedProfileProof $profilePath $state.payload_root $state.integration_root $state.integration_sha $true
$baseline=Join-Path $FixtureRoot 'baseline-results'
$names=@('GH_TOKEN','GITHUB_TOKEN','WSS_TEST_VARIABLE_READ_TOKEN','WSS_EVIDENCE_READ_TOKEN','GITHUB_ENV','GITHUB_OUTPUT','GITHUB_PATH','GITHUB_STATE');$prior=@{}
try{
 foreach($name in $names){$prior[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,'synthetic-parent-only')}
 Invoke-CredentialFreeSelectedPowerShell "$scripts/Invoke-ProfileFullTests.ps1" @{EvidencePath=$profilePath;ResultsDirectory=$baseline}
 Assert-PreparedProfileProof $proof
 & (Join-Path $state.integration_root '.github/scripts/Verify-WssOutput.ps1') -ArtifactRoot $state.payload_root -OutputRoot (Join-Path $proof.state.output_root 'Release/net9.0')
 $baselineRoots=@($proof.state.output_root,$baseline)
 $baselineSnapshot=New-TrustedBaselineSnapshot $baselineRoots
 function Assert-BaselineFiles {Assert-TrustedBaselineSnapshot $baselineSnapshot}
 function SelectedOptions([string]$Name){@{Role='cli';IntegrationRoot=$state.integration_root;IntegrationSha=$state.integration_sha;ProductRoot=$state.product_root;ProductSha=$state.product_sha;PayloadRoot=$state.payload_root;WorkRoot=(Join-Path $FixtureRoot $Name);TestRoot=$state.test_root;TestSha=$state.test_sha;TestRepository='cwru-non-academic/CLI_CSharp_WSS_Application';TestSelectionId=$state.selection_id;ProfileEvidencePath=$profilePath}}
 function Assert-SelectedResults([string]$Name){
  $root=Join-Path $FixtureRoot $Name
  Assert-CSharpFullTestResults (Join-Path $root 'commands/commands.trx')
  [xml]$trx=Get-Content (Join-Path $root 'commands/commands.trx') -Raw
  $extra=@($trx.TestRun.Results.UnitTestResult | Where-Object testName -ceq 'SelectedOnlyFixtureChecksIsolationAndOptionalMutation')
  Require ($extra.Count -eq 1 -and $extra[0].outcome -ceq 'Passed') 'Selected-only fixture was not executed exactly once.'
  $stages=@(Get-Content (Join-Path $baseline 'behavior/conformance-stages.json') -Raw | ConvertFrom-Json)
  Require ($stages.Count -eq 2 -and @($stages | Where-Object passed -ne 16).Count -eq 0) 'Mandatory modern16+16 missing.'
 }
 # Independent mandatory CLI baseline uses the immutable PRODUCT-owned tests,
 # not either separately selected bundle or its poisoned configuration.
 $trustedOptions=SelectedOptions 'baseline-cli'
 $baselineRoots+=@(Invoke-TrustedCliBaseline $trustedOptions (Join-Path $FixtureRoot 'baseline-cli'))
 $baselineSnapshot=New-TrustedBaselineSnapshot $baselineRoots
 Invoke-CredentialFreeSelectedPowerShell "$scripts/Invoke-SelectedCSharpTests.ps1" (SelectedOptions 'selected-success')
 Assert-SelectedResults 'selected-success';Assert-PreparedProfileProof $proof;Assert-BaselineFiles
 $success=Get-Content (Join-Path $FixtureRoot 'selected-success/test-source-evidence.json') -Raw | ConvertFrom-Json
 Require ($success.product_sha -ceq $state.product_sha -and $success.test_sha -ceq $state.test_sha -and $success.product_root -cne $success.test_root) 'Product/test identities became coupled.'
 foreach($case in @(@{name='reject-baseline-mutation';path=$proof.state.project;reason='*proof/source changed*'},@{name='reject-payload-mutation';path=(Join-Path $state.payload_root 'wss-candidate.json');reason='*payload changed*'})){
  $original=[IO.File]::ReadAllBytes($case.path)
  try{
   $env:WSS_FIXTURE_MUTATION_PATH=$case.path;$rejected=$false
   try{Invoke-CredentialFreeSelectedPowerShell "$scripts/Invoke-SelectedCSharpTests.ps1" (SelectedOptions $case.name)}catch{$rejected=$true}
   Require $rejected 'Mutating selected suite was accepted.';Assert-SelectedResults $case.name
   Require (!(Test-Path (Join-Path $FixtureRoot "$($case.name)/test-source-evidence.json"))) 'Rejected fixture emitted success evidence.'
   $parentRejected=$false
   try{Assert-PreparedProfileProof $proof}catch{if($_.Exception.Message -notlike $case.reason){throw};$parentRejected=$true}
   Require $parentRejected 'Parent failed to detect selected mutation.'
  }finally{Remove-Item Env:WSS_FIXTURE_MUTATION_PATH -ErrorAction SilentlyContinue;[IO.File]::WriteAllBytes($case.path,$original)}
  Assert-PreparedProfileProof $proof;Assert-BaselineFiles
 }
 # The child can add an evidence file without altering existing hashes. The parent
 # inventory guard must reject it even when the selected test runner succeeds.
 $added=Join-Path $baseline 'selected-added-evidence.json'
 try{
  $env:WSS_FIXTURE_MUTATION_PATH=$added
  Invoke-CredentialFreeSelectedPowerShell "$scripts/Invoke-SelectedCSharpTests.ps1" (SelectedOptions 'reject-baseline-addition')
  Assert-SelectedResults 'reject-baseline-addition'
  $rejected=$false
  try{Assert-BaselineFiles}catch{if($_.Exception.Message -notlike '*baseline inventory/content*'){throw};$rejected=$true}
  Require $rejected 'Parent accepted selected-added baseline evidence.'
 }finally{Remove-Item Env:WSS_FIXTURE_MUTATION_PATH -ErrorAction SilentlyContinue;if(Test-Path -LiteralPath $added){Remove-Item -LiteralPath $added}}
 Assert-BaselineFiles
 foreach($name in $names){Require ([Environment]::GetEnvironmentVariable($name) -ceq 'synthetic-parent-only') 'Child modified parent credential fixture.'}
 Assert-TestBundleCheckout $state.product_root $state.product_sha
 Assert-TestBundleCheckout $state.test_root $state.test_sha
 Assert-TestBundleCheckout $state.integration_root $state.integration_sha
 Assert-TestBundleCheckout $state.baseline_test_root $state.product_sha
 Require (@(Get-ChildItem $FixtureRoot -Recurse -Filter evidence.json | Where-Object FullName -match '[/\\]selection[/\\]').Count -eq 0) 'Synthetic fixture emitted generic selection evidence.'
 @{schema='wss-synthetic-selected-runtime-result/v1';acceptance=$false;product_sha=$state.product_sha;test_sha=$state.test_sha;test_seed_sha=$state.test_seed_sha;mandatory_stages='16+16';mandatory_cli=10;selected_only_test=$true;baseline_mutation_rejected=$true;baseline_addition_rejected=$true;payload_mutation_rejected=$true;credential_isolation=$true;passed=$true} | ConvertTo-Json | Set-Content (Join-Path $FixtureRoot 'synthetic-result.json')
}finally{foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$prior[$name])}}
