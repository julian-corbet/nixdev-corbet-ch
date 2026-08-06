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
    helmfile = { arch = "helmfile"; nixpkgs = "helmfile"; };
    minikube = { arch = "minikube"; nixpkgs = "minikube"; };
    kind = { arch = "kind-bin"; nixpkgs = "kind"; aur = true; };
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

  };

  # ── Rust ───────────────────────────────────────────────────────────────────────────────────
  rust = {
    # rustup, not rust: a toolchain manager, because Rust projects routinely need a pinned or
    # nightly compiler and a single host rustc cannot express that.
    rustup = { arch = "rustup"; nixpkgs = "rustup"; };
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
    transcrypt = { arch = "transcrypt"; nixpkgs = "transcrypt"; aur = true; };
  };

  # ── Document processing LIBRARIES ───────────────────────────────────────────────────────────
  # Here rather than in nixoffice, by that module's own test: you script against these, you never
  # look at them. A PDF you read is office; a PDF you parse is dev, and the same file can be both
  # depending on who opens it.
  documents = {
    pypdf = { arch = "python-pypdf"; nixpkgs = "python3Packages.pypdf"; };
    pymupdf = { arch = "python-pymupdf"; nixpkgs = "python3Packages.pymupdf"; };
    pdfplumber = { arch = "python-pdfplumber"; nixpkgs = "python3Packages.pdfplumber"; aur = true; };
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
    direnv = { arch = "direnv"; nixpkgs = "direnv"; };
  };
}
    cargo-tauri = { arch = "cargo-tauri"; nixpkgs = "cargo-tauri"; };
    github-desktop = { arch = "github-desktop"; nixpkgs = "github-desktop"; };
    cmake = { arch = "cmake"; nixpkgs = "cmake"; };
    tidy = { arch = "tidy"; nixpkgs = "html-tidy"; };
    linuxdeploy-appimage = { arch = "linuxdeploy-appimage"; nixpkgs = "linuxdeploy"; aur = true; };
