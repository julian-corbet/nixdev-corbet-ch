#
# nixdev's cluster surface: declare which of the developer's tools run in the cluster, and render
# them.
#
# ── THIS MODULE DOES NOT IMPLEMENT KUBERNETES, AND THAT IS THE DESIGN ──────────────────────────
#
# A sibling repository's whole subject is the app grammar: a workload declares WHAT IT NEEDS -- an
# image, ports, an exposure class, whether it may sleep, which directories it writes and what backs
# them -- and that grammar renders the Argo CD Application, the Namespace, the Deployment and the
# Service. Everything expressible in those terms is expressed in them: this module DEFINES INTO
# `nixk3s.apps` and renders no Kubernetes object of its own.
#
# So it is a translator. What it adds is the one thing the grammar cannot know: what these
# particular tools ARE. Which of them writes a database file and therefore cannot roll; which is a
# static bundle that keeps nothing; how patient a probe has to be before it is calling a slow start
# a failure.
#
# IMPORT THE GRAMMAR ALONGSIDE IT. `nixk3s.apps` is declared there, not here, and a render that
# composes this module without it fails with "the option `nixk3s.apps' does not exist".
#
# ── THE KNOWLEDGE/VALUE SPLIT, ENFORCED RATHER THAN TRUSTED ────────────────────────────────────
#
# `lib/applications.nix` holds what is true of the software anywhere. A declaration holds what is
# true of one cluster. The two cannot supply each other's half: the catalogue says WHERE inside the
# container a directory lives and only a declaration can say WHAT BACKS IT, so a workload that
# writes a database and is declared without a backing is refused rather than quietly rendered onto
# a pod's ephemeral filesystem.
{ config, lib, ... }:

let
  cfg = config.nixdev;
  platform = cfg.clusterPlatform;
  catalogue = (import ../lib/applications.nix { }).applications;

  declared = lib.filterAttrs (_: w: w.enable) cfg.applications;
  workloads = lib.mapAttrsToList (name: w: { inherit name w; entry = catalogue.${w.app}; }) declared;

  # A whole reference wins over a repository plus a tag, which is what pinning by digest looks
  # like. The catalogue never carries either: a version is a deployment's choice and a digest is
  # one deployment's proof of what it is running.
  imageOf = entry: w: if w.image != null then w.image else "${entry.image}:${w.version}";

  portsOf = entry: lib.mapAttrs (_: number: { inherit number; }) entry.ports;

  # The split in one function: WHERE inside the container comes from the catalogue, WHAT BACKS IT
  # comes from the declaration, and neither side can supply the other's half.
  stateOf = entry: w:
    lib.mapAttrs
      (key: backing: {
        mountPath = entry.state.${key};
        inherit (backing) claim hostPath hostPathType readOnly;
      })
      w.state;

  probesOf = entry:
    lib.optionalAttrs (entry.readiness != null) {
      readiness = { port = entry.primaryPort; } // entry.readiness;
    };

  # Whole Secrets, loaded wholesale. Nothing here can carry a secret's CONTENT, which is what makes
  # a declaration written against this module safe to publish.
  secretsOf = w:
    lib.listToAttrs (map (s: lib.nameValuePair s { secret = s; envFrom = true; }) w.envFromSecrets);

  # Handed to the band model only when the consumer says it is part of the render: `origin` and
  # `slot` are ITS terms, and defining them into a render that does not declare them is an eval
  # error rather than a graceful no-op.
  addressingOf = w:
    lib.optionalAttrs (platform.origin != null) {
      origin = platform.origin;
      inherit (w) slot;
    };

  mkApp = x:
    let inherit (x) entry w; in
    {
      inherit (w) namespace createNamespace project exposure scaling;
      image = imageOf entry w;
      ports = portsOf entry;
      state = stateOf entry w;
      secrets = secretsOf w;
      env = entry.env // w.env;
      args = entry.args ++ w.args;
      probes = probesOf entry;
    }
    // lib.optionalAttrs (w.wake != null) { inherit (w) wake; }
    // addressingOf w;

  # ── Assertions ────────────────────────────────────────────────────────────────────────────────

  stateAssertions = lib.concatMap
    (x:
      let inherit (x) name w entry; in
      [
        {
          assertion = lib.attrNames w.state == lib.attrNames entry.state;
          message =
            "nixdev: application `${name}` must back every directory it writes, and backs "
            + (if w.state == { } then "none" else lib.concatMapStringsSep ", " (k: "`${k}`") (lib.attrNames w.state))
            + ". It writes: "
            + (if entry.state == { } then "nothing"
               else lib.concatStringsSep ", " (lib.mapAttrsToList (k: p: "`${k}` at ${p}") entry.state))
            + ".";
        }
        {
          assertion = lib.all
            (backing: (backing.claim == null) != (backing.hostPath == null))
            (lib.attrValues w.state);
          message =
            "nixdev: application `${name}` must back each directory with EITHER an existing claim OR a "
            + "node path, never both and never neither. A directory with no backing is a pod's own "
            + "filesystem, which is discarded on the restart this workload's own database guarantees.";
        }
      ])
    workloads;

  # A namespace outlives every workload in it, so exactly one thing may own it. Two anchors is not a
  # merge, it is two Namespace objects Argo will fight over.
  anchorAssertions =
    let
      anchors = lib.filter (x: x.w.createNamespace) workloads;
      byNs = lib.groupBy (x: x.w.namespace) anchors;
    in
    lib.mapAttrsToList
      (ns: xs: {
        assertion = lib.length xs == 1;
        message =
          "nixdev: namespace `${ns}` is anchored by ${toString (lib.length xs)} applications ("
          + lib.concatMapStringsSep ", " (x: "`${x.name}`") xs
          + "). Exactly one workload may create a namespace.";
      })
      byNs;

  slotAssertions =
    let
      claimed = lib.filter (x: x.w.slot != null) workloads;
      bySlot = lib.groupBy (x: toString x.w.slot) claimed;
    in
    lib.mapAttrsToList
      (slot: xs: {
        assertion = lib.length xs == 1;
        message =
          "nixdev: slot ${slot} is claimed by ${toString (lib.length xs)} applications ("
          + lib.concatMapStringsSep ", " (x: "`${x.name}`") xs
          + "). A slot is one identity in several address spaces at once; two workloads on one number "
          + "is two workloads on one address.";
      })
      bySlot;

  # A warning is `{ when; message; }` -- the renderer decides whether to print it, so the condition
  # travels with the text rather than being applied here.
  warnings = lib.concatMap
    (x:
      let inherit (x) name w; in
      [
        {
          when = w.scaling == "scale-to-zero" && w.wake == null;
          message =
            "nixdev: application `${name}` is declared scale-to-zero with no wake front, so nothing "
            + "brings it back. At zero replicas that is not an idle workload, it is an unreachable one.";
        }
        {
          when = w.slot != null && platform.origin == null;
          message =
            "nixdev: application `${name}` claims slot ${toString w.slot}, and "
            + "`nixdev.clusterPlatform.origin` is unset -- so the number is checked for collisions "
            + "inside this repository and by nothing for which RANGE it may come from.";
        }
      ])
    workloads;

  commonOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to render this workload. Declaring the attribute is declaring the workload, so this
        defaults to true; set false to park a declaration without rendering it.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = platform.namespace;
      defaultText = lib.literalExpression "config.nixdev.clusterPlatform.namespace";
      description = "Namespace this workload lands in.";
    };

    createNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this workload anchors its namespace. Defaults to false, because these tools share
        one namespace by default and exactly one of them may own it.
      '';
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = platform.project;
      defaultText = lib.literalExpression "config.nixdev.clusterPlatform.project";
      description = "Delivery project this workload's Application belongs to.";
    };

    slot = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = ''
        THE POSITION this workload holds in the fleet's ordered identity space. Not an address --
        the layers underneath map it into however many address spaces the fleet keeps, which is
        why nothing here moves one. The VALUE is a fleet fact and belongs to the consumer.
      '';
    };

    exposure = lib.mkOption {
      type = lib.types.enum [ "internal" "nb" "public" ];
      default = "internal";
      description = ''
        Who can reach it, as a CLASS rather than an address. Defaults to the closed answer: a tool
        that has not been thought about is not on the internet.
      '';
    };

    scaling = lib.mkOption {
      type = lib.types.enum [ "always" "scale-to-zero" ];
      default = "always";
      description = ''
        Whether the workload may idle to zero replicas.

        The catalogue records whether sleeping is SAFE for a given tool -- whether anything fires on
        a timer or watches a directory, which is what makes zero replicas lossy rather than merely
        cold. Whether it is WANTED is a deployment's call, because the wake path is one cluster's
        routing and this repository cannot see whether that path is healthy.
      '';
    };

    wake = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "keda" "sablier" ]);
      default = null;
      description = ''
        Which front wakes it from zero. Meaningless unless `scaling = "scale-to-zero"`, and its
        absence there is warned about: nothing brings the workload back.
      '';
    };

    state = lib.mkOption {
      default = { };
      description = ''
        What backs each directory the catalogue says this tool writes, keyed by the SAME names.
        Backing a directory the tool does not write, or leaving one it does write unbacked, is an
        eval error rather than a surprise at runtime.
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          claim = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "An existing PersistentVolumeClaim, by name. Nothing here creates one.";
          };
          hostPath = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "A directory on the node. Pins the workload to whichever node holds it.";
          };
          hostPathType = lib.mkOption {
            type = lib.types.str;
            default = "DirectoryOrCreate";
            description = "The hostPath type, when a node path is what backs it.";
          };
          readOnly = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether the mount is read-only.";
          };
        };
      });
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment this deployment adds, merged over whatever the catalogue sets. Values only --
        anything secret belongs in a Secret and arrives through `envFromSecrets`.
      '';
    };

    envFromSecrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Secrets loaded wholesale, by name. Named rather than carried: nothing in this repository
        can hold a secret's contents, which is what makes a declaration written here publishable.
      '';
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Arguments appended to whatever the catalogue sets.";
    };

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A whole image reference, overriding the catalogue's repository and this workload's version.
        This is where a digest pin goes, and pinning by digest is what makes two syncs of an
        identical rendered tree run identical code.
      '';
    };
  };
in
{
  options.nixdev.clusterPlatform = {
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "devtools";
      description = "Namespace these tools share unless a declaration says otherwise.";
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = "swe";
      description = "Delivery project their Applications belong to unless a declaration says otherwise.";
    };

    origin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        THE IDENTITY THIS REPOSITORY'S APPS ARE ADDRESSED UNDER, when the render composes the band
        model. A repository naming itself is not a fleet fact; which band that name binds is, and it
        lives in whatever repository owns the fleet. Left null, slots are still checked for
        collisions here and by nothing for range.
      '';
    };
  };

  options.nixdev.applications = lib.mkOption {
    default = { };
    description = ''
      The developer's tools that run in the cluster, keyed by a name of your choosing.

      THE ENUM IS THE HOUSE RULE. It is built from `lib/applications.nix`, so a tool this repository
      does not catalogue is not a refused value here -- it is not a value. What belongs in that
      catalogue is the developer's own toolbox: things reached for while building something, not
      everything a developer happens to open.
    '';
    example = lib.literalExpression ''
      {
        example-snippets = {
          app = "bytestash";
          version = "0.0.0";
          exposure = "nb";
          slot = 42;
          state.data.hostPath = "/example/state/snippets";
          envFromSecrets = [ "example-snippets-env" ];
        };
      }
    '';
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = commonOptions // {
        app = lib.mkOption {
          type = lib.types.enum (lib.attrNames catalogue);
          description = "Which tool, from the catalogue. Available: ${lib.concatStringsSep ", " (lib.attrNames catalogue)}.";
        };

        version = lib.mkOption {
          type = lib.types.str;
          description = "Which version this workload runs, used as the image tag. Required, and defaulted nowhere.";
        };
      };
    }));
  };

  # ── Computed, read-only ───────────────────────────────────────────────────────────────────────
  options.nixdev.clusterSlots = lib.mkOption {
    type = lib.types.attrsOf lib.types.ints.unsigned;
    readOnly = true;
    default = lib.listToAttrs
      (map (x: lib.nameValuePair x.name x.w.slot) (lib.filter (x: x.w.slot != null) workloads));
    defaultText = lib.literalExpression "every declared workload that claims a slot";
    description = ''
      workload -> the position it claims. Nothing is rendered from it here: what an address looks
      like is the private layer's business, and this is what that layer reads to build one.
    '';
  };

  config = {
    nixk3s.apps = lib.listToAttrs (map (x: lib.nameValuePair x.name (mkApp x)) workloads);
    nixidy.assertions = stateAssertions ++ anchorAssertions ++ slotAssertions;
    nixidy.warnings = warnings;
  };
}
