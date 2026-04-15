# WSL Plugin Technical Implementation Details

This document provides detailed technical information about the WSL plugin implementation, including code structure, API usage, and integration points.

## Rust Implementation Details

### Systemd-Shim Modifications

The `utils/src/shim.rs` file has been enhanced with plugin communication capabilities:

#### New Dependencies
```rust
// Cargo.toml additions
configparser = "1.0"  // INI file parsing
libc = "0.2"          // Low-level VSOCK operations
nix = { version = "0.30.0", features = ["socket"] }  // Socket functionality
```

#### Key Functions

##### `check_plugin_config() -> anyhow::Result<()>`
- **Purpose**: Main orchestration function called before boot
- **Logic**:
  1. Check if `/etc/nixos-wsl-plugin.ini` exists
  2. Parse INI file using configparser
  3. Determine if any disks are configured
  4. If configured, call `communicate_with_plugin()`
  5. Handle response and decide whether to continue boot

##### `communicate_with_plugin(config_content: &str) -> anyhow::Result<String>`
- **Purpose**: Handles VSOCK server creation and data exchange
- **Protocol**:
  1. Create AF_VSOCK socket bound to port 5001
  2. Listen for plugin connection (5-second timeout)
  3. Send complete INI configuration to plugin
  4. Receive status response from plugin
  5. Return response for decision making

#### VSOCK Implementation
```rust
use libc::{AF_VSOCK, SOCK_STREAM, VMADDR_CID_ANY};

// VSOCK address structure
#[repr(C)]
struct sockaddr_vm {
    svm_family: u16,
    svm_reserved1: u16,
    svm_port: u32,
    svm_cid: u32,
    svm_zero: [u8; 4],
}

const PLUGIN_PORT: u32 = 5001;
```

#### Error Handling Strategy
- **Missing config file**: Silent continuation (no requirements)
- **Parse errors**: Log warning, continue boot
- **Socket creation failure**: Log warning, continue boot  
- **Connection timeout**: Log warning, continue boot
- **Plugin reports "not ready"**: Exit with error code 1

### NixOS Module Implementation

#### Module Structure (`modules/wsl-plugin-config.nix`)

The module provides type-safe configuration options:

```nix
# Option definitions
wsl.plugin = {
  enable = mkEnableOption "WSL plugin support";
  
  disks.bare = mkOption {
    type = types.listOf (types.submodule {
      options = {
        uuid = mkOption { type = types.str; };
        label = mkOption { type = types.str; default = ""; };
      };
    });
  };
  
  disks.vhdx = mkOption {
    type = types.listOf (types.submodule {
      options = {
        path = mkOption { type = types.str; };
        sizeGB = mkOption { type = types.int; };
        filesystem = mkOption { type = types.str; default = "ext4"; };
      };
    });
  };
};
```

#### INI Generation Logic
```nix
# INI content generation
configContent = ''
  [version]
  format=1
  
  ${concatImapStrings bareDiskSection cfg.disks.bare}
  ${concatImapStrings vhdxSection cfg.disks.vhdx}
'';

# File placement
environment.etc."nixos-wsl-plugin.ini" = {
  source = configFile;
  mode = "0444";  # Read-only
};
```

#### Section Generators
```nix
# Bare disk section
bareDiskSection = idx: disk: ''
  [bare_disk_${toString idx}]
  uuid=${disk.uuid}
  ${optionalString (disk.label != "") "label=${disk.label}"}
'';

# VHDX section  
vhdxSection = idx: vhdx: ''
  [vhdx_${toString idx}]
  path=${vhdx.path}
  size_gb=${toString vhdx.sizeGB}
  filesystem=${vhdx.filesystem}
'';
```

## Windows Plugin Implementation

### Plugin Structure Overview

The Windows plugin (`../wsl-plugin-sample/plugin.cpp`) implements the WSL Plugin API:

#### Core Plugin Functions
```cpp
// WSL Plugin API callbacks
BOOL WINAPI WslpIsDistributionSupported(PCWSTR distributionName);
BOOL WINAPI WslpBeginPlan(WslPlanContext context);
BOOL WINAPI WslpExecutePlan(WslPlanContext context);
BOOL WINAPI WslpEndPlan(WslPlanContext context);
```

#### VSOCK Communication (Production Version)
```cpp
// Full Windows SDK implementation
#include <hvsocket.h>  // AF_HYPERV sockets

SOCKET sock = socket(AF_HYPERV, SOCK_STREAM, HV_PROTOCOL_RAW);
SOCKADDR_HV addr = {0};
addr.Family = AF_HYPERV;
// Service GUID: 00001389-facb-11e6-bd58-64006a7986d3
addr.ServiceId = {0x00001389, 0xfacb, 0x11e6, {0xbd, 0x58, 0x64, 0x00, 0x6a, 0x79, 0x86, 0xd3}};
```

#### WMI VM Discovery
```cpp
// Query Hyper-V for VM GUID
IWbemServices* pWbemServices;
IWbemLocator* pWbemLocator;

// WQL query for VM information
bstrQuery = SysAllocString(L"SELECT * FROM Msvm_ComputerSystem WHERE ElementName LIKE '%NixOS%'");
```

#### VirtDisk API Integration
```cpp
// VHDX management
#include <virtdisk.h>

VIRTUAL_DISK_ACCESS_MASK accessMask = VIRTUAL_DISK_ACCESS_CREATE;
CREATE_VIRTUAL_DISK_PARAMETERS createParams = {0};
createParams.Version = CREATE_VIRTUAL_DISK_VERSION_1;
createParams.Version1.MaximumSize = sizeGB * 1024ULL * 1024ULL * 1024ULL;

CreateVirtualDisk(&storageType, vhdxPath, accessMask, NULL, 
                  CREATE_VIRTUAL_DISK_FLAG_NONE, 0, &createParams, 
                  NULL, &vhdHandle);
```

### MinGW Limitations and Workarounds

#### Current MinGW Build (`../wsl-plugin-sample/plugin.dll`)
The existing plugin uses MinGW with these limitations:

1. **AF_HYPERV Simulation**:
   ```cpp
   #ifdef _MSC_VER
       // Real VSOCK implementation
   #else
       // MinGW: Log message and simulate success
       LogMessage("WARNING: MinGW build - AF_HYPERV not available");
   #endif
   ```

2. **WMI Stub Implementation**:
   ```cpp
   // MinGW: Simplified WMI simulation
   HRESULT queryResult = CoCreateInstance(CLSID_WbemLocator, 0, 
                                         CLSCTX_INPROC_SERVER, 
                                         IID_IWbemLocator, 
                                         (LPVOID*)&pWbemLocator);
   // Basic success simulation for testing
   ```

3. **VirtDisk Alternative**:
   ```cpp
   // MinGW: File system simulation
   CreateDirectoryA(vhdxDirectory, NULL);
   HANDLE fileHandle = CreateFileA(vhdxPath, GENERIC_WRITE, 0, NULL, 
                                   CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
   ```

### Build System Integration

#### Nix Build Environment
The plugin project uses Nix for reproducible builds:

```nix
# MinGW development shell
devShells.mingw = pkgs.mkShell {
  buildInputs = with pkgs; [
    pkgsCross.mingwW64.stdenv.cc
    pkgsCross.mingwW64.windows.mingw_w64_pthreads
    wine64  # For testing
  ];
};

# Production Windows container shell  
devShells.winpod = pkgs.mkShell {
  buildInputs = with pkgs; [
    podman
    buildWindowsPlugin  # Custom build script
  ];
};
```

#### Makefile Build Logic
```makefile
# Auto-detect build method
ifeq ($(shell command -v podman 2>/dev/null && echo found),found)
    BUILD_METHOD := container
else
    BUILD_METHOD := mingw
endif

# MinGW build (current working version)
plugin.dll: plugin.cpp
	x86_64-w64-mingw32-g++ -shared -o plugin.dll plugin.cpp \
		-lws2_32 -lkernel32 -luser32 -lole32 -loleaut32 -lwbemuuid

# Container build (future production)
container-build:
	podman build -f Dockerfile.windows -t wsl-plugin-builder .
	podman run --rm -v $(PWD):/workspace wsl-plugin-builder \
		msbuild /workspace/plugin.vcxproj /p:Configuration=Release
```

## Communication Protocol Specification

### INI Configuration Format
```ini
# Version header (required)
[version]
format=1

# Bare disk entries (0 or more)
[bare_disk_1]
uuid=e8f7a6b5-c4d3-a2b1-0123-456789abcdef
label=external-data  # Optional

[bare_disk_2]
uuid=f9c8b7a6-d5e4-b3a2-1234-56789abcdef0
label=backup-disk

# VHDX entries (0 or more)  
[vhdx_1]
path=D:\WSL\NixOS\secondary.vhdx
size_gb=100
filesystem=ext4

[vhdx_2]
path=E:\WSL\NixOS\work.vhdx
size_gb=200
filesystem=ext4
```

### VSOCK Message Protocol
```
1. Connection establishment:
   - Linux: bind(AF_VSOCK, port=5001, cid=VMADDR_CID_ANY)
   - Windows: connect(AF_HYPERV, ServiceGUID=00001389-facb-11e6-bd58-64006a7986d3)

2. Data exchange:
   Linux → Windows: Complete INI file content (null-terminated string)
   Windows → Linux: Status response ("STATUS ready" or "STATUS notReady")

3. Connection termination:
   Both sides close socket after exchange
```

### Error Response Codes
- `"STATUS ready"`: All disks available, continue boot
- `"STATUS notReady"`: Missing disks, abort boot
- Connection timeout: Continue boot with warning
- Socket errors: Continue boot with warning

## Testing and Validation

### Rust Test Coverage
Current test infrastructure in `utils/`:

```bash
# Test summary
$ NIXOS_WSL_SH=/bin/sh NIXOS_WSL_ENV=/usr/bin/env cargo test
running 4 tests
test tests::exactly_one ... ok
test tests::spicy_escapes ... ok  
test tests::simple ... ok
test tests::include_interop ... ok

test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```

Tests cover the `split_path` functionality but do not yet cover the plugin communication logic.

### Build Verification
```bash
# Verify Rust build with new dependencies
$ nix build '.#nixosConfigurations.default.config.system.build.nativeUtils'
# Success: builds systemd-shim with plugin support

# Check binary outputs
$ ls -la result/bin/
-r-xr-xr-x 2 root root  809552 systemd-shim  # Contains plugin code
-r-xr-xr-x 2 root root 1166800 split-path
-r-xr-xr-x 2 root root  834288 shell-wrapper
```

### Missing Test Areas
1. **Plugin communication tests**: Need unit tests for VSOCK logic
2. **INI parsing tests**: Validate configparser integration
3. **Error handling tests**: Test various failure scenarios
4. **Integration tests**: End-to-end VSOCK communication
5. **Windows plugin tests**: Validation of plugin.dll functionality

## Security Model

### Trust Boundaries
- **Host ↔ VM Communication**: VSOCK provides VM isolation
- **Configuration File**: Read-only, contains only disk identifiers
- **Plugin Validation**: Happens before filesystem access
- **No Sensitive Data**: Only disk UUIDs and paths in configuration

### Attack Vectors and Mitigations
1. **Malicious Plugin**: VM isolation limits access to Linux side
2. **Configuration Tampering**: Read-only file permissions  
3. **VSOCK Hijacking**: Port 5001 only accessible within VM
4. **Disk Validation Bypass**: Plugin timeout allows graceful fallback

### Privilege Requirements
- **Linux side**: No special privileges (runs as systemd-shim)
- **Windows side**: Plugin requires admin privileges for disk operations
- **Configuration**: Generated during NixOS build, not runtime

## Performance Considerations

### Boot Time Impact
- **Configuration check**: ~1ms for file reading and parsing
- **VSOCK connection**: 5-second timeout maximum
- **Normal case**: <100ms additional boot time
- **Plugin unavailable**: 5-second delay, then continue

### Resource Usage
- **Memory**: Minimal - configuration file typically <1KB
- **Network**: Local VSOCK only, no external communication
- **Disk**: Read-only access to configuration file

### Scaling Considerations
- **Multiple Distributions**: Each creates separate VSOCK server
- **Large Configurations**: INI parsing scales linearly with disk count
- **Concurrent Access**: VSOCK ports are distribution-specific

## Future Development Areas

### Immediate Priorities
1. **Windows Plugin Testing**: Complete MSVC build environment
2. **Error Recovery**: Handle partial disk attachment failures
3. **Service Registration**: Automate Windows registry configuration
4. **Integration Tests**: End-to-end validation framework

### Long-term Enhancements
1. **Dynamic Disk Management**: Runtime disk attachment/detachment
2. **Performance Monitoring**: Boot time and resource usage metrics
3. **Configuration Validation**: Pre-boot disk availability checking
4. **Distribution Bundling**: Plugin included in WSL tarball
5. **Upstream Integration**: Contribution to NixOS-WSL mainline