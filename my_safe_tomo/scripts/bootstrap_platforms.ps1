$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root
try {
    $Seed = Join-Path $Root '_platform_seed'
    if ((Test-Path (Join-Path $Root 'android')) -or (Test-Path (Join-Path $Root 'ios'))) {
        Write-Host 'Android or iOS folder already exists. Skipping platform generation to avoid overwriting it.'
        exit 0
    }
    flutter create --empty --platforms=android,ios --org com.mysafetomo --project-name my_safe_tomo $Seed
    Copy-Item (Join-Path $Seed 'android') (Join-Path $Root 'android') -Recurse
    Copy-Item (Join-Path $Seed 'ios') (Join-Path $Root 'ios') -Recurse
    Remove-Item $Seed -Recurse -Force
    Write-Host 'Created Android and iOS runner folders. Now follow README.md for permission strings and FlutterFire setup.'
} finally {
    Pop-Location
}
