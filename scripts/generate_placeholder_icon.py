#!/usr/bin/env python3
"""플레이스홀더 앱 아이콘 생성기.

TODO(ASSET): 정식 앱 아이콘 (1024×1024 PNG, 마스터 1장).
실제 아이콘이 준비되면 scripts/app_icon_placeholder_1024.png를 교체하고
아래 배포 명령(README 참조)만 다시 실행하면 된다.

게임의 아이소메트릭 타일을 모티프로 순수 파이썬(stdlib)으로 그린다:
초록 그라데이션 배경 + 주황 타일 블록 + 검은 매장 블록 + 회색 주차 타일.

사용법:
  python3 scripts/generate_placeholder_icon.py
  # → scripts/app_icon_placeholder_1024.png 생성
  # 이후 sips로 각 플랫폼 아이콘 세트에 리사이즈 배포(README/PROGRESS 참조)
"""

import struct
import zlib
from pathlib import Path

SIZE = 1024


def lerp(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def render():
    top_bg = (0x8E, 0xB0, 0x6E)
    bottom_bg = (0x5C, 0x77, 0x47)
    px = [[lerp(top_bg, bottom_bg, y / SIZE) for _ in range(SIZE)]
          for y in range(SIZE)]

    def fill_diamond(cx, cy, a, b, color):
        for y in range(max(0, cy - b), min(SIZE, cy + b + 1)):
            dy = abs(y - cy) / b
            if dy > 1:
                continue
            half = int(a * (1 - dy))
            for x in range(max(0, cx - half), min(SIZE, cx + half + 1)):
                px[y][x] = color

    def fill_block(cx, cy, a, b, h, top, left, right):
        # 아이소메트릭 블록: 아래쪽 측면(좌/우) 먼저, 그 위에 윗면 마름모.
        for x in range(max(0, cx - a), min(SIZE, cx + a + 1)):
            dx = abs(x - cx) / a
            edge_y = cy + b * (1 - dx)
            for y in range(int(edge_y), min(SIZE, int(edge_y + h) + 1)):
                if 0 <= y < SIZE:
                    px[y][x] = left if x < cx else right
        fill_diamond(cx, cy, a, b, top)

    # 회색 주차 타일(평면)
    fill_diamond(300, 760, 210, 110, (0xA7, 0xA7, 0xA7))
    # 주황 상업 타일 블록
    fill_block(512, 560, 340, 180, 95,
               (0xD9, 0xA9, 0x6C), (0xA8, 0x7B, 0x42), (0xC0, 0x8E, 0x52))
    # 검은 매장 블록(타일 위)
    fill_block(512, 380, 150, 80, 165,
               (0x38, 0x33, 0x2E), (0x17, 0x15, 0x13), (0x26, 0x23, 0x20))
    return px


def write_png(path, px):
    raw = b"".join(
        b"\x00" + bytes(v for pixel in row for v in pixel) for row in px
    )

    def chunk(tag, data):
        payload = tag + data
        return (struct.pack(">I", len(data)) + payload +
                struct.pack(">I", zlib.crc32(payload)))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
           chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


if __name__ == "__main__":
    out = Path(__file__).parent / "app_icon_placeholder_1024.png"
    write_png(out, render())
    print(f"wrote {out}")
