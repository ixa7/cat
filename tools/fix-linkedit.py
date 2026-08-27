#!/usr/bin/env python3
"""
Agrandit le segment __LINKEDIT des binaires Mach-O d'un .app avant signature.

Pourquoi : Xcode laisse très peu de marge entre `filesize` et `vmsize` du
segment __LINKEDIT. Les outils de sideload (Sideloader, certaines versions de
zsign) y ajoutent la signature en mettant à jour `filesize` mais PAS `vmsize`.
dyld refuse alors de charger l'app :

    DYLD: segment '__LINKEDIT' filesize exceeds vmsize

On réserve donc la place à l'avance. __LINKEDIT étant toujours le dernier
segment, augmenter sa taille mémoire est sans effet de bord.

Usage : fix-linkedit.py <chemin .app ou binaire> [...]
"""
import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC, FAT_CIGAM = 0xCAFEBABE, 0xBEBAFECA
LC_SEGMENT_64 = 0x19
PAGE = 0x4000          # iOS arm64 : pages de 16 Ko
HEADROOM = 6 * PAGE    # 96 Ko de marge, largement au-dessus d'une signature


def slice_offsets(data: bytes) -> list[int]:
    """Décalages des architectures (binaire simple ou universel)."""
    if len(data) < 8:
        return []
    magic = struct.unpack(">I", data[:4])[0]
    if magic in (FAT_MAGIC, FAT_CIGAM):
        count = struct.unpack(">I", data[4:8])[0]
        return [struct.unpack(">I", data[8 + i * 20 + 8: 8 + i * 20 + 12])[0]
                for i in range(count)]
    return [0]


def patch_file(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    changed = False

    for base in slice_offsets(bytes(data)):
        if base + 32 > len(data):
            continue
        if struct.unpack_from("<I", data, base)[0] != MH_MAGIC_64:
            continue
        ncmds = struct.unpack_from("<I", data, base + 16)[0]
        off = base + 32
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, off)
            if cmd == LC_SEGMENT_64:
                name = data[off + 8: off + 24].rstrip(b"\0").decode(errors="replace")
                if name == "__LINKEDIT":
                    vmsize, _fileoff, filesize = struct.unpack_from("<QQQ", data, off + 32)
                    needed = ((filesize + HEADROOM + PAGE - 1) // PAGE) * PAGE
                    if needed > vmsize:
                        struct.pack_into("<Q", data, off + 32, needed)
                        print(f"  {path.name}: vmsize {vmsize} -> {needed} "
                              f"(filesize {filesize})")
                        changed = True
            off += cmdsize

    if changed:
        path.write_bytes(bytes(data))
    return changed


def binaries_of(target: Path):
    """Binaire principal d'un .app + ses frameworks embarqués."""
    if target.is_file():
        yield target
        return
    plist = target / "Info.plist"
    name = target.stem
    if plist.is_file():
        try:
            import plistlib
            with plist.open("rb") as fh:
                name = plistlib.load(fh).get("CFBundleExecutable", name)
        except Exception:
            pass
    main = target / name
    if main.is_file():
        yield main
    for fw in sorted(target.glob("Frameworks/*.framework")):
        yield from binaries_of(fw)


def main() -> int:
    targets = [Path(a) for a in sys.argv[1:]]
    if not targets:
        print(__doc__.strip())
        return 2
    total = 0
    for target in targets:
        if not target.exists():
            print(f"introuvable : {target}", file=sys.stderr)
            return 1
        print(f"== {target}")
        for binary in binaries_of(target):
            if patch_file(binary):
                total += 1
    print(f"{total} binaire(s) corrigé(s)." if total else "Aucune correction nécessaire.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
