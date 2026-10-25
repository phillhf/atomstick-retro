"""Gemeinsame Systemdefinitionen für retro-playlists und retro-import."""
import glob
import os
import zipfile
from collections import namedtuple

ROM_DIR = "/home/retro/roms"
BIOS_DIR = "/home/retro/bios"
PLAYLIST_DIR = "/home/retro/.config/retroarch/playlists"
UID = GID = 1000
ARCHIVE_EXT = {"zip", "7z"}

# folder: Ordner unter ~/roms, playlist: RetroArch-Systemname (bestimmt die Symbole im Menü)
System = namedtuple("System", "folder playlist core core_name extensions aliases")

SYSTEMS = [
    System("nes", "Nintendo - Nintendo Entertainment System",
           "nestopia_libretro.so", "Nintendo - NES / Famicom (Nestopia UE)",
           ("nes", "fds", "unf", "unif"), ("famicom", "fc", "nintendo")),
    System("snes", "Nintendo - Super Nintendo Entertainment System",
           "snes9x_libretro.so", "Nintendo - SNES / SFC (Snes9x)",
           ("sfc", "smc", "fig", "swc", "bs"), ("sfc", "superfamicom", "supernintendo", "supernes")),
    System("gb", "Nintendo - Game Boy",
           "gambatte_libretro.so", "Nintendo - Game Boy / Color (Gambatte)",
           ("gb",), ("gameboy",)),
    System("gbc", "Nintendo - Game Boy Color",
           "gambatte_libretro.so", "Nintendo - Game Boy / Color (Gambatte)",
           ("gbc", "gb"), ("gameboycolor", "gameboycolour")),
    System("megadrive", "Sega - Mega Drive - Genesis",
           "genesis_plus_gx_libretro.so", "Sega - MS/GG/MD/CD (Genesis Plus GX)",
           ("md", "gen", "smd", "bin", "68k", "sgd"), ("genesis", "md", "segagenesis", "segamegadrive")),
    System("mastersystem", "Sega - Master System - Mark III",
           "genesis_plus_gx_libretro.so", "Sega - MS/GG/MD/CD (Genesis Plus GX)",
           ("sms",), ("sms", "segamastersystem", "markiii")),
    System("gamegear", "Sega - Game Gear",
           "genesis_plus_gx_libretro.so", "Sega - MS/GG/MD/CD (Genesis Plus GX)",
           ("gg",), ("gg", "segagamegear")),
]

# Eindeutige Endungen für das automatische Einsortieren (".bin" ist mehrdeutig und fehlt deshalb)
_GUESS = {
    "nes": "nes", "fds": "nes", "unf": "nes", "unif": "nes",
    "sfc": "snes", "smc": "snes", "fig": "snes", "swc": "snes", "bs": "snes",
    "gb": "gb", "gbc": "gbc",
    "md": "megadrive", "gen": "megadrive", "smd": "megadrive", "68k": "megadrive", "sgd": "megadrive",
    "sms": "mastersystem", "gg": "gamegear",
}


def _norm(name):
    return "".join(c for c in name.lower() if c.isalnum())


def ext_of(filename):
    return os.path.splitext(filename)[1].lower().lstrip(".")


def by_folder_name(name):
    """Ordnet einen Ordnernamen wie "SNES", "Mega Drive" oder "genesis" einem System zu."""
    n = _norm(name)
    for s in SYSTEMS:
        if n == _norm(s.folder) or n in (_norm(a) for a in s.aliases):
            return s
    return None


def by_folder(folder):
    return next(s for s in SYSTEMS if s.folder == folder)


def accepts(system, filename):
    ext = ext_of(filename)
    return ext in system.extensions or ext in ARCHIVE_EXT


def guess_system(path):
    """Errät das System einer einzelnen Datei anhand der Endung (bei ZIP anhand des Inhalts)."""
    ext = ext_of(path)
    if ext == "zip":
        try:
            with zipfile.ZipFile(path) as z:
                for member in z.namelist():
                    if not member.endswith("/") and ext_of(member) in _GUESS:
                        return by_folder(_GUESS[ext_of(member)])
        except (OSError, zipfile.BadZipFile):
            return None
        return None
    folder = _GUESS.get(ext)
    return by_folder(folder) if folder else None


def core_path(system):
    for d in glob.glob("/usr/lib/*/libretro") + ["/usr/lib/libretro"]:
        p = os.path.join(d, system.core)
        if os.path.isfile(p):
            return p
    return None
