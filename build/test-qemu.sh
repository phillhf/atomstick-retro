#!/bin/bash
# Startet das fertige Image in QEMU vom virtuellen USB-Stick und prüft, ob RetroArch läuft.
# Aufruf (als root in debian:trixie): test-qemu.sh x64|ia32
#   x64  = 64-Bit-UEFI
#   ia32 = 32-Bit-UEFI mit 64-Bit-CPU, wie bei vielen Atom-Sticks (Bay Trail)
set -euo pipefail

ARCH=${1:-x64}
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT="$REPO/out"
T=/tmp/retro-test-$ARCH
RESULT="$OUT/test-$ARCH"
TIMEOUT=900

export DEBIAN_FRONTEND=noninteractive MTOOLS_SKIP_CHECK=1
apt-get update -q
apt-get install -y -q --no-install-recommends qemu-system-x86 ovmf ovmf-ia32 e2fsprogs fdisk mtools socat

case "$ARCH" in
    x64)  CODE=/usr/share/OVMF/OVMF_CODE_4M.fd;   VARS=/usr/share/OVMF/OVMF_VARS_4M.fd ;;
    ia32) CODE=/usr/share/OVMF/OVMF32_CODE_4M.fd; VARS=/usr/share/OVMF/OVMF32_VARS_4M.fd ;;
    *) echo "Unbekannt: $ARCH"; exit 1 ;;
esac

rm -rf "$T" "$RESULT"
mkdir -p "$T" "$RESULT"
IMG=$(ls "$OUT"/tv-retro-gaming-*.img | head -n1)
cp --sparse=always "$IMG" "$T/disk.img"
cp "$VARS" "$T/vars.fd"

part_start() { sfdisk -d "$T/disk.img" | sed -n "s/.*start= *\([0-9]*\),.*name=\"$1\".*/\1/p"; }
part_size()  { sfdisk -d "$T/disk.img" | sed -n "s/.*size= *\([0-9]*\),.*name=\"$1\".*/\1/p"; }

echo "==> Testmarkierung ins Root-Dateisystem schreiben"
rs=$(part_start RETRO_ROOT); rz=$(part_size RETRO_ROOT)
dd if="$T/disk.img" of="$T/root.img" bs=1M skip=$((rs / 2048)) count=$((rz / 2048)) conv=sparse status=none
echo ci > "$T/ci-test"
debugfs -w -R "write $T/ci-test /etc/retro-tv/ci-test" "$T/root.img"
dd if="$T/root.img" of="$T/disk.img" bs=1M seek=$((rs / 2048)) conv=notrunc,sparse status=none
rm "$T/root.img"

echo "==> Test-ROM auf die RETRO-Partition legen (prüft Import und Spieleliste)"
printf 'NES\x1a\x02\x01' > "$T/Testspiel.nes"
head -c 40960 /dev/zero >> "$T/Testspiel.nes"
mcopy -i "$T/disk.img@@$(( $(part_start RETRO) * 512 ))" "$T/Testspiel.nes" ::/roms/nes/

# Stick größer als das Image, damit die Vergrößerung beim ersten Start mitgetestet wird
truncate -s +1G "$T/disk.img"

ACCEL=(-accel tcg -cpu max)
[ -w /dev/kvm ] && ACCEL=(-accel kvm -cpu host)
echo "==> QEMU starten ($ARCH, ${ACCEL[1]})"
qemu-system-x86_64 -machine q35 -m 2048 -smp 2 "${ACCEL[@]}" \
    -drive if=pflash,format=raw,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,file="$T/vars.fd" \
    -device qemu-xhci \
    -drive if=none,id=stick,format=raw,file="$T/disk.img" \
    -device usb-storage,drive=stick,removable=on \
    -device usb-kbd \
    -vga std -display none \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -audiodev none,id=snd0 -device intel-hda -device hda-output,audiodev=snd0 \
    -serial file:"$T/serial.log" \
    -monitor unix:"$T/monitor.sock",server,nowait \
    -daemonize -pidfile "$T/qemu.pid"

monitor() { echo "$1" | socat - UNIX-CONNECT:"$T/monitor.sock" >/dev/null; }

end=$((SECONDS + TIMEOUT))
until grep -q RETROTV-CI-DONE "$T/serial.log" 2>/dev/null; do
    if [ $SECONDS -ge $end ]; then
        echo "Zeitüberschreitung nach $TIMEOUT s"
        break
    fi
    sleep 10
done

monitor "screendump $RESULT/bildschirm.png -f png" || true
sleep 2
monitor quit || true
cp "$T/serial.log" "$RESULT/serial.log"
cat "$RESULT/serial.log"

ok=true
check() {
    if grep -qE "$1" "$RESULT/serial.log"; then echo "OK      $2"; else echo "FEHLER  $2"; ok=false; fi
}
echo "==> Ergebnis ($ARCH)"
check 'RETROTV-CI-DONE'                                 "System gestartet, Testbericht erhalten"
check '^retroarch=active'                               "RetroArch läuft"
check '^retro-config=active'                            "Einstellungen angewendet"
check '^retro-firstboot=active'                         "Ersteinrichtung gelaufen"
check '^smbd=active'                                    "Netzwerkfreigabe läuft"
check 'Nintendo - Nintendo Entertainment System\.lpl'   "Test-ROM importiert, NES-Spieleliste erzeugt"
[ "$ARCH" = ia32 ] && check '^firmware=32'              "Start über 32-Bit-UEFI"
rm -rf "$T"
$ok
