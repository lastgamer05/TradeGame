class_name PixelTheme
extends RefCounted
## 픽셀 아트 톤에 맞춘 공용 테마. 갈무리11 폰트(원본 12px)를 정수배 크기로만 쓴다.

const FONT := "res://assets/fonts/Galmuri11.ttf"
const FONT_BOLD := "res://assets/fonts/Galmuri11-Bold.ttf"
const PANEL_TEX := "res://assets/ui/panel.png"
const PANEL_PRESSED_TEX := "res://assets/ui/panel_pressed.png"

## 갈무리11 원본 크기의 배수.
const SIZE_SMALL := 12
const SIZE_BODY := 24

const TEXT := Color(0.9, 0.87, 0.8)
const TEXT_DIM := Color(0.6, 0.57, 0.52)
const ACCENT := Color(1.0, 0.72, 0.32)
const PANEL_BG := Color(0.06, 0.055, 0.075, 0.66)
const PANEL_BORDER := Color(0.36, 0.28, 0.2)


static func font(bold := false) -> FontFile:
	var f: FontFile = load(FONT_BOLD if bold else FONT)
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = SIZE_BODY
	t.set_color("font_color", "Label", TEXT)

	t.set_stylebox("panel", "PanelContainer", panel_box())

	var normal := _button_box(PANEL_TEX, Color(0.42, 0.38, 0.36))
	var hover := _button_box(PANEL_TEX, Color(0.58, 0.5, 0.42))
	var pressed := _button_box(PANEL_PRESSED_TEX, Color(0.5, 0.44, 0.38))
	var disabled := _button_box(PANEL_TEX, Color(0.22, 0.21, 0.22))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.43, 0.42))
	return t


static func panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	sb.anti_aliasing = false
	return sb


static func _button_box(path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.set_texture_margin_all(12)
	sb.modulate_color = tint
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	return sb
