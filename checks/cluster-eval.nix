# Proves the cluster module resolves what it claims and REFUSES what it claims to refuse, both
# directions, through the real renderer and the real app grammar.
#
# Both halves matter and neither is enough alone. A guard nobody has watched fire is a comment; a
# guard that fires on everything is a wall. So every case below is a complete, otherwise-valid
# surface with exactly one thing wrong, and the `control` case is the same shape with nothing wrong
# and MUST render -- without it, a typo in the shared base would make every other case "pass" for
# the wrong reason.
#
# SEVERAL OF THE REFUSALS ARE NOT GUARDS AT ALL. Naming a tool the catalogue does not hold, leaving
# out the version, writing a securityContext by hand, and asking for a device by name all fail as a
# type error or a missing option -- not as assertions. That is the stronger kind: a boundary nobody
# has to remember, because it is unwritable rather than refused. `tryEval` cannot tell those apart
# from a guard, so the ones that ARE guards additionally have their message asserted by content.
{ pkgs, lib, nixidy, appsModule, clusterModule, values }:

let
  base = import values;

  mkEnv = v: nixidy.lib.mkEnv {
    inherit pkgs;
    modules = [ appsModule clusterModule v ];
  };

  # `tryEval` alone forces only WHNF. Forcing the derivation path is what actually runs the module
  # system's type checks and the assertions underneath.
  renders = v: (builtins.tryEval (builtins.seq (mkEnv v).environmentPackage.drvPath true)).success;

  # An assertion fired, AND it is the one meant: a refusal that happens for an unrelated reason is
  # a false pass, which is exactly the failure this repository's checks exist to make impossible.
  failsWith = infix: v:
    let
      r = builtins.tryEval (lib.any
        (a: !a.assertion && lib.hasInfix infix a.message)
        (mkEnv v).config.nixidy.assertions);
    in
    r.success && r.value;

  # A surface with nothing declared at all, to prove the module is inert until something asks.
  emptyCfg = (mkEnv {
    nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
    nixidy.target.branch = "main";
  }).config;

  goodCfg = (mkEnv base).config;
  snippets = goodCfg.nixk3s.apps.example-snippets;
  workbench = goodCfg.nixk3s.apps.example-workbench;

  with' = f: lib.recursiveUpdate base f;

  results = {
    # ── The control, and the floor ────────────────────────────────────────────────────────────
    "the example surface renders -- without this every refusal below could pass for the wrong reason" =
      renders base;

    "an undeclared surface renders no apps at all, rather than a default one" =
      emptyCfg.nixk3s.apps == { };

    "both declared workloads reach the grammar" =
      lib.sort (a: b: a < b) (lib.attrNames goodCfg.nixk3s.apps)
      == [ "example-snippets" "example-workbench" ];

    "the catalogue supplies the port, and the declaration never states one" =
      snippets.ports.http.number == 5000 && workbench.ports.http.number == 8080;

    "a version becomes the tag, and a whole reference overrides it" =
      snippets.image == "ghcr.io/jordan-dalby/bytestash:0.0.0"
      && lib.hasInfix "@sha256:" workbench.image;

    "the catalogue supplies WHERE a directory lives and the declaration supplies WHAT BACKS IT" =
      snippets.state.data.mountPath == "/data/snippets"
      && snippets.state.data.hostPath == "/example/state/snippets";

    # A node path that is missing must stop the pod, not be conjured: an empty directory is a
    # snippet store that comes up looking healthy having lost everything.
    "a node path defaults to one that must already exist" =
      snippets.state.data.hostPathType == "Directory";

    "a tool that writes nothing renders no state, so nothing forces it to stop before it starts" =
      workbench.state == { };

    # ── The four split fields, each read back on both halves ──────────────────────────────────
    "the catalogue decides WHICH probes exist" =
      lib.sort (a: b: a < b) (lib.attrNames (lib.filterAttrs (_: p: p != null) snippets.probes))
      == [ "liveness" "readiness" "startup" ]
      && lib.sort (a: b: a < b) (lib.attrNames (lib.filterAttrs (_: p: p != null) workbench.probes))
      == [ "liveness" "readiness" ];

    "a probe asks what the catalogue says it asks, on the catalogue's own port" =
      snippets.probes.readiness.path == "/" && snippets.probes.readiness.port == "http"
      && workbench.probes.liveness.path == "/" && workbench.probes.liveness.port == "http";

    # The whole point of splitting the budget out: the declaration moved ONE number and inherited
    # the rest, rather than restating a block it does not own.
    "a declaration overrides one budget field and inherits the others" =
      snippets.probes.startup.failureThreshold == 60
      && snippets.probes.startup.periodSeconds == 5
      && snippets.probes.startup.timeoutSeconds == 5;

    "an unbudgeted probe is entirely the catalogue's" =
      snippets.probes.liveness.periodSeconds == 20
      && snippets.probes.liveness.timeoutSeconds == 5
      && workbench.probes.liveness.timeoutSeconds == 1;

    "a Secret is NAMED by the declaration and its variables come from the catalogue" =
      snippets.secrets ? example-snippets-env
      && snippets.secrets.example-snippets-env.secret == "example-snippets-env"
      && lib.sort (a: b: a < b) (lib.attrNames snippets.secrets.example-snippets-env.env)
      == [ "JWT_SECRET" "OIDC_CLIENT_SECRET" ];

    "a variable takes its own name as the key unless the declaration renames it" =
      snippets.secrets.example-snippets-env.env.JWT_SECRET == "jwt-signing-key"
      && snippets.secrets.example-snippets-env.env.OIDC_CLIENT_SECRET == "OIDC_CLIENT_SECRET";

    "a tool that reads no credential names no Secret" =
      workbench.secrets == { };

    "the hardening CLASSES come from the catalogue, and only the decision to stamp them is declared" =
      snippets.security.capabilitiesDrop == [ "ALL" ]
      && snippets.security.allowPrivilegeEscalation == false
      && snippets.security.seccomp == "RuntimeDefault"
      # Never established for this image, so no field at all -- a `false` here would read as a
      # finding rather than as an open question.
      && snippets.security.readOnlyRootFilesystem == null;

    "`harden = false` renders no securityContext, which is what an adoption needs" =
      workbench.security.capabilitiesDrop == [ ]
      && workbench.security.allowPrivilegeEscalation == null
      && workbench.security.seccomp == null;

    # Whether an object is already there is that cluster's history, not the software's nature, so
    # the catalogue has no say and the default is the one that creates rather than takes over.
    "adoption is a declaration's own term, and unstated means creating rather than taking over" =
      workbench.adopt == true && snippets.adopt == false;

    "resources are four named scalars, and an unset one renders no key" =
      workbench.resources.requests == { cpu = "10m"; memory = "16Mi"; }
      && workbench.resources.limits == { memory = "128Mi"; }
      && snippets.resources.requests == { }
      && snippets.resources.limits == { cpu = "500m"; };

    # ── Unwritable, not merely refused ────────────────────────────────────────────────────────
    "a tool the catalogue does not hold is not a value this option has" =
      !renders (with' { nixdev.applications.example-snippets.app = "nonesuch"; });

    "a workload with no version is refused, because a floating tag is not a default anyone can pick" =
      !renders {
        nixidy.target.repository = "https://example.com/x.git";
        nixidy.target.branch = "main";
        nixdev.applications.x = { app = "cyberchef"; };
      };

    # The classes are the catalogue's. A declaration that could write `seccomp = "Unconfined"` could
    # loosen a pod below what the software is catalogued as tolerating, which is the one direction
    # this vocabulary must not have.
    "a declaration cannot write a securityContext of its own" =
      !renders (with' { nixdev.applications.example-workbench.security.seccomp = "Unconfined"; });

    # `resources` names four scalars rather than taking the grammar's map, and this is why: a
    # free-form resource map is how a device request -- a catalogue fact about the software -- gets
    # in through a deployment.
    "a declaration cannot ask for a device by name" =
      !renders (with' {
        nixdev.applications.example-workbench.resources.requests."example.com/gpu" = "1";
      });

    # ── The guards, each with its message asserted ────────────────────────────────────────────
    "backing a directory the tool does not write is refused" =
      failsWith "must back every directory it writes"
        (with' { nixdev.applications.example-workbench.state.data.hostPath = "/example/nope"; });

    "leaving a directory the tool DOES write unbacked is refused" =
      failsWith "must back every directory it writes"
        (lib.recursiveUpdate base { nixdev.applications.example-snippets.state = lib.mkForce { }; });

    "a directory backed by both a claim and a node path is refused" =
      failsWith "EITHER an existing claim OR a node path"
        (with' { nixdev.applications.example-snippets.state.data.claim = "example-claim"; });

    "budgeting a probe the software does not warrant is refused" =
      failsWith "does not warrant"
        (with' { nixdev.applications.example-workbench.probes.startup.periodSeconds = 5; });

    "a tool that reads credentials and names no Secret is refused" =
      failsWith "names no Secret to deliver them"
        (lib.recursiveUpdate base {
          nixdev.applications.example-snippets.credentials.secret = lib.mkForce null;
        });

    "a tool that reads none and names one anyway is refused" =
      failsWith "reads no credential"
        (with' { nixdev.applications.example-workbench.credentials.secret = "example-nothing"; });

    "renaming the key of a variable the software never reads is refused" =
      failsWith "cannot invent the variable"
        (with' { nixdev.applications.example-snippets.credentials.keys.NOT_A_VARIABLE = "x"; });

    "two workloads anchoring one namespace is refused" =
      failsWith "Exactly one workload may create a namespace"
        (with' { nixdev.applications.example-workbench.createNamespace = true; });

    "two workloads on one slot is refused" =
      failsWith "is claimed by 2 applications"
        (with' { nixdev.applications.example-workbench.slot = 40; });

    # ── The warnings that are not refusals ────────────────────────────────────────────────────
    # Sleeping with nothing to wake it is a real mistake and still not an eval error: which front a
    # cluster runs is its own business, and a repository that refused the combination would be
    # legislating routing it cannot see.
    "scale-to-zero with no wake front warns rather than refuses" =
      let cfg = (mkEnv (with' { nixdev.applications.example-snippets.wake = lib.mkForce null; })).config;
      in lib.any (w: w.when && lib.hasInfix "nothing brings it back" w.message) cfg.nixidy.warnings;

    # And a pod left looser than the software needs stays COUNTABLE. Adoption is a legitimate reason
    # to render no securityContext and a bad reason to stop noticing.
    "a workload that declines the hardening it tolerates warns" =
      lib.any
        (w: w.when && lib.hasInfix "renders no securityContext" w.message)
        (mkEnv base).config.nixidy.warnings;
  };

  failed = lib.filter (n: !results.${n}) (lib.attrNames results);
in
pkgs.runCommand "nixdev-cluster-eval" { } (
  if failed == [ ]
  then ''
    echo "nixdev: all ${toString (lib.length (lib.attrNames results))} cluster-eval properties hold"
    touch $out
  ''
  else ''
    echo "nixdev cluster-eval FAILED (${toString (lib.length failed)}/${toString (lib.length (lib.attrNames results))}):" >&2
    ${lib.concatMapStringsSep "\n" (n: ''echo "  - ${n}" >&2'') failed}
    exit 1
  ''
)
