$ErrorActionPreference = "Stop"

. "C:\BuildTools\devcmd.ps1"
& python (Join-Path $PSScriptRoot "tools\generate_assets.py")
if ($LASTEXITCODE -ne 0) {
    throw "Procedural asset generation failed with exit code $LASTEXITCODE."
}

Push-Location $PSScriptRoot
try {
    & odin.exe check . -vet
    if ($LASTEXITCODE -ne 0) {
        throw "Odin client check failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
