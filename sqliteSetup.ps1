$ErrorActionPreference = "Stop"

$sqliteVersion = "3540100"
$downloadRoot = "https://www.sqlite.org/2026"
$sqliteDir = Join-Path $PSScriptRoot "odin-sqlite3"
$downloadDir = Join-Path $env:TEMP "rift-sqlite-$sqliteVersion"
$sourceDir = Join-Path $sqliteDir "vendor\source-$sqliteVersion"

New-Item -ItemType Directory -Force -Path $sqliteDir, $downloadDir, $sourceDir | Out-Null

$archiveName = "sqlite-amalgamation-$sqliteVersion.zip"
$archivePath = Join-Path $downloadDir $archiveName
$extractDir = Join-Path $downloadDir "sqlite-amalgamation-$sqliteVersion"

if (-not (Test-Path $archivePath)) {
    Invoke-WebRequest -Uri "$downloadRoot/$archiveName" -OutFile $archivePath
}
if (Test-Path $extractDir) {
    Remove-Item -Recurse -Force $extractDir
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir -Force

$amalgamation = Get-ChildItem -Path $extractDir -Filter "sqlite3.c" -File -Recurse | Select-Object -First 1
if (-not $amalgamation) {
    throw "Could not find sqlite3.c in the SQLite amalgamation archive."
}
$header = Join-Path $amalgamation.DirectoryName "sqlite3.h"
if (-not (Test-Path $header)) {
    throw "Could not find sqlite3.h alongside sqlite3.c."
}
Copy-Item $amalgamation.FullName (Join-Path $sourceDir "sqlite3.c") -Force
Copy-Item $header (Join-Path $sourceDir "sqlite3.h") -Force

$source = Join-Path $sourceDir "sqlite3.c"

# Build the Windows x64 static library with the Visual Studio C toolchain.
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue) -or
    -not (Get-Command lib.exe -ErrorAction SilentlyContinue)) {
    throw "Windows static build requires Visual Studio C++ Build Tools (x64 Native Tools command prompt), with cl.exe and lib.exe on PATH."
}
$windowsObject = Join-Path $downloadDir "sqlite3-windows-x64.obj"
$windowsLibrary = Join-Path $sqliteDir "libsqlite3.lib"
& cl.exe /nologo /O2 /c /DSQLITE_THREADSAFE=1 "/Fo$windowsObject" $source
if ($LASTEXITCODE -ne 0) {
    throw "Compiling SQLite for Windows failed (cl.exe exit code $LASTEXITCODE)."
}
& lib.exe /nologo "/OUT:$windowsLibrary" $windowsObject
if ($LASTEXITCODE -ne 0) {
    throw "Creating the Windows static library failed (lib.exe exit code $LASTEXITCODE)."
}

# Build the Linux x64 static library through WSL so the archive contains Linux
# machine code rather than a Windows object file. WSL must have gcc and ar.
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "Linux static build requires WSL with a Linux distribution installed, plus gcc and ar."
}
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

$sourceWsl = Convert-ToWslPath $source
$objectWsl = "$sourceWsl.linux-x64.o"
$libraryWsl = (Convert-ToWslPath $sqliteDir) + "/libsqlite3.a"
& wsl.exe gcc -O2 -fPIC -DSQLITE_THREADSAFE=1 -c $sourceWsl -o $objectWsl
if ($LASTEXITCODE -ne 0) {
    throw "Compiling SQLite for Linux failed. Ensure WSL has gcc installed."
}
& wsl.exe ar rcs $libraryWsl $objectWsl
if ($LASTEXITCODE -ne 0) {
    throw "Creating the Linux static library failed. Ensure WSL has ar installed."
}

$vendorDir = Join-Path $sqliteDir "vendor"
if (Test-Path $vendorDir) {
    Remove-Item -LiteralPath $vendorDir -Recurse -Force
}

Write-Host "Ready: static SQLite libraries created in $sqliteDir"
Write-Host "Windows x64: libsqlite3.lib"
Write-Host "Linux x64:   libsqlite3.a"
Write-Host "Build each target with the default static-link settings (do not set SQLITE3_DYNAMIC_LIB or SQLITE3_SYSTEM_LIB)."
