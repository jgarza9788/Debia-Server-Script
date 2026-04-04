#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-${USER:-root}}"
TARGET_HOME="$(eval echo "~${TARGET_USER}")"
BASHRC_PATH="${TARGET_HOME}/.bashrc"
BACKUP_PATH="${BASHRC_PATH}.backup.$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC_TEMPLATE="${SCRIPT_DIR}/bashrc.proxmox.template"
INTERACTIVE=true
DRY_RUN=false
INSTALL_BASE=true
INSTALL_DOCKER=true
INSTALL_COCKPIT=true
CONFIGURE_BASHRC=true
CONFIGURE_FIREWALL=false
CONFIGURE_FAIL2BAN=false
HARDEN_SSH=false
BASHRC_MODE="replace" # replace | append | skip
SUMMARY=()

log() {
  printf '\n==> %s\n' "$1"
}

show_intro_banner() {
  if [[ "${INTERACTIVE}" != "true" ]]; then
    return 0
  fi

  cat <<'EOF'
==========================================
   ____       _     _       
  |  _ \  ___| |__ (_) __ _ 
  | | | |/ _ \ '_ \| |/ _` |
  | |_| |  __/ |_) | | (_| |
  |____/ \___|_.__/|_|\__,_|

        Server Bootstrap
==========================================
This script prepares a Debian server with
optional tooling, services, and hardening.
EOF
}

usage() {
  cat <<USAGE
Usage:
  sudo ./bootstrap.sh [options]

Options:
  --yes, --non-interactive  Run without confirmation prompts
  --dry-run                 Print actions without executing changes
  --minimal                 Install base packages only (skip docker/cockpit/bashrc)
  --no-base                 Skip base package installation
  --no-docker               Skip Docker install/setup
  --no-cockpit              Skip Cockpit install/setup
  --no-bashrc               Skip bashrc configuration
  --hardening, --harden     Enable security hardening steps (UFW, fail2ban, SSH)
  --no-firewall             Skip firewall hardening even when --hardening is set
  --no-fail2ban             Skip fail2ban setup even when --hardening is set
  --no-harden-ssh           Skip SSH hardening even when --hardening is set
  --harden-ssh              Enable SSH hardening step
  --bashrc-mode MODE        Bashrc mode: replace | append | skip
  (Interactive mode includes an intro banner, all/some/none selection, and plan confirmation.)
  --help                    Show this help text
USAGE
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] %q ' "$@"
    echo
    return 0
  fi
  "$@"
}

confirm_step() {
  local prompt="$1"
  if [[ "${INTERACTIVE}" != "true" ]]; then
    return 0
  fi
  read -r -p "${prompt} [y/N]: " reply
  [[ "${reply}" =~ ^[Yy]$ ]]
}

record_status() {
  SUMMARY+=("$1")
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-N}"
  local reply=""
  local suffix="[y/N]"
  local is_yes_default=false

  if [[ "${default}" == "Y" ]]; then
    suffix="[Y/n]"
    is_yes_default=true
  fi

  while true; do
    read -r -p "${prompt} ${suffix}: " reply
    if [[ -z "${reply}" ]]; then
      [[ "${is_yes_default}" == "true" ]]
      return $?
    fi
    case "${reply}" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO)
        return 1
        ;;
      *)
        echo "Please answer y or n."
        ;;
    esac
  done
}

interactive_selection_menu() {
  if [[ "${INTERACTIVE}" != "true" ]]; then
    return 0
  fi

  local choice=""
  echo
  echo "Selection profile:"
  echo "  1) All  - install/configure everything"
  echo "  2) Some - choose each component"
  echo "  3) None - do not apply changes"

  while true; do
    read -r -p "Choose [1-3]: " choice
    case "${choice}" in
      1)
        INSTALL_BASE=true
        INSTALL_DOCKER=true
        INSTALL_COCKPIT=true
        CONFIGURE_BASHRC=true
        if prompt_yes_no "Include security hardening (UFW + fail2ban + SSH)?" "N"; then
          CONFIGURE_FIREWALL=true
          CONFIGURE_FAIL2BAN=true
          HARDEN_SSH=true
        else
          CONFIGURE_FIREWALL=false
          CONFIGURE_FAIL2BAN=false
          HARDEN_SSH=false
        fi
        return 0
        ;;
      2)
        if prompt_yes_no "Install base packages?" "Y"; then INSTALL_BASE=true; else INSTALL_BASE=false; fi
        if prompt_yes_no "Install/configure Docker?" "Y"; then INSTALL_DOCKER=true; else INSTALL_DOCKER=false; fi
        if prompt_yes_no "Install/configure Cockpit?" "Y"; then INSTALL_COCKPIT=true; else INSTALL_COCKPIT=false; fi
        if prompt_yes_no "Configure bashrc?" "Y"; then CONFIGURE_BASHRC=true; else CONFIGURE_BASHRC=false; fi
        if prompt_yes_no "Configure UFW firewall?" "N"; then CONFIGURE_FIREWALL=true; else CONFIGURE_FIREWALL=false; fi
        if prompt_yes_no "Enable fail2ban?" "N"; then CONFIGURE_FAIL2BAN=true; else CONFIGURE_FAIL2BAN=false; fi
        if prompt_yes_no "Apply SSH hardening?" "N"; then HARDEN_SSH=true; else HARDEN_SSH=false; fi
        return 0
        ;;
      3)
        INSTALL_BASE=false
        INSTALL_DOCKER=false
        INSTALL_COCKPIT=false
        CONFIGURE_BASHRC=false
        CONFIGURE_FIREWALL=false
        CONFIGURE_FAIL2BAN=false
        HARDEN_SSH=false
        return 0
        ;;
      *)
        echo "Invalid selection. Please choose 1, 2, or 3."
        ;;
    esac
  done
}

print_execution_plan() {
  echo
  echo "Execution plan:"
  printf '  - Base packages: %s\n' "$( [[ "${INSTALL_BASE}" == "true" ]] && echo enabled || echo skipped )"
  printf '  - Docker: %s\n' "$( [[ "${INSTALL_DOCKER}" == "true" ]] && echo enabled || echo skipped )"
  printf '  - Cockpit: %s\n' "$( [[ "${INSTALL_COCKPIT}" == "true" ]] && echo enabled || echo skipped )"
  if [[ "${CONFIGURE_BASHRC}" == "true" ]]; then
    printf '  - bashrc: enabled (%s mode)\n' "${BASHRC_MODE}"
  else
    printf '  - bashrc: skipped\n'
  fi
  printf '  - UFW firewall: %s\n' "$( [[ "${CONFIGURE_FIREWALL}" == "true" ]] && echo enabled || echo skipped )"
  printf '  - fail2ban: %s\n' "$( [[ "${CONFIGURE_FAIL2BAN}" == "true" ]] && echo enabled || echo skipped )"
  printf '  - SSH hardening: %s\n' "$( [[ "${HARDEN_SSH}" == "true" ]] && echo enabled || echo skipped )"
}

install_optional_packages() {
  local available=()
  local pkg
  for pkg in "$@"; do
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      available+=("${pkg}")
    else
      log "Optional package unavailable in current repositories, skipping: ${pkg}"
    fi
  done

  if [[ ${#available[@]} -eq 0 ]]; then
    record_status "Optional packages: none available"
    return 0
  fi

  log "Installing optional extra tools"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
  record_status "Optional packages: installed (${available[*]})"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|--non-interactive)
        INTERACTIVE=false
        ;;
      --dry-run)
        DRY_RUN=true
        INTERACTIVE=false
        ;;
      --minimal)
        INSTALL_DOCKER=false
        INSTALL_COCKPIT=false
        CONFIGURE_BASHRC=false
        ;;
      --no-base)
        INSTALL_BASE=false
        ;;
      --no-docker)
        INSTALL_DOCKER=false
        ;;
      --no-cockpit)
        INSTALL_COCKPIT=false
        ;;
      --no-bashrc)
        CONFIGURE_BASHRC=false
        ;;
      --hardening|--harden)
        CONFIGURE_FIREWALL=true
        CONFIGURE_FAIL2BAN=true
        HARDEN_SSH=true
        ;;
      --no-firewall)
        CONFIGURE_FIREWALL=false
        ;;
      --no-fail2ban)
        CONFIGURE_FAIL2BAN=false
        ;;
      --no-harden-ssh)
        HARDEN_SSH=false
        ;;
      --harden-ssh)
        HARDEN_SSH=true
        ;;
      --bashrc-mode)
        BASHRC_MODE="${2:-}"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

preflight_checks() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root (or with sudo)."
    exit 1
  fi

  if [[ ! -r /etc/os-release ]] || ! grep -qi "debian" /etc/os-release; then
    echo "This script is intended for Debian systems."
    exit 1
  fi

  if [[ ! -d "/home/${TARGET_USER}" ]] && [[ "${TARGET_USER}" != "root" ]]; then
    echo "Unable to determine home directory for target user: ${TARGET_USER}"
    exit 1
  fi

  if [[ ! -d /run/systemd/system ]]; then
    echo "systemd is required for service enable/start steps."
    exit 1
  fi

  if [[ "${BASHRC_MODE}" != "replace" && "${BASHRC_MODE}" != "append" && "${BASHRC_MODE}" != "skip" ]]; then
    echo "Invalid --bashrc-mode '${BASHRC_MODE}'. Use: replace | append | skip."
    exit 1
  fi
}

on_error() {
  local line="$1"
  local cmd="$2"
  echo
  echo "Error on line ${line}: ${cmd}"
  echo "Review the output above and re-run with --dry-run to preview changes."
}

install_base_packages() {
  log "Updating apt cache"
  run_cmd apt-get update

  log "Installing base server tools"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    unzip \
    zip \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    nano \
    micro \
    bat \
    htop \
    btop \
    fzf \
    duf \
    trash-cli \
    tree \
    tmux \
    rsync \
    jq \
    ripgrep \
    fd-find \
    net-tools \
    dnsutils \
    nmap \
    ufw \
    fail2ban \
    smartmontools \
    lm-sensors \
    openssh-server \
    build-essential \
    p7zip-full \
    ncdu \
    ifupdown \
    network-manager \
    wireless-tools \
    wpasupplicant

  install_optional_packages \
    software-properties-common \
    fastfetch \
    eza \
    zoxide \
    git-delta \
    tldr \
    httpie \
    qrencode \
    ffmpeg

  # Debian packages the bat binary as batcat.
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    run_cmd ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi
  record_status "Base packages: applied"
}

install_docker() {
  if ! confirm_step "Install or configure Docker?"; then
    record_status "Docker: skipped by user"
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed, skipping"
    record_status "Docker: already installed"
  else
    log "Installing Docker from Debian repositories"
    run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-plugin
    record_status "Docker: installed"
  fi

  run_cmd systemctl enable --now docker

  if id -nG "${TARGET_USER}" | grep -qw docker; then
    log "User ${TARGET_USER} already in docker group"
    record_status "Docker group: already present for ${TARGET_USER}"
  else
    run_cmd usermod -aG docker "${TARGET_USER}"
    log "Added ${TARGET_USER} to docker group (re-login required)"
    record_status "Docker group: added ${TARGET_USER} (re-login required)"
  fi
}

install_cockpit() {
  if ! confirm_step "Install or configure Cockpit web console?"; then
    record_status "Cockpit: skipped by user"
    return 0
  fi

  if dpkg -s cockpit >/dev/null 2>&1; then
    log "Cockpit already installed, skipping"
    record_status "Cockpit: already installed"
  else
    log "Installing Cockpit web console"
    run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y cockpit
    record_status "Cockpit: installed"
  fi

  run_cmd systemctl enable --now cockpit.socket
}

configure_firewall() {
  if ! confirm_step "Configure UFW firewall with default-deny incoming policy?"; then
    record_status "UFW: skipped by user"
    return 0
  fi

  log "Configuring UFW defaults"
  run_cmd ufw default deny incoming
  run_cmd ufw default allow outgoing
  run_cmd ufw allow OpenSSH
  if [[ "${INSTALL_COCKPIT}" == "true" ]]; then
    run_cmd ufw allow 9090/tcp
  fi
  run_cmd ufw --force enable
  record_status "UFW: configured and enabled"
}

configure_fail2ban() {
  if ! confirm_step "Enable fail2ban with SSH protection?"; then
    record_status "fail2ban: skipped by user"
    return 0
  fi

  local jail_local="/etc/fail2ban/jail.local"
  if [[ ! -f "${jail_local}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "Would create ${jail_local} with SSH jail defaults"
    else
      cat >"${jail_local}" <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
    fi
    record_status "fail2ban: jail.local created"
  else
    record_status "fail2ban: existing jail.local preserved"
  fi

  run_cmd systemctl enable --now fail2ban
  record_status "fail2ban: service enabled"
}

set_sshd_option() {
  local key="$1"
  local value="$2"
  local file="$3"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "${file}"; then
    run_cmd sed -i -E "s|^[#[:space:]]*(${key})[[:space:]]+.*$|\\1 ${value}|" "${file}"
  else
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "Would append '${key} ${value}' to ${file}"
    else
      echo "${key} ${value}" >>"${file}"
    fi
  fi
}

harden_ssh() {
  if ! confirm_step "Apply SSH hardening (disable root/password login where safe)?"; then
    record_status "SSH hardening: skipped by user"
    return 0
  fi

  local sshd_config="/etc/ssh/sshd_config"
  local backup_path="${sshd_config}.backup.$(date +%Y%m%d-%H%M%S)"
  local auth_keys="${TARGET_HOME}/.ssh/authorized_keys"

  if [[ ! -f "${sshd_config}" ]]; then
    record_status "SSH hardening: skipped (missing ${sshd_config})"
    return 0
  fi

  run_cmd cp -a "${sshd_config}" "${backup_path}"
  record_status "SSH hardening: backed up sshd_config"

  set_sshd_option "PermitRootLogin" "no" "${sshd_config}"
  set_sshd_option "PubkeyAuthentication" "yes" "${sshd_config}"

  if [[ -s "${auth_keys}" ]]; then
    set_sshd_option "PasswordAuthentication" "no" "${sshd_config}"
    record_status "SSH hardening: disabled password auth (authorized_keys present)"
  else
    record_status "SSH hardening: kept password auth (no authorized_keys for ${TARGET_USER})"
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "Would validate sshd config and restart ssh service"
    record_status "SSH hardening: validation/restart planned (dry-run)"
    return 0
  fi

  if sshd -t; then
    run_cmd systemctl restart ssh
    record_status "SSH hardening: applied and ssh restarted"
  else
    record_status "SSH hardening: validation failed, restoring backup"
    run_cmd cp -a "${backup_path}" "${sshd_config}"
    run_cmd systemctl restart ssh
    return 1
  fi
}

configure_bashrc() {
  if [[ ! -f "${BASHRC_TEMPLATE}" ]]; then
    echo "Missing template: ${BASHRC_TEMPLATE}"
    exit 1
  fi

  if [[ "${BASHRC_MODE}" == "skip" ]]; then
    log "Skipping .bashrc configuration (--bashrc-mode skip)"
    record_status "bashrc: skipped"
    return 0
  fi

  if ! confirm_step "Apply bashrc mode '${BASHRC_MODE}' for ${TARGET_USER}?"; then
    record_status "bashrc: skipped by user"
    return 0
  fi

  if [[ -f "${BASHRC_PATH}" ]]; then
    run_cmd cp -a "${BASHRC_PATH}" "${BACKUP_PATH}"
    log "Backed up existing .bashrc to ${BACKUP_PATH}"
  fi

  if [[ "${BASHRC_MODE}" == "replace" ]]; then
    run_cmd install -o "${TARGET_USER}" -g "${TARGET_USER}" -m 0644 "${BASHRC_TEMPLATE}" "${BASHRC_PATH}"
    log "Installed new .bashrc for ${TARGET_USER}"
    record_status "bashrc: replaced"
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "Would append template content to .bashrc for ${TARGET_USER}"
    record_status "bashrc: append planned (dry-run)"
    return 0
  fi

  cat >>"${BASHRC_PATH}" <<'EOF'

# >>> debia-server-script managed block >>>
# Added by bootstrap.sh in append mode.
EOF
  cat "${BASHRC_TEMPLATE}" >>"${BASHRC_PATH}"
  cat >>"${BASHRC_PATH}" <<'EOF'
# <<< debia-server-script managed block <<<
EOF
  run_cmd chown "${TARGET_USER}:${TARGET_USER}" "${BASHRC_PATH}"
  log "Appended template content to .bashrc for ${TARGET_USER}"
  record_status "bashrc: appended"
}

final_notes() {
  log "Done"
  cat <<NOTES
- Reboot recommended after first run.
- If you added yourself to docker group, log out and log back in.
- Configure WiFi with: nmtui
- Verify services:
    systemctl status docker
    systemctl status cockpit.socket
    systemctl status fail2ban
    systemctl status NetworkManager
- Open Cockpit: https://<server-ip>:9090
NOTES
  echo
  echo "Summary:"
  for item in "${SUMMARY[@]}"; do
    echo "  - ${item}"
  done
}

main() {
  parse_args "$@"
  show_intro_banner
  trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR
  preflight_checks
  interactive_selection_menu
  print_execution_plan

  if [[ "${INTERACTIVE}" == "true" ]]; then
    if ! prompt_yes_no "Proceed with this plan?" "Y"; then
      echo "No changes applied."
      exit 0
    fi
  fi

  if [[ "${INSTALL_BASE}" == "true" ]]; then
    if confirm_step "Install base packages?"; then
      install_base_packages
    else
      record_status "Base packages: skipped by user"
    fi
  else
    record_status "Base packages: skipped by flag"
  fi

  if [[ "${INSTALL_DOCKER}" == "true" ]]; then
    install_docker
  else
    record_status "Docker: skipped by flag"
  fi

  if [[ "${INSTALL_COCKPIT}" == "true" ]]; then
    install_cockpit
  else
    record_status "Cockpit: skipped by flag"
  fi

  if [[ "${CONFIGURE_BASHRC}" == "true" ]]; then
    configure_bashrc
  else
    record_status "bashrc: skipped by flag"
  fi

  if [[ "${CONFIGURE_FIREWALL}" == "true" ]]; then
    configure_firewall
  else
    record_status "UFW: skipped by flag"
  fi

  if [[ "${CONFIGURE_FAIL2BAN}" == "true" ]]; then
    configure_fail2ban
  else
    record_status "fail2ban: skipped by flag"
  fi

  if [[ "${HARDEN_SSH}" == "true" ]]; then
    harden_ssh
  else
    record_status "SSH hardening: skipped by flag"
  fi

  final_notes
}

main "$@"
