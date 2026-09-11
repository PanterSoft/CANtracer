#!/bin/sh
# Wrap build/linux/x64/release/bundle into CANtracer-linux-amd64.deb. Usage: package-deb.sh <version>
set -e
V=$1; P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/opt/cantracer" "$P/usr/bin" "$P/usr/share/applications"
install -Dm644 linux/cantracer.png "$P/usr/share/icons/hicolor/256x256/apps/cantracer.png"
cp -r build/linux/x64/release/bundle/. "$P/opt/cantracer/"
ln -s /opt/cantracer/cantracer "$P/usr/bin/cantracer"
cat > "$P/DEBIAN/control" <<CTL
Package: cantracer
Version: $V
Architecture: amd64
Maintainer: PanterSoft <https://github.com/PanterSoft/CANtracer>
Depends: libgtk-3-0
Description: Cross-platform CAN tracer with DBC decoding.
CTL
cat > "$P/usr/share/applications/cantracer.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=CANtracer
Exec=/opt/cantracer/cantracer
Icon=cantracer
Categories=Development;Electronics;
DESK
dpkg-deb --build --root-owner-group "$P" CANtracer-linux-amd64.deb
