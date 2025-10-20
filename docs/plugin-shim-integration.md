# NixOS-WSL Plugin Integration

This document provides a high-level overview of the WSL plugin integration project for NixOS-WSL, including task tracking, implementation status, and next steps for achieving production readiness and upstream contribution.

## 🎯 Task Tracker

### Phase 1: Foundation Completion
- [x] **PRIORITY 1**: Research Windows plugin build dependencies and MinGW limitations
  - [x] Investigate specific Windows SDK APIs missing from MinGW
  - [x] Research alternative build automation (Windows containers in podman)  
  - [x] Evaluate MSVC cross-compilation options
  - [x] Document definitive build strategy
  - **📄 DELIVERABLE**: [MinGW Limitations Analysis](mingw-limitations-analysis.md)
- [x] **Complete Windows Plugin Implementation with real APIs**
  - [x] Remove all MinGW-specific stubs and limitations
  - [x] Implement real AF_HYPERV socket communication
  - [x] Implement WMI-based Hyper-V VM GUID discovery
  - [x] Implement VirtDisk API for VHDX creation and management
  - [x] Implement SetupAPI for disk enumeration
  - [x] Add all required Windows SDK headers and libraries
  - **📄 DELIVERABLE**: Production-ready plugin code with full Windows SDK APIs
- [x] **Windows Container Build Environment (winpod devShell)**
  - [x] Create winpod devShell with Windows Server Core + VS Build Tools
  - [x] Implement build-windows-plugin script for container builds
  - [x] Add container management tools (manage-containers)
  - [x] Make winpod the default devShell (nix develop)
  - [x] Maintain MinGW devShell for lightweight development
  - [x] Auto-detecting Makefile for build method selection
  - **📄 DELIVERABLE**: Complete Windows container development environment
- [x] **WSL Interop Enhancement** ✅ **COMPLETE**
  - [x] Investigate Docker Desktop WSL integration for Windows containers
  - [x] Implement PowerShell build script fallback for Windows host
  - [x] Add WSL interop detection and Windows host build capability
  - **✅ ACHIEVED**: Enable Windows container builds from within WSL environment
- [ ] Service GUID Registration Automation
- [ ] Enhanced Error Handling and Testing

### Phase 2: Distribution Integration
- [ ] Plugin Distribution bundling
- [ ] User Experience Enhancement
- [ ] Testing Infrastructure

### Phase 3: Upstream Contribution
- [ ] Code Quality & Standards review
- [ ] Upstream Compatibility validation
- [ ] Community Engagement

---

## Project Overview

This integration implements VSOCK-based communication between the NixOS-WSL systemd-shim and a Windows-side WSL plugin, enabling declarative disk management through NixOS configuration. The system ensures specified bare disks and VHDX files are available before distribution boot proceeds.

## Architecture Components

### NixOS-WSL Side Implementation

#### Systemd-Shim Modifications (`utils/src/shim.rs`)

The systemd-shim has been enhanced with:

- **VSOCK Server**: Creates a VSOCK listener on port 5001 when disk requirements are configured
- **INI Parsing**: Reads `/etc/nixos-wsl-plugin.ini` to check for disk requirements
- **Plugin Communication**: Exchanges configuration with the Windows plugin and waits for disk validation
- **Graceful Fallback**: Continues boot if plugin communication fails (with warning)

Key functions added:
- `communicate_with_plugin()`: Handles VSOCK server creation and data exchange
- `check_plugin_config()`: Orchestrates the plugin check before boot

#### NixOS Module (`modules/wsl-plugin-config.nix`)

A new NixOS module provides declarative configuration for disk requirements:

```nix
wsl.plugin = {
  enable = true;
  
  disks.bare = [
    { uuid = "..."; label = "data-disk"; }
  ];
  
  disks.vhdx = [
    { path = "D:\\WSL\\data.vhdx"; sizeGB = 100; filesystem = "ext4"; }
  ];
};
```

The module:
- Generates an INI configuration file at `/etc/nixos-wsl-plugin.ini`
- Validates configuration options
- Integrates with the NixOS-WSL module system

#### Dependencies Added

- `configparser = "1.0"`: For INI file parsing in Rust
- `libc = "0.2"`: For low-level VSOCK socket operations
- `socket` feature for nix crate: Additional socket functionality

### Windows Plugin Side Implementation

#### Core Plugin (`wsl-plugin-sample/plugin.cpp`)

The Windows plugin implements:

- **WSL Plugin API Integration**: Hooks into WSL lifecycle events
- **VSOCK Client**: Connects to NixOS-WSL systemd-shim via AF_HYPERV sockets
- **WMI VM Discovery**: Identifies target WSL distribution VM GUID
- **Disk Management**: Validates bare disk presence and manages VHDX creation/attachment
- **Selective Activation**: Only processes distributions that implement the VSOCK protocol

#### Key Plugin Features
- **Distribution Detection**: Attempts VSOCK connection to identify compatible distributions
- **Disk Validation**: Checks disk UUIDs and VHDX file availability
- **Error Reporting**: Provides detailed status to systemd-shim
- **Graceful Fallback**: Handles non-NixOS distributions transparently

#### Current Limitations
**MinGW Build Constraints**:
- Missing AF_HYPERV socket family definitions
- Incomplete WMI COM interface support
- No VirtDisk API for VHDX management
- Limited Windows Storage APIs

**Production Requirements**:
- MSVC compilation for full Windows SDK access
- Real WMI queries for VM GUID discovery
- Complete disk enumeration and VHDX operations
- Service GUID registration automation

---

## VSOCK Communication Protocol

### Connection Flow

1. **Shim starts**: Reads `/etc/nixos-wsl-plugin.ini`
2. **If disks configured**: Creates VSOCK server on port 5001
3. **Waits for connection**: 5-second timeout for plugin to connect
4. **Data exchange**:
   - Shim → Plugin: Complete INI configuration
   - Plugin → Shim: Status response (ready/notReady)
5. **Boot decision**:
   - `STATUS ready`: Continue boot
   - `STATUS notReady`: Exit with error
   - Connection timeout: Continue with warning

### VSOCK Addressing

- **Linux side**: AF_VSOCK family, port 5001, VMADDR_CID_ANY
- **Windows side**: AF_HYPERV family, Service GUID `00001389-facb-11e6-bd58-64006a7986d3`
- Port encoding: 5001 (0x1389) embedded in Service GUID

## Configuration Format

The INI file at `/etc/nixos-wsl-plugin.ini`:

```ini
[version]
format=1

[bare_disk_1]
uuid=e8f7a6b5-c4d3-a2b1-0123-456789abcdef
label=data-disk

[vhdx_1]
path=D:\WSL\NixOS\secondary.vhdx
size_gb=100
filesystem=ext4
```

## Current Status & Integration Gaps

### ✅ Completed
- VSOCK communication protocol design and implementation
- NixOS-WSL systemd-shim integration
- Plugin configuration module
- Basic Windows plugin structure
- Comprehensive documentation and design
- **MinGW limitations analysis and Windows build strategy** ([Report](mingw-limitations-analysis.md))

### 🔄 In Progress
- Windows Plugin Implementation with real Windows APIs
- Service GUID Registration automation

### ❌ Missing for Production
- **Windows Plugin Real APIs**: WMI, VirtDisk, SetupAPI implementations
- **MSVC Build System**: Production compilation environment
- **Service GUID Registration**: Automated Windows registry configuration
- **Integration Testing**: End-to-end testing infrastructure
- **Distribution Bundling**: Plugin packaging with NixOS-WSL

## Building and Testing

### NixOS-WSL Side
```bash
# Build the modified systemd-shim
nix build '.#nixosConfigurations.default.config.system.build.nativeUtils'

# Test with plugin configuration
# See example-plugin-config.nix for complete examples
```

### Windows Plugin Side

#### Production MSVC Build (WSL Interop Method) ✅ **COMPLETE**
```bash
# Production Windows container build with full SDK APIs
cd /home/tim/src/wsl-plugin-sample
nix develop                    # Enter winpod devShell
build-windows-plugin          # Builds via WSL interop + Windows containers
```

**Requirements**: Windows container runtime must be installed on Windows host (see Windows Container Setup below).

#### Development MinGW Build (Limited APIs)
```bash
# Current MinGW build (limited functionality - testing only)
cd /home/tim/src/wsl-plugin-sample
nix develop .#mingw
make plugin
```

## Windows Container Runtime Setup

### **Recommended: Podman Desktop (Windows 11 Home)**

Podman Desktop is the recommended container runtime for Windows 11 Home as it provides better flexibility and troubleshooting capabilities compared to Docker Desktop.

#### Prerequisites
1. **Windows 11 Home** (Build 19043 or greater)
2. **WSL 2** must be enabled
3. **Virtual Machine Platform** feature enabled
4. At least **6 GB RAM** available

#### Installation Steps

1. **Enable Required Windows Features** (Run as Administrator):
   ```powershell
   # Enable Virtual Machine Platform
   dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
   
   # Install WSL 2 (if not already installed)
   wsl.exe --install
   
   # Restart Windows
   ```

2. **Download and Install Podman Desktop**:
   - Visit [podman-desktop.io](https://podman-desktop.io/docs/installation/windows-install)
   - Download the Windows installer
   - Run installer and select **WSL v2** option during setup

3. **Verify Installation**:
   ```powershell
   # Check Podman installation
   podman --version
   
   # Verify WSL integration
   wsl --list --verbose
   ```

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

Common issues and solutions:

1. **"docker/podman not recognized"**:
   - Verify container runtime is installed and in PATH
   - Restart PowerShell/Command Prompt
   - Check Windows environment variables

2. **WSL interop fails**:
   - Ensure WSL 2 is properly installed: `wsl --status`
   - Verify WSL can access Windows filesystem: `ls /mnt/c/`
   - Check PowerShell execution policy: `Get-ExecutionPolicy`

3. **Container pull fails**:
   - Verify internet connectivity
   - Check Windows Defender/Firewall settings
   - Try pulling container manually: `podman pull mcr.microsoft.com/windows/servercore:ltsc2022`

### **Architecture Benefits**

The WSL interop approach provides:
- **Development in WSL**: Use familiar Linux/NixOS tools
- **Production builds on Windows**: Access full Windows SDK APIs
- **Automatic path conversion**: WSL paths → Windows UNC paths
- **Fallback capability**: Linux containers when Windows host unavailable

## Error Handling

The implementation includes robust error handling:

1. **Missing configuration**: Silently continues (no disk requirements)
2. **Invalid INI format**: Logs warning and continues
3. **VSOCK creation failure**: Logs warning and continues
4. **Plugin timeout**: Logs warning and continues without validation
5. **Plugin reports not ready**: Exits with error code 1

## Security Considerations

- Configuration file is read-only (`0444` permissions)
- VSOCK communication is VM-isolated
- No sensitive data in configuration (only disk UUIDs and paths)
- Plugin validation happens before filesystem mounts

## Next Steps & Roadmap

### Immediate Priority: Build Environment Research
The first critical step is resolving Windows plugin compilation:

1. **MinGW Limitation Analysis**: Document specific Windows SDK APIs unavailable
2. **Alternative Build Strategies**: Research Windows containers, MSVC cross-compilation
3. **Automation Requirements**: Define reproducible build environment needs
4. **Implementation Plan**: Choose and implement chosen build strategy

### Integration Roadmap
1. **Phase 1**: Complete Windows plugin with real API implementations
2. **Phase 2**: Full integration testing and distribution bundling
3. **Phase 3**: Upstream contribution to NixOS-WSL

### Success Metrics
- Real disk operations working end-to-end
- Automated plugin installation process
- NixOS-WSL maintainer approval
- Community adoption and documentation

## Compatibility

- **WSL2**: Full support with VSOCK communication
- **WSL1**: Gracefully skipped (no Hyper-V VMs)
- **Non-plugin distributions**: No impact (plugin won't connect)

## Repository Structure

### NixOS-WSL Repository
- `docs/plugin-shim-integration.md` - This overview document
- `docs/wsl-plugin-design-doc.md` - Detailed technical design (in wsl-plugin-sample)
- `utils/src/shim.rs` - Systemd-shim VSOCK implementation
- `modules/wsl-plugin-config.nix` - NixOS configuration module
- `example-plugin-config.nix` - Example configurations

### WSL Plugin Repository (`/home/tim/src/wsl-plugin-sample`)
- `plugin.cpp` - Windows plugin implementation
- `docs/wsl-plugin-design-doc.md` - Comprehensive technical design
- `docs/WSL-STARTUP.md` - WSL architecture analysis
- `flake.nix` - Development environment (MinGW + Wine)
- `Makefile` - Build automation

### Cross-Project Integration
- **Shared Protocol**: VSOCK communication specification
- **Coordinated Testing**: Joint testing between repositories  
- **Release Coordination**: Synchronized compatibility releases