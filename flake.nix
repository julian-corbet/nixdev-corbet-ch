{
  description = "nixdev — the operator's toolbox: cloud CLIs, IaC, Kubernetes clients and language toolchains, declared per host, plus the developer's own tools that run in the cluster";

  # NO INPUTS FOR CONSUMERS. This flake is options plus catalogues, taking `pkgs`/`config`/`lib`
  # from whichever evaluation composes it, so a real host or a real cluster render never puts a
  # second nixpkgs -- or a sibling flake's whole input closure -- into its own closure. Everything
  # below is used by `checks` ALONE; nothing this flake exports reaches into any of it.
  #
  # The file said "NO INPUTS" outright until the cluster surface arrived. That was true of a flake
  # with nothing to check, and keeping it would have meant a repository whose cluster module was
  # verified by nobody -- `nix flake check` evaluates no module output on its own, so it would have
  # passed on flake syntax alone.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The renderer the cluster module defines into. A real input rather than a name in a comment:
    # without it there is no module system to evaluate the cluster side against.
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # THE APP GRAMMAR THIS REPOSITORY CONSUMES, and the point being proven rather than a shortcut:
    # a consumer imports the grammar itself, and this input exists so the checks can render the
    # cluster module through the REAL grammar and assert what comes out -- rather than asserting
    # that a module which merely mentions `nixk3s.apps` evaluates.
    nixk3s = {
      url = "github:julian-corbet/nixk3s-corbet-ch";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixidy.follows = "nixidy";
    };
  };

  outputs = { self, nixpkgs, nixidy, nixk3s }:
    let
      lib = nixpkgs.lib;

      # x86_64-linux only, and narrow ON PURPOSE. Every check here builds a real nixidy environment,
      # so a declared platform that cannot be built is a platform `nix flake check` skips while
      # exiting 0 -- a check that passed having tested nothing. Narrow the claim rather than weaken
      # the check.
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
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

      # The cluster plane: the developer's tools that run in the cluster rather than on a desk.
      # Only one module in the class, so `.default` is honest rather than invented.
      #
      # BUILT FROM THE GRAMMAR'S OWN CONSUMER FACTORY rather than hand-written here, and the
      # reason is measured rather than aesthetic. This module used to be 722 lines, of which the
      # parts that were genuinely nixdev's came to about twenty: `addressingOf` was byte-identical
      # to the same function in eight sibling repositories, `imageOf` to six, and the probe, state,
      # ports and secrets helpers to eleven or twelve apiece. Fourteen copies of one design, each
      # ageing on its own -- which is exactly how `adopt` reached eight of thirteen translators and
      # stopped, and how five repositories kept a different name for the same platform option for
      # two weeks with nothing able to notice.
      #
      # What was nixdev's is entirely in `lib/applications.nix`: which of these tools writes a
      # database file and therefore cannot roll, which is a static bundle that keeps nothing, how
      # patient a probe must be before it calls a slow start a failure, which variables carry a
      # credential, what each one can be locked down to. That is knowledge about software and it
      # stays here. The vocabulary for DECLARING one, and every guard on it, is the grammar's and
      # now comes from the grammar.
      #
      # nixdev needs no `extend`: every field its catalogue carries is one the factory already
      # knows. A repository whose catalogue holds something genuinely its own -- a WOPI host list,
      # a retention argument, a write probe -- passes it there instead of forking the translator.
      nixidyModules.nixdev = nixk3s.lib.mkConsumerModule {
        namespace = "nixdev";
        catalogue = self.lib.applications;
      };
      nixidyModules.default = self.nixidyModules.nixdev;

      # The catalogues, exposed so a consumer can inspect or validate them without re-reading the
      # files.
      lib.tools = import ./lib/tools.nix { };
      lib.applications = (import ./lib/applications.nix { }).applications;

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          # The cluster module's own resolution and every guard it makes, in BOTH directions: an
          # empty surface renders nothing, a declared one resolves, and each refusal gets a
          # declaration that must be refused.
          cluster-eval = import ./checks/cluster-eval.nix {
            inherit pkgs lib nixidy;
            appsModule = nixk3s.nixidyModules.apps;
            clusterModule = self.nixidyModules.nixdev;
            values = ./examples/all/values.nix;
          };

          # The manifests that actually come out, read back off the rendered bytes rather than off
          # the options that produced them.
          cluster-render = import ./checks/cluster-render.nix {
            inherit pkgs lib nixidy;
            appsModule = nixk3s.nixidyModules.apps;
            clusterModule = self.nixidyModules.nixdev;
            values = ./examples/all/values.nix;
          };

          # THE ADOPTION BAR: the same two workloads written out by hand in the grammar underneath,
          # rendered separately and diffed against the translator's tree. Byte-identical or the
          # check is red, because for an adopter a changed byte is a sync and a sync is a rollout.
          cluster-parity = import ./checks/cluster-parity.nix {
            inherit pkgs lib nixidy;
            appsModule = nixk3s.nixidyModules.apps;
            clusterModule = self.nixidyModules.nixdev;
            values = ./examples/all/values.nix;
            grammar = ./examples/parity/grammar.nix;
          };
        });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
