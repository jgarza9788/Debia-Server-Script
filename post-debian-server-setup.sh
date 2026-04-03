#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (or with sudo)."
  exit 1
fi

TARGET_USER="${SUDO_USER:-${USER:-root}}"
TARGET_HOME="$(eval echo "~${TARGET_USER}")"
BASHRC_PATH="${TARGET_HOME}/.bashrc"
BACKUP_PATH="${BASHRC_PATH}.backup.$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC_TEMPLATE="${SCRIPT_DIR}/bashrc.proxmox.template"

log() {
  printf '\n==> %s\n' "$1"
}

install_base_packages() {
  log "Updating apt cache"
  apt-get update

  log "Installing base server tools"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
    ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed, skipping"
  else
    log "Installing Docker from Debian repositories"
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-plugin
  fi

  systemctl enable --now docker

  if id -nG "${TARGET_USER}" | grep -qw docker; then
    log "User ${TARGET_USER} already in docker group"
  else
    usermod -aG docker "${TARGET_USER}"
    log "Added ${TARGET_USER} to docker group (re-login required)"
  fi
}

install_cockpit() {
  if dpkg -s cockpit >/dev/null 2>&1; then
    log "Cockpit already installed, skipping"
  else
    log "Installing Cockpit web console"
    DEBIAN_FRONTEND=noninteractive apt-get install -y cockpit
  fi

  systemctl enable --now cockpit.socket
}

configure_bashrc() {
  if [[ ! -f "${BASHRC_TEMPLATE}" ]]; then
    echo "Missing template: ${BASHRC_TEMPLATE}"
    exit 1
  fi

  if [[ -f "${BASHRC_PATH}" ]]; then
    cp -a "${BASHRC_PATH}" "${BACKUP_PATH}"
    log "Backed up existing .bashrc to ${BACKUP_PATH}"
  fi

  install -o "${TARGET_USER}" -g "${TARGET_USER}" -m 0644 "${BASHRC_TEMPLATE}" "${BASHRC_PATH}"
  log "Installed new .bashrc for ${TARGET_USER}"
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
}

main() {
  install_base_packages
  install_docker
  install_cockpit
  configure_bashrc
  final_notes
}

main "$@"
