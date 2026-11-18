param(
    [ValidateRange(4, 512)]
    [int] $MaxClients = 32
)

$ErrorActionPreference = "Stop"

$sourceDir = Join-Path $PSScriptRoot "wsServer"
$workDir = Join-Path ([IO.Path]::GetTempPath()) ("rift-wsserver-build-" + [guid]::NewGuid().ToString("N"))
$windowsBuildDir = Join-Path $workDir "build-windows"
$linuxBuildDir = Join-Path $workDir "build-linux"
$wsserverDir = Join-Path $PSScriptRoot "odin-wsserver"
$serverDir = Join-Path $PSScriptRoot "server"
$serverDepsDir = Join-Path $serverDir "deps"

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
    if (-not (Test-Path (Join-Path $sourceDir "CMakeLists.txt"))) {
        throw "wsServer source is missing. Run 'git submodule update --init wsServer' from the repository root."
    }

    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue) -or
        -not (Get-Command lib.exe -ErrorAction SilentlyContinue)) {
        $devcmd = "C:\BuildTools\devcmd.ps1"
        if (Test-Path $devcmd) {
            . $devcmd
        }
    }

    foreach ($tool in @("cmake.exe", "gcc.exe", "mingw32-make.exe", "wsl.exe", "cl.exe", "lib.exe")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required tool '$tool' was not found. Install CMake, MSYS2 MinGW-w64 x64 tools, WSL, and the C++ Build Tools."
        }
    }

    New-Item -ItemType Directory -Force -Path $workDir, $serverDepsDir | Out-Null

    # wsServer's Windows build is a MinGW COFF archive, not an MSVC library.
    & cmake.exe -S $sourceDir -B $windowsBuildDir -G "MinGW Makefiles" `
        -DCMAKE_BUILD_TYPE=Release "-DCMAKE_C_FLAGS=-DMAX_CLIENTS=$MaxClients"
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

    # Link the pthread runtime as a DLL and provide small UCRT-compatible
    # replacements for MinGW-only CRT functions referenced by wsServer.
    $gccPath = (Get-Command gcc.exe).Source
    $mingwBin = Split-Path $gccPath -Parent
    $mingwRoot = Split-Path $mingwBin -Parent
    $winpthreadRuntime = Get-ChildItem -Path $mingwRoot -Filter "libwinpthread-1.dll" -File -Recurse | Select-Object -First 1
    if (-not $winpthreadRuntime) {
        throw "Could not find libwinpthread-1.dll under the MinGW installation at $mingwRoot."
    }
    Copy-Item $winpthreadRuntime.FullName (Join-Path $serverDir "libwinpthread-1.dll") -Force

    $winpthreadDef = Join-Path $workDir "libwinpthread.def"
    @"
LIBRARY libwinpthread-1.dll
EXPORTS
    clock_gettime64
    pthread_cond_destroy
    pthread_cond_init
    pthread_cond_signal
    pthread_cond_timedwait64
    pthread_create
    pthread_detach
    pthread_join
    pthread_mutex_destroy
    pthread_mutex_init
    pthread_mutex_lock
    pthread_mutex_unlock
"@ | Set-Content -Path $winpthreadDef -Encoding ascii
    $winpthreadLibrary = Join-Path $serverDepsDir "libwinpthread.lib"
    & lib.exe /nologo "/DEF:$winpthreadDef" /MACHINE:X64 "/OUT:$winpthreadLibrary"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create an MSVC import library for libwinpthread-1.dll."
    }

    $compatSource = Join-Path $serverDir "wsserver_msvc_compat.c"
    $compatObject = Join-Path $workDir "wsserver_msvc_compat.obj"
    $compatLibrary = Join-Path $serverDepsDir "libwscompat.lib"
    & cl.exe /nologo /c /O2 /MD "/Fo$compatObject" "/Tc$compatSource"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not compile the wsServer MSVC compatibility functions."
    }
    & lib.exe /nologo "/OUT:$compatLibrary" $compatObject
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the wsServer compatibility library."
    }

    # Build a native Linux x64 archive in WSL; Windows objects cannot be reused.
    $sourceWsl = Convert-ToWslPath $sourceDir
    $linuxBuildWsl = Convert-ToWslPath $linuxBuildDir
    $checkLinuxTools = "command -v cmake >/dev/null && command -v make >/dev/null && command -v gcc >/dev/null"
    & wsl.exe bash -lc $checkLinuxTools
    if ($LASTEXITCODE -ne 0) {
        throw "WSL needs cmake, make, and gcc installed (for Debian/Ubuntu: sudo apt install cmake build-essential)."
    }

    & wsl.exe cmake -S $sourceWsl -B $linuxBuildWsl -DCMAKE_BUILD_TYPE=Release "-DCMAKE_C_FLAGS=-DMAX_CLIENTS=$MaxClients"
    if ($LASTEXITCODE -ne 0) {
        throw "Linux CMake configuration failed in WSL."
    }
    & wsl.exe cmake --build $linuxBuildWsl --config Release --target ws --parallel
    if ($LASTEXITCODE -ne 0) {
        throw "Linux wsServer build failed."
    }

    $linuxArchive = Get-ChildItem -Path $linuxBuildDir -Filter "libws.a" -File -Recurse | Select-Object -First 1
    if (-not $linuxArchive) {
        throw "Linux build completed but libws.a was not found in its build directory."
    }
    Copy-Item $linuxArchive.FullName (Join-Path $wsserverDir "libws.a") -Force

    Write-Host "Ready: wsServer libraries built from the wsServer submodule."
    Write-Host "Windows: odin-wsserver/libws.lib plus server/deps MSVC import libraries"
    Write-Host "Linux:   odin-wsserver/libws.a"
    Write-Host "Maximum WebSocket clients per server: $MaxClients"
} finally {
    if (Test-Path $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}
