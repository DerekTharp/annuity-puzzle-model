#!/bin/bash
# Watchdog for the AWS pipeline run. Polls the instance every POLL seconds and
# EXITS with an event report when something needs operator attention:
#   EVENT=COMPLETE        .pipeline-complete flag set (pull results, terminate)
#   EVENT=PARTIAL_FAILED  .pipeline-partial flag set (a stage failed)
#   EVENT=STALL           run_all.log stopped growing for STALL seconds
#                         (the known julia -p hang signature)
#   EVENT=INSTANCE_*      instance left the running state (spot interruption)
#   EVENT=SSH_FAILED      cannot reach the box
#   EVENT=DIGEST          nothing wrong; periodic status report after DIGEST s
# Relaunch after each exit to keep watching. Reads .aws-instance.meta.
#
# Usage: bash scripts/aws/watch_pipeline.sh
#   POLL=300 DIGEST=2700 STALL=1500 bash scripts/aws/watch_pipeline.sh

set -uo pipefail
cd "$(dirname "$0")/../.."
[ -f .aws-instance.meta ] || { echo "EVENT=NO_INSTANCE_META"; exit 1; }
source .aws-instance.meta

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15"
POLL=${POLL:-300}
DIGEST=${DIGEST:-2700}
STALL=${STALL:-1500}

start=$(date +%s)
last_size=-1
last_change=$(date +%s)

# Salvage pull: copy whatever tables/logs exist on the box to local scratch so
# a spot reclamation loses at most one digest cycle of artifacts. Non-fatal.
pull_partial() {
    mkdir -p logs/aws-partial
    rsync -az -e "$SSH" \
        ec2-user@"$PUBLIC_DNS":/home/ec2-user/annuity-puzzle/tables/ \
        logs/aws-partial/tables/ 2>/dev/null || true
    rsync -az -e "$SSH" \
        ec2-user@"$PUBLIC_DNS":/home/ec2-user/run_all.log \
        logs/aws-partial/ 2>/dev/null || true
}

while true; do
    now=$(date +%s)

    STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --region "$REGION" --output text 2>/dev/null || echo "UNKNOWN")
    if [ "$STATE" != "running" ]; then
        echo "EVENT=INSTANCE_$STATE"
        echo "ELAPSED_MIN=$(( (now - LAUNCHED) / 60 ))"
        exit 0
    fi

    INFO=$($SSH ec2-user@"$PUBLIC_DNS" '
        PROJ=/home/ec2-user/annuity-puzzle
        [ -f "$PROJ/.pipeline-complete" ] && echo "FLAG=COMPLETE"
        [ -f "$PROJ/.pipeline-partial" ] && echo "FLAG=PARTIAL"
        LOG=/home/ec2-user/run_all.log
        echo "SIZE=$(stat -c %s "$LOG" 2>/dev/null || echo 0)"
        echo "STAGE=$(grep "STAGE:" "$LOG" 2>/dev/null | tail -1 | sed "s/^ *//")"
        echo "HEARTBEAT=$(grep "\[heartbeat\]" "$LOG" 2>/dev/null | tail -1 | sed "s/^ *//")"
        echo "TAIL_START"
        tail -5 "$LOG" 2>/dev/null
        echo "TAIL_END"
    ' 2>/dev/null)
    if [ -z "$INFO" ]; then
        echo "EVENT=SSH_FAILED"
        echo "ELAPSED_MIN=$(( (now - LAUNCHED) / 60 ))"
        exit 0
    fi

    if echo "$INFO" | grep -q "FLAG=COMPLETE"; then
        echo "EVENT=COMPLETE"
        echo "ELAPSED_MIN=$(( (now - LAUNCHED) / 60 ))"
        echo "$INFO"
        exit 0
    fi
    if echo "$INFO" | grep -q "FLAG=PARTIAL"; then
        pull_partial
        echo "EVENT=PARTIAL_FAILED"
        echo "ELAPSED_MIN=$(( (now - LAUNCHED) / 60 ))"
        echo "$INFO"
        exit 0
    fi

    size=$(echo "$INFO" | grep "^SIZE=" | head -1 | cut -d= -f2)
    if [ -n "$size" ] && [ "$size" != "$last_size" ]; then
        last_size=$size
        last_change=$now
    fi
    if [ $((now - last_change)) -gt "$STALL" ]; then
        pull_partial
        echo "EVENT=STALL"
        echo "STALL_MIN=$(( (now - last_change) / 60 ))"
        echo "ELAPSED_MIN=$(( (now - LAUNCHED) / 60 ))"
        echo "$INFO"
        exit 0
    fi

    if [ $((now - start)) -ge "$DIGEST" ]; then
        pull_partial
        echo "EVENT=DIGEST"
        echo "ELAPSED_MIN=$(( (now - LAUNCHED) / 60 ))"
        echo "$INFO"
        exit 0
    fi

    sleep "$POLL"
done
