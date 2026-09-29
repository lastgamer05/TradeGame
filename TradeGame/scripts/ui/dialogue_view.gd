extends Control
## 대화 창 (docs/city_spec.md 4절). 전체 화면 위에 떠서 대화를 진행하고, 끝나면 finished.
## 틀: 초상화, 판정 결과 표시, 꾸밈은 엔진 담당이 채운다. 화면 담당은 start()와 finished만 쓴다.

signal finished

var _runner: DialogueRunner
var _box: VBoxContainer


func start(state: GameState, dialogue_id: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_runner = DialogueRunner.new(state, dialogue_id)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(140, 380)
	panel.custom_minimum_size = Vector2(1000, 0)
	add_child(panel)
	_box = VBoxContainer.new()
	panel.add_child(_box)
	_show()


func _show() -> void:
	for c in _box.get_children():
		c.queue_free()
	if _runner.is_finished():
		finished.emit()
		queue_free()
		return
	var cur := _runner.current()
	var who := Label.new()
	who.text = cur.speaker_name
	_box.add_child(who)
	var text := Label.new()
	text.text = cur.text
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(960, 0)
	_box.add_child(text)
	for i in cur.choices.size():
		var b := Button.new()
		b.text = cur.choices[i].tags + cur.choices[i].text
		b.disabled = not cur.choices[i].enabled
		b.pressed.connect(func():
			_runner.choose(i)
			_show())
		_box.add_child(b)
