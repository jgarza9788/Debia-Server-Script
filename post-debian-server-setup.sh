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
BASHRC_MODE="replace" # replace | append | skip
SUMMARY=()

log() {
  printf '\n==> %s\n' "$1"
}

usage() {
  cat <<USAGE
Usage:
  sudo ./post-debian-server-setup.sh [options]

Options:
  --yes, --non-interactive  Run without confirmation prompts
  --dry-run                 Print actions without executing changes
  --minimal                 Install base packages only (skip docker/cockpit/bashrc)
  --no-base                 Skip base package installation
  --no-docker               Skip Docker install/setup
  --no-cockpit              Skip Cockpit install/setup
  --no-bashrc               Skip bashrc configuration
  --bashrc-mode MODE        Bashrc mode: replace | append | skip
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
    software-properties-common \
    apt-transport-https \
    nano \
    micro \
    bat \
    htop \
    btop \
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
# Added by post-debian-server-setup.sh in append mode.
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
  trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR
  preflight_checks

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

  final_notes
}

main "$@"
