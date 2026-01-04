# Windows GPU VM Setup for Flutter Gemma Testing

## Create VM (Google Cloud)

```bash
gcloud compute instances create flutter-gemma-gpu \
  --zone=us-central1-a \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --image-family=windows-2022 \
  --image-project=windows-cloud \
  --boot-disk-size=200GB \
  --maintenance-policy=TERMINATE \
  --no-address
```

**Note:** `--no-address` for projects with external IP restrictions. Use Cloud NAT + IAP for access.

## Connect via IAP Tunnel

```bash
# Get Windows password
gcloud compute reset-windows-password flutter-gemma-gpu --zone=us-central1-a

# Start IAP tunnel (run in separate terminal)
gcloud compute start-iap-tunnel flutter-gemma-gpu 3389 --local-host-port=localhost:13389 --zone=us-central1-a

# Connect RDP to localhost:13389
```

## Setup Checklist

### 1. Network Access
- [ ] Cloud NAT configured (for internet access without external IP)
- [ ] Verify internet access: `ping google.com`

### 2. NVIDIA Drivers (REQUIRED)
```powershell
# Official GCP script - easiest method
Invoke-WebRequest https://github.com/GoogleCloudPlatform/compute-gpu-installation/raw/main/windows/install_gpu_driver.ps1 -OutFile C:\install_gpu_driver.ps1
C:\install_gpu_driver.ps1

# Verify
nvidia-smi
```

### 3. DirectX Shader Compiler (REQUIRED for WebGPU/LiteRT-LM)
```powershell
# Download DXC (DirectX Shader Compiler) - contains dxil.dll
Invoke-WebRequest -Uri "https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.8.2407/dxc_2024_07_31.zip" -OutFile "$env:TEMP\dxc.zip"

# Extract
Expand-Archive -Path "$env:TEMP\dxc.zip" -DestinationPath "$env:TEMP\dxc" -Force

# Copy DLLs to System32 (REQUIRED!)
Copy-Item "$env:TEMP\dxc\bin\x64\dxil.dll" "C:\Windows\System32\"
Copy-Item "$env:TEMP\dxc\bin\x64\dxcompiler.dll" "C:\Windows\System32\"
```

**Without dxil.dll you will get:**
```
DynamicLib.Open: dxil.dll Windows Error: 87
Failed to create WebGPU environment
```

### 4. SSL Root Certificates
```powershell
certutil -generateSSTFromWU roots.sst
certutil -addstore -f Root roots.sst
del roots.sst
```

### 5. Install Dev Tools (Chocolatey method)
```powershell
# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install all tools
choco install git -y
choco install temurin21 -y
choco install visualstudio2022buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" -y
choco install flutter -y
```

### 6. Configure JAVA_HOME (REQUIRED)
```powershell
# Find Java path
Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Recurse -Filter "java.exe" | Select-Object FullName

# Set environment variables (adjust path if needed)
[Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot", "Machine")
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot\bin", "Machine")

# Update current session
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$env:Path += ";C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot\bin"

# Verify
java -version
```

### 7. Git Config
```powershell
git config --global user.name "Sasha Denisov"
git config --global user.email "denisov.shureg@gmail.com"
```

### 8. Reboot
```powershell
Restart-Computer
```

### 9. After Reboot - Verify Everything
```powershell
# GPU
nvidia-smi

# Java
java -version
echo $env:JAVA_HOME

# Flutter
flutter doctor

# DXC
Test-Path "C:\Windows\System32\dxil.dll"
```

### 10. Clone and Test
```powershell
cd C:\Users\sasha
git clone https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma
git checkout feature/desktop-support

cd example
flutter pub get
flutter run -d windows
```

## Expected Success Log
```
Selected adapter: NVIDIA Tesla T4, arch=turing, vendor=nvidia, backend=Direct3D 12, adapterType=Discrete GPU
LiteRT-LM Server started on port XXXXX
```

## Troubleshooting

### "dxil.dll Windows Error: 87"
- DirectX Shader Compiler not installed
- Run step 3 (DXC installation)

### "JDK 21+ not found"
- JAVA_HOME not set
- Run step 6 (Configure JAVA_HOME)
- Restart PowerShell or reboot

### "Microsoft Basic Render Driver" instead of NVIDIA
- NVIDIA drivers not installed
- Run step 2 (NVIDIA Drivers)
- Reboot

## Cost
- n1-standard-4 + T4: ~$0.75/hour (running)
- Stopped: ~$0.005/hour (disk only)
- Spot/Preemptible: ~$0.25/hour

## Stop/Start VM
```bash
# Stop (saves money)
gcloud compute instances stop flutter-gemma-gpu --zone=us-central1-a

# Start
gcloud compute instances start flutter-gemma-gpu --zone=us-central1-a
```

## Cleanup
```bash
gcloud compute instances delete flutter-gemma-gpu --zone=us-central1-a
```
