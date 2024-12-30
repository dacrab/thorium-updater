# Thorium Browser Updater
#
# Script to automatically update Thorium Browser installations
# Requires admin privileges and handles multiple installation types

#region Setup

# Auto-elevate if not running as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Initialize constants
$Host.UI.RawUI.WindowTitle = "Thorium Browser Updater"
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$tempDir = "$env:TEMP\ThoriumUpdater"
$releaseApi = "https://api.github.com/repos/Alex313031/Thorium-Win/releases"

#region Helper Functions
function Write-Section($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Status($text) { Write-Host $text -ForegroundColor Yellow }
function Write-Success($text) { Write-Host $text -ForegroundColor Green }
function Write-Error($text) { Write-Host $text -ForegroundColor Red }
#endregion

#region Search Paths
# Registry search paths
$THORIUM_REG_PATHS = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\thorium.exe",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# Common installation directories
$THORIUM_SEARCH_PATHS = @(
    "${env:ProgramFiles}\Thorium",
    "${env:ProgramFiles(x86)}\Thorium",
    "${env:LocalAppData}\Thorium",
    "${env:ProgramFiles}\Thorium Browser",
    "${env:ProgramFiles(x86)}\Thorium Browser",
    "${env:LocalAppData}\Thorium Browser",
    "${env:LocalAppData}\Programs\Thorium",
    "${env:LocalAppData}\Programs\Thorium Browser",
    [Environment]::GetFolderPath('Desktop')
)

# Recursive search roots
$THORIUM_SEARCH_ROOTS = @(
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)},
    $env:LocalAppData,
    "$env:LocalAppData\Programs"
)
#endregion

#endregion

#region Installation Detection Functions

function Get-ThoriumFromRegistry {
    foreach ($regPath in $THORIUM_REG_PATHS) {
        if (-not (Test-Path $regPath)) { continue }
        
        $thoriumReg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Thorium*" -or $_.Path -like "*Thorium*" }
        
        if (-not $thoriumReg) { continue }
        
        $exePath = if ($thoriumReg.InstallLocation) {
            Join-Path $thoriumReg.InstallLocation "thorium.exe"
        } elseif ($thoriumReg.Path) {
            $thoriumReg.Path
        } elseif ($thoriumReg.'(Default)') {
            $thoriumReg.'(Default)'
        }

        if ($exePath -and (Test-Path $exePath)) {
            Write-Verbose "Found Thorium in registry: $exePath"
            return $exePath
        }
    }
    return $null
}

function Get-ThoriumFromFileSystem {
    $searchPaths = $THORIUM_SEARCH_PATHS.Clone()
    
    # Add paths from recursive search
    foreach ($root in $THORIUM_SEARCH_ROOTS) {
        if (Test-Path $root) {
            $searchPaths += Get-ChildItem -Path $root -Recurse -Filter "thorium.exe" -ErrorAction SilentlyContinue |
                ForEach-Object { Split-Path -Parent $_.FullName }
        }
    }

    $searchPaths = $searchPaths | Select-Object -Unique
    
    foreach ($basePath in $searchPaths) {
        $possiblePaths = @(
            (Join-Path $basePath "thorium.exe"),
            (Join-Path $basePath "Thorium\thorium.exe"),
            (Join-Path $basePath "Thorium Browser\thorium.exe")
        )
        
        $found = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) { return $found }
    }
    return $null
}

function Get-ThoriumArchitecture($exePath) {
    $content = [System.IO.File]::ReadAllBytes($exePath)
    $contentStr = [System.Text.Encoding]::ASCII.GetString($content)
    
    if ($contentStr -match "avx2") { return "AVX2" }
    if ($contentStr -match "sse4") { return "SSE4" }
    return "SSE3"
}

function Get-ThoriumInstall {
    Write-Section "Locating Thorium Installation"
    
    $exePath = Get-ThoriumFromRegistry
    if (-not $exePath) {
        $exePath = Get-ThoriumFromFileSystem
    }
    
    if (-not $exePath -or -not (Test-Path $exePath)) {
        Write-Error "No Thorium installation found!"
        return $null
    }
    
    try {
        $fileInfo = Get-Item $exePath
        $version = $fileInfo.VersionInfo.FileVersion
        $arch = Get-ThoriumArchitecture $exePath
        
        Write-Success "Found Thorium installation:"
        Write-Host "Path: $exePath" -ForegroundColor Gray
        Write-Host "Version: $version" -ForegroundColor Gray
        Write-Host "Architecture: $arch" -ForegroundColor Gray
        
        return @{
            Version = $version
            Path = $exePath
            Architecture = $arch
        }
    }
    catch {
        Write-Error "Error reading executable: $_"
        return $null
    }
}

#endregion

#region Update Functions

function Get-LatestVersion {
    try {
        $releases = Invoke-RestMethod -Uri $releaseApi
        return $releases[0]
    }
    catch {
        throw "Failed to check for updates: $_"
    }
}

function Update-Thorium {
    param($current, $release)
    
    Write-Section "Updating Thorium Browser"
    
    # Create temp directory and find matching installer
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $pattern = "thorium.*$($current.Architecture.ToLower()).*\.exe$"
    $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    
    if (-not $asset) {
        throw "No compatible update found for $($current.Architecture)"
    }
    
    # Download and install
    $installerPath = Join-Path $tempDir $asset.name
    Write-Status "Downloading update..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath
    
    Write-Status "Installing update..."
    Get-Process | Where-Object { $_.ProcessName -like "*thorium*" } | Stop-Process -Force
    Start-Process -FilePath $installerPath -Wait
    
    Write-Success "Update complete!"
}

function Compare-ThoriumVersions {
    param ([string]$CurrentVersion, [string]$LatestVersion)
    
    $currentClean = $CurrentVersion -replace '^M' -replace '[^0-9.]'
    $latestClean = $LatestVersion -replace '^M' -replace '[^0-9.]'
    
    try {
        return [version]$currentClean -ge [version]$latestClean
    }
    catch {
        Write-Verbose "Version parsing failed, using string comparison"
        return $CurrentVersion -eq $LatestVersion
    }
}

#endregion

#region Main Execution

try {
    Write-Section "Thorium Browser Updater"
    
    $current = Get-ThoriumInstall
    if (-not $current) {
        Write-Error "Please install Thorium Browser first!"
        exit 1
    }
    
    Write-Status "Checking for updates..."
    $latest = Get-LatestVersion
    
    Write-Host "Current version: " -NoNewline
    Write-Host $current.Version -ForegroundColor Cyan
    Write-Host "Latest version:  " -NoNewline
    Write-Host $latest.tag_name -ForegroundColor Cyan
    
    if (Compare-ThoriumVersions -CurrentVersion $current.Version -LatestVersion $latest.tag_name) {
        Write-Success "`nYou have the latest version installed!"
        exit 0
    }
    
    Write-Host "`nUpdate available!" -ForegroundColor Yellow
    Write-Host "Would you like to update? (Y/N) [Y]: " -NoNewline
    $response = Read-Host
    if ($response -eq "N") { exit 0 }
    
    Update-Thorium -current $current -release $latest
}
catch {
    Write-Error "Error: $_"
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

#endregion
