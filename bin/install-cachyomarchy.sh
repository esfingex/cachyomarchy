#!/bin/bash
# ==============================================================================
#      ____                __           ____                                 
#     / ___|__ _  ___  ___| |__  _   _ / ___| _ __ ___   __ _ _ __ ___| |__  
#    | |   / _` |/ __|/ __| '_ \| | | | |  _ | '_ ` _ \ / _` | '__/ __| '_ \ 
#    | |__| (_| | (__| (__| | | | |_| | |_| || | | | | | (_| | | | (__| | | |
#     \____\__,_|\___|\___|_| |_|\__, |\____||_| |_| |_|\__,_|_|  \___|_| |_|
#                                |___/                                       
#   CachyOmarchy - Modular CachyOS Hyprland Installer Orchestrator
# ==============================================================================
# Target OS: CachyOS (Arch Linux based)
# Purpose  : Installs David Heinemeier Hansson's (DHH) Omarchy environment
#            custom-patched for optimal performance, stability, and hardware
#            integration on CachyOS systems.
# ==============================================================================

# ==============================================================================
# SECTION 1: SELF-TEEING RESILIENT LOGGING PIPELINE
# ==============================================================================
# Define the persistent log file path
LOG_FILE="/tmp/cachyomarchy-install.log"

# Ensure USER environment variable is always defined and exported (fixes Neovim configuration and sudoers script errors inside Docker/headless environments)
export USER="${USER:-$(whoami)}"

# If not already running inside the tee pipeline, restart the script and duplicate
# all outputs (stdout & stderr) to both the terminal and the log file.
if [ "${CACHYOMARCHY_LOGGED}" != "true" ]; then
    export CACHYOMARCHY_LOGGED="true"
    
    # Initialize a clean log file for this run
    rm -f "$LOG_FILE"
    
    # Set a trap on the outer execution to display the log summary upon exit/termination
    cleanup_outer() {
        local exit_code=$?
        echo ""
        if [ $exit_code -eq 0 ]; then
            echo -e "\e[1;32m[+] CachyOmarchy installation completed successfully!\e[0m"
        else
            echo -e "\e[1;31m[!] CachyOmarchy installation encountered an error (Exit Code: $exit_code).\e[0m"
        fi

        # Detect the host workspace to persist logs across container restarts/deletion
        local workspace=""
        for dir in "/home/esfingex/omarchy-on-cachyos" "/home/esfingex/Github/omarchy-on-cachyos" "$PWD"; do
            if [ -w "$dir" ] && [ -d "$dir/.git" ]; then
                workspace="$dir"
                break
            fi
        done

        if [ -n "$workspace" ]; then
            cp "$LOG_FILE" "$workspace/cachyomarchy-runner.log" 2>/dev/null || true
            if [ -f "/var/log/omarchy-install.log" ]; then
                cp "/var/log/omarchy-install.log" "$workspace/omarchy-install.log" 2>/dev/null || true
            fi
            echo -e "\e[1;34m[*] To survive Docker container deletions, all logs have been persisted to your host workspace:\e[0m"
            echo -e "\e[1;36m    --> $workspace/cachyomarchy-runner.log\e[0m"
            [ -f "/var/log/omarchy-install.log" ] && echo -e "\e[1;36m    --> $workspace/omarchy-install.log\e[0m"
            echo ""
        else
            echo -e "\e[1;34m[*] A complete log of this session has been saved to:\e[0m"
            echo -e "\e[1;36m    --> $LOG_FILE\e[0m"
            echo -e "\e[1;33m[!] You can share this log file directly with an AI to analyze or debug.\e[0m"
            echo ""
        fi
    }
    trap cleanup_outer EXIT
    
    # Run the script and duplicate output
    $0 "$@" 2>&1 | tee "$LOG_FILE"
    
    # Propagate the inner exit status to the outer shell environment
    exit ${PIPESTATUS[0]}
fi

# Exit immediately on error, treat unset variables as errors, and catch piped failures
set -euo pipefail

# ==============================================================================
# DRY-RUN MODE: pass --dry-run to preview all actions without executing anything
# ==============================================================================
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Wrapper to skip destructive commands in dry-run mode
run_or_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\e[2;37m[DRY-RUN] Would run: $*\e[0m"
    else
        "$@"
    fi
}

# ==============================================================================
# SECTION 2: LOGGING SYSTEM (ANSI COLORS + TIMESTAMPS)
# ==============================================================================

_ts() { date '+%H:%M:%S'; }

log_info() {
    echo -e "\e[2;37m[$(_ts)]\e[0m \e[1;34m[*] $1\e[0m"
}

log_success() {
    echo -e "\e[2;37m[$(_ts)]\e[0m \e[1;32m[+] $1\e[0m"
}

log_warn() {
    echo -e "\e[2;37m[$(_ts)]\e[0m \e[1;33m[!] $1\e[0m"
}

log_error() {
    echo -e "\e[2;37m[$(_ts)]\e[0m \e[1;31m[ERROR] $1\e[0m" >&2
}

# ==============================================================================
# SECTION 3: MODULAR DEPLOYMENT FUNCTIONS
# ==============================================================================

# Verifies that running environment preconditions are met
check_preflight() {
    log_info "Running preflight system validation..."
    log_info "All execution details are being logged to: $LOG_FILE"

    # Dry-run banner
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY-RUN MODE ENABLED — no changes will be made to your system."
    fi

    # Guard 1: Root execution block (User space configuration requirements)
    if [ "$EUID" -eq 0 ]; then
        log_error "Please do not run this script as root/sudo directly."
        log_error "CachyOmarchy must configure files in user-space. Sudo is requested only when needed."
        exit 1
    fi

    # Guard 2: OS validation — must be Arch Linux or a derivative (CachyOS)
    if ! grep -q 'ID_LIKE=arch\|ID=cachyos\|ID=arch' /etc/os-release 2>/dev/null; then
        if ! grep -q 'Arch Linux\|CachyOS' /etc/os-release 2>/dev/null; then
            log_error "This script requires CachyOS or an Arch Linux-based distribution."
            log_error "Detected OS: $(grep '^PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"')"
            exit 1
        fi
    fi
    log_success "OS validation passed: $(grep '^PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"')"

    # Guard 3: Network connectivity check — test DNS + HTTPS reach before any downloads
    log_info "Verifying network connectivity..."
    if ! curl -fsS --max-time 5 https://github.com -o /dev/null 2>/dev/null; then
        log_error "Cannot reach GitHub. Please check your network connection and try again."
        exit 1
    fi
    log_success "Network connectivity confirmed."

    # Guard 4: Git dependency check
    if ! command -v git &>/dev/null; then
        log_error "git is not installed. Please install git before proceeding."
        exit 1
    fi

    # Guard 5: Disk space check — warn if less than 5 GB free in home partition
    local free_gb
    free_gb=$(df --output=avail -BG "$HOME" | tail -1 | tr -d 'G ')
    if (( free_gb < 5 )); then
        log_warn "Low disk space detected: only ${free_gb}GB free in $HOME. Omarchy may require 5GB+."
    else
        log_success "Disk space check passed: ${free_gb}GB free."
    fi

    # Pre-install gum early: omarchy's error handler depends on it for interactive UI.
    # If gum isn't present when a crash happens, the error handler itself crashes (double failure).
    if ! command -v gum &>/dev/null; then
        log_info "Pre-installing 'gum' (required by Omarchy error handler UI)..."
        sudo pacman -S --needed --noconfirm gum || log_warn "Could not pre-install gum; continuing anyway."
    fi

    # Sudo keepalive: ask for password once upfront, then refresh every 60s in background.
    # This prevents repeated password prompts throughout the long installation process.
    log_info "Requesting sudo privileges (you will only be asked once)..."
    sudo -v
    # Spawn a background loop that keeps the sudo session alive until the script exits
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit 0; done ) &
    SUDO_KEEPALIVE_PID=$!
    # Ensure the keepalive process is killed cleanly when the main script exits
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
    # Set up systemctl sandbox wrapper inside Docker/virtual environments to avoid systemd errors
    if ! [ -d /run/systemd/system ]; then
        log_info "Creating systemctl sandbox wrapper for non-systemd environment..."
        sudo tee /usr/local/bin/systemctl > /dev/null << 'SYSOP'
#!/bin/bash
if [ -d /run/systemd/system ]; then
  exec /usr/bin/systemctl "$@"
else
  action=""
  for arg in "$@"; do
    if [[ ! "$arg" =~ ^- ]]; then
      action="$arg"
      break
    fi
  done
  case "$action" in
    enable|disable|mask|unmask)
      /usr/bin/systemctl "$@" || true
      ;;
    *)
      echo "[CachyOmarchy Sandbox] systemctl '$action' bypassed safely inside container."
      ;;
  esac
fi
SYSOP
        sudo chmod +x /usr/local/bin/systemctl
        log_success "systemctl sandbox wrapper successfully registered."
    fi

    log_success "Preflight validation completed successfully."
}

# Pulls or clones the basecamp/omarchy repository
clone_upstream() {
    log_info "Synchronizing upstream Omarchy repository..."

    # Resolve the absolute path to the omarchy submodule directory relative to this script.
    # Using SCRIPT_DIR-based path prevents breakage when called from arbitrary working directories.
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local OMARCHY_SRC="${SCRIPT_DIR}/../omarchy"

    if [ -d "${OMARCHY_SRC}/.git" ]; then
        log_info "Upstream Omarchy codebase found. Resetting and pulling latest revisions..."
        # Hard-reset any local modifications from previous patch runs before pulling.
        # This is safe: apply_cachy_patches() always re-applies all patches fresh on each run.
        git -C "${OMARCHY_SRC}" reset --hard HEAD
        git -C "${OMARCHY_SRC}" clean -fd
        git -C "${OMARCHY_SRC}" pull
    else
        log_info "Cloning a clean basecamp/omarchy repository..."
        if ! git clone https://github.com/basecamp/omarchy "${OMARCHY_SRC}"; then
            log_error "Failed to clone upstream repository."
            exit 1
        fi
    fi
    log_success "Upstream codebase successfully synchronized."
}

# Configures the AUR helper (yay) needed for compiling core elements
setup_aur_helper() {
    if ! command -v yay &>/dev/null; then
        log_info "AUR helper 'yay' not detected. Initiating compilation..."

        # Consolidated Build Package Dependency Installation:
        # - git: Control version tool to clone the build files.
        # - base-devel: Complete compilation suite (make, gcc, patch, etc.) needed to compile AUR binaries.
        log_info "Installing standard compile-time dependencies..."
        sudo pacman -S --needed --noconfirm git base-devel

        log_info "Cloning and building yay (from AUR)..."
        # Clean any leftover /tmp/yay from previous failed runs
        rm -rf /tmp/yay
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        # Use a subshell to avoid changing the working directory of the parent script
        (cd /tmp/yay && makepkg -si --noconfirm)
        
        # Clean up temporary compilation directory
        rm -rf /tmp/yay

        if ! command -v yay &>/dev/null; then
            log_error "Failed to verify AUR helper installation."
            exit 1
        fi
        log_success "AUR helper 'yay' successfully installed."
    else
        log_info "AUR helper 'yay' is already present. Skipping installation."
    fi
}

# Handles GPG key import with robust regional fallbacks (resolving South America/Chile timeouts)
setup_keyring() {
    log_info "Configuring Omarchy GPG keyring signatures..."
    
    # Import the key (F0134EE680CAC571) with keyserver fallbacks
    if ! sudo pacman-key --recv-keys F0134EE680CAC571 --keyserver keys.openpgp.org; then
        log_warn "Primary keyserver timed out. Attempting Canonical high-availability fallback..."
        if ! sudo pacman-key --recv-keys F0134EE680CAC571 --keyserver keyserver.ubuntu.com; then
            log_warn "Failed to download GPG key. Settle for SigLevel fallback in pacman.conf."
        fi
    fi

    # Locally trust and sign the key inside the Arch key ring
    sudo pacman-key --lsign-key F0134EE680CAC571 || true
    log_success "Cryptographic keyring configured."
}

# Registers the binary package repository with security-checking fallbacks
setup_pacman_repository() {
    log_info "Registering CachyOmarchy package repositories..."

    # Configure the pacman repository.
    # - SigLevel = Optional TrustAll: Bypasses strict local key checking if keyserver timeouts occur.
    # - Server = ... \$arch: Dynamic system architecture resolution preserves native package queries.
    if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
        log_info "Adding [omarchy] block to /etc/pacman.conf..."
        echo -e "\n[omarchy]\nSigLevel = Optional TrustAll\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
    else
        log_info "Omarchy repository is already registered in /etc/pacman.conf."
    fi

    # Synchronize all package databases
    # Refresh mirrorlist first to avoid slow/dead mirrors causing timeout errors.
    # Uses rate-mirrors (CachyOS native tool) with fallback to reflector (standard Arch).
    log_info "Refreshing pacman mirrorlist for fastest available servers..."
    if command -v rate-mirrors &>/dev/null; then
        log_info "Using rate-mirrors (CachyOS native)..."
        sudo rate-mirrors --allow-root --protocol https \
            --save /etc/pacman.d/mirrorlist arch 2>/dev/null \
            || log_warn "rate-mirrors failed, proceeding with existing mirrorlist."
    elif command -v reflector &>/dev/null; then
        log_info "Using reflector to select fastest mirrors..."
        sudo reflector \
            --country 'Chile,Brazil,Argentina,United States,Germany' \
            --age 12 --protocol https --sort rate \
            --save /etc/pacman.d/mirrorlist 2>/dev/null \
            || log_warn "reflector failed, proceeding with existing mirrorlist."
    else
        log_warn "No mirror optimization tool found (rate-mirrors/reflector). Skipping mirror refresh."
    fi

    log_info "Updating local package databases..."
    sudo pacman -Syu --noconfirm

    # Clear conflicting SDDM display manager configs to permit UWSM session handovers
    if [ -f /etc/sddm.conf ]; then
        log_info "Cleaning up conflicting legacy /etc/sddm.conf..."
        sudo rm /etc/sddm.conf
    fi
    log_success "Package databases and repositories successfully updated."
}

# Applies all targeted CachyOS compatibility patches to the upstream source files
apply_cachy_patches() {
    log_info "Applying custom CachyOS compatibility patches..."

    # Resolve absolute paths to be safe against working directory drift
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Dynamic host workspace path — used for log persistence; avoids hardcoded usernames
    local HOST_WORKSPACE
    HOST_WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"

    cd "${SCRIPT_DIR}/../omarchy"

    # Patch 0 (CRITICAL): Rewrite guard.sh entirely to support CachyOS + Docker.
    # Using heredoc overwrite instead of fragile sed to avoid metacharacter issues.
    log_info "Patching upstream guard.sh for CachyOS and container compatibility..."
    cat > install/preflight/guard.sh << 'GUARD_EOF'
abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

# Must be an Arch distro
if [[ ! -f /etc/arch-release ]]; then
  abort "Vanilla Arch"
fi

# [CachyOmarchy] CachyOS, EndeavourOS, Garuda, Manjaro are explicitly supported.

# Must not be running as root
if (( EUID == 0 )); then
  abort "Running as root (not user)"
fi

# Must be x86 only to fully work
if [[ $(uname -m) != "x86_64" ]]; then
  abort "x86_64 CPU"
fi

# Must have secure boot disabled
if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
  abort "Secure Boot disabled"
fi

# Must not have Gnome or KDE already installed
if pacman -Qe gnome-shell &>/dev/null || pacman -Qe plasma-desktop &>/dev/null; then
  abort "Fresh + Vanilla Arch"
fi

# Must have limine (bypassed inside Docker/container environments)
if [[ ! -f /.dockerenv ]]; then
  command -v limine &>/dev/null || abort "Limine bootloader"
fi

# Must have btrfs root filesystem (bypassed inside Docker/container environments)
if [[ ! -f /.dockerenv ]]; then
  [[ $(findmnt -n -o FSTYPE /) = "btrfs" ]] || abort "Btrfs root filesystem"
fi

# Cleared all guards
echo "Guards: OK"
GUARD_EOF
    log_success "guard.sh rewritten for CachyOS and container compatibility."

    # Patch 1: Remove conflicting 'tldr' package; ensure 'kitty' terminal is installed
    sed -i '/tldr/d' install/omarchy-base.packages
    # Idempotency guard: only append kitty if not already present
    grep -qx 'kitty' install/omarchy-base.packages || echo "kitty" >> install/omarchy-base.packages

    # Patch 2: Skip base Arch pacman repository configurations during preflight
    sed -i '/run_logged \$OMARCHY_INSTALL\/preflight\/pacman\.sh/d' install/preflight/all.sh

    # Patch 3: Copy and register our high-performance NVIDIA 580xx proprietary driver setup
    cp ../bin/nvidia.sh install/config/hardware/nvidia.sh
    chmod +x install/config/hardware/nvidia.sh

    # Patch 4: Enforce symlink idempotency inside install scripts
    sed -i 's/ln -s/ln -sf/' install/config/omarchy-ai-skill.sh

    # Patch 5: Disable upstream plymouth.sh to prevent graphic login locking conflicts
    sed -i '/run_logged \$OMARCHY_INSTALL\/login\/plymouth\.sh/d' install/login/all.sh

    # Patch 6: CRITICAL - Overwrite snapper script to ONLY re-enable mkinitcpio pacman build hooks.
    # Restores package updates integrity, preventing system bricks on future kernel upgrades.
    log_info "Patching initramfs mkinitcpio hooks manager..."
    cat > install/login/limine-snapper.sh << 'EOF'
#!/bin/bash
echo "Re-enabling CachyOS mkinitcpio hooks..."
if [[ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi
if [[ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi
echo "mkinitcpio hooks successfully re-enabled."
EOF
    chmod +x install/login/limine-snapper.sh

    # Patch 7: Strip alternate bootloaders to preserve CachyOS systemd-boot
    sed -i '/run_logged \$OMARCHY_INSTALL\/login\/alt-bootloaders\.sh/d' install/login/all.sh

    # Patch 8: Prevent post-installation pacman rewrites
    sed -i '/run_logged \$OMARCHY_INSTALL\/post-install\/pacman\.sh/d' install/post-install/all.sh

    # Patch 9: WiFi Device Backend Alignment (NetworkManager + iwd)
    # Disables wpa_supplicant to avoid device driver race conditions and network dropouts.
    log_info "Configuring NetworkManager with high-speed iwd WiFi backend..."
    # Idempotency guard: only append if the wpa_supplicant block is not already present
    if ! grep -q 'wpa_supplicant' install/config/hardware/network.sh 2>/dev/null; then
        cat >> install/config/hardware/network.sh << 'NETEOF'

# Disable conflicting wpa_supplicant services
sudo systemctl disable --now wpa_supplicant.service 2>/dev/null

# Configure NetworkManager to leverage iwd backend
if ! grep -q "wifi.backend=iwd" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
  sudo mkdir -p /etc/NetworkManager
  sudo tee -a /etc/NetworkManager/NetworkManager.conf > /dev/null << EOF

[device]
wifi.backend=iwd
EOF
fi
NETEOF
    else
        log_info "Patch 9 (iwd backend) already applied, skipping."
    fi

    # Patch 10: Pin Walker application version
    # Avoids CachyOS repository overrides that break compatibility with elephant.
    # Idempotency guard: only insert if the IgnorePkg block is not already present
    if ! grep -q 'IgnorePkg.*walker' install/config/walker-elephant.sh 2>/dev/null; then
        sed -i '1a\
# Pin walker package in pacman.conf to prevent incompatible CachyOS overrides\
if ! grep -q "^IgnorePkg.*walker" /etc/pacman.conf 2>/dev/null; then\
  if grep -q "^IgnorePkg" /etc/pacman.conf;\
  then\
    sudo sed -i '"'"'s/^IgnorePkg = \\(.*\\)/IgnorePkg = \\1 walker/'"'"' /etc/pacman.conf\
  else\
    sudo sed -i '"'"'/^\\[options\\]/a IgnorePkg = walker'"'"' /etc/pacman.conf\
  fi\
fi\
' install/config/walker-elephant.sh
    else
        log_info "Patch 10 (walker pin) already applied, skipping."
    fi

    # Patch 11: Setup Fish shell activation paths for mise shims inside UWSM configurations.
    # Idempotency guard: only apply if the old single-shell pattern still exists upstream.
    if grep -q 'omarchy-cmd-present mise' config/uwsm/env 2>/dev/null; then
        log_info "Applying Patch 11 (UWSM Fish+Bash mise shim)..."
        sed -i 's/omarchy-cmd-present mise && eval "\$(mise activate bash --shims)"/if [ "\$SHELL" = "\/bin\/bash" ] \&\& command -v mise \&> \/dev\/null; then\n  eval "\$(mise activate bash --shims)"\nelif [ "\$SHELL" = "\/bin\/fish" ] \&\& command -v mise \&> \/dev\/null; then\n  mise activate fish | source\nfi/' config/uwsm/env
        log_success "Patch 11 (UWSM mise shims) applied."
    else
        log_info "Patch 11 (UWSM mise shims) already up-to-date, skipping."
    fi

    # Patch 12: Make file watchers sysctl call resilient inside container sandboxes
    # Docker/podman standard environment restricts sysctl modifications, causing non-fatal failures that shouldn't halt the installer.
    sed -i 's/sudo sysctl --system/sudo sysctl --system || true/' install/config/increase-file-watchers.sh

    # Patch 13: Automatically persist install logs to host workspace upon completion of install.sh.
    # Uses dynamic HOST_WORKSPACE path (no hardcoded username).
    # Idempotency guard: only inject if the persistence block is not already present.
    if ! grep -q 'CACHYOMARCHY_LOG_PERSIST' install.sh; then
        sed -i "\$a \\
\\
# [CACHYOMARCHY_LOG_PERSIST] Persist logs to mounted host workspace on completion\\
if [ -w \"${HOST_WORKSPACE}\" ]; then\\
  cp \"\/var\/log\/omarchy-install.log\" \"${HOST_WORKSPACE}\/omarchy-install.log\" 2>\/dev\/null || true\\
fi" install.sh
        log_success "Patch 13 (log persistence on success) applied."
    else
        log_info "Patch 13 already applied, skipping."
    fi

    # Patch 14: Ensure error logs are copied to host workspace immediately on crash.
    # Uses dynamic HOST_WORKSPACE path (no hardcoded username).
    # Idempotency guard: only inject if the error persistence block is not already present.
    if ! grep -q 'CACHYOMARCHY_ERR_PERSIST' install/helpers/errors.sh; then
        sed -i "/local exit_code=\$\?/a \\  # [CACHYOMARCHY_ERR_PERSIST] Persist logs on crash\n  if [ -w \"${HOST_WORKSPACE}\" ]; then\n    cp \"\$OMARCHY_INSTALL_LOG_FILE\" \"${HOST_WORKSPACE}\/omarchy-install.log\" 2>\/dev\/null || true\n  fi" install/helpers/errors.sh
        log_success "Patch 14 (log persistence on error) applied."
    else
        log_info "Patch 14 already applied, skipping."
    fi

    log_success "All CachyOmarchy optimization patches successfully applied."
}

# Transfers the configured installer into user local space and launches installation
start_installation() {
    log_info "Preparing local installation files..."
    
    # Replicate the configured deployment folder in ~/.local/share/omarchy
    # Remove a pre-existing directory to avoid stale files from previous partial installs
    mkdir -p ~/.local/share/omarchy
    cp -rT . ~/.local/share/omarchy
    cd ~/.local/share/omarchy

    # Show final checklist
    echo ""
    echo "=============================================================================="
    echo " CachyOmarchy is fully configured and ready to be deployed:"
    echo "=============================================================================="
    echo "  1. Registered [omarchy] repo with TrustAll GPG fallback and dynamic arch."
    echo "  2. Removed conflicting 'tldr' package to prioritize CachyOS's 'tealdeer'."
    echo "  3. Protected CachyOS core packages and pacman config."
    echo "  4. Custom CachyOmarchy proprietary NVIDIA 580xx + VA-API profile added."
    echo "  5. Plymouth disabled to prevent boot-login locks."
    echo "  6. Snapper replaced to safely re-enable system initramfs hooks."
    echo "  7. Alternate bootloaders stripped (systemd-boot preserved)."
    echo "  8. Configured NetworkManager iwd WiFi backend and disabled wpa_supplicant."
    echo "  9. Pinned walker package in pacman.conf to prevent update breakage."
    echo " 10. Added Fish shell support for UWSM mise shims."
    echo " 11. Appended 'kitty' to packages list to guarantee latest terminal installation."
    echo "=============================================================================="
    echo ""
    echo "IMPORTANT: If you installed CachyOS without a desktop environment, you will"
    echo "need to run the following script after this installation completes:"
    echo "   ~/.local/share/omarchy/install/login/plymouth.sh"  
    echo ""
    echo "This will configure your system to launch Hyprland/UWSM automatically."
    echo ""
    echo "Press Enter to begin the installation of CachyOmarchy..."
    read -r

    # Execute main setup script
    chmod +x install.sh
    ./install.sh
}

# ==============================================================================
# SECTION 4: MAIN ORCHESTRATION PIPELINE
# ==============================================================================

main() {
    check_preflight
    clone_upstream
    setup_aur_helper
    setup_keyring
    setup_pacman_repository
    apply_cachy_patches
    start_installation
}

# Trigger the modular pipeline
main "$@"
