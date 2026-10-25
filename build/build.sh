#!/bin/bash
# Baut das TV-Retro-Gaming-Image.
# Läuft als root in einem privilegierten debian:trixie-Container:
#   docker run --rm --privileged -v "$PWD:/work" debian:trixie bash /work/build/build.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT="$REPO/out"
WORK=/tmp/retro-build
SUITE=trixie
MIRROR=http://deb.debian.org/debian

ESP_MB=256      # EFI-Systempartition
RETRO_MB=512    # FAT32-Partition "RETRO" (Einstellungen + ROMs, unter Windows sichtbar)
MIN_ROOT_MB=3072

export DEBIAN_FRONTEND=noninteractive
export MTOOLS_SKIP_CHECK=1

echo "==> Build-Werkzeuge installieren"
apt-get update -q
apt-get install -y -q --no-install-recommends \
    mmdebstrap dosfstools mtools e2fsprogs fdisk xz-utils git ca-certificates uuid-runtime

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
rm -f "$OUT"/tv-retro-gaming-*

ROOT_UUID=$(uuidgen)
ESP_ID=$(uuidgen | tr -d '-' | cut -c1-8 | tr 'a-f' 'A-F')
RETRO_ID=$(uuidgen | tr -d '-' | cut -c1-8 | tr 'a-f' 'A-F')
BUILD_ID="$(date -u +%Y%m%d)-${GITHUB_RUN_NUMBER:-lokal}"
ESP_UUID="${ESP_ID:0:4}-${ESP_ID:4:4}"
RETRO_UUID="${RETRO_ID:0:4}-${RETRO_ID:4:4}"

echo "==> Controller-Profile holen"
git clone -q --depth 1 https://github.com/libretro/retroarch-joypad-autoconfig "$WORK/autoconfig"

echo "==> Root-Dateisystem bauen"
packages=$(grep -v '^[[:space:]]*#' "$REPO/build/packages.txt" | xargs | tr ' ' ',')

mmdebstrap \
    --variant=minbase \
    --format=directory \
    --components="main contrib non-free non-free-firmware" \
    --aptopt='APT::Install-Recommends "false"' \
    --include="$packages" \
    --customize-hook="cp -rT --no-preserve=ownership '$REPO/rootfs' \"\$1\"" \
    --customize-hook="mkdir -p \"\$1/usr/local/share/retro-tv/autoconfig\" && cp -r '$WORK/autoconfig/udev' \"\$1/usr/local/share/retro-tv/autoconfig/\"" \
    --customize-hook="cp '$REPO/retro-partition/retro-config.txt' \"\$1/usr/local/share/retro-tv/retro-config.txt\"" \
    --customize-hook="chroot \"\$1\" env ROOT_UUID='$ROOT_UUID' ESP_UUID='$ESP_UUID' RETRO_UUID='$RETRO_UUID' BUILD_ID='$BUILD_ID' /bin/bash -s < '$REPO/build/configure.sh'" \
    "$SUITE" "$WORK/rootfs" "$MIRROR"

R="$WORK/rootfs"

echo "==> Partitionen vorbereiten"
mkdir -p "$WORK/esp" "$WORK/retro"
cp -r "$R/boot/efi/." "$WORK/esp/"
rm -rf "${R:?}/boot/efi/"*

cp -r "$REPO/retro-partition/." "$WORK/retro/"
for d in nes snes gb gbc megadrive mastersystem gamegear; do
    mkdir -p "$WORK/retro/roms/$d"
done
mkdir -p "$WORK/retro/bios"
# Textdateien mit Windows-Zeilenenden, damit sie im Editor sauber aussehen
for f in "$WORK/retro/"*.txt; do sed -i 's/\r$//; s/$/\r/' "$f"; done

used_mb=$(du -sm "$R" | cut -f1)
ROOT_MB=$(( used_mb * 13 / 10 + 512 ))
[ "$ROOT_MB" -lt "$MIN_ROOT_MB" ] && ROOT_MB=$MIN_ROOT_MB
echo "    Root-Dateisystem: ${used_mb} MB belegt, Partition ${ROOT_MB} MB"

mkfs.ext4 -q -F -L RETRO_ROOT -U "$ROOT_UUID" -E root_owner=0:0 -d "$R" "$WORK/root.img" "${ROOT_MB}M"
mkfs.vfat -C -F 32 -n RETRO_EFI -i "$ESP_ID" "$WORK/esp.img" $((ESP_MB * 1024)) >/dev/null
mcopy -s -i "$WORK/esp.img" "$WORK/esp/"* ::/
mkfs.vfat -C -F 32 -n RETRO -i "$RETRO_ID" "$WORK/retro.img" $((RETRO_MB * 1024)) >/dev/null
mcopy -s -i "$WORK/retro.img" "$WORK/retro/"* ::/

echo "==> Image zusammensetzen"
S=2048  # Sektoren pro MiB
P1=$S
P2=$(( P1 + ESP_MB * S ))
P3=$(( P2 + RETRO_MB * S ))
IMG="$OUT/tv-retro-gaming-$BUILD_ID.img"
truncate -s $(( (P3 + ROOT_MB * S + S) * 512 )) "$IMG"

sfdisk -q "$IMG" <<EOF
label: gpt
first-lba: 2048
start=$P1, size=$((ESP_MB * S)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
start=$P2, size=$((RETRO_MB * S)), type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="RETRO"
start=$P3, size=$((ROOT_MB * S)), type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name="RETRO_ROOT"
EOF

dd if="$WORK/esp.img"   of="$IMG" bs=1M seek=$((P1 / S)) conv=notrunc,sparse status=none
dd if="$WORK/retro.img" of="$IMG" bs=1M seek=$((P2 / S)) conv=notrunc,sparse status=none
dd if="$WORK/root.img"  of="$IMG" bs=1M seek=$((P3 / S)) conv=notrunc,sparse status=none
sfdisk -l "$IMG"

echo "==> Komprimieren"
xz -T0 -6 -k -f "$IMG"
( cd "$OUT" && sha256sum "$(basename "$IMG").xz" > "$(basename "$IMG").xz.sha256" )

cat > "$OUT/release-notes.md" <<EOF
TV Retro Gaming, Build $BUILD_ID (Debian $SUITE, Kernel $(ls "$R/lib/modules"))

**Installation:** \`.img.xz\` herunterladen und mit balenaEtcher oder Rufus (DD-Modus) auf einen USB-Stick schreiben. Danach siehe README.

Größe entpackt: $(( $(stat -c %s "$IMG") / 1024 / 1024 )) MB
EOF

rm -rf "$WORK"
ls -lh "$OUT"
echo "==> Fertig: $IMG.xz"
