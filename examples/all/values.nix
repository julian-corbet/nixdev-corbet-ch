# Placeholder values for the cluster module — the file that makes the render check real.
# `nix flake check` renders the whole surface from here, so a module that stops evaluating, or that
# grows a required value nobody supplies, fails in CI rather than in somebody's cluster.
#
# NOTHING HERE IS REAL. Every namespace, path, name, number and image is invented for this file, and
# no credential appears in any form — only the NAME of a Secret that would hold one.
#
# The two declarations are chosen to cover the paths that differ in what gets RENDERED rather than
# merely in what evaluates:
#
#   - a tool that writes a database and therefore cannot roll, anchoring the shared namespace,
#     sleeping behind a wake front, and taking its whole environment from a named Secret;
#   - a tool that writes nothing at all, joining that namespace rather than creating a second one,
#     permanently resident, and pinned by digest — which is what the grammar asks for and what the
#     first one deliberately does not do.
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
    envFromSecrets = [ "example-snippets-env" ];
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
  };
}
