#!/bin/bash
# Cloud-init script for the AWS spot instance.
# Installs Julia and Python deps; the project tree is rsync'd in by the
# launcher after this script finishes.

set -e
exec > /var/log/cloud-init-annuity.log 2>&1
echo "=== Annuity Puzzle Cloud-Init: $(date) ==="

# AL2023 / RHEL family
dnf install -y tar gzip wget gcc make rsync git

# Install Julia 1.12.5 to match Manifest.toml lockfile (julia_version = "1.12.5").
# Set ANNUITY_JULIA_VERSION in the launch environment to override.
JULIA_VERSION="${ANNUITY_JULIA_VERSION:-1.12.5}"
JULIA_MINOR=$(echo "$JULIA_VERSION" | cut -d. -f1-2)
JULIA_DIR="/opt/julia-${JULIA_VERSION}"
JULIA_TARBALL="julia-${JULIA_VERSION}-linux-x86_64.tar.gz"

if [ ! -d "$JULIA_DIR" ]; then
    cd /tmp
    wget -q "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MINOR}/${JULIA_TARBALL}"
    tar -xzf "$JULIA_TARBALL"
    mv "julia-${JULIA_VERSION}" "$JULIA_DIR"
    ln -sf "${JULIA_DIR}/bin/julia" /usr/local/bin/julia
fi

julia --version

# Prepare scratch directory
mkdir -p /home/ec2-user/annuity-puzzle
chown ec2-user:ec2-user /home/ec2-user/annuity-puzzle

echo "=== Cloud-Init complete: $(date) ==="
touch /home/ec2-user/.cloud-init-ready
