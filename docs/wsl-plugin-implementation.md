# WSL Plugin Disk Management Implementation

This document describes the implementation of WSL plugin disk management support in NixOS-WSL, based on the design specified in `wsl-plugin-design-doc.md`.

## Overview

The implementation adds VSOCK-based communication between the NixOS-WSL systemd-shim and a Windows-side WSL plugin, enabling declarative disk management through NixOS configuration. The shim waits for disk requirements to be met before continuing the boot process.

## Implementation Components

### 1. Systemd-Shim Modifications (`utils/src/shim.rs`)

The systemd-shim has been enhanced with:

- **VSOCK Server**: Creates a VSOCK listener on port 5001 when disk requirements are configured
- **INI Parsing**: Reads `/etc/nixos-wsl-plugin.ini` to check for disk requirements
- **Plugin Communication**: Exchanges configuration with the Windows plugin and waits for disk validation
- **Graceful Fallback**: Continues boot if plugin communication fails (with warning)

Key functions added:
- `communicate_with_plugin()`: Handles VSOCK server creation and data exchange
- `check_plugin_config()`: Orchestrates the plugin check before boot

### 2. NixOS Module (`modules/wsl-plugin-config.nix`)

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

### 3. Dependencies Added

- `configparser = "1.0"`: For INI file parsing in Rust
- `libc = "0.2"`: For low-level VSOCK socket operations
- `socket` feature for nix crate: Additional socket functionality

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

## Building and Testing

### Build the modified utils:
```bash
nix build '.#nixosConfigurations.default.config.system.build.nativeUtils'
```

### Test with configuration:
```nix
# In your NixOS configuration
{ config, pkgs, ... }:
{
  imports = [ <nixos-wsl/modules> ];
  
  wsl.enable = true;
  wsl.plugin.enable = true;
  wsl.plugin.disks.bare = [ ... ];
}
```

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

## Limitations and Future Work

Current implementation:
- Requires Windows-side plugin to be installed separately
- Service GUID must be registered in Windows registry
- No retry mechanism if disks become available later

Future enhancements:
- Automatic Service GUID registration during tarball import
- Support for dynamic disk attachment after boot
- Integration with systemd device units
- Encrypted disk support

## Compatibility

- **WSL2**: Full support with VSOCK communication
- **WSL1**: Gracefully skipped (no Hyper-V VMs)
- **Non-plugin distributions**: No impact (plugin won't connect)

## Related Files

- Design document: `docs/wsl-plugin-design-doc.md`
- Shim source: `utils/src/shim.rs`
- NixOS module: `modules/wsl-plugin-config.nix`
- Example config: `example-plugin-config.nix`
- Windows plugin: `wsl-plugin-sample/plugin.cpp` (separate repository)