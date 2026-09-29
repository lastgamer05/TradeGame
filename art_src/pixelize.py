"""생성 이미지를 게임용 픽셀 아트로 다듬는다.

큰 그림을 목표 픽셀 크기로 줄이고, 색 수를 제한하고, 반투명 가장자리를 없애고,
필요하면 1픽셀 외곽선을 두른다. 게임은 이 결과를 1:1로 그린 뒤 화면 전체를 정수배 확대한다.

python art_src/pixelize.py <입력.png> <출력.png> (--height N | --width N | --size WxH) [--colors N] [--outline]
"""
import argparse
from PIL import Image

OUTLINE = (24, 18, 28, 255)


def pixelize(src, dst, height=None, width=None, size=None, colors=24, outline=False, kmeans=0):
    """kmeans > 0: 색 줄이기 뒤에 k-평균으로 팔레트를 다듬는다. 초상화처럼 작은 그림에서
    눈빛·문신 같은 작은 강조색이 사라지지 않게 한다. 0이면 예전과 같다."""
    im = Image.open(src).convert("RGBA")
    if size:
        target = size
    elif height:
        target = (max(1, round(im.width * height / im.height)), height)
    else:
        target = (width, max(1, round(im.height * width / im.width)))
    small = im.resize(target, Image.LANCZOS)
    alpha = small.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    rgb = small.convert("RGB")
    q = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, kmeans=kmeans, dither=Image.Dither.NONE).convert("RGB")
    out = q.convert("RGBA")
    out.putalpha(alpha)
    if outline:
        w, h = out.size
        padded = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
        padded.paste(out, (1, 1))
        src_px = padded.copy().load()
        px = padded.load()
        for y in range(h + 2):
            for x in range(w + 2):
                if src_px[x, y][3] != 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w + 2 and 0 <= ny < h + 2 and src_px[nx, ny][3] != 0:
                        px[x, y] = OUTLINE
                        break
        out = padded
    out.save(dst)
    return out.size


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--height", type=int)
    ap.add_argument("--width", type=int)
    ap.add_argument("--size")
    ap.add_argument("--colors", type=int, default=24)
    ap.add_argument("--outline", action="store_true")
    ap.add_argument("--kmeans", type=int, default=0)
    a = ap.parse_args()
    size = tuple(int(v) for v in a.size.split("x")) if a.size else None
    print(pixelize(a.src, a.dst, a.height, a.width, size, a.colors, a.outline, a.kmeans))
