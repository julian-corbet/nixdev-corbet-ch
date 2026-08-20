# The same two workloads as `examples/all/values.nix`, written out BY HAND in the grammar
# underneath — `nixk3s.apps.<name>`, with no nixdev module composed at all.
#
# WHAT IT IS FOR. `checks/cluster-parity.nix` renders this and the translator's declaration into two
# separate environments and diffs the bytes. Byte-identical is the bar rather than equivalent,
# because the consumer this repository is written for adopts apps that are ALREADY RUNNING: a
# rendered manifest that differs from the live one is a server-side-apply diff, a diff is a sync,
# and for the workload below that cannot roll a sync is downtime. So the question the check answers
# is not "does the translator produce something reasonable" but "can this repository's vocabulary
# say everything a hand-written grammar block says, exactly".
#
# IT IS A GOLDEN FILE, and it is meant to be read as one: every value here that the translator gets
# from `lib/applications.nix` is written out literally — the ports, the mount path, the probe
# endpoints and budgets, the hardening classes, the credential variable names. Reading the two files
# side by side is the clearest statement of what the catalogue actually knows.
#
# NOTHING HERE IS REAL either. Same invented namespace, paths, host and Secret name as the
# declaration it mirrors.
{
  nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
  nixidy.target.branch = "main";

  # ── The stateful one ────────────────────────────────────────────────────────────────────────
  nixk3s.apps.example-snippets = {
    namespace = "example-devtools";
    createNamespace = true;
    project = "example-swe";

    image = "ghcr.io/jordan-dalby/bytestash:0.0.0";
    ports.http.number = 5000;

    exposure = "nb";
    scaling = "scale-to-zero";
    wake = "keda";

    state.data = {
      mountPath = "/data/snippets";
      hostPath = "/example/state/snippets";
    };

    env = {
      ALLOW_NEW_ACCOUNTS = "false";
      DISABLE_INTERNAL_ACCOUNTS = "true";
      OIDC_ENABLED = "true";
      OIDC_DISPLAY_NAME = "Example ID";
      OIDC_ISSUER_URL = "https://id.example.com";
      OIDC_CLIENT_ID = "00000000-0000-0000-0000-000000000000";
      TOKEN_EXPIRY = "2w";
    };

    secrets.example-snippets-env.env = {
      JWT_SECRET = "jwt-signing-key";
      OIDC_CLIENT_SECRET = "OIDC_CLIENT_SECRET";
    };

    security = {
      seccomp = "RuntimeDefault";
      allowPrivilegeEscalation = false;
      capabilitiesDrop = [ "ALL" ];
    };

    resources.limits.cpu = "500m";

    probes.startup = {
      port = "http";
      path = "/";
      periodSeconds = 5;
      failureThreshold = 60;
      timeoutSeconds = 5;
    };
    probes.readiness = {
      port = "http";
      path = "/";
      periodSeconds = 10;
      failureThreshold = 6;
      timeoutSeconds = 5;
    };
    probes.liveness = {
      port = "http";
      path = "/";
      periodSeconds = 20;
      failureThreshold = 6;
      timeoutSeconds = 5;
    };
  };

  # ── The stateless one ───────────────────────────────────────────────────────────────────────
  nixk3s.apps.example-workbench = {
    namespace = "example-devtools";
    project = "example-swe";

    image = "registry.example.com/example-org/example-workbench:0.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000";
    ports.http.number = 8080;

    exposure = "public";

    resources.requests = {
      cpu = "10m";
      memory = "16Mi";
    };
    resources.limits.memory = "128Mi";

    probes.readiness = {
      port = "http";
      path = "/";
      periodSeconds = 10;
      failureThreshold = 6;
    };
    probes.liveness = {
      port = "http";
      path = "/";
      periodSeconds = 20;
      failureThreshold = 6;
    };
  };
}
