# WSL Plugin Installation Guide

This guide provides detailed instructions for setting up the Windows container build environment required for NixOS-WSL plugin development.

## Windows Container Runtime Setup

### **Recommended: Podman Desktop (Windows 11 Home)**

Podman Desktop is the recommended container runtime for Windows 11 Home as it provides better flexibility and troubleshooting capabilities compared to Docker Desktop.

#### Prerequisites
1. **Windows 11 Home** (Build 19043 or greater)
2. **WSL 2** must be enabled
3. **Virtual Machine Platform** feature enabled
4. At least **8 GB RAM** available (6 GB minimum, 8 GB recommended)
5. **Administrator privileges** for initial setup

#### Complete Installation Guide

##### Step 1: Enable Required Windows Features

**Option A: Using Windows Features Dialog (Recommended for beginners)**
1. Press `Win + R`, type `appwiz.cpl`, press Enter
2. Click "Turn Windows features on or off" (left sidebar)
3. Check these boxes:
   - ☑️ **Virtual Machine Platform**
   - ☑️ **Windows Subsystem for Linux**
   - ☑️ **Hyper-V** (if available - not on all Home editions)
4. Click OK and restart when prompted

**Option B: Using PowerShell (Run as Administrator)**
```powershell
# Enable Virtual Machine Platform
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Enable WSL
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# Install/update WSL 2 (latest version)
wsl.exe --install --no-distribution

# Restart Windows (REQUIRED)
Restart-Computer
```

##### Step 2: Install WSL 2 and Set as Default
After restart, open PowerShell as Administrator:

```powershell
# Update WSL to latest version
wsl.exe --update

# Set WSL 2 as default version
wsl.exe --set-default-version 2

# Verify WSL 2 is working
wsl.exe --status
```

**Expected output should show WSL 2 as default version**

##### Step 3: Download and Install Podman Desktop

1. **Download Podman Desktop**:
   - Visit [podman-desktop.io/downloads/windows](https://podman-desktop.io/downloads/windows)
   - Download the `.exe` installer (not the `.msi`)
   - Choose the x64 version for 64-bit Windows

2. **Install Podman Desktop**:
   - Right-click the downloaded `.exe` → "Run as administrator"
   - **IMPORTANT**: During installation, when prompted:
     - ☑️ Check "Install Podman"
     - ☑️ Check "WSL integration" 
     - ☑️ Check "Add to PATH"
   - Complete installation and restart if prompted

##### Step 4: Configure Podman Desktop for Windows Containers

1. **Launch Podman Desktop**:
   - Open from Start Menu or desktop shortcut
   - Allow through Windows Firewall when prompted

2. **Initialize Podman Machine**:
   - Podman Desktop should prompt to initialize a machine
   - Click "Initialize and start" 
   - **Machine Settings**:
     - Memory: 4-6 GB (adjust based on available RAM)
     - CPUs: 2-4 cores
     - Disk Size: 50-100 GB
   - Wait for initialization (3-5 minutes)

3. **Enable Windows Container Support**:
   - In Podman Desktop, go to Settings
   - Navigate to "Resources" → "Machine"
   - Look for "Windows containers" option
   - If not available, this feature may need manual configuration

##### Step 5: Verify Installation

**Test Basic Podman Functionality**:
```powershell
# Check Podman version
podman --version

# Test Linux container (should work)
podman run --rm hello-world

# Check machine status
podman machine list
```

**Test Windows Container Support**:
```powershell
# Try to pull Windows base image
podman pull mcr.microsoft.com/windows/servercore:ltsc2022

# If successful, test run
podman run --rm mcr.microsoft.com/windows/servercore:ltsc2022 cmd /c "echo Windows containers working"
```

##### Step 6: WSL Integration Verification

From within your NixOS-WSL environment:
```bash
# Check if podman is accessible from WSL
which podman.exe

# Test WSL interop
/mnt/c/Windows/System32/cmd.exe /c "podman --version"

# Verify Windows filesystem access
ls /mnt/c/Program\ Files/
```

#### Configuration for Plugin Development

Once Podman Desktop is installed, configure for plugin development:

1. **Set Resource Limits** (in Podman Desktop Settings):
   - Memory: At least 6 GB for building Windows containers
   - Disk: 100 GB recommended (Windows base images are large)
   - CPU: Use all available cores for faster builds

2. **Configure Windows Container Mode**:
   - Some operations may require switching between Linux/Windows container modes
   - Use `podman system connection list` to see available connections

3. **Network Configuration**:
   - Ensure Windows Firewall allows Podman Desktop
   - Corporate networks may need proxy configuration

#### Testing WSL Interop Build
Once Podman Desktop is installed:

```bash
# From WSL (NixOS-WSL environment):
cd /home/tim/src/wsl-plugin-sample
nix develop
build-windows-plugin
```

**Expected Output**:
- Detects WSL environment: `[INFO] WSL environment detected: NixOS`
- Creates PowerShell script on Windows side
- Executes Windows container build via PowerShell interop
- Builds plugin.dll with full Windows SDK APIs

### **Alternative: Docker Desktop (Limited)**

Docker Desktop on Windows 11 Home only supports Linux containers, not Windows containers. However, it can be used if you modify the approach to use Linux-based cross-compilation.

#### Installation
- Download from [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)
- Requires WSL 2 backend
- **Limitation**: Cannot run Windows Server Core containers

### **Troubleshooting**

#### Common Installation Issues

**1. "Feature installation failed" or "DISM error"**:
```powershell
# Check Windows version compatibility
winver

# Try alternative feature enabling method
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All

# Verify features are enabled
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
```

**2. "WSL 2 requires an update to its kernel component"**:
- Download latest WSL2 kernel: [WSL2 Kernel Update](https://aka.ms/wsl2kernel)
- Install and restart
- Run: `wsl --update` then `wsl --shutdown`

**3. "Podman not recognized" or PATH issues**:
```powershell
# Check if podman is in PATH
where.exe podman

# Manually add to PATH if needed
$env:PATH += ";C:\Program Files\RedHat\Podman"

# Permanent PATH addition (as Administrator)
[Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\Program Files\RedHat\Podman", "Machine")
```

#### Runtime Issues

**4. "WSL interop fails" or permission denied**:
```bash
# From WSL, check interop is enabled
cat /proc/sys/fs/binfmt_misc/WSLInterop

# Verify Windows executable access
ls -la /mnt/c/Windows/System32/cmd.exe

# Test basic interop
/mnt/c/Windows/System32/cmd.exe /c "echo test"

# Check WSL configuration
cat /etc/wsl.conf
```

**5. "Container pull fails" or network issues**:
```powershell
# Test network connectivity
Test-NetConnection mcr.microsoft.com -Port 443

# Check Windows Defender/Firewall
Get-NetFirewallRule -DisplayName "*Podman*"

# Try manual container pull with verbose output
podman pull --log-level debug mcr.microsoft.com/windows/servercore:ltsc2022

# Check proxy settings if behind corporate firewall
netsh winhttp show proxy
```

**6. "Podman machine won't start" or initialization fails**:
```powershell
# Check Hyper-V status (if available)
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V

# Reset podman machine
podman machine stop
podman machine rm podman-machine-default
podman machine init --memory 4096 --cpus 2

# Check available resources
Get-ComputerInfo | Select-Object TotalPhysicalMemory, CsProcessors
```

#### Windows Container Specific Issues

**7. "Windows containers not supported" or switching modes**:
```powershell
# Check current container mode
podman system info | findstr -i "os type"

# Some Windows 11 Home editions have limited container support
# Verify Windows version supports containers
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion
```

**8. "Access denied" or permission issues**:
- Run PowerShell as Administrator for container operations
- Check Windows User Account Control (UAC) settings
- Verify user is in "docker-users" group (if it exists)

#### WSL Integration Debugging

**9. "Build script can't find Windows tools"**:
```bash
# From NixOS-WSL, verify Windows paths
echo $PATH | grep -i windows
ls /mnt/c/Program\ Files/RedHat/Podman/

# Test PowerShell interop specifically
powershell.exe -Command "Get-Command podman"

# Check WSL filesystem mounting
mount | grep drvfs
```

**10. Performance issues or slow builds**:
- Increase Podman machine memory allocation
- Use WSL 2 performance tips:
  ```bash
  # Store project files in WSL filesystem, not Windows
  cp -r /mnt/c/your-project ~/src/your-project
  ```
- Enable WSL memory management:
  ```
  # Create/edit ~/.wslconfig on Windows side
  [wsl2]
  memory=6GB
  processors=4
  ```

#### Getting Help

**Log Locations for Debugging**:
- Podman Desktop logs: `%APPDATA%\Podman Desktop\logs\`
- WSL logs: `wsl --shutdown; wsl --debug-shell`
- Windows Event Viewer: Look for Hyper-V and Container events

**Useful Diagnostic Commands**:
```powershell
# System information
systeminfo | findstr /C:"OS Name" /C:"OS Version" /C:"System Type"

# Check virtualization support
powershell "Get-ComputerInfo | Select-Object HyperV*"

# WSL diagnostic
wsl --list --verbose
wsl --status
```

### **Architecture Benefits**

The WSL interop approach provides:
- **Development in WSL**: Use familiar Linux/NixOS tools
- **Production builds on Windows**: Access full Windows SDK APIs
- **Automatic path conversion**: WSL paths → Windows UNC paths
- **Fallback capability**: Linux containers when Windows host unavailable