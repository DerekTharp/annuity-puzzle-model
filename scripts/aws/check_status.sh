#!/bin/bash
# Check the AWS pipeline run's status. Reads .aws-instance.meta from project root.

set -e
cd "$(dirname "$0")/../.."
[ -f .aws-instance.meta ] || { echo "No .aws-instance.meta — instance not launched"; exit 1; }
source .aws-instance.meta

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
echo "=== AWS Pipeline Status ==="
echo "Instance: $INSTANCE_ID  ($PUBLIC_DNS)"
echo "Launched: $(date -r $LAUNCHED)"
echo "Elapsed:  $(( ($(date +%s) - LAUNCHED) / 60 )) minutes"
echo

# Instance state
STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --region "$REGION" --output text 2>/dev/null || echo "UNKNOWN")
echo "EC2 state: $STATE"

if [ "$STATE" != "running" ]; then
    echo "(Cannot SSH — instance not running)"
    exit 0
fi

# Pipeline status
echo
echo "=== Pipeline status ==="
$SSH ec2-user@"$PUBLIC_DNS" '
if [ -f /home/ec2-user/annuity-puzzle/.pipeline-complete ]; then
    echo "STATUS: COMPLETE"
    ls -lh /home/ec2-user/annuity-puzzle/results-latest.tar.gz 2>/dev/null
else
    echo "STATUS: RUNNING"
    pgrep -af julia | head -3 || echo "(no julia processes)"
fi
echo
echo "=== Latest log lines ==="
tail -25 /home/ec2-user/run_all.log 2>/dev/null || echo "(no log yet)"
'
