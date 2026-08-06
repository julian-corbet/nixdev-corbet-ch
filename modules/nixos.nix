#
# NixOS backend — resolves nixdev's selections into environment.systemPackages.
#
# Unlike the Arch side, this one CAN install: on NixOS the package set is part of the same
# evaluation, so there is no reconciler to hand a list to. That asymmetry is real and deliberate,
# not an inconsistency to paper over.
#
# A selection whose nixpkgs attribute is null (AUR-only, vendor binary with no derivation) is
# reported as a warning rather than dropped in silence — the host is told what it will not get.
{ config, lib, pkgs, ... }:
let
  cfg = config.nixdev;
  wanted = lib.filter (t: t.nixpkgs != null) cfg.want;
  resolves = t: lib.hasAttrByPath (lib.splitString "." t.nixpkgs) pkgs;
  missingAttrs = lib.filter (t: !(resolves t)) wanted;
  packageFor = t:
    if t ? nixpkgsOverride
    then t.nixpkgsOverride pkgs
    else lib.getAttrFromPath (lib.splitString "." t.nixpkgs) pkgs;
in
{
  imports = [ ./nixdev.nix ];

  config = {
    environment.systemPackages =
      map packageFor (lib.filter resolves wanted);

    warnings =
      lib.optional (cfg.unavailableOnNixos != [ ]) ''
        nixdev: ${toString (builtins.length cfg.unavailableOnNixos)} selected tool(s) have no nixpkgs equivalent and will NOT be installed on this host: ${lib.concatStringsSep ", " cfg.unavailableOnNixos}.
      ''
      ++ lib.optional (missingAttrs != [ ]) ''
        nixdev: ${toString (builtins.length missingAttrs)} tool(s) name a nixpkgs attribute that does not exist in this nixpkgs: ${lib.concatStringsSep ", " (map (t: t.nixpkgs) missingAttrs)}. Fix lib/tools.nix rather than pinning around it.
      '';
  };
}
