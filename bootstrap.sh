#!/bin/sh

set -eu

# ── Dotfiles location ─────────────────────────────────────────────────────────
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP_LOCAL_CONFIG="$DOTFILES_DIR/bootstrap.local.sh"
if [ -f "$BOOTSTRAP_LOCAL_CONFIG" ]; then
  # shellcheck source=bootstrap.local.example.sh
  . "$BOOTSTRAP_LOCAL_CONFIG"
fi

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf '%b[INFO]%b  %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%b[WARN]%b  %s\n' "$YELLOW" "$NC" "$*"; }
error() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; }

# ── Temp-file cleanup ─────────────────────────────────────────────────────────
TMPDIR_CUSTOM=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CUSTOM"' 0
export PATH="$HOME/.local/bin:$HOME/.krew/bin:$PATH"

# ── Helpers ───────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" >/dev/null 2>&1; }

verify_sha256() {
  VERIFY_FILE="$1"
  VERIFY_EXPECTED="$2"
  VERIFY_NAME="$3"
  if [ -n "$VERIFY_EXPECTED" ]; then
    case "$VERIFY_EXPECTED" in
      *[!0123456789abcdefABCDEF]*) error "Invalid SHA-256 for $VERIFY_NAME"; return 1 ;;
    esac
    if [ "${#VERIFY_EXPECTED}" -ne 64 ]; then
      error "SHA-256 for $VERIFY_NAME must contain 64 hexadecimal characters"
      return 1
    fi
    printf '%s  %s\n' "$VERIFY_EXPECTED" "$VERIFY_FILE" | sha256sum -c - >/dev/null
    info "$VERIFY_NAME checksum verified"
  fi
}

# Back up an existing real file/dir, then create a symlink.
# Skips silently if the symlink already points to the right source.
link_dotfile() {
  LINK_SRC="$1"
  LINK_DST="$2"

  # Already a correct symlink — nothing to do.
  if [ -L "$LINK_DST" ] && [ "$(readlink "$LINK_DST")" = "$LINK_SRC" ]; then
    warn "Symlink already correct: $LINK_DST → $LINK_SRC — skipping"
    return
  fi

  # Existing symlink pointing elsewhere — remove it.
  if [ -L "$LINK_DST" ]; then
    warn "Replacing stale symlink: $LINK_DST"
    rm "$LINK_DST"
  # Existing real file/dir — back it up.
  elif [ -e "$LINK_DST" ]; then
    LINK_BACKUP="${LINK_DST}.bak"
    warn "Backing up existing $(basename "$LINK_DST") to ${LINK_BACKUP}"
    mv "$LINK_DST" "$LINK_BACKUP"
  fi

  # Create parent dir if needed (e.g. ~/.config/).
  mkdir -p "$(dirname "$LINK_DST")"
  ln -s "$LINK_SRC" "$LINK_DST"
  info "Symlink created: $LINK_DST → $LINK_SRC"
}

# Resolve the latest version tag from a GitHub repo (returns e.g. "v1.2.3").
github_latest_tag() {
  GITHUB_LATEST_REPO="$1"
  curl -fsSL "https://api.github.com/repos/${GITHUB_LATEST_REPO}/releases/latest" \
    | grep -oP '"tag_name":\s*"\K[^"]+'
}

# Install a single binary from a GitHub release tarball.
# Usage: install_github_binary <repo> <tarball-name-pattern> <binary-name-in-archive> <dest-name>
install_github_binary() {
  INSTALL_REPO="$1"
  INSTALL_TARBALL_PATTERN="$2"
  INSTALL_BINARY_IN_ARCHIVE="$3"
  INSTALL_DEST_NAME="$4"

  INSTALL_TAG=$(github_latest_tag "$INSTALL_REPO")
  if [ -z "$INSTALL_TAG" ]; then
    error "Could not resolve latest tag for $INSTALL_REPO"
    return 1
  fi
  INSTALL_VERSION="${INSTALL_TAG#v}"
  # Allow the caller to embed {tag} and {version} in the pattern
  INSTALL_URL="https://github.com/${INSTALL_REPO}/releases/download/${INSTALL_TAG}/$(echo "$INSTALL_TARBALL_PATTERN" \
    | sed "s/{tag}/${INSTALL_TAG}/g; s/{version}/${INSTALL_VERSION}/g")"

  INSTALL_TMP_TGZ="$TMPDIR_CUSTOM/${INSTALL_DEST_NAME}.tar.gz"
  wget -qO "$INSTALL_TMP_TGZ" "$INSTALL_URL"
  tar -xzf "$INSTALL_TMP_TGZ" -C "$TMPDIR_CUSTOM" "$INSTALL_BINARY_IN_ARCHIVE" 2>/dev/null \
    || tar -xzf "$INSTALL_TMP_TGZ" -C "$TMPDIR_CUSTOM"   # some archives have no subdir
  sudo install -m 0755 "$TMPDIR_CUSTOM/$INSTALL_BINARY_IN_ARCHIVE" "/usr/local/bin/$INSTALL_DEST_NAME"
  info "$INSTALL_DEST_NAME $INSTALL_TAG installed to /usr/local/bin/$INSTALL_DEST_NAME"
}

# ── Sanity-check dotfiles dir ─────────────────────────────────────────────────
info "Dotfiles directory: $DOTFILES_DIR"
for f in .zshrc .tmux.conf nvim .k9s; do
  if [ ! -e "$DOTFILES_DIR/$f" ]; then
    error "Expected config not found: $DOTFILES_DIR/$f"
    exit 1
  fi
done

# ── System packages ───────────────────────────────────────────────────────────
info "Updating package lists…"
sudo apt-get update -qq

info "Installing base system packages…"
sudo apt-get install -y \
  unzip zip zsh fd-find bat ripgrep jq shellcheck \
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
if command_exists kubectl && [ -z "${KUBECTL_VERSION:-}${KUBELOGIN_VERSION:-}" ]; then
  warn "kubectl already installed ($(kubectl version --client --short 2>/dev/null || true)) — skipping"
else
  info "Installing kubectl (latest stable) via az aks install-cli…"
  KUBECTL_TMP="$TMPDIR_CUSTOM/kubectl"
  KUBELOGIN_TMP="$TMPDIR_CUSTOM/kubelogin"
  set -- aks install-cli \
    --install-location "$KUBECTL_TMP" \
    --kubelogin-install-location "$KUBELOGIN_TMP"
  if [ -n "${KUBECTL_VERSION:-}" ]; then
    set -- "$@" --client-version "$KUBECTL_VERSION"
  fi
  if [ -n "${KUBELOGIN_VERSION:-}" ]; then
    set -- "$@" --kubelogin-version "$KUBELOGIN_VERSION"
  fi
  az "$@"
  verify_sha256 "$KUBECTL_TMP" "${KUBECTL_SHA256:-}" "kubectl ${KUBECTL_VERSION:-latest}"
  verify_sha256 "$KUBELOGIN_TMP" "${KUBELOGIN_SHA256:-}" "kubelogin ${KUBELOGIN_VERSION:-latest}"
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$KUBECTL_TMP" "$HOME/.local/bin/kubectl"
  install -m 0755 "$KUBELOGIN_TMP" "$HOME/.local/bin/kubelogin"
fi

# ── krew (kubectl plugin manager) ────────────────────────────────────────────
info "Checking krew…"
if kubectl krew version >/dev/null 2>&1; then
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
if kubectl ctx --help >/dev/null 2>&1; then
  warn "kubectx already installed — skipping"
else
  info "Installing kubectx via krew…"
  kubectl krew install ctx
fi

# ── Additional kubectl plugins (via krew) ─────────────────────────────────────
for KREW_PLUGIN in access-matrix deprecations gadget ktop popeye retina score sniff stern tree tail radar resource-capacity; do
  if kubectl krew list | grep -Fxq "$KREW_PLUGIN"; then
    warn "kubectl plugin $KREW_PLUGIN already installed — skipping"
  else
    info "Installing kubectl plugin $KREW_PLUGIN via krew…"
    kubectl krew install "$KREW_PLUGIN"
  fi
done

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

# ── tofuenv ───────────────────────────────────────────────────────────────────
TOFUENV_DIR="$HOME/.local/share/tofuenv"
info "Checking tofuenv…"
if [ -x "$TOFUENV_DIR/bin/tofuenv" ] && [ -z "${TOFUENV_VERSION:-}" ]; then
  warn "tofuenv already installed — skipping"
else
  info "Installing tofuenv…"
  mkdir -p "$(dirname "$TOFUENV_DIR")"
  if [ -d "$TOFUENV_DIR/.git" ] && [ -n "${TOFUENV_VERSION:-}" ]; then
    git -C "$TOFUENV_DIR" fetch --depth 1 origin "$TOFUENV_VERSION"
    git -C "$TOFUENV_DIR" checkout --detach FETCH_HEAD
  elif [ -n "${TOFUENV_VERSION:-}" ]; then
    git clone --depth=1 --branch "$TOFUENV_VERSION" https://github.com/tofuutils/tofuenv.git "$TOFUENV_DIR"
  else
    git clone --depth=1 https://github.com/tofuutils/tofuenv.git "$TOFUENV_DIR"
  fi
fi

mkdir -p "$HOME/.local/bin"
for executable in tofu tofuenv; do
  source="$TOFUENV_DIR/bin/$executable"
  target="$HOME/.local/bin/$executable"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
      continue
    fi
    warn "Existing $target found — leaving it unchanged"
    continue
  fi
  ln -s "$source" "$target"
  info "Linked $executable to $target"
done

# ── Istio CLI (istioctl) ──────────────────────────────────────────────────────
info "Checking istioctl…"
if command_exists istioctl && [ -z "${ISTIO_VERSION:-}" ]; then
  warn "istioctl already installed ($(istioctl version --short 2>/dev/null || true)) — skipping"
else
  info "Installing istioctl (latest)…"
  if [ -n "${ISTIO_VERSION:-}" ]; then
    ISTIO_TAG="$ISTIO_VERSION"
  else
    ISTIO_TAG=$(github_latest_tag "istio/istio")
  fi
  ISTIO_VERSION="${ISTIO_TAG#v}"
  if [ -z "$ISTIO_TAG" ]; then
    error "Could not resolve latest Istio version"
    exit 1
  fi
  ISTIO_TGZ="$TMPDIR_CUSTOM/istio.tar.gz"
  wget -qO "$ISTIO_TGZ" \
    "https://github.com/istio/istio/releases/download/${ISTIO_TAG}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz"
  verify_sha256 "$ISTIO_TGZ" "${ISTIO_SHA256:-}" "Istio $ISTIO_TAG"
  tar -xzf "$ISTIO_TGZ" -C "$TMPDIR_CUSTOM"
  sudo install -m 0755 "$TMPDIR_CUSTOM/istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/istioctl
fi

# ── Velero ────────────────────────────────────────────────────────────────────
info "Checking velero…"
if command_exists velero && [ -z "${VELERO_VERSION:-}" ]; then
  warn "velero already installed ($(velero version --client-only 2>/dev/null | grep Version || true)) — skipping"
else
  info "Installing velero (latest)…"
  if [ -n "${VELERO_VERSION:-}" ]; then
    VELERO_TAG="$VELERO_VERSION"
  else
    VELERO_TAG=$(github_latest_tag "vmware-tanzu/velero")
  fi
  if [ -z "$VELERO_TAG" ]; then
    error "Could not resolve latest Velero version"
    exit 1
  fi
  VELERO_TGZ="$TMPDIR_CUSTOM/velero.tar.gz"
  wget -qO "$VELERO_TGZ" \
    "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_TAG}/velero-${VELERO_TAG}-linux-amd64.tar.gz"
  verify_sha256 "$VELERO_TGZ" "${VELERO_SHA256:-}" "Velero $VELERO_TAG"
  tar -xzf "$VELERO_TGZ" -C "$TMPDIR_CUSTOM"
  sudo install -m 0755 \
    "$TMPDIR_CUSTOM/velero-${VELERO_TAG}-linux-amd64/velero" \
    /usr/local/bin/velero
fi

# ── Go ────────────────────────────────────────────────────────────────────────
info "Checking Go…"
GO_VERSION="${GO_VERSION:-$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)}"
case "$GO_VERSION" in go*) ;; *) GO_VERSION="go$GO_VERSION" ;; esac
if [ -z "$GO_VERSION" ]; then
  error "Could not resolve latest Go version"
  exit 1
fi
if command_exists go && go version 2>&1 | grep -qF "$GO_VERSION"; then
  warn "Go $GO_VERSION already installed — skipping"
else
  info "Installing Go $GO_VERSION…"
  GO_ARCHIVE="${GO_VERSION}.linux-amd64.tar.gz"
  wget -qO "$TMPDIR_CUSTOM/$GO_ARCHIVE" "https://go.dev/dl/${GO_ARCHIVE}"
  verify_sha256 "$TMPDIR_CUSTOM/$GO_ARCHIVE" "${GO_SHA256:-}" "Go $GO_VERSION"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$TMPDIR_CUSTOM/$GO_ARCHIVE"
  info "Go installed to /usr/local/go — ensure /usr/local/go/bin is in PATH"
fi

# ── EKS Node Viewer ───────────────────────────────────────────────────────────
info "Checking eks-node-viewer…"
if command_exists eks-node-viewer || [ -x "$HOME/.local/bin/eks-node-viewer" ]; then
  warn "eks-node-viewer already installed — skipping"
else
  info "Installing eks-node-viewer (latest)…"
  mkdir -p "$HOME/.local/bin"
  PATH="/usr/local/go/bin:$PATH" GOBIN="$HOME/.local/bin" \
    go install github.com/awslabs/eks-node-viewer/cmd/eks-node-viewer@latest
fi

# ── Neovim ────────────────────────────────────────────────────────────────────
info "Checking Neovim…"
if command_exists nvim; then
  warn "Neovim already installed ($(nvim --version | head -1)) — skipping"
else
  info "Installing Neovim (latest stable)…"
  NVIM_URL=$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
    | grep -oP '"browser_download_url":\s*"\K[^"]+nvim-linux-x86_64\.deb')
  if [ -z "$NVIM_URL" ]; then
    error "Could not determine Neovim download URL"
    exit 1
  fi
  NVIM_DEB="$TMPDIR_CUSTOM/nvim-linux-x86_64.deb"
  wget -qO "$NVIM_DEB" "$NVIM_URL"
  sudo apt-get install -y "$NVIM_DEB"
fi

# ── Lazygit ───────────────────────────────────────────────────────────────────
info "Checking lazygit…"
if command_exists lazygit && [ -z "${LAZYGIT_VERSION:-}" ]; then
  warn "lazygit already installed ($(lazygit --version 2>/dev/null | head -1)) — skipping"
else
  info "Installing lazygit (latest)…"
  if [ -n "${LAZYGIT_VERSION:-}" ]; then
    LG_TAG="$LAZYGIT_VERSION"
  else
    LG_TAG=$(github_latest_tag "jesseduffield/lazygit")
  fi
  case "$LG_TAG" in v*) ;; *) LG_TAG="v$LG_TAG" ;; esac
  if [ -z "$LG_TAG" ]; then
    error "Could not resolve latest lazygit version"
    exit 1
  fi
  LG_VERSION_NUM="${LG_TAG#v}"
  LG_TGZ="$TMPDIR_CUSTOM/lazygit.tar.gz"
  wget -qO "$LG_TGZ" \
    "https://github.com/jesseduffield/lazygit/releases/download/${LG_TAG}/lazygit_${LG_VERSION_NUM}_Linux_x86_64.tar.gz"
  verify_sha256 "$LG_TGZ" "${LAZYGIT_SHA256:-}" "lazygit $LG_TAG"
  tar -xzf "$LG_TGZ" -C "$TMPDIR_CUSTOM" lazygit
  sudo install -m 0755 "$TMPDIR_CUSTOM/lazygit" /usr/local/bin/lazygit
fi

# ── SDKMAN + Java ─────────────────────────────────────────────────────────────
info "Checking SDKMAN…"
if [ -d "${SDKMAN_DIR:-$HOME/.sdkman}" ]; then
  if [ -z "${SDKMAN_VERSION:-}${SDKMAN_NATIVE_VERSION:-}" ]; then
    warn "SDKMAN already installed — skipping"
  else
    error "SDKMAN is already installed; remove it before applying SDKMAN version pins"
    exit 1
  fi
else
  info "Installing SDKMAN…"
  SDKMAN_INSTALLER="$TMPDIR_CUSTOM/sdkman-install.sh"
  curl -fsSL "https://get.sdkman.io?ci=true&rcupdate=false" -o "$SDKMAN_INSTALLER"
  verify_sha256 "$SDKMAN_INSTALLER" "${SDKMAN_INSTALLER_SHA256:-}" "SDKMAN installer"
  if [ -n "${SDKMAN_VERSION:-}${SDKMAN_NATIVE_VERSION:-}" ]; then
    case "${SDKMAN_VERSION:-}" in *[!0123456789.]*) error "SDKMAN_VERSION must be numeric"; exit 1 ;; esac
    case "${SDKMAN_NATIVE_VERSION:-}" in *[!0123456789.]*) error "SDKMAN_NATIVE_VERSION must be numeric"; exit 1 ;; esac
    awk -v version="${SDKMAN_VERSION:-}" -v native_version="${SDKMAN_NATIVE_VERSION:-}" '
      /^export SDKMAN_VERSION=/ && version != "" { print "export SDKMAN_VERSION=\"" version "\""; next }
      /^export SDKMAN_NATIVE_VERSION=/ && native_version != "" { print "export SDKMAN_NATIVE_VERSION=\"" native_version "\""; next }
      { print }
    ' "$SDKMAN_INSTALLER" > "$TMPDIR_CUSTOM/sdkman-pinned-install.sh"
    SDKMAN_INSTALLER="$TMPDIR_CUSTOM/sdkman-pinned-install.sh"
  fi
  bash "$SDKMAN_INSTALLER"
fi

# ── Zsh + Oh-My-Zsh ──────────────────────────────────────────────────────────
info "Configuring Zsh as default shell…"
if [ "${SHELL:-}" = "$(command -v zsh)" ]; then
  warn "Zsh already the default shell — skipping chsh"
else
  chsh -s "$(which zsh)"
fi

info "Checking Oh-My-Zsh…"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if [ -d "$ZSH_DIR" ] && [ -z "${OH_MY_ZSH_VERSION:-}" ]; then
  warn "Oh-My-Zsh already installed — skipping"
else
  info "Installing Oh-My-Zsh…"
  if [ -d "$ZSH_DIR/.git" ] && [ -n "${OH_MY_ZSH_VERSION:-}" ]; then
    git -C "$ZSH_DIR" fetch --depth 1 origin "$OH_MY_ZSH_VERSION"
    git -C "$ZSH_DIR" checkout --detach FETCH_HEAD
  elif [ -n "${OH_MY_ZSH_VERSION:-}" ]; then
    git clone --depth=1 --branch "$OH_MY_ZSH_VERSION" https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
  else
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended
  fi
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
AUTOSUGGESTIONS_DIR="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
if [ -d "$AUTOSUGGESTIONS_DIR" ] && [ -z "${ZSH_AUTOSUGGESTIONS_VERSION:-}" ]; then
  warn "zsh-autosuggestions already cloned — skipping"
else
  if [ -d "$AUTOSUGGESTIONS_DIR/.git" ] && [ -n "${ZSH_AUTOSUGGESTIONS_VERSION:-}" ]; then
    git -C "$AUTOSUGGESTIONS_DIR" fetch --depth 1 origin "$ZSH_AUTOSUGGESTIONS_VERSION"
    git -C "$AUTOSUGGESTIONS_DIR" checkout --detach FETCH_HEAD
  elif [ -n "${ZSH_AUTOSUGGESTIONS_VERSION:-}" ]; then
    git clone --depth=1 --branch "$ZSH_AUTOSUGGESTIONS_VERSION" https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGESTIONS_DIR"
  else
    git clone https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGESTIONS_DIR"
  fi
fi

# ── bat symlink ───────────────────────────────────────────────────────────────
info "Configuring bat symlink…"
mkdir -p ~/.local/bin
if [ ! -e "$HOME/.local/bin/bat" ]; then
  ln -s "$(which batcat)" ~/.local/bin/bat
  info "Symlink created: ~/.local/bin/bat"
else
  warn "$HOME/.local/bin/bat already exists — skipping"
fi

# ── fd symlink ────────────────────────────────────────────────────────────────
info "Configuring fd symlink…"
if [ ! -e "$HOME/.local/bin/fd" ]; then
  ln -s "$(which fdfind)" ~/.local/bin/fd
  info "Symlink created: ~/.local/bin/fd"
else
  warn "$HOME/.local/bin/fd already exists — skipping"
fi

# ── fzf ───────────────────────────────────────────────────────────────────────
info "Checking fzf…"
if [ -d "$HOME/.fzf" ] && [ -z "${FZF_VERSION:-}" ]; then
  warn "fzf already cloned — skipping"
else
  if [ -d "$HOME/.fzf/.git" ] && [ -n "${FZF_VERSION:-}" ]; then
    git -C "$HOME/.fzf" fetch --depth 1 origin "$FZF_VERSION"
    git -C "$HOME/.fzf" checkout --detach FETCH_HEAD
  elif [ -n "${FZF_VERSION:-}" ]; then
    git clone --depth=1 --branch "$FZF_VERSION" https://github.com/junegunn/fzf.git "$HOME/.fzf"
  else
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  fi
  "$HOME/.fzf/install" --all --no-bash --no-fish
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
if command_exists jetbrains-toolbox && [ -z "${JETBRAINS_TOOLBOX_VERSION:-}" ]; then
  warn "JetBrains Toolbox already installed — skipping"
else
  info "Installing JetBrains Toolbox (latest)…"
  JB_API="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
  if [ -n "${JETBRAINS_TOOLBOX_VERSION:-}" ]; then
    JB_API="https://data.services.jetbrains.com/products/releases?code=TBA&version=${JETBRAINS_TOOLBOX_VERSION}&type=release"
  fi
  JB_RELEASE=$(curl -fsSL "$JB_API")
  JB_URL=$(printf '%s' "$JB_RELEASE" | jq -r '.TBA[0].downloads.linux.link // empty')
  JB_CHECKSUM_URL=$(printf '%s' "$JB_RELEASE" | jq -r '.TBA[0].downloads.linux.checksumLink // empty')
  if [ -z "$JB_URL" ]; then
    error "Could not determine JetBrains Toolbox download URL"
    exit 1
  fi
  JB_TGZ="$TMPDIR_CUSTOM/toolbox.tar.gz"
  wget -qO "$JB_TGZ" "$JB_URL"
  if [ -n "${JETBRAINS_TOOLBOX_SHA256:-}" ]; then
    verify_sha256 "$JB_TGZ" "$JETBRAINS_TOOLBOX_SHA256" "JetBrains Toolbox"
  elif [ -n "$JB_CHECKSUM_URL" ]; then
    JB_CHECKSUM=$(curl -fsSL "$JB_CHECKSUM_URL" | grep -oE '^[0-9a-fA-F]{64}')
    verify_sha256 "$JB_TGZ" "$JB_CHECKSUM" "JetBrains Toolbox"
  fi
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

# .k9s/          →  ~/.config/k9s
# k9s looks for config.yaml, skin.yaml, aliases.yaml etc. under this dir.
link_dotfile "$DOTFILES_DIR/.k9s"       "$HOME/.config/k9s"

info "✓ All done! Start a new shell session (or 'exec zsh') to pick up PATH changes."
info "  PATH additions to verify are in your .zshrc:"
info "    /usr/local/go/bin   (Go)"
info "    ~/.local/bin        (bat, fd, jetbrains-toolbox)"
info "    ~/.krew/bin         (kubectl plugins)"
