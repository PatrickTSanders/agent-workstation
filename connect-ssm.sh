#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-agent-workstation}"

INSTANCE_ID="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)"

echo "Connecting via SSM to ${INSTANCE_ID} ..."
aws-vault exec kuba-patrick --no-session -- aws ssm start-session --target "${INSTANCE_ID}"