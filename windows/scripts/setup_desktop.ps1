<#
.SYNOPSIS
    LiteRT-LM Desktop Setup Script for Flutter Gemma (Windows)

.DESCRIPTION
    Downloads JRE, copies JAR, and extracts native libraries for Windows builds.
    Called by CMake during the build process.

.PARAMETER PluginDir
    Path to the plugin directory (flutter_gemma/windows)

.PARAMETER OutputDir
    Path to the CMake build output directory

.EXAMPLE
    .\setup_desktop.ps1 -PluginDir "C:\flutter_gemma\windows" -OutputDir "C:\build"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PluginDir,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

Write-Host "=== LiteRT-LM Desktop Setup (Windows) ===" -ForegroundColor Cyan

# Configuration
$JreVersion = "21.0.5+11"
$JreVersionUnderscore = $JreVersion -replace '\+', '_'
$JreCacheDir = "$env:LOCALAPPDATA\flutter_gemma\jre"
$JreArchive = "OpenJDK21U-jre_x64_windows_hotspot_$JreVersionUnderscore.zip"
$JreUrl = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-$JreVersion/$JreArchive"

$JarName = "litertlm-server.jar"
$PluginRoot = Split-Path -Parent $PluginDir

Write-Host "Plugin root: $PluginRoot"
Write-Host "Output dir: $OutputDir"

# Create output directories
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputDir\jre" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputDir\litertlm" | Out-Null

# === Download and install JRE ===
function Install-Jre {
    $jreDest = "$OutputDir\jre"

    if (Test-Path "$jreDest\bin\java.exe") {
        Write-Host "JRE already installed" -ForegroundColor Green
        return
    }

    Write-Host "Setting up JRE..."
    New-Item -ItemType Directory -Force -Path $JreCacheDir | Out-Null

    $archive = "$JreCacheDir\$JreArchive"
    $extractedDir = "$JreCacheDir\jdk-$JreVersion-jre"

    # Download if not cached
    if (-not (Test-Path $archive)) {
        Write-Host "Downloading JRE from $JreUrl..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $JreUrl -OutFile $archive -UseBasicParsing
        } catch {
            Write-Error "Failed to download JRE: $_"
            exit 1
        }
    } else {
        Write-Host "Using cached JRE archive" -ForegroundColor Green
    }

    # Extract if needed
    if (-not (Test-Path $extractedDir)) {
        Write-Host "Extracting JRE..."
        Expand-Archive -Path $archive -DestinationPath $JreCacheDir -Force
    }

    # Copy to output directory
    Write-Host "Copying JRE to output..."
    Copy-Item -Path "$extractedDir\*" -Destination $jreDest -Recurse -Force

    Write-Host "JRE installed successfully" -ForegroundColor Green
}

# === Copy JAR ===
function Copy-Jar {
    $jarDest = "$OutputDir\$JarName"

    if (Test-Path $jarDest) {
        Write-Host "JAR already in output directory" -ForegroundColor Green
        return
    }

    # Check possible JAR locations
    $jarLocations = @(
        "$PluginDir\Resources\$JarName",
        "$PluginRoot\Resources\$JarName",
        "$PluginRoot\litertlm-server\build\libs\litertlm-server-0.1.0-all.jar"
    )

    $jarSource = $null
    foreach ($location in $jarLocations) {
        if (Test-Path $location) {
            $jarSource = $location
            break
        }
    }

    if ($jarSource) {
        Write-Host "Copying JAR from $jarSource..."
        Copy-Item -Path $jarSource -Destination $jarDest -Force
        Write-Host "JAR copied successfully" -ForegroundColor Green
    } else {
        Write-Warning "JAR not found! Build the server first:"
        Write-Warning "  cd $PluginRoot\litertlm-server && .\gradlew.bat fatJar"
    }
}

# === Extract native libraries ===
function Extract-Natives {
    $nativesDir = "$OutputDir\litertlm"
    $jarPath = "$OutputDir\$JarName"

    if (-not (Test-Path $jarPath)) {
        Write-Host "JAR not found, skipping native extraction" -ForegroundColor Yellow
        return
    }

    # Native library path inside JAR (Windows x64)
    $nativePath = "com/google/ai/edge/litertlm/jni/win32-x86-64"

    Write-Host "Extracting native libraries from JAR..."

    # Use jar command or PowerShell to extract
    try {
        # Create temp directory for extraction
        $tempDir = "$env:TEMP\flutter_gemma_natives"
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

        # Extract using Expand-Archive (treat JAR as ZIP)
        $jarCopy = "$tempDir\temp.zip"
        Copy-Item -Path $jarPath -Destination $jarCopy
        Expand-Archive -Path $jarCopy -DestinationPath $tempDir -Force

        # Find and copy native libraries
        $nativeSourceDir = "$tempDir\$($nativePath -replace '/', '\')"
        if (Test-Path $nativeSourceDir) {
            Get-ChildItem -Path $nativeSourceDir -Filter "*.dll" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $nativesDir -Force
                Write-Host "  Extracted: $($_.Name)" -ForegroundColor Green
            }
        } else {
            Write-Warning "Native libraries not found in JAR at path: $nativePath"
            Write-Host "  Available paths in JAR may differ. Check JAR contents manually."
        }

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    } catch {
        Write-Warning "Failed to extract natives: $_"
    }
}

# === Main ===
try {
    Install-Jre
    Copy-Jar
    Extract-Natives

    Write-Host ""
    Write-Host "=== Setup complete ===" -ForegroundColor Cyan
    Write-Host "JRE: $OutputDir\jre"
    Write-Host "JAR: $OutputDir\$JarName"
    Write-Host "Natives: $OutputDir\litertlm"

} catch {
    Write-Error "Setup failed: $_"
    exit 1
}
