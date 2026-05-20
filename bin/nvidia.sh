#!/bin/bash
# ==============================================================================
#      _  ____     _____ ____ ___   _                                        
#     | |/ /\ \   / /_ _|  _ \_ _| / \                                       
#     | ' /  \ \ / / | || | | | | / _ \                                      
#     | . \   \ V /  | || |_| | |/ ___ \                                     
#     |_|\_\   \_/  |___|____/___/_/   \_\                                    
#                                                                            
#   CachyOmarchy - CachyOS NVIDIA 580xx Proprietary Driver Custom Patch
# ==============================================================================
# Target OS: CachyOS (Arch Linux based)
# Purpose  : Configures chwd (Cachy Hardware Detection) to automatically setup
#            proprietary NVIDIA 580xx drivers, removing conflicting open modules,
#            installing VA-API diagnostics, and setting UWSM environment.
# ==============================================================================

# Exit immediately if any command exits with a non-zero status
set -e

# ==============================================================================
# STEP 1: DETECT NVIDIA HARDWARE
# ==============================================================================
# Ensure lspci is installed (from pciutils package)
if ! command -v lspci &>/dev/null; then
    echo "[*] 'lspci' not found. Installing 'pciutils' to detect hardware..."
    sudo pacman -S --needed --noconfirm pciutils 2>/dev/null || echo "[!] Failed to install pciutils, attempting fallback."
fi

# Query local PCI devices to find the primary NVIDIA graphics card ID.
# - VGA (0300) or 3D controller (0302) PCI class matching vendor 10de (NVIDIA)
GPU_ID=$(lspci -nn -d 10de: | grep -E "VGA|3D" | head -n1 | grep -oP '(?<=\[10de:)[0-9a-fA-F]{4}(?=\])' || true)

if [[ -z "$GPU_ID" ]]; then
    echo "No NVIDIA GPU detected on this system. Skipping NVIDIA configurations."
    exit 0
fi

echo "[*] Detected NVIDIA GPU Device ID: $GPU_ID"

# ==============================================================================
# STEP 2: ELIMINATE OPEN DRIVER CONFLICTS
# ==============================================================================
# CachyOS frequently installs the open-source kernel modules (nvidia-open-dkms)
# by default. These conflict directly with the high-performance proprietary 
# driver setup. We force-remove them to clear the path.
echo "[*] Removing conflicting open-source NVIDIA drivers and helpers..."
sudo pacman -Rdd --noconfirm libxnvctrl linux-cachyos-nvidia-open linux-cachyos-lts-nvidia-open nvidia-open-dkms 2>/dev/null || true

# ==============================================================================
# STEP 3: PATCH CHWD DEVICE ID REGISTER
# ==============================================================================
# We append the detected GPU ID to /var/lib/chwd/ids/nvidia-580.ids to register 
# it for proprietary 580xx automatic hardware configuration.
echo "[*] Ensuring chwd ID registry directory and file exist..."
sudo mkdir -p /var/lib/chwd/ids
sudo touch /var/lib/chwd/ids/nvidia-580.ids

if ! grep -q "$GPU_ID" /var/lib/chwd/ids/nvidia-580.ids; then
    echo "[*] Adding GPU ID ($GPU_ID) to the chwd 580xx proprietary list..."
    
    # Insert a trailing newline if the file is not empty and lacks one
    if [ -s /var/lib/chwd/ids/nvidia-580.ids ] && [ -n "$(tail -c1 /var/lib/chwd/ids/nvidia-580.ids 2>/dev/null)" ]; then
        sudo sh -c "echo >> /var/lib/chwd/ids/nvidia-580.ids"
    fi
    
    # Safely append the GPU ID to the registry
    sudo sh -c "echo '$GPU_ID' >> /var/lib/chwd/ids/nvidia-580.ids"
else
    echo "[*] GPU ID ($GPU_ID) is already present in the chwd 580xx registry, skipping patch."
fi

# ==============================================================================
# STEP 4: TRIGGER HARDWARE AUTO-CONFIGURATION
# ==============================================================================
# Reset the old chwd profile and trigger auto-configuration.
# chwd will detect our patched ID list and automatically download, install, 
# and load the correct proprietary 580xx drivers.
echo "[*] Removing any old chwd open-driver profiles..."
sudo chwd -r nvidia-open-dkms || true

# Ensure mkinitcpio.conf.d exists so chwd's pre_install hook can write to it
echo "[*] Ensuring /etc/mkinitcpio.conf.d exists..."
sudo mkdir -p /etc/mkinitcpio.conf.d

# chwd nvidia profile's conditional_packages hook searches for /usr/lib/modules/*/pkgbase
# to determine the headers package to install. In containers or environments without host modules setup,
# this directory or its pkgbase files may be missing. When no matches exist, the hook outputs "-headers",
# which pacman interprets as an invalid option (-h -e -a -d -e -r -s) and fails with "pacman: invalid option -- 'a'".
# We create a fallback mock pkgbase file if none are present to ensure compatibility.
if ! ls /usr/lib/modules/*/pkgbase &>/dev/null; then
    echo "[*] No kernel pkgbase files detected. Creating a mock entry for chwd compatibility..."
    sudo mkdir -p "/usr/lib/modules/$(uname -r)"
    echo "linux" | sudo tee "/usr/lib/modules/$(uname -r)/pkgbase" > /dev/null
fi

echo "[*] Running chwd automatic proprietary hardware configuration..."
sudo chwd -a

# ==============================================================================
# STEP 5: INSTALL HARDWARE ACCELERATION SUPPORT
# ==============================================================================
# Consolidated hardware acceleration utility installation:
# - libva-utils: Diagnostic utilities to verify and debug VA-API hardware-accelerated video decoding support.
echo "[*] Installing hardware acceleration support packages..."
sudo pacman -S --needed --noconfirm libva-utils

# ==============================================================================
# STEP 6: INJECT ENVIRONMENT VARIABLES FOR UWSM
# ==============================================================================
# Hyprland under Wayland requires specific environment variables to render 
# correctly on proprietary NVIDIA drivers. We write these into UWSM's config
# so they are loaded at session startup.
echo "[*] Injecting NVIDIA Wayland environment variables into UWSM..."
mkdir -p "$HOME/.config/uwsm"

# Idempotency guard: only inject env vars if they are not already present
if ! grep -q 'LIBVA_DRIVER_NAME=nvidia' "$HOME/.config/uwsm/env" 2>/dev/null; then
    cat >> "$HOME/.config/uwsm/env" << 'EOF'

# NVIDIA Wayland & Hardware Acceleration Settings
export LIBVA_DRIVER_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
export MOZ_DISABLE_RDD_SANDBOX=1
export CUDA_DISABLE_PERF_BOOST=1
EOF
else
    echo "[*] NVIDIA UWSM environment variables already present, skipping injection."
fi

echo "[+] CachyOmarchy NVIDIA proprietary configuration completed successfully!"
