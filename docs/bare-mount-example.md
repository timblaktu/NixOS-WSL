# WSL Bare Mount Module - Usage Guide

The `wsl.bareMounts` module provides a declarative way to mount bare block devices in WSL2, enabling high-performance storage access without Windows filesystem overhead.

## Why Use Bare Mounts?

WSL2's default filesystem access through Windows (e.g., `/mnt/c`) incurs significant performance penalties:
- 10-50x slower for I/O intensive operations
- Especially noticeable for Nix store operations
- File permission and case sensitivity issues

Bare mounts provide near-native Linux performance by directly accessing block devices.

## Prerequisites

1. Identify your disk's serial number from Windows PowerShell (as Administrator):
   ```powershell
   Get-PhysicalDisk | Select-Object FriendlyName, SerialNumber
   ```

2. Ensure the disk is not mounted in Windows (for exclusive access)

3. Format the disk with a Linux filesystem if needed (from WSL):
   ```bash
   # After bare mounting, format if needed
   sudo mkfs.ext4 /dev/disk/by-id/nvme-YourDiskPattern
   ```

## Basic Configuration

### Simple Bare Mount (No Filesystem)

```nix
{
  wsl.bareMounts = {
    enable = true;
    disks = [{
      name = "data-disk";
      serialNumber = "YOUR_SERIAL_NUMBER_HERE";
      devicePattern = "nvme-*YOUR_DISK_MODEL*";
      filesystem = null;  # Just bare mount, no automatic filesystem mounting
    }];
  };
}
```

### With Automatic Filesystem Mounting

```nix
{
  wsl.bareMounts = {
    enable = true;
    disks = [{
      name = "storage";
      serialNumber = "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.";
      devicePattern = "nvme-Samsung_SSD_990_PRO_4TB_*";
      filesystem = {
        mountPoint = "/mnt/wsl/storage";
        fsType = "ext4";
        options = [ "defaults" "noatime" "nodiratime" ];
      };
    }];
  };
}
```

## Multiple Disks

```nix
{
  wsl.bareMounts = {
    enable = true;
    disks = [
      {
        name = "fast-storage";
        serialNumber = "SERIAL_1";
        devicePattern = "nvme-Samsung_*";
        filesystem = {
          mountPoint = "/mnt/fast";
          fsType = "ext4";
          options = [ "defaults" "noatime" ];
        };
      }
      {
        name = "bulk-storage";
        serialNumber = "SERIAL_2";
        devicePattern = "scsi-WD_*";
        filesystem = {
          mountPoint = "/mnt/bulk";
          fsType = "xfs";
          options = [ "defaults" ];
        };
      }
    ];
  };
}
```

## Using for Nix Store

For maximum Nix performance, you can bind mount from bare storage:

```nix
{
  wsl.bareMounts = {
    enable = true;
    disks = [{
      name = "nix-storage";
      serialNumber = "YOUR_SERIAL";
      devicePattern = "nvme-*";
      filesystem = {
        mountPoint = "/mnt/wsl/nix-storage";
        fsType = "ext4";
        options = [ "defaults" "noatime" ];
      };
    }];
  };

  # Bind mount /nix from the bare storage
  fileSystems."/nix" = {
    device = "/mnt/wsl/nix-storage/nix";
    fsType = "none";
    options = [ "bind" ];
  };
}
```

## Manual Management

The module provides a `wsl-bare-mount` command for manual management:

```bash
# Check status of configured disks
wsl-bare-mount status

# Manually mount all configured disks
wsl-bare-mount mount

# Unmount all configured disks
wsl-bare-mount unmount
```

## Troubleshooting

### Disk Not Found

If the disk isn't found at boot:
1. Verify the serial number matches exactly (including trailing dots)
2. Check Windows Event Viewer for mount errors
3. Ensure the disk isn't in use by Windows
4. Try manual mounting with `wsl-bare-mount mount`

### Mount Fails

1. Check the device pattern matches: `ls /dev/disk/by-id/ | grep YOUR_PATTERN`
2. Verify filesystem type is correct
3. Check systemd journal: `journalctl -u '*.mount'`

### Performance Not Improved

1. Ensure you're accessing the bare mount path, not Windows paths
2. Verify with `mount | grep YOUR_MOUNT_POINT`
3. Test with: `dd if=/dev/zero of=/YOUR_MOUNT/test.img bs=1M count=1000`

## Device Pattern Examples

The `devicePattern` should match entries in `/dev/disk/by-id/`:

- NVMe: `nvme-Samsung_SSD_990_PRO_4TB_*`
- SATA SSD: `ata-Samsung_SSD_870_EVO_*`
- SCSI/SAS: `scsi-3600508b1001c*`
- USB (not recommended): `usb-WD_Elements_*`

Use wildcards (`*`) to handle minor variations in device naming.

## Security Considerations

- Bare mounted disks are accessible to all WSL instances on the system
- Consider encryption if storing sensitive data
- Set appropriate file permissions on mount points
- Regular backups recommended as WSL2 is still evolving

## Example: Development Environment

Complete example for a development machine with fast NVMe storage:

```nix
{ config, ... }:

{
  wsl.bareMounts = {
    enable = true;
    disks = [{
      name = "dev-storage";
      serialNumber = "NVME_SERIAL_12345";
      devicePattern = "nvme-Samsung_SSD_980_PRO_2TB_*";
      filesystem = {
        mountPoint = "/mnt/dev";
        fsType = "ext4";
        options = [ 
          "defaults"
          "noatime"      # Skip access time updates
          "nodiratime"   # Skip directory access time updates
          "lazytime"     # Batch timestamp updates
        ];
      };
    }];
  };

  # Use bare storage for development directories
  systemd.tmpfiles.rules = [
    "L+ /home/developer/projects - - - - /mnt/dev/projects"
    "L+ /var/lib/docker - - - - /mnt/dev/docker"
  ];
}
```

## Performance Benchmarks

Typical improvements with bare mounts (results may vary):

| Operation | Windows FS | Bare Mount | Improvement |
|-----------|------------|------------|-------------|
| Nix build | 45 min | 8 min | 5.6x |
| Git operations | 30 sec | 2 sec | 15x |
| Database writes | 1000 ops/s | 25000 ops/s | 25x |
| Large file copy | 100 MB/s | 2000 MB/s | 20x |

## Further Reading

- [WSL2 Disk Management](https://learn.microsoft.com/en-us/windows/wsl/disk-space)
- [WSL Mount Options](https://learn.microsoft.com/en-us/windows/wsl/wsl2-mount-disk)
- [NixOS-WSL Documentation](https://github.com/nix-community/NixOS-WSL)