#!/bin/sh
# Wrap build/linux/x64/release/bundle into Pantrace-linux-amd64.deb. Usage: package-deb.sh <version>
set -e
V=$1; P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/opt/pantrace" "$P/usr/bin" "$P/usr/share/applications"
install -Dm644 linux/pantrace.png "$P/usr/share/icons/hicolor/256x256/apps/pantrace.png"
cp -r build/linux/x64/release/bundle/. "$P/opt/pantrace/"
ln -s /opt/pantrace/pantrace "$P/usr/bin/pantrace"
cat > "$P/DEBIAN/control" <<CTL
Package: pantrace
Version: $V
Architecture: amd64
Maintainer: PanterSoft <https://github.com/PanterSoft/Pantrace>
Depends: libgtk-3-0
Description: Cross-platform CAN tracer with DBC decoding.
CTL
cat > "$P/usr/share/applications/pantrace.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Pantrace
Exec=/opt/pantrace/pantrace
Icon=pantrace
Categories=Development;Electronics;
DESK
dpkg-deb --build --root-owner-group "$P" Pantrace-linux-amd64.deb
