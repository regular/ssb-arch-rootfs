#!/usr/bin/bash
set -eux -o pipefail

export ssb_appname=ssb-pacman
root=root
bin="$HOME/.ssb-pacman/node_modules/ssb-pacman/bin"
archisodir=$(mktemp -d)

ssb-pacman () {
  local cmd=$1
  shift
  $bin/ssb-pacman-$cmd $*
}

extract_archiso_script () {
  archiso_id=$(sbot pacman.versions archiso --arch x86_64 --sort | jsonpath-dl key | head -n1)
  echo "Extracting" "$(sbot pacman.get "$archiso_id" | jsonpath-dl content.name)" "..."
  ssb-pacman extract "$archiso_id" "$archisodir"
}

install_packages () {
  pkgs="base syslinux haveged intel-ucode memtest86+ mkinitcpio-nfs-utils nbd zsh"
  pkgs+=" efitools"
  for pkg in $pkgs; do
    ssb-pacman install "$pkg" "$root"
  done
}

make_initcpio () {
  mkdir -p "$root/etc/initcpio/hooks"
  mkdir -p "$root/etc/initcpio/install"

  hooks="\
    archiso \
    archiso_shutdown \
    archiso_pxe_common \
    archiso_pxe_nbd \
    archiso_pxe_http \
    archiso_pxe_nfs \
    archiso_loop_mnt \
  "

  local src="$archisodir/usr/lib/initcpio"
  local dest="$root/etc/initcpio"
  local script_path="$archisodir/usr/share/archiso/configs/releng"

  for hook in $hooks; do
    sudo cp "$src/hooks/$hook" "$dest/hooks"
    sudo cp "$src/install/$hook" "$dest/install"
  done
  
  sudo sed -i "s|/usr/lib/initcpio/|/etc/initcpio/|g" "$dest/install/archiso_shutdown"
  sudo cp "$src/install/archiso_kms" "$dest/install"
  sudo cp "$src/archiso_shutdown" "$dest"

  sudo cp "${script_path}/mkinitcpio.conf" "$root/etc/mkinitcpio-archiso.conf"
  sudo arch-chroot "$root" mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img
}

ssb-pacman bootstrap "$root"
install_packages
extract_archiso_script
make_initcpio
