{
  imports = [
    <nixos-wsl/modules>
  ];

  wsl.enable = true;

  # Test basic configuration
  wsl.bareMounts = {
    enable = true;
    mounts = [
      {
        diskUuid = "test-uuid-0001-0001-0001-000000000001";
        mountPoint = "/mnt/wsl/test-disk-1";
        fsType = "ext4";
        options = [ "defaults" ];
      }
      {
        diskUuid = "test-uuid-0002-0002-0002-000000000002";
        mountPoint = "/mnt/wsl/test-disk-2";
        fsType = "ext4";
        options = [ "defaults" "noatime" ];
      }
    ];
  };
}