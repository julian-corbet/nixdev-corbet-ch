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
# a failure; which environment variables carry a credential; what the software can be locked down
# to.
#
# IMPORT THE GRAMMAR ALONGSIDE IT. `nixk3s.apps` is declared there, not here, and a render that
# composes this module without it fails with "the option `nixk3s.apps' does not exist".
#
# ── THE KNOWLEDGE/VALUE SPLIT, ENFORCED RATHER THAN TRUSTED ────────────────────────────────────
#
# `lib/applications.nix` holds what is true of the software anywhere. A declaration holds what is
# true of one cluster. The two cannot supply each other's half, and four fields are split down the
# middle rather than assigned to a side:
#
#   state       catalogue: WHERE inside the container   declaration: WHAT BACKS IT
#   probes      catalogue: WHICH probes, WHAT they ask  declaration: THIS cluster's budget
#   credentials catalogue: WHICH VARIABLES carry them   declaration: WHICH SECRET delivers them
#   hardening   catalogue: what the software TOLERATES  declaration: whether to STAMP it
#
# Each of those is refused in both directions: a workload that writes a database and is declared
# without a backing is refused rather than quietly rendered onto a pod's ephemeral filesystem; a
# workload that reads no credential may not name a Secret; a budget for a probe the software does
# not warrant is an error rather than a silently dropped attribute.
#
# WHAT IS DELIBERATELY NOT HERE. There is no option that forwards a nested attrset into the
# grammar untouched. `resources` names four scalars rather than taking the grammar's
# `attrsOf str`, because a free-form resource map is how a device request -- which is a catalogue
# fact, `gpu`, and belongs to the software -- gets smuggled in through a deployment. `security`
# is not declarable at all: the classes are catalogued and a deployment gets one boolean saying
# whether they are stamped. Anything genuinely beyond this vocabulary is a typed merge on the
# object in the consumer's own tree, where somebody types it on purpose and a reader can count it.
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

  # The same split, for probes. The catalogue decides WHICH probes exist and WHAT THEY ASK FOR --
  # the endpoint, the port, and how long one answer may take, which is a property of the software
  # answering. A declaration overrides the BUDGET: how often to ask and how many failures to
  # tolerate before acting, which is how much slowness one cluster is willing to absorb. An
  # unstated budget field is the catalogue's, so a declaration states only what it is changing.
  probesOf = entry: w:
    lib.mapAttrs
      (kind: shape:
        let
          budget = w.probes.${kind} or null;
          take = field: if budget != null && budget.${field} != null then budget.${field} else shape.${field};
        in
        {
          port = entry.primaryPort;
          inherit (shape) path;
          periodSeconds = take "periodSeconds";
          failureThreshold = take "failureThreshold";
          timeoutSeconds = take "timeoutSeconds";
          initialDelaySeconds = if budget == null then 0 else budget.initialDelaySeconds;
        })
      entry.probes;

  # HARDENING: the catalogue holds the CLASSES, the declaration holds one boolean saying whether
  # this deployment stamps them. Both halves are real. "This app needs no Linux capability and
  # never has to regain privilege" is true of the software wherever it runs; whether a given pod
  # CARRIES those fields is not, because a live object that predates them takes a rollout to
  # acquire them and some clusters enforce the same thing at admission instead.
  #
  # Every term restricts, and the mapping is deliberately lossy in that direction: there is no
  # spelling here for adding a capability or allowing escalation, so a catalogue entry cannot
  # widen a pod no matter what it says.
  securityOf = entry: w:
    let h = entry.hardening; in
    lib.optionalAttrs w.harden (
      lib.optionalAttrs (h.capabilities == "none") { capabilitiesDrop = [ "ALL" ]; }
      // lib.optionalAttrs (h.privilegeEscalation == "never") { allowPrivilegeEscalation = false; }
      // lib.optionalAttrs (h.seccomp != null) { seccomp = h.seccomp; }
      // lib.optionalAttrs (h.rootFilesystem != null) {
        readOnlyRootFilesystem = h.rootFilesystem == "read-only";
      }
    );

  # Four named scalars in, two maps out, nulls dropped. A field nobody set renders no key, which
  # is what lets a declaration carry exactly the subset its live object already has.
  dropNulls = lib.filterAttrs (_: v: v != null);

  resourcesOf = w: {
    requests = dropNulls { cpu = w.resources.cpuRequest; memory = w.resources.memoryRequest; };
    limits = dropNulls { cpu = w.resources.cpuLimit; memory = w.resources.memoryLimit; };
  };

  # WHICH VARIABLES carry credentials is the catalogue's; WHICH SECRET delivers them, and under
  # which keys, is the declaration's. Named keys rather than a wholesale `envFrom`: every variable
  # this software reads is already known by name, so a key added to the Secret later has no
  # business appearing in the process environment unannounced.
  #
  # Nothing here can carry a secret's CONTENT, which is what makes a declaration written against
  # this module safe to publish.
  secretsOf = entry: w:
    lib.optionalAttrs (w.credentials.secret != null) {
      ${w.credentials.secret} = {
        secret = w.credentials.secret;
        env = lib.listToAttrs
          (map (v: lib.nameValuePair v (w.credentials.keys.${v} or v)) entry.credentials);
      };
    };

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
      secrets = secretsOf entry w;
      env = entry.env // w.env;
      args = entry.args ++ w.args;
      probes = probesOf entry w;
      security = securityOf entry w;
      resources = resourcesOf w;
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

  # A budget is an override of something, so there has to be something. Budgeting a probe the
  # software does not warrant is the same class of mistake as backing a directory it does not
  # write: the attribute would be silently dropped on the way to the manifest, and the declaration
  # would go on saying something the cluster never heard.
  probeAssertions = lib.concatMap
    (x:
      let
        inherit (x) name w entry;
        stray = lib.subtractLists (lib.attrNames entry.probes) (lib.attrNames w.probes);
      in
      [{
        assertion = stray == [ ];
        message =
          "nixdev: application `${name}` budgets "
          + lib.concatMapStringsSep ", " (k: "`${k}`") stray
          + ", which `${w.app}` does not warrant. It warrants: "
          + (if entry.probes == { } then "no probes at all"
          else lib.concatMapStringsSep ", " (k: "`${k}`") (lib.attrNames entry.probes))
          + ". A budget for a probe that is never rendered is a number nothing reads.";
      }])
    workloads;

  # Both directions, because both are real mistakes. A workload that reads credentials and names
  # no Secret starts without them and fails later, further from the cause; a workload that reads
  # none and names one has a reference nothing consumes, which is a typo wearing a declaration's
  # clothes.
  credentialAssertions = lib.concatMap
    (x:
      let
        inherit (x) name w entry;
        named = w.credentials.secret != null;
        reads = entry.credentials != [ ];
        stray = lib.subtractLists entry.credentials (lib.attrNames w.credentials.keys);
      in
      [
        {
          assertion = reads == named;
          message =
            if reads
            then
              "nixdev: application `${name}` reads credentials from "
              + lib.concatMapStringsSep ", " (v: "`${v}`") entry.credentials
              + " and names no Secret to deliver them. This repository cannot carry their content, "
              + "so the Secret's NAME is the one half a declaration owes."
            else
              "nixdev: application `${name}` names a Secret, and `${w.app}` reads no credential from "
              + "its environment. A reference nothing consumes is a typo, not a declaration.";
        }
        {
          assertion = stray == [ ];
          message =
            "nixdev: application `${name}` maps a key for "
            + lib.concatMapStringsSep ", " (v: "`${v}`") stray
            + ", which `${w.app}` does not read. A key mapping renames the KEY inside the Secret for "
            + "a variable the software already looks in; it cannot invent the variable.";
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
      let inherit (x) name w entry; in
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
        {
          when = !w.harden && entry.hardening.capabilities == "none";
          message =
            "nixdev: application `${name}` renders no securityContext, and `${w.app}` is catalogued as "
            + "needing no capability and never regaining privilege. The pod is therefore looser than the "
            + "software requires. That is a legitimate ADOPTION position -- a live pod acquires these "
            + "fields by being replaced -- and it is not a resting place.";
        }
      ])
    workloads;

  # ── The declaration's own vocabulary ──────────────────────────────────────────────────────────

  # The BUDGET half of a probe. Every field is `null` by default and `null` means "the catalogue's",
  # so a declaration states only the numbers it is actually changing and a reader can tell the two
  # apart. Which endpoint is probed, on which port, is NOT here: that is what the probe asks, and
  # what a tool answers on does not vary by cluster.
  probeBudgetType = lib.types.submodule {
    options = {
      periodSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "How often this cluster asks. Null takes the catalogue's interval.";
      };

      failureThreshold = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          How many consecutive failures this cluster absorbs before acting. Together with
          `periodSeconds` this is the whole patience budget, and it is the number that decides
          whether a slow start is tolerated or restarted into another slow start. Null takes the
          catalogue's.
        '';
      };

      timeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          How long ONE answer may take. Normally the catalogue's, because it is a property of the
          software answering rather than of the cluster asking -- overridable because a cluster
          whose storage is slower makes the same software answer slower.
        '';
      };

      initialDelaySeconds = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 0;
        description = ''
          Delay before the first probe. Purely a deployment's, and almost always wrong: a startup
          probe expresses "not yet" far better, because it stops waiting the moment the app
          answers instead of always waiting the whole time.
        '';
      };
    };
  };

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

    harden = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to stamp the catalogue's hardening classes onto this pod.

        THE CLASSES ARE NOT DECLARABLE, and that is the point of the split: "needs no Linux
        capability", "never regains privilege", "runs under the default seccomp profile" are facts
        about the software, so they live in `lib/applications.nix` and a deployment cannot loosen
        them by writing a different value. What a deployment genuinely owns is WHETHER the fields
        are rendered at all.

        That is a real question rather than a hedge. A pod acquires a securityContext by being
        REPLACED, so an adoption that takes over live objects renders exactly the subset those
        objects already carry and turns the rest on in a commit that is allowed to roll. Some
        clusters also enforce the same restrictions at admission and want nothing on the pod.

        Defaults to true: the restrictive answer is the one you get for free, and the loose one is
        the one somebody has to type -- and typing it warns, so it stays countable.
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
            type = lib.types.enum [
              "Directory"
              "DirectoryOrCreate"
              "File"
              "FileOrCreate"
              "Socket"
              "CharDevice"
              "BlockDevice"
            ];
            default = "Directory";
            description = ''
              The hostPath type, when a node path is what backs it. `Directory` -- the default, and
              the same default the grammar underneath uses -- refuses to start the pod when the
              path is missing. `DirectoryOrCreate` makes an empty one instead, which for a tool
              whose whole state is one database file means coming up looking healthy with no data.
            '';
          };
          readOnly = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether the mount is read-only.";
          };
        };
      });
    };

    probes = lib.mkOption {
      type = lib.types.attrsOf probeBudgetType;
      default = { };
      example = lib.literalExpression ''{ startup.failureThreshold = 60; }'';
      description = ''
        THIS CLUSTER'S PATIENCE, keyed by the probe the catalogue already warrants: `readiness`,
        `liveness`, `startup`. Everything unstated is the catalogue's, so a declaration carries
        only the numbers that differ here -- and budgeting a probe the software does not warrant is
        an eval error rather than an attribute silently dropped on the way to the manifest.

        The case this exists for is not fine-tuning. It is a workload woken from zero with a
        request already held open, or a node whose disk is slow enough that the software's own
        patience is no longer enough: both are the CLUSTER being slow, not the software.
      '';
    };

    resources = {
      cpuRequest = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "10m";
        description = ''
          CPU the scheduler must find for this container. A REQUEST is what placement is computed
          from, and a container with none is placed as if it were free.
        '';
      };

      memoryRequest = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "16Mi";
        description = "Memory the scheduler must find for this container.";
      };

      memoryLimit = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "128Mi";
        description = ''
          Memory ceiling. A memory limit is a KILL threshold rather than a throttle, which is
          usually what is wanted for a process that can leak.
        '';
      };

      cpuLimit = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "500m";
        description = ''
          CPU ceiling, and the one to leave unset by default. A CPU limit THROTTLES: the container
          is descheduled for the rest of each period once it is spent, which turns a burst of work
          into latency rather than into a failure somebody notices.
        '';
      };
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment this deployment adds, merged over whatever the catalogue sets. Values only --
        anything secret belongs in a Secret and is wired by NAME through `credentials`.
      '';
    };

    credentials = {
      secret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          NAME of the Secret that delivers every credential variable the catalogue says this tool
          reads. Named rather than carried: nothing in this repository can hold a secret's
          contents, which is what makes a declaration written here publishable.

          The two halves check each other. A tool that reads credentials must name a Secret and a
          tool that reads none may not, so a missing credential is an eval error rather than a pod
          that starts anyway and fails somewhere further away.
        '';
      };

      keys = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = lib.literalExpression ''{ JWT_SECRET = "jwt-signing-key"; }'';
        description = ''
          Where inside that Secret each variable's value lives, as `<VARIABLE> = "<key>"`, for the
          variables whose key is not simply their own name. Only variables the catalogue lists are
          mappable: this renames a KEY, it cannot invent a variable the software never reads.
        '';
      };
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
          credentials.secret = "example-snippets-env";
          probes.startup.failureThreshold = 60;
          resources.memoryLimit = "256Mi";
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
    nixidy.assertions =
      stateAssertions ++ probeAssertions ++ credentialAssertions ++ anchorAssertions ++ slotAssertions;
    nixidy.warnings = warnings;
  };
}
