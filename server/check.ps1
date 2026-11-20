$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "prepare.ps1")
Prepare-OdinServer -serverDir $PSScriptRoot

Push-Location $PSScriptRoot
try {
    & odin.exe check . -vet
    if ($LASTEXITCODE -ne 0) {
        throw "odin check failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
