#!/bin/bash
# Pull pipeline results from the AWS instance and apply them locally.

set -e
cd "$(dirname "$0")/../.."
[ -f .aws-instance.meta ] || { echo "No .aws-instance.meta"; exit 1; }
source .aws-instance.meta

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP="scp -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Verify completion
if ! $SSH ec2-user@"$PUBLIC_DNS" 'test -f /home/ec2-user/annuity-puzzle/.pipeline-complete' 2>/dev/null; then
    echo "Pipeline not complete on remote. Last log lines:"
    $SSH ec2-user@"$PUBLIC_DNS" 'tail -20 /home/ec2-user/run_all.log'
    exit 1
fi

# Download results tarball
LOCAL_TARBALL="results-latest.tar.gz"
echo "Downloading $LOCAL_TARBALL..."
$SCP ec2-user@"$PUBLIC_DNS":/home/ec2-user/annuity-puzzle/results-latest.tar.gz "$LOCAL_TARBALL"

# Extract into project tree
echo "Extracting..."
mkdir -p tables/csv tables/tex figures/pdf figures/png paper logs
tar -xzf "$LOCAL_TARBALL"

echo
echo "=== Results applied ==="
ls -1 tables/csv/ | head -5
echo "..."

# Regenerate manuscript macros
echo
echo "Regenerating paper/numbers.tex..."
julia --project=. scripts/export_manuscript_numbers.jl

# Recompile manuscripts
echo
echo "Recompiling paper..."
cd paper && pdflatex -interaction=nonstopmode -halt-on-error main.tex >/dev/null && \
    pdflatex -interaction=nonstopmode -halt-on-error appendix.tex >/dev/null
cd ..

echo
echo "=== Pull complete ==="
ls -lh paper/main.pdf paper/appendix.pdf 2>/dev/null

# Auto-terminate the instance — leaving it running burns money and the user
# may not be available to confirm. Set NO_AUTO_TERMINATE=1 to skip if you
# want to debug on the instance.
if [ "${NO_AUTO_TERMINATE:-0}" != "1" ]; then
  echo
  echo "=== Auto-terminating instance ==="
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
      --query 'TerminatingInstances[0].CurrentState.Name' --output text
  mv .aws-instance.meta ".aws-instance.meta.terminated.$(date +%s)"
  echo "Instance terminated. Metadata archived."
else
  echo
  echo "NO_AUTO_TERMINATE=1 set — instance left running."
  echo "Manually terminate with: bash scripts/aws/terminate.sh --force"
fi
