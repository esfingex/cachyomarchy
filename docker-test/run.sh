#!/bin/bash
# ==============================================================================
#   CachyOmarchy - Docker Testing Container Launcher
# ==============================================================================
# Usage: Run this script to spin up a fully-fledged CachyOS CLI environment
#        in a sandbox Docker container to safely test the installation pipeline.
# ==============================================================================

# Get absolute path of this workspace directory
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Building Sandbox CachyOS Docker testing image (cachyomarchy-test)..."
docker build -t cachyomarchy-test -f "${WORKSPACE_DIR}/docker-test/Dockerfile" "${WORKSPACE_DIR}/docker-test"

echo "[*] Launching CachyOS Sandbox container..."
echo "[!] You will enter an interactive shell as 'esfingex' (EUID: 1000) inside the repository."
echo "[!] Run this to test the installation: ./bin/install-cachyomarchy.sh"
echo ""

docker run -it --rm \
  --name cachyomarchy_sandbox \
  -v "${WORKSPACE_DIR}":/home/esfingex/omarchy-on-cachyos \
  cachyomarchy-test \
  bash
