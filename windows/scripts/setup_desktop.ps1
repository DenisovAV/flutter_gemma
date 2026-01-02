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

# Detect architecture
$Arch = $env:PROCESSOR_ARCHITECTURE
if ($Arch -eq "ARM64") {
    $JreArch = "aarch64"
    $NativeArch = "win32-aarch64"
    Write-Host "Detected ARM64 architecture" -ForegroundColor Yellow
} else {
    $JreArch = "x64"
    $NativeArch = "win32-x86-64"
    Write-Host "Detected x64 architecture"
}

$JreArchive = "OpenJDK21U-jre_${JreArch}_windows_hotspot_$JreVersionUnderscore.zip"
$JreUrl = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-$JreVersion/$JreArchive"

# SHA256 checksums from Adoptium (https://adoptium.net/temurin/releases/)
$JreChecksums = @{
    "x64" = "cb4a8a778a69aa8e5b95d1a8c7e0d60a0ad2cba005e3f4a9b25a3c33b7986b3e"
    "aarch64" = ""  # ARM64 Windows JRE checksum - add when available
}

$JarName = "litertlm-server.jar"
$PluginRoot = Split-Path -Parent $PluginDir

Write-Host "Plugin root: $PluginRoot"
Write-Host "Output dir: $OutputDir"
Write-Host "Architecture: $Arch ($JreArch)"

# Create output directories
# Note: JAR goes to data/ subdirectory to match Dart path expectations
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputDir\data" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputDir\jre" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputDir\litertlm" | Out-Null

# === Download and install JRE ===
function Install-Jre {
    $jreDest = "$OutputDir\jre"
    $jreMarker = "$jreDest\.jre_installed"

    # Check for marker file to detect complete installation
    if (Test-Path $jreMarker) {
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
            $ProgressPreference = 'Continue'  # Show progress bar
            Invoke-WebRequest -Uri $JreUrl -OutFile $archive -UseBasicParsing
        } catch {
            Write-Error "Failed to download JRE: $_"
            exit 1
        }

        # Verify checksum if available
        $expectedChecksum = $JreChecksums[$JreArch]
        if ($expectedChecksum) {
            Write-Host "Verifying checksum..."
            $actualChecksum = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLower()
            if ($actualChecksum -ne $expectedChecksum.ToLower()) {
                Remove-Item $archive -Force -ErrorAction SilentlyContinue
                Write-Error "JRE checksum mismatch! Expected: $expectedChecksum, Got: $actualChecksum"
                exit 1
            }
            Write-Host "Checksum verified" -ForegroundColor Green
        } else {
            Write-Host "Checksum not available for $JreArch, skipping verification" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Using cached JRE archive" -ForegroundColor Green
    }

    # Extract if needed
    $extractionMarker = "$extractedDir\.extracted"
    if (-not (Test-Path $extractionMarker)) {
        Write-Host "Extracting JRE..."
        # Remove partial extraction if exists
        if (Test-Path $extractedDir) {
            Remove-Item -Path $extractedDir -Recurse -Force
        }
        Expand-Archive -Path $archive -DestinationPath $JreCacheDir -Force
        # Mark extraction complete
        New-Item -ItemType File -Force -Path $extractionMarker | Out-Null
    }

    # Copy to output directory
    Write-Host "Copying JRE to output..."
    Copy-Item -Path "$extractedDir\*" -Destination $jreDest -Recurse -Force

    # Create marker file to indicate complete installation
    New-Item -ItemType File -Force -Path $jreMarker | Out-Null

    Write-Host "JRE installed successfully" -ForegroundColor Green
}

# === Copy JAR ===
function Copy-Jar {
    # JAR goes to data/ subdirectory to match Dart path expectations
    $jarDest = "$OutputDir\data\$JarName"

    if (Test-Path $jarDest) {
        Write-Host "JAR already in output directory" -ForegroundColor Green
        return $true
    }

    # Check possible JAR locations (static paths first)
    $jarLocations = @(
        "$PluginDir\Resources\$JarName",
        "$PluginRoot\Resources\$JarName"
    )

    # Dynamically find fat JAR in build directory (version-agnostic)
    $gradleLibsDir = "$PluginRoot\litertlm-server\build\libs"
    if (Test-Path $gradleLibsDir) {
        $fatJars = Get-ChildItem -Path $gradleLibsDir -Filter "*-all.jar" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending
        if ($fatJars) {
            $jarLocations += $fatJars[0].FullName
        }
    }

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
        return $true
    } else {
        Write-Error "JAR not found! Build the server first:"
        Write-Error "  cd $PluginRoot\litertlm-server && .\gradlew.bat fatJar"
        return $false
    }
}

# === Extract native libraries ===
function Extract-Natives {
    $nativesDir = "$OutputDir\litertlm"
    $jarPath = "$OutputDir\data\$JarName"

    if (-not (Test-Path $jarPath)) {
        Write-Host "JAR not found, skipping native extraction" -ForegroundColor Yellow
        return
    }

    # Native library path inside JAR (architecture-specific)
    $nativePath = "com/google/ai/edge/litertlm/jni/$NativeArch"

    Write-Host "Extracting native libraries from JAR..."
    Write-Host "  Native path: $nativePath"

    try {
        # Create temp directory for extraction
        $tempDir = "$env:TEMP\flutter_gemma_natives_$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

        # Extract using Expand-Archive (treat JAR as ZIP)
        $jarCopy = "$tempDir\temp.zip"
        Copy-Item -Path $jarPath -Destination $jarCopy
        Expand-Archive -Path $jarCopy -DestinationPath $tempDir -Force

        # Find and copy native libraries with path validation
        $nativeSourceDir = "$tempDir\$($nativePath -replace '/', '\')"
        $allowedPath = [System.IO.Path]::GetFullPath($nativeSourceDir)

        if (Test-Path $nativeSourceDir) {
            Get-ChildItem -Path $nativeSourceDir -Filter "*.dll" | ForEach-Object {
                # Validate path is within expected directory (prevent path traversal)
                $resolvedPath = [System.IO.Path]::GetFullPath($_.FullName)
                if ($resolvedPath.StartsWith($allowedPath)) {
                    Copy-Item -Path $_.FullName -Destination $nativesDir -Force
                    Write-Host "  Extracted: $($_.Name)" -ForegroundColor Green
                } else {
                    Write-Warning "Skipping suspicious path: $resolvedPath"
                }
            }
        } else {
            Write-Warning "Native libraries not found in JAR at path: $nativePath"
            Write-Host "  This may be expected if natives are bundled differently."
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

    $jarCopied = Copy-Jar
    if (-not $jarCopied) {
        Write-Error "Build cannot continue without JAR file"
        exit 1
    }

    Extract-Natives

    Write-Host ""
    Write-Host "=== Setup complete ===" -ForegroundColor Cyan
    Write-Host "JRE: $OutputDir\jre"
    Write-Host "JAR: $OutputDir\data\$JarName"
    Write-Host "Natives: $OutputDir\litertlm"

} catch {
    Write-Error "Setup failed: $_"
    exit 1
}
