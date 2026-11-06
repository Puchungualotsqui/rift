$ErrorActionPreference = "Stop"

$repository = "https://github.com/Theldus/wsServer.git"
$workDir = Join-Path ([IO.Path]::GetTempPath()) ("rift-wsserver-" + [guid]::NewGuid().ToString("N"))
$sourceDir = Join-Path $workDir "source"
$windowsBuildDir = Join-Path $workDir "build-windows"
$linuxBuildDir = Join-Path $workDir "build-linux"
$wsserverDir = Join-Path $PSScriptRoot "odin-wsserver"

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)] [string] $WindowsPath)

    $fullPath = [IO.Path]::GetFullPath($WindowsPath)
    if ($fullPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Expected a drive-qualified Windows path, got: $fullPath"
    }
    $drive = $matches[1].ToLowerInvariant()
    $relativePath = $matches[2] -replace '\\', '/'
    return "/mnt/$drive/$relativePath"
}

try {
    foreach ($tool in @("git.exe", "cmake.exe", "gcc.exe", "mingw32-make.exe", "wsl.exe")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required tool '$tool' was not found on PATH. Install Git, CMake, MSYS2 MinGW-w64 x64 tools, and WSL."
        }
    }

    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    & git.exe clone --depth 1 $repository $sourceDir
    if ($LASTEXITCODE -ne 0) {
        throw "Cloning wsServer failed (git exit code $LASTEXITCODE)."
    }

    # Build the Windows x64 static archive using the upstream-recommended
    # MinGW toolchain. The Odin binding names this archive libws.lib.
    & cmake.exe -S $sourceDir -B $windowsBuildDir -G "MinGW Makefiles" `
        -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) {
        throw "Windows CMake configuration failed."
    }
    & cmake.exe --build $windowsBuildDir --config Release --target ws --parallel
    if ($LASTEXITCODE -ne 0) {
        throw "Windows wsServer build failed."
    }

    $windowsArchive = Get-ChildItem -Path $windowsBuildDir -Filter "libws.a" -File -Recurse | Select-Object -First 1
    if (-not $windowsArchive) {
        throw "Windows build completed but libws.a was not found in its build directory."
    }
    Copy-Item $windowsArchive.FullName (Join-Path $wsserverDir "libws.lib") -Force

    # Build a native Linux x64 archive in WSL; Windows-produced objects cannot
    # be reused for the Linux target.
    $sourceWsl = Convert-ToWslPath $sourceDir
    $linuxBuildWsl = Convert-ToWslPath $linuxBuildDir
    $checkLinuxTools = "command -v cmake >/dev/null && command -v make >/dev/null && command -v gcc >/dev/null"
    & wsl.exe bash -lc $checkLinuxTools
    if ($LASTEXITCODE -ne 0) {
        throw "WSL needs cmake, make, and gcc installed (for Debian/Ubuntu: sudo apt install cmake build-essential)."
    }

    & wsl.exe cmake -S $sourceWsl -B $linuxBuildWsl -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) {
        throw "Linux CMake configuration failed in WSL."
    }
    & wsl.exe cmake --build $linuxBuildWsl --config Release --target ws --parallel
    if ($LASTEXITCODE -ne 0) {
        throw "Linux wsServer build failed in WSL."
    }

    $linuxArchive = Get-ChildItem -Path $linuxBuildDir -Filter "libws.a" -File -Recurse | Select-Object -First 1
    if (-not $linuxArchive) {
        throw "Linux build completed but libws.a was not found in its build directory."
    }
    Copy-Item $linuxArchive.FullName (Join-Path $wsserverDir "libws.a") -Force

    Write-Host "Ready: wsServer static libraries created in $wsserverDir"
    Write-Host "Windows x64: libws.lib"
    Write-Host "Linux x64:   libws.a"
} finally {
    if (Test-Path $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}
