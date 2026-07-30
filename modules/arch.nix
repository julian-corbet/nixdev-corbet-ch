#
# Arch backend — exposes the selections as pacman package names.
#
# This module installs NOTHING, because on Arch nixdev has no installer to call: packages arrive
# through whatever reconciler the host runs (nixarch's `nixarch.packages.pacman`, for the deployment
# this was written in). Wiring that reconciler in here would couple a general flake to one
# consumer's module, so the list is published and the consumer connects it:
#
#   nixarch.packages.pacman = config.nixdev.archPackages;
#
# Importing this module is therefore equivalent to importing modules/nixdev.nix directly; it
# exists so that `nixdev.archBackend` reads as a deliberate choice in a host's imports rather than
# an accident of which file someone happened to pick.
{ ... }:
{
  imports = [ ./nixdev.nix ];
}
