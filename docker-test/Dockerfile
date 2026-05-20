# syntax=docker/dockerfile:1.4
FROM archlinux:latest

# Step 1: Enable multilib and install base dependencies required for Arch compilation and setup
# Use BuildKit cache mount to avoid re-downloading packages on every build
RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

RUN --mount=type=cache,target=/var/cache/pacman/pkg,sharing=locked \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm --noprogressbar && \
    pacman -S --needed --noconfirm --noprogressbar base-devel git curl sudo pciutils

# Step 2: Bootstrap the official CachyOS repositories and signatures
RUN --mount=type=cache,target=/var/cache/pacman/pkg,sharing=locked \
    curl -O https://mirror.cachyos.org/cachyos-repo.tar.xz && \
    tar xvf cachyos-repo.tar.xz && \
    cd cachyos-repo && \
    yes | ./cachyos-repo.sh && \
    cd .. && \
    rm -rf cachyos-repo cachyos-repo.tar.xz

# Step 3: Refresh databases with CachyOS active and install Cachy Hardware Detection (chwd)
RUN --mount=type=cache,target=/var/cache/pacman/pkg,sharing=locked \
    pacman -Syu --noconfirm --noprogressbar && \
    pacman -S --needed --noconfirm --noprogressbar chwd libva-utils gum

# Step 4: Create the non-root 'esfingex' user with passwordless sudo (required by the installer)
RUN useradd -m -u 1000 -G wheel -s /bin/bash esfingex && \
    echo "esfingex ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Run as the normal user 'esfingex' inside the workspace
USER esfingex
WORKDIR /home/esfingex/omarchy-on-cachyos
