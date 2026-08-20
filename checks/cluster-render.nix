# Reads the tier's promises back off the RENDERED BYTES, not off the options that produced them.
#
# The eval check proves the module resolves and refuses. This one proves the manifests that come
# out say what the module claims — which is a different question, and the only one a cluster ever
# sees. An option can be correct and the rendering still wrong.
{ pkgs, lib, nixidy, appsModule, clusterModule, values }:

let
  env = nixidy.lib.mkEnv {
    inherit pkgs;
    modules = [ appsModule clusterModule (import values) ];
  };
in
pkgs.runCommand "nixdev-cluster-render"
{
  nativeBuildInputs = [ pkgs.yq-go ];
  manifests = env.environmentPackage;
} ''
  set -euo pipefail
  fail=0
  check() { # name expected actual
    if [ "$2" = "$3" ]; then echo "  ok   $1: $3"
    else echo "  FAIL $1: expected '$2', got '$3'"; fail=1; fi
  }
  y() { yq -r "$1" "$2"; }

  echo "== the environment renders both workloads and nothing else =="
  rendered=$(ls "$manifests" | sort | tr '\n' ' ' | sed 's/ $//')
  check "rendered apps" "apps example-snippets example-workbench" "$rendered"

  snip="$manifests/example-snippets"
  work="$manifests/example-workbench"

  echo "== the catalogue's ports reach the container, and the declaration never stated one =="
  check "snippets port" "5000" "$(y '.spec.template.spec.containers[0].ports[0].containerPort' $snip/Deployment-example-snippets.yaml)"
  check "workbench port" "8080" "$(y '.spec.template.spec.containers[0].ports[0].containerPort' $work/Deployment-example-workbench.yaml)"

  echo "== a database file is single-writer, so its Deployment may not roll =="
  check "snippets strategy" "Recreate" "$(y '.spec.strategy.type' $snip/Deployment-example-snippets.yaml)"
  # An absent `replicas` IS one -- Kubernetes' own default. Asserting it is unset is the honest
  # form: the grammar deliberately does not stamp a count on a workload that cannot have two.
  check "snippets replicas unset (defaults to one)" "null" "$(y '.spec.replicas' $snip/Deployment-example-snippets.yaml)"

  echo "== and a workload that writes nothing carries no volume at all =="
  check "workbench volumes" "null" "$(y '.spec.template.spec.volumes' $work/Deployment-example-workbench.yaml)"
  check "snippets mountPath" "/data/snippets" "$(y '.spec.template.spec.containers[0].volumeMounts[0].mountPath' $snip/Deployment-example-snippets.yaml)"

  echo "== the image is a tag when a version was given and a whole reference when one was =="
  check "snippets image" "ghcr.io/jordan-dalby/bytestash:0.0.0" "$(y '.spec.template.spec.containers[0].image' $snip/Deployment-example-snippets.yaml)"
  check "workbench digest-pinned" "true" "$(y '.spec.template.spec.containers[0].image' $work/Deployment-example-workbench.yaml | grep -q '@sha256:' && echo true || echo false)"

  echo "== no address is invented here: the Service is a plain ClusterIP with nothing pinned =="
  for f in $snip/Service-example-snippets.yaml $work/Service-example-workbench.yaml; do
    check "$(basename $f) type" "ClusterIP" "$(y '.spec.type' $f)"
    check "$(basename $f) no pinned IP" "null" "$(y '.spec.clusterIP' $f)"
    check "$(basename $f) no nodePort" "null" "$(y '.spec.ports[0].nodePort' $f)"
  done

  # `-L` is load-bearing: the rendered tree is SYMLINKS into the store, so a plain `-type f`
  # matches nothing and returns a confident zero. A count that can only ever be zero is worse than
  # no check, because it passes the moment somebody expects zero.
  echo "== exactly one workload anchors the shared namespace, and only one =="
  check "namespaces rendered" "1" "$(find -L $manifests -name 'Namespace-*.yaml' -type f | wc -l)"
  check "which namespace"    "example-devtools" "$(y '.metadata.name' $snip/Namespace-example-devtools.yaml)"

  if [ "$fail" -ne 0 ]; then
    echo "rendered output does not match the tier's promises" >&2
    exit 1
  fi
  echo "nixdev: the rendered tree matches every promise asserted here"
  touch $out
''
