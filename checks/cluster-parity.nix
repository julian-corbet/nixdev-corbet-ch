# THE ADOPTION BAR, checked rather than claimed.
#
# A consumer that already runs these tools does not adopt this repository by rewriting its cluster.
# It rewrites its DECLARATION — from a hand-written block in the grammar underneath to a nixdev
# workload — and the manifests must not move by a single byte. Anything else is a server-side-apply
# diff, which is a sync, and for the workload here that cannot roll a sync is downtime: the old pod
# stops before the new one starts, because a database file has one writer.
#
# So this check renders TWO environments — `examples/all/values.nix` through the translator, and
# `examples/parity/grammar.nix` written out by hand with no nixdev module composed at all — and
# diffs the trees. It is the only check in this repository that can catch the failure that matters
# most to an adopter: a term the catalogue knows about, that the translator never passes on.
#
# WHY THE DIFF AND NOT A LIST OF ASSERTIONS. A field-by-field comparison only ever finds the fields
# somebody remembered to compare, and the fields nobody remembered are exactly the ones a translator
# drops. A whole-tree diff has no such blind spot: every object, every key, in both directions.
{ pkgs, lib, nixidy, appsModule, clusterModule, values, grammar }:

let
  mkEnv = modules: (nixidy.lib.mkEnv { inherit pkgs modules; }).environmentPackage;

  translated = mkEnv [ appsModule clusterModule (import values) ];
  handWritten = mkEnv [ appsModule (import grammar) ];
in
pkgs.runCommand "nixdev-cluster-parity"
{
  nativeBuildInputs = [ pkgs.diffutils ];
  inherit translated handWritten;
} ''
  set -euo pipefail

  echo "== the translator's tree and the hand-written grammar tree are the same bytes =="
  if diff -r "$handWritten" "$translated"; then
    echo "nixdev: a nixdev declaration renders exactly what the hand-written grammar block renders"
  else
    echo "" >&2
    echo "The two trees differ. Read the diff above as: '<' is what a hand-written grammar block" >&2
    echo "produces, '>' is what this repository's translator produces. Either the translator has" >&2
    echo "stopped passing a term on, or the catalogue and the golden file have drifted apart." >&2
    echo "An adopter reading this diff would be reading their own rollout." >&2
    exit 1
  fi

  touch $out
''
