extends Control
## 대화 창 (docs/city_spec.md 4절). 전체 화면 위에 떠서 대화를 진행하고, 끝나면 finished를 내고 사라진다.
## 화면 담당은 start()와 finished만 쓴다. 숫자 키 1~9로 선택지, Enter/Space로 "계속".
## 대화 중 생긴 start_combat 등은 state에 남으므로 finished 뒤에 화면이 처리한다.

signal finished

const PORTRAIT_DIR := "res://assets/portraits/"
## 초상화 원본 48x48을 2배로
const PORTRAIT_SIZE := 96
const DiceRollView := preload("res://scripts/ui/dice_roll_view.gd")
const SUCCESS := Color(0.56, 0.84, 0.5)
const FAILURE := Color(0.95, 0.45, 0.38)

var _state: GameState
var _runner: DialogueRunner
var _portrait_frame: PanelContainer
var _name_label: Label
var _text_label: Label
var _result_box: VBoxContainer
var _choice_box: VBoxContainer
## 지금 눌 수 있는 버튼 (키보드 선택용)
var _buttons: Array = []
var _done := false


func start(state: GameState, dialogue_id: String) -> void:
	_state = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = PixelTheme.build()
	_build()
	_runner = DialogueRunner.new(state, dialogue_id)
	if _runner.is_finished():
		# 대화 파일이 없거나 비었다. 호출한 쪽이 finished를 연결할 틈을 준다.
		_finish.call_deferred()
		return
	_show_node(_runner.current().get("entry_lines", []))


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.045, 0.065, 0.95), PixelTheme.PANEL_BORDER, 2, 16))
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 64
	panel.offset_right = -64
	panel.offset_bottom = -24
	panel.offset_top = -24
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	_portrait_frame = PanelContainer.new()
	_portrait_frame.add_theme_stylebox_override("panel", _box(Color(0.11, 0.1, 0.13), PixelTheme.ACCENT.darkened(0.45), 2, 2))
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait_frame)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	row.add_child(col)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", PixelTheme.font(true))
	_name_label.add_theme_color_override("font_color", PixelTheme.ACCENT)
	col.add_child(_name_label)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_text_label)

	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 4)
	col.add_child(_result_box)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 4)
	col.add_child(_choice_box)


## 지금 노드를 보여 준다. lines: 노드에 들어서며 생긴 효과 (첫 노드용).
func _show_node(lines: Array = []) -> void:
	_clear(_result_box)
	_clear(_choice_box)
	_buttons.clear()
	if _runner.is_finished():
		_finish()
		return
	var cur := _runner.current()
	_set_speaker(cur.speaker, cur.speaker_name)
	_text_label.text = cur.text
	var narrator: bool = cur.speaker == "narrator"
	_text_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM if narrator else PixelTheme.TEXT)
	for line in lines:
		_result_line(line, PixelTheme.ACCENT)

	var choices: Array = cur.choices
	if choices.is_empty():
		_add_button("계속", true, "", _on_choice.bind(0))
		return
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var label := "%d. %s%s" % [i + 1, ch.tags, ch.text]
		if not ch.enabled:
			label += "  (%s)" % ch.blocker
		_add_button(label, ch.enabled, ch.blocker, _on_choice.bind(i))


func _on_choice(index: int) -> void:
	var picked := ""
	var cur := _runner.current()
	if index < cur.get("choices", []).size():
		picked = cur.choices[index].text
	var r := _runner.choose(index)
	var roll: Dictionary = r.get("roll", {})
	if not roll.is_empty():
		# 판정은 주사위 연출로 보여 준다. 끝날 때까지 선택지를 막는다.
		_clear(_choice_box)
		_buttons.clear()
		var dice := DiceRollView.new()
		add_child(dice)
		dice.play(roll)
		await dice.finished
	if r.roll_text == "" and r.effect_lines.is_empty():
		_show_node()
		return
	# 판정과 효과를 보여 주고 "계속"을 기다린다.
	_clear(_result_box)
	_clear(_choice_box)
	_buttons.clear()
	if picked != "":
		_result_line("> " + picked, PixelTheme.TEXT_DIM)
	if not roll.is_empty():
		_result_line("%s 판정 %s  (%d / 난이도 %d)" % [roll.stat_name, "성공" if roll.success else "실패", roll.total, roll.dc],
			SUCCESS if r.success else FAILURE)
	for line in r.effect_lines:
		_result_line(line, PixelTheme.ACCENT)
	_add_button("계속", true, "", _show_node)


func _set_speaker(speaker: String, speaker_name: String) -> void:
	_clear(_portrait_frame)
	var narrator := speaker == "narrator"
	_portrait_frame.visible = not narrator
	_name_label.visible = not narrator and speaker_name != ""
	_name_label.text = speaker_name
	if narrator:
		return
	var path := PORTRAIT_DIR + speaker + ".png"
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
		_portrait_frame.add_child(tex)
	else:
		# 초상화가 없으면 이름 첫 글자를 틀 안에 그린다.
		var initial := Label.new()
		initial.text = speaker_name.left(1) if speaker_name != "" else "?"
		initial.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_override("font", PixelTheme.font(true))
		initial.add_theme_font_size_override("font_size", PixelTheme.SIZE_BODY * 2)
		initial.add_theme_color_override("font_color", PixelTheme.ACCENT)
		_portrait_frame.add_child(initial)


func _result_line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	_result_box.add_child(l)


func _add_button(text: String, enabled: bool, tooltip: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tooltip
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(action)
	_choice_box.add_child(b)
	_buttons.append(b)


func _unhandled_key_input(event: InputEvent) -> void:
	if _done or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	var index := -1
	if key >= KEY_1 and key <= KEY_9:
		index = key - KEY_1
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _buttons.size() == 1:
		index = 0
	if index >= 0 and index < _buttons.size() and not _buttons[index].disabled:
		get_viewport().set_input_as_handled()
		_buttons[index].pressed.emit()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func _box(bg: Color, border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = false
	return sb
