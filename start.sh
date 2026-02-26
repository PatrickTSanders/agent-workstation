#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-agent-workstation-1}"

INSTANCE_ID="$(aws-vault exec kuba-patrick --no-session --  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)"

echo "Starting ${INSTANCE_ID} ..."
aws-vault exec kuba-patrick --no-session --  aws ec2 start-instances --instance-ids "${INSTANCE_ID}" >/dev/null
aws-vault exec kuba-patrick --no-session --  aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
echo "Running."