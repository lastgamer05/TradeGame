extends Control
## 정육각형 타일 전투 화면 (pointy-top). 규칙은 Battle이 처리하고, 이 화면은 Battle.events를
## 차례대로 애니메이션으로 재생한다. 스프라이트가 없으면 입체 도형으로 대신 그린다.
## 조작: 내 유닛 클릭 = 선택, 파란 칸 = 이동, 적 = 공격, 우클릭 = 취소
## 단축키: 1 숨기, 2 경계, 3 수류탄, 4 탑승, 5 항복 요구, Space 턴 종료, Tab 다음 유닛, F 빠르게

signal finished(battle: Battle)

const R := 26.0  # 육각형 외접원 반지름. 칸 폭 = sqrt(3) * R
## 세로 눌림 비율. 1.0 = 위에서 내려다본 정육각형, 1보다 작으면 비스듬히 본 시점.
const TILT := 0.58
## 전장 회전 (도). 0 = 왼쪽→오른쪽 가로 배치, 음수면 오른쪽 위로 기운 대각선 배치.
const ROT_DEG := -30.0
const TH := 20.0  # 스프라이트 발밑 보정용
const HALF_H := 12.0
const FULL_H := 30.0
const UNIT_H := 56.0
const UNIT_SPRITE := "res://assets/combat/units/%s.png"
const PROP_SPRITE := "res://assets/combat/props/%s.png"
const GROUND := "res://assets/combat/ground/%s.png"
## 좌우로 뒤집어도 되는 소품. 줄로 늘어서는 소품은 뒤집으면 긴 축이 어긋난다.
const FLIPPABLE := ["crates", "tires", "rubble", "scrap", "rocks", "boulder", "barrel"]
## 스프라이트 표시 크기 (px). 유닛은 키, 소품은 폭 기준.
const UNIT_HEIGHTS := { "raider_brute": 66.0, "war_machine": 64.0 }
const PROP_WIDTHS := {
	"barrier": 50.0, "crates": 48.0, "sandbags": 52.0, "wall": 42.0, "wreck": 64.0,
	"container": 50.0, "barrel": 20.0, "car": 118.0,
	"rubble": 46.0, "tires": 32.0, "brick": 52.0, "scrap": 48.0, "boulder": 50.0, "rocks": 42.0,
	"tank": 100.0, "bus": 108.0,
}
## 두 칸짜리로 놓였을 때의 폭
const LONG_WIDTHS := { "container": 88.0, "tank": 100.0, "bus": 108.0 }
const RESULT_NAMES := { "victory": "승리", "surrender": "항복을 받아냈다", "escaped": "도주 성공", "wiped": "분대 전멸" }

const FLOOR_COLORS := {
	"highway": [Color(0.2, 0.19, 0.2), Color(0.25, 0.23, 0.22)],
	"checkpoint": [Color(0.19, 0.2, 0.22), Color(0.24, 0.25, 0.27)],
	"canyon": [Color(0.3, 0.19, 0.14), Color(0.36, 0.23, 0.16)],
	"alley": [Color(0.17, 0.17, 0.19), Color(0.21, 0.2, 0.22)],
	"gas_station": [Color(0.22, 0.2, 0.17), Color(0.27, 0.24, 0.2)],
}
const COL_HALF := Color(0.5, 0.37, 0.24)
const COL_FULL := Color(0.4, 0.41, 0.45)
const COL_BARREL := Color(0.72, 0.22, 0.16)
const COL_CAR := Color(0.55, 0.46, 0.32)
const COL_PLAYER := Color(0.4, 0.85, 0.95)
const COL_ENEMY := Color(0.92, 0.35, 0.3)
const COL_REACH := Color(0.35, 0.6, 1.0, 0.28)
const COL_ESCAPE := Color(0.3, 0.85, 0.4, 0.25)

var battle: Battle
var selected_id := ""
var mode := "normal"  # normal, grenade
var hover := Vector2i(-1, -1)
var playing := false
var speed := 1.0

var origin := Vector2.ZERO
## 화면에 보이는 상태. 규칙 상태와 달리 애니메이션이 끝나야 따라간다.
var disp := {}      # id -> Vector2 (화면 좌표, 발밑)
var disp_hp := {}
var disp_down := {}
var disp_boarded := {}
var facing := {}    # id -> 1 오른쪽 / -1 왼쪽
var flash := {}     # id -> 남은 시간
var lunge := {}     # id -> Vector2 화면 오프셋
var _fx: Array = [] # { kind, t, dur, ... }
var _banner := ""
var _banner_t := 0.0
var _tex_cache := {}

var _board: Control
var _title: Label
var _phase: Label
var _log_label: Label
var _squad_box: HBoxContainer
var _info: Label
var _buttons := {}


func setup(b: Battle) -> void:
	battle = b
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle.events.clear()
	_build_ui()
	_layout_origin()
	for u in battle.units:
		disp[u.id] = tile_center(u.pos)
		disp_hp[u.id] = u.hp
		disp_down[u.id] = u.down
		disp_boarded[u.id] = u.boarded
		facing[u.id] = 1 if u.side == "player" else -1
	_select_next()
	_refresh()
	_show_banner("%s" % battle.encounter.name)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_board = Control.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	add_child(_board)

	# 왼쪽 위: 제목과 턴
	var top := PanelContainer.new()
	top.position = Vector2(16, 12)
	add_child(top)
	var tbox := VBoxContainer.new()
	top.add_child(tbox)
	_title = Label.new()
	_title.add_theme_font_override("font", PixelTheme.font(true))
	_title.add_theme_color_override("font_color", PixelTheme.ACCENT)
	tbox.add_child(_title)
	_phase = Label.new()
	tbox.add_child(_phase)

	# 오른쪽 위: 전투 로그
	var log_panel := PanelContainer.new()
	log_panel.position = Vector2(1280 - 16 - 470, 12)
	log_panel.custom_minimum_size = Vector2(470, 0)
	add_child(log_panel)
	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(440, 0)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	log_panel.add_child(_log_label)

	# 아래: 분대 카드, 정보, 행동 버튼
	var bottom := PanelContainer.new()
	bottom.position = Vector2(16, 720 - 16 - 112)
	bottom.custom_minimum_size = Vector2(1280 - 32, 112)
	add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bottom.add_child(row)
	_squad_box = HBoxContainer.new()
	_squad_box.add_theme_constant_override("separation", 8)
	row.add_child(_squad_box)
	_info = Label.new()
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	row.add_child(_info)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	for id in ["hide", "overwatch", "grenade", "board", "surrender", "end_turn"]:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 0)
		btn.pressed.connect(_on_action.bind(id))
		grid.add_child(btn)
		_buttons[id] = btn


func _layout_origin() -> void:
	# 맵 전체가 위아래 HUD 사이에 들어오게 가운데 정렬
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for y in battle.h:
		for x in battle.w:
			var p := _project(Battle.to_plane(Vector2i(x, y)) * R)
			min_p = min_p.min(p - Vector2(R, R * TILT))
			max_p = max_p.max(p + Vector2(R, R * TILT))
	var area := Rect2(0, 100, 1280, 720 - 100 - 136)
	origin = (area.get_center() - (min_p + max_p) / 2).round()


# --- 좌표 ---

func tile_center(c: Vector2i) -> Vector2:
	return origin + _project(Battle.to_plane(c) * R)


## 평면 좌표 -> 화면: 회전한 뒤 세로로 눌러 비스듬한 시점을 만든다.
func _project(v: Vector2) -> Vector2:
	return v.rotated(deg_to_rad(ROT_DEG)) * Vector2(1, TILT)


func cell_at(p: Vector2) -> Vector2i:
	var l := ((p - origin) / Vector2(1, TILT)).rotated(-deg_to_rad(ROT_DEG)) / R
	var q := sqrt(3.0) / 3.0 * l.x - l.y / 3.0
	var r := 2.0 / 3.0 * l.y
	return Battle.from_cube(Battle._cube_round(Vector3(q, r, -q - r)))


## 화면 좌표 중심의 정육각형 (꼭짓점: 오른쪽 위부터 시계 방향, 위가 뾰족)
func _hex_at(center: Vector2, scale := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + _project(Vector2(cos(a), sin(a)) * R * scale))
	return pts


func _hex(c: Vector2i, scale := 1.0) -> PackedVector2Array:
	return _hex_at(tile_center(c), scale)


# --- 입력 ---

func _on_board_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := cell_at(ev.position)
		if c != hover:
			hover = c
			_refresh_info()
			_board.queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and not playing:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			mode = "normal"
			_refresh()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			_click(cell_at(ev.position))


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	match ev.keycode:
		KEY_1: _on_action("hide")
		KEY_2: _on_action("overwatch")
		KEY_3: _on_action("grenade")
		KEY_4: _on_action("board")
		KEY_5: _on_action("surrender")
		KEY_SPACE: _on_action("end_turn")
		KEY_TAB:
			_select_next(true)
			_refresh()
		KEY_F:
			speed = 2.5 if speed == 1.0 else 1.0
			_refresh_info()


func _selected() -> Dictionary:
	for u in battle.units:
		if u.id == selected_id:
			return u
	return {}


func _unit(id: String) -> Dictionary:
	for u in battle.units:
		if u.id == id:
			return u
	return {}


func _click(c: Vector2i) -> void:
	if battle.result != "" or not battle._in_bounds(c):
		return
	var sel := _selected()
	var u := battle.unit_at(c)
	if mode == "grenade":
		if not sel.is_empty() and battle.throw_grenade(sel, c):
			mode = "normal"
			_after_action()
		return
	if not u.is_empty() and u.side == "player":
		selected_id = u.id
	elif not u.is_empty() and u.side == "enemy":
		if not sel.is_empty() and battle.attack(sel, u):
			_after_action()
			return
	elif not sel.is_empty() and battle.move(sel, c):
		_after_action()
		return
	_refresh()


func _on_action(id: String) -> void:
	if playing:
		return
	if battle.result != "":
		if id == "end_turn":
			finished.emit(battle)
		return
	var sel := _selected()
	match id:
		"hide":
			battle.hide(sel)
		"overwatch":
			battle.set_overwatch(sel)
		"grenade":
			if sel.is_empty() or battle.grenades <= 0 or not battle.can_act(sel):
				return
			mode = "normal" if mode == "grenade" else "grenade"
			_refresh()
			return
		"board":
			battle.board(sel)
		"surrender":
			battle.demand_surrender(sel)
		"end_turn":
			battle.end_player_turn()
	_after_action()


func _after_action() -> void:
	await _play_events()
	var sel := _selected()
	if sel.is_empty() or not battle.can_act(sel):
		_select_next()
	_refresh()
	if battle.result != "":
		_show_banner("전투 종료: %s" % RESULT_NAMES.get(battle.result, battle.result), 99.0)


func _select_next(cycle := false) -> void:
	var squad := battle.active_units("player")
	if squad.is_empty():
		selected_id = ""
		return
	var start := 0
	if cycle:
		for i in squad.size():
			if squad[i].id == selected_id:
				start = i + 1
	for i in squad.size():
		var u: Dictionary = squad[(start + i) % squad.size()]
		if u.ap > 0:
			selected_id = u.id
			return
	if _selected().is_empty() or _selected().down or _selected().boarded:
		selected_id = squad[0].id


# --- 사건 재생 ---

func _wait(t: float) -> void:
	await get_tree().create_timer(t / speed).timeout


func _play_events() -> void:
	playing = true
	_refresh()
	while not battle.events.is_empty():
		var ev: Dictionary = battle.events.pop_front()
		match ev.type:
			"move":
				await _anim_move(ev)
			"shot":
				await _anim_shot(ev)
			"damage":
				_popup("-%d" % ev.dmg, _unit_head(ev.id), Color(1, 0.4, 0.35))
				flash[ev.id] = 0.25
				disp_hp[ev.id] = ev.hp_after
				if ev.hp_after == 0:
					disp_down[ev.id] = true
					_popup("쓰러짐", _unit_head(ev.id) + Vector2(0, -22), PixelTheme.TEXT_DIM)
				_refresh_squad()
				await _wait(0.35)
			"explode":
				_fx.append({ "kind": "explode", "pos": tile_center(ev.cell), "r": (ev.radius + 0.6) * R * 1.7, "t": 0.0, "dur": 0.5 })
				await _wait(0.45)
			"status":
				_popup(ev.text, _unit_head(ev.id), PixelTheme.ACCENT)
				await _wait(0.45)
			"board":
				_popup("탑승", _unit_head(ev.id), Color(0.5, 0.95, 0.6))
				await _wait(0.25)
				disp_boarded[ev.id] = true
			"car_shot":
				var car := _car_center()
				_fx.append({ "kind": "tracer", "from": _unit_chest(ev.from), "to": car, "t": 0.0, "dur": 0.18, "color": COL_ENEMY })
				await _wait(0.18)
				_popup(("%s 파손!" % ev.part) if ev.hit else "차체를 스쳤다", car + Vector2(0, -30), Color(1, 0.5, 0.3) if ev.hit else PixelTheme.TEXT_DIM)
				await _wait(0.45)
			"phase":
				_show_banner("적 턴" if ev.side == "enemy" else "내 턴", 0.8)
				_phase.text = "적 턴" if ev.side == "enemy" else "%d턴 · 내 턴" % battle.turn
				await _wait(0.7)
	# 규칙 상태와 맞추기
	for u in battle.units:
		disp[u.id] = tile_center(u.pos)
		disp_hp[u.id] = u.hp
		disp_down[u.id] = u.down
		disp_boarded[u.id] = u.boarded
	playing = false


func _anim_move(ev: Dictionary) -> void:
	var path: Array = ev.path
	for i in range(1, path.size()):
		var a := tile_center(path[i - 1])
		var b := tile_center(path[i])
		var dir := b - a
		if absf(dir.x) > 0.1:
			facing[ev.id] = 1 if dir.x > 0 else -1
		var tw := create_tween()
		var id: String = ev.id
		tw.tween_method(func(v: Vector2):
			disp[id] = v
			_board.queue_redraw(), a, b, 0.09 / speed)
		await tw.finished


func _anim_shot(ev: Dictionary) -> void:
	var from := _unit_chest(ev.from)
	var to := _unit_chest(ev.to)
	facing[ev.from] = 1 if to.x >= from.x else -1
	if ev.melee:
		var dir := (to - from).normalized() * 14
		lunge[ev.from] = dir
		await _wait(0.12)
		lunge.erase(ev.from)
	else:
		_fx.append({ "kind": "muzzle", "pos": from, "t": 0.0, "dur": 0.12 })
		_fx.append({ "kind": "tracer", "from": from, "to": to, "t": 0.0, "dur": 0.16, "color": COL_PLAYER if ev.from.begins_with("p") else COL_ENEMY })
		await _wait(0.16)
	if not ev.hit:
		_popup("빗나감", _unit_head(ev.to), PixelTheme.TEXT_DIM)
		await _wait(0.3)


func _popup(text: String, pos: Vector2, col: Color) -> void:
	_fx.append({ "kind": "text", "text": text, "pos": pos, "t": 0.0, "dur": 0.9, "color": col })


func _show_banner(text: String, dur := 1.2) -> void:
	_banner = text
	_banner_t = dur


func _process(delta: float) -> void:
	var dirty := false
	for f in _fx:
		f.t += delta * speed
	_fx = _fx.filter(func(f): return f.t < f.dur)
	if not _fx.is_empty():
		dirty = true
	for id in flash.keys():
		flash[id] -= delta * speed
		if flash[id] <= 0:
			flash.erase(id)
		dirty = true
	if _banner_t > 0:
		_banner_t -= delta
		dirty = true
	if dirty or playing:
		_board.queue_redraw()


func _unit_screen(id: String) -> Vector2:
	return disp[id] + lunge.get(id, Vector2.ZERO)


func _unit_chest(id: String) -> Vector2:
	return _unit_screen(id) + Vector2(0, -UNIT_H * 0.5)


func _unit_head(id: String) -> Vector2:
	return _unit_screen(id) + Vector2(0, -UNIT_H - 10)


func _car_ground() -> Vector2:
	var sum := Vector2.ZERO
	for c in battle.car_cells:
		sum += tile_center(c)
	return sum / battle.car_cells.size()


func _car_center() -> Vector2:
	return _car_ground() + Vector2(0, -20)


# --- HUD ---

func _refresh() -> void:
	_title.text = "%s · %s" % [battle.encounter.name, battle.location.name]
	if not playing:
		_phase.text = "%d턴 · 내 턴" % battle.turn if battle.result == "" else "전투 종료: %s" % RESULT_NAMES.get(battle.result, battle.result)
	_log_label.text = "\n".join(battle.messages.slice(-5))
	var sel := _selected()
	var can := not playing and battle.result == "" and not sel.is_empty() and battle.can_act(sel)
	_set_button("hide", "숨기 [1]", can)
	_set_button("overwatch", "경계 [2]", can and sel.get("weapon", "") != "")
	_set_button("grenade", "취소 [3]" if mode == "grenade" else "수류탄 %d [3]" % battle.grenades, can and battle.grenades > 0)
	_set_button("board", "탑승 [4]", can and battle.can_board(sel))
	_set_button("surrender", "항복 요구 [5]", can and battle.can_demand_surrender())
	_set_button("end_turn", "계속" if battle.result != "" else "턴 종료 [Space]", not playing)
	_refresh_squad()
	_refresh_info()
	_board.queue_redraw()


func _set_button(id: String, text: String, enabled: bool) -> void:
	_buttons[id].text = text
	_buttons[id].disabled = not enabled


func _refresh_squad() -> void:
	for c in _squad_box.get_children():
		c.queue_free()
	for u in battle.units:
		if u.side != "player":
			continue
		var card := Button.new()
		card.custom_minimum_size = Vector2(200, 0)
		card.toggle_mode = true
		card.button_pressed = u.id == selected_id
		var status := "쓰러짐" if disp_down[u.id] else ("탑승" if disp_boarded[u.id] else "행동 " + "●".repeat(u.ap) + "○".repeat(int(battle.cfg.ap_per_turn) - u.ap))
		card.text = "%s  %d/%d\n%s" % [u.name, disp_hp[u.id], u.max_hp, status]
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.disabled = disp_down[u.id] or disp_boarded[u.id]
		var uid: String = u.id
		card.pressed.connect(func():
			selected_id = uid
			_refresh())
		_squad_box.add_child(card)


func _refresh_info() -> void:
	var sel := _selected()
	var lines := []
	if not sel.is_empty():
		var wpn: String = battle.cfg.weapons[sel.weapon].name if sel.weapon != "" else "-"
		lines.append("%s · %s · 집중 %d 완력 %d" % [sel.name, wpn, sel.aim, sel.might])
	lines.append(_hover_text())
	if speed > 1.0:
		lines.append("빠르게 재생 중 [F]")
	_info.text = "\n".join(lines)


func _hover_text() -> String:
	if mode == "grenade":
		return "수류탄 목표를 고른다 (사거리 %d, 우클릭 취소)" % int(battle.cfg.grenade.range)
	if not battle._in_bounds(hover):
		return "파란 칸 이동 · 적 클릭 공격 · 초록 칸에서 탑승"
	var u := battle.unit_at(hover)
	var sel := _selected()
	if not u.is_empty():
		var line := "%s 체력 %d/%d" % [u.name, u.hp, u.max_hp]
		if u.side == "enemy" and not sel.is_empty():
			var wid := battle.weapon_for(sel, u.pos)
			line += "  ·  " + ("사거리 밖이거나 가려짐" if wid == "" else "%s 명중 %d%%" % [battle.cfg.weapons[wid].name, battle.hit_chance(sel, u)])
		return line
	match battle.tile(hover):
		Battle.Tile.HALF: return "반 엄폐물: 뒤에 서면 명중률이 크게 떨어진다"
		Battle.Tile.FULL: return "완전 엄폐물: 시야를 가린다"
		Battle.Tile.BARREL: return "폭발물 통: 수류탄에 연쇄 폭발한다"
	if hover in battle.car_cells:
		var dmg := battle.damaged_parts.keys().map(func(p): return battle.cfg.car.parts[p].name)
		return "우리 차" + ("  ·  파손: " + ", ".join(dmg) if not dmg.is_empty() else "")
	if hover in battle.escape_cells:
		return "탈출 구역: 여기서 탑승할 수 있다"
	if not sel.is_empty():
		var reach := battle.reachable(sel)
		if reach.has(hover):
			var cover := 0
			for e in battle.active_units("enemy"):
				cover = maxi(cover, battle.cover_level(hover, e.pos))
			return "이동 %d칸%s" % [reach[hover].size(), ["", " · 반 엄폐", " · 완전 엄폐"][cover]]
	return ""


# --- 그리기 ---

func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _draw_board() -> void:
	var sel := _selected()
	var reach := {}
	if mode == "normal" and not playing and not sel.is_empty() and battle.can_act(sel):
		reach = battle.reachable(sel)
	var colors: Array = FLOOR_COLORS.get(battle.encounter.location, FLOOR_COLORS.highway)

	# 바닥: 장소 지형 그림을 화면 전체에 어둡게 깔고, 칸 안에는 같은 그림을 밝게 비춘다.
	var ground := _tex(GROUND % battle.encounter.location)
	var bg_rect := _cover_rect(ground.get_size()) if ground else Rect2()
	if ground:
		_board.draw_texture_rect(ground, bg_rect, false, Color(0.32, 0.3, 0.34))
	for y in battle.h:
		for x in battle.w:
			var c := Vector2i(x, y)
			var shade := float((x * 7 + y * 13) % 5) / 4.0
			var poly := _hex(c)
			if ground:
				var uvs := PackedVector2Array()
				for pt in poly:
					uvs.append((pt - bg_rect.position) / bg_rect.size)
				_board.draw_colored_polygon(poly, Color(1, 1, 1), uvs, ground)
				_board.draw_colored_polygon(poly, Color(0, 0, 0, 0.06 * shade))
			else:
				_board.draw_colored_polygon(poly, colors[0].lerp(colors[1], shade))
			if c in battle.escape_cells:
				_board.draw_colored_polygon(_hex(c, 0.88), COL_ESCAPE)
			if reach.has(c):
				_board.draw_colored_polygon(_hex(c, 0.88), COL_REACH)
			_board.draw_polyline(_closed(poly), Color(0, 0, 0, 0.28), 1.0)
			_board.draw_polyline(_closed(_hex(c, 0.97)), Color(1, 0.9, 0.7, 0.06), 1.0)
	# 공격 가능한 적 표시
	if not sel.is_empty() and battle.can_act(sel) and not playing:
		for e in battle.active_units("enemy"):
			if battle.weapon_for(sel, e.pos) != "":
				_board.draw_polyline(_closed(_hex(e.pos, 0.86)), Color(1, 0.4, 0.3, 0.9), 2.0)
	# 선택 유닛 발밑
	if not sel.is_empty() and not disp_boarded.get(sel.id, false):
		_board.draw_polyline(_closed(_hex_at(disp[sel.id], 0.9)), Color.WHITE, 2.0)
	# 이동 경로 미리보기
	if reach.has(hover):
		_draw_path([sel.pos] + reach[hover])
	elif battle._in_bounds(hover) and mode == "normal":
		_board.draw_polyline(_closed(_hex(hover, 0.92)), Color(1, 1, 1, 0.35), 1.5)
	# 수류탄 범위
	if mode == "grenade" and battle._in_bounds(hover) and not sel.is_empty():
		var ok := Battle.hex_dist(sel.pos, hover) <= int(battle.cfg.grenade.range)
		for p in battle.cells_within(hover, int(battle.cfg.grenade.radius)):
			_board.draw_colored_polygon(_hex(p, 0.88), Color(1, 0.5, 0.2, 0.35) if ok else Color(0.5, 0.5, 0.5, 0.3))

	# 물체와 유닛을 화면 아래쪽일수록 나중에 (앞에) 그린다
	var items := []
	for y in battle.h:
		for x in battle.w:
			var c := Vector2i(x, y)
			var t := battle.tile(c)
			if t == Battle.Tile.FLOOR:
				continue
			var prop: Dictionary = battle.props.get(c, { "name": "", "anchor": true, "cells": [c] })
			if not prop.anchor:
				continue
			var d := -INF
			for pc in prop.cells:
				d = maxf(d, tile_center(pc).y)
			items.append({ "d": d, "k": "tile", "c": c, "t": t, "prop": prop })
	items.append({ "d": _car_ground().y, "k": "car" })
	for u in battle.units:
		if disp_boarded[u.id]:
			continue
		var p: Vector2 = disp[u.id]
		items.append({ "d": p.y + 0.1, "k": "unit", "u": u })
	items.sort_custom(func(a, b): return a.d < b.d)
	for it in items:
		match it.k:
			"tile": _draw_tile_object(it.c, it.t, it.prop)
			"car": _draw_car()
			"unit": _draw_unit(it.u)

	# 조준선과 명중률
	if mode == "normal" and not playing and not sel.is_empty() and battle._in_bounds(hover):
		var t := battle.unit_at(hover)
		if not t.is_empty() and t.side == "enemy":
			var ch := battle.hit_chance(sel, t)
			var a := _unit_chest(sel.id)
			var b := _unit_chest(t.id)
			if ch > 0:
				_dashed(a, b, Color(1, 0.72, 0.32, 0.9))
			_label_at("%d%%" % ch if ch > 0 else "불가", _unit_head(t.id) + Vector2(0, -20), PixelTheme.ACCENT, 24)

	# 효과
	var font := get_theme_default_font()
	for f in _fx:
		var k: float = f.t / f.dur
		match f.kind:
			"tracer":
				var head: Vector2 = f.from.lerp(f.to, clampf(k * 1.3, 0, 1))
				var tail: Vector2 = f.from.lerp(f.to, clampf(k * 1.3 - 0.35, 0, 1))
				_board.draw_line(tail, head, f.color, 3.0)
			"muzzle":
				_board.draw_circle(f.pos, 7.0 * (1.0 - k), Color(1, 0.9, 0.5, 1.0 - k))
			"explode":
				_board.draw_circle(f.pos, f.r * (0.3 + 0.7 * k), Color(1, 0.55, 0.2, 0.7 * (1.0 - k)))
				_board.draw_circle(f.pos, f.r * 0.5 * (0.3 + 0.7 * k), Color(1, 0.9, 0.5, 0.8 * (1.0 - k)))
			"text":
				_label_at(f.text, f.pos + Vector2(0, -26 * k), Color(f.color, 1.0 - maxf(0, k - 0.6) / 0.4), 24)
	if _banner_t > 0:
		var a := clampf(_banner_t, 0, 1)
		var y := 300.0
		_board.draw_rect(Rect2(0, y - 34, 1280, 56), Color(0, 0, 0, 0.55 * a))
		_board.draw_string(font, Vector2(0, y + 8), _banner, HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color(PixelTheme.ACCENT, a))


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _label_at(text: String, pos: Vector2, col: Color, fsize := 12) -> void:
	var font := get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := (pos - Vector2(w / 2, 0)).round()
	_board.draw_string(font, p + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, col.a * 0.8))
	_board.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(a.distance_to(b) / 10)
	for i in n:
		if i % 2 == 0:
			_board.draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 2.0)


## 이동 경로를 부드러운 곡선으로 그리고 도착 칸에 고리를 친다.
func _draw_path(cells: Array) -> void:
	var pts := PackedVector2Array()
	for c in cells:
		pts.append(tile_center(c))
	for iter in 2:
		var smooth := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			smooth.append(pts[i].lerp(pts[i + 1], 0.25))
			smooth.append(pts[i].lerp(pts[i + 1], 0.75))
		smooth.append(pts[pts.size() - 1])
		pts = smooth
	_board.draw_polyline(pts, Color(0, 0, 0, 0.5), 6.0)
	_board.draw_polyline(pts, Color(1, 1, 1, 0.95), 3.0)
	var end: Vector2i = cells[cells.size() - 1]
	_board.draw_polyline(_closed(_hex(end, 0.8)), Color.WHITE, 3.0)
	_board.draw_polyline(_closed(_hex(end, 0.5)), Color(1, 1, 1, 0.6), 2.0)


## 바닥 위에 선 육각 기둥. 스프라이트가 없을 때 쓴다.
func _draw_prism(ground: Vector2, scale: float, height: float, col: Color) -> void:
	var base := _hex_at(ground, scale)
	var top := PackedVector2Array()
	for p in base:
		top.append(p - Vector2(0, height))
	# 아래를 향한 면 (꼭짓점 0-1, 1-2, 2-3, 3-4)
	var shades := [0.15, 0.25, 0.35, 0.45]
	for i in 4:
		_board.draw_colored_polygon(PackedVector2Array([base[i], base[i + 1], top[i + 1], top[i]]), col.darkened(shades[i]))
	_board.draw_colored_polygon(top, col.lightened(0.12))
	_board.draw_polyline(_closed(top), Color(0, 0, 0, 0.5), 1.0)


## 화면을 꽉 채우도록 비율을 유지해 늘린 사각형
func _cover_rect(tex_size: Vector2) -> Rect2:
	var screen := Vector2(1280, 720)
	var s := maxf(screen.x / tex_size.x, screen.y / tex_size.y)
	var sz := tex_size * s
	return Rect2((screen - sz) / 2, sz)


func _draw_tile_object(c: Vector2i, t: int, info: Dictionary) -> void:
	var prop: String = info.name
	var cells: Array = info.cells
	var tex := _tex(PROP_SPRITE % prop) if prop != "" else null
	if tex:
		var ground := Vector2.ZERO
		for pc in cells:
			ground += tile_center(pc)
		ground /= cells.size()
		var width: float = LONG_WIDTHS.get(prop, PROP_WIDTHS.get(prop, 48.0)) if cells.size() > 1 else PROP_WIDTHS.get(prop, 48.0)
		if prop in FLIPPABLE:
			# 같은 소품이 반복돼 보이지 않게 칸마다 크기를 조금씩 다르게
			width *= 0.85 + 0.3 * float((c.x * 37 + c.y * 71) % 10) / 9.0
		_draw_sprite(tex, ground, width, prop in FLIPPABLE and (c.x + c.y) % 2 == 1)
		return
	match t:
		Battle.Tile.HALF:
			_draw_prism(tile_center(c), 0.75, HALF_H, COL_HALF)
		Battle.Tile.FULL:
			_draw_prism(tile_center(c), 0.9, FULL_H, COL_FULL)
		Battle.Tile.BARREL:
			var ctr := tile_center(c)
			_board.draw_rect(Rect2(ctr + Vector2(-8, -20), Vector2(16, 20)), COL_BARREL)
			_board.draw_rect(Rect2(ctr + Vector2(-8, -12), Vector2(16, 3)), Color(0.95, 0.8, 0.2))
			_board.draw_circle(ctr + Vector2(0, -20), 8, COL_BARREL.lightened(0.2))


func _draw_car() -> void:
	var tex := _tex(PROP_SPRITE % "car")
	var ground := _car_ground()
	if tex:
		_draw_sprite(tex, ground + Vector2(0, R * 0.6), PROP_WIDTHS.car, true)
	else:
		_draw_prism(ground, 1.7, 22, COL_CAR)
		_draw_prism(ground + Vector2(-6, -4), 0.9, 38, COL_CAR.darkened(0.15))
	if not battle.damaged_parts.is_empty():
		_label_at("파손", ground + Vector2(0, -56), Color(1, 0.45, 0.35))


## 텍스처를 발밑(아래 가운데)이 ground에 오도록 폭 기준으로 그린다.
func _draw_sprite(tex: Texture2D, ground: Vector2, width: float, flip: bool, modulate := Color.WHITE) -> void:
	var s := width / tex.get_width()
	var sz := tex.get_size() * s
	var rect := Rect2(ground - Vector2(sz.x / 2, sz.y - TH * 0.25), sz)
	if flip:
		rect.size.x = -sz.x
	_board.draw_texture_rect(tex, rect, false, modulate)


func _draw_unit(u: Dictionary) -> void:
	var ground := _unit_screen(u.id)
	var down: bool = disp_down[u.id]
	var col := COL_PLAYER if u.side == "player" else COL_ENEMY
	var tint := Color(3, 3, 3) if flash.has(u.id) else (Color(0.45, 0.4, 0.4, 0.8) if down else Color.WHITE)
	# 그림자
	_board.draw_set_transform(ground, 0, Vector2(1, 0.5))
	_board.draw_circle(Vector2.ZERO, 16, Color(0, 0, 0, 0.35))
	_board.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var tex := _tex(UNIT_SPRITE % u.kind)
	var big: bool = u.kind == "war_machine"
	if tex:
		var width: float = UNIT_HEIGHTS.get(u.kind, 60.0) / tex.get_height() * tex.get_width()
		if down:
			_board.draw_set_transform(ground, PI / 2 * facing[u.id], Vector2.ONE)
			_draw_sprite(tex, Vector2.ZERO, width, facing[u.id] > 0, tint)
			_board.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		else:
			_draw_sprite(tex, ground, width, facing[u.id] > 0, tint)
	else:
		if down:
			_board.draw_rect(Rect2(ground + Vector2(-14, -6), Vector2(28, 8)), col.darkened(0.6))
		else:
			var body := Rect2(ground + Vector2(-9, -UNIT_H * 0.72), Vector2(18, UNIT_H * 0.62))
			if big:
				body = Rect2(ground + Vector2(-20, -UNIT_H * 0.8), Vector2(40, UNIT_H * 0.7))
			_board.draw_rect(body, col.darkened(0.35) * tint)
			_board.draw_rect(body.grow(-3), col * tint)
			_board.draw_circle(ground + Vector2(0, -UNIT_H * 0.85), 8, col.lightened(0.3) * tint)
			_board.draw_circle(ground + Vector2(4 * facing[u.id], -UNIT_H * 0.86), 2, Color(0.05, 0.05, 0.08))
	if down:
		return
	# 체력 막대와 상태
	var top := ground + Vector2(0, -UNIT_H - (14 if big else 0))
	var w := 36.0
	var hp_ratio: float = float(disp_hp[u.id]) / u.max_hp
	_board.draw_rect(Rect2(top + Vector2(-w / 2 - 1, -1), Vector2(w + 2, 6)), Color(0, 0, 0, 0.8))
	_board.draw_rect(Rect2(top + Vector2(-w / 2, 0), Vector2(w * hp_ratio, 4)), Color(0.45, 0.9, 0.45) if u.side == "player" else Color(0.95, 0.35, 0.3))
	var tags := []
	if u.hidden:
		tags.append("숨")
	if u.overwatch:
		tags.append("경")
	if not tags.is_empty():
		_label_at(" ".join(tags), top + Vector2(0, -8), PixelTheme.ACCENT)
	if u.side == "player" and u.ap > 0 and battle.result == "" and not playing:
		for i in u.ap:
			_board.draw_rect(Rect2(top + Vector2(-w / 2 + i * 8, 8), Vector2(5, 5)), Color(0.4, 0.85, 0.95))
