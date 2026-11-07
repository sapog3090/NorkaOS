#!/usr/bin/env bash
set -euo pipefail
# Сборка ISO в WSL с Arch: wsl -d archlinux -u root -- bash /mnt/d/noriOS/archiso/build-wsl.sh
# Быстрый тестовый образ: wsl -d archlinux -u root -- env FAST=1 bash /mnt/d/noriOS/archiso/build-wsl.sh
# Образ ложится в E:\NorkaVM\iso-local. Пока идёт сжатие, ПК сильно занят: виртуалку лучше выключить
src=/mnt/d/noriOS
if ! command -v mkarchiso >/dev/null; then
  pacman-key --init
  pacman-key --populate archlinux
fi
# grub и noto-fonts нужны для меню загрузки: шрифты темы делаются при сборке
pacman -Syu --needed --noconfirm archiso grub noto-fonts
pacman-key --add "$src/pkgbuilds/norkaos-keyring/norkaos.gpg"
pacman-key --lsign-key "$(cut -d: -f1 "$src/pkgbuilds/norkaos-keyring/norkaos-trusted")"
# build-repo пересобирает наши пакеты при той же версии, старые копии в кэше не пройдут проверку
rm -f /var/cache/pacman/pkg/norkaos-*
b=/var/tmp/norka
rm -rf "$b"; mkdir -p "$b" /mnt/e/NorkaVM/iso-local
bash "$src/archiso/make-profile.sh" "$b/profile"
# FAST=1: тестовый образ со сжатием zstd вместо xz -9, собирается в 2-3 раза быстрее, но крупнее. Для релиза не годится
if [[ "${FAST:-0}" == 1 ]]; then
  sed -i "s/^airootfs_image_tool_options=.*/airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '3' '-b' '1M')/" "$b/profile/profiledef.sh"
  sed -i 's/^COMPRESSION=.*/COMPRESSION="zstd"/; /^COMPRESSION_OPTIONS=/d' "$b/profile/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
fi
mkarchiso -v -w "$b/work" -o /mnt/e/NorkaVM/iso-local "$b/profile"
cd /mnt/e/NorkaVM/iso-local && sha256sum *.iso > SHA256SUMS
rm -rf "$b"
echo BUILD-OK
