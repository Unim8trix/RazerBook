export PATH=$HOME/.local/bin:$PATH
export EDITOR="nvim"
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""

plugins=(git ssh-agent zsh-autosuggestions)

source $ZSH/oh-my-zsh.sh

# Pyenv
if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi

## Kubectl Context Config
# Set the default kube context if present
DEFAULT_KUBE_CONTEXTS="$HOME/.kube/config"
if test -f "${DEFAULT_KUBE_CONTEXTS}"
then
  export KUBECONFIG="$DEFAULT_KUBE_CONTEXTS"
fi
# Additional contexts should be in ~/.kube/configs/XXXX-XXX-XX/xxx.yml/pem/..
KUBE_CONTEXTS="$HOME/.kube/configs"
mkdir -p "${KUBE_CONTEXTS}"

OIFS="$IFS"
IFS=$'\n'
for contextFile in `find "${KUBE_CONTEXTS}" -type f -name "*.yaml" -or -name "*.json"`
do
    export KUBECONFIG="$contextFile:$KUBECONFIG"
done
IFS="$OIFS"

# Alias
alias ll="ls -lah"
alias cls="clear"
alias vim="nvim"
alias kc="kubectl"

# Starship
eval "$(starship init zsh)"

# Start hyprland
if [ -z $DISPLAY ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec /home/me/hypr
fi

