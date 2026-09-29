# Asset credits

## Generated art — VARCO (model gpt-image-2-medium)

All art was generated in a modern clean pixel style (Eastward / Sea of Stars look) and then reduced to its native pixel size with `art_src/pixelize.py` (downscale, limited palette, hard alpha, 1px outline). The game draws it 1:1 and scales the screen 2x with nearest filtering.

- `art/cities/*.png`: 8 city backgrounds, 640x360.
- `icons/goods/*.png`, `icons/ui/*.png`: cut from one 5x5 icon sheet, 18x18.
- `combat/units/*.png`: 8 unit sprites (about 34px tall), `combat/props/*.png`: 16 props and the truck, `combat/ground/*.png`: 5 battlefield grounds (640x360).
- Originals and sheets: `art_src/modern/` and `art_src/combat/modern/`. Sheets are cut with `art_src/slice_sheet.py`.

## Font — Galmuri (SIL Open Font License 1.1)

`fonts/Galmuri11.ttf`, `fonts/Galmuri11-Bold.ttf` by Lee Minseo (quiple), https://github.com/quiple/galmuri.
License text: `fonts/Galmuri-LICENSE.txt`. Designed for 12px; use sizes that are multiples of 12.

## UI — Kenney Pixel UI Pack (CC0)

`ui/kenney_pixel/` from https://kenney.nl/assets/pixel-ui-pack. `ui/panel*.png` are the grey "Ancient" 9-slice panels scaled 2x (nearest neighbour) and tinted in-game.
