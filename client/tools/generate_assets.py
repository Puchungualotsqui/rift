import struct
import zlib
from pathlib import Path

ICON_SIZE = 24
PIXEL_SCALE = 2
HEIGHT = ICON_SIZE
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "rift_marks.png"
TRANSPARENT = (0, 0, 0, 0)

MARKS = (
    (
        (
            "............",
            "..pp..pp....",
            "..pp..pp....",
            ".pppppppppp.",
            ".phppdpphpp.",
            ".pppppppppp.",
            "...p..p..p..",
            "...p..p..p..",
            "..pppppppp..",
            "..p......p..",
            "..p......p..",
            "............",
        ),
        {"p": (120, 110, 86, 255), "h": (163, 149, 113, 255), "d": (69, 63, 50, 255)},
    ),
    (
        (
            ".....h......",
            ".....p......",
            "....hpp.....",
            "...hppp.....",
            "..hppppp....",
            "..ppppdp....",
            "...ppppp....",
            "....ppp.....",
            ".....pd.....",
            ".....d......",
            "............",
            "............",
        ),
        {"p": (174, 142, 82, 255), "h": (211, 184, 120, 255), "d": (102, 78, 47, 255)},
    ),
    (
        (
            "............",
            "..pppppppp..",
            ".p........p.",
            "p..........p",
            "p..pppppp..p",
            "p..phhhhp..p",
            "p..pddddp..p",
            "p..pppppp..p",
            "p..........p",
            ".p........p.",
            "..pppppppp..",
            "....p..p....",
        ),
        {"p": (104, 130, 120, 255), "h": (153, 170, 150, 255), "d": (57, 78, 71, 255)},
    ),
    (
        (
            "..d.......d.",
            "...d.....d..",
            "....d...d...",
            ".....d.d....",
            "......p.....",
            ".....p......",
            "....p.......",
            "...p........",
            "..p.........",
            ".p..........",
            "p...........",
            "............",
        ),
        {"p": (129, 105, 112, 255), "h": (167, 143, 139, 255), "d": (74, 62, 64, 255)},
    ),
    (
        (
            "............",
            "..pp....pp..",
            ".phpp..phpp.",
            ".pppp..pppp.",
            "...pppppp...",
            "....phpp....",
            "....pppp....",
            "...p....p...",
            "...p....p...",
            "............",
            "............",
            "............",
        ),
        {"p": (133, 145, 102, 255), "h": (169, 177, 126, 255), "d": (74, 83, 57, 255)},
    ),
    (
        (
            "............",
            "....pppp....",
            "...pphhpp...",
            "..pppppppp..",
            ".pppppppppp.",
            ".pp..dd..pp.",
            ".pp..dd..pp.",
            ".pppppppppp.",
            "....pppp....",
            "....pppp....",
            "..pppppppp..",
            "............",
        ),
        {"p": (171, 137, 80, 255), "h": (200, 169, 109, 255), "d": (91, 72, 45, 255)},
    ),
    (
        (
            ".....pp.....",
            ".....pp.....",
            "..pp.pp.pp..",
            "...pppppp...",
            "..pphhhhpp..",
            "...pppppp...",
            "..pp.pp.pp..",
            ".....pp.....",
            ".....pp.....",
            "...pp..pp...",
            "...pp..pp...",
            "............",
        ),
        {"p": (104, 130, 120, 255), "h": (153, 170, 150, 255), "d": (57, 78, 71, 255)},
    ),
    (
        (
            "......p.....",
            ".....ppp....",
            "....ppppp...",
            "...ppphppp..",
            "..ppppppppp.",
            "...pppppp...",
            "....pppp....",
            ".....pp.....",
            "......p.....",
            "............",
            "............",
            "............",
        ),
        {"p": (159, 106, 82, 255), "h": (190, 137, 104, 255), "d": (83, 57, 48, 255)},
    ),
    (
        (
            "....pppp....",
            "...phhhhp...",
            "..pppppppp..",
            "..pp..dd..pp",
            "..pp..dd..pp",
            "..pppppppp..",
            "....pppp....",
            "...pp..pp...",
            "...pp..pp...",
            "..pppppppp..",
            "............",
            "............",
        ),
        {"p": (120, 110, 86, 255), "h": (163, 149, 113, 255), "d": (69, 63, 50, 255)},
    ),
    (
        (
            ".....pp.....",
            ".....pp.....",
            "....phhp....",
            "..pppppppp..",
            ".pp..pp..pp.",
            "....pppp....",
            ".....pp.....",
            "...pp..pp...",
            "...pp..pp...",
            "............",
            "............",
            "............",
        ),
        {"p": (104, 130, 120, 255), "h": (153, 170, 150, 255), "d": (57, 78, 71, 255)},
    ),
)

ICON_COUNT = len(MARKS)
WIDTH = ICON_SIZE * ICON_COUNT


def Chunk(kind, payload):
    checksum = zlib.crc32(kind + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def WritePng(path, pixels):
    rows = bytearray()
    stride = WIDTH * 4
    for y in range(HEIGHT):
        rows.append(0)
        rows.extend(pixels[y * stride:(y + 1) * stride])
    header = struct.pack(">2I5B", WIDTH, HEIGHT, 8, 6, 0, 0, 0)
    data = bytearray(b"\x89PNG\r\n\x1a\n")
    data.extend(Chunk(b"IHDR", header))
    data.extend(Chunk(b"IDAT", zlib.compress(bytes(rows), 9)))
    data.extend(Chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def GenerateMarks():
    pixels = bytearray(bytes(TRANSPARENT) * (WIDTH * HEIGHT))
    for markIndex, (rows, palette) in enumerate(MARKS):
        if len(rows) != 12 or any(len(row) != 12 for row in rows):
            raise ValueError(f"Mark {markIndex} must be a 12 by 12 pixel pattern")
        for y, row in enumerate(rows):
            for x, key in enumerate(row):
                if key == ".":
                    continue
                color = bytes(palette[key])
                for pixelY in range(y * PIXEL_SCALE, y * PIXEL_SCALE + PIXEL_SCALE):
                    for pixelX in range(markIndex * ICON_SIZE + x * PIXEL_SCALE, markIndex * ICON_SIZE + x * PIXEL_SCALE + PIXEL_SCALE):
                        offset = (pixelY * WIDTH + pixelX) * 4
                        pixels[offset:offset + 4] = color
    WritePng(OUTPUT, pixels)
    print(f"Generated {OUTPUT}")


if __name__ == "__main__":
    GenerateMarks()
