#
# The tool catalogue: one entry per selectable tool, naming it on each platform.
#
# WHY A TABLE AND NOT ROLES. nixdesktop declares *roles* ("a file manager") because desktop
# components are interchangeable — thunar and nautilus fill the same slot. Dev tools are not like
# that: `opentofu` is not "an IaC implementation you might swap for another", it is the thing you
# asked for by name. So the indirection here is narrower and honest about it — a selection resolves
# to a package NAME, and the only thing that varies by platform is that name.
#
# `arch` is the pacman package. `nixpkgs` is the attribute under a nixpkgs instance, or `null`
# where no equivalent exists (AUR-only builds, vendor binaries with no nixpkgs derivation). A null
# is not an oversight — it is the module telling a NixOS consumer that this selection cannot be
# satisfied there, which is better than silently installing nothing.
#
{ ... }:
{
  # ── Cloud provider CLIs ─────────────────────────────────────────────────────────────────────
  providers = {
    gcp = { arch = "google-cloud-cli"; nixpkgs = "google-cloud-sdk"; aur = true; };
    aws = { arch = "aws-cli-v2"; nixpkgs = "awscli2"; };
    azure = { arch = "azure-cli"; nixpkgs = "azure-cli"; };
    cloudflare = { arch = "wrangler"; nixpkgs = "wrangler"; };
    hetzner = { arch = "hcloud"; nixpkgs = "hcloud"; };
    digitalocean = { arch = "doctl"; nixpkgs = "doctl"; };
    vultr = { arch = "vultr-cli"; nixpkgs = "vultr-cli"; };
    scaleway = { arch = "scaleway-cli"; nixpkgs = "scaleway-cli"; };
  };

  # ── Infrastructure as code ──────────────────────────────────────────────────────────────────
  iac = {
    # The binary is `tofu`; the package is `opentofu` on both channels.
    opentofu = { arch = "opentofu"; nixpkgs = "opentofu"; };
    terragrunt = { arch = "terragrunt"; nixpkgs = "terragrunt"; };
    packer = { arch = "packer"; nixpkgs = "packer"; };
  };

  # ── Kubernetes CLIENT tooling ───────────────────────────────────────────────────────────────
  # Deliberately clients only. Running a cluster is nixk3s's job; this is what you type at one.
  kubernetes = {
    k9s = { arch = "k9s"; nixpkgs = "k9s"; };
    kubectx = { arch = "kubectx"; nixpkgs = "kubectx"; };
    helm = { arch = "helm"; nixpkgs = "kubernetes-helm"; };
    helmfile = { arch = "helmfile"; nixpkgs = "helmfile"; };
    minikube = { arch = "minikube"; nixpkgs = "minikube"; };
    kind = { arch = "kind-bin"; nixpkgs = "kind"; aur = true; };
  };

  # ── Remote object storage ───────────────────────────────────────────────────────────────────
  # `rclone` is NOT here. It belongs to nixcloud (github:julian-corbet/nixcloud-corbet-ch), which
  # declares its own `pkgs.rclone` wherever `nixcloud.enable = true` -- the same package its FUSE
  # mount units already invoke by store path. Do not re-add it to this table.
  storage = {
    s3cmd = { arch = "s3cmd"; nixpkgs = "s3cmd"; };
  };

  # ── Observability / log-analytics CLIs ──────────────────────────────────────────────────────
  # NOT `providers`: that group is cloud infrastructure you PROVISION -- compute, storage, network
  # primitives -- via gcp/aws/azure/etc. Axiom is a hosted log-analytics SaaS you QUERY and stream
  # data into; nothing here provisions a resource, so it does not belong beside gcp/aws just
  # because both happen to be reached by an API key against a cloud vendor.
  # NOT `storage`: that group is remote OBJECT storage clients (s3cmd). Axiom stores structured
  # log/event datasets, not objects, and is never addressed by bucket/key.
  # NOT a database tool of any kind: every one of those -- the wire shells, the multi-engine
  # command lines and the local FILE inspectors alike -- is catalogued in nixdb
  # (github:julian-corbet/nixdb-corbet-ch), the repository whose subject is databases. Axiom has no
  # database at either end: it is a remote SaaS query surface over log/event datasets. Hence its
  # own group.
  observability = {
    # Axiom's own CLI (github.com/axiomhq/cli): query, stream, and manage datasets on the hosted
    # axiom.co log-analytics platform. AUR-only -- checked three ways on 2026-08-07: `pacman -Si
    # axiom-bin` finds it in none of this host's configured repos (core/extra/multilib nor any of
    # the cachyos/cachyos-v3/cachyos-core-v3/cachyos-extra-v3 CachyOS repos); archlinux.org's
    # package search returns zero results, so no Arch-family repository carries it under any
    # name; the AUR RPC finds it (PackageBase `axiom-bin`, URL axiom.co, description "Powerful
    # log analytics from the comfort of your command-line", maintainer axiomautomation). `aur =
    # true` is therefore the whole answer -- unlike nixagent's `claude-code` entry, no
    # `archRepoOn` lift applies, because no derivative's own repository resolves this name today.
    # No nixpkgs derivation exists either, checked by force-evaluating the full top-level
    # attribute set (27707 names, nothing matching `axiom` in any case).
    axiom = { arch = "axiom-bin"; nixpkgs = null; aur = true; };
  };

  # ── Language toolchains ─────────────────────────────────────────────────────────────────────
  languages = {
    go = { arch = "go"; nixpkgs = "go"; };
    deno = { arch = "deno"; nixpkgs = "deno"; };
    bun = { arch = "bun"; nixpkgs = "bun"; };
    node = { arch = "nodejs"; nixpkgs = "nodejs"; };
    pnpm = { arch = "pnpm"; nixpkgs = "pnpm"; };
    yarn = { arch = "yarn"; nixpkgs = "yarn"; };
    # Not a runtime or a package manager -- it rewrites the version RANGES in package.json
    # itself, reporting and applying updates beyond what the declared ranges already allow.
    # That is the reason to reach for it over `npm outdated`/`pnpm outdated`, which only report
    # within the ranges you already wrote. Filed here beside node/pnpm/yarn anyway: it is the
    # same Node-ecosystem workflow tool, not a separate class this table has a home for.
    npm-check-updates = { arch = "npm-check-updates"; nixpkgs = "npm-check-updates"; };
  };

  # ── Rust ───────────────────────────────────────────────────────────────────────────────────
  rust = {
    # rustup, not rust: a toolchain manager, because Rust projects routinely need a pinned or
    # nightly compiler and a single host rustc cannot express that.
    rustup = { arch = "rustup"; nixpkgs = "rustup"; };
    cargo-tauri = { arch = "cargo-tauri"; nixpkgs = "cargo-tauri"; };
  };

  # ── Python ─────────────────────────────────────────────────────────────────────────────────
  # The host-level floor: an interpreter plus uv. Project pyproject.toml and uv.lock files own
  # every dependency, virtual environment, Python version, and Python CLI beyond these two.
  python = {
    python = { arch = "python"; nixpkgs = "python3"; };
    uv = { arch = "uv"; nixpkgs = "uv"; };
  };

  # ── Editors ─────────────────────────────────────────────────────────────────────────────────
  # Named, never defaulted. Editor choice is the most personal selection in this table and there
  # is no house pick -- an empty selection is the correct state for a machine whose owner has not
  # said. Listed here only so the choice is declared rather than hand-installed and forgotten.
  #
  # `emacs` is NOT here: it moved to nixsh's `edit` group as `emacs-nox`. Two separate reasons, and
  # the second is the one that decides it. The package was wrong -- nixpkgs' `emacs` and Arch's
  # `emacs` are both the GTK-linked build, which is not what a terminal Emacs user wants and which
  # CONFLICTS with `emacs-nox` in pacman, so the two can never be installed side by side. And
  # `emacs-nox` has no display mode AT ALL, which is exactly nixsh's own stated placement test
  # ("does the tool have a display mode, and is that its DEFAULT? no -> nixsh"), putting it beside
  # neovim, helix and nano rather than beside the IDEs below.
  # `neovim` and `helix` are NOT here, by this same group's own display-mode test above: neither
  # has a display mode at all, so both are catalogued in nixsh's `edit` group, not this one. Only
  # graphical development editors belong in this table.
  editors = {
    zed = { arch = "zed"; nixpkgs = "zed-editor"; };
    # The MIT-licensed build, not Microsoft's branded binary -- that one is AUR-only on Arch and
    # unfree in nixpkgs, so it would not resolve cleanly on either platform from this table.
    vscode = { arch = "code"; nixpkgs = "vscodium"; };
    gnome-builder = { arch = "gnome-builder"; nixpkgs = "gnome-builder"; };
    qtcreator = { arch = "qtcreator"; nixpkgs = "qtcreator"; };
    # JetBrains' two Apache-2.0 IDEs, and the one pair in this table where the obvious nixpkgs name
    # is a TRAP. JetBrains merged its Community and Ultimate editions into a single distribution in
    # 2025, and nixpkgs followed: `jetbrains.idea-community` and `jetbrains.pycharm-community` are
    # now aliases that THROW ("has been removed as it has been discontinued"), while the bare
    # `jetbrains.idea` / `jetbrains.pycharm` are the unified, UNFREE distribution. The open-source
    # builds -- Apache-2.0, the same licence Arch's own packages carry -- kept the `-oss` suffix,
    # and those are what belong here.
    #
    # This is the class of error `lib.hasAttrByPath` cannot see: a throwing alias IS present as an
    # attribute, so modules/nixos.nix's own `resolves` guard passes it and the failure only appears
    # when a consumer force-evaluates its whole system closure. Verified by force-evaluation, not
    # by existence, against nixpkgs 38a4887411571457d700c51c64a6e49ead2ed5ab.
    #
    # Keys are the full pacman names rather than a shortened `intellij`/`pycharm`, because the very
    # distinction the upstream merge blurred -- which edition -- is one a selection should have to
    # state out loud.
    intellij-idea-community-edition = { arch = "intellij-idea-community-edition"; nixpkgs = "jetbrains.idea-oss"; };
    pycharm-community-edition = { arch = "pycharm-community-edition"; nixpkgs = "jetbrains.pycharm-oss"; };
  };

  # ── git beyond git ──────────────────────────────────────────────────────────────────────────
  # NOT git config: that is nixarch's home/dev.nix, which owns the settings. This is binaries.
  #
  # `lazygit` and `delta` are NOT here, by the editors group's own display-mode test above: neither
  # has a display mode at all, so both are catalogued in nixsh's `git`/`core` groups, not this one.
  gitExtras = {
    lfs = { arch = "git-lfs"; nixpkgs = "git-lfs"; };
    filter-repo = { arch = "git-filter-repo"; nixpkgs = "git-filter-repo"; };
    crypt = { arch = "git-crypt"; nixpkgs = "git-crypt"; };
    transcrypt = { arch = "transcrypt"; nixpkgs = "transcrypt"; aur = true; };
    github-desktop = { arch = "github-desktop"; nixpkgs = "github-desktop"; };
    # A graphical three-way diff/merge tool -- filed here rather than under `editors` because what
    # you reach for it FOR is `git difftool` / `git mergetool`, the same slot `delta` above fills
    # for reading a diff. It resolves a conflict; it is not where you write code.
    meld = { arch = "meld"; nixpkgs = "meld"; };
  };

  # ── Document processing LIBRARIES ───────────────────────────────────────────────────────────
  # Here rather than in nixoffice, by that module's own test: you script against these, you never
  # look at them. A PDF you read is office; a PDF you parse is dev, and the same file can be both
  # depending on who opens it.
  documents = {
    pypdf = { arch = "python-pypdf"; nixpkgs = "python3Packages.pypdf"; };
    pymupdf = { arch = "python-pymupdf"; nixpkgs = "python3Packages.pymupdf"; };
    pdfplumber = {
      arch = "python-pdfplumber";
      nixpkgs = "python3Packages.pdfplumber";
      aur = true;
      nixpkgsOverride = pkgs:
        pkgs.python3Packages.pdfplumber.override {
          pandas-stubs = pkgs.python3Packages.pandas-stubs.overridePythonAttrs (_: {
            doCheck = false;
            pythonImportsCheck = [ ];
          });
        };
    };
    extract-msg = { arch = "python-extract-msg"; nixpkgs = "python3Packages.extract-msg"; aur = true; };
  };

  # ── Typst tooling ───────────────────────────────────────────────────────────────────────────
  # The LSP and the formatter, NOT the typst compiler itself -- that renders something a person
  # reads, so it lives in nixoffice. Editor plumbing stays here.
  typst = {
    tinymist = { arch = "tinymist"; nixpkgs = "tinymist"; };
    typstyle = { arch = "typstyle"; nixpkgs = "typstyle"; };
  };

  # ── Build/dev ergonomics ────────────────────────────────────────────────────────────────────
  build = {
    just = { arch = "just"; nixpkgs = "just"; };
    mold = { arch = "mold"; nixpkgs = "mold"; };
    ccache = { arch = "ccache"; nixpkgs = "ccache"; };
    patchelf = { arch = "patchelf"; nixpkgs = "patchelf"; };
    cmake = { arch = "cmake"; nixpkgs = "cmake"; };
    tidy = { arch = "tidy"; nixpkgs = "html-tidy"; };
    linuxdeploy-appimage = { arch = "linuxdeploy-appimage"; nixpkgs = "linuxdeploy"; aur = true; };
    buildah = { arch = "buildah"; nixpkgs = "buildah"; };
    direnv = { arch = "direnv"; nixpkgs = "direnv"; };
  };
}
