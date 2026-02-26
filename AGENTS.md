# remote-agents

Infrastructure-as-code for a remote AI agent workstation on AWS EC2.

## Project Purpose

This project provisions a stateful EC2 workstation designed to run AI coding agents
(OpenCode, Claude Code, etc.) in a controlled environment, away from a local laptop.
The primary goals are blast-radius containment, persistent state, and cost efficiency
via hibernation.

## Repository Structure

All files are in the project root (flat layout — no subdirectories).

- `agent-workstation.yaml` — CloudFormation template (the entire infrastructure)
- `deploy.sh` — Deploy or update the CloudFormation stack
- `connect-ssm.sh` — Connect to the instance via AWS SSM Session Manager
- `start.sh` — Start (resume from hibernate) the instance
- `hibernate.sh` — Hibernate the instance (preserves RAM + EBS)
- `status.sh` — Show current instance state
- `allow-ssh-my-ip.sh` — Update the Security Group to allow SSH from your current IP

## Infrastructure Design

### Compute
- Single EC2 instance (default: `t3a.xlarge`, 4 vCPU / 16 GB RAM)
- Amazon Linux 2023
- Hibernation enabled — stop writes RAM to EBS; resume restores full state
- IMDSv2 enforced

### Storage — Two Volumes

| Volume | Size | DeleteOnTermination | Purpose |
|--------|------|---------------------|---------|
| Root (`/dev/xvda`) | 30 GiB gp3 | true | OS + system packages; disposable |
| Data (`/dev/sdf`) | 120 GiB gp3 | **false** (Retain) | Repos, caches, nvm, toolchains |

The data volume is a separate `AWS::EC2::Volume` resource with `DeletionPolicy: Retain`.
It persists through instance termination and stack deletion. Mount point: `/data`.
Symlinks: `~/repos -> /data/repos`, `~/cache -> /data/cache`.

### Access
- Primary: AWS SSM Session Manager (no inbound ports required)
- Optional: SSH (port 22), restricted to your current public IP via `allow-ssh-my-ip.sh`

### IAM
- Instance role: `AmazonSSMManagedInstanceCore` only (least privilege)

### Bootstrap (UserData)
On first boot the instance installs:
- System: `git`, `tmux`, `curl`, `wget`, `unzip`, `jq`, `ripgrep`, `fd-find`, `docker`, `gh`
- Node via nvm (LTS) — installed to `/data/nvm` for persistence
- `opencode-ai` (global npm install)
- Auto-tmux attach on SSH login (`/etc/profile.d/tmux-attach.sh`)

CloudFormation waits for a `cfn-signal` from the instance before marking the stack
`CREATE_COMPLETE`, so outputs (instance ID, SSM command) are only available once
bootstrap has fully completed.

## Conventions

### Shell scripts
- All scripts accept `STACK_NAME` as `$1` (default: `agent-workstation`)
- Use `set -euo pipefail`
- Derive instance ID from CloudFormation stack outputs (not hardcoded)
- Use AWS CLI v2 syntax

### CloudFormation
- Parameters use `Default` values that work out of the box for a single-instance setup
- `VpcId` is intentionally omitted — assumes default VPC
- SSH ingress placeholder IP is `127.0.0.1/32`; always update with `allow-ssh-my-ip.sh`
- Data volume uses `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain`

## Deployment

```bash
chmod +x *.sh
./deploy.sh agent-workstation agent-workstation.yaml
```

Optional environment variable overrides for `deploy.sh`:
- `INSTANCE_TYPE` (default: `t3a.xlarge`)
- `ROOT_VOL` (default: `30`)
- `DATA_VOL` (default: `120`)
- `KEY_NAME` (default: empty — SSM only)
- `ENABLE_SSH_INGRESS` (default: `false`)

## Day-to-Day Workflow

```bash
# Morning: resume from hibernate
./start.sh && ./connect-ssm.sh

# Evening: hibernate
./hibernate.sh

# Check state
./status.sh

# If using SSH instead of SSM
./allow-ssh-my-ip.sh  # update SG to current IP first
```

## Not Implemented Yet

- Auto-hibernate Lambda (EventBridge + Lambda for idle detection)
- SSM Parameter Store heartbeat
- Telegram control plane
