# Debia-Server-Script

Post-install Debian server bootstrap script.

## What this does

`post-debian-server-setup.sh` prepares a fresh Debian install with common server tooling and shell defaults:

- Installs essential admin tools (`curl`, `git`, `htop`, `tmux`, `ufw`, `fail2ban`, etc.)
- Installs requested editors/utilities (`nano`, `micro`, `bat`)
- Installs and enables Docker (`docker.io` + compose plugin)
- Installs and enables Cockpit web console (`cockpit`)
- Installs WiFi/networking tools (`network-manager`, `wpasupplicant`, `wireless-tools`)
- Ensures `sudo` is installed
- Backs up the current user's `.bashrc`
- Replaces `.bashrc` using `bashrc.proxmox.template`

## Files

- `post-debian-server-setup.sh` - main setup script
- `bashrc.proxmox.template` - Proxmox-style `.bashrc` template used by the script

## Usage

From the repo directory:

```bash
chmod +x post-debian-server-setup.sh
sudo ./post-debian-server-setup.sh
```

Or run it without changing file permissions:

```bash
sudo bash ./post-debian-server-setup.sh
```

Show available options:

```bash
sudo ./post-debian-server-setup.sh --help
```

Common examples:

```bash
# Non-interactive full run
sudo ./post-debian-server-setup.sh --yes

# Preview what would happen without making changes
sudo ./post-debian-server-setup.sh --dry-run

# Minimal setup (base packages only)
sudo ./post-debian-server-setup.sh --minimal --yes

# Skip docker and cockpit, append shell config block
sudo ./post-debian-server-setup.sh --no-docker --no-cockpit --bashrc-mode append
```

After running:

- Reboot is recommended.
- Log out/in to apply Docker group membership changes.
- Use `nmtui` to configure WiFi networks.
- Access Cockpit at `https://<server-ip>:9090`.
- Review the final run summary to see what was applied or skipped.

## Notes

- The script creates a timestamped backup like `~/.bashrc.backup.YYYYMMDD-HHMMSS`.
- On Debian, `bat` may be packaged as `batcat`; the script creates `/usr/local/bin/bat` if needed.
