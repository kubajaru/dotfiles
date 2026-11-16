# Copy this file to bootstrap.local.sh, set your pins/checksums, and chmod 600 it.
# For example: cp bootstrap.local.example.sh bootstrap.local.sh
# Leave a version blank to use the installer's normal default.
# No version overrides are provided for APT-managed tools or Krew.
# shellcheck disable=SC2034

# Azure CLI accepts these tool versions and installs to temporary files first.
KUBECTL_VERSION=
KUBECTL_SHA256=
KUBELOGIN_VERSION=
KUBELOGIN_SHA256=

# GitHub release tags; checksums are SHA-256 hex for the downloaded artifact.
ISTIO_VERSION=
ISTIO_SHA256=
VELERO_VERSION=
VELERO_SHA256=
LAZYGIT_VERSION=
LAZYGIT_SHA256=

# Go accepts 1.x.y or go1.x.y.
GO_VERSION=
GO_SHA256=

# Git refs (tags or branches).
TOFUENV_VERSION=
OH_MY_ZSH_VERSION=
ZSH_AUTOSUGGESTIONS_VERSION=
FZF_VERSION=

# SDKMAN versions are numeric. The installer checksum is SHA-256 hex.
SDKMAN_VERSION=
SDKMAN_NATIVE_VERSION=
SDKMAN_INSTALLER_SHA256=

# JetBrains Toolbox requires the exact build identifier, e.g. 3.9.1.89198.
JETBRAINS_TOOLBOX_VERSION=
JETBRAINS_TOOLBOX_SHA256=