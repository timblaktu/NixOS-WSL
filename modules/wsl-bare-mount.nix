{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wsl.bareMounts;

  # Generate PowerShell command to mount a bare disk
  makeMountCommand = disk: ''
    powershell.exe -NoProfile -Command "& { \
      \$disk = Get-PhysicalDisk -SerialNumber '${disk.serialNumber}' 2>\$null; \
      if (\$disk) { \
        \$physPath = '\\.\PHYSICALDRIVE' + \$disk.DeviceId; \
        wsl.exe --mount \$physPath --bare --name '${disk.name}' 2>\$null | Out-Null; \
      } \
    }"
  '';

  # Generate manual mount command script
  manualMountScript = pkgs.writeShellScriptBin "wsl-bare-mount" ''
    set -euo pipefail

    usage() {
      echo "Usage: $0 [mount|unmount|status]"
      echo
      echo "Manually manage WSL bare mount disks"
      echo
      echo "Commands:"
      echo "  mount    - Mount all configured bare disks"
      echo "  unmount  - Unmount all configured bare disks"
      echo "  status   - Show status of configured disks"
      exit 1
    }

    mount_disk() {
      local name="$1"
      local serial="$2"
      
      echo "Mounting disk $name (serial: $serial)..."
      
      powershell.exe -NoProfile -Command "& { \
        \$disk = Get-PhysicalDisk -SerialNumber '$serial' 2>\$null; \
        if (\$disk) { \
          \$physPath = '\\.\PHYSICALDRIVE' + \$disk.DeviceId; \
          Write-Host \"Found disk at \$physPath\"; \
          wsl.exe --mount \$physPath --bare --name '$name'; \
        } else { \
          Write-Error \"Disk with serial $serial not found\"; \
          exit 1; \
        } \
      }"
    }

    unmount_disk() {
      local name="$1"
      
      echo "Unmounting disk $name..."
      wsl.exe --unmount --name "$name"
    }

    check_disk() {
      local name="$1"
      local pattern="$2"
      
      echo -n "  $name: "
      
      if ls /dev/disk/by-id/$pattern 2>/dev/null | head -1 >/dev/null; then
        echo "✓ Available"
        ls -la /dev/disk/by-id/$pattern 2>/dev/null | head -1
      else
        echo "✗ Not found"
      fi
    }

    case "''${1:-}" in
      mount)
        ${concatMapStrings (disk: ''
          mount_disk "${disk.name}" "${disk.serialNumber}"
        '') cfg.disks}
        ;;
      
      unmount)
        ${concatMapStrings (disk: ''
          unmount_disk "${disk.name}"
        '') cfg.disks}
        ;;
      
      status)
        echo "WSL Bare Mount Status:"
        echo
        echo "Configured disks:"
        ${concatMapStrings (disk: ''
          check_disk "${disk.name}" "${disk.devicePattern}"
        '') cfg.disks}
        
        ${optionalString (any (d: d.filesystem != null) cfg.disks) ''
          echo
          echo "Filesystem mounts:"
          ${concatMapStrings (disk: optionalString (disk.filesystem != null) ''
            echo -n "  ${disk.filesystem.mountPoint}: "
            if mountpoint -q "${disk.filesystem.mountPoint}" 2>/dev/null; then
              echo "✓ Mounted"
            else
              echo "✗ Not mounted"
            fi
          '') cfg.disks}
        ''}
        ;;
      
      *)
        usage
        ;;
    esac
  '';

  diskType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        example = "internal-4tb-nvme";
        description = "Name for the WSL bare mount (used with --name flag)";
      };

      serialNumber = mkOption {
        type = types.str;
        example = "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.";
        description = "Physical disk serial number from Windows (Get-PhysicalDisk)";
      };

      devicePattern = mkOption {
        type = types.str;
        example = "nvme-Samsung_SSD_990_PRO_4TB_*";
        description = "Device pattern to match in /dev/disk/by-id/";
      };

      filesystem = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            mountPoint = mkOption {
              type = types.path;
              example = "/mnt/wsl/storage";
              description = "Where to mount the filesystem";
            };

            fsType = mkOption {
              type = types.str;
              default = "ext4";
              example = "ext4";
              description = "Filesystem type";
            };

            options = mkOption {
              type = types.listOf types.str;
              default = [ "defaults" "noatime" ];
              example = [ "defaults" "noatime" "nodiratime" ];
              description = "Mount options";
            };
          };
        });
        default = null;
        description = "Optional filesystem mount configuration. If null, only bare mount is performed.";
      };
    };
  };

in {
  options.wsl.bareMounts = {
    enable = mkEnableOption "WSL bare disk mounting support";

    disks = mkOption {
      type = types.listOf diskType;
      default = [];
      example = literalExpression ''
        [{
          name = "internal-4tb-nvme";
          serialNumber = "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.";
          devicePattern = "nvme-Samsung_SSD_990_PRO_4TB_*";
          filesystem = {
            mountPoint = "/mnt/wsl/storage";
            fsType = "ext4";
            options = [ "defaults" "noatime" ];
          };
        }]
      '';
      description = ''
        List of disks to mount as bare devices in WSL.
        Each disk requires a Windows serial number for identification
        and a name for the WSL mount. Optionally, a filesystem can
        be mounted from the bare device.
      '';
    };
  };

  config = mkIf (config.wsl.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.disks != [] -> config.wsl.wslConf.boot.systemd;
        message = "wsl.bareMounts requires systemd to be enabled (wsl.wslConf.boot.systemd)";
      }
      {
        assertion = all (disk: disk.serialNumber != "") cfg.disks;
        message = "All disks in wsl.bareMounts must have a serialNumber";
      }
      {
        assertion = unique (map (d: d.name) cfg.disks) == map (d: d.name) cfg.disks;
        message = "Disk names in wsl.bareMounts must be unique";
      }
    ];

    # Add mount commands to boot command
    wsl.wslConf.boot.command = mkIf (cfg.disks != []) (
      mkAfter (concatMapStringsSep "; " makeMountCommand cfg.disks)
    );

    # Create systemd mount units for filesystems
    systemd.mounts = lib.flatten (
      map (disk: 
        optional (disk.filesystem != null) {
          description = "Mount ${disk.name} filesystem";
          after = [ "local-fs-pre.target" ];
          before = [ "local-fs.target" ];
          wantedBy = [ "local-fs.target" ];

          unitConfig = {
            DefaultDependencies = false;
          };

          where = disk.filesystem.mountPoint;
          what = "/dev/disk/by-id/${disk.devicePattern}";
          type = disk.filesystem.fsType;
          options = concatStringsSep "," (disk.filesystem.options ++ [ "nofail" "x-systemd.device-timeout=10s" ]);
        }
      ) cfg.disks
    );

    # Add manual mount script to system packages
    environment.systemPackages = [ manualMountScript ];

    # Add documentation
    environment.etc."wsl/bare-mounts.conf" = {
      text = ''
        # WSL Bare Mount Configuration
        # Generated by NixOS - DO NOT EDIT
        #
        # This file documents the configured bare mounts.
        # Use 'wsl-bare-mount' command for manual management.
        
        ${concatMapStrings (disk: ''
          [${disk.name}]
          Serial Number: ${disk.serialNumber}
          Device Pattern: ${disk.devicePattern}
          ${optionalString (disk.filesystem != null) ''
            Mount Point: ${disk.filesystem.mountPoint}
            Filesystem: ${disk.filesystem.fsType}
            Options: ${concatStringsSep "," disk.filesystem.options}
          ''}
          
        '') cfg.disks}
      '';
    };
  };
}