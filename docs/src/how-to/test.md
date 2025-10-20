# Testing Guide

This document provides a comprehensive overview of the testing framework, mechanisms, and coverage for NixOS-WSL.

## Test Framework Overview

NixOS-WSL uses a multi-layered testing approach combining:

1. **Cargo Unit Tests** - Rust unit tests for core utilities
2. **Nix-based Integration Tests** - NixOS configuration validation
3. **Format/Style Checks** - Code quality and consistency
4. **Flake Checks** - Automated testing via `nix flake check`

## Test Mechanisms

### 1. Cargo Unit Tests (`utils/`)

Located in the `utils/` directory, these test the core Rust utilities that power NixOS-WSL's functionality.

**Build Requirements:**
- Tests require `NIXOS_WSL_SH` and `NIXOS_WSL_ENV` environment variables at compile time
- These are automatically set during nix builds via `utils/default.nix`:
  ```nix
  env = {
    NIXOS_WSL_SH = "${bash}/bin/sh";
    NIXOS_WSL_ENV = "${coreutils}/bin/env";
  };
  ```

**Test Execution:**
- Tests run automatically during package builds (`doCheck = "1"`)
- Integrated with `nix flake check` via the `test-native-utils` check

### 2. Nix-based Integration Tests (`checks/`)

These validate NixOS configuration behavior and module integration:

- **side-effects.nix** - Ensures WSL module has no side effects when disabled
- **username.nix** - Tests user configuration with different username scenarios
- **nixpkgs-input.nix** - Validates nixpkgs input compatibility
- **rustfmt.nix** - Code formatting validation
- **nixpkgs-fmt.nix** - Nix code formatting validation  
- **dotnet-format.nix** - .NET code formatting validation

### 3. Flake Check Integration

All tests are integrated with Nix's flake check system:
```bash
nix flake check  # Runs all tests
```

## Detailed Test Coverage

### Cargo Unit Tests (20 tests total)

#### split_path.rs (4 tests)
Tests PATH splitting logic for WSL environment setup:

- **`simple`** - Basic PATH splitting with good/bad paths
- **`exactly_one`** - Single path handling
- **`include_interop`** - Windows interoperability path handling
- **`spicy_escapes`** - Shell escaping with special characters (single quotes)

#### shim.rs (16 tests)
Tests VSOCK plugin communication and disk configuration parsing:

**Disk Requirements Detection (7 tests):**
- **`test_has_disk_requirements_with_bare_disk`** - Detects bare disk configurations
- **`test_has_disk_requirements_with_vhdx`** - Detects VHDX configurations
- **`test_has_disk_requirements_with_both_types`** - Detects mixed disk types
- **`test_has_disk_requirements_no_disks`** - Handles configurations without disks
- **`test_has_disk_requirements_empty_config`** - Handles empty configurations
- **`test_has_disk_requirements_only_version`** - Handles version-only configurations
- **`test_has_disk_requirements_similar_but_not_matching_sections`** - Rejects invalid section names

**Section Name Validation (2 tests):**
- **`test_is_disk_section_name_valid_cases`** - Validates correct section patterns (`bare_disk_N`, `vhdx_N`)
- **`test_is_disk_section_name_invalid_cases`** - Rejects invalid section patterns

**Multi-disk Support (1 test):**
- **`test_has_disk_requirements_multiple_numbered_sections`** - Tests multiple numbered disk sections

**VSOCK Protocol (4 tests):**
- **`test_create_vsock_addr_structure`** - VSOCK address structure creation
- **`test_vsock_constants`** - VSOCK constant validation (AF_VSOCK=40, port=5001)
- **`test_is_plugin_ready_response_ready`** - Plugin "STATUS ready" response parsing
- **`test_is_plugin_ready_response_not_ready`** - Plugin error/not-ready response handling

**C Interop (2 tests):**
- **`test_sockaddr_vm_size`** - Ensures C struct size compatibility (16 bytes)
- **`test_plugin_port_encoding`** - Validates port encoding (5001 = 0x1389)

#### shell_wrapper.rs (0 tests)
Currently has no unit tests (integration tested via system functionality).

### Integration Tests Coverage

1. **Module Side Effects** - Ensures WSL module doesn't affect non-WSL systems
2. **User Configuration** - Tests username changes and user attribute handling
3. **Build System** - Validates nixpkgs compatibility and formatting standards

## How to View Detailed Test Output

### 1. View Build Logs After Build
```bash
# Get the store path
OUT_PATH=$(nix build '.#packages.x86_64-linux.utils' --print-out-paths --no-link)

# View complete build log including cargo test output
nix log $OUT_PATH
```

### 2. Live Build Output
```bash
# See all build steps as they happen
nix build '.#packages.x86_64-linux.utils' -v

# Most verbose (includes all nix internal steps)
nix build '.#packages.x86_64-linux.utils' -vvv
```

### 3. Run Tests Directly in Development Shell
```bash
# Enter development environment
nix develop

# Run cargo tests with verbose output
cd utils
cargo test --verbose

# Run specific test module
cargo test --verbose test_has_disk_requirements
```

### 4. Run Individual Checks
```bash
# Run a specific flake check
nix build '.#checks.x86_64-linux.test-native-utils' -v

# Run all checks
nix flake check -v
```

### 5. For NixOS Rebuilds
```bash
# Show build details during system rebuild
sudo nixos-rebuild switch --flake '.#' -v --show-trace
```

## Test Results Summary

From the most recent test run:

```
shell_wrapper.rs: 0 tests (no test module)
split_path.rs: 4 tests passed (PATH splitting logic)
shim.rs: 16 tests passed (VSOCK plugin configuration)

Total: 20 tests passed, 0 failed
```

## Running Tests Manually

### Prerequisites for Manual Testing
When running cargo tests outside of nix:

```bash
# Required environment variables for compilation
export NIXOS_WSL_SH=/bin/sh
export NIXOS_WSL_ENV=/usr/bin/env

# Run tests
cd utils
cargo test
```

### Test During Development
```bash
# Enter development shell (sets up environment automatically)
nix develop

# Run tests with coverage
cd utils
cargo test --verbose

# Run specific tests
cargo test test_has_disk_requirements --verbose
```

## Continuous Integration

All tests run automatically via GitHub Actions and are integrated with the repository's flake check system. The `nix flake check` command provides a single entry point for running the complete test suite.