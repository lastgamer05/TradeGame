extends Control
## 전투 화면. 왼쪽 타일 맵, 오른쪽 유닛 정보·행동 버튼·전투 로그.
## 조작: 내 유닛 클릭 = 선택, 파란 칸 클릭 = 이동, 적 클릭 = 공격.

signal finished(battle: Battle)

const TILE := 32
const BOARD_ORIGIN := Vector2(24, 40)
const RESULT_NAMES := { "victory": "승리", "surrender": "항복을 받아냈다", "escaped": "도주 성공", "wiped": "분대 전멸" }

const COL_FLOOR := Color(0.15, 0.13, 0.13)
const COL_GRID := Color(0, 0, 0, 0.35)
const COL_HALF := Color(0.48, 0.34, 0.2)
const COL_FULL := Color(0.34, 0.35, 0.4)
const COL_BARREL := Color(0.75, 0.25, 0.18)
const COL_ESCAPE := Color(0.3, 0.8, 0.4, 0.18)
const COL_REACH := Color(0.35, 0.6, 1.0, 0.22)
const COL_PLAYER := Color(0.4, 0.85, 0.95)
const COL_ENEMY := Color(0.92, 0.35, 0.3)

var battle: Battle
var selected: Dictionary = {}
var mode := "normal"  # normal, grenade
var hover := Vector2i(-1, -1)

var _board: Control
var _title: Label
var _unit_info: Label
var _hover_info: Label
var _log_label: Label
var _buttons := {}


func setup(b: Battle) -> void:
	battle = b
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_board = Control.new()
	_board.position = BOARD_ORIGIN
	_board.size = Vector2(battle.w, battle.h) * TILE
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	_board.mouse_exited.connect(func(): hover = Vector2i(-1, -1); _refresh())
	add_child(_board)

	var panel := PanelContainer.new()
	panel.position = Vector2(BOARD_ORIGIN.x * 2 + _board.size.x, 16)
	panel.size = Vector2(1280 - panel.position.x - 16, 720 - 32)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_override("font", PixelTheme.font(true))
	_title.add_theme_color_override("font_color", PixelTheme.ACCENT)
	box.add_child(_title)
	_unit_info = Label.new()
	box.add_child(_unit_info)
	_hover_info = Label.new()
	_hover_info.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	box.add_child(_hover_info)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for id in ["hide", "overwatch", "grenade", "board", "surrender", "end_turn"]:
		var btn := Button.new()
		btn.pressed.connect(_on_action.bind(id))
		grid.add_child(btn)
		_buttons[id] = btn

	_log_label = Label.new()
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.clip_text = true
	_log_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	box.add_child(_log_label)

	_select_next()
	_refresh()


# --- 입력 ---

func _on_board_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := Vector2i((ev.position / TILE).floor())
		if c != hover:
			hover = c
			_refresh()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			mode = "normal"
			_refresh()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			_click(Vector2i((ev.position / TILE).floor()))


func _click(c: Vector2i) -> void:
	if battle.result != "" or not battle._in_bounds(c):
		return
	var u := battle.unit_at(c)
	if mode == "grenade":
		if not selected.is_empty() and battle.throw_grenade(selected, c):
			mode = "normal"
			_after_action()
		return
	if not u.is_empty() and u.side == "player":
		selected = u
	elif not u.is_empty() and u.side == "enemy":
		if not selected.is_empty() and battle.attack(selected, u):
			_after_action()
			return
	elif not selected.is_empty() and battle.move(selected, c):
		_after_action()
		return
	_refresh()


func _on_action(id: String) -> void:
	if battle.result != "":
		finished.emit(battle)
		return
	match id:
		"hide":
			battle.hide(selected)
		"overwatch":
			battle.set_overwatch(selected)
		"grenade":
			mode = "normal" if mode == "grenade" else "grenade"
			_refresh()
			return
		"board":
			battle.board(selected)
		"surrender":
			battle.demand_surrender(selected)
		"end_turn":
			battle.end_player_turn()
			_select_next()
			_refresh()
			return
	_after_action()


func _after_action() -> void:
	if selected.is_empty() or not battle.can_act(selected):
		_select_next()
	_refresh()


func _select_next() -> void:
	for u in battle.active_units("player"):
		if u.ap > 0:
			selected = u
			return
	if selected.is_empty() or selected.down or selected.boarded:
		var any := battle.active_units("player")
		selected = any[0] if not any.is_empty() else {}


# --- 표시 ---

func _refresh() -> void:
	_title.text = "%s · %d턴" % [battle.encounter.name, battle.turn]
	if battle.result != "":
		_title.text = "전투 종료: %s" % RESULT_NAMES.get(battle.result, battle.result)
	if selected.is_empty():
		_unit_info.text = ""
	else:
		var wpn: String = battle.cfg.weapons[selected.weapon].name if selected.weapon != "" else "-"
		var state_text := []
		if selected.hidden:
			state_text.append("숨음")
		if selected.overwatch:
			state_text.append("경계")
		_unit_info.text = "%s   체력 %d/%d   행동력 %d\n무기 %s   집중 %d   완력 %d  %s" % [
			selected.name, selected.hp, selected.max_hp, selected.ap, wpn, selected.aim, selected.might,
			" ".join(state_text)]
	_hover_info.text = _hover_text()

	var can := battle.result == "" and not selected.is_empty() and battle.can_act(selected)
	_set_button("hide", "숨기", can)
	_set_button("overwatch", "경계", can and selected.weapon != "")
	_set_button("grenade", "취소" if mode == "grenade" else "수류탄 %d" % battle.grenades, can and battle.grenades > 0)
	_set_button("board", "탑승", can and battle.can_board(selected))
	_set_button("surrender", "항복 요구", can and battle.can_demand_surrender())
	_set_button("end_turn", "계속" if battle.result != "" else "턴 종료", true)
	_log_label.text = "\n".join(battle.messages.slice(-9))
	_board.queue_redraw()


func _set_button(id: String, text: String, enabled: bool) -> void:
	_buttons[id].text = text
	_buttons[id].disabled = not enabled


func _hover_text() -> String:
	if not battle._in_bounds(hover):
		return "파란 칸: 이동  ·  적 클릭: 공격  ·  초록 칸에서 탑승"
	if mode == "grenade":
		return "수류탄 목표 (사거리 %d, 우클릭 취소)" % int(battle.cfg.grenade.range)
	var u := battle.unit_at(hover)
	if not u.is_empty():
		var line := "%s  체력 %d/%d" % [u.name, u.hp, u.max_hp]
		if u.side == "enemy" and not selected.is_empty():
			var wid := battle.weapon_for(selected, u.pos)
			if wid == "":
				line += "  ·  사거리 밖이거나 가려짐"
			else:
				line += "  ·  %s 명중 %d%%" % [battle.cfg.weapons[wid].name, battle.hit_chance(selected, u)]
		return line
	match battle.tile(hover):
		Battle.Tile.HALF:
			return "반 엄폐물"
		Battle.Tile.FULL:
			return "완전 엄폐물 (시야를 가린다)"
		Battle.Tile.BARREL:
			return "폭발물 통 (수류탄에 터진다)"
	if hover in battle.car_cells:
		var dmg := battle.damaged_parts.keys().map(func(p): return battle.cfg.car.parts[p].name)
		return "우리 차" + ("  ·  파손: " + ", ".join(dmg) if not dmg.is_empty() else "")
	if hover in battle.escape_cells:
		return "탈출 구역: 여기서 탑승할 수 있다"
	return ""


func _draw_board() -> void:
	var font := get_theme_default_font()
	var reach := {}
	if mode == "normal" and not selected.is_empty() and battle.can_act(selected):
		reach = battle.reachable(selected)
	for y in battle.h:
		for x in battle.w:
			var c := Vector2i(x, y)
			var r := Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
			_board.draw_rect(r, COL_FLOOR)
			if c in battle.escape_cells:
				_board.draw_rect(r, COL_ESCAPE)
			if reach.has(c):
				_board.draw_rect(r, COL_REACH)
			_board.draw_rect(r, COL_GRID, false, 1.0)
			match battle.tile(c):
				Battle.Tile.HALF:
					_board.draw_rect(r.grow(-7), COL_HALF)
					_board.draw_rect(Rect2(r.position + Vector2(7, 7), Vector2(TILE - 14, 3)), COL_HALF.lightened(0.25))
				Battle.Tile.FULL:
					_board.draw_rect(r.grow(-2), COL_FULL)
					_board.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(TILE - 4, 4)), COL_FULL.lightened(0.3))
				Battle.Tile.BARREL:
					_board.draw_circle(r.get_center(), 10, COL_BARREL)
					_board.draw_rect(Rect2(r.get_center() - Vector2(10, 2), Vector2(20, 3)), COL_BARREL.darkened(0.4))
	# 차
	var car_rect := Rect2(Vector2(battle.car_cells[0]) * TILE, Vector2(TILE * 2, TILE * 2)).grow(-3)
	_board.draw_rect(car_rect, Color(0.55, 0.48, 0.36))
	_board.draw_rect(car_rect, Color(0, 0, 0, 0.6), false, 2.0)
	_board.draw_string(font, car_rect.get_center() + Vector2(-12, 8), "차", HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
		Color(0.9, 0.3, 0.25) if not battle.damaged_parts.is_empty() else Color(0.12, 0.1, 0.1))
	# 수류탄 범위
	if mode == "grenade" and battle._in_bounds(hover) and not selected.is_empty():
		var ok := Battle.cheb(selected.pos, hover) <= int(battle.cfg.grenade.range)
		var rad := int(battle.cfg.grenade.radius)
		var area := Rect2(Vector2(hover - Vector2i(rad, rad)) * TILE, Vector2.ONE * TILE * (rad * 2 + 1))
		_board.draw_rect(area, Color(1, 0.5, 0.2, 0.3) if ok else Color(0.5, 0.5, 0.5, 0.25))
	# 유닛
	for u in battle.units:
		if u.boarded:
			continue
		var center := Vector2(u.pos) * TILE + Vector2(TILE, TILE) / 2
		if u.down:
			_board.draw_line(center - Vector2(8, 8), center + Vector2(8, 8), Color(0.5, 0.2, 0.2), 3)
			_board.draw_line(center - Vector2(8, -8), center + Vector2(8, -8), Color(0.5, 0.2, 0.2), 3)
			continue
		var col := COL_PLAYER if u.side == "player" else COL_ENEMY
		if u == selected:
			_board.draw_circle(center, 14, Color.WHITE)
		_board.draw_circle(center, 12, col.darkened(0.2))
		_board.draw_circle(center, 9, col)
		_board.draw_string(font, center + Vector2(-6, 5), u.name.substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.08))
		var hp_w: float = 26.0 * u.hp / u.max_hp
		_board.draw_rect(Rect2(center + Vector2(-13, 13), Vector2(26, 3)), Color(0.2, 0.05, 0.05))
		_board.draw_rect(Rect2(center + Vector2(-13, 13), Vector2(hp_w, 3)), Color(0.4, 0.9, 0.4))
		if u.hidden:
			_board.draw_string(font, center + Vector2(6, -6), "숨", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelTheme.ACCENT)
		if u.overwatch:
			_board.draw_string(font, center + Vector2(6, -6), "경", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelTheme.ACCENT)
	# 조준 중인 적의 명중률
	if mode == "normal" and battle._in_bounds(hover) and not selected.is_empty():
		var t := battle.unit_at(hover)
		if not t.is_empty() and t.side == "enemy":
			var ch := battle.hit_chance(selected, t)
			var p := Vector2(hover) * TILE + Vector2(-4, -6)
			_board.draw_string(font, p, "%d%%" % ch if ch > 0 else "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, PixelTheme.ACCENT)
	_board.draw_rect(Rect2(Vector2.ZERO, _board.size), PixelTheme.PANEL_BORDER, false, 2.0)
