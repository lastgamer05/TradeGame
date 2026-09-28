# Asset credits

## City illustrations and item icons — generated with VARCO

- `art/cities/*.png`: 8 city backgrounds, generated with VARCO (model gpt-image-2-medium), then resized to 1280x720 and reduced to a 256-color palette.
- `icons/goods/*.png`, `icons/ui/*.png`: cut from one generated 5x5 icon sheet (VARCO, gpt-image-2-medium). Background removed, resized to 96x96.
- Full-resolution originals and the icon sheet are kept outside the Godot project in `art_src/` so they are not exported.

## Font — Galmuri (SIL Open Font License 1.1)

`fonts/Galmuri11.ttf`, `fonts/Galmuri11-Bold.ttf` by Lee Minseo (quiple), https://github.com/quiple/galmuri.
License text: `fonts/Galmuri-LICENSE.txt`. Designed for 12px; use sizes that are multiples of 12.

## UI — Kenney Pixel UI Pack (CC0)

`ui/kenney_pixel/` from https://kenney.nl/assets/pixel-ui-pack. `ui/panel*.png` are the grey "Ancient" 9-slice panels scaled 2x (nearest neighbour) and tinted in-game.
