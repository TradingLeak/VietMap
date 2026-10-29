#!/usr/bin/env python3
"""Create the original opaque 1024px app icon using only the Python standard library."""
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024


def inside(x, y):
    # An original north arrow, not a third-party logo.
    vertices = [(512, 185), (787, 791), (512, 648), (237, 791)]
    result = False
    j = len(vertices) - 1
    for i, (xi, yi) in enumerate(vertices):
        xj, yj = vertices[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            result = not result
        j = i
    return result


def pixel(x, y):
    glow = max(0, 1 - math.hypot(x - 510, y - 420) / 750)
    color = [int(9 + glow * 7), int(15 + glow * 10), int(25 + glow * 14)]
    radius = math.hypot(x - 512, y - 512)
    for ring in (245, 364, 478):
        if abs(radius - ring) < 1.2:
            color = [c + 12 for c in color]
    # Supersample the arrow boundary for an antialiased edge.
    coverage = sum(inside(x + dx, y + dy) for dx, dy in ((0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75))) / 4
    arrow = [255, int(65 + (1 - y / SIZE) * 45), int(70 + (1 - y / SIZE) * 35)]
    color = [int(c * (1 - coverage) + a * coverage) for c, a in zip(color, arrow)]
    if math.hypot(x - 512, y - 505) < 30:
        color = [255, 255, 255]
    return bytes(color)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def main():
    scanlines = b"".join(b"\x00" + b"".join(pixel(x, y) for x in range(SIZE)) for y in range(SIZE))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b"")
    path = ROOT / "VietMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(f"{path.relative_to(ROOT)} ({len(png):,} bytes)")


if __name__ == "__main__":
    main()
