$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "build.ps1")

Push-Location $PSScriptRoot
try {
    & (Join-Path $PSScriptRoot "server.exe") @args
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

exit $exitCode
