#!/bin/bash
# Enable iwd service to start on next boot
sudo systemctl enable iwd.service 2>/dev/null

# Prevent systemd-networkd-wait-online timeout on boot
sudo systemctl disable systemd-networkd-wait-online.service 2>/dev/null
sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null

# Disable conflicting wpa_supplicant service on next boot
sudo systemctl disable wpa_supplicant.service 2>/dev/null

# Configure NetworkManager to leverage iwd backend
if ! grep -q "wifi.backend=iwd" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
  sudo mkdir -p /etc/NetworkManager
  sudo tee -a /etc/NetworkManager/NetworkManager.conf > /dev/null << EOF

[device]
wifi.backend=iwd
EOF
fi
