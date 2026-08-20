# Proves the cluster module resolves what it claims and REFUSES what it claims to refuse, both
# directions, through the real renderer and the real app grammar.
#
# Both halves matter and neither is enough alone. A guard nobody has watched fire is a comment; a
# guard that fires on everything is a wall. So every case below is a complete, otherwise-valid
# surface with exactly one thing wrong, and the `control` case is the same shape with nothing wrong
# and MUST render -- without it, a typo in the shared base would make every other case "pass" for
# the wrong reason.
#
# TWO OF THE REFUSALS ARE NOT GUARDS AT ALL. Naming a tool the catalogue does not hold, and leaving
# out the version, fail as a type error and a missing required option -- not as assertions. That is
# the stronger kind: a boundary nobody has to remember, because it is unwritable rather than
# refused. `tryEval` cannot tell those apart from a guard, so the ones that ARE guards additionally
# have their message asserted by content.
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
    let r = builtins.tryEval (lib.any
      (a: !a.assertion && lib.hasInfix infix a.message)
      (mkEnv v).config.nixidy.assertions);
    in r.success && r.value;

  # A surface with nothing declared at all, to prove the module is inert until something asks.
  emptyCfg = (mkEnv {
    nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
    nixidy.target.branch = "main";
  }).config;

  goodCfg = (mkEnv base).config;

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
      goodCfg.nixk3s.apps.example-snippets.ports.http.number == 5000
      && goodCfg.nixk3s.apps.example-workbench.ports.http.number == 8080;

    "a version becomes the tag, and a whole reference overrides it" =
      goodCfg.nixk3s.apps.example-snippets.image == "ghcr.io/jordan-dalby/bytestash:0.0.0"
      && lib.hasInfix "@sha256:" goodCfg.nixk3s.apps.example-workbench.image;

    "the catalogue supplies WHERE a directory lives and the declaration supplies WHAT BACKS IT" =
      goodCfg.nixk3s.apps.example-snippets.state.data.mountPath == "/data/snippets"
      && goodCfg.nixk3s.apps.example-snippets.state.data.hostPath == "/example/state/snippets";

    "a tool that writes nothing renders no state, so nothing forces it to stop before it starts" =
      goodCfg.nixk3s.apps.example-workbench.state == { };

    "a Secret is named and never carried" =
      goodCfg.nixk3s.apps.example-snippets.secrets ? example-snippets-env
      && goodCfg.nixk3s.apps.example-snippets.secrets.example-snippets-env.envFrom;

    # ── Unwritable, not merely refused ────────────────────────────────────────────────────────
    "a tool the catalogue does not hold is not a value this option has" =
      !renders (with' { nixdev.applications.example-snippets.app = "nonesuch"; });

    "a workload with no version is refused, because a floating tag is not a default anyone can pick" =
      !renders {
        nixidy.target.repository = "https://example.com/x.git";
        nixidy.target.branch = "main";
        nixdev.applications.x = { app = "cyberchef"; };
      };

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

    "two workloads anchoring one namespace is refused" =
      failsWith "Exactly one workload may create a namespace"
        (with' { nixdev.applications.example-workbench.createNamespace = true; });

    "two workloads on one slot is refused" =
      failsWith "is claimed by 2 applications"
        (with' { nixdev.applications.example-workbench.slot = 40; });

    # ── The warning that is not a refusal ─────────────────────────────────────────────────────
    # Sleeping with nothing to wake it is a real mistake and still not an eval error: which front a
    # cluster runs is its own business, and a repository that refused the combination would be
    # legislating routing it cannot see.
    "scale-to-zero with no wake front warns rather than refuses" =
      let cfg = (mkEnv (with' { nixdev.applications.example-snippets.wake = lib.mkForce null; })).config;
      in lib.any (w: w.when && lib.hasInfix "nothing brings it back" w.message) cfg.nixidy.warnings;
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
