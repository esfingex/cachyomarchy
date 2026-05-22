#!/bin/bash
echo "Configurando entrada de sesión de coexistencia para Omarchy..."
sudo mkdir -p /usr/local/share/wayland-sessions
sudo mkdir -p /usr/share/wayland-sessions

# Copiar el descriptor de sesión de Omarchy para GDM y otros gestores
sudo cp "$OMARCHY_PATH/default/wayland-sessions/omarchy.desktop" /usr/local/share/wayland-sessions/omarchy.desktop
sudo cp "$OMARCHY_PATH/default/wayland-sessions/omarchy.desktop" /usr/share/wayland-sessions/omarchy.desktop

echo "Sesión de coexistencia registrada exitosamente."
