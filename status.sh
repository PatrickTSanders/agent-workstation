#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-agent-workstation}"

INSTANCE_ID="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)"

aws ec2 describe-instances --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].{State:State.Name,InstanceType:InstanceType,PublicDns:PublicDnsName}" \
  --output table