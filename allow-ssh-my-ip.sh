#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-agent-workstation}"

# Get your current public IP
MYIP="$(curl -fsSL https://checkip.amazonaws.com)/32"

# Find the SG ID from the stack resources
SG_ID="$(aws-vault exec kuba-patrick --no-session --  aws cloudformation describe-stack-resources --stack-name "${STACK_NAME}" \
  --query "StackResources[?LogicalResourceId=='WorkstationSecurityGroup'].PhysicalResourceId" \
  --output text)"

echo "Security group: ${SG_ID}"
echo "Your current IP: ${MYIP}"

# Revoke ALL existing port-22 ingress rules (whatever CIDRs are currently there).
# This correctly handles prior runs that left specific IPs, not just 0.0.0.0/0.
EXISTING_CIDRS="$(aws-vault exec kuba-patrick --no-session --  aws ec2 describe-security-groups \
  --group-ids "${SG_ID}" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\` && ToPort==\`22\` && IpProtocol==\`tcp\`].IpRanges[].CidrIp" \
  --output text)"

if [[ -n "${EXISTING_CIDRS}" ]]; then
  for cidr in ${EXISTING_CIDRS}; do
    echo "Revoking existing SSH rule for ${cidr} ..."
    aws-vault exec kuba-patrick --no-session -- aws ec2 revoke-security-group-ingress \
      --group-id "${SG_ID}" \
      --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${cidr}}]" \
      2>/dev/null || echo "  (already gone, skipping)"
  done
fi

# Authorize only your current IP
echo "Authorizing SSH from ${MYIP} ..."
aws-vault exec kuba-patrick --no-session -- aws ec2 authorize-security-group-ingress \
  --group-id "${SG_ID}" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${MYIP},Description=my-current-ip}]"

echo "Done. SSH on port 22 is now allowed from ${MYIP} only."
