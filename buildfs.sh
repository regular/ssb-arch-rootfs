#!/usr/bin/bash
set -eux -o pipefail

export ssb_appname=ssb-pacman
root=root
bin="$HOME/.ssb-pacman/node_modules/ssb-pacman/bin"
archisodir=$(mktemp -d)

source ./config

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
  pkgs="\
    base \
    haveged \
    intel-ucode \
    memtest86+ \
    mkinitcpio-nfs-utils \
    nbd \
    zsh \
  "
  pkgs+=" efitools"
  #pkgs+=" syslinux"

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

make_efi() {
  local efitools="$root/usr/share/efitools"
  local EFI="$root/boot/EFI"
  mkdir -p "$EFI/boot"
  cp "$efitools/efi/PreLoader.efi" "$EFI/boot/bootx64.efi"
  cp "$efitools/efi/HashTool.efi" "$EFI/boot/"
  cp "$root/usr/lib/systemd/boot/efi/systemd-bootx64.efi" \
    "$EFI/boot/loader.efi"

  local entries="$root/boot/loader/entries"
  mkdir -p "$entries"

  cp loader/loader.conf "$root/boot/loader"

  for entry in $(ls loader/entries); do
    sed "s|%ARCHISO_LABEL%|${iso_label}|g" \
      "loader/entries/$entry" > "$entries/$entry"
  done

  # cp ${script_path}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf iso/loader/entries/
  # cp ${script_path}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf iso/loader/entries/
  # EFI Shell 2.0 for UEFI 2.3+
  # curl -o ${work_dir}/iso/EFI/shellx64_v2.efi https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/X    64/Shell.efi
  # EFI Shell 1.0 for non UEFI 2.3+
  # curl -o ${work_dir}/iso/EFI/shellx64_v1.efi https://raw.githubusercontent.com/tianocore/edk2/master/EdkShellBinPkg/FullShel    l/X64/Shell_Full.efi
}

# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
make_efiboot_image () {
  local tmp=$(mktemp -d)
  truncate -s 64M "$tmp/efiboot.img"
  mkfs.fat -n ARCHISO_EFI "$tmp/efiboot.img"

  local efiboot="$tmp/efiboot"
  mkdir -p "$efiboot"
  sudo mount "$tmp/efiboot.img" "$efiboot"

  sudo mkdir -p "$efiboot/EFI"
  sudo cp -v "$root"/boot/{archiso.img,intel-ucode.img,vmlinuz-linux} "$efiboot"

  sudo cp -rv "$root/boot/EFI/boot" "$efiboot/EFI"
  sudo cp -rv "$root/boot/loader" "$efiboot"

# cp iso/EFI/shellx64_v2.efi efiboot/EFI/
# cp iso/EFI/shellx64_v1.efi efiboot/EFI/

  sudo umount -d "$efiboot"
  
  cp "$tmp/efiboot.img" "$root/boot/EFI/"
}


#ssb-pacman bootstrap "$root"
#install_packages
#extract_archiso_script
#make_initcpio
make_efi
make_efiboot_image

sudo chown -R root:root "$root"
sudo mksquashfs "$root" "build/rootfs.sfs" -noappend -comp xz
