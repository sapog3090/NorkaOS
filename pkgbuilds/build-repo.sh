#!/usr/bin/env bash
# Собирает и подписывает репозиторий norkaos в папке из первого аргумента
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(realpath -m "${1:?укажи папку результата}")"
kernel=7.3.1-1
cachyos_mirror=https://mirror.cachyos.org/repo/x86_64/cachyos
cachyos_key=882DCFE48E2051D48E2562ABF3B607488DB35A47

mkdir -p "$out"

# Свои пакеты: makepkg не работает от root
useradd -m builder
for dir in "$here"/*/; do
  name="$(basename "$dir")"
  cp -r "$dir" "/home/builder/$name"
  cp -r "$here/../art" "/home/builder/$name/art"
  chown -R builder: "/home/builder/$name"
  su builder -c "cd /home/builder/$name && makepkg --nodeps --noconfirm"
  cp /home/builder/"$name"/*.pkg.tar.zst "$out/"
done

# Ядро CachyOS: сначала проверяем их подпись, потом подписываем своей
export GNUPGHOME
GNUPGHOME="$(mktemp -d)"
gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$cachyos_key"
for pkg in linux-cachyos linux-cachyos-headers; do
  file="$pkg-$kernel-x86_64.pkg.tar.zst"
  curl -fsSL --retry 3 -o "$out/$file" "$cachyos_mirror/$file"
  curl -fsSL --retry 3 -o "$GNUPGHOME/$file.sig" "$cachyos_mirror/$file.sig"
  gpg --batch --verify "$GNUPGHOME/$file.sig" "$out/$file"
done

GNUPGHOME="$(mktemp -d)"
gpg --batch --import <<<"$NORKA_SIGNING_KEY"
fpr="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')"
expected="$(cut -d: -f1 "$here/norkaos-keyring/norkaos-trusted")"
[[ "$fpr" == "$expected" ]] || { echo "секрет не совпадает с ключом в norkaos-keyring"; exit 1; }

for file in "$out"/*.pkg.tar.zst; do
  gpg --batch --yes --local-user "$fpr" --detach-sign "$file"
done
repo-add --sign --key "$fpr" "$out/norkaos.db.tar.zst" "$out"/*.pkg.tar.zst

# GitHub Releases не хранит симлинки, pacman просит файлы без .tar.zst
for name in norkaos.db norkaos.db.sig norkaos.files norkaos.files.sig; do
  cp --remove-destination "$(readlink -f "$out/$name")" "$out/$name"
done
rm -f "$out"/norkaos.db.tar.zst* "$out"/norkaos.files.tar.zst* "$out"/*.old "$out"/*.old.sig
