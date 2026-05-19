FROM archlinux:latest

# Step 1: Install base dependencies required for Arch compilation and setup
RUN pacman -Syu --noconfirm && \
    pacman -S --needed --noconfirm base-devel git curl sudo pciutils

# Step 2: Bootstrap the official CachyOS repositories and signatures
RUN curl -fsSL https://raw.githubusercontent.com/cachyos/cachyos-repo-config/main/cachyos-repo-config.sh | bash

# Step 3: Refresh databases with CachyOS active and install Cachy Hardware Detection (chwd)
RUN pacman -Syu --noconfirm && \
    pacman -S --needed --noconfirm chwd libva-utils

# Step 4: Create the non-root 'esfingex' user with passwordless sudo (required by the installer)
RUN useradd -m -u 1000 -G wheel -s /bin/bash esfingex && \
    echo "esfingex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Run as the normal user 'esfingex' inside the workspace
USER esfingex
WORKDIR /home/esfingex/omarchy-on-cachyos
