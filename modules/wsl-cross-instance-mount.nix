{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wsl.crossInstanceMount;
  
  # Default mountpoint with WSL_DISTRO_NAME substitution
  defaultMountpoint = "/mnt/wsl/${config.wsl.wslConf.network.hostname}";
  
  # Determine actual mountpoint - use hostname if distroName not available
  actualMountpoint = if cfg.mountpoint != null 
    then cfg.mountpoint 
    else defaultMountpoint;

in

{
  options.wsl.crossInstanceMount = {
    enable = mkEnableOption "WSL cross-instance root filesystem bind mount";
    
    mountpoint = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/mnt/wsl/my-distro";
      description = ''
        Mount point for the root filesystem bind mount.
        
        If null (default), uses /mnt/wsl/$HOSTNAME where HOSTNAME 
        is taken from wsl.wslConf.network.hostname.
        
        This allows other WSL instances to access this instance's 
        root filesystem at the specified mount point.
        
        References:
        - https://learn.microsoft.com/en-us/windows/wsl/wsl-config#automount-settings
        - https://learn.microsoft.com/en-us/windows/wsl/wsl2-mount-disk#access-the-disk-content
      '';
    };
    
    options = mkOption {
      type = types.listOf types.str;
      default = [ "bind" "x-mount.mkdir" ];
      description = ''
        Mount options for the bind mount.
        
        x-mount.mkdir ensures the mount point directory is created if it doesn't exist.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Create the bind mount via NixOS fileSystems
    fileSystems."${actualMountpoint}" = {
      device = "/";
      fsType = "none";
      options = cfg.options;
    };
    
    # Optional: Add systemd service to verify mount after boot
    systemd.services.wsl-cross-instance-mount-verify = {
      description = "Verify WSL cross-instance mount is active";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "verify-cross-instance-mount" ''
          set -euo pipefail
          
          MOUNT_POINT="${actualMountpoint}"
          
          if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
            echo "WSL cross-instance mount verified: $MOUNT_POINT"
          else
            echo "Warning: WSL cross-instance mount not found at $MOUNT_POINT"
            exit 1
          fi
        '';
      };
    };
    
    # Add mount information to system environment for scripts
    environment.sessionVariables = {
      WSL_CROSS_INSTANCE_MOUNT = actualMountpoint;
    };
  };
}
