# TV Retro Gaming

Ein schlankes, maßgeschneidertes Linux für den **CSL PC on a Stick** (Art. 54988, Intel Atom) und
ähnliche HDMI-Sticks. Nach dem Einschalten startet direkt eine Spieleoberfläche für:

| System | Ordner | Emulator |
|---|---|---|
| Nintendo NES / Famicom | `roms/nes` | Nestopia UE |
| Super Nintendo | `roms/snes` | Snes9x |
| Game Boy | `roms/gb` | Gambatte |
| Game Boy Color | `roms/gbc` | Gambatte |
| Sega Mega Drive / Genesis | `roms/megadrive` | Genesis Plus GX |
| Sega Master System | `roms/mastersystem` | Genesis Plus GX |
| Sega Game Gear | `roms/gamegear` | Genesis Plus GX |

Basis: Debian 13 „trixie“ (64 Bit), RetroArch direkt auf dem Bildschirm (ohne Desktop),
Bootloader für **64- und 32-Bit-UEFI**: Viele Atom-Sticks haben eine 32-Bit-Firmware, die
gängige Linux-Images nicht starten kann.

## 1. Image herunterladen

Unter **Releases** in diesem Repository die neueste Datei `tv-retro-gaming-….img.xz` herunterladen.
Das Image wird bei jeder Änderung automatisch von GitHub Actions gebaut und in QEMU getestet
(64-Bit- und 32-Bit-UEFI).

## 2. Auf einen USB-Stick schreiben

Mit [balenaEtcher](https://etcher.balena.io/) oder [Rufus](https://rufus.ie/) (im **DD-Modus**)
die `.img.xz`-Datei auf einen USB-Stick schreiben (mindestens 8 GB). Dabei wird der Stick gelöscht.

Danach erscheint unter Windows ein Laufwerk **RETRO**:

- `retro-config.txt` mit dem Editor öffnen und **WLAN-Name und -Passwort** eintragen.
- Eigene Spiele in die Ordner unter `roms` legen (siehe Tabelle oben, ZIP geht auch).

Fragt Windows, ob eine Partition formatiert werden soll: **Abbrechen**.

## 3. Vom USB-Stick starten

1. USB-Stick (über einen USB-Hub zusammen mit Tastatur/Controller) an den HDMI-Stick anschließen.
2. Beim Einschalten **F7** (Bootmenü) oder **Entf/F2** (BIOS) drücken.
3. Im BIOS **Secure Boot ausschalten**, falls er eingeschaltet ist.
4. Den USB-Stick als Startmedium wählen.

Im Startmenü gibt es drei Einträge:

- **TV Retro Gaming**: normal starten (direkt vom USB-Stick spielen geht auch)
- **Auf internen Speicher installieren**: kopiert alles auf den internen 32-GB-Speicher.
  Dafür wird eine **Tastatur** gebraucht. Danach den USB-Stick abziehen.
- **Fehlersuche**: Textkonsole statt Spieleoberfläche (Login `retro` / `retro`)

## 4. Bedienung

| Aktion | Controller | Tastatur |
|---|---|---|
| Menü im Spiel öffnen | **Start + Select** (oder Home-Taste) | F1 |
| Bestätigen / Zurück | A / B | X / Z |
| Gerät ausschalten | Hauptmenü → „RetroArch beenden“ | |

Spielstände (Batteriespeicher) werden alle 10 Sekunden gesichert. Speicherstände legst du im Menü an.

### Controller

- **USB-Controller**: einstecken, fertig. Die meisten Modelle werden automatisch erkannt.
- **Bluetooth-Controller** (8BitDo, PS4/PS5, Xbox, Switch Pro …): Controller in den
  Kopplungsmodus versetzen und den Stick (neu) starten. In den ersten 2 Minuten nach dem Start
  wird er automatisch gekoppelt. Danach verbindet er sich beim Einschalten von selbst.

## 5. Weitere Spiele hinzufügen

**Über das WLAN:** Im Windows-Explorer `\\retro-tv` eingeben, Benutzer `retro`,
Passwort `retro` (bzw. `SHARE_PASSWORD` aus der `retro-config.txt`).

| Freigabe | Inhalt |
|---|---|
| `roms` | Spiele, ein Unterordner je System |
| `spielstaende` | Batteriespeicher, zum Sichern |
| `bios` | optionale BIOS-Dateien (z. B. `disksys.rom` für Famicom Disk System) |
| `einstellungen` | `retro-config.txt` |

**Per USB-Stick:** Auf einem beliebigen USB-Stick einen Ordner `roms` anlegen, darin die Unterordner
wie oben (oder die Dateien einfach direkt in `roms`, sie werden anhand der Endung einsortiert).
Stick einstecken, ein paar Sekunden warten. Nichts wird vom Stick gelöscht.

Neue Spiele erscheinen automatisch im Menü. Kommt ein ganz neues System dazu, startet die
Oberfläche kurz neu (nur wenn gerade kein Spiel läuft).

Bitte nur Sicherungskopien von Spielen verwenden, die du selbst besitzt.

## 6. Einstellungen (`retro-config.txt`)

| Einstellung | Bedeutung |
|---|---|
| `WIFI_SSID`, `WIFI_PASSWORD` | WLAN-Zugang |
| `WIFI_COUNTRY` | Land für die Funkregeln, Standard `DE` |
| `HOSTNAME` | Name im Netzwerk, Standard `retro-tv` |
| `SHARE_PASSWORD` | Passwort für Freigabe und SSH |
| `RESOLUTION` | `1080p` (Standard), `720p` oder `auto`. Bei 4K-Fernsehern 1080p lassen. |
| `AUDIO_DEVICE` | `auto` oder z. B. `hw:0,3`, falls kein Ton kommt |
| `BLUETOOTH_AUTOPAIR` | `ja`/`nein` |
| `SSH` | `ja`/`nein`, Wartungszugang |

## Hardware-Hinweise

- Getestet wird automatisch nur in QEMU. Auf echter Hardware hängt WLAN/Bluetooth vom verbauten Chip ab:
  Realtek RTL8723BS (in vielen Atom-Sticks) wird unterstützt. Broadcom-SDIO-Chips (AP6xxx)
  brauchen oft eine gerätespezifische Datei und funktionieren eventuell nicht. Dann hilft ein
  kleiner USB-WLAN-Adapter oder ein USB-LAN-Adapter.
- Der Kernelparameter `intel_idle.max_cstate=1` verhindert die bekannten Hänger von Bay-Trail-CPUs.
- Netzteil: 5 V / 3 A. Mit schwächeren Netzteilen gibt es Abstürze.

## Aufbau des Projekts

```
.github/workflows/build.yml   GitHub Actions: Image bauen, in QEMU testen, Release erstellen
build/build.sh                Baut das Image (mmdebstrap, ohne Loop-Devices)
build/configure.sh            Systemeinrichtung im chroot
build/packages.txt            Paketliste
build/test-qemu.sh            Starttest mit 64- und 32-Bit-UEFI
rootfs/                       Dateien, die ins System kopiert werden
  etc/systemd/system/         Dienste (RetroArch, Einstellungen, Import, Installer …)
  usr/local/bin, sbin/        Skripte (retro-*)
  usr/local/share/retro-tv/   RetroArch- und GRUB-Vorlagen
retro-partition/              Inhalt des Windows-Laufwerks RETRO
```

Partitionen auf dem Stick: `EFI` (256 MB, Bootloader), `RETRO` (512 MB FAT32, Einstellungen und
ROM-Übergabe), `RETRO_ROOT` (ext4, System + Spiele, wird beim ersten Start auf den ganzen Speicher
vergrößert).

Lokal bauen geht auf jedem Linux mit Docker:

```bash
docker run --rm --privileged -v "$PWD:/work" debian:trixie bash /work/build/build.sh
```
