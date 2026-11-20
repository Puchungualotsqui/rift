$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "prepare.ps1")
Prepare-OdinServer -serverDir $PSScriptRoot

Push-Location $PSScriptRoot
try {
    & odin.exe build . -vet -out:server.exe
    if ($LASTEXITCODE -ne 0) {
        throw "odin build failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
