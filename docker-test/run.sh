#!/bin/bash
# ==============================================================================
#   CachyOmarchy - Docker Testing Container Launcher
# ==============================================================================
# Usage: Run this script to spin up a fully-fledged CachyOS CLI environment
#        in a sandbox Docker container to safely test the installation pipeline.
#
# Optional flags:
#   --dry-run   Launch the installer immediately in dry-run mode (no changes)
# ==============================================================================

# Validate that Docker daemon is running before attempting anything
if ! docker info &>/dev/null; then
    echo "[ERROR] Docker daemon is not running."
    echo "        Start it with: sudo systemctl start docker"
    exit 1
fi

# Get absolute path of this workspace directory
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Enable BuildKit for cache mount support (speeds up iterative builds significantly)
export DOCKER_BUILDKIT=1

echo "[*] Building Sandbox CachyOS Docker testing image (cachyomarchy-test)..."
docker build -t cachyomarchy-test -f "${WORKSPACE_DIR}/docker-test/Dockerfile" "${WORKSPACE_DIR}/docker-test"

echo "[*] Launching CachyOS Sandbox container..."
echo "[!] You will enter an interactive shell as 'esfingex' (EUID: 1000) inside the repository."
echo "[!] Run this to test the installation: ./bin/install-cachyomarchy.sh"
echo "[!] Run this for a quick dry-run (no changes): ./bin/install-cachyomarchy.sh --dry-run"
echo ""

# --privileged:              Grants full hardware access (lspci, chwd, PCI enumeration, PTY allocation)
# --security-opt seccomp=...: Allows sysctl calls inside the container (needed by increase-file-watchers.sh)
# NOTE: Do NOT bind-mount /dev as read-only — sudo requires write access to /dev/pts for PTY allocation.
#       --privileged already provides full device access including PCI hardware detection.
docker run -it --rm \
  --name cachyomarchy_sandbox \
  --privileged \
  --security-opt seccomp=unconfined \
  -v "${WORKSPACE_DIR}":/home/esfingex/omarchy-on-cachyos \
  cachyomarchy-test \
  bash
