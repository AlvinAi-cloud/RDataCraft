param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = (Get-Content (Join-Path $root 'config/release.json') -Raw | ConvertFrom-Json).version
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RDataCraft-installer-test-' + [guid]::NewGuid().ToString('N'))
$installPath = Join-Path $testRoot 'installed'
$reportDirectory = Join-Path $root 'artifacts'
New-Item -ItemType Directory -Path $testRoot,$reportDirectory -Force | Out-Null
try {
  # NSIS requires /D last, without additional quoting, even when its path has spaces.
  $setup = Start-Process -FilePath (Resolve-Path $Installer) -ArgumentList @('/S',"/D=$installPath") -PassThru -Wait
  if ($setup.ExitCode -ne 0) { throw 'Silent installation failed.' }
  $metadata = Get-Content (Join-Path $installPath 'build-platform.json') -Raw | ConvertFrom-Json
  if ($metadata.version -ne $version) { throw 'Installed version differs from the source checkout.' }
  $engine = Join-Path $installPath 'runtime/R/bin/x64/Rscript.exe'
  if (!(Test-Path $engine)) { $engine = Join-Path $installPath 'runtime/R/bin/Rscript.exe' }
  if (!(Test-Path $engine)) { throw 'The installed bundled R engine is missing.' }
  $native = Join-Path $installPath 'RDataCraft.exe'
  if (!(Test-Path $native)) { throw 'The native Windows executable is missing.' }
  $nativeReports = Join-Path $reportDirectory 'installed-windows-native'
  $test = Start-Process -FilePath $native -ArgumentList ('--native-test="' + $nativeReports + '"') -PassThru
  if (!$test.WaitForExit(420000)) { $test.Kill(); throw 'The native Windows workflow tests timed out.' }
  if ($test.ExitCode -ne 0) { throw 'The native Windows workflow tests failed; inspect installed-windows-native reports.' }
  $nativeReport = Get-Content (Join-Path $nativeReports 'validation-windows-desktop.json') -Raw | ConvertFrom-Json
  if ($nativeReport.status -ne 'passed') { throw 'Native Windows validation did not pass.' }
  if (Get-Process -Id $nativeReport.engine_pid -ErrorAction SilentlyContinue) { throw 'The native app left its R engine running.' }
  Push-Location $installPath
  try {
    $env:R_LIBS_USER = Join-Path $installPath 'runtime/library'
    $env:R_HOME = Join-Path $installPath 'runtime/R'
    $env:RHOME = $env:R_HOME
    $env:R_LIBS_SITE = ''
    $env:R_LIBS = ''
    & (Join-Path $installPath 'Validate RDataCraft.cmd') --no-pause
    if ($LASTEXITCODE -ne 0) { throw 'Installed R workflow tests failed.' }
  } finally { Pop-Location }
  Copy-Item (Join-Path $installPath "artifacts/validation-native-$version.json") (Join-Path $reportDirectory "validation-installed-windows-$version.json")
  $sentinel = Join-Path $installPath 'keep-study.rdatacraft'
  Set-Content -LiteralPath $sentinel -Value '{"original_test_study":true}'
  $uninstall = Start-Process -FilePath (Join-Path $installPath 'Uninstall.exe') -ArgumentList @('/S',"_?=$installPath") -PassThru -Wait
  if ($uninstall.ExitCode -ne 0 -or !(Test-Path $sentinel)) { throw 'Uninstallation did not preserve the extra study.' }
  if (Test-Path $engine) { throw 'Uninstallation left the bundled runtime behind.' }
  @{version=$version;status='passed';installed_R_tests=$true;extra_study_preserved=$true;native_window_tested=$true;native_checks=$nativeReport.checks.Count;engine_cleanup_verified=$true} |
    ConvertTo-Json | Set-Content (Join-Path $reportDirectory "validation-windows-installer-$version.json")
} finally {
  # This unique fixture directory contains no user-provided study.
  if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
