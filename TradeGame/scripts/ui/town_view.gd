extends Control
## 도시 거리. 옆에서 본 거리를 주인공이 좌우로 걸어 다닌다 (도시 허브를 대신한다).
## 구역 입구 앞에 그 구역 NPC가 서 있고, 왼쪽 끝은 도시 입구(큰 지도)다. 다가가면 머리 위에 이름이 뜨고
## E(또는 클릭)로 들어가거나 말을 건다. 거리 데이터는 data/towns.json, 그림은 assets/art/towns/와 assets/town/.
## 픽셀 퍼펙트: 640x360 SubViewport에 1:1로 그리고 정확히 2배로 보여 준다. 글자는 바깥(원래 해상도)에 그린다.

signal open_location(location_id: String)
signal open_gate
signal talk(npc_id: String)
## 주인공이 멈춘 자리 (화면을 다시 만들어도 같은 자리에서 시작하려고 main이 기억한다)
signal moved(x: float)

const Kit := preload("res://scripts/ui/ui_kit.gd")
const VIEW := Vector2(640, 360)
const PX := 2
const STREET_ART := "res://assets/art/towns/%s.png"
const CITY_ART := "res://assets/art/cities/%s.png"
const PLAYER_ART := "res://assets/town/player_%d.png"
const NPC_ART := "res://assets/town/npcs/%s.png"
const FOLK_ART := "res://assets/town/folk/%s.png"
const WALK_SPEED := 90.0
const FOLK_SPEED := 22.0
## 이만큼 가까우면 상호작용 대상이 된다 (원래 픽셀)
const REACH := 22.0
const STEP_TIME := 0.14

var _state: GameState
var _town: Dictionary
var _width := 640.0
var _ground := 330.0
## { kind: "gate"|"door"|"npc", x, id, name, sub, mark, node }
var _spots: Array = []
var _player: Sprite2D
var _player_frames: Array[Texture2D] = []
var _player_x := 0.0
var _target_x := -1.0
## 걸어간 뒤 할 일 (클릭한 대상)
var _pending: Dictionary = {}
var _step := 0.0
var _cam: Camera2D
var _folk: Array = []
var _focus: Dictionary = {}
var _tag: PanelContainer
var _tag_name: Label
var _tag_sub: Label
var _info: Control
var _was_moving := false
## 참이면 걷기와 입력을 멈춘다 (main이 모달·대화·전투 중에 참을 돌려주는 함수를 넣는다)
var blocked: Callable = func(): return false


func build(state: GameState, start_x := -1.0) -> void:
	_state = state
	_town = GameData.towns.get(state.city, {})
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var tex := Kit.texture_or_null(STREET_ART % state.city)
	if tex == null:
		tex = load(CITY_ART % state.city)
		_width = VIEW.x
	else:
		_width = tex.get_width()
	_ground = float(_town.get("ground", 330))
	_build_world(tex)
	_build_spots()
	_build_overlay()
	var gate_x := float(_town.get("gate", 40))
	_player_x = clampf(start_x if start_x >= 0.0 else gate_x + 36.0, 12.0, _width - 12.0)
	_place_player()
	_update_focus()
	grab_focus.call_deferred()


func _build_world(tex: Texture2D) -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = PX
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	vp.snap_2d_vertices_to_pixel = true
	container.add_child(vp)
	var world := Node2D.new()
	vp.add_child(world)
	var bg := Sprite2D.new()
	bg.texture = tex
	bg.centered = false
	world.add_child(bg)
	if tex.get_height() < VIEW.y:
		bg.scale = Vector2.ONE * VIEW.y / tex.get_height()
	_cam = Camera2D.new()
	_cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(_width)
	_cam.limit_bottom = int(VIEW.y)
	world.add_child(_cam)
	_cam.make_current()

	for i in 4:
		var t := Kit.texture_or_null(PLAYER_ART % i)
		if t != null:
			_player_frames.append(t)
	for name in _town.get("folk", []):
		var ft := Kit.texture_or_null(FOLK_ART % name)
		if ft == null:
			continue
		var f := Sprite2D.new()
		f.texture = ft
		f.centered = false
		f.modulate = Color(0.82, 0.8, 0.88)
		world.add_child(f)
		var x := randf_range(80.0, _width - 80.0)
		_folk.append({ "node": f, "x": x, "dir": 1.0 if randf() < 0.5 else -1.0,
			"speed": FOLK_SPEED * randf_range(0.7, 1.3), "y": _ground - 4.0 - randf_range(0, 6) })
	_player = Sprite2D.new()
	_player.centered = false
	world.add_child(_player)
	if _player_frames.is_empty():
		_player.texture = _placeholder(Color(0.55, 0.38, 0.25), 16, 40)
	else:
		_player.texture = _player_frames[0]
	set_meta("world", world)


## 거리의 상호작용 지점: 도시 입구, 구역 입구, 입구 앞 NPC.
func _build_spots() -> void:
	var world: Node2D = get_meta("world")
	_spots.append({ "kind": "gate", "x": float(_town.get("gate", 40)), "id": "",
		"name": "도시 입구", "sub": "큰 지도로" })
	var locs := _state.locations_here()
	var xs := _spot_xs(locs)
	for i in locs.size():
		var loc: Dictionary = locs[i]
		var x: float = xs[i]
		var tags: Array = []
		for s in loc.services:
			tags.append(Kit.SERVICE_NAMES.get(s, s))
		_spots.append({ "kind": "door", "x": x, "id": loc.id, "name": loc.name,
			"sub": " · ".join(tags) if not tags.is_empty() else "들어가기" })
		var npc := _state.npc_at(loc.id)
		if npc.is_empty():
			continue
		var nx := x + float(_town.get("npc_offset", 34))
		var s := Sprite2D.new()
		s.centered = false
		var tex := Kit.texture_or_null(NPC_ART % npc.id)
		s.texture = tex if tex != null else _placeholder(Kit.faction_color(npc.get("faction", "")).darkened(0.3), 16, 40)
		s.position = Vector2(roundf(nx - s.texture.get_width() / 2.0), roundf(_ground - s.texture.get_height()))
		s.flip_h = nx > _width / 2.0
		world.add_child(s)
		var dlg: String = npc.get("dialogue", "")
		if dlg == "" or not GameData.dialogues.has(dlg):
			continue
		_spots.append({ "kind": "npc", "x": nx, "id": npc.id, "name": npc.name,
			"sub": _npc_mark(npc), "node": s })
	world.move_child(_player, -1)


## 구역 입구 위치. towns.json에 없으면 거리 폭에 고르게 놓는다.
func _spot_xs(locs: Array) -> Array:
	var given: Dictionary = _town.get("doors", {})
	var xs := []
	for i in locs.size():
		if given.has(locs[i].id):
			xs.append(float(given[locs[i].id]))
		else:
			xs.append(lerpf(140.0, _width - 70.0, float(i) / maxf(1.0, locs.size() - 1)))
	return xs


func _npc_mark(npc: Dictionary) -> String:
	for q in GameData.quests.values():
		if q.get("giver") != npc.id:
			continue
		if _state.quest_ready(q.id):
			return "! 의뢰 보고"
		if _state.quests.get(q.id, "") == "active":
			return "의뢰 진행 중"
	if npc.get("companion", "") != "" and _state.companion != npc.companion:
		return "동료 후보"
	return str(npc.get("role", ""))


func _build_overlay() -> void:
	_tag = PanelContainer.new()
	var box := PixelTheme.panel_box()
	box.bg_color.a = 0.85
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 6
	_tag.add_theme_stylebox_override("panel", box)
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tag)
	var col := Kit.vbox(0)
	_tag.add_child(col)
	_tag_name = Kit.label("", PixelTheme.ACCENT)
	_tag_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_tag_name)
	_tag_sub = Kit.label("", PixelTheme.TEXT_DIM)
	_tag_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_tag_sub)

	var hint := Kit.label("←→ 걷기   E 들어가기·말 걸기   Tab 도시 정보", PixelTheme.TEXT_DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -36)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	_info = _city_info()
	_info.visible = false
	add_child(_info)


## Tab으로 여닫는 도시 정보: 진영, 평판, 특산·수요, 의뢰, 차량, 정세.
func _city_info() -> Control:
	var city: Dictionary = GameData.cities[_state.city]
	var p := Kit.panel(0.92)
	p.position = Vector2(16, 92)
	p.custom_minimum_size = Vector2(380, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Kit.vbox(6)
	p.add_child(col)
	var rep: int = _state.reputation[_state.city]
	col.add_child(Kit.label("%s 진영 · 평판 %+d" % [GameData.factions[city.faction].name, rep], Kit.faction_color(city.faction)))
	col.add_child(Kit.wrap("싸다 " + Kit.goods_names(city.specialties), PixelTheme.TEXT_DIM, 352))
	col.add_child(Kit.wrap("비싸다 " + Kit.goods_names(city.demands), PixelTheme.TEXT_DIM, 352))
	var active: Array = _state.quests.keys().filter(func(q): return _state.quests[q] == "active" and GameData.quests.has(q))
	for q in active.slice(0, 2):
		col.add_child(Kit.wrap("의뢰: " + GameData.quests[q].title, PixelTheme.ACCENT, 352))
	if not _state.vehicle_damage.is_empty():
		var parts := _state.vehicle_damage.keys().map(func(part): return GameData.combat.car.parts[part].name)
		col.add_child(Kit.wrap("차량 파손: " + ", ".join(parts), Kit.BAD, 352))
	col.add_child(Kit.politics_block(_state))
	return p


func _process(delta: float) -> void:
	if _state == null:
		return
	if blocked.call():
		_target_x = -1.0
		_pending = {}
		_move_folk(delta)
		return
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir += 1.0
	if dir != 0.0:
		_target_x = -1.0
		_pending = {}
	elif _target_x >= 0.0:
		var gap := _target_x - _player_x
		if absf(gap) <= WALK_SPEED * delta:
			_player_x = _target_x
			_target_x = -1.0
			if not _pending.is_empty():
				var spot := _pending
				_pending = {}
				_update_focus()
				_activate(spot)
				return
		else:
			dir = signf(gap)
	var moving := dir != 0.0
	if moving:
		_player_x = clampf(_player_x + dir * WALK_SPEED * delta, 8.0, _width - 8.0)
		_player.flip_h = dir < 0.0
		_step += delta
	else:
		_step = 0.0
	if _was_moving and not moving:
		moved.emit(_player_x)
	_was_moving = moving
	_place_player()
	_move_folk(delta)
	_update_focus()


func _place_player() -> void:
	if not _player_frames.is_empty():
		# 멈춰 있으면 두 발을 모은 그림(1번)
		var frame := 1 if _step == 0.0 else int(_step / STEP_TIME) % _player_frames.size()
		_player.texture = _player_frames[frame]
	var tex := _player.texture
	_player.position = Vector2(roundf(_player_x - tex.get_width() / 2.0), roundf(_ground + 2.0 - tex.get_height()))
	var cam_x := clampf(_player_x - VIEW.x / 2.0, 0.0, maxf(0.0, _width - VIEW.x))
	_cam.position = Vector2(roundf(cam_x), 0)


func _move_folk(delta: float) -> void:
	for f in _folk:
		f.x += f.dir * f.speed * delta
		if f.x < 20.0 or f.x > _width - 20.0:
			f.dir = -f.dir
		var n: Sprite2D = f.node
		n.flip_h = f.dir < 0.0
		n.position = Vector2(roundf(f.x - n.texture.get_width() / 2.0), roundf(f.y - n.texture.get_height()))


## 가장 가까운 지점이 손 닿는 거리면 이름표를 띄운다.
func _update_focus() -> void:
	var best := {}
	var best_d := REACH
	for s in _spots:
		var d: float = absf(s.x - _player_x)
		if d <= best_d:
			best = s
			best_d = d
	_focus = best
	_tag.visible = not best.is_empty()
	if best.is_empty():
		return
	_tag_name.text = best.name
	_tag_sub.text = best.sub
	_tag_sub.visible = best.sub != ""
	_tag_sub.add_theme_color_override("font_color", PixelTheme.ACCENT if best.sub.begins_with("!") else PixelTheme.TEXT_DIM)
	_tag.reset_size()
	var head_y := _ground - 58.0
	if best.has("node"):
		head_y = (best.node as Sprite2D).position.y - 4.0
	var screen_x: float = (best.x - _cam.position.x) * PX
	_tag.position = Vector2(roundf(clampf(screen_x - _tag.size.x / 2.0, 8.0, size.x - _tag.size.x - 8.0)),
		roundf(head_y * PX - _tag.size.y - 8.0))


func _activate(spot: Dictionary) -> void:
	match spot.kind:
		"gate":
			open_gate.emit()
		"door":
			open_location.emit(spot.id)
		"npc":
			talk.emit(spot.id)


func _gui_input(event: InputEvent) -> void:
	if blocked.call():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var wx: float = event.position.x / PX + _cam.position.x
		var wy: float = event.position.y / PX
		var hit := _spot_at(wx, wy)
		if not hit.is_empty() and absf(hit.x - _player_x) <= REACH:
			_activate(hit)
		elif not hit.is_empty():
			_target_x = hit.x
			_pending = hit
		else:
			_target_x = clampf(wx, 8.0, _width - 8.0)
			_pending = {}
		accept_event()


## 클릭한 자리의 대상. NPC는 그림 범위, 입구와 도시 입구는 그 언저리 거리 위쪽.
func _spot_at(wx: float, wy: float) -> Dictionary:
	for s in _spots:
		if s.has("node"):
			var n: Sprite2D = s.node
			if Rect2(n.position, n.texture.get_size()).grow(3).has_point(Vector2(wx, wy)):
				return s
	for s in _spots:
		if s.kind != "npc" and absf(s.x - wx) <= 18.0 and wy < _ground - 8.0:
			return s
	return {}


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or blocked.call():
		return
	match event.keycode:
		KEY_E, KEY_SPACE, KEY_ENTER, KEY_UP, KEY_W:
			if not _focus.is_empty():
				_handled()
				_activate(_focus)
		KEY_TAB:
			_handled()
			_info.visible = not _info.visible


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func player_x() -> float:
	return _player_x


static func _placeholder(color: Color, w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
