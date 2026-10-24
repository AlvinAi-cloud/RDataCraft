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
  Push-Location $installPath
  try {
    $env:R_LIBS_USER = Join-Path $installPath 'runtime/library'
    & $engine --vanilla scripts/validate.R
    if ($LASTEXITCODE -ne 0) { throw 'Installed R workflow tests failed.' }
  } finally { Pop-Location }
  Copy-Item (Join-Path $installPath "artifacts/validation-native-$version.json") (Join-Path $reportDirectory "validation-installed-windows-$version.json")
  $sentinel = Join-Path $installPath 'keep-study.rdatacraft'
  Set-Content -LiteralPath $sentinel -Value '{"original_test_study":true}'
  $uninstall = Start-Process -FilePath (Join-Path $installPath 'Uninstall.exe') -ArgumentList @('/S',"_?=$installPath") -PassThru -Wait
  if ($uninstall.ExitCode -ne 0 -or !(Test-Path $sentinel)) { throw 'Uninstallation did not preserve the extra study.' }
  if (Test-Path $engine) { throw 'Uninstallation left the bundled runtime behind.' }
  @{version=$version;status='passed';installed_R_tests=$true;extra_study_preserved=$true;interactive_browser_tested=$false} |
    ConvertTo-Json | Set-Content (Join-Path $reportDirectory "validation-windows-installer-$version.json")
} finally {
  # This unique fixture directory contains no user-provided study.
  if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
