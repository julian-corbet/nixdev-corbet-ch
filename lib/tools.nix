#
# The tool catalogue: one entry per selectable tool, naming it on each platform.
#
# WHY A TABLE AND NOT ROLES. nixdesktop declares *roles* ("a file manager") because desktop
# components are interchangeable — thunar and nautilus fill the same slot. Dev tools are not like
# that: `pulumi` is not "an IaC implementation you might swap for another", it is the thing you
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
    gcp = { arch = "google-cloud-cli"; nixpkgs = "google-cloud-sdk"; };
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
    pulumi = { arch = "pulumi"; nixpkgs = "pulumi"; };
    terragrunt = { arch = "terragrunt"; nixpkgs = "terragrunt"; };
    packer = { arch = "packer"; nixpkgs = "packer"; };
  };

  # ── Kubernetes CLIENT tooling ───────────────────────────────────────────────────────────────
  # Deliberately clients only. Running a cluster is nixk3s's job; this is what you type at one.
  kubernetes = {
    k9s = { arch = "k9s"; nixpkgs = "k9s"; };
    kubectx = { arch = "kubectx"; nixpkgs = "kubectx"; };
    helmfile = { arch = "helmfile"; nixpkgs = "helmfile"; };
    minikube = { arch = "minikube"; nixpkgs = "minikube"; };
    kind = { arch = "kind-bin"; nixpkgs = "kind"; };
  };

  # ── Remote object storage ───────────────────────────────────────────────────────────────────
  storage = {
    rclone = { arch = "rclone"; nixpkgs = "rclone"; };
    s3cmd = { arch = "s3cmd"; nixpkgs = "s3cmd"; };
  };

  # ── Language toolchains ─────────────────────────────────────────────────────────────────────
  languages = {
    go = { arch = "go"; nixpkgs = "go"; };
    deno = { arch = "deno"; nixpkgs = "deno"; };
    bun = { arch = "bun"; nixpkgs = "bun"; };
    node = { arch = "nodejs"; nixpkgs = "nodejs"; };
    pnpm = { arch = "pnpm"; nixpkgs = "pnpm"; };
    yarn = { arch = "yarn"; nixpkgs = "yarn"; };

    # An interpreter and a fast env/package manager -- the floor under a per-project uv/venv
    # workflow, deliberately WITHOUT the scientific stack or any ML framework. Those belong in
    # per-project environments, reproducible per repo, not as one global version fighting every
    # project that disagrees with it.
    python = { arch = "python"; nixpkgs = "python3"; };
    uv = { arch = "uv"; nixpkgs = "uv"; };

    # rustup, not rust: a toolchain MANAGER, because Rust work routinely needs a pinned or nightly
    # toolchain per project and a single system rustc cannot express that. `rust` exists on both
    # platforms if you genuinely want one fixed compiler instead.
    rustup = { arch = "rustup"; nixpkgs = "rustup"; };
  };

  # ── Editors ─────────────────────────────────────────────────────────────────────────────────
  # Named, never defaulted. Editor choice is the most personal selection in this table and there
  # is no house pick -- an empty selection is the correct state for a machine whose owner has not
  # said. Listed here only so the choice is declared rather than hand-installed and forgotten.
  editors = {
    neovim = { arch = "neovim"; nixpkgs = "neovim"; };
    helix = { arch = "helix"; nixpkgs = "helix"; };
    emacs = { arch = "emacs"; nixpkgs = "emacs"; };
    zed = { arch = "zed"; nixpkgs = "zed-editor"; };
    # The MIT-licensed build, not Microsoft's branded binary -- that one is AUR-only on Arch and
    # unfree in nixpkgs, so it would not resolve cleanly on either platform from this table.
    vscode = { arch = "code"; nixpkgs = "vscodium"; };
  };

  # ── git beyond git ──────────────────────────────────────────────────────────────────────────
  # NOT git config: that is nixarch's home/dev.nix, which owns the settings. This is binaries.
  gitExtras = {
    lazygit = { arch = "lazygit"; nixpkgs = "lazygit"; };
    delta = { arch = "git-delta"; nixpkgs = "delta"; };
    lfs = { arch = "git-lfs"; nixpkgs = "git-lfs"; };
    filter-repo = { arch = "git-filter-repo"; nixpkgs = "git-filter-repo"; };
    crypt = { arch = "git-crypt"; nixpkgs = "git-crypt"; };
    transcrypt = { arch = "transcrypt"; nixpkgs = "transcrypt"; };
  };

  # ── Document processing LIBRARIES ───────────────────────────────────────────────────────────
  # Here rather than in nixoffice, by that module's own test: you script against these, you never
  # look at them. A PDF you read is office; a PDF you parse is dev, and the same file can be both
  # depending on who opens it.
  documents = {
    pypdf = { arch = "python-pypdf"; nixpkgs = "python3Packages.pypdf"; };
    pymupdf = { arch = "python-pymupdf"; nixpkgs = "python3Packages.pymupdf"; };
    pdfplumber = { arch = "python-pdfplumber"; nixpkgs = "python3Packages.pdfplumber"; };
    extract-msg = { arch = "python-extract-msg"; nixpkgs = "python3Packages.extract-msg"; };
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
    direnv = { arch = "direnv"; nixpkgs = "direnv"; };
  };
}
