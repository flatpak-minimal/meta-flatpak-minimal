#!/bin/sh
set -e

APPID="org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager"
BUNDLE="/usr/share/flatpak-minimal/bundles/org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager_stable_aarch64.flatpak"

if flatpak info --user "$APPID" >/dev/null 2>&1; then
    echo "install-remote-manager: $APPID already installed, nothing to do"
    exit 0
fi

flatpak install --user -y --bundle "$BUNDLE"
