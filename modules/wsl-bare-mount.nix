{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.wsl.bareMountDisks;

  diskOptions = {
    options = {
      name = mkOption {
        type = types.str;
        description = "Name for the WSL bare mount (passed to --name flag)";
        example = "internal-4tb-nvme";
      };

      # Inspect disk details with: `lsblk -o NAME,SIZE,TYPE,FSTYPE,RO,MOUNTPOINTS,UUID`
      filesystem = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            uuid = mkOption {
              type = types.str;
              description = "UUID of the filesystem on the bare-mounted disk. From `lsblk -o NAME,SIZE,TYPE,FSTYPE,RO,MOUNTPOINTS,UUID`";
              example = "a4d3b2c1-1234-5678-90ab-cdef12345678";
            };

            mountPoint = mkOption {
              type = types.str;
              description = "Where to mount the filesystem";
              example = "/mnt/wsl/internal-4tb-nvme";
            };

            fsType = mkOption {
              type = types.str;
              default = "ext4";
              description = "Filesystem type";
            };

            options = mkOption {
              type = types.listOf types.str;
              default = [ "defaults" ];
              description = "Mount options";
            };
          };
        });
        default = null;
        description = "Filesystem configuration. If null, disk is bare-mounted but not mounted to a filesystem path.";
      };
    };
  };
in
{
  options.wsl.bareMountDisks = mkOption {
    type = types.listOf (types.submodule diskOptions);
    default = [];
    description = "List of physical disks to bare mount in WSL";
  };

  config = mkIf (cfg != []) {
    # Generate systemd mount units for each disk with filesystem config
    systemd.mounts = map (disk: {
      enable = true;
      description = "Mount ${disk.name} filesystem";

      unitConfig = {
        DefaultDependencies = false;
      };

      where = disk.filesystem.mountPoint;
      what = "/dev/disk/by-uuid/${disk.filesystem.uuid}";
      type = disk.filesystem.fsType;
      options = concatStringsSep "," (disk.filesystem.options ++ [
        "nofail"
        "x-systemd.device-timeout=10s"
      ]);

      wantedBy = [ "multi-user.target" ];
      before = [ "nix-daemon.service" ];  # If you need the mount before nix-daemon
    }) (filter (d: d.filesystem != null) cfg);

    # Create mount points
    system.activationScripts.wslBareMountDirs = stringAfter [ "specialfs" ] ''
      ${concatMapStrings (disk:
        optionalString (disk.filesystem != null) ''
          mkdir -p ${disk.filesystem.mountPoint}
        ''
      ) cfg}
    '';

    # Optional: Add a diagnostic script
    environment.systemPackages = [
      (pkgs.writeScriptBin "check-bare-mounts" ''
        #!${pkgs.bash}/bin/bash
        echo "Checking WSL bare mount status..."
        echo
        echo "Expected UUIDs:"
        ${concatMapStrings (disk:
          optionalString (disk.filesystem != null) ''
            echo "  ${disk.name}: ${disk.filesystem.uuid}"
          ''
        ) cfg}
        echo
        echo "Available block devices by UUID:"
        ls -la /dev/disk/by-uuid/ 2>/dev/null || echo "  No by-uuid directory found"
        echo
        echo "Current mounts:"
        mount | grep -E "(${concatMapStringsSep "|" (d: d.name) cfg})"
      '')
    ];
  };
}