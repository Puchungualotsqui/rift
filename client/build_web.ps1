$ErrorActionPreference = "Stop"

. "C:\BuildTools\devcmd.ps1"
& python (Join-Path $PSScriptRoot "tools\generate_assets.py")
if ($LASTEXITCODE -ne 0) {
    throw "Procedural asset generation failed with exit code $LASTEXITCODE."
}

$repoRoot = Split-Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
    	& odin.exe run karl2d/build_web -- client
    if ($LASTEXITCODE -ne 0) {
        throw "Odin web client build failed with exit code $LASTEXITCODE."
    }
} finally {
    Remove-Item (Join-Path $repoRoot "build_web.exe") -ErrorAction SilentlyContinue
    Pop-Location
}
