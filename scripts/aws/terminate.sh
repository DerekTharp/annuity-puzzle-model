#!/bin/bash
# Terminate the AWS instance and clean up the metadata file.
# Pass --force to skip the confirmation prompt.

set -e
cd "$(dirname "$0")/../.."
[ -f .aws-instance.meta ] || { echo "No .aws-instance.meta — nothing to terminate"; exit 0; }
source .aws-instance.meta

if [ "$1" != "--force" ]; then
  read -p "Terminate $INSTANCE_ID ($PUBLIC_DNS)? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; exit 0; }
fi

aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
    --query 'TerminatingInstances[0].CurrentState.Name' --output text

mv .aws-instance.meta ".aws-instance.meta.terminated.$(date +%s)"
echo "Instance termination requested. Metadata moved to .aws-instance.meta.terminated.*"
