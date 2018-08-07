#!/usr/bin/bash
ad
set -eux -o pipefail

export ssb_appname=ssb-pacman
root=root
bin="$HOME/.ssb-pacman/node_modules/ssb-pacman/bin"

source ./config

ssb-pacman () {
  local cmd=$1
  shift
  $bin/ssb-pacman-$cmd $*
}

install_packages () {
  pkgs="\
    haveged \
    intel-ucode \
    memtest86+ \
    efitools
  "

  for pkg in $pkgs; do
    ssb-pacman install "$pkg" "$root"
  done
}

make_initcpio () {
  mkdir -p "$root/etc/initcpio/hooks"
  mkdir -p "$root/etc/initcpio/install"

  # TODO: list hooks on mkcpio cmdline rather than in conf file,
  # so we can configure them here

  hooks="\
    archiso \
    archiso_shutdown \
    archiso_loop_mnt \
  "
  local src="initcpio"
  local dest="$root/etc/initcpio"

  for hook in $hooks; do
    sudo cp "$src/hooks/$hook" "$dest/hooks"
    sudo cp "$src/install/$hook" "$dest/install"
  done
  
  sudo sed -i "s|/usr/lib/initcpio/|/etc/initcpio/|g" "$dest/install/archiso_shutdown"
  sudo cp "$src/install/archiso_kms" "$dest/install"
  sudo cp "$src/archiso_shutdown" "$dest"

  sudo cp "$src/mkinitcpio.conf" "$root/etc/mkinitcpio-archiso.conf"
  sudo arch-chroot "$root" mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img
}

make_efi() {
  local efitools="$root/usr/share/efitools"
  local EFI="$root/boot/EFI"
  sudo mkdir -p "$EFI/boot"
  sudo cp "$efitools/efi/PreLoader.efi" "$EFI/boot/bootx64.efi"
  sudo cp "$efitools/efi/HashTool.efi" "$EFI/boot/"
  sudo cp "$root/usr/lib/systemd/boot/efi/systemd-bootx64.efi" \
    "$EFI/boot/loader.efi"

  local entries="$root/boot/loader/entries"
  sudo mkdir -p "$entries"

  sudo cp loader/loader.conf "$root/boot/loader"

  for entry in $(ls loader/entries); do
    sed "s|%ARCHISO_LABEL%|${iso_label}|g" \
      "loader/entries/$entry" | sudo tee "$entries/$entry"
  done
}

# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
make_efiboot_image () {
  local tmp=$(mktemp -d)
  truncate -s 900M "$tmp/efiboot.img"
  mkfs.fat -n "$iso_label" "$tmp/efiboot.img"

  local efiboot="$tmp/efiboot"
  mkdir -p "$efiboot"
  sudo mount "$tmp/efiboot.img" "$efiboot"

  sudo mkdir -p "$efiboot/EFI"
  sudo cp -v "$root"/boot/{archiso.img,intel-ucode.img,vmlinuz-linux} "$efiboot"

  sudo cp -rv "$root/boot/EFI/boot" "$efiboot/EFI"
  sudo cp -rv "$root/boot/loader" "$efiboot"

  sudo mkdir -p "$efiboot/arch/x86_64"
  sudo cp build/rootfs.sfs "$efiboot/arch/x86_64/airootfs.sfs"

  sudo umount -d "$efiboot"
  mkdir -p build/EFI
  sudo cp "$tmp/efiboot.img" "build/EFI"
}

make_iso () {
  local args
  # add an EFI "El Torito" boot image (FAT filesystem) to ISO-9660 image.
  args="-eltorito-alt-boot
        -e efiboot.img
        -no-emul-boot
        -eltorito-alt-boot
        -efi-boot-part --efi-boot-image"

  sudo xorriso -as mkisofs \
      -iso-level 3 \
      -full-iso9660-filenames \
      -volid "ISO-${iso_label}" \
      -appid "${iso_application}" \
      -publisher "${iso_publisher}" \
      -preparer "prepared by ssb-rootfs" \
      ${args} \
      -boot-load-size 4 \
      -boot-info-table \
      -output "${iso_label}.iso" \
      "build/EFI"
}

#ssb-pacman bootstrap "$root"
#install_packages
make_initcpio
make_efi

sudo chown -R root:root "$root"
mkdir -p build
sudo mksquashfs "$root" "build/rootfs.sfs" -noappend -comp xz
make_efiboot_image
make_iso
