"""컷신 그림을 원본에서 게임용으로 만든다.

python art_src/build_cutscene_art.py

art_src/modern/cutscenes/<이름>.png (1536x864) -> TradeGame/assets/art/cutscenes/<이름>.png (768x432, 64색).
화면(640x360)보다 조금 커서 컷신이 그림을 천천히 훑는다 (data/cutscenes/*.json의 from/to).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixelize import pixelize  # noqa: E402

SRC = os.path.join(HERE, "modern", "cutscenes")
DST = os.path.join(os.path.dirname(HERE), "TradeGame", "assets", "art", "cutscenes")

if __name__ == "__main__":
    os.makedirs(DST, exist_ok=True)
    for f in sorted(os.listdir(SRC)):
        if f.endswith(".png"):
            print(f, pixelize(os.path.join(SRC, f), os.path.join(DST, f), size=(768, 432), colors=64))
