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

# Helper function to get SHA256 hash (works in restricted environments)
function Get-SHA256Hash {
    param([string]$FilePath)

    # Try Get-FileHash first (PowerShell 4.0+)
    try {
        return (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower()
    } catch {
        # Fallback to certutil (always available on Windows)
        $output = certutil -hashfile $FilePath SHA256 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            # certutil output format: line 2 contains the hash
            $hash = ($output | Select-Object -Index 1) -replace '\s', ''
            return $hash.ToLower()
        }
        throw "Failed to compute hash for $FilePath"
    }
}

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
    # ARM64 Windows is NOT supported by LiteRT-LM
    # Google only provides native libraries for x86_64
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR: ARM64 Windows is not supported" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "LiteRT-LM only provides native libraries for Windows x86_64." -ForegroundColor Yellow
    Write-Host "ARM64 Windows (including Windows on ARM devices) is not supported." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "See: https://github.com/google-ai-edge/LiteRT-LM" -ForegroundColor Gray
    Write-Host ""
    exit 1
} else {
    $JreArch = "x64"
    $NativeArch = "windows-x86_64"
    $NativeLib = "litertlm_jni.dll"
    Write-Host "Detected x64 architecture"
}

$JreArchive = "OpenJDK21U-jre_${JreArch}_windows_hotspot_$JreVersionUnderscore.zip"
$JreUrl = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-$JreVersion/$JreArchive"

# SHA256 checksums from Adoptium (https://adoptium.net/temurin/releases/)
$JreChecksums = @{
    "x64" = "1749b36cfac273cee11802bf3e90caada5062de6a3fef1a3814c0568b25fd654"
    "aarch64" = "2f689ae673479c87f07daf6b7729de022a5fc415d3304ed4d25031eac0b9ce42"
}

# JAR settings
$JarName = "litertlm-server.jar"
$JarVersion = "0.11.16"
$JarUrl = "https://github.com/DenisovAV/flutter_gemma/releases/download/v$JarVersion/$JarName"
$JarChecksum = "914b9d2526b5673eb810a6080bbc760e537322aaee8e19b9cd49609319cfbdc8"
$JarCacheDir = "$env:LOCALAPPDATA\flutter_gemma\jar"
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
            # Enable TLS 1.2 and 1.3 for better compatibility with GitHub/Adoptium
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
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
            $actualChecksum = Get-SHA256Hash -FilePath $archive
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

    # Verify copy succeeded
    $criticalFile = "$jreDest\lib\jvm.cfg"
    if (-not (Test-Path $criticalFile)) {
        Write-Error "JRE copy failed: $criticalFile not found"
        exit 1
    }

    # Create marker file to indicate complete installation
    New-Item -ItemType File -Force -Path $jreMarker | Out-Null

    Write-Host "JRE installed successfully" -ForegroundColor Green
}

# === Check JDK version ===
function Check-JdkVersion {
    param([string]$JavaPath)

    if (-not (Test-Path $JavaPath)) {
        return $false
    }

    try {
        $versionOutput = & $JavaPath -version 2>&1 | Select-Object -First 1
        if ($versionOutput -match '"(\d+)') {
            $majorVersion = [int]$Matches[1]
        } elseif ($versionOutput -match '(\d+)\.') {
            $majorVersion = [int]$Matches[1]
        } else {
            return $false
        }

        if ($majorVersion -ge 21) {
            Write-Host "Found JDK $majorVersion (>= 21 required)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "JDK $majorVersion found, but 21+ required" -ForegroundColor Yellow
            return $false
        }
    } catch {
        return $false
    }
}

# === Find JDK for building ===
function Find-BuildJdk {
    # Check JAVA_HOME first
    if ($env:JAVA_HOME) {
        $javaPath = "$env:JAVA_HOME\bin\java.exe"
        if (Check-JdkVersion $javaPath) {
            return $javaPath
        }
    }

    # Check common JDK locations on Windows
    $jdkPaths = @(
        "$env:ProgramFiles\Eclipse Adoptium\jdk-21*\bin\java.exe",
        "$env:ProgramFiles\Java\jdk-21*\bin\java.exe",
        "$env:ProgramFiles\Microsoft\jdk-21*\bin\java.exe",
        "$env:ProgramFiles\Zulu\zulu-21*\bin\java.exe"
    )

    foreach ($pattern in $jdkPaths) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found -and (Check-JdkVersion $found.FullName)) {
            return $found.FullName
        }
    }

    # Try system java
    $systemJava = Get-Command java -ErrorAction SilentlyContinue
    if ($systemJava -and (Check-JdkVersion $systemJava.Source)) {
        return $systemJava.Source
    }

    return $null
}

# === Build JAR from source ===
function Build-Jar {
    $gradleDir = "$PluginRoot\litertlm-server"
    $gradleWrapper = "$gradleDir\gradlew.bat"

    if (-not (Test-Path $gradleWrapper)) {
        Write-Host "Gradle wrapper not found at $gradleWrapper" -ForegroundColor Yellow
        return $null
    }

    Write-Host "Building JAR from source..."
    Push-Location $gradleDir

    try {
        # Run gradle with error handling - don't let it crash the whole script
        $output = & $gradleWrapper fatJar --no-daemon -q 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Host "Gradle build failed (exit code: $exitCode)" -ForegroundColor Yellow
            if ($output) {
                Write-Host "Output: $output" -ForegroundColor Gray
            }
            return $null
        }

        # Find built JAR
        $builtJar = Get-ChildItem -Path "$gradleDir\build\libs\*-all.jar" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1

        if ($builtJar) {
            Write-Host "JAR built successfully: $($builtJar.FullName)" -ForegroundColor Green
            return $builtJar.FullName
        } else {
            Write-Host "Built JAR not found" -ForegroundColor Yellow
            return $null
        }
    } catch {
        Write-Host "Gradle build threw exception: $_" -ForegroundColor Yellow
        return $null
    } finally {
        Pop-Location
    }
}

# === Download JAR as fallback ===
function Download-Jar {
    Write-Host "Downloading JAR from $JarUrl..."
    New-Item -ItemType Directory -Force -Path $JarCacheDir | Out-Null

    $cachedJar = "$JarCacheDir\$JarName"

    try {
        # Enable TLS 1.2 and 1.3 for better compatibility
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $JarUrl -OutFile $cachedJar -UseBasicParsing
    } catch {
        Write-Host "Failed to download JAR: $_" -ForegroundColor Red
        Remove-Item $cachedJar -Force -ErrorAction SilentlyContinue
        return $null
    }

    # Verify checksum
    if ($JarChecksum) {
        Write-Host "Verifying checksum..."
        $actualChecksum = Get-SHA256Hash -FilePath $cachedJar
        if ($actualChecksum -ne $JarChecksum.ToLower()) {
            Remove-Item $cachedJar -Force -ErrorAction SilentlyContinue
            Write-Host "JAR checksum mismatch! Expected: $JarChecksum, Got: $actualChecksum" -ForegroundColor Red
            return $null
        }
        Write-Host "Checksum verified" -ForegroundColor Green
    }

    return $cachedJar
}

# === Setup JAR (build or download) ===
function Setup-Jar {
    Write-Host ""
    Write-Host "=== Setting up JAR ===" -ForegroundColor Gray

    # JAR goes to data/ subdirectory to match Dart path expectations
    $jarDest = "$OutputDir\data\$JarName"
    Write-Host "JAR destination: $jarDest"

    if (Test-Path $jarDest) {
        Write-Host "JAR already in output directory" -ForegroundColor Green
        return
    }

    Write-Host "Setting up LiteRT-LM Server JAR..."

    $jarSource = $null

    # 1. Check for locally built JAR first
    $localJar = Get-ChildItem -Path "$PluginRoot\litertlm-server\build\libs\*-all.jar" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
    if ($localJar) {
        Write-Host "Using locally built JAR: $($localJar.FullName)" -ForegroundColor Green
        $jarSource = $localJar.FullName
    }

    # 2. Try to build if JDK 21+ available
    if (-not $jarSource) {
        Write-Host "Checking for JDK 21+..."
        $jdkPath = Find-BuildJdk
        if ($jdkPath) {
            Write-Host "Using JDK: $jdkPath"
            $env:JAVA_HOME = Split-Path (Split-Path $jdkPath)
            $jarSource = Build-Jar
            if (-not $jarSource) {
                Write-Host "Build failed, will try download..." -ForegroundColor Yellow
            }
        } else {
            Write-Host "JDK 21+ not found, will download JAR..." -ForegroundColor Yellow
        }
    }

    # 3. Download as fallback
    if (-not $jarSource) {
        # Check cache first
        $cachedJar = "$JarCacheDir\$JarName"
        if (Test-Path $cachedJar) {
            Write-Host "Using cached JAR" -ForegroundColor Green
            $jarSource = $cachedJar
        } else {
            $jarSource = Download-Jar
            if (-not $jarSource) {
                Write-Error "Could not obtain JAR (build failed, download failed)"
                exit 1
            }
            Write-Host "Downloaded JAR successfully" -ForegroundColor Green
        }
    }

    # Copy to output directory
    Write-Host "Copying JAR to output..."
    Copy-Item -Path $jarSource -Destination $jarDest -Force

    Write-Host "JAR installed successfully" -ForegroundColor Green
}

# === Extract native libraries ===
# Extracts natives from JAR once at build time, so JVM doesn't extract to temp on every run
# This avoids temp directory bloat (TensorFlow users reported 8GB+ accumulation)
# JVM will find natives via -Djava.library.path passed by ServerProcessManager
function Extract-Natives {
    $nativesDir = "$OutputDir\litertlm"
    $jarPath = "$OutputDir\data\$JarName"

    # Check if already extracted
    if (Test-Path "$nativesDir\$NativeLib") {
        Write-Host "  Native library already extracted: $NativeLib" -ForegroundColor Green
        return
    }

    if (-not (Test-Path $jarPath)) {
        Write-Host "  JAR not found, skipping native extraction" -ForegroundColor Yellow
        return
    }

    # Native library path inside JAR (architecture-specific)
    # Format: com/google/ai/edge/litertlm/jni/windows-x86_64/litertlm_jni.dll
    $nativeZipPath = "com/google/ai/edge/litertlm/jni/$NativeArch/$NativeLib"

    Write-Host "  Extracting: $nativeZipPath"

    try {
        # Use .NET ZipFile to extract only the specific file we need
        # Much faster than extracting entire 58MB JAR
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $zip = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq $nativeZipPath }

            if ($entry) {
                $destPath = "$nativesDir\$NativeLib"
                New-Item -ItemType Directory -Force -Path $nativesDir | Out-Null

                # Extract single file
                $stream = $entry.Open()
                $fileStream = [System.IO.File]::Create($destPath)
                try {
                    $stream.CopyTo($fileStream)
                } finally {
                    $fileStream.Close()
                    $stream.Close()
                }

                $sizeMB = [math]::Round((Get-Item $destPath).Length / 1MB, 1)
                Write-Host "  Extracted: $NativeLib ($sizeMB MB)" -ForegroundColor Green
            } else {
                Write-Host "  Native library not found in JAR: $nativeZipPath" -ForegroundColor Yellow
                Write-Host "  Available paths:" -ForegroundColor Gray
                $zip.Entries | Where-Object { $_.FullName -like "*litertlm*" } | ForEach-Object {
                    Write-Host "    $($_.FullName)" -ForegroundColor Gray
                }
            }
        } finally {
            $zip.Dispose()
        }

    } catch {
        Write-Warning "  Failed to extract native library: $_"
    }
}

# === Download DirectX Shader Compiler (required for GPU) ===
function Install-DXC {
    $dxcDir = "$OutputDir\litertlm"
    $dxilDll = "$dxcDir\dxil.dll"
    $dxcompilerDll = "$dxcDir\dxcompiler.dll"

    # Check if already installed
    if ((Test-Path $dxilDll) -and (Test-Path $dxcompilerDll)) {
        Write-Host "  DirectX Shader Compiler already installed" -ForegroundColor Green
        return
    }

    Write-Host "  Downloading DirectX Shader Compiler (required for GPU)..."

    # Use stable version v1.7.2308 (August 2023) - tested and working
    $dxcVersion = "v1.7.2308"
    $dxcUrl = "https://github.com/microsoft/DirectXShaderCompiler/releases/download/$dxcVersion/dxc_2023_08_14.zip"
    $dxcCacheDir = "$env:LOCALAPPDATA\flutter_gemma\dxc"
    $dxcArchive = "$dxcCacheDir\dxc_$dxcVersion.zip"

    New-Item -ItemType Directory -Force -Path $dxcCacheDir | Out-Null

    # Download if not cached
    if (-not (Test-Path $dxcArchive)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            Write-Host "  Downloading from $dxcUrl..."
            Invoke-WebRequest -Uri $dxcUrl -OutFile $dxcArchive -UseBasicParsing
        } catch {
            Write-Warning "  Failed to download DXC: $_"
            Write-Host "  GPU acceleration may not work without DirectX Shader Compiler" -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host "  Using cached DXC archive" -ForegroundColor Green
    }

    # Extract DLLs
    try {
        $extractDir = "$dxcCacheDir\extracted"
        if (-not (Test-Path "$extractDir\bin\x64\dxil.dll")) {
            Write-Host "  Extracting DXC..."
            Expand-Archive -Path $dxcArchive -DestinationPath $extractDir -Force
        }

        # Copy DLLs to natives directory
        Copy-Item -Path "$extractDir\bin\x64\dxil.dll" -Destination $dxilDll -Force
        Copy-Item -Path "$extractDir\bin\x64\dxcompiler.dll" -Destination $dxcompilerDll -Force

        Write-Host "  DirectX Shader Compiler installed (GPU support enabled)" -ForegroundColor Green
    } catch {
        Write-Warning "  Failed to extract DXC: $_"
        Write-Host "  GPU acceleration may not work" -ForegroundColor Yellow
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
    Write-Host "Step 2: Setting up JAR..." -ForegroundColor Gray
    Setup-Jar

    Write-Host ""
    Write-Host "Step 3: Extracting native libraries..." -ForegroundColor Gray
    Extract-Natives

    Write-Host ""
    Write-Host "Step 4: Installing DirectX Shader Compiler..." -ForegroundColor Gray
    Install-DXC

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "=== Setup complete ===" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "JRE: $OutputDir\jre"
    Write-Host "JAR: $OutputDir\data\$JarName"
    Write-Host "Natives: $OutputDir\litertlm"
    Write-Host "DXC: $OutputDir\litertlm (dxil.dll, dxcompiler.dll)"

} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "SETUP FAILED!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}
