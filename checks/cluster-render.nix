# Reads the tier's promises back off the RENDERED BYTES, not off the options that produced them.
#
# The eval check proves the module resolves and refuses. The parity check proves the bytes match a
# hand-written grammar block. This one proves the manifests SAY what the module claims — which is a
# different question from either, and the only one a cluster ever sees. An option can be correct,
# and the parity file can be wrong in exactly the same way as the translator, and the rendering
# still not mean what the catalogue says it means.
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
  snipd="$snip/Deployment-example-snippets.yaml"
  workd="$work/Deployment-example-workbench.yaml"
  # Every container-level assertion below reads the app's OWN container by name rather than by
  # index: an index is right until something else joins the pod, and then it is silently wrong.
  sc='.spec.template.spec.containers[] | select(.name == "example-snippets")'
  wc='.spec.template.spec.containers[] | select(.name == "example-workbench")'

  echo "== the catalogue's ports reach the container, and the declaration never stated one =="
  check "snippets port" "5000" "$(y "$sc.ports[0].containerPort" $snipd)"
  check "workbench port" "8080" "$(y "$wc.ports[0].containerPort" $workd)"

  echo "== a database file is single-writer, so its Deployment may not roll =="
  check "snippets strategy" "Recreate" "$(y '.spec.strategy.type' $snipd)"
  # An absent `replicas` IS one -- Kubernetes' own default. Asserting it is unset is the honest
  # form: the grammar deliberately does not stamp a count on a workload that cannot have two.
  check "snippets replicas unset (defaults to one)" "null" "$(y '.spec.replicas' $snipd)"

  echo "== and a workload that writes nothing carries no volume at all =="
  check "workbench volumes" "null" "$(y '.spec.template.spec.volumes' $workd)"
  check "snippets mountPath" "/data/snippets" "$(y "$sc.volumeMounts[0].mountPath" $snipd)"
  # A node path that is not there must stop the pod. `DirectoryOrCreate` would hand this app an
  # empty directory and a clean bill of health, having lost every snippet in it.
  check "snippets hostPath type" "Directory" "$(y '.spec.template.spec.volumes[0].hostPath.type' $snipd)"

  echo "== the image is a tag when a version was given and a whole reference when one was =="
  check "snippets image" "ghcr.io/jordan-dalby/bytestash:0.0.0" "$(y "$sc.image" $snipd)"
  check "workbench digest-pinned" "true" "$(y "$wc.image" $workd | grep -q '@sha256:' && echo true || echo false)"

  echo "== probes: the catalogue decides which exist and what they ask, the declaration budgets =="
  check "snippets readiness path"   "/"  "$(y "$sc.readinessProbe.httpGet.path" $snipd)"
  check "snippets readiness port"   "5000" "$(y "$sc.readinessProbe.httpGet.port" $snipd)"
  check "snippets readiness period" "10" "$(y "$sc.readinessProbe.periodSeconds" $snipd)"
  check "snippets liveness period"  "20" "$(y "$sc.livenessProbe.periodSeconds" $snipd)"
  # The one number the declaration moved, and the two beside it that it did not.
  check "snippets startup threshold (declared)"  "60" "$(y "$sc.startupProbe.failureThreshold" $snipd)"
  check "snippets startup period (catalogued)"   "5"  "$(y "$sc.startupProbe.periodSeconds" $snipd)"
  check "snippets startup timeout (catalogued)"  "5"  "$(y "$sc.startupProbe.timeoutSeconds" $snipd)"
  # A Node process with a database open answers slowly; a file server does not. Neither number is
  # a cluster's opinion, which is why both come from the catalogue and they differ.
  check "workbench readiness timeout" "1" "$(y "$wc.readinessProbe.timeoutSeconds" $workd)"
  # A static bundle has no slow first boot, so it renders no startup probe at all.
  check "workbench startup probe absent" "null" "$(y "$wc.startupProbe" $workd)"
  # Nobody asked for a delay, so nobody waits. An `initialDelaySeconds: 0` in the manifest would be
  # a field this repository stamped for no reason.
  check "no initial delay stamped" "null" "$(y "$sc.readinessProbe.initialDelaySeconds" $snipd)"

  echo "== hardening: classes from the catalogue, the decision to stamp them from the declaration =="
  check "snippets drops all capabilities" "ALL"   "$(y "$sc.securityContext.capabilities.drop[0]" $snipd)"
  check "snippets never escalates"        "false" "$(y "$sc.securityContext.allowPrivilegeEscalation" $snipd)"
  check "snippets seccomp is on the POD"  "RuntimeDefault" "$(y '.spec.template.spec.securityContext.seccompProfile.type' $snipd)"
  # Never established for this image, so no field at all rather than a `false` that reads as a
  # finding somebody made.
  check "snippets states nothing about the root filesystem" "null" "$(y "$sc.securityContext.readOnlyRootFilesystem" $snipd)"
  # `harden = false`: the adoption position, and it must render NOTHING rather than something empty.
  check "workbench container securityContext absent" "null" "$(y "$wc.securityContext" $workd)"
  check "workbench pod securityContext absent"       "null" "$(y '.spec.template.spec.securityContext' $workd)"

  echo "== resources: named scalars in, and an unset one renders no key =="
  check "workbench cpu request"    "10m"   "$(y "$wc.resources.requests.cpu" $workd)"
  check "workbench memory request" "16Mi"  "$(y "$wc.resources.requests.memory" $workd)"
  check "workbench memory limit"   "128Mi" "$(y "$wc.resources.limits.memory" $workd)"
  check "workbench has no cpu limit to throttle it" "null" "$(y "$wc.resources.limits.cpu" $workd)"
  check "snippets cpu limit"       "500m"  "$(y "$sc.resources.limits.cpu" $snipd)"
  check "snippets requests nothing" "null" "$(y "$sc.resources.requests" $snipd)"

  echo "== a credential is REFERENCED, never carried: no value of one appears in the tree =="
  check "JWT_SECRET is a secretKeyRef" "example-snippets-env" \
    "$(y "$sc.env[] | select(.name == \"JWT_SECRET\") | .valueFrom.secretKeyRef.name" $snipd)"
  check "and it reads the renamed key" "jwt-signing-key" \
    "$(y "$sc.env[] | select(.name == \"JWT_SECRET\") | .valueFrom.secretKeyRef.key" $snipd)"
  check "a variable not renamed keys on its own name" "OIDC_CLIENT_SECRET" \
    "$(y "$sc.env[] | select(.name == \"OIDC_CLIENT_SECRET\") | .valueFrom.secretKeyRef.key" $snipd)"
  check "no credential variable carries an inline value" "null" \
    "$(y "$sc.env[] | select(.name == \"JWT_SECRET\") | .value" $snipd)"
  # The blunt form is what this repository replaced: `envFrom` hands the process whatever the Secret
  # happens to contain, including a key somebody adds next year.
  check "nothing is loaded wholesale" "null" "$(y "$sc.envFrom" $snipd)"
  # A tool that reads no credential must reference no Secret at all -- not an empty block.
  check "workbench references no Secret" "0" \
    "$(y "[$wc.env[]? | select(.valueFrom.secretKeyRef)] | length" $workd)"

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
