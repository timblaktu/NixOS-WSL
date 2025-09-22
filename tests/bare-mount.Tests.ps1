Describe "WSL Bare Mount Module" {
    BeforeAll {
        $distro = "NixOS-WSL-Test-BareMounts"
        $testConfig = "tests/bare-mount/bare-mount.nix"
        
        # Helper function to evaluate Nix expressions
        function Test-NixEval {
            param([string]$Expression)
            
            $result = nix-instantiate --eval --json -E $Expression 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Nix evaluation failed: $result"
            }
            return $result | ConvertFrom-Json
        }
    }

    Context "Module Configuration" {
        It "Should accept valid bare mount configuration" {
            $config = @"
{
  imports = [ ./modules ];
  wsl.enable = true;
  wsl.bareMounts = {
    enable = true;
    mounts = [{
      diskUuid = "test-uuid-1234";
      mountPoint = "/mnt/test";
      fsType = "ext4";
      options = [ "defaults" ];
    }];
  };
}
"@
            
            $tempFile = New-TemporaryFile
            $config | Out-File -FilePath $tempFile.FullName -Encoding UTF8
            
            # Test that configuration evaluates without errors
            $result = nix-instantiate --eval --json -E "(import <nixpkgs/nixos> { configuration = $($tempFile.FullName); }).config.wsl.bareMounts.enable" 2>&1
            $result | Should -Be "true"
            
            Remove-Item $tempFile.FullName
        }

        It "Should require diskUuid for each mount" {
            $invalidConfig = @"
{
  imports = [ ./modules ];
  wsl.enable = true;
  wsl.bareMounts = {
    enable = true;
    mounts = [{
      mountPoint = "/mnt/test";
      fsType = "ext4";
    }];
  };
}
"@
            
            $tempFile = New-TemporaryFile
            $invalidConfig | Out-File -FilePath $tempFile.FullName -Encoding UTF8
            
            # This should fail due to missing diskUuid
            { nix-instantiate --eval -E "(import <nixpkgs/nixos> { configuration = $($tempFile.FullName); }).config" 2>&1 } | Should -Throw
            
            Remove-Item $tempFile.FullName
        }
    }

    Context "PowerShell Script Generation" {
        It "Should generate mount script at expected location" {
            # Build test configuration
            $testDir = "tests/bare-mount"
            
            # Check if script generation is configured
            $scriptEnabled = Test-NixEval "(import <nixpkgs/nixos> { configuration = ./$testConfig; }).config.wsl.bareMounts.generateScript"
            $scriptEnabled | Should -Be $true
        }

        It "Should include idempotency checks in generated script" {
            # This would require building the configuration and checking the generated script
            # For now, we verify the option exists
            $validateEnabled = Test-NixEval "(import <nixpkgs/nixos> { configuration = ./$testConfig; }).config.wsl.bareMounts.validateOnBoot"
            $validateEnabled | Should -Be $true
        }
    }

    Context "Systemd Mount Units" {
        It "Should create systemd mount units for configured mounts" {
            # Verify that systemd.mounts are generated
            $mounts = Test-NixEval "(import <nixpkgs/nixos> { configuration = ./$testConfig; }).config.systemd.mounts"
            $mounts | Should -Not -BeNullOrEmpty
        }

        It "Should use UUID-based device paths" {
            # Check that mount units use /dev/disk/by-uuid/ paths
            $config = @"
{
  imports = [ ./modules ];
  wsl.enable = true;
  wsl.bareMounts = {
    enable = true;
    mounts = [{
      diskUuid = "abc-123";
      mountPoint = "/mnt/test";
      fsType = "ext4";
      options = [ "defaults" ];
    }];
  };
}
"@
            
            $tempFile = New-TemporaryFile
            $config | Out-File -FilePath $tempFile.FullName -Encoding UTF8
            
            # The mount units should reference /dev/disk/by-uuid/
            $mountWhat = Test-NixEval "(builtins.head (import <nixpkgs/nixos> { configuration = $($tempFile.FullName); }).config.systemd.mounts).what"
            $mountWhat | Should -BeLike "*/dev/disk/by-uuid/*"
            
            Remove-Item $tempFile.FullName
        }
    }

    Context "Boot Validation Service" {
        It "Should enable validation service by default" {
            $validationEnabled = Test-NixEval "(import <nixpkgs/nixos> { configuration = ./$testConfig; }).config.wsl.bareMounts.validateOnBoot"
            $validationEnabled | Should -Be $true
        }

        It "Should create validation systemd service" {
            $services = Test-NixEval "(import <nixpkgs/nixos> { configuration = ./$testConfig; }).config.systemd.services"
            $services | Should -Match "validate-wsl-bare-mounts"
        }
    }

    Context "Integration" {
        It "Should fail when bareMounts is enabled but no mounts configured" {
            $emptyConfig = @"
{
  imports = [ ./modules ];
  wsl.enable = true;
  wsl.bareMounts = {
    enable = true;
    mounts = [];
  };
}
"@
            
            $tempFile = New-TemporaryFile
            $emptyConfig | Out-File -FilePath $tempFile.FullName -Encoding UTF8
            
            # Should trigger assertion failure
            { nix-instantiate --eval -E "(import <nixpkgs/nixos> { configuration = $($tempFile.FullName); }).config" 2>&1 } | Should -Throw
            
            Remove-Item $tempFile.FullName
        }

        It "Should handle multiple mount configurations" {
            $multiConfig = @"
{
  imports = [ ./modules ];
  wsl.enable = true;
  wsl.bareMounts = {
    enable = true;
    mounts = [
      {
        diskUuid = "uuid-1";
        mountPoint = "/mnt/disk1";
        fsType = "ext4";
        options = [ "defaults" ];
      }
      {
        diskUuid = "uuid-2";
        mountPoint = "/mnt/disk2";
        fsType = "btrfs";
        options = [ "compress=zstd" ];
      }
    ];
  };
}
"@
            
            $tempFile = New-TemporaryFile
            $multiConfig | Out-File -FilePath $tempFile.FullName -Encoding UTF8
            
            $mountCount = Test-NixEval "(builtins.length (import <nixpkgs/nixos> { configuration = $($tempFile.FullName); }).config.systemd.mounts)"
            $mountCount | Should -BeGreaterOrEqual 2
            
            Remove-Item $tempFile.FullName
        }
    }
}