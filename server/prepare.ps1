function Prepare-OdinServer {
    param([Parameter(Mandatory = $true)] [string] $serverDir)

    $repoRoot = Split-Path $serverDir -Parent
    $devcmd = "C:\BuildTools\devcmd.ps1"
    if (Test-Path $devcmd) {
        . $devcmd
    }
    if (-not (Get-Command odin.exe -ErrorAction SilentlyContinue)) {
        throw "odin.exe was not found on PATH. Install Odin and make it available in the Build Tools environment."
    }

    if (-not (Test-Path (Join-Path $repoRoot "wsServerOdin\server.odin"))) {
        throw "The pure-Odin wsServerOdin package was not found in the repository."
    }
}
