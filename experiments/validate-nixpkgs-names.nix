# Checks every `nixpkgs` attribute in lib/tools.nix actually exists. A wrong attribute name is
# invisible until a NixOS host tries to build, and then it is an eval error in someone else's
# config -- so it gets checked here instead.
#
#   nix-instantiate --eval --strict experiments/validate-nixpkgs-names.nix -A missing   # => [ ]
{ nixpkgs ? <nixpkgs> }:
let
  pkgs = import nixpkgs { };
  lib = pkgs.lib;
  tools = import ../lib/tools.nix { };
  all = lib.flatten (map lib.attrValues (lib.attrValues tools));
  named = lib.filter (t: t.nixpkgs != null) all;
in
{
  checked = builtins.length named;
  missing = map (t: t.nixpkgs) (lib.filter (t: !(lib.hasAttrByPath (lib.splitString "." t.nixpkgs) pkgs)) named);
}
