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

    $sourceDir = Join-Path $repoRoot "wsServer"
    if (-not (Test-Path (Join-Path $sourceDir "CMakeLists.txt"))) {
        if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
            throw "git.exe was not found; install Git to initialize the wsServer submodule."
        }
        & git.exe -C $repoRoot submodule update --init wsServer
        if ($LASTEXITCODE -ne 0) {
            throw "Could not initialize the wsServer submodule (git exit code $LASTEXITCODE)."
        }
    }

    $requiredFiles = @(
        (Join-Path $repoRoot "odin-wsserver\libws.lib"),
        (Join-Path $serverDir "deps\libwinpthread.lib"),
        (Join-Path $serverDir "deps\libwscompat.lib"),
        (Join-Path $serverDir "libwinpthread-1.dll")
    )
    $missingFiles = @($requiredFiles | Where-Object { -not (Test-Path $_) })
    if ($missingFiles.Count -gt 0) {
        $setupScript = Join-Path $repoRoot "wsserverSetup.ps1"
        & $setupScript
        if ($LASTEXITCODE -ne 0) {
            throw "wsserverSetup.ps1 failed (exit code $LASTEXITCODE)."
        }

        $missingFiles = @($requiredFiles | Where-Object { -not (Test-Path $_) })
        if ($missingFiles.Count -gt 0) {
            throw "WebSocket setup did not produce required files: $($missingFiles -join ', ')"
        }
    }
}
