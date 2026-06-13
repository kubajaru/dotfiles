# ── Oh My Zsh ────────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
zstyle ':omz:update' mode reminder

plugins=(
  git
  branch
  aliases
  alias-finder
  common-aliases
  vi-mode

  zsh-autosuggestions
  zsh-interactive-cd
  fzf

  kubectl
  kubectx
  helm
  fluxcd
  terraform

  docker
  docker-compose

  golang
  tmux
  ubuntu
  ssh
)

source "$ZSH/oh-my-zsh.sh"

# ── PATH ─────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"           # bat, fd, jetbrains-toolbox
export PATH="/usr/local/go/bin:$PATH"          # Go
export PATH="$HOME/.krew/bin:$PATH"            # kubectl plugins (krew)
export PATH="/usr/local/bin:$PATH"

# ── Editor ───────────────────────────────────────────────────────────────────
if [[ -n "$SSH_CONNECTION" ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi
export KUBE_EDITOR='nvim'
export MANPATH="/usr/local/man:$MANPATH"

# ── GPG ──────────────────────────────────────────────────────────────────────
export GPG_TTY=$(tty)

# ── fzf ──────────────────────────────────────────────────────────────────────
export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
export FZF_DEFAULT_OPTS="
  --preview 'bat --color=always --style=numbers --line-range=:500 {}'
  --bind 'ctrl-/:toggle-preview'
  --height=80% --layout=reverse --border
"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ── Aliases ──────────────────────────────────────────────────────────────────
alias zshconfig="$EDITOR ~/.zshrc"
alias ohmyzsh="$EDITOR ~/.oh-my-zsh"
alias ll="ls -lha"
alias cat="bat --paging=never"
alias lg="lazygit"
alias tf="terraform"
alias tofu="tofu"
alias k="kubectl"
alias kctx="kubectl ctx"

# ── SDKMAN (must remain last) ────────────────────────────────────────────────
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
