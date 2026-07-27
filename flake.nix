{
  description = "nixdev — the operator's toolbox: cloud CLIs, IaC, Kubernetes clients and language toolchains, declared per host";

  # NO INPUTS. This flake is options plus a name table; it takes `pkgs` from the consumer's own
  # evaluation rather than pinning a nixpkgs, so it never puts a second nixpkgs in anyone's closure.

  outputs = { self }: {
    # Platform-neutral policy: the options and the resolved selection. Import this directly if you
    # want the lists and intend to wire them yourself.
    nixosModules.nixdev = ./modules/nixdev.nix;

    # NixOS backend — installs, via environment.systemPackages.
    nixosModules.default = ./modules/nixos.nix;
    nixosModules.install = ./modules/nixos.nix;

    # Arch / system-manager backend — publishes `nixdev.archPackages` for the host's own pacman
    # reconciler to consume. Installs nothing itself; see modules/arch.nix for why.
    systemManagerModules.nixdev = ./modules/arch.nix;
    systemManagerModules.default = ./modules/arch.nix;

    # The catalogue, exposed so a consumer can inspect or validate it without re-reading the file.
    lib.tools = import ./lib/tools.nix { };
  };
}
