# Example NixOS configuration with WSL plugin disk management
{ config, pkgs, ... }:

{
  # Import NixOS-WSL modules
  imports = [ ./modules ];
  
  # Enable WSL support
  wsl = {
    enable = true;
    
    # Enable the WSL plugin disk management
    plugin = {
      enable = true;
      
      # Configure bare disks that must be attached before boot
      disks.bare = [
        {
          # UUID of the external disk (get this with `blkid` on Windows/WSL)
          uuid = "e8f7a6b5-c4d3-a2b1-0123-456789abcdef";
          label = "external-data";
        }
        {
          uuid = "f9c8b7a6-d5e4-b3a2-1234-56789abcdef0";
          label = "backup-disk";
        }
      ];
      
      # Configure VHDX files to create and attach
      disks.vhdx = [
        {
          # Windows path for the VHDX file
          path = "D:\\WSL\\NixOS\\secondary.vhdx";
          sizeGB = 100;
          filesystem = "ext4";
        }
        {
          path = "E:\\WSL\\NixOS\\work.vhdx";
          sizeGB = 200;
          filesystem = "ext4";
        }
      ];
    };
  };
  
  # Example mount points for the attached disks
  # These would be configured based on your actual disk UUIDs
  fileSystems."/mnt/external-data" = {
    device = "/dev/disk/by-uuid/e8f7a6b5-c4d3-a2b1-0123-456789abcdef";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };
  
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-uuid/f9c8b7a6-d5e4-b3a2-1234-56789abcdef0";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };
  
  # The VHDX disks would be mounted after they're created and attached
  # You would need to determine their device paths after attachment
}