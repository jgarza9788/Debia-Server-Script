# Debia-Server-Script

Post-install Debian server bootstrap script.

## What this does

`bootstrap.sh` prepares a fresh Debian install with common server tooling and shell defaults:

- Installs essential admin tools (`curl`, `git`, `htop`, `tmux`, `ufw`, `fail2ban`, etc.)
- Installs requested editors/utilities (`nano`, `micro`, `bat`)
- Installs and enables Docker (`docker.io` + compose plugin)
- Installs and enables Cockpit web console (`cockpit`)
- Installs WiFi/networking tools (`network-manager`, `wpasupplicant`, `wireless-tools`)
- Ensures `sudo` is installed
- Backs up the current user's `.bashrc`
- Replaces `.bashrc` using `bashrc.proxmox.template`

## Files

- `bootstrap.sh` - main setup script
- `bashrc.proxmox.template` - Proxmox-style `.bashrc` template used by the script

## Usage

From the repo directory:

```bash
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

Or run it without changing file permissions:

```bash
sudo bash ./bootstrap.sh
```

Run it directly without cloning the repo:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/Debia-Server-Script/main/bootstrap.sh | sudo bash
```

Show available options:

```bash
sudo ./bootstrap.sh --help
```

Common examples:

```bash
# Non-interactive full run
sudo ./bootstrap.sh --yes

# Preview what would happen without making changes
sudo ./bootstrap.sh --dry-run

# Minimal setup (base packages only)
sudo ./bootstrap.sh --minimal --yes

# Skip docker and cockpit, append shell config block
sudo ./bootstrap.sh --no-docker --no-cockpit --bashrc-mode append

# Apply security hardening profile (firewall + fail2ban + SSH hardening)
sudo ./bootstrap.sh --hardening --yes

# Firewall + fail2ban only (skip SSH hardening)
sudo ./bootstrap.sh --hardening --no-harden-ssh --yes
```

After running:

- Reboot is recommended.
- Log out/in to apply Docker group membership changes.
- Use `nmtui` to configure WiFi networks.
- Access Cockpit at `https://<server-ip>:9090`.
- Review the final run summary to see what was applied or skipped.

## Security hardening options

The script can optionally apply a hardening profile:

- `--hardening` / `--harden`: enables UFW + fail2ban + SSH hardening
- `--no-firewall`: skips UFW even if hardening is enabled
- `--no-fail2ban`: skips fail2ban even if hardening is enabled
- `--no-harden-ssh`: skips SSH hardening even if hardening is enabled
- `--harden-ssh`: enables only SSH hardening (can be used without `--hardening`)

SSH hardening is conservative:

- `PermitRootLogin` is set to `no`
- `PubkeyAuthentication` is set to `yes`
- `PasswordAuthentication` is set to `no` **only** if `${TARGET_HOME}/.ssh/authorized_keys` exists for the target user

## Notes

- The script creates a timestamped backup like `~/.bashrc.backup.YYYYMMDD-HHMMSS`.
- On Debian, `bat` may be packaged as `batcat`; the script creates `/usr/local/bin/bat` if needed.
