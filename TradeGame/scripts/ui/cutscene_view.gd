extends Control
## 컷신 재생기. 그림 한 장(샷)마다 화면이 천천히 흐르고(팬), 위아래 검은 띠 사이로 자막이 한 줄씩
## 타자기처럼 찍힌다. 데이터는 data/cutscenes/<id>.json:
##   { id, shots: [{ image, from: [x, y], to: [x, y], lines: [...], title, subtitle, flash, tint, choices }] }
## - image: res://assets/art/cutscenes/<image>.png (768x432, 원래 픽셀). 640x360 화면으로 보이는 부분을 from -> to로 옮긴다.
## - bars: false면 위아래 검은 띠를 걷는다 (제목 샷). title, subtitle: 화면 가운데 큰 제목.
## - choices: [{ text, effects }] 마지막 줄 뒤에 고른다. 효과는 EventRunner.apply_effects로 적용한다.
## 클릭/Space/Enter: 타자 중이면 줄을 다 보이고, 아니면 다음 줄. Esc: 컷신 건너뛰기.
## 픽셀 퍼펙트: 그림은 640x360 SubViewport에 1:1로 그리고 정확히 2배로 보여 준다. 팬은 정수 픽셀로만 움직인다.

signal finished

const Kit := preload("res://scripts/ui/ui_kit.gd")
const ART := "res://assets/art/cutscenes/%s.png"
const VIEW := Vector2(640, 360)
const CHARS_PER_SEC := 28.0
## 한 샷에서 줄마다 주는 팬 시간 (줄이 없는 제목 샷은 TITLE_TIME)
const LINE_TIME := 3.2
const TITLE_TIME := 4.5
const BAR_H := 72

var _state: GameState
var _shots: Array = []
var _shot := -1
var _line := 0
var _typing := false
var _chars := 0.0
var _pan_t := 0.0
var _pan_len := 1.0
var _busy := false
var _done := false

var _image: Sprite2D
var _fade: ColorRect
var _flash: ColorRect
var _caption: Label
var _title: Label
var _subtitle: Label
var _choice_box: VBoxContainer
var _hint: Label
var _top_bar: ColorRect
var _bottom_bar: ColorRect


func play(state: GameState, cutscene_id: String) -> void:
	_state = state
	_shots = GameData.cutscenes.get(cutscene_id, {}).get("shots", [])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = PixelTheme.build()
	_build()
	if _shots.is_empty():
		_finish.call_deferred()
		return
	_next_shot()


func _build() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)

	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 2
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	container.add_child(vp)
	_image = Sprite2D.new()
	_image.centered = false
	vp.add_child(_image)

	_flash = _rect(Color(1, 0.95, 0.85, 0.0))
	_fade = _rect(Color(0, 0, 0, 1.0))

	_top_bar = _rect(Color.BLACK)
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_bottom = 0
	_bottom_bar = _rect(Color.BLACK)
	_bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_bar.offset_top = 0
	create_tween().set_parallel().tween_property(_top_bar, "offset_bottom", BAR_H, 0.8)
	create_tween().tween_property(_bottom_bar, "offset_top", -BAR_H * 1.6, 0.8)

	_caption = Kit.label("", PixelTheme.TEXT)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -BAR_H * 1.6 + 14
	_caption.offset_bottom = -12
	_caption.offset_left = 120
	_caption.offset_right = -120
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	_title = Kit.title("", 96)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.offset_top = 150
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.05))
	_title.add_theme_constant_override("outline_size", 12)
	_title.modulate.a = 0.0
	add_child(_title)
	_subtitle = Kit.label("", PixelTheme.TEXT)
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_subtitle.offset_top = 272
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.05))
	_subtitle.add_theme_constant_override("outline_size", 6)
	_subtitle.modulate.a = 0.0
	add_child(_subtitle)

	_choice_box = Kit.vbox(8)
	_choice_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_choice_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choice_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_choice_box.custom_minimum_size = Vector2(520, 0)
	add_child(_choice_box)

	_hint = Kit.label("Space 다음   Esc 건너뛰기", PixelTheme.TEXT_DIM)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hint.offset_left = -400
	_hint.offset_top = 24
	_hint.offset_right = -24
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _shot_data() -> Dictionary:
	return _shots[_shot]


## 검게 닫았다가 다음 그림으로 연다.
func _next_shot() -> void:
	_busy = true
	_caption.text = ""
	var close := create_tween()
	close.tween_property(_fade, "color:a", 1.0, 0.35 if _shot >= 0 else 0.0)
	if _shot >= 0:
		close.parallel().tween_property(_title, "modulate:a", 0.0, 0.3)
		close.parallel().tween_property(_subtitle, "modulate:a", 0.0, 0.3)
	await close.finished
	_shot += 1
	if _shot >= _shots.size():
		_finish()
		return
	var s := _shot_data()
	var tex := Kit.texture_or_null(ART % s.get("image", ""))
	_image.texture = tex
	_image.modulate = Color(s.tint) if s.has("tint") else Color.WHITE
	var lines: Array = s.get("lines", [])
	_pan_len = maxf(TITLE_TIME, LINE_TIME * lines.size())
	_pan_t = 0.0
	_place_image()
	_line = 0
	_title.text = s.get("title", "")
	_subtitle.text = s.get("subtitle", "")
	var open := create_tween()
	open.tween_property(_fade, "color:a", 0.0, 0.9)
	if s.get("flash", false):
		_flash.color.a = 0.85
		create_tween().tween_property(_flash, "color:a", 0.0, 0.6)
	if _title.text != "":
		var t := create_tween()
		t.tween_interval(0.4)
		t.tween_property(_title, "modulate:a", 1.0, 1.4)
		t.tween_property(_subtitle, "modulate:a", 1.0, 1.0)
	# 제목 샷처럼 bars가 false면 검은 띠를 걷어 그림을 다 보인다
	var bars: bool = s.get("bars", true)
	var b := create_tween().set_parallel()
	b.tween_property(_top_bar, "offset_bottom", BAR_H if bars else 0, 0.8)
	b.tween_property(_bottom_bar, "offset_top", -BAR_H * 1.6 if bars else 0, 0.8)
	_busy = false
	if lines.is_empty():
		await open.finished
		if _title.text == "":
			_end_of_shot()
		return
	_start_line()


func _start_line() -> void:
	var lines: Array = _shot_data().get("lines", [])
	_caption.text = lines[_line]
	_caption.visible_characters = 0
	_chars = 0.0
	_typing = true


func _process(delta: float) -> void:
	if _shot < 0 or _shot >= _shots.size():
		return
	_pan_t = minf(_pan_t + delta, _pan_len)
	_place_image()
	if _typing:
		_chars += delta * CHARS_PER_SEC
		_caption.visible_characters = int(_chars)
		if _chars >= _caption.text.length():
			_typing = false
			_caption.visible_characters = -1


## 팬: from에서 to로, 끝으로 갈수록 천천히. 원래 픽셀 단위로만 움직인다.
func _place_image() -> void:
	if _image.texture == null:
		return
	var s := _shot_data()
	var from: Array = s.get("from", [0, 0])
	var to: Array = s.get("to", from)
	var k := _pan_t / _pan_len
	k = 1.0 - (1.0 - k) * (1.0 - k)
	var p := Vector2(from[0], from[1]).lerp(Vector2(to[0], to[1]), k)
	var max_off := _image.texture.get_size() - VIEW
	p = p.clamp(Vector2.ZERO, max_off.max(Vector2.ZERO))
	_image.position = -p.round()


func _advance() -> void:
	if _busy or _done or not _choice_box.get_children().is_empty():
		return
	if _typing:
		_typing = false
		_caption.visible_characters = -1
		return
	var lines: Array = _shot_data().get("lines", [])
	if _line + 1 < lines.size():
		_line += 1
		_start_line()
		return
	_end_of_shot()


## 줄을 다 봤다: 선택지가 있으면 고르게 하고, 없으면 다음 샷.
func _end_of_shot() -> void:
	var choices: Array = _shot_data().get("choices", [])
	if choices.is_empty():
		_next_shot()
		return
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var b := Kit.button("%d. %s" % [i + 1, ch.text], true, _choose.bind(i))
		b.custom_minimum_size = Vector2(520, 48)
		_choice_box.add_child(b)


func _choose(index: int) -> void:
	var ch: Dictionary = _shot_data().get("choices", [])[index]
	if _state != null:
		EventRunner.apply_effects(_state, ch.get("effects", []))
	Kit.clear(_choice_box)
	_next_shot()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if _done or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if key == KEY_ESCAPE:
		_handled()
		_finish()
	elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_handled()
		_advance()
	elif key >= KEY_1 and key <= KEY_9 and _choice_box.get_child_count() > key - KEY_1:
		_handled()
		_choose(key - KEY_1)


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()
