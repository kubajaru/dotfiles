#!/bin/bash

set -euo pipefail

# ── Dotfiles location ─────────────────────────────────────────────────────────
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Temp-file cleanup ─────────────────────────────────────────────────────────
TMPDIR_CUSTOM=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CUSTOM"' EXIT

# ── Helpers ───────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

# Back up an existing real file/dir, then create a symlink.
# Skips silently if the symlink already points to the right source.
link_dotfile() {
  local src="$1" dst="$2"

  # Already a correct symlink — nothing to do.
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    warn "Symlink already correct: $dst → $src — skipping"
    return
  fi

  # Existing symlink pointing elsewhere — remove it.
  if [[ -L "$dst" ]]; then
    warn "Replacing stale symlink: $dst"
    rm "$dst"
  # Existing real file/dir — back it up.
  elif [[ -e "$dst" ]]; then
    local backup="${dst}.bak"
    warn "Backing up existing $(basename "$dst") to ${backup}"
    mv "$dst" "$backup"
  fi

  # Create parent dir if needed (e.g. ~/.config/).
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  info "Symlink created: $dst → $src"
}

# Resolve the latest version tag from a GitHub repo (returns e.g. "v1.2.3").
github_latest_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep -oP '"tag_name":\s*"\K[^"]+'
}

# Install a single binary from a GitHub release tarball.
# Usage: install_github_binary <repo> <tarball-name-pattern> <binary-name-in-archive> <dest-name>
install_github_binary() {
  local repo="$1" tarball_pattern="$2" binary_in_archive="$3" dest_name="$4"
  local tag version url tmp_tgz

  tag=$(github_latest_tag "$repo")
  if [[ -z "$tag" ]]; then
    error "Could not resolve latest tag for $repo"
    return 1
  fi
  version="${tag#v}"
  # Allow the caller to embed {tag} and {version} in the pattern
  url="https://github.com/${repo}/releases/download/${tag}/$(echo "$tarball_pattern" \
    | sed "s/{tag}/${tag}/g; s/{version}/${version}/g")"

  tmp_tgz="$TMPDIR_CUSTOM/${dest_name}.tar.gz"
  wget -qO "$tmp_tgz" "$url"
  tar -xzf "$tmp_tgz" -C "$TMPDIR_CUSTOM" "$binary_in_archive" 2>/dev/null \
    || tar -xzf "$tmp_tgz" -C "$TMPDIR_CUSTOM"   # some archives have no subdir
  sudo install -m 0755 "$TMPDIR_CUSTOM/$binary_in_archive" "/usr/local/bin/$dest_name"
  info "$dest_name $tag installed to /usr/local/bin/$dest_name"
}

# ── Sanity-check dotfiles dir ─────────────────────────────────────────────────
info "Dotfiles directory: $DOTFILES_DIR"
for f in .zshrc .tmux.conf nvim k9s; do
  if [[ ! -e "$DOTFILES_DIR/$f" ]]; then
    error "Expected config not found: $DOTFILES_DIR/$f"
    exit 1
  fi
done

# ── System packages ───────────────────────────────────────────────────────────
info "Updating package lists…"
sudo apt-get update -qq

info "Installing base system packages…"
sudo apt-get install -y \
  unzip zip zsh fd-find bat ripgrep \
  apt-transport-https \
  libxi6 libxrender1 libxtst6 mesa-utils libfontconfig libgtk-3-bin \
  tar dbus-user-session curl wget gpg git ca-certificates lsb-release

# ── Azure CLI ─────────────────────────────────────────────────────────────────
info "Checking Azure CLI…"
if command_exists az; then
  warn "Azure CLI already installed ($(az version --query '"azure-cli"' -o tsv 2>/dev/null || true)) — skipping"
else
  info "Installing Azure CLI (latest)…"
  sudo mkdir -p /etc/apt/keyrings
  curl -sLS https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor \
    | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

  AZ_DIST=$(lsb_release -cs)
  echo "Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${AZ_DIST}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg" \
    | sudo tee /etc/apt/sources.list.d/azure-cli.sources > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y azure-cli
fi

# ── kubectl + kubelogin (via az aks install-cli) ──────────────────────────────
info "Checking kubectl…"
if command_exists kubectl; then
  warn "kubectl already installed ($(kubectl version --client --short 2>/dev/null || true)) — skipping"
else
  info "Installing kubectl (latest stable) via az aks install-cli…"
  az aks install-cli
fi

# ── krew (kubectl plugin manager) ────────────────────────────────────────────
info "Checking krew…"
if kubectl krew version &>/dev/null; then
  warn "krew already installed — skipping"
else
  info "Installing krew…"
  KREW_TAG=$(github_latest_tag "kubernetes-sigs/krew")
  KREW_TGZ="$TMPDIR_CUSTOM/krew.tar.gz"
  wget -qO "$KREW_TGZ" \
    "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_TAG}/krew-linux_amd64.tar.gz"
  tar -xzf "$KREW_TGZ" -C "$TMPDIR_CUSTOM"
  "$TMPDIR_CUSTOM/krew-linux_amd64" install krew
  info "krew installed — ensure ~/.krew/bin is in PATH"
fi

# ── kubectl-ctx (kubectx via krew) ───────────────────────────────────────────
info "Checking kubectx (kubectl ctx)…"
if kubectl ctx --help &>/dev/null 2>&1; then
  warn "kubectx already installed — skipping"
else
  info "Installing kubectx via krew…"
  kubectl krew install ctx
fi

# ── Helm ──────────────────────────────────────────────────────────────────────
info "Checking Helm…"
if command_exists helm; then
  warn "Helm already installed ($(helm version --short 2>/dev/null || true)) — skipping"
else
  info "Installing Helm (latest)…"
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/helm.gpg] \
https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
    | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y helm
fi

# ── k9s ───────────────────────────────────────────────────────────────────────
info "Checking k9s…"
if command_exists k9s; then
  warn "k9s already installed ($(k9s version --short 2>/dev/null || true)) — skipping"
else
  info "Installing k9s (latest)…"
  K9S_DEB="$TMPDIR_CUSTOM/k9s_linux_amd64.deb"
  wget -qO "$K9S_DEB" \
    https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb
  sudo apt-get install -y "$K9S_DEB"
fi

# ── Terraform ─────────────────────────────────────────────────────────────────
info "Checking Terraform…"
if command_exists terraform; then
  warn "Terraform already installed ($(terraform version -json 2>/dev/null | grep -oP '"terraform_version":\s*"\K[^"]+' || true)) — skipping"
else
  info "Installing Terraform (latest)…"
  wget -qO- https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y terraform
fi

# ── OpenTofu ──────────────────────────────────────────────────────────────────
info "Checking OpenTofu…"
if command_exists tofu; then
  warn "OpenTofu already installed ($(tofu version 2>/dev/null | head -1 || true)) — skipping"
else
  info "Installing OpenTofu (latest)…"
  curl -fsSL https://get.opentofu.org/opentofu.gpg \
    | sudo tee /usr/share/keyrings/opentofu.gpg > /dev/null
  curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey \
    | gpg --no-tty --batch --dearmor \
    | sudo tee /usr/share/keyrings/opentofu-repo.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/opentofu.gpg,/usr/share/keyrings/opentofu-repo.gpg] \
https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=/usr/share/keyrings/opentofu.gpg,/usr/share/keyrings/opentofu-repo.gpg] \
https://packages.opentofu.org/opentofu/tofu/any/ any main" \
    | sudo tee /etc/apt/sources.list.d/opentofu.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y tofu
fi

# ── Istio CLI (istioctl) ──────────────────────────────────────────────────────
info "Checking istioctl…"
if command_exists istioctl; then
  warn "istioctl already installed ($(istioctl version --short 2>/dev/null || true)) — skipping"
else
  info "Installing istioctl (latest)…"
  ISTIO_TAG=$(github_latest_tag "istio/istio")
  ISTIO_VERSION="${ISTIO_TAG#v}"
  if [[ -z "$ISTIO_TAG" ]]; then
    error "Could not resolve latest Istio version"
    exit 1
  fi
  ISTIO_TGZ="$TMPDIR_CUSTOM/istio.tar.gz"
  wget -qO "$ISTIO_TGZ" \
    "https://github.com/istio/istio/releases/download/${ISTIO_TAG}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz"
  tar -xzf "$ISTIO_TGZ" -C "$TMPDIR_CUSTOM"
  sudo install -m 0755 "$TMPDIR_CUSTOM/istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/istioctl
fi

# ── Velero ────────────────────────────────────────────────────────────────────
info "Checking velero…"
if command_exists velero; then
  warn "velero already installed ($(velero version --client-only 2>/dev/null | grep Version || true)) — skipping"
else
  info "Installing velero (latest)…"
  VELERO_TAG=$(github_latest_tag "vmware-tanzu/velero")
  VELERO_VERSION="${VELERO_TAG#v}"
  if [[ -z "$VELERO_TAG" ]]; then
    error "Could not resolve latest Velero version"
    exit 1
  fi
  VELERO_TGZ="$TMPDIR_CUSTOM/velero.tar.gz"
  wget -qO "$VELERO_TGZ" \
    "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_TAG}/velero-${VELERO_TAG}-linux-amd64.tar.gz"
  tar -xzf "$VELERO_TGZ" -C "$TMPDIR_CUSTOM"
  sudo install -m 0755 \
    "$TMPDIR_CUSTOM/velero-${VELERO_TAG}-linux-amd64/velero" \
    /usr/local/bin/velero
fi

# ── Go ────────────────────────────────────────────────────────────────────────
info "Checking Go…"
GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)
if [[ -z "$GO_VERSION" ]]; then
  error "Could not resolve latest Go version"
  exit 1
fi
if command_exists go && go version 2>&1 | grep -qF "$GO_VERSION"; then
  warn "Go $GO_VERSION already installed — skipping"
else
  info "Installing Go $GO_VERSION…"
  GO_ARCHIVE="${GO_VERSION}.linux-amd64.tar.gz"
  wget -qO "$TMPDIR_CUSTOM/$GO_ARCHIVE" "https://go.dev/dl/${GO_ARCHIVE}"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$TMPDIR_CUSTOM/$GO_ARCHIVE"
  info "Go installed to /usr/local/go — ensure /usr/local/go/bin is in PATH"
fi

# ── Neovim ────────────────────────────────────────────────────────────────────
info "Checking Neovim…"
if command_exists nvim; then
  warn "Neovim already installed ($(nvim --version | head -1)) — skipping"
else
  info "Installing Neovim (latest stable)…"
  NVIM_URL=$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
    | grep -oP '"browser_download_url":\s*"\K[^"]+nvim-linux-x86_64\.deb')
  if [[ -z "$NVIM_URL" ]]; then
    error "Could not determine Neovim download URL"
    exit 1
  fi
  NVIM_DEB="$TMPDIR_CUSTOM/nvim-linux-x86_64.deb"
  wget -qO "$NVIM_DEB" "$NVIM_URL"
  sudo apt-get install -y "$NVIM_DEB"
fi

# ── Lazygit ───────────────────────────────────────────────────────────────────
info "Checking lazygit…"
if command_exists lazygit; then
  warn "lazygit already installed ($(lazygit --version 2>/dev/null | head -1)) — skipping"
else
  info "Installing lazygit (latest)…"
  LG_TAG=$(github_latest_tag "jesseduffield/lazygit")
  if [[ -z "$LG_TAG" ]]; then
    error "Could not resolve latest lazygit version"
    exit 1
  fi
  LG_VERSION_NUM="${LG_TAG#v}"
  LG_TGZ="$TMPDIR_CUSTOM/lazygit.tar.gz"
  wget -qO "$LG_TGZ" \
    "https://github.com/jesseduffield/lazygit/releases/download/${LG_TAG}/lazygit_${LG_VERSION_NUM}_Linux_x86_64.tar.gz"
  tar -xzf "$LG_TGZ" -C "$TMPDIR_CUSTOM" lazygit
  sudo install -m 0755 "$TMPDIR_CUSTOM/lazygit" /usr/local/bin/lazygit
fi

# ── SDKMAN + Java ─────────────────────────────────────────────────────────────
info "Checking SDKMAN…"
if [[ -d "${SDKMAN_DIR:-$HOME/.sdkman}" ]]; then
  warn "SDKMAN already installed — skipping"
else
  info "Installing SDKMAN…"
  curl -s "https://get.sdkman.io?ci=true&rcupdate=false" | bash
fi

# ── Zsh + Oh-My-Zsh ──────────────────────────────────────────────────────────
info "Configuring Zsh as default shell…"
if [[ "$SHELL" == "$(which zsh)" ]]; then
  warn "Zsh already the default shell — skipping chsh"
else
  chsh -s "$(which zsh)"
fi

info "Checking Oh-My-Zsh…"
if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
  warn "Oh-My-Zsh already installed — skipping"
else
  info "Installing Oh-My-Zsh…"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
AUTOSUGGESTIONS_DIR="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
if [[ -d "$AUTOSUGGESTIONS_DIR" ]]; then
  warn "zsh-autosuggestions already cloned — skipping"
else
  git clone https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGESTIONS_DIR"
fi

# ── bat symlink ───────────────────────────────────────────────────────────────
info "Configuring bat symlink…"
mkdir -p ~/.local/bin
if [[ ! -e ~/.local/bin/bat ]]; then
  ln -s "$(which batcat)" ~/.local/bin/bat
  info "Symlink created: ~/.local/bin/bat"
else
  warn "~/.local/bin/bat already exists — skipping"
fi

# ── fd symlink ────────────────────────────────────────────────────────────────
info "Configuring fd symlink…"
if [[ ! -e ~/.local/bin/fd ]]; then
  ln -s "$(which fdfind)" ~/.local/bin/fd
  info "Symlink created: ~/.local/bin/fd"
else
  warn "~/.local/bin/fd already exists — skipping"
fi

# ── fzf ───────────────────────────────────────────────────────────────────────
info "Checking fzf…"
if [[ -d ~/.fzf ]]; then
  warn "fzf already cloned — skipping"
else
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --all --no-bash --no-fish
fi

# ── VS Code ───────────────────────────────────────────────────────────────────
info "Checking VS Code…"
if command_exists code; then
  warn "VS Code already installed — skipping"
else
  info "Installing VS Code (latest)…"
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
  sudo chmod go+r /usr/share/keyrings/microsoft.gpg

  echo "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg" \
    | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y code
fi

# ── JetBrains Toolbox ─────────────────────────────────────────────────────────
info "Checking JetBrains Toolbox…"
if command_exists jetbrains-toolbox; then
  warn "JetBrains Toolbox already installed — skipping"
else
  info "Installing JetBrains Toolbox (latest)…"
  JB_API="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
  JB_URL=$(curl -fsSL "$JB_API" \
    | grep -oP '"linux":\{"link":"\K[^"]+' \
    | head -1)
  if [[ -z "$JB_URL" ]]; then
    error "Could not determine JetBrains Toolbox download URL"
    exit 1
  fi
  JB_TGZ="$TMPDIR_CUSTOM/toolbox.tar.gz"
  wget -qO "$JB_TGZ" "$JB_URL"
  mkdir -p ~/.local/bin
  tar -xzf "$JB_TGZ" --strip-components=1 -C "$TMPDIR_CUSTOM"
  install -m 0755 "$TMPDIR_CUSTOM"/jetbrains-toolbox ~/.local/bin/jetbrains-toolbox
  info "Run 'jetbrains-toolbox' to complete setup"
fi

# ── Dotfile symlinks ──────────────────────────────────────────────────────────
# All config files live in $DOTFILES_DIR (~/repos/dotfiles) and are symlinked
# into the locations each tool expects. Re-running is safe — existing correct
# symlinks are left alone; real files are backed up as <name>.bak first.
info "Linking dotfiles from $DOTFILES_DIR…"

# .zshrc         →  ~/.zshrc
link_dotfile "$DOTFILES_DIR/.zshrc"     "$HOME/.zshrc"

# .tmux.conf     →  ~/.tmux.conf
link_dotfile "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

# nvim/          →  ~/.config/nvim
link_dotfile "$DOTFILES_DIR/nvim"       "$HOME/.config/nvim"

# k9s/           →  ~/.config/k9s
# k9s looks for config.yaml, skin.yaml, aliases.yaml etc. under this dir.
link_dotfile "$DOTFILES_DIR/k9s"        "$HOME/.config/k9s"

info "✓ All done! Start a new shell session (or 'exec zsh') to pick up PATH changes."
info "  PATH additions to verify are in your .zshrc:"
info "    /usr/local/go/bin   (Go)"
info "    ~/.local/bin        (bat, fd, jetbrains-toolbox)"
info "    ~/.krew/bin         (kubectl plugins)"
