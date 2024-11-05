#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installer/Updater script for Thorium Browser on Windows
.DESCRIPTION
    Automatically installs or updates Thorium Browser based on CPU architecture.
    Handles elevation, installation detection, version comparison, and cleanup.
.NOTES
    Requires administrative privileges
    Supports AVX2, SSE4, and SSE3 CPU architectures
#>

# Self-elevate if not running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting administrative privileges..." -ForegroundColor Yellow
    $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
    Start-Process -FilePath PowerShell.exe -Verb RunAs -ArgumentList $CommandLine
    exit
}

#region Installation Detection Functions

<#
.SYNOPSIS
    Locates installed Thorium Browser instance
.DESCRIPTION
    Searches common installation paths, registry locations, and file system
    for Thorium Browser installation
.OUTPUTS
    PSCustomObject with Version, IsAVX2, and Path properties if found, null otherwise
#>
function Get-InstalledThorium {
    # Define all possible installation locations
    $thoriumPaths = @(
        "${env:ProgramFiles}\Thorium",
        "${env:ProgramFiles}\Thorium Browser", 
        "${env:ProgramFiles(x86)}\Thorium",
        "${env:ProgramFiles(x86)}\Thorium Browser",
        "${env:LocalAppData}\Thorium",
        "${env:LocalAppData}\Programs\Thorium",
        "${env:LocalAppData}\Programs\Thorium Browser"
    )

    Write-Host "Searching for Thorium installation..." -ForegroundColor Cyan
    Write-Verbose "Checking registry for Thorium installation..."

    # Search registry locations
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\thorium.exe",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    # Add registry paths to search locations
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $thoriumReg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -like "*Thorium*" -or $_.Path -like "*Thorium*" }
            
            if ($thoriumReg) {
                $possiblePath = if ($thoriumReg.InstallLocation) { 
                    $thoriumReg.InstallLocation 
                } elseif ($thoriumReg.Path) {
                    Split-Path -Parent $thoriumReg.Path
                }
                
                if ($possiblePath) {
                    $thoriumPaths += $possiblePath
                }
            }
        }
    }

    # Search Program Files and AppData locations
    Write-Verbose "Searching in Program Files directories..."
    $searchPaths = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LocalAppData,
        "$env:LocalAppData\Programs"
    )

    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            $thoriumPaths += Get-ChildItem -Path $searchPath -Recurse -Filter "thorium.exe" -ErrorAction SilentlyContinue |
                ForEach-Object { Split-Path -Parent $_.FullName }
        }
    }

    # Remove duplicates and empty entries
    $thoriumPaths = $thoriumPaths | Select-Object -Unique | Where-Object { $_ }
    
    # Search each path for thorium.exe
    foreach ($thoriumPath in $thoriumPaths) {
        Write-Verbose "Checking path: $thoriumPath"
        
        $exeFiles = Get-ChildItem -Path $thoriumPath -Filter "thorium.exe" -Recurse -Depth 1 -ErrorAction SilentlyContinue
        
        foreach ($exeFile in $exeFiles) {
            $exePath = $exeFile.FullName
            Write-Verbose "Found potential Thorium executable: $exePath"
            
            if (Test-Path $exePath) {
                Write-Verbose "Executable exists at: $exePath"
                try {
                    $fileInfo = Get-Item $exePath
                    $fileVersion = $fileInfo.VersionInfo.FileVersion
                    
                    if ($fileVersion) {
                        # Check for AVX2 support
                        $isAVX2 = try {
                            Select-String -Path $exePath -Pattern "avx2" -Quiet
                        } catch {
                            $false
                        }
                        
                        Write-Host "Found Thorium installation:" -ForegroundColor Green
                        Write-Host "Path: $exePath" -ForegroundColor Gray
                        Write-Host "Version: $fileVersion" -ForegroundColor Gray
                        
                        return @{
                            Version = $fileVersion
                            IsAVX2 = $isAVX2
                            Path = $exePath
                        }
                    }
                } catch {
                    Write-Verbose "Error reading file info: $_"
                    continue
                }
            }
        }
    }
    
    return $null
}

#region Uninstallation Functions

<#
.SYNOPSIS
    Removes existing Thorium Browser installation
.DESCRIPTION
    Uses Windows Installer to remove any existing Thorium Browser installations
#>
function Uninstall-Thorium {
    Write-Host "Removing old Thorium installation..." -ForegroundColor Cyan
    
    $thoriumApps = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "*Thorium*" }
    
    if ($thoriumApps) {
        foreach ($app in $thoriumApps) {
            Write-Host "Uninstalling $($app.Name)..." -ForegroundColor Yellow
            $null = $app | Invoke-CimMethod -MethodName Uninstall
        }
    }
}

#region Version Management Functions

<#
.SYNOPSIS
    Retrieves available Thorium Browser versions
.DESCRIPTION
    Queries GitHub API for Thorium Browser releases
.OUTPUTS
    Array of PSCustomObjects containing Version, Date, and Assets
#>
function Get-ThoriumVersions {
    $maxRetries = 3
    $retryCount = 0
    $releaseUrl = "https://api.github.com/repos/Alex313031/Thorium-Win/releases"
    
    while ($retryCount -lt $maxRetries) {
        try {
            $releases = Invoke-RestMethod -Uri $releaseUrl
            return $releases | ForEach-Object {
                [PSCustomObject]@{
                    Version = $_.tag_name
                    Date = $_.published_at
                    Assets = $_.assets
                }
            }
        } catch {
            $retryCount++
            if ($retryCount -eq $maxRetries) {
                throw "Failed to get latest version after $maxRetries attempts"
            }
            Start-Sleep -Seconds 2
        }
    }
}

#region CPU Architecture Detection

<#
.SYNOPSIS
    Detects CPU architecture and capabilities
.DESCRIPTION
    Checks for AVX2, SSE4, and SSE3 support
.OUTPUTS
    String indicating supported architecture level
#>
function Get-CPUArchitecture {
    Write-Host "Detecting CPU capabilities..." -ForegroundColor Cyan

    try {
        $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
        $cpuFeatures = Get-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" -ErrorAction SilentlyContinue
        
        # Check for AVX2 support
        if ($cpuFeatures.ProcessorNameString -match "AVX2" -or $cpu.Name -match "AVX2") {
            Write-Host "AVX2 support detected" -ForegroundColor Green
            return "AVX2"
        }
        
        # Check for SSE4 support
        if ($cpuFeatures.ProcessorNameString -match "SSE4" -or $cpu.Name -match "SSE4") {
            Write-Host "SSE4 support detected" -ForegroundColor Green
            return "SSE4"
        }
        
        # Check for SSE3 support
        if ($cpuFeatures.ProcessorNameString -match "SSE3" -or $cpu.Name -match "SSE3") {
            Write-Host "SSE3 support detected" -ForegroundColor Green
            return "SSE3"
        }

        Write-Host "Error: Unsupported CPU architecture" -ForegroundColor Red
        throw "Unsupported CPU architecture"
        
    } catch {
        Write-Host "Error detecting CPU architecture: $_" -ForegroundColor Red
        throw "Failed to detect CPU architecture"
    }
}

<#
.SYNOPSIS
    Gets appropriate Thorium installer asset for CPU architecture
.PARAMETER LatestVersion
    PSCustomObject containing release information
.OUTPUTS
    Asset object containing download information
#>
function Get-ThoriumAsset {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$LatestVersion
    )

    $cpuArch = Get-CPUArchitecture

    $patterns = switch ($cpuArch) {
        "AVX2" { "thorium.*avx2.*\.exe$" }
        "SSE4" { "thorium.*sse4.*\.exe$" }
        "SSE3" { "thorium.*sse3.*\.exe$" }
        default {
            Write-Host "Unsupported CPU architecture detected" -ForegroundColor Red
            return $null
        }
    }

    $asset = $LatestVersion.Assets | Where-Object { $_.name -match $patterns } | Select-Object -First 1
    if ($asset) {
        return $asset
    }

    Write-Host "No suitable installer found for CPU architecture: $cpuArch" -ForegroundColor Red
    return $null
}

#region Process Management

<#
.SYNOPSIS
    Closes all running Thorium Browser processes
.DESCRIPTION
    Attempts graceful shutdown first, then force closes if necessary
#>
function Close-Thorium {
    Write-Host "`nClosing Thorium browser..." -ForegroundColor Cyan
    
    $thoriumProcesses = Get-Process | Where-Object { 
        $_.ProcessName -like "*thorium*" -or 
        $_.MainWindowTitle -like "*Thorium*" 
    }
    
    if ($thoriumProcesses) {
        $thoriumProcesses | Stop-Process -Force
        
        # Wait for processes to close
        $maxWait = 10
        $count = 0
        while (($count -lt $maxWait) -and (Get-Process | Where-Object { $_.ProcessName -like "*thorium*" })) {
            Write-Host "Waiting for Thorium to close... ($count/$maxWait)" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            $count++
        }
        
        # Force kill if still running
        $remainingProcesses = Get-Process | Where-Object { $_.ProcessName -like "*thorium*" }
        if ($remainingProcesses) {
            Write-Host "Force closing remaining Thorium processes..." -ForegroundColor Yellow
            $remainingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }
}

<#
.SYNOPSIS
    Compares Thorium Browser versions
.PARAMETER CurrentVersion
    Currently installed version string
.PARAMETER LatestVersion
    Latest available version string
.OUTPUTS
    Boolean indicating if versions match
#>
function Compare-ThoriumVersions {
    param (
        [string]$CurrentVersion,
        [string]$LatestVersion
    )
    
    $currentClean = $CurrentVersion -replace '^M' -replace '[^0-9.]'
    $latestClean = $LatestVersion -replace '^M' -replace '[^0-9.]'
    
    try {
        return [version]$currentClean -eq [version]$latestClean
    } catch {
        return $CurrentVersion -eq $LatestVersion
    }
}

#region Main Script Execution

# Main script
try {
    $ErrorActionPreference = "Stop"
    $tempDir = Join-Path $env:TEMP "ThoriumDownload"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    Write-Host "=== Thorium Browser Installer/Updater ===" -ForegroundColor Cyan
    Write-Host "----------------------------------------"
    
    $currentInstall = Get-InstalledThorium
    $versions = Get-ThoriumVersions
    $latestVersion = $versions[0]

    if ($currentInstall) {
        Write-Host "`nCurrent Thorium Installation:" -ForegroundColor Cyan
        Write-Host "Version: $($currentInstall.Version)" -ForegroundColor White

        if (Compare-ThoriumVersions -CurrentVersion $currentInstall.Version -LatestVersion $latestVersion.Version) {
            Write-Host "`nYou are already running the latest version of Thorium!" -ForegroundColor Green
            Write-Host "Version: $($currentInstall.Version)" -ForegroundColor Green
            exit 0
        }

        Write-Host "`nNew version available: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($latestVersion.Version)" -ForegroundColor Green
        Write-Host "Would you like to update? (Y/N) [Y]" -ForegroundColor Yellow
        if ((Read-Host) -eq "N") {
            exit 0
        }

        Close-Thorium
    } else {
        $cpuArch = Get-CPUArchitecture
        Write-Host "`nInstalling Thorium Browser..." -ForegroundColor Cyan
        Write-Host "Detected CPU Architecture: " -NoNewline
        Write-Host "$cpuArch" -ForegroundColor Green
        Write-Host "Installing version: " -NoNewline
        Write-Host "$($latestVersion.Version)" -ForegroundColor Green
        Write-Host "Would you like to proceed with installation? (Y/N) [Y]" -ForegroundColor Yellow
        if ((Read-Host) -eq "N") {
            exit 0
        }
    }

    $asset = Get-ThoriumAsset -LatestVersion $latestVersion
    if (-not $asset) {
        throw "Could not find suitable installer"
    }

    $installerPath = Join-Path $tempDir $asset.name
    Write-Host "`nDownloading Thorium installer..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath

    Uninstall-Thorium
    Write-Host "`nInstalling new version..." -ForegroundColor Cyan
    Start-Process -FilePath $installerPath -Wait
    
    Write-Host "`nInstallation/Update complete!" -ForegroundColor Green
    Write-Host "----------------------------------------"
    
} catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
} finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}