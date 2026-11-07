#!/usr/bin/env bash
# Собирает профиль NorkaOS из штатного releng и файлов этой папки
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dst="${1:?укажи папку профиля}"
root="$dst/airootfs"
units="$root/etc/systemd/system"

cp -a /usr/share/archiso/configs/releng "$dst"

# Пакеты: гостевые утилиты с графикой конфликтуют с версией nox, cloud-init живой системе не нужен,
# ядро заменяем на CachyOS, а broadcom-wl собран под штатное ядро и потянул бы его обратно
sed -i \
  -e '/^virtualbox-guest-utils-nox$/d' \
  -e '/^cloud-init$/d' \
  -e '/^linux$/d' \
  -e '/^broadcom-wl$/d' \
  "$dst/packages.x86_64"
# Инструменты спасения серверов из releng обычному человеку не нужны, а образ должен влезть в 2 ГБ (предел файла в релизе GitHub).
# Установщику нужны arch-install-scripts, parted, gptfdisk, btrfs-progs, dosfstools, rsync, efibootmgr: их не трогаем.
# brltty и espeakup оставлены для пункта меню с экранным диктором, nbd и mkinitcpio-nfs-utils нужны хукам загрузки archiso
for pkg in archinstall clonezilla partclone partimage fsarchiver ddrescue testdisk gpart \
           irssi lynx lftp mc nmap tcpdump darkhttpd bind ldns dnsmasq ndisc6 \
           openconnect openvpn vpnc pptpclient xl2tpd wvdial ppp open-iscsi \
           hyperv open-vm-tools qemu-guest-agent \
           grml-zsh-config zsh tmux screen vim man-db man-pages \
           bcachefs-tools nilfs-utils jfsutils dmraid sequoia-sq openpgp-card-tools tpm2-tools tpm2-tss \
           gpm mmc-utils sg3_utils sdparm refind reflector iwd b43-fwcutter \
           rxvt-unicode-terminfo foot-terminfo ghostty-terminfo kmscon-terminfo; do
  sed -i "/^$pkg\$/d" "$dst/packages.x86_64"
done
grep -v -e '^#' -e '^$' "$here/packages.txt" >> "$dst/packages.x86_64"

# Репозитории: живая система читает снимок из norkaos-mirrorlist, сборка берёт ту же дату
snapshot="$(sed -n 's/^pkgver=//p' "$here/../pkgbuilds/norkaos-mirrorlist/PKGBUILD")"
snapshot="${snapshot:0:4}/${snapshot:4:2}/${snapshot:6:2}"
sed -i '/^\[core\]/i [norkaos]\nSigLevel = Required DatabaseRequired\nServer = https://github.com/sapog3090/NorkaOS/releases/download/repo\n' "$dst/pacman.conf"
sed 's|^Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/norkaos-snapshot|' "$dst/pacman.conf" > "$root/etc/pacman.conf"
# multilib нужен Steam и 32-битным библиотекам игр, берётся из того же снимка
sed -i '/^#\[multilib\]$/{s/^#//;n;s|^#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/norkaos-snapshot|}' "$root/etc/pacman.conf"
grep -A1 '^\[multilib\]' "$root/etc/pacman.conf" | grep -q norkaos-snapshot
sed -i "s|^Include = /etc/pacman.d/mirrorlist|Server = https://archive.archlinux.org/repos/$snapshot/\$repo/os/\$arch|" "$dst/pacman.conf"

cp -a "$here/airootfs/." "$root/"

# Меню загрузки UEFI: systemd-boot умеет только текст, поэтому GRUB с темой NorkaOS
sed -i "s/'uefi.systemd-boot'/'uefi.grub'/" "$dst/profiledef.sh"
rm -rf "$dst/efiboot"
theme="$dst/grub/themes/norkaos"
cp -r "$here/grub/themes" "$dst/grub/"
cp "$here/../art/boot/grub-background.png" "$theme/background.png"
cp "$here/../art/boot/select_c.png" "$theme/"
glyphs='0x20-0x7E,0xA0-0x17F,0x400-0x4FF,0x2010-0x2027'
noto=/usr/share/fonts/noto
grub-mkfont -r "$glyphs" -s 18 -o "$theme/norka-18.pf2" "$noto/NotoSans-Regular.ttf"
grub-mkfont -r "$glyphs" -s 24 -o "$theme/norka-24.pf2" "$noto/NotoSans-Regular.ttf"
grub-mkfont -r "$glyphs" -s 24 -o "$theme/norka-bold-24.pf2" "$noto/NotoSans-Bold.ttf"
sed -i -e '/^    terminal_output console$/{r '"$here/boot/grub-theme.cfg" -e 'd}' "$dst/grub/grub.cfg"
# Пункт «безопасная графика» встаёт перед пунктом с экранным диктором
awk -v f="$here/boot/grub-safe.cfg" '/with speakup screen reader/ { while ((getline l < f) > 0) print l } { print }' \
  "$dst/grub/grub.cfg" > "$dst/grub/grub.cfg.new"
mv "$dst/grub/grub.cfg.new" "$dst/grub/grub.cfg"
# Короткие названия пунктов: длинные не влезают в меню на маленьком экране
sed -i   -e 's/ (%ARCH%, ${archiso_platform})"/"/'   -e 's/with speakup screen reader/with screen reader/'   -e "s/'Run Memtest86+ (RAM test)'/'Memory test'/"   -e "s/'UEFI Firmware Settings'/'Firmware settings'/"   -e "s/'System shutdown'/'Shut down'/"   -e "s/'System restart'/'Restart'/"   "$dst/grub/grub.cfg"

# Загрузочный экран с Норкой: видеодрайвер и plymouth в initramfs, quiet splash только в основном пункте.
# В безопасной графике и с диктором остаётся обычный текст
sed -i 's/^HOOKS=(base udev microcode modconf /HOOKS=(base udev microcode modconf kms plymouth /' \
  "$root/etc/mkinitcpio.conf.d/archiso.conf"
grep -q 'kms plymouth' "$root/etc/mkinitcpio.conf.d/archiso.conf"
sed -i 's/archisosearchuuid=%ARCHISO_UUID% %KERNEL_PARAMS%/archisosearchuuid=%ARCHISO_UUID% quiet splash %KERNEL_PARAMS%/' \
  "$dst/grub/grub.cfg" "$dst/syslinux/archiso_sys-linux.cfg"

# Меню загрузки BIOS: наш фон и фиолетовая подсветка
cp "$here/../art/boot/syslinux-splash.png" "$dst/syslinux/splash.png"
sed -i \
  -e 's/^MENU TITLE Arch Linux$/MENU TITLE NorkaOS/' \
  -e 's/^MENU COLOR sel .*/MENU COLOR sel          7;37;40 #ffffffff #a07a4fd0 all/' \
  -e 's/^MENU COLOR title .*/MENU COLOR title        1;36;44 #ffc9b8ea #00000000 std/' \
  "$dst/syslinux/archiso_head.cfg"
awk -v f="$here/boot/syslinux-safe.cfg" '/^# Accessibility boot option$/ { while ((getline l < f) > 0) print l } { print }' \
  "$dst/syslinux/archiso_sys-linux.cfg" > "$dst/syslinux/archiso_sys-linux.cfg.new"
mv "$dst/syslinux/archiso_sys-linux.cfg.new" "$dst/syslinux/archiso_sys-linux.cfg"
# Короткие названия, как в GRUB
sed -i -e 's/ (%ARCH%, BIOS), /, /' -e 's/ (%ARCH%, BIOS) / /' -e 's/ (%ARCH%, BIOS)$//' -e 's/with ^speech/with screen ^reader/' \
  "$dst/syslinux/archiso_sys-linux.cfg"
sed -i -e 's/Run Memtest86+ (RAM test)/Memory test/' -e 's/Hardware Information (HDT)/Hardware info/' -e 's/^MENU LABEL Power Off$/MENU LABEL Shut down/' -e 's/^MENU LABEL Reboot$/MENU LABEL Restart/' \
  "$dst/syslinux/archiso_tail.cfg"

# Место под изменения в живой системе: по умолчанию 256 МБ, установка пары пакетов его съедает
sed -i 's/archisosearchuuid=%ARCHISO_UUID%/archisosearchuuid=%ARCHISO_UUID% cow_spacesize=1G/' \
  "$dst/grub/grub.cfg" "$dst/syslinux/archiso_sys-linux.cfg"

# Имя системы
sed -i \
  -e 's/^iso_name=.*/iso_name="norkaos"/' \
  -e 's/^iso_label="ARCH_/iso_label="NORKAOS_/' \
  -e 's|^iso_publisher=.*|iso_publisher="NorkaOS <https://github.com/sapog3090/NorkaOS>"|' \
  -e 's/^iso_application=.*/iso_application="NorkaOS Live"/' \
  -e '/^file_permissions=(/a\  ["/etc/gshadow"]="0:0:400"\n  ["/etc/sudoers.d/norka-live"]="0:0:440"\n  ["/home/norka/"]="1000:1000:750"' \
  "$dst/profiledef.sh"
find "$dst/syslinux" "$dst/grub" -type f \( -name '*.cfg' -o -name '*.conf' \) -exec sed -i \
  -e 's/Arch Linux install medium/NorkaOS Live/g' \
  -e 's/install Arch Linux/try NorkaOS/g' \
  -e 's/vmlinuz-linux/vmlinuz-linux-cachyos/g' \
  -e 's/initramfs-linux\.img/initramfs-linux-cachyos.img/g' {} +
echo norka > "$root/etc/hostname"
: > "$root/etc/motd"

# Пользователь живой системы
mkdir -p "$root/home/norka"
# Аватар Норки: в домашней папке для Plasma, отдельно для SDDM и AccountsService, им домашняя папка закрыта
face="$here/../art/mascot/norka-face.png"
install -Dm644 "$face" "$root/home/norka/.face.icon"
install -Dm644 "$face" "$root/usr/share/sddm/faces/norka.face.icon"
install -Dm644 "$face" "$root/var/lib/AccountsService/icons/norka"
printf '[User]\nIcon=/var/lib/AccountsService/icons/norka\n' | install -Dm644 /dev/stdin "$root/var/lib/AccountsService/users/norka"
echo 'norka:x:1000:1000:Norka:/home/norka:/bin/bash' >> "$root/etc/passwd"
# zsh из образа убран, root получает bash
sed -i 's|^\(root:.*\):/usr/bin/zsh$|\1:/bin/bash|' "$root/etc/passwd"
rm -f "$root/root/.zlogin"
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
