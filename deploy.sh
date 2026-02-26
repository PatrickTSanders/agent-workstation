#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-agent-workstation}"
TEMPLATE_FILE="${2:-agent-workstation.yaml}"

# Optional params you can override via env vars
INSTANCE_TYPE="${INSTANCE_TYPE:-t3a.xlarge}"
ROOT_VOL="${ROOT_VOL:-30}"         # Root OS volume (small — toolchain installs fresh)
DATA_VOL="${DATA_VOL:-120}"        # Separate persistent data volume
KEY_NAME="${KEY_NAME:-}"           # e.g. KEY_NAME=my-keypair (leave empty for SSM-only)
ENABLE_SSH_INGRESS="${ENABLE_SSH_INGRESS:-false}"  # true/false

PARAMS=(
  "ParameterKey=ProjectName,ParameterValue=${STACK_NAME}"
  "ParameterKey=InstanceType,ParameterValue=${INSTANCE_TYPE}"
  "ParameterKey=RootVolumeGiB,ParameterValue=${ROOT_VOL}"
  "ParameterKey=DataVolumeGiB,ParameterValue=${DATA_VOL}"
  "ParameterKey=EnableSshIngressFromMyIp,ParameterValue=${ENABLE_SSH_INGRESS}"
)

if [[ -n "${KEY_NAME}" ]]; then
  PARAMS+=("ParameterKey=KeyName,ParameterValue=${KEY_NAME}")
fi

aws-vault exec kuba-patrick --no-session -- aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE_FILE}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "${PARAMS[@]}"

echo "Done."
aws-vault exec kuba-patrick --no-session -- aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs" --output table
