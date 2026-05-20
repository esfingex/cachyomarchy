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
