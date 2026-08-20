# Builds the NixOS backend's declared Python environment and proves that an explicitly selected
# host library is importable. This catches the subtle failure where a Python module is present in
# the system closure as a separate package but absent from the interpreter's import path.
#
#   nix-build --no-out-link experiments/validate-python-environment.nix
{ nixpkgs ? <nixpkgs> }:
let
  pkgs = import nixpkgs { };
  evaluated = import "${nixpkgs}/nixos/lib/eval-config.nix" {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      ../modules/nixos.nix
      {
        system.stateVersion = "26.11";
        nixdev.python = [ "python" ];
        nixdev.pythonLibraries = [ "pyyaml" ];
      }
    ];
  };
  pythonEnvironment = pkgs.lib.findFirst
    (package: pkgs.lib.hasPrefix "python" (package.name or "") && pkgs.lib.hasSuffix "-env" (package.name or ""))
    (throw "nixdev did not assemble a Python environment")
    evaluated.config.environment.systemPackages;
in
pkgs.runCommand "nixdev-python-environment-check" { } ''
  ${pythonEnvironment}/bin/python3 -c 'import yaml; assert yaml.__version__'
  touch $out
''
