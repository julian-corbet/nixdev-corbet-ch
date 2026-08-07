#
# nixdev — the operator's toolbox, declared per host.
#
# WHAT THIS IS FOR. Every other module in this family owns a machine or a service. Nothing owned
# the set of tools you type at them, so on a real workstation that set grows by hand and is
# invisible to the config: on the machine this was written for, 460 packages were explicitly
# installed against roughly 30 declared. This module is how that gap closes for dev tooling.
#
# PLATFORM-NEUTRAL BY DESIGN. This file declares WHAT is wanted and resolves it to a package name
# per platform via lib/tools.nix. It installs nothing itself — see modules/nixos.nix (which sets
# environment.systemPackages) and modules/arch.nix (which publishes a pacman list for a consumer
# to feed its own reconciler, because on Arch this module has no installer of its own).
#
# NOT A LUMPED TOGGLE. There is deliberately no `nixdev.enable = true` that pulls the lot. A host
# selects per group, because the groups have genuinely different audiences: a laptop wants
# languages and git extras, a build hub might want kubernetes clients and nothing else, and an edge
# VPS should not import this module at all.
#
{ config, lib, ... }:
let
  cfg = config.nixdev;
  tools = import ../lib/tools.nix { };

  # A group's selection is a list of keys into its table. Unknown keys are an ERROR, not a silent
  # no-op: a typo'd tool name that quietly installs nothing is the failure mode this whole module
  # exists to remove.
  mkGroup = name: table: lib.mkOption {
    type = lib.types.listOf (lib.types.enum (lib.attrNames table));
    default = [ ];
    description = "Which ${name} to install. Available: ${lib.concatStringsSep ", " (lib.attrNames table)}.";
  };

  selected = lib.flatten [
    (map (k: tools.providers.${k}) cfg.cloud.providers)
    (map (k: tools.iac.${k}) cfg.cloud.iac)
    (map (k: tools.kubernetes.${k}) cfg.kubernetes)
    (map (k: tools.storage.${k}) cfg.storage)
    (map (k: tools.observability.${k}) cfg.observability)
    (map (k: tools.languages.${k}) cfg.languages)
    (map (k: tools.rust.${k}) cfg.rust)
    (map (k: tools.python.${k}) cfg.python)
    (map (k: tools.gitExtras.${k}) cfg.gitExtras)
    (map (k: tools.build.${k}) cfg.build)
    (map (k: tools.documents.${k}) cfg.documents)
    (map (k: tools.typst.${k}) cfg.typst)
    (map (k: tools.editors.${k}) cfg.editors)
    (map (k: tools.databases.${k}) cfg.databases)
  ];
in
{
  options.nixdev = {
    cloud.providers = mkGroup "cloud provider CLIs" tools.providers;
    cloud.iac = mkGroup "infrastructure-as-code tools" tools.iac;
    kubernetes = mkGroup "Kubernetes client tools" tools.kubernetes;
    storage = mkGroup "remote storage clients" tools.storage;
    observability = mkGroup "observability / log-analytics CLIs" tools.observability;
    languages = mkGroup "language toolchains" tools.languages;
    rust = mkGroup "Rust tooling" tools.rust;
    python = mkGroup "Python tooling" tools.python;
    gitExtras = mkGroup "git tooling" tools.gitExtras;
    build = mkGroup "build and dev ergonomics" tools.build;
    documents = mkGroup "document-processing libraries" tools.documents;
    typst = mkGroup "typst editor tooling (LSP, formatter)" tools.typst;
    editors = mkGroup "editors" tools.editors;
    databases = mkGroup "database inspection tools" tools.databases;

    # ── Computed, read-only ───────────────────────────────────────────────────────────────────
    want = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Resolved tool entries. The contract a platform backend consumes.";
    };

    archPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        The selected tools as pacman package names.

        This module cannot install them: on Arch there is no installer here to call. Feed it to
        whatever reconciler the host uses, e.g.

          nixarch.packages.pacman = config.nixdev.archPackages;

        Kept as a plain list rather than wired into any particular reconciler on purpose — that
        would couple this flake to one consumer's package module.
      '';
    };

    aurPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selections that live in the AUR rather than an official repo, kept SEPARATE because
        `pacman -S` cannot resolve them -- it fails the whole transaction with "target not found",
        which takes the rest of the converge down with it. Wire them to the AUR side:

          nixarch.packages.aur = config.nixdev.aurPackages;

        With no `aurUser` configured the reconciler skips them with a warning, which is the right
        failure mode: the packages stay as they are and nothing else breaks.
      '';
    };

    unavailableOnNixos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        Selected tools with no nixpkgs equivalent. Surfaced rather than silently dropped, so a
        NixOS host is told what it will not get instead of quietly missing it.
      '';
    };
  };

  config = {
    nixdev.want = selected;
    nixdev.archPackages = lib.unique (map (t: t.arch) (lib.filter (t: !(t.aur or false)) selected));
    nixdev.aurPackages = lib.unique (map (t: t.arch) (lib.filter (t: t.aur or false) selected));
    nixdev.unavailableOnNixos =
      lib.unique (map (t: t.arch) (lib.filter (t: t.nixpkgs == null) selected));
  };
}
