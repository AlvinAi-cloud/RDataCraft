$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$bundled = Join-Path $PSScriptRoot 'runtime\R\bin\x64\Rscript.exe'
if (!(Test-Path -LiteralPath $bundled)) { $bundled = Join-Path $PSScriptRoot 'runtime\R\bin\Rscript.exe' }
$engine = $bundled
if (!(Test-Path -LiteralPath $engine)) {
    $rCommand = Get-Command Rscript.exe -ErrorAction SilentlyContinue
    if ($rCommand) { $engine = $rCommand.Source }
    else {
        $rKey = Get-ItemProperty 'HKLM:\SOFTWARE\R-core\R' -ErrorAction SilentlyContinue
        if (!$rKey) { $rKey = Get-ItemProperty 'HKCU:\SOFTWARE\R-core\R' -ErrorAction SilentlyContinue }
        if ($rKey) { $engine = Join-Path $rKey.InstallPath 'bin\Rscript.exe' }
    }
}
if (!(Test-Path -LiteralPath $engine)) { throw 'Install R 4.6 or use a portable RDataCraft Windows bundle containing runtime\R. See PLATFORM_SUPPORT.md.' }
$env:R_LIBS_USER = Join-Path $PSScriptRoot 'runtime\library'
$env:RDATACRAFT_RUNTIME = Join-Path $PSScriptRoot 'runtime'
$env:RDATACRAFT_PORTABLE = '1'
$env:R_USER_CACHE_DIR = Join-Path $env:TEMP 'RDataCraft\cache'
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'runtime\R')) {
    $env:RHOME = Join-Path $PSScriptRoot 'runtime\R'
    $env:R_HOME = $env:RHOME
} else {
    $env:RHOME = $null
    $env:R_HOME = $null
}
& $engine --vanilla scripts/portable.R @args
if ($LASTEXITCODE -ne 0) { throw "RDataCraft exited with code $LASTEXITCODE. See the console output above." }
