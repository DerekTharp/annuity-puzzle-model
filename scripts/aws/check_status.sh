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
PROJ=/home/ec2-user/annuity-puzzle
if [ -f "$PROJ/.pipeline-complete" ]; then
    echo "STATUS: COMPLETE"
    ls -lh "$PROJ/results-latest.tar.gz" 2>/dev/null
elif [ -f "$PROJ/.pipeline-partial" ]; then
    JULIA_PIDS=$(pgrep -af julia | head -3)
    if [ -n "$JULIA_PIDS" ]; then
        echo "STATUS: PARTIAL_BUT_JULIA_RUNNING (resume in progress?)"
        echo "$JULIA_PIDS"
    else
        echo "STATUS: FAILED (.pipeline-partial flag set, no julia processes)"
        echo "Partial bundle (if any): $(ls -1 "$PROJ"/results_*.tar.gz 2>/dev/null | tail -1)"
        echo "To resume the failing stages, ssh in and run:"
        echo "  bash scripts/aws/resume_pipeline_remote.sh"
    fi
else
    JULIA_PIDS=$(pgrep -af julia | head -3)
    if [ -n "$JULIA_PIDS" ]; then
        echo "STATUS: RUNNING"
        echo "$JULIA_PIDS"
    else
        echo "STATUS: UNKNOWN (no flags, no julia processes — instance may be idle or pre-launch)"
    fi
fi
echo
echo "=== Latest log lines ==="
tail -25 "$PROJ/run_all.log" 2>/dev/null || tail -25 /home/ec2-user/run_all.log 2>/dev/null || echo "(no log yet)"
'
