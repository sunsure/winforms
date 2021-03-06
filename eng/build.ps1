[CmdletBinding(PositionalBinding=$false)]
Param(
  [string][Alias('c')]$configuration = "Debug",
  [string] $projects,
  [string][Alias('v')]$verbosity = "minimal",
  [string] $msbuildEngine = $null,
  [bool] $warnAsError = $true,
  [bool] $nodeReuse = $true,
  [switch][Alias('r')]$restore,
  [switch] $deployDeps,
  [switch][Alias('b')]$build,
  [switch] $rebuild,
  [switch] $deploy,
  [switch] $test,
  [switch] $integrationTest,
  [switch] $performanceTest,
  [switch] $sign,
  [switch] $pack,
  [switch] $publish,
  [string][Alias('bl')]$binaryLog,
  [switch] $ci,
  [switch] $prepareMachine,
  [switch] $help,
  [Parameter(ValueFromRemainingArguments=$true)][String[]]$properties
)

. $PSScriptRoot\tools.ps1

function Print-Usage() {
    Write-Host "Common settings:"
    Write-Host "  -configuration <value>  Build configuration: 'Debug' or 'Release' (short: -c)"
    Write-Host "  -verbosity <value>      Msbuild verbosity: q[uiet], m[inimal], n[ormal], d[etailed], and diag[nostic] (short: -v)"
    Write-Host "  -binaryLog <value>      Output binary log; specify name of Binary Log in the form <value>.binlog (short: -bl)"
    Write-Host "  -help                   Print help and exit"
    Write-Host ""

    Write-Host "Actions:"
    Write-Host "  -restore                Restore dependencies (short: -r)"
    Write-Host "  -build                  Build solution (short: -b)"
    Write-Host "  -rebuild                Rebuild solution"
    Write-Host "  -deploy                 Deploy built VSIXes"
    Write-Host "  -deployDeps             Deploy dependencies (e.g. VSIXes for integration tests)"
    Write-Host "  -test                   Run all unit tests in the solution"
    Write-Host "  -pack                   Package build outputs into NuGet packages and Willow components"
    Write-Host "  -integrationTest        Run all integration tests in the solution"
    Write-Host "  -performanceTest        Run all performance tests in the solution"
    Write-Host "  -sign                   Sign build outputs"
    Write-Host "  -publish                Publish artifacts (e.g. symbols)"
    Write-Host ""

    Write-Host "Advanced settings:"
    Write-Host "  -projects <value>       Semi-colon delimited list of sln/proj's to build. Globbing is supported (*.sln)"
    Write-Host "  -ci                     Set when running on CI server"
    Write-Host "  -prepareMachine         Prepare machine for CI run"
    Write-Host "  -msbuildEngine <value>  Msbuild engine to use to run build ('dotnet', 'vs', or unspecified)."
    Write-Host ""
    Write-Host "Command line arguments not listed above are passed thru to msbuild."
    Write-Host "The above arguments can be shortened as much as to be unambiguous (e.g. -co for configuration, -t for test, etc.)."
}

function InitializeCustomToolset {
  if (-not $restore) {
    return
  }

  $script = Join-Path $EngRoot "restore-toolset.ps1"

  if (Test-Path $script) {
    . $script
  }
}

function Build {
  $toolsetBuildProj = InitializeToolset
  InitializeCustomToolset

  $bl = ""
  # if flag is present
  if ($null -ne $binaryLog)
  { 
    # if value is set, then use it; otherwise default to Build.binlog
    $binaryLogName = if ("" -eq $binaryLog) { "Build" } else { $binaryLog }
    $bl = "/bl:" + (Join-Path $LogDir ($binaryLogName + ".binlog")) 
  }

  if ($projects) {
    # Re-assign properties to a new variable because PowerShell doesn't let us append properties directly for unclear reasons.
    # Explicitly set the type as string[] because otherwise PowerShell would make this char[] if $properties is empty.
    [string[]] $msbuildArgs = $properties
    $msbuildArgs += "/p:Projects=$projects"
    $properties = $msbuildArgs
  }

  MSBuild $toolsetBuildProj `
    $bl `
    /p:Configuration=$configuration `
    /p:RepoRoot=$RepoRoot `
    /p:Restore=$restore `
    /p:DeployDeps=$deployDeps `
    /p:Build=$build `
    /p:Rebuild=$rebuild `
    /p:Deploy=$deploy `
    /p:Test=$test `
    /p:Pack=$pack `
    /p:IntegrationTest=$integrationTest `
    /p:PerformanceTest=$performanceTest `
    /p:Sign=$sign `
    /p:Publish=$publish `
    /p:ContinuousIntegrationBuild=$ci `
    @properties
}

try {
  if ($help -or (($null -ne $properties) -and ($properties.Contains("/help") -or $properties.Contains("/?")))) {
    Print-Usage
    exit 0
  }

  if ($ci) {
    # if binarylog value is given, do not overwrite it
    $binaryLog = if ($null -eq $binaryLog) { "" } else { $binaryLog }
    $nodeReuse = $false
  }

  # Import custom tools configuration, if present in the repo.
  # Note: Import in global scope so that the script set top-level variables without qualification.
  $configureToolsetScript = Join-Path $EngRoot "configure-toolset.ps1"
  if (Test-Path $configureToolsetScript) {
    . $configureToolsetScript
  }

  Build
}
catch {
  Write-Host $_
  Write-Host $_.Exception
  Write-Host $_.ScriptStackTrace
  ExitWithExitCode 1
}

ExitWithExitCode 0
