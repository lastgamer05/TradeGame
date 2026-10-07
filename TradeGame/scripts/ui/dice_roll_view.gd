extends Control
## 능력치 판정 연출 (발더스 게이트식). 화면 가운데 난이도(DC)와 보정치를 먼저 보여 주고,
## "굴린다"를 누르면 d20이 굴러가다 멈추고, 보정치를 더해 합계와 성공·실패를 크게 띄운다.
## 판정 자체는 EventRunner.roll_check가 이미 끝낸 값({ d20, stat_name, base, bonus, bonus_name, total, dc, success })이고
## 여기서는 보여 주기만 한다. 클릭이나 Space로 다음 단계, 굴러가는 중에 누르면 바로 결과로 넘어간다.
## 주사위는 120x120 SubViewport에 1:1로 그리고 정확히 2배로 보여 준다 (픽셀 퍼펙트).

signal finished

const Kit := preload("res://scripts/ui/ui_kit.gd")
const DIE_VIEW := 120
const ROLL_TIME := 1.3
const STEP_TIME := 0.45
const SUCCESS := Color(0.56, 0.84, 0.5)
const FAILURE := Color(0.95, 0.45, 0.38)
const GOLD := Color(1.0, 0.82, 0.36)
## 주사위 색: 몸통, 밝은 면, 어두운 면, 테두리
const BODY := Color(0.26, 0.21, 0.36)
const LIGHT := Color(0.38, 0.31, 0.5)
const DARK := Color(0.15, 0.12, 0.21)
const EDGE := Color(1.0, 0.72, 0.32)

var _roll: Dictionary
## "ready" -> "rolling" -> "sum" -> "done"
var _phase := "ready"
var _t := 0.0
var _shown := 1
var _flip := false
var _tick := 0.0
var _die: Node2D
var _die_label: Label
var _mods: VBoxContainer
var _total_label: Label
var _verdict: Label
var _button: Button
var _chance_label: Label
var _step := 0


func play(roll: Dictionary) -> void:
	_roll = roll
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = PixelTheme.build()
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.035, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var col := Kit.vbox(8)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	col.add_child(_center(Kit.title("%s 판정" % _roll.stat_name, 48)))
	var dc := Kit.label("난이도 %d" % _roll.dc, PixelTheme.TEXT)
	dc.add_theme_font_size_override("font_size", 36)
	col.add_child(_center(dc))

	var box := SubViewportContainer.new()
	box.stretch = true
	box.stretch_shrink = 2
	box.custom_minimum_size = Vector2(DIE_VIEW * 2, DIE_VIEW * 2)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(box)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	vp.snap_2d_vertices_to_pixel = true
	box.add_child(vp)
	_die = Node2D.new()
	_die.position = Vector2(DIE_VIEW, DIE_VIEW) / 2.0
	_die.draw.connect(_draw_die)
	vp.add_child(_die)
	_die_label = Label.new()
	_die_label.add_theme_font_override("font", PixelTheme.font(true))
	_die_label.add_theme_font_size_override("font_size", 24)
	_die_label.add_theme_color_override("font_color", PixelTheme.TEXT)
	_die_label.add_theme_color_override("font_outline_color", DARK)
	_die_label.add_theme_constant_override("outline_size", 4)
	_die_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_die_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_die_label.size = Vector2(DIE_VIEW, DIE_VIEW)
	_die_label.text = "20"
	vp.add_child(_die_label)

	_mods = Kit.vbox(2)
	_mods.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_mods)
	_mods.add_child(_center(Kit.label(_mod_text(_roll.stat_name, int(_roll.base)), PixelTheme.TEXT_DIM)))
	if int(_roll.bonus) != 0:
		_mods.add_child(_center(Kit.label(_mod_text("%s (동료)" % _roll.bonus_name, int(_roll.bonus)), PixelTheme.TEXT_DIM)))
	# 굴리기 전에는 성공 확률, 굴린 뒤에는 합계를 같은 자리에 쓴다 (화면이 흔들리지 않게)
	_total_label = Kit.label("성공 확률 %d%%" % _chance(), PixelTheme.TEXT_DIM)
	_total_label.add_theme_font_size_override("font_size", 36)
	_total_label.add_theme_color_override("font_color", PixelTheme.TEXT)
	col.add_child(_center(_total_label))
	_chance_label = _total_label
	_verdict = Label.new()
	_verdict.add_theme_font_override("font", PixelTheme.font(true))
	_verdict.add_theme_font_size_override("font_size", 72)
	_verdict.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	_verdict.add_theme_constant_override("outline_size", 8)
	_verdict.text = " "
	_verdict.modulate.a = 0.0
	col.add_child(_center(_verdict))

	_button = Kit.button("주사위를 굴린다", true, _advance)
	_button.custom_minimum_size = Vector2(320, 48)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_button)


func _center(l: Control) -> Control:
	if l is Label:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _sum_text() -> String:
	var mods := int(_roll.total) - int(_roll.d20)
	return "%d %s %d = %d" % [int(_roll.d20), "+" if mods >= 0 else "-", absi(mods), int(_roll.total)]


func _mod_text(name: String, v: int) -> String:
	return "%s %+d" % [name, v]


## d20 + 보정치 >= DC 가 나올 확률 (%)
func _chance() -> int:
	var need := int(_roll.dc) - int(_roll.base) - int(_roll.bonus)
	return clampi(21 - need, 0, 20) * 5


func _advance() -> void:
	match _phase:
		"ready":
			_phase = "rolling"
			_t = 0.0
			_button.modulate.a = 0.0
			_button.disabled = true
			_total_label.text = " "
		"rolling", "sum":
			_land()
			_show_result()
		"done":
			finished.emit()
			queue_free()


func _process(delta: float) -> void:
	match _phase:
		"rolling":
			_t += delta
			var k := clampf(_t / ROLL_TIME, 0.0, 1.0)
			# 처음엔 빠르게, 끝으로 갈수록 느리게 숫자가 바뀐다
			_tick -= delta
			if _tick <= 0.0:
				_tick = lerpf(0.04, 0.2, k * k)
				_shown = randi_range(1, 20)
				_flip = not _flip
			_die.rotation = (1.0 - k) * (1.0 - k) * 14.0 * PI
			_die.position.y = DIE_VIEW / 2.0 - absf(sin(_t * 9.0)) * 26.0 * (1.0 - k)
			_die_label.text = str(_shown)
			_die_label.position.y = _die.position.y - DIE_VIEW / 2.0
			_die.queue_redraw()
			if k >= 1.0:
				_land()
		"sum":
			_t += delta
			if _t >= STEP_TIME:
				_t = 0.0
				_step += 1
				if _step == 1:
					_total_label.text = _sum_text()
				else:
					_show_result()


## 주사위가 멈춘다: 진짜 눈을 보이고 살짝 튀어 오른다.
func _land() -> void:
	_die.rotation = 0.0
	_die.position.y = DIE_VIEW / 2.0
	_die_label.position.y = 0.0
	_flip = false
	_shown = int(_roll.d20)
	_die_label.text = str(_shown)
	_die.queue_redraw()
	var pop := create_tween()
	_die.scale = Vector2.ONE * 1.25
	pop.tween_property(_die, "scale", Vector2.ONE, 0.18)
	_phase = "sum"
	_t = 0.0
	_step = 0
	for c in _mods.get_children():
		c.add_theme_color_override("font_color", PixelTheme.TEXT)


func _show_result() -> void:
	_phase = "done"
	_total_label.text = _sum_text()
	var ok: bool = _roll.success
	var word := "성공" if ok else "실패"
	if int(_roll.d20) == 20:
		word = "대성공!" if ok else word
	elif int(_roll.d20) == 1 and not ok:
		word = "대실패"
	_verdict.text = word
	_verdict.add_theme_color_override("font_color", SUCCESS if ok else FAILURE)
	_verdict.pivot_offset = _verdict.size / 2.0
	_verdict.scale = Vector2.ONE * 1.6
	_verdict.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_verdict, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_verdict, "modulate:a", 1.0, 0.15)
	_die.queue_redraw()
	_button.text = "계속"
	_button.modulate.a = 1.0
	_button.disabled = false
	if is_inside_tree():
		_button.grab_focus()


## 앞에서 본 이십면체: 바깥 육각형, 가운데 삼각형, 둘을 잇는 모서리.
func _draw_die() -> void:
	var r := 44.0
	var outer: Array[Vector2] = []
	for i in 6:
		var a := -PI / 2.0 + i * PI / 3.0
		outer.append(Vector2(cos(a), sin(a)) * r)
	var inner: Array[Vector2] = []
	var flip := -1.0 if _flip else 1.0
	for i in 3:
		var a := (-PI / 2.0 + i * TAU / 3.0) * flip
		inner.append(Vector2(cos(a), sin(a) * flip) * r * 0.56)
	var edge := EDGE
	var body := BODY
	if _phase == "done" or _phase == "sum":
		if int(_roll.d20) == 20:
			edge = GOLD
		elif _phase == "done":
			edge = SUCCESS if _roll.success else FAILURE
	_die.draw_colored_polygon(PackedVector2Array(outer), body)
	# 바깥 고리의 여섯 면: 위쪽은 밝게, 아래쪽은 어둡게
	for i in 6:
		var a: Vector2 = outer[i]
		var b: Vector2 = outer[(i + 1) % 6]
		var c: Vector2 = _nearest(inner, (a + b) / 2.0)
		var mid := ((a + b) / 2.0).y
		var shade := LIGHT if mid < -r * 0.2 else (DARK if mid > r * 0.2 else BODY)
		_die.draw_colored_polygon(PackedVector2Array([a, b, c]), shade)
	_die.draw_colored_polygon(PackedVector2Array(inner), LIGHT.lightened(0.08))
	for i in 6:
		_die.draw_line(outer[i], outer[(i + 1) % 6], edge, 2.0)
		_die.draw_line(outer[i], _nearest(inner, outer[i]), edge.darkened(0.25), 1.0)
	for i in 3:
		_die.draw_line(inner[i], inner[(i + 1) % 3], edge, 1.0)


static func _nearest(points: Array[Vector2], p: Vector2) -> Vector2:
	var best: Vector2 = points[0]
	for q in points:
		if q.distance_to(p) < best.distance_to(p):
			best = q
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		get_viewport().set_input_as_handled()
		_advance()
