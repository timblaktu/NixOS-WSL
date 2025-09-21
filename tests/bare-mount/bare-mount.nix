{
  imports = [
    <nixos-wsl/modules>
  ];

  wsl.enable = true;

  # Test basic configuration
  wsl.bareMounts = {
    enable = true;
    disks = [
      {
        name = "test-disk-1";
        serialNumber = "TEST_SERIAL_001";
        devicePattern = "nvme-test-disk-1-*";
        filesystem = null;  # Test bare mount without filesystem
      }
      {
        name = "test-disk-2";
        serialNumber = "TEST_SERIAL_002";
        devicePattern = "nvme-test-disk-2-*";
        filesystem = {
          mountPoint = "/mnt/test";
          fsType = "ext4";
          options = [ "defaults" "noatime" ];
        };
      }
    ];
  };
}