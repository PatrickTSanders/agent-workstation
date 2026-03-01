#!/usr/bin/env bash
# Creates an encrypted copy of the latest Amazon Linux 2023 AMI and stores the
# ID in SSM Parameter Store at /agent-workstation/ami-id.
# Hibernation requires an encrypted AMI — the default public AMI is unencrypted.
# Run this once per region, or whenever you want to refresh to a newer AL2023 version.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
SSM_PARAM="/agent-workstation/ami-id"
NAME="al2023-encrypted-$(date +%Y%m%d)"

echo "Fetching latest AL2023 AMI in ${REGION}..."
SOURCE_AMI="$(aws-vault exec kuba-patrick --no-session -- aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --region "${REGION}" \
  --query Parameter.Value --output text)"
echo "Source AMI: ${SOURCE_AMI}"

echo "Copying with encryption enabled (name: ${NAME})..."
AMI_ID="$(aws-vault exec kuba-patrick --no-session -- aws ec2 copy-image \
  --source-image-id "${SOURCE_AMI}" \
  --source-region "${REGION}" \
  --region "${REGION}" \
  --name "${NAME}" \
  --encrypted \
  --query ImageId --output text)"
echo "Created AMI: ${AMI_ID} — waiting for it to become available..."

aws-vault exec kuba-patrick --no-session -- aws ec2 wait image-available \
  --region "${REGION}" \
  --image-ids "${AMI_ID}"

echo "Storing AMI ID in SSM at ${SSM_PARAM}..."
aws-vault exec kuba-patrick --no-session -- aws ssm put-parameter \
  --name "${SSM_PARAM}" \
  --value "${AMI_ID}" \
  --type String \
  --description "Encrypted AL2023 AMI for agent-workstation hibernation" \
  --overwrite

echo ""
echo "Done. Encrypted AMI ${AMI_ID} stored at ${SSM_PARAM}."
echo ""
echo "Deploy with:"
echo "  ./deploy.sh"
