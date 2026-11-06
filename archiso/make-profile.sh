#!/usr/bin/env bash
# Собирает профиль NorkaOS из штатного releng и файлов этой папки
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dst="${1:?укажи папку профиля}"
root="$dst/airootfs"
units="$root/etc/systemd/system"

cp -a /usr/share/archiso/configs/releng "$dst"

# Пакеты: гостевые утилиты с графикой конфликтуют с версией nox, cloud-init живой системе не нужен
sed -i -e '/^virtualbox-guest-utils-nox$/d' -e '/^cloud-init$/d' "$dst/packages.x86_64"
grep -v -e '^#' -e '^$' "$here/packages.txt" >> "$dst/packages.x86_64"

cp -a "$here/airootfs/." "$root/"

# Имя системы
sed -i \
  -e 's/^iso_name=.*/iso_name="norkaos"/' \
  -e 's/^iso_label="ARCH_/iso_label="NORKAOS_/' \
  -e 's|^iso_publisher=.*|iso_publisher="NorkaOS <https://github.com/sapog3090/NorkaOS>"|' \
  -e 's/^iso_application=.*/iso_application="NorkaOS Live"/' \
  -e '/^file_permissions=(/a\  ["/etc/gshadow"]="0:0:400"\n  ["/etc/sudoers.d/norka-live"]="0:0:440"\n  ["/home/norka/"]="1000:1000:750"' \
  "$dst/profiledef.sh"
find "$dst/syslinux" "$dst/efiboot" "$dst/grub" -type f \( -name '*.cfg' -o -name '*.conf' \) -exec sed -i \
  -e 's/Arch Linux install medium/NorkaOS Live/g' \
  -e 's/install Arch Linux/try NorkaOS/g' {} +
echo norka > "$root/etc/hostname"
: > "$root/etc/motd"

# Пользователь живой системы
mkdir -p "$root/home/norka"
echo 'norka:x:1000:1000:Norka:/home/norka:/bin/bash' >> "$root/etc/passwd"
echo 'norka::14871::::::' >> "$root/etc/shadow"

# Сеть ведёт NetworkManager. SSH и автовход root при пустом пароле в графической системе не нужны
rm -f \
  "$units/multi-user.target.wants/iwd.service" \
  "$units/multi-user.target.wants/sshd.service" \
  "$units/multi-user.target.wants/systemd-networkd.service" \
  "$units/sockets.target.wants/systemd-networkd.socket" \
  "$units/network-online.target.wants/systemd-networkd-wait-online.service" \
  "$units/dbus-org.freedesktop.network1.service"
rm -rf "$units/cloud-init.target.wants" "$units/getty@tty1.service.d"

ln -s /usr/lib/systemd/system/NetworkManager.service "$units/multi-user.target.wants/NetworkManager.service"
ln -s /usr/lib/systemd/system/sddm.service "$units/display-manager.service"
ln -s /usr/lib/systemd/system/graphical.target "$units/default.target"
