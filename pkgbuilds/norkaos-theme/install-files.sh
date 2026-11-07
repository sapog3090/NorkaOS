#!/usr/bin/env bash
# Раскладывает тему в корень из первого аргумента. Запускается из папки пакета
set -eu

dest="$1"
share="$dest/usr/share"

install -Dm644 NorkaOS.colors "$share/color-schemes/NorkaOS.colors"

install -d "$share/plasma/look-and-feel"
rm -rf "$share/plasma/look-and-feel/org.norkaos.desktop"
cp -r lookandfeel "$share/plasma/look-and-feel/org.norkaos.desktop"

install -Dm644 art/wallpaper/norka-dusk.png "$share/wallpapers/NorkaOS/contents/images/3840x2160.png"
install -Dm644 wallpaper-metadata.json "$share/wallpapers/NorkaOS/metadata.json"

install -Dm644 art/logo/norka-icon.svg "$share/icons/hicolor/scalable/apps/norkaos.svg"
install -Dm644 art/logo/norka-symbolic.svg "$share/icons/hicolor/symbolic/apps/norkaos-symbolic.svg"
install -Dm644 art/logo/norka-logo.svg "$share/pixmaps/norkaos-logo.svg"

# Курсоры рисуются при сборке: нужны python, librsvg и xorg-xcursorgen
python art/cursor/make.py "$share/icons"

# Цвета схемы читаются из kdeglobals, поэтому файл схемы дописывается сюда целиком
install -d "$dest/etc/xdg"
cat kdeglobals.head NorkaOS.colors > "$dest/etc/xdg/kdeglobals"
chmod 644 "$dest/etc/xdg/kdeglobals"
install -m644 xdg/plasmarc xdg/ksplashrc xdg/kscreenlockerrc xdg/kcminputrc "$dest/etc/xdg/"

# Экран входа: тема breeze из plasma-desktop, фон наш
install -Dm644 sddm/10-norkaos.conf "$dest/etc/sddm.conf.d/10-norkaos.conf"
install -Dm644 sddm/theme.conf.user "$share/sddm/themes/breeze/theme.conf.user"
