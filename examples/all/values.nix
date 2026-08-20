# Placeholder values for the cluster module — the file that makes the render check real.
# `nix flake check` renders the whole surface from here, so a module that stops evaluating, or that
# grows a required value nobody supplies, fails in CI rather than in somebody's cluster.
#
# NOTHING HERE IS REAL. Every namespace, path, name, number, host and image is invented for this
# file, and no credential appears in any form — only the NAME of a Secret that would hold one and
# the NAMES of the variables it fills.
#
# EVERY TERM THE MODULE HAS IS EXERCISED HERE, on purpose: `examples/parity/grammar.nix` writes the
# same two workloads out by hand in the grammar underneath, and the parity check renders both and
# diffs the bytes. A term nothing here sets is a term that comparison cannot see.
#
# The two declarations are chosen to cover the paths that differ in what gets RENDERED rather than
# merely in what evaluates:
#
#   - a tool that writes a database and therefore cannot roll, anchoring the shared namespace,
#     sleeping behind a wake front, taking its credentials from a named Secret, stamping the
#     hardening classes it is catalogued as tolerating, and lengthening one probe budget because
#     the request that wakes it is held open while it boots;
#   - a tool that writes nothing at all, joining that namespace rather than creating a second one,
#     permanently resident, pinned by digest, bounded by requests and a limit — and ADOPTING an
#     object that is already running, which is why it renders NO securityContext either: a live pod
#     acquires one by being replaced.
{
  # Required by the nixidy environment itself, not by any module here.
  nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
  nixidy.target.branch = "main";

  nixdev.clusterPlatform = {
    namespace = "example-devtools";
    project = "example-swe";
  };

  # Writes one directory, so it may not roll; backs it on a node path, which is the other half the
  # catalogue cannot supply. Sleeps, and names the front that wakes it — without which the module
  # warns that nothing brings it back.
  nixdev.applications.example-snippets = {
    app = "bytestash";
    version = "0.0.0";
    createNamespace = true;
    exposure = "nb";
    slot = 40;
    scaling = "scale-to-zero";
    wake = "keda";
    state.data.hostPath = "/example/state/snippets";

    # Switches and identifiers, never secrets: an issuer URL and a client id say WHICH identity
    # provider one installation talks to, and neither of them authenticates anything.
    env = {
      ALLOW_NEW_ACCOUNTS = "false";
      DISABLE_INTERNAL_ACCOUNTS = "true";
      OIDC_ENABLED = "true";
      OIDC_DISPLAY_NAME = "Example ID";
      OIDC_ISSUER_URL = "https://id.example.com";
      OIDC_CLIENT_ID = "00000000-0000-0000-0000-000000000000";
      TOKEN_EXPIRY = "2w";
    };

    # The Secret is NAMED and never carried. One of the two variables the catalogue lists is filled
    # from a key spelled differently inside the Secret, which is the whole reason `keys` exists; the
    # other takes its own name.
    credentials = {
      secret = "example-snippets-env";
      keys.JWT_SECRET = "jwt-signing-key";
    };

    # THE CLUSTER'S PATIENCE, not the software's. The catalogue already says a Node process opening
    # a database is slow to answer the first time; what is different HERE is that the request which
    # woke the pod is being held open by the wake front while it boots, so the startup budget is
    # five times the software's own. Everything else is left to the catalogue.
    probes.startup.failureThreshold = 60;

    # A ceiling that throttles rather than kills, stated here only because a declaration is the one
    # place a CPU limit can be stated at all.
    resources.cpuLimit = "500m";
  };

  # Writes nothing, so it backs nothing and the assertion reads that back as "backs none". Joins the
  # namespace above rather than anchoring a second one, and carries a whole reference so two syncs
  # of an identical tree run identical code.
  nixdev.applications.example-workbench = {
    app = "cyberchef";
    version = "0.0.0";
    image = "registry.example.com/example-org/example-workbench:0.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000";
    exposure = "public";
    slot = 41;

    # TAKES OVER an object that is already running rather than creating one, which is that
    # cluster's history and nothing about the software: the same tool is adopted here and created
    # fresh somewhere else. It renders the Application with server-side apply and diff, so what is
    # compared is what the API server actually holds.
    adopt = true;

    # NO securityContext on this pod, and the module warns about it. The same position, one layer
    # down and written down rather than defaulted into: the objects this declaration takes over
    # were created before the classes existed, a pod acquires a securityContext only by being
    # replaced, and the commit that adopts an app is not the commit that is allowed to roll it.
    harden = false;

    resources = {
      cpuRequest = "10m";
      memoryRequest = "16Mi";
      memoryLimit = "128Mi";
    };
  };
}
