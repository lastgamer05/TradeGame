# Asset credits

## Generated art — VARCO (model gpt-image-2-medium)

All art was generated in a modern clean pixel style (Eastward / Sea of Stars look) and then reduced to its native pixel size with `art_src/pixelize.py` (downscale, limited palette, hard alpha, 1px outline). The game draws it 1:1 and scales the screen 2x with nearest filtering.

- `art/cities/*.png`: 8 city backgrounds, 640x360.
- `art/locations/*.png`: 32 location backgrounds for city exploration (one per location id in `data/locations.json`), 640x360, 64 colors. Originals: `art_src/modern/locations/`.
- `portraits/*.png`: 32 NPC portraits (one per NPC id in `data/npcs.json`), 48x48 with a 1px outline, 24 colors. Cut from four 4x2 magenta sheets in `art_src/modern/portraits/` (`sheet_1` Helios + Gate 7, `sheet_2` Undergrid + Red Mesa, `sheet_3` Rustbelt + Greenhouse, `sheet_4` Swapmeet + Scrapyard). Rebuild both with `python art_src/build_city_art.py`.
- `icons/goods/*.png`, `icons/ui/*.png`: cut from one 5x5 icon sheet, 18x18.
- `art/towns/*.png`: 8 side-view town streets for walking (height 360, about 850 wide, 64 colors), cut from a horizontal band of 1536x864 originals in `art_src/modern/towns/`.
- `town/npcs/*.png`: 32 full-body NPC sprites (about 48px tall, 24 colors, 1px outline) from four 4x2 magenta sheets in `art_src/modern/town_sprites/` (same order as the portrait sheets, portraits used as references). `town/player_0~3.png`: courier walk cycle, `town/folk/*.png`: 4 passers-by (`town_sprites/player.png`). Rebuild with `python art_src/build_town_art.py`.
- `combat/units/*.png`: 8 unit sprites (about 34px tall), `combat/props/*.png`: 16 props and the truck, `combat/ground/*.png`: 5 battlefield grounds (640x360).
- Originals and sheets: `art_src/modern/` and `art_src/combat/modern/`. Sheets are cut with `art_src/slice_sheet.py`.

## Font — Galmuri (SIL Open Font License 1.1)

`fonts/Galmuri11.ttf`, `fonts/Galmuri11-Bold.ttf` by Lee Minseo (quiple), https://github.com/quiple/galmuri.
License text: `fonts/Galmuri-LICENSE.txt`. Designed for 12px; use sizes that are multiples of 12.

## UI — Kenney Pixel UI Pack (CC0)

`ui/kenney_pixel/` from https://kenney.nl/assets/pixel-ui-pack. `ui/panel*.png` are the grey "Ancient" 9-slice panels scaled 2x (nearest neighbour) and tinted in-game.
