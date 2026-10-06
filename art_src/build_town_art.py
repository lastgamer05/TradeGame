"""도시 거리(걷기 화면)용 그림을 원본에서 게임용으로 만든다.

python art_src/build_town_art.py [streets] [npcs] [player]

- 거리 배경: art_src/modern/towns/<도시 id>.png (1536x864) 에서 가로 띠를 잘라 높이 360으로 줄인다
  -> assets/art/towns/<도시 id>.png (폭 약 850, 64색). 띠 위치는 STREET_CROP.
- NPC 전신: art_src/modern/town_sprites/npcs_<n>.png (4x2 마젠타 시트, 초상화 시트와 같은 순서)
  -> assets/town/npcs/<npc id>.png. 한 시트 안의 키 차이를 살리려고 시트마다 같은 배율로 줄인다
  (가운데 키 인물이 NPC_HEIGHT가 되게). 24색, 1px 외곽선.
- 주인공 걷기 4장과 행인 4명: art_src/modern/town_sprites/player.png (윗줄 걷기, 아랫줄 행인)
  -> assets/town/player_<0~3>.png (같은 크기 틀에 발끝·가운데 맞춤), assets/town/folk/<이름>.png
"""
import os
import statistics
import sys
import tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixelize import pixelize  # noqa: E402
from slice_sheet import slice_sheet  # noqa: E402
from build_city_art import SHEETS  # noqa: E402

ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "TradeGame", "assets")
STREET_SRC = os.path.join(HERE, "modern", "towns")
SPRITE_SRC = os.path.join(HERE, "modern", "town_sprites")

## 원본에서 자를 가로 띠: 도시 id -> (위 y, 높이). 없으면 DEFAULT_CROP.
DEFAULT_CROP = (60, 648)
STREET_CROP = {
    "gate7": (46, 648), "undergrid": (46, 648), "red_mesa": (76, 648), "rustbelt": (16, 648),
    "greenhouse": (26, 648), "swapmeet": (0, 648), "scrapyard": (16, 648),
}
NPC_HEIGHT = 46
PLAYER_HEIGHT = 46
FOLK = ["porter", "old_woman", "kid", "worker"]


def build_streets():
    dst = os.path.join(ASSETS, "art", "towns")
    os.makedirs(dst, exist_ok=True)
    for f in sorted(os.listdir(STREET_SRC)):
        if not f.endswith(".png"):
            continue
        city = f[:-4]
        top, height = STREET_CROP.get(city, DEFAULT_CROP)
        im = Image.open(os.path.join(STREET_SRC, f)).convert("RGBA")
        band = im.crop((0, top, im.width, top + height))
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, f)
            band.save(p)
            print(city, pixelize(p, os.path.join(dst, f), height=360, colors=64))


def _scaled(tmp, names, height, dst_dir, outline=True):
    """잘라 둔 그림들을 같은 배율로 줄인다. 가운데 키가 height가 되게."""
    crops = {n: Image.open(os.path.join(tmp, n + ".png")) for n in names}
    k = height / statistics.median(im.height for im in crops.values())
    os.makedirs(dst_dir, exist_ok=True)
    sizes = {}
    for n, im in crops.items():
        size = (max(1, round(im.width * k)), max(1, round(im.height * k)))
        sizes[n] = pixelize(os.path.join(tmp, n + ".png"), os.path.join(dst_dir, n + ".png"),
                            size=size, colors=24, outline=outline, kmeans=4)
        print(n, sizes[n])
    return sizes


def build_npcs():
    for i, names in enumerate(SHEETS.values(), start=1):
        src = os.path.join(SPRITE_SRC, "npcs_%d.png" % i)
        if not os.path.exists(src):
            continue
        with tempfile.TemporaryDirectory() as tmp:
            slice_sheet(src, tmp, 4, 2, names, {})
            _scaled(tmp, names, NPC_HEIGHT, os.path.join(ASSETS, "town", "npcs"))


def build_player():
    src = os.path.join(SPRITE_SRC, "player.png")
    if not os.path.exists(src):
        return
    walk = ["player_%d" % i for i in range(4)]
    with tempfile.TemporaryDirectory() as tmp:
        slice_sheet(src, tmp, 4, 2, walk + FOLK, {})
        out = os.path.join(tmp, "out")
        _scaled(tmp, walk, PLAYER_HEIGHT, out)
        _scaled(tmp, FOLK, PLAYER_HEIGHT - 2, os.path.join(ASSETS, "town", "folk"))
        # 걷기 그림은 같은 틀에 발끝·가운데를 맞춰야 걸을 때 흔들리지 않는다.
        frames = [Image.open(os.path.join(out, n + ".png")) for n in walk]
        w = max(f.width for f in frames)
        h = max(f.height for f in frames)
        for n, f in zip(walk, frames):
            canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            canvas.paste(f, ((w - f.width) // 2, h - f.height), f)
            canvas.save(os.path.join(ASSETS, "town", n + ".png"))
            print(n, canvas.size)


if __name__ == "__main__":
    parts = sys.argv[1:] or ["streets", "npcs", "player"]
    if "streets" in parts:
        build_streets()
    if "npcs" in parts:
        build_npcs()
    if "player" in parts:
        build_player()
