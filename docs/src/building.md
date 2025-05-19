# Building a NixOS-WSL System Tarball

This requires access to a system that already has Nix installed. Please refer to the [Nix installation guide](https://nixos.org/guides/install-nix.html) if that\'s not the case.

In all the below examples, note that:
- the tarballBuilder writes its output to cwd as `nixos-wsl.tar.gz`.
- commands that require root privilege are written with `sudo -i` to use login shell.
  - this may be necessary to provide root user access to the `nix` binaries, but this depends on your nix installation method.

## Using Flakes

### Remote Flake 

This syntax evaluates the NixOS-WSL flake defined in a remote path, e.g. a github repository:

```sh
sudo -i nix run github:nix-community/NixOS-WSL#nixosConfigurations.default.config.system.build.tarballBuilder
```

### Local Flake

Useful for local flake development, this syntax evaluates a NixOS-WSL flake defined locally, e.g. a local folder containing a flake.nix:

```sh
sudo -i nix run /home/username/src/my-nixos-wsl-fork#.nixosConfigurations.your-hostname.config.system.build.tarballBuilder
```

Here we specify the absolute path to the flake for the [_installable_](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix#installables) argument to [`nix run`](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-run#description) to avoid any problems related to cwd changing in the sudo call. Since this argument follows the [_path-like syntax for a flakeref_](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake#path-like-syntax), it can be specified relative or absolute, however we are being explicit here so these instructions aren't overly dependent on the nix user's environment.

Without a flake-enabled nix, you must separately:

1. Build the tarballBuilder: `nix-build -A nixosConfigurations.mysystem.config.system.build.tarballBuilder`
2. Run the tarballBuilder: `sudo ./result/bin/nixos-wsl-tarball-builder`

The resulting tarball can then be found under `nixos.wsl`.
