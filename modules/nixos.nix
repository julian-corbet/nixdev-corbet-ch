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
  pythonModules = lib.filter (t: t.pythonModule or false) wanted;
  pythonInterpreters = lib.filter (t: t.pythonInterpreter or false) wanted;
  ordinaryWanted = lib.filter
    (t: !(t.pythonModule or false) && !(t.pythonInterpreter or false))
    wanted;
  pythonEnvironment =
    if pythonInterpreters == [ ] then null else
    let
      interpreter = packageFor (builtins.head pythonInterpreters);
    in
    interpreter.withPackages (_: map packageFor (lib.filter resolves pythonModules));

  # `nixpkgsDesktop`: replace a desktop entry that nixpkgs ships wrong, or add one it omits. See
  # lib/tools.nix's own header for the defect class; github-desktop is the case today, whose
  # nixpkgs entry carries no `Categories=` line at all while Arch's says `Development;`, so the
  # same application files under a different heading depending which machine it is on.
  #
  # symlinkJoin rather than overrideAttrs, because appending a postInstall invalidates the
  # derivation and rebuilds from source -- an Electron application, to edit nine lines of text. A
  # join is symlinks: one entry becomes a real file and every other path still points into the
  # original output. `meta` is carried across explicitly; symlinkJoin drops it, and
  # `meta.mainProgram` is read elsewhere in this family.
  withDesktop = t: pkg:
    if !(t ? nixpkgsDesktop) then pkg else
    let
      d = t.nixpkgsDesktop;
      text = lib.concatStringsSep "\n"
        ([ "[Desktop Entry]" ] ++ lib.mapAttrsToList (k: v: "${k}=${v}") d.entry);
      file = pkgs.writeText d.file "${text}\n";
    in
    pkgs.symlinkJoin {
      name = "${lib.getName pkg}-${lib.getVersion pkg}-desktop";
      paths = [ pkg ];
      # `rm -f` first: where the package ships the entry, $out holds a SYMLINK into a read-only
      # store path and writing through it would fail. Where it ships none, this is a no-op.
      postBuild = ''
        mkdir -p $out/share/applications
        rm -f $out/share/applications/${d.file}
        cp ${file} $out/share/applications/${d.file}
      '';
      inherit (pkg) meta;
    };
in
{
  imports = [ ./nixdev.nix ];

  config = {
    assertions = [
      {
        assertion = pythonModules == [ ] || builtins.length pythonInterpreters == 1;
        message = "nixdev: select exactly one interpreter through nixdev.python when selecting host-level Python libraries.";
      }
      {
        assertion = builtins.length pythonInterpreters <= 1;
        message = "nixdev: select no more than one Python interpreter.";
      }
    ];

    environment.systemPackages =
      map (t: withDesktop t (packageFor t)) (lib.filter resolves ordinaryWanted)
      ++ lib.optional (pythonEnvironment != null) pythonEnvironment;

    warnings =
      lib.optional (cfg.unavailableOnNixos != [ ]) ''
        nixdev: ${toString (builtins.length cfg.unavailableOnNixos)} selected tool(s) have no nixpkgs equivalent and will NOT be installed on this host: ${lib.concatStringsSep ", " cfg.unavailableOnNixos}.
      ''
      ++ lib.optional (missingAttrs != [ ]) ''
        nixdev: ${toString (builtins.length missingAttrs)} tool(s) name a nixpkgs attribute that does not exist in this nixpkgs: ${lib.concatStringsSep ", " (map (t: t.nixpkgs) missingAttrs)}. Fix lib/tools.nix rather than pinning around it.
      '';
  };
}
