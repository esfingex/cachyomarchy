# Increase inotify file watchers for VS Code, webpack, and other dev tools (default 8192 is too low)
echo "fs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/90-omarchy-file-watchers.conf >/dev/null
sudo sysctl --system || true >/dev/null 2>&1
