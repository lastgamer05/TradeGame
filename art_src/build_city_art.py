"""도시 탐방용 구역 배경과 NPC 초상화를 원본에서 게임용으로 만든다.

python art_src/build_city_art.py [locations] [portraits]

- 구역 배경: art_src/modern/locations/<구역 id>.png -> assets/art/locations/<구역 id>.png (640x360, 64색)
- 초상화: art_src/modern/portraits/sheet_<n>.png (4x2 마젠타 시트) -> assets/portraits/<npc id>.png
  시트마다 같은 크기의 정사각 틀에 아래·가운데 맞춰 넣어 한 시트 안의 얼굴 크기를 맞추고,
  46x46으로 줄인 뒤 1px 외곽선을 둘러 48x48로 만든다. 24색, k-평균으로 작은 강조색(눈빛, 문신)을 살린다.
"""
import os
import sys
import tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixelize import pixelize  # noqa: E402
from slice_sheet import slice_sheet  # noqa: E402

ROOT = os.path.dirname(HERE)
LOC_SRC = os.path.join(HERE, "modern", "locations")
LOC_DST = os.path.join(ROOT, "TradeGame", "assets", "art", "locations")
POR_SRC = os.path.join(HERE, "modern", "portraits")
POR_DST = os.path.join(ROOT, "TradeGame", "assets", "portraits")

SHEETS = {
    "sheet_1": ["ration_clerk", "aurel_beck", "sergeant_kade", "lina",
                "quartermaster_ro", "mechanic_juno", "cook_bram", "commander_voss"],
    "sheet_2": ["dealer_vex", "nova", "piece", "foreman_dal",
                "ammo_trader_sol", "han", "keeper_wen", "elder_tarr"],
    "sheet_3": ["scrap_trader_pim", "gale", "morae", "crane_mechanic_ivo",
                "produce_trader_mei", "soha", "ian", "farmhand_tuk"],
    "sheet_4": ["bazaar_trader_ada", "meter", "innkeeper_moss", "auctioneer_fin",
                "fence_rook", "crank", "arena_master_gus", "scavenger_nim"],
}


def build_locations():
    os.makedirs(LOC_DST, exist_ok=True)
    for f in sorted(os.listdir(LOC_SRC)):
        if f.endswith(".png"):
            print(f, pixelize(os.path.join(LOC_SRC, f), os.path.join(LOC_DST, f), size=(640, 360), colors=64))


def build_portraits():
    os.makedirs(POR_DST, exist_ok=True)
    for sheet, names in SHEETS.items():
        src = os.path.join(POR_SRC, sheet + ".png")
        if not os.path.exists(src):
            continue
        with tempfile.TemporaryDirectory() as tmp:
            slice_sheet(src, tmp, 4, 2, names, {})
            crops = {n: Image.open(os.path.join(tmp, n + ".png")).convert("RGBA") for n in names}
            side = max(max(im.size) for im in crops.values())
            for n, im in crops.items():
                sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
                sq.paste(im, ((side - im.width) // 2, side - im.height), im)
                padded = os.path.join(tmp, n + "_sq.png")
                sq.save(padded)
                print(n, pixelize(padded, os.path.join(POR_DST, n + ".png"), size=(46, 46), colors=24, outline=True, kmeans=4))


if __name__ == "__main__":
    what = sys.argv[1:] or ["locations", "portraits"]
    if "locations" in what:
        build_locations()
    if "portraits" in what:
        build_portraits()
