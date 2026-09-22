#!/usr/bin/env bash

# ==============================================================================
# Bootstrap terminal DEV / DEVOPS / OPS — Kasm Workspaces
# ==============================================================================
#
# Adapté pour l'image : kasmweb/terminal:1.18.0-rolling-weekly
#   - Base            : kasmweb/core-ubuntu-jammy (Ubuntu 22.04 LTS)
#   - Pas de systemd  : aucun `systemctl` dans ce script
#   - Utilisateur     : kasm-user (UID 1000), sudo sans mot de passe
#   - Conteneur JETABLE : rien ne persiste d'une session à l'autre, sauf si
#     tu actives le "Persistent Profile" côté Kasm (dans ce cas le home
#     directory est conservé et les checks idempotents ci-dessous évitent
#     de tout retélécharger).
#
# Installation :
#   - Zsh + Oh My Zsh + autosuggestions + syntax highlighting
#   - Git
#   - kubectl / Helm
#   - Terraform (dépôt officiel HashiCorp)
#   - Ansible
#   - Python / Node / Go / Rust
#   - Outils Linux / réseau
#   - CLI modernes (eza, zoxide, delta, bat, ripgrep, fzf...)
#
# Usage (dans le terminal Kasm, en tant que kasm-user) :
#   chmod +x bootstrap-kasm.sh
#   sudo ./bootstrap-kasm.sh
#
# Le script est idempotent : tu peux le relancer sans risque.
#
# ==============================================================================

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

# ==============================================================================
# Configuration
# ==============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0-kasm"

readonly BACKUP_DIR="$HOME/.bootstrap-kasm-backup"

# ------------------------------------------------------------------------------
# Paquets APT
# ------------------------------------------------------------------------------

APT_PACKAGES=(
    # Shell / terminal
    zsh
    bash
    tmux
    screen

    # Documentation / utilitaires
    man-db
    manpages
    manpages-dev
    tree
    less
    vim
    nano

    # Monitoring
    htop
    btop
    iotop
    iftop
    ncdu

    # Réseau
    curl
    wget
    ca-certificates
    dnsutils
    iputils-ping
    net-tools
    iproute2
    traceroute
    mtr-tiny
    nmap
    socat
    netcat-openbsd
    openssh-client

    # Archives
    zip
    unzip
    tar
    gzip
    bzip2
    xz-utils
    p7zip-full

    # Dev
    git
    git-lfs
    build-essential
    pkg-config
    make
    gcc
    g++
    autoconf
    automake

    # Data / CLI
    jq
    ripgrep
    fd-find
    fzf
    bat

    # Python
    python3
    python3-pip
    python3-venv
    python3-dev

    # Sécurité / crypto
    gnupg
    openssl
    age
    pass

    # Compression / JSON / YAML
    yq

    # Process / système
    procps
    psmisc
    lsof
    strace
    rsync
    file
    util-linux

    # Compilation
    clang
    llvm

    # Nécessaire pour le dépôt HashiCorp
    software-properties-common
    lsb-release
)

# ------------------------------------------------------------------------------
# Outils installés via les releases officielles / dépôts tiers
# ------------------------------------------------------------------------------

INSTALL_ZOXIDE=true
INSTALL_EZA=true
INSTALL_DELTA=true

# DevOps
INSTALL_DOCKER_CLI=false   # pas de daemon systemd dans Kasm — CLI seule, utile si DOCKER_HOST distant
INSTALL_KUBECTL=true
INSTALL_HELM=true
INSTALL_TERRAFORM=true
INSTALL_ANSIBLE=true

# Languages
INSTALL_GO=true
INSTALL_NODE=true
INSTALL_RUST=true

# Zsh
INSTALL_OH_MY_ZSH=true
INSTALL_ZSH_PLUGINS=true

# ==============================================================================
# Couleurs
# ==============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    RESET=''
fi

# ==============================================================================
# Logging
# ==============================================================================

log() {
    printf '%b[%s]%b %s\n' "$CYAN" "$(date '+%H:%M:%S')" "$RESET" "$*"
}

success() {
    printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$*"
}

warning() {
    printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"
}

error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$*" >&2
}

die() {
    error "$*"
    exit 1
}

section() {
    printf '\n%b========================================%b\n' "$BLUE" "$RESET"
    printf '%b%s%b\n' "$BLUE" "$*" "$RESET"
    printf '%b========================================%b\n\n' "$BLUE" "$RESET"
}

# ==============================================================================
# Gestion erreurs
# ==============================================================================

trap 'error "Erreur ligne ${LINENO}: ${BASH_COMMAND}"' ERR

# ==============================================================================
# Vérification
# ==============================================================================

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Ce script doit être exécuté avec sudo (ex: sudo ./${SCRIPT_NAME})."
    fi
}

detect_user() {

    if [[ -n "${SUDO_USER:-}" ]]; then
        TARGET_USER="$SUDO_USER"
    else
        TARGET_USER="$(logname 2>/dev/null || echo "kasm-user")"
    fi

    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    [[ -d "$TARGET_HOME" ]] || die "Impossible de déterminer HOME de $TARGET_USER."

    log "Utilisateur cible : $TARGET_USER"
    log "HOME cible        : $TARGET_HOME"
}

detect_os() {

    [[ -f /etc/os-release ]] || die "/etc/os-release introuvable."

    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID}" in
        debian|ubuntu)
            OS="${ID}"
            OS_CODENAME="${VERSION_CODENAME:-jammy}"
            ;;
        *)
            die "OS non supporté : ${ID}"
            ;;
    esac

    log "OS détecté : ${PRETTY_NAME} (${OS_CODENAME})"
}

# ==============================================================================
# Commandes exécutées pour l'utilisateur cible
# ==============================================================================

run_as_user() {
    sudo -u "$TARGET_USER" -H "$@"
}

# ==============================================================================
# APT
# ==============================================================================

apt_update() {

    section "APT"

    apt-get update
}

apt_install_packages() {

    log "Installation des paquets système..."

    local packages=()

    for package in "${APT_PACKAGES[@]}"; do

        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
            grep -q "install ok installed"; then

            packages+=("$package")
        fi

    done

    if [[ "${#packages[@]}" -eq 0 ]]; then
        success "Tous les paquets APT sont déjà installés."
        return
    fi

    log "Paquets à installer : ${#packages[@]}"

    apt-get install -y "${packages[@]}"

    success "Paquets système installés."
}

# ==============================================================================
# Installation Git
# ==============================================================================

configure_git() {

    section "Git"

    if ! run_as_user git config --global init.defaultBranch >/dev/null 2>&1; then
        run_as_user git config --global init.defaultBranch main
    fi

    run_as_user git config --global pull.rebase false

    success "Git configuré."
}

# ==============================================================================
# Oh My Zsh
# ==============================================================================

install_oh_my_zsh() {

    section "Oh My Zsh"

    [[ "$INSTALL_OH_MY_ZSH" == true ]] || return

    local ohmyzsh="${TARGET_HOME}/.oh-my-zsh"

    if [[ -d "$ohmyzsh" ]]; then
        success "Oh My Zsh déjà installé."
        return
    fi

    log "Installation de Oh My Zsh..."

    run_as_user env \
        RUNZSH=no \
        CHSH=no \
        KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    success "Oh My Zsh installé."
}

# ==============================================================================
# Plugins Zsh
# ==============================================================================

install_zsh_plugins() {

    section "Plugins Zsh"

    [[ "$INSTALL_ZSH_PLUGINS" == true ]] || return

    local plugins_dir="${TARGET_HOME}/.oh-my-zsh/custom/plugins"

    mkdir -p "$plugins_dir"

    chown -R "$TARGET_USER:$TARGET_USER" "$plugins_dir"

    if [[ ! -d "${plugins_dir}/zsh-autosuggestions" ]]; then
        run_as_user git clone --depth 1 \
            https://github.com/zsh-users/zsh-autosuggestions.git \
            "${plugins_dir}/zsh-autosuggestions"
    else
        success "zsh-autosuggestions déjà installé."
    fi

    if [[ ! -d "${plugins_dir}/zsh-syntax-highlighting" ]]; then
        run_as_user git clone --depth 1 \
            https://github.com/zsh-users/zsh-syntax-highlighting.git \
            "${plugins_dir}/zsh-syntax-highlighting"
    else
        success "zsh-syntax-highlighting déjà installé."
    fi

    if [[ ! -d "${plugins_dir}/zsh-completions" ]]; then
        run_as_user git clone --depth 1 \
            https://github.com/zsh-users/zsh-completions.git \
            "${plugins_dir}/zsh-completions"
    else
        success "zsh-completions déjà installé."
    fi
}

# ==============================================================================
# Configuration Zsh
# ==============================================================================

configure_zsh() {

    section "Configuration Zsh"

    local zshrc="${TARGET_HOME}/.zshrc"

    if [[ -f "$zshrc" && ! -f "${zshrc}.bootstrap-backup" ]]; then
        cp -a "$zshrc" "${zshrc}.bootstrap-backup"
    fi

    cat > "$zshrc" <<'EOF'
# ==============================================================================
# ~/.zshrc — Bootstrap DEV / DEVOPS / OPS (Kasm)
# ==============================================================================

export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"

# --------------------------------------------------------------------------
# Oh My Zsh
# --------------------------------------------------------------------------

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
    git
    kubectl
    helm
    terraform
    ansible
    python
    sudo
    command-not-found
    zsh-autosuggestions
    zsh-syntax-highlighting
)

if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
    source "$ZSH/oh-my-zsh.sh"
fi

# --------------------------------------------------------------------------
# Completion
# --------------------------------------------------------------------------

autoload -Uz compinit
compinit

# --------------------------------------------------------------------------
# History
# --------------------------------------------------------------------------

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt EXTENDED_HISTORY

# --------------------------------------------------------------------------
# Navigation
# --------------------------------------------------------------------------

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt CORRECT

# --------------------------------------------------------------------------
# Completion UI
# --------------------------------------------------------------------------

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' use-cache on

# --------------------------------------------------------------------------
# Aliases
# --------------------------------------------------------------------------

alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias ports='ss -tulpn'
alias myip='curl -4 ifconfig.me'

alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'

# --------------------------------------------------------------------------
# Modern CLI
# --------------------------------------------------------------------------

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons'
    alias ll='eza -lah --icons'
    alias la='eza -a --icons'
fi

if command -v batcat >/dev/null 2>&1; then
    alias cat='batcat'
elif command -v bat >/dev/null 2>&1; then
    alias cat='bat'
fi

if command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
fi

if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

if command -v fzf >/dev/null 2>&1; then
    source <(fzf --zsh 2>/dev/null || true)
fi

# --------------------------------------------------------------------------
# Prompt
# --------------------------------------------------------------------------

PROMPT='%F{cyan}%n%f@%F{blue}%m%f:%F{green}%~%f %# '

# --------------------------------------------------------------------------
# Kubernetes
# --------------------------------------------------------------------------

if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion zsh)
    compdef k=kubectl
fi

# --------------------------------------------------------------------------
# Useful functions
# --------------------------------------------------------------------------

mkcd() {
    mkdir -p "$1" && cd "$1"
}

extract() {

    if [[ ! -f "$1" ]]; then
        echo "Fichier introuvable : $1"
        return 1
    fi

    case "$1" in
        *.tar.gz|*.tgz) tar xzf "$1" ;;
        *.tar.bz2) tar xjf "$1" ;;
        *.tar.xz) tar xJf "$1" ;;
        *.tar) tar xf "$1" ;;
        *.zip) unzip "$1" ;;
        *.7z) 7z x "$1" ;;
        *) echo "Format non supporté : $1" ;;
    esac
}
EOF

    chown "$TARGET_USER:$TARGET_USER" "$zshrc"

    success "Zsh configuré."
}

# ==============================================================================
# Docker CLI (pas de daemon — pas de systemd dans Kasm)
# ==============================================================================

install_docker_cli() {

    section "Docker CLI"

    [[ "$INSTALL_DOCKER_CLI" == true ]] || { log "Docker CLI désactivé (INSTALL_DOCKER_CLI=false)."; return; }

    if command -v docker >/dev/null 2>&1; then
        success "Docker CLI déjà installé."
        return
    fi

    log "Installation de Docker CLI (client uniquement, pas de daemon local)..."

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${OS_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce-cli docker-compose-plugin

    warning "Docker CLI installé sans daemon (pas de systemd ici). Utilise DOCKER_HOST pour pointer vers un daemon distant, ou monte /var/run/docker.sock si le conteneur Kasm le permet."

    success "Docker CLI installé."
}

# ==============================================================================
# Kubernetes
# ==============================================================================

install_kubectl() {

    section "kubectl"

    [[ "$INSTALL_KUBECTL" == true ]] || return

    if command -v kubectl >/dev/null 2>&1; then
        success "kubectl déjà installé."
        return
    fi

    local version
    version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"

    curl -fsSL \
        "https://dl.k8s.io/release/${version}/bin/linux/$(dpkg --print-architecture)/kubectl" \
        -o /tmp/kubectl

    install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl

    success "kubectl installé : ${version}"
}

# ==============================================================================
# Helm
# ==============================================================================

install_helm() {

    section "Helm"

    [[ "$INSTALL_HELM" == true ]] || return

    if command -v helm >/dev/null 2>&1; then
        success "Helm déjà installé."
        return
    fi

    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    success "Helm installé."
}

# ==============================================================================
# Terraform (dépôt officiel HashiCorp — pas dispo dans les dépôts Ubuntu)
# ==============================================================================

install_terraform() {

    section "Terraform"

    [[ "$INSTALL_TERRAFORM" == true ]] || return

    if command -v terraform >/dev/null 2>&1; then
        success "Terraform déjà installé."
        return
    fi

    log "Ajout du dépôt HashiCorp..."

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://apt.releases.hashicorp.com/gpg -o /etc/apt/keyrings/hashicorp.asc
    chmod a+r /etc/apt/keyrings/hashicorp.asc

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp.asc] https://apt.releases.hashicorp.com ${OS_CODENAME} main" \
        > /etc/apt/sources.list.d/hashicorp.list

    apt-get update
    apt-get install -y terraform

    success "Terraform installé."
}

# ==============================================================================
# Ansible
# ==============================================================================

install_ansible() {

    section "Ansible"

    [[ "$INSTALL_ANSIBLE" == true ]] || return

    if command -v ansible >/dev/null 2>&1; then
        success "Ansible déjà installé."
        return
    fi

    apt-get install -y ansible

    success "Ansible installé."
}

# ==============================================================================
# Go
# ==============================================================================

install_go() {

    section "Go"

    [[ "$INSTALL_GO" == true ]] || return

    if command -v go >/dev/null 2>&1; then
        success "Go déjà installé."
        return
    fi

    apt-get install -y golang

    success "Go installé."
}

# ==============================================================================
# Node.js
# ==============================================================================

install_node() {

    section "Node.js"

    [[ "$INSTALL_NODE" == true ]] || return

    if command -v node >/dev/null 2>&1; then
        success "Node.js déjà installé."
        return
    fi

    apt-get install -y nodejs npm

    success "Node.js installé."
}

# ==============================================================================
# Rust
# ==============================================================================

install_rust() {

    section "Rust"

    [[ "$INSTALL_RUST" == true ]] || return

    if run_as_user command -v rustc >/dev/null 2>&1; then
        success "Rust déjà installé."
        return
    fi

    run_as_user bash -c \
        'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'

    success "Rust installé."
}

# ==============================================================================
# CLI modernes
# ==============================================================================

install_modern_cli() {

    section "CLI modernes"

    if [[ "$INSTALL_EZA" == true ]] && ! command -v eza >/dev/null 2>&1; then

        log "Installation de eza..."

        local arch
        arch="$(dpkg --print-architecture)"

        case "$arch" in
            amd64)
                curl -fsSL \
                    https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz \
                    -o /tmp/eza.tar.gz
                ;;
            arm64)
                curl -fsSL \
                    https://github.com/eza-community/eza/releases/latest/download/eza_aarch64-unknown-linux-gnu.tar.gz \
                    -o /tmp/eza.tar.gz
                ;;
            *)
                warning "Architecture non supportée pour eza : $arch"
                ;;
        esac

        if [[ -f /tmp/eza.tar.gz ]]; then
            tar -xzf /tmp/eza.tar.gz -C /tmp
            install -m 0755 /tmp/eza /usr/local/bin/eza
            rm -rf /tmp/eza /tmp/eza.tar.gz
        fi
    fi

    if [[ "$INSTALL_ZOXIDE" == true ]] && ! command -v zoxide >/dev/null 2>&1; then
        log "Installation de zoxide..."
        run_as_user bash -c \
            'curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh'
    fi

    if [[ "$INSTALL_DELTA" == true ]] && ! command -v delta >/dev/null 2>&1; then
        if apt-cache show git-delta >/dev/null 2>&1; then
            apt-get install -y git-delta
        else
            warning "git-delta indisponible dans les dépôts APT."
        fi
    fi

    success "CLI modernes traitées."
}

# ==============================================================================
# Validation
# ==============================================================================

validate_installation() {

    section "Validation"

    local commands=(
        zsh git curl jq rg fzf kubectl helm terraform ansible
    )

    local failed=0

    for command in "${commands[@]}"; do
        if command -v "$command" >/dev/null 2>&1; then
            printf '  %-15s %bOK%b\n' "$command" "$GREEN" "$RESET"
        else
            printf '  %-15s %bABSENT%b\n' "$command" "$RED" "$RESET"
            failed=1
        fi
    done

    printf '\n'

    if [[ "$failed" -eq 0 ]]; then
        success "Validation terminée."
    else
        warning "Certains outils sont absents. Voir les messages ci-dessus."
    fi
}

# ==============================================================================
# Résumé
# ==============================================================================

show_summary() {

    section "Installation terminée"

    cat <<EOF

Utilisateur : $TARGET_USER
HOME        : $TARGET_HOME
OS          : $PRETTY_NAME

Configuration : $TARGET_HOME/.zshrc
Backup        : $BACKUP_DIR

RAPPEL — conteneur jetable :
  Rien ne persiste à la prochaine session Kasm, sauf profil persistant activé.
  Relance simplement ce script à chaque nouvelle session.

Pour basculer sur Zsh MAINTENANT (dans cette session) :
  exec zsh

EOF

    success "Bootstrap DEV/DEVOPS/OPS Kasm terminé."
}

# ==============================================================================
# Main
# ==============================================================================

main() {

    section "Bootstrap DEV / DEVOPS / OPS — Kasm v${SCRIPT_VERSION}"

    require_root
    detect_user
    detect_os

    apt_update
    apt_install_packages

    configure_git

    install_docker_cli
    install_kubectl
    install_helm
    install_terraform
    install_ansible

    install_go
    install_node
    install_rust

    install_modern_cli

    install_oh_my_zsh
    install_zsh_plugins
    configure_zsh

    validate_installation
    show_summary
}

main "$@"