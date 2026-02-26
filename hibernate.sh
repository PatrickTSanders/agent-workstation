#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-agent-workstation}"

INSTANCE_ID="$(aws-vault exec kuba-patrick --no-session --  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)"

echo "Hibernating ${INSTANCE_ID} ..."
aws-vault exec kuba-patrick --no-session -- aws ec2 stop-instances --instance-ids "${INSTANCE_ID}" --hibernate >/dev/null

echo "Waiting for instance to stop (hibernate writes RAM to EBS — may take a minute)..."
aws-vault exec kuba-patrick --no-session -- aws ec2 wait instance-stopped --instance-ids "${INSTANCE_ID}"

echo "Hibernated. EBS volumes are preserved. Resume with: ./start.sh ${STACK_NAME}"
