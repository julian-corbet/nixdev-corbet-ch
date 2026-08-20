# nixdev

A small NixOS flake module that declares operator tooling — cloud CLIs, infrastructure-as-code
tools, Kubernetes clients, language toolchains, Python tooling, and build utilities — per host, replacing the
manual installation of hundreds of packages with per-group declarations that resolve to the right
package name on each platform.

The problem this solves: a real workstation's "dev tools" set grows invisibly, installed by hand
whenever a tool is needed. On the machine this module was extracted from, 460 packages were
explicitly installed against roughly 30 declared groups. This module is how that gap closes: you
declare *which groups* you want (cloud providers, Kubernetes clients, Python tooling), and the
resolution to actual package names — and the decision of what comes from where (nixpkgs vs AUR,
or where no nixpkgs equivalent exists) — becomes auditable and portable.

## What nixdev is

A platform-neutral NixOS module that owns one concern: declaring *which* operator tools a host
needs, grouped by use case, and resolving each group to package names. It exists in three forms:

- `nixdev.nix`: the declarative policy, selection logic, and the single source of truth for
  per-platform package name mapping (via `lib/tools.nix`).
- `modules/nixos.nix`: the NixOS backend, which installs via `environment.systemPackages`.
- `modules/arch.nix`: the Arch / system-manager backend, which publishes `nixdev.archPackages`
  and `nixdev.aurPackages` for the host's own pacman reconciler to consume (because on Arch,
  this module has no installer of its own).

Every tool is named explicitly by the operator, never defaulted. A host selects per group because
the groups have genuinely different audiences: a laptop wants languages and git extras, a build
hub might want Kubernetes clients and nothing else, and an edge VPS should not import this module
at all.

## What it explicitly does not own

- **Editor configuration.** How an editor is configured belongs to nixarch's home/dev.nix or a
  user's dotfiles, not here. Terminal-native editors (neovim and helix) are catalogued by nixsh;
  nixdev names graphical development editors only.
- **Language toolchain configuration.** This module offers
  `nixdev.rust = [ "stable-toolchain" ];` (rustc, Cargo, rustfmt, Clippy, and rust-analyzer) or
  `nixdev.rust = [ "rustup" ];` as mutually exclusive host floors, plus
  `nixdev.python = [ "python" "uv" ];`. Per-project Rust versions, Python dependencies, virtual
  environments, Python versions, and Python CLI tools belong to each project's own build files
  and `uv.lock`, not to a host-level declaration. The narrow `nixdev.pythonLibraries` catalogue is
  for explicitly approved cross-repository scripting capabilities such as PyYAML; on NixOS these
  are assembled into the selected interpreter rather than merely placed beside it in the closure.
- **Build orchestration.** A host that has `just` does not hereby declare how to use it; that is
  a Justfile's concern.
- **Git configuration and workflows.** nixdev installs git binaries (git-lfs, git-filter-repo,
  git-crypt) but git settings belong to nixarch or a user's config. `lazygit` and `delta` are
  catalogued by nixsh instead, by the same terminal-native test as the editors above.
- **Document processing libraries versus document rendering.** On purpose: `pypdf` and `pdfplumber`
  are libraries you script with, so they live here. `typst` (a typesetter whose output you read)
  lives in nixoffice. The difference is consumption: does a person look at it or only a program?
- **Database tooling of any kind.** Wire-protocol shells, multi-engine command lines and the
  inspectors that open a database file on disk all belong to
  [nixdb](https://github.com/julian-corbet/nixdb-corbet-ch), the repository whose subject is
  databases. "A developer uses it" is not the test — by that test this catalogue would swallow half
  the machine.

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | Flake entry point: `nixosModules.default` (NixOS install), `systemManagerModules.default` (Arch publish), `nixidyModules.default` (the cluster plane), and `nixdev.nix` (the module itself). |
| `modules/` | Platform backends: `nixos.nix` and `arch.nix`, plus `cluster.nix`. |
| `lib/tools.nix` | The tool catalogue: one entry per selectable tool, with platform-specific package names. |
| `lib/applications.nix` | The cluster catalogue: one entry per tool that runs in the cluster — what the software IS, everywhere. |
| `examples/` | `all/values.nix` declares every term the cluster module has; `parity/grammar.nix` is the same two workloads written by hand in the grammar underneath. |
| `checks/` | What the cluster module resolves and refuses, what its manifests say, and that both trees are the same bytes. |

## The cluster plane

The developer's tools that run in the cluster rather than on a desk are declared with
`nixdev.applications.<name>`, and this module renders no Kubernetes object of its own: it defines
into the app grammar published by
[nixk3s](https://github.com/julian-corbet/nixk3s-corbet-ch), which owns Applications, Namespaces,
Deployments and Services. Import that grammar alongside this module.

What this repository adds is the half the grammar cannot know — what these particular tools ARE —
and four fields are split down the middle rather than assigned to a side:

| Field | `lib/applications.nix` knows | A declaration supplies |
|---|---|---|
| `state` | WHERE inside the container a directory lives | WHAT BACKS IT — a claim or a node path |
| `probes` | WHICH probes the software warrants, what they ask for, how fast it answers | THIS cluster's patience budget |
| `credentials` | WHICH ENVIRONMENT VARIABLES carry secret material | WHICH SECRET delivers them, and under which keys |
| `hardening` | what the software TOLERATES, as classes | whether to STAMP those classes on the pod (`harden`) |

Each is refused in both directions: a tool that writes a database and is declared without a backing
does not render onto a pod's ephemeral filesystem, a tool that reads no credential may not name a
Secret, and a budget for a probe the software does not warrant is an eval error rather than an
attribute quietly dropped on the way to the manifest.

Nothing here forwards a nested attrset into the grammar untouched. `resources` names four scalars
rather than taking a free-form resource map, because a map is how a device request — which is a
fact about the software — arrives through a deployment; and the hardening classes are not
declarable at all, so a deployment can decline to stamp them and cannot loosen them.

The bar is byte-identical rendering: `checks/cluster-parity.nix` renders a nixdev declaration and a
hand-written grammar block into two environments and diffs the trees. An adopter's apps are already
running, and a manifest that moves is a sync.

## Platform support

**NixOS:** Full. Options resolve to nixpkgs attributes; the NixOS backend installs them via
`environment.systemPackages`. Selected Python modules are assembled into the selected interpreter
with `python.withPackages`, so host-library selection means the module is actually importable.

**Arch / CachyOS (via system-manager):** Publishes `nixdev.archPackages` and `nixdev.aurPackages`
for the host to consume via its own reconciler (e.g., nixarch). Cannot install anything itself,
because Arch's distro tooling owns that decision.

## Related projects

Part of the same independently-usable NixOS module family: [nixfont](https://github.com/julian-corbet/nixfont-corbet-ch)
(fonts as a shared concern), [nixoffice](https://github.com/julian-corbet/nixoffice-corbet-ch)
(the documents half of a workstation), [nixprint](https://github.com/julian-corbet/nixprint-corbet-ch)
(printing declared), and [nixram](https://github.com/julian-corbet/nixram-corbet-ch) (memory-pressure tuning).

## License

MIT License &copy; 2026 Julian Corbet
