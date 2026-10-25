#!/bin/bash
# Richtet das Root-Dateisystem ein. Läuft per chroot innerhalb von mmdebstrap.
# Erwartet ROOT_UUID, ESP_UUID, RETRO_UUID und BUILD_ID als Umgebungsvariablen.
set -euo pipefail
: "${ROOT_UUID:?}" "${ESP_UUID:?}" "${RETRO_UUID:?}" "${BUILD_ID:?}"

echo "==> [chroot] Skripte und Rechte"
chmod 755 /usr/local/bin/retro-* /usr/local/sbin/retro-*
chown -R root:root /etc/systemd/system /etc/udev/rules.d /etc/samba /usr/local
mkdir -p /etc/retro-tv /var/lib/retro-tv
echo "$BUILD_ID" > /etc/retro-tv/version

echo "==> [chroot] Benutzer retro"
groups=""
for g in video input audio render plugdev netdev bluetooth sudo; do
    getent group "$g" >/dev/null && groups="${groups:+$groups,}$g"
done
useradd -m -u 1000 -U -s /bin/bash -G "$groups" retro
echo 'retro:retro' | chpasswd
passwd -l root >/dev/null
printf 'retro\nretro\n' | smbpasswd -s -a retro >/dev/null
printf 'retro' | sha256sum | cut -d' ' -f1 > /var/lib/retro-tv/share-password.sha256

install -d -o retro -g retro /home/retro/roms /home/retro/saves /home/retro/states \
    /home/retro/bios /home/retro/screenshots /home/retro/.config/retroarch/playlists
for d in nes snes gb gbc megadrive mastersystem gamegear; do
    install -d -o retro -g retro "/home/retro/roms/$d"
done
install -o retro -g retro -m 644 /usr/local/share/retro-tv/retroarch.cfg /home/retro/.config/retroarch/retroarch.cfg

echo "==> [chroot] System"
cat > /etc/fstab <<EOF
# <Gerät>             <Einhängepunkt> <Typ> <Optionen>                                    <dump> <pass>
UUID=$ROOT_UUID  /           ext4  defaults,noatime,commit=60                    0 1
UUID=$ESP_UUID   /boot/efi   vfat  umask=0077,nofail                             0 2
UUID=$RETRO_UUID /boot/retro vfat  uid=1000,gid=1000,umask=0022,flush,nofail     0 2
EOF
mkdir -p /boot/efi /boot/retro

echo retro-tv > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo Europe/Berlin > /etc/timezone
echo 'LANG=C.UTF-8' > /etc/default/locale

# Kernel-Links für GRUB prüfen
if [ ! -e /vmlinuz ] || [ ! -e /initrd.img ]; then
    k=$(ls /boot/vmlinuz-* | sort -V | tail -n1)
    ln -sf "${k#/}" /vmlinuz
    ln -sf "boot/initrd.img-${k#/boot/vmlinuz-}" /initrd.img
fi

echo "==> [chroot] Dienste"
systemctl enable \
    retroarch.service retro-config.service retro-firstboot.service retro-boot-import.service \
    retro-roms-watch.service retro-bt-autopair.service retro-installer.service retro-ci-report.service \
    NetworkManager.service bluetooth.service smbd.service nmbd.service avahi-daemon.service wsdd2.service
systemctl disable ssh.service ssh.socket apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl mask systemd-firstboot.service

# Jedes Gerät bekommt beim ersten Start eigene Schlüssel und eine eigene Machine-ID
rm -f /etc/ssh/ssh_host_*
rm -f /var/lib/dbus/machine-id
: > /etc/machine-id

echo "==> [chroot] Bootloader"
/usr/local/sbin/retro-mkgrub / "$ROOT_UUID" live

echo "==> [chroot] Kontrolle"
ls -l /usr/lib/x86_64-linux-gnu/libretro/
for core in nestopia snes9x gambatte genesis_plus_gx; do
    test -f "/usr/lib/x86_64-linux-gnu/libretro/${core}_libretro.so" || { echo "Core fehlt: $core"; exit 1; }
done
test -d /usr/share/libretro/assets || echo "WARNUNG: /usr/share/libretro/assets fehlt"
ls /boot /boot/efi/EFI/BOOT

apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /tmp/* /var/log/*.log
