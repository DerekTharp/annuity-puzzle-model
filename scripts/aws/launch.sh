#!/bin/bash
# Launch a c7a.48xlarge spot instance, install Julia, rsync the project,
# and kick off run_all.jl. Detaches from the run; SSH in to monitor.
#
# Prereqs:
#   - aws CLI configured (us-east-1)
#   - SSH key at ~/.ssh/annuity-key.pem
#   - Security group annuity-ssh that allows SSH from your IP
#   - Run from the project root: bash scripts/aws/launch.sh
#
# Usage:
#   bash scripts/aws/launch.sh                   # spot c7a.48xlarge default
#   INSTANCE_TYPE=c7a.16xlarge bash launch.sh    # smaller (cheaper, slower)
#   ON_DEMAND=1 bash launch.sh                   # on-demand instead of spot

set -euo pipefail

cd "$(dirname "$0")/../.."
PROJECT_ROOT="$PWD"

# Configuration
REGION=${REGION:-us-east-1}
INSTANCE_TYPE=${INSTANCE_TYPE:-c7a.48xlarge}
KEY_NAME=${KEY_NAME:-annuity-key}
KEY_FILE=${KEY_FILE:-$HOME/.ssh/annuity-key.pem}
SG_NAME=${SG_NAME:-annuity-ssh}
SPOT=${SPOT:-1}
NAME_TAG="annuity-puzzle-10ch-$(date +%Y%m%d-%H%M)"

echo "=== AWS Annuity-Puzzle Pipeline Launcher ==="
echo "Region:        $REGION"
echo "Instance type: $INSTANCE_TYPE"
echo "Key:           $KEY_NAME ($KEY_FILE)"
echo "Security grp:  $SG_NAME"
echo "Spot:          $SPOT"
echo "Tag:           $NAME_TAG"
echo

# Verify prereqs
[ -f "$KEY_FILE" ] || { echo "ERROR: Key file not found: $KEY_FILE"; exit 1; }
chmod 400 "$KEY_FILE"
aws --version >/dev/null || { echo "ERROR: aws CLI not found"; exit 1; }

# Resolve security group
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --region "$REGION" --output text)
[ -z "$SG_ID" ] || [ "$SG_ID" = "None" ] && { echo "ERROR: SG $SG_NAME not found"; exit 1; }
echo "Security group: $SG_ID"

# Latest Amazon Linux 2023 AMI for x86_64
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters \
        "Name=name,Values=al2023-ami-2023*-x86_64" \
        "Name=state,Values=available" \
        "Name=architecture,Values=x86_64" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --region "$REGION" --output text)
[ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ] && { echo "ERROR: AMI lookup failed"; exit 1; }
echo "AMI:           $AMI_ID"

# Build user-data
USERDATA_FILE=$(mktemp)
cat scripts/aws/cloud_init.sh > "$USERDATA_FILE"

# Compose run-instances args
LAUNCH_ARGS=(
    --image-id "$AMI_ID"
    --instance-type "$INSTANCE_TYPE"
    --key-name "$KEY_NAME"
    --security-group-ids "$SG_ID"
    --user-data "file://$USERDATA_FILE"
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG}]"
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=80,VolumeType=gp3,DeleteOnTermination=true}'
    --region "$REGION"
)

if [ "$SPOT" = "1" ]; then
    LAUNCH_ARGS+=(--instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}')
fi

echo
echo "Launching instance..."
INSTANCE_ID=$(aws ec2 run-instances "${LAUNCH_ARGS[@]}" \
    --query 'Instances[0].InstanceId' --output text)
echo "Instance ID:   $INSTANCE_ID"

rm "$USERDATA_FILE"

# Wait for running state
echo "Waiting for instance to enter running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --region "$REGION" --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --region "$REGION" --output text)
echo "Public DNS:    $PUBLIC_DNS"
echo "Public IP:     $PUBLIC_IP"

# Save metadata for later commands
META_FILE="$PROJECT_ROOT/.aws-instance.meta"
cat > "$META_FILE" <<EOF
INSTANCE_ID=$INSTANCE_ID
PUBLIC_DNS=$PUBLIC_DNS
PUBLIC_IP=$PUBLIC_IP
REGION=$REGION
KEY_FILE=$KEY_FILE
NAME_TAG=$NAME_TAG
LAUNCHED=$(date +%s)
EOF
echo "Saved metadata: $META_FILE"

# Wait for cloud-init to finish (Julia install)
echo
echo "Waiting for cloud-init to install Julia (this takes ~3-5 minutes)..."
SSH_CMD="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
for attempt in {1..30}; do
    if $SSH_CMD ec2-user@"$PUBLIC_DNS" 'test -f /home/ec2-user/.cloud-init-ready' 2>/dev/null; then
        echo "Cloud-init ready (attempt $attempt)."
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "ERROR: cloud-init did not complete within 15 minutes"
        echo "Inspect: ssh -i $KEY_FILE ec2-user@$PUBLIC_DNS sudo cat /var/log/cloud-init-annuity.log"
        exit 1
    fi
    sleep 30
    echo "  waiting... ($((attempt * 30))s elapsed)"
done

# Verify Julia
$SSH_CMD ec2-user@"$PUBLIC_DNS" 'julia --version'

# rsync project to instance (excluding heavy outputs and git)
echo
echo "Syncing project to instance..."
RSYNC_OPTS=(-avz --delete --compress-level=9
    --exclude '.git/'
    --exclude 'logs/'
    --exclude 'results-latest.tar.gz'
    --exclude 'results_*.tar.gz'
    --exclude 'paper/*.pdf'
    --exclude 'paper/*.aux'
    --exclude 'paper/*.fdb_latexmk'
    --exclude 'paper/*.fls'
    --exclude 'paper/*.log'
    --exclude 'paper/*.synctex.gz'
    --exclude 'figures/pdf/'
    --exclude 'figures/png/'
    --exclude '.aws-instance.meta'
    -e "ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
)
rsync "${RSYNC_OPTS[@]}" "$PROJECT_ROOT/" \
    ec2-user@"$PUBLIC_DNS":/home/ec2-user/annuity-puzzle/

# Make remote scripts executable
$SSH_CMD ec2-user@"$PUBLIC_DNS" 'chmod +x /home/ec2-user/annuity-puzzle/scripts/aws/run_pipeline_remote.sh'

# Kick off the pipeline detached
echo
echo "Starting pipeline (detached, will run for ~2-3 hours)..."
$SSH_CMD ec2-user@"$PUBLIC_DNS" 'cd /home/ec2-user/annuity-puzzle && nohup bash scripts/aws/run_pipeline_remote.sh > /home/ec2-user/run_all.log 2>&1 < /dev/null &'
sleep 3

# Confirm it's running
$SSH_CMD ec2-user@"$PUBLIC_DNS" 'pgrep -af "run_pipeline_remote\|julia" | head -5'

cat <<EOF

==============================================================
PIPELINE LAUNCHED
==============================================================
Instance:    $INSTANCE_ID  ($INSTANCE_TYPE)
Public DNS:  $PUBLIC_DNS
Started:     $(date)
Expected runtime: ~2-3 hours (192 vCPU)

Monitor progress:
  ssh -i $KEY_FILE ec2-user@$PUBLIC_DNS 'tail -f /home/ec2-user/run_all.log'

Check completion:
  bash scripts/aws/check_status.sh

Pull results when done (this also auto-terminates the instance):
  bash scripts/aws/pull_results.sh

Manual termination (if pull was already done elsewhere):
  bash scripts/aws/terminate.sh --force

Metadata saved to: $META_FILE
==============================================================
EOF
