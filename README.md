# Agent Workstation (EC2 + Hibernate)

A stateful, on-demand remote workstation for safely running AI coding agents
(OpenCode, Claude Code, etc.) with persistent state and cost-efficient hibernation.

## Goals

1. **Reduce local blast radius** — a bad agent command affects the EC2 instance only, not your laptop
2. **Preserve context** — git repos, caches, and toolchains persist on a separate EBS data volume; EC2 hibernate preserves RAM and tmux sessions
3. **Secure remote access** — SSM Session Manager by default; no inbound ports required
4. **Least privilege** — instance IAM role contains only `AmazonSSMManagedInstanceCore`

## Architecture

```
Developer
   |
   |  aws ssm start-session  (or SSH)
   v
EC2 Instance (Agent Workstation)
   - Amazon Linux 2023
   - tmux, git, docker, gh CLI
   - nvm + Node LTS
   - opencode-ai
   |
   +-- /dev/xvda  (root, 30 GiB, DeleteOnTermination=true)
   +-- /dev/sdf   (data, 120 GiB, DeletionPolicy=Retain)
                      /data/repos    ~/repos -> /data/repos
                      /data/cache    ~/cache -> /data/cache
                      /data/nvm      (nvm + Node, persists across reprovision)
```

## Storage Design

Two volumes, two different lifecycles:

| Volume | Device | Size | Fate on termination | Purpose |
|--------|--------|------|---------------------|---------|
| Root | `/dev/xvda` | 30 GiB gp3 | **Deleted** | OS + system packages (disposable) |
| Data | `/dev/sdf` | 120 GiB gp3 | **Retained** (`DeletionPolicy: Retain`) | Repos, caches, nvm, toolchains |

The data volume is a standalone `AWS::EC2::Volume` resource. It survives instance
termination and stack deletion. On first boot it is formatted and mounted at `/data`.
On subsequent boots (hibernate resume or normal start) it is mounted from `/etc/fstab`.

## Quick Start

```bash
chmod +x *.sh

# Deploy (waits for bootstrap to complete via cfn-signal — ~5-10 min)
./deploy.sh

# Connect
./connect-ssm.sh

# Hibernate at end of session
./hibernate.sh

# Resume next session
./start.sh && ./connect-ssm.sh

# Check instance state
./status.sh
```

## Deploy Parameters

All parameters have defaults. Override via environment variables before running `deploy.sh`:

| Env var | CFN parameter | Default | Description |
|---------|--------------|---------|-------------|
| `INSTANCE_TYPE` | `InstanceType` | `t3a.xlarge` | 4 vCPU / 16 GB RAM |
| `ROOT_VOL` | `RootVolumeGiB` | `30` | Root EBS size |
| `DATA_VOL` | `DataVolumeGiB` | `120` | Data EBS size |
| `KEY_NAME` | `KeyName` | _(empty)_ | EC2 KeyPair for SSH; leave empty for SSM-only |
| `ENABLE_SSH_INGRESS` | `EnableSshIngressFromMyIp` | `false` | Add SSH SG rule (update IP with `allow-ssh-my-ip.sh`) |

Example with overrides:

```bash
INSTANCE_TYPE=t3a.large ROOT_VOL=20 DATA_VOL=200 ./deploy.sh
```

## Day-to-Day Workflow

```bash
# Morning: resume from hibernate
./start.sh && ./connect-ssm.sh

# Work in tmux — sessions survive hibernate/resume
tmux attach -t main   # or: tmux new -s main

# Run agents
opencode              # OpenCode TUI
# or: claude, gh copilot, etc.

# Push work upstream before hibernating
# (treat the instance as low-trust; always push to GitHub)

# Evening: hibernate
./hibernate.sh        # waits for instance-stopped before returning

# If you need SSH (e.g. VS Code Remote SSH)
./allow-ssh-my-ip.sh  # restricts port 22 to your current IP only
```

## Bootstrap Details

On first launch, UserData installs:

- System packages: `git`, `tmux`, `curl`, `wget`, `unzip`, `jq`, `ripgrep`, `fd-find`, `docker`
- GitHub CLI (`gh`)
- nvm (latest) + Node.js LTS — installed to `/data/nvm` so it survives reprovisioning
- `opencode-ai` (global npm)
- Auto-tmux attach on SSH login

CloudFormation uses `cfn-signal` to wait for bootstrap to complete before marking
the stack `CREATE_COMPLETE`. Outputs (instance ID, SSM connect command) are not
available until bootstrap has finished.

Bootstrap log: `/var/log/user-data.log` on the instance.

## Design Decisions

**Why EC2 over a VPS?**
- Native hibernate support
- IAM-native access control
- No public SSH required (SSM)
- Easy automation with EventBridge + Lambda (future)

**Why hibernate over stop?**
- No compute billing either way
- Hibernate preserves RAM and running tmux sessions
- Resume feels like laptop sleep/wake rather than a fresh boot

**Why SSM over SSH?**
- No inbound port exposure
- No static IP requirement
- Works behind any NAT
- Auditable via CloudTrail

**Why a separate data volume?**
- Root volume can be discarded when reprovisioning (OS update, instance type change)
- Data volume survives `terminate-instances` and stack deletion
- nvm, repos, and caches don't need to be reinstalled on every reprovision

## Cost Model

Assumptions: ~20 hours/week active, `t3a.xlarge`, `us-east-1`

- Compute: billed per-second only when running
- Storage: ~$0.08/GiB/month (gp3) — 150 GiB total ≈ $12/month continuously
- Estimated total: **$20–$40/month** at 20 hours/week active

## Operational Philosophy

Treat this instance as:
- **Disposable** — the root volume can be deleted and reprovisioned at any time
- **Low-trust** — do not store long-lived production secrets here
- **Not the only copy** — always push repos to GitHub; don't rely on EBS as a backup

## Not Implemented Yet

- Auto-hibernate Lambda (EventBridge + Lambda for idle detection)
- SSM Parameter Store heartbeat
- Telegram control plane
- Snapshot rotation for data volume
