#!/bin/bash
# Pull pipeline results from the AWS instance and apply them locally.

set -euo pipefail
cd "$(dirname "$0")/../.."
[ -f .aws-instance.meta ] || { echo "No .aws-instance.meta"; exit 1; }
source .aws-instance.meta

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP="scp -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# AWS termination is paid-resource hygiene: once we have the tarball we
# should terminate the instance regardless of whether downstream local
# steps (macro export, validation, LaTeX recompile) succeed. Install an
# EXIT trap that fires after the tarball is downloaded; if the trap
# fires before the tarball lands (e.g., SSH or remote-completion check
# failed), it exits without touching AWS so the operator can debug.
TARBALL_PULLED=0
PULL_OK=0
terminate_on_exit() {
    if [ "$TARBALL_PULLED" != "1" ]; then
        echo "Tarball not pulled (likely a remote-completion or SSH failure)."
        echo "Instance left running for debugging. To force-terminate:"
        echo "  bash scripts/aws/terminate.sh --force"
        return
    fi
    if [ "${NO_AUTO_TERMINATE:-0}" = "1" ]; then
        echo
        echo "NO_AUTO_TERMINATE=1 set — instance left running."
        echo "Manually terminate with: bash scripts/aws/terminate.sh --force"
        return
    fi
    echo
    if [ "$PULL_OK" = "1" ]; then
        echo "=== Auto-terminating instance (pull + local steps OK) ==="
    else
        echo "=== Auto-terminating instance (tarball secured; local steps failed) ==="
    fi
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
        --query 'TerminatingInstances[0].CurrentState.Name' --output text || \
        echo "WARNING: terminate-instances call failed; verify manually."
    mv .aws-instance.meta ".aws-instance.meta.terminated.$(date +%s)" 2>/dev/null || true
    echo "Instance termination requested. Metadata archived."
}
trap terminate_on_exit EXIT

# Verify completion
if ! $SSH ec2-user@"$PUBLIC_DNS" 'test -f /home/ec2-user/annuity-puzzle/.pipeline-complete' 2>/dev/null; then
    echo "Pipeline not complete on remote. Last log lines:"
    $SSH ec2-user@"$PUBLIC_DNS" 'tail -20 /home/ec2-user/run_all.log' || true
    exit 1
fi

# Download results tarball
LOCAL_TARBALL="results-latest.tar.gz"
echo "Downloading $LOCAL_TARBALL..."
$SCP ec2-user@"$PUBLIC_DNS":/home/ec2-user/annuity-puzzle/results-latest.tar.gz "$LOCAL_TARBALL"
TARBALL_PULLED=1

# Extract into project tree
echo "Extracting..."
mkdir -p tables/csv tables/tex figures/pdf figures/png paper logs
tar -xzf "$LOCAL_TARBALL"

echo
echo "=== Results applied ==="
ls -1 tables/csv/ | head -5
echo "..."

# Regenerate manuscript macros and validate them against the pulled CSVs. The
# remote pipeline already ran Stage 16, but this script mutates numbers.tex
# locally after extraction, so repeat the integrity check before compiling.
echo
echo "Regenerating paper/numbers.tex..."
julia --project=. scripts/export_manuscript_numbers.jl

echo
echo "Validating paper/numbers.tex against pulled CSVs..."
julia --project=. test/test_manuscript_numbers.jl

# Recompile manuscripts
echo
echo "Recompiling paper..."
cd paper && pdflatex -interaction=nonstopmode -halt-on-error main.tex >/dev/null && \
    pdflatex -interaction=nonstopmode -halt-on-error appendix.tex >/dev/null && \
    pdflatex -interaction=nonstopmode -halt-on-error cover_letter.tex >/dev/null
cd ..

echo
echo "=== Pull complete ==="
ls -lh paper/main.pdf paper/appendix.pdf 2>/dev/null

# Mark all local steps as successful so the EXIT trap can report a clean
# auto-terminate. Termination itself is handled by the trap so the
# instance is shut down even if any of the local steps above fail.
PULL_OK=1
