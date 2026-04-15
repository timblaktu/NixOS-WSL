# NixOS module for WSL plugin disk management configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wsl.plugin;

  # Generate INI section for a bare disk
  bareDiskSection = idx: disk: ''
    [bare_disk_${toString idx}]
    uuid=${disk.uuid}
    ${optionalString (disk.label != "") "label=${disk.label}"}
  '';

  # Generate INI section for a VHDX
  vhdxSection = idx: vhdx: ''
    [vhdx_${toString idx}]
    path=${vhdx.path}
    size_gb=${toString vhdx.sizeGB}
    filesystem=${vhdx.filesystem}
  '';

  # Complete INI content
  configContent = ''
    [version]
    format=1
    
    ${concatImapStrings bareDiskSection cfg.disks.bare}
    ${concatImapStrings vhdxSection cfg.disks.vhdx}
  '';

  configFile = pkgs.writeText "nixos-wsl-plugin.ini" configContent;

in
{
  options.wsl.plugin = {
    enable = mkEnableOption "WSL plugin support for disk management";

    disks.bare = mkOption {
      type = types.listOf (types.submodule {
        options = {
          uuid = mkOption {
            type = types.str;
            description = "UUID of the bare disk device";
            example = "e8f7a6b5-c4d3-a2b1-0123-456789abcdef";
          };

          label = mkOption {
            type = types.str;
            default = "";
            description = "Optional human-readable label";
            example = "data-disk";
          };
        };
      });
      default = [ ];
      description = "Bare disks that must be attached before boot";
    };

    disks.vhdx = mkOption {
      type = types.listOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Windows path for VHDX file";
            example = "D:\\WSL\\NixOS\\data.vhdx";
          };

          sizeGB = mkOption {
            type = types.int;
            description = "Size in gigabytes";
            example = 100;
          };

          filesystem = mkOption {
            type = types.str;
            default = "ext4";
            description = "Filesystem type";
          };
        };
      });
      default = [ ];
      description = "VHDX files to create and attach";
    };
  };

  config = mkIf cfg.enable {
    # Generate the plugin configuration file in /etc
    environment.etc."nixos-wsl-plugin.ini" = {
      source = configFile;
      mode = "0444";
    };

    # Ensure the systemd-shim has the required functionality
    # This is already handled by the modified shim.rs
  };
}
