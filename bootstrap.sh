#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/bootstrap.log) 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "[$(date '+%H:%M:%S')] FAILED: $*" >&2; exit 1; }

# ─── 1. System packages ────────────────────────────────────────────────────────
log "==> [1/7] Installing system packages..."
sudo dnf -y update || fail "dnf update"
sudo dnf -y install git tmux wget unzip jq docker || fail "dnf install packages"
# ripgrep and fd are in different repos on AL2023
sudo dnf -y install ripgrep 2>/dev/null || log "      ripgrep not available, skipping"
sudo dnf -y install fd-find 2>/dev/null || sudo dnf -y install fd 2>/dev/null || log "      fd not available, skipping"

log "==> [1/7] Installing gh CLI..."
sudo dnf -y install 'dnf-command(config-manager)' || fail "dnf config-manager plugin"
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || fail "add gh repo"
sudo dnf -y install gh || fail "install gh"

log "==> [1/7] System packages done."

# ─── 2. Format & mount data volume ────────────────────────────────────────────
log "==> [2/7] Setting up data volume..."

# The data volume may not be attached yet — wait up to 2 minutes
DATA_DEV=""
for i in $(seq 1 24); do
  for dev in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$dev" ]; then
      DATA_DEV="$dev"
      break 2
    fi
  done
  log "      Waiting for data volume... (attempt $i/24)"
  sleep 5
done
[ -n "$DATA_DEV" ] || fail "Could not find data volume device after 2 minutes"
log "      Data device: $DATA_DEV"

FSTYPE=$(sudo blkid -o value -s TYPE "$DATA_DEV" 2>/dev/null || true)
if [ -z "$FSTYPE" ]; then
  log "      No filesystem found — formatting as xfs..."
  sudo mkfs -t xfs "$DATA_DEV" || fail "mkfs"
else
  log "      Filesystem already exists ($FSTYPE) — skipping mkfs"
fi

sudo mkdir -p /data

if ! grep -q "$DATA_DEV" /etc/fstab; then
  echo "$DATA_DEV /data xfs defaults 0 2" | sudo tee -a /etc/fstab
  log "      Added fstab entry"
else
  log "      fstab entry already present"
fi

sudo mount -a || fail "mount -a"
df -h /data || fail "df /data"
log "==> [2/7] Data volume mounted."

# ─── 3. Directories & symlinks ─────────────────────────────────────────────────
log "==> [3/7] Creating directories and symlinks..."
sudo mkdir -p /data/repos /data/cache /data/nvm
sudo chown -R ec2-user:ec2-user /data

# Run as ec2-user for symlinks in home dir
sudo -u ec2-user bash -c '
  [ -L ~/repos ] || ln -s /data/repos ~/repos
  [ -L ~/cache ] || ln -s /data/cache ~/cache
  echo "  symlinks: $(ls -la ~/repos ~/cache)"
'
log "==> [3/7] Directories and symlinks done."

# ─── 4. nvm + Node LTS ────────────────────────────────────────────────────────
log "==> [4/7] Installing nvm and Node LTS to /data/nvm..."
sudo -u ec2-user bash -c '
  export NVM_DIR="/data/nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | NVM_DIR=/data/nvm bash
  source /data/nvm/nvm.sh
  nvm install --lts
  nvm use --lts
  node --version
  npm --version
' || fail "nvm/node install"

# Persist nvm in ec2-user bash profile
sudo -u ec2-user bash -c '
  PROFILE="$HOME/.bashrc"
  if ! grep -q "NVM_DIR" "$PROFILE"; then
    cat >> "$PROFILE" << '"'"'EOF'"'"'

# nvm
export NVM_DIR="/data/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
EOF
    echo "  nvm added to $PROFILE"
  else
    echo "  nvm already in $PROFILE"
  fi
'
log "==> [4/7] nvm and Node done."

# ─── 5. opencode ──────────────────────────────────────────────────────────────
log "==> [5/7] Installing opencode-ai..."
sudo -u ec2-user bash -c '
  export NVM_DIR="/data/nvm"
  source /data/nvm/nvm.sh
  npm install -g opencode-ai
  opencode --version
' || fail "opencode install"
log "==> [5/7] opencode done."

# ─── 6. Docker ────────────────────────────────────────────────────────────────
log "==> [6/7] Enabling Docker..."
sudo systemctl enable --now docker || fail "docker enable"
sudo usermod -aG docker ec2-user || fail "usermod docker"
log "==> [6/7] Docker done."

# ─── 7. Auto-tmux on SSH login ────────────────────────────────────────────────
log "==> [7/7] Configuring auto-tmux on SSH..."
sudo tee /etc/profile.d/tmux-attach.sh > /dev/null << 'EOF'
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
  tmux attach-session -t main 2>/dev/null || tmux new-session -s main
fi
EOF
log "==> [7/7] Auto-tmux done."

# ─── Done ─────────────────────────────────────────────────────────────────────
log ""
log "Bootstrap complete. Log saved to /var/log/bootstrap.log"
log ""
log "Summary:"
df -h /data
sudo -u ec2-user bash -c 'source /data/nvm/nvm.sh && node --version && npm --version'
opencode --version 2>/dev/null || sudo -u ec2-user bash -c 'source /data/nvm/nvm.sh && opencode --version'
docker --version
gh --version
