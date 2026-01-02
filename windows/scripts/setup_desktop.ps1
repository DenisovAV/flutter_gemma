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
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host "Working Directory: $(Get-Location)" -ForegroundColor Gray

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
    "x64" = "1749b36cfac273cee11802bf3e90caada5062de6a3fef1a3814c0568b25fd654"
    "aarch64" = "2f689ae673479c87f07daf6b7729de022a5fc415d3304ed4d25031eac0b9ce42"
}

$JarName = "litertlm-server.jar"
$PluginRoot = Split-Path -Parent $PluginDir

Write-Host "Plugin dir: $PluginDir"
Write-Host "Plugin root: $PluginRoot"
Write-Host "Output dir: $OutputDir"
Write-Host "JRE cache dir: $JreCacheDir"
Write-Host "Architecture: $Arch ($JreArch)"

# Verify paths exist
Write-Host ""
Write-Host "Checking paths..." -ForegroundColor Gray
if (-not (Test-Path $PluginDir)) {
    Write-Warning "Plugin dir does not exist: $PluginDir"
}
if (-not (Test-Path $PluginRoot)) {
    Write-Warning "Plugin root does not exist: $PluginRoot"
}

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
    Write-Host ""
    Write-Host "=== Checking for JAR file ===" -ForegroundColor Gray

    # JAR goes to data/ subdirectory to match Dart path expectations
    $jarDest = "$OutputDir\data\$JarName"
    Write-Host "JAR destination: $jarDest"

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
    Write-Host "Gradle libs dir: $gradleLibsDir (exists: $(Test-Path $gradleLibsDir))"

    if (Test-Path $gradleLibsDir) {
        $fatJars = Get-ChildItem -Path $gradleLibsDir -Filter "*-all.jar" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending
        if ($fatJars) {
            Write-Host "Found fat JAR: $($fatJars[0].FullName)"
            $jarLocations += $fatJars[0].FullName
        } else {
            Write-Host "No *-all.jar files found in gradle libs dir" -ForegroundColor Yellow
        }
    }

    Write-Host "Searching JAR in locations:"
    $jarSource = $null
    foreach ($location in $jarLocations) {
        $exists = Test-Path $location
        Write-Host "  $location (exists: $exists)"
        if ($exists -and -not $jarSource) {
            $jarSource = $location
        }
    }

    if ($jarSource) {
        Write-Host "Copying JAR from $jarSource..."
        Copy-Item -Path $jarSource -Destination $jarDest -Force
        Write-Host "JAR copied successfully" -ForegroundColor Green
        return $true
    } else {
        Write-Host "JAR not found in any location" -ForegroundColor Yellow
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
Write-Host ""
Write-Host "=== Starting setup ===" -ForegroundColor Cyan

try {
    Write-Host ""
    Write-Host "Step 1: Installing JRE..." -ForegroundColor Gray
    Install-Jre

    Write-Host ""
    Write-Host "Step 2: Copying JAR..." -ForegroundColor Gray
    $jarCopied = Copy-Jar
    if (-not $jarCopied) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "WARNING: JAR file not found!" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The litertlm-server.jar is required for desktop runtime."
        Write-Host "The app will build but won't work without it."
        Write-Host ""
        Write-Host "To build the JAR, run:"
        Write-Host "  cd <flutter_gemma_plugin>/litertlm-server" -ForegroundColor Yellow
        Write-Host "  .\gradlew.bat fatJar" -ForegroundColor Yellow
        Write-Host ""
        # Don't fail build - JAR is needed at runtime, not build time
    }

    Write-Host ""
    Write-Host "Step 3: Extracting native libraries..." -ForegroundColor Gray
    Extract-Natives

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "=== Setup complete ===" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "JRE: $OutputDir\jre"
    Write-Host "JAR: $OutputDir\data\$JarName"
    Write-Host "Natives: $OutputDir\litertlm"

} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "SETUP FAILED!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}
