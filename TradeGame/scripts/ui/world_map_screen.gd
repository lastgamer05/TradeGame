extends HBoxContainer
## 큰 지도 화면. 도시 입구에서 연다. 왼쪽은 지도(원래 픽셀 크기로 그려 2배 확대), 오른쪽은 갈 수 있는 곳과 정세.
## 갈 수 있는 도시를 누르면 차가 달려간 뒤 travel을 보낸다.

signal travel(to: String)
signal cancel

const Kit := preload("res://scripts/ui/ui_kit.gd")
const WorldMap := preload("res://scripts/ui/world_map.gd")
## 지도 영역의 화면 폭. 짝수여야 절반 해상도가 정수로 맞는다.
const MAP_WIDTH := 776

var _board: Control
var _buttons := {}
var _busy := false


## came_from: 방금 지나온 길을 밝힐 출발 도시. 이동 중이면 버튼을 막는다.
func build(state: GameState, came_from := "") -> void:
	add_theme_constant_override("separation", 12)
	var reach := {}
	for r in state.routes_from_here():
		reach[r.to] = { "road": r.road, "days": r.days, "power": r.power, "affordable": r.power <= state.power }
	if came_from != "":
		reach = {}
	_busy = came_from != ""

	var frame := Kit.panel(1.0)
	var box := frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	box.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", box)
	frame.custom_minimum_size = Vector2(MAP_WIDTH, 0)
	add_child(frame)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 2
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(container)
	var vp := SubViewport.new()
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	vp.snap_2d_vertices_to_pixel = true
	container.add_child(vp)
	_board = WorldMap.new()
	_board.data = GameData
	_board.current_city = state.city
	_board.reach = reach
	_board.came_from = came_from
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.city_clicked.connect(_go)
	_board.city_hovered.connect(_on_hover)
	vp.add_child(_board)

	var side := Kit.panel()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(side)
	var col := Kit.vbox(8)
	side.add_child(col)
	var city: Dictionary = GameData.cities[state.city]
	col.add_child(Kit.title("큰 지도"))
	if _busy:
		col.add_child(Kit.wrap("%s에서 %s로 가는 길" % [Kit.city_name(came_from), city.name], PixelTheme.TEXT_DIM, 420))
	else:
		col.add_child(Kit.label("%s에서 출발 · %s" % [city.name, GameData.factions[city.faction].name], PixelTheme.TEXT_DIM))
		col.add_child(Kit.label("갈 수 있는 곳", PixelTheme.TEXT_DIM))
		for to in reach:
			var r: Dictionary = reach[to]
			var b := Kit.button("%s · %s %d일 · %s" % [Kit.city_name(to), Kit.ROAD_NAMES.get(r.road, r.road), r.days,
				Kit.fmt_power(r.power)], r.affordable, _go.bind(to))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not r.affordable:
				b.tooltip_text = "전력이 모자란다"
			b.mouse_entered.connect(_on_hover.bind(to))
			b.mouse_exited.connect(_on_hover.bind(""))
			col.add_child(b)
			_buttons[to] = b
	if not state.vehicle_damage.is_empty():
		var parts := state.vehicle_damage.keys().map(func(p): return GameData.combat.car.parts[p].name)
		col.add_child(Kit.wrap("차량 파손: " + ", ".join(parts), Kit.BAD, 420))

	col.add_child(Kit.spacer())
	col.add_child(_legend())
	col.add_child(Kit.politics_block(state))
	if not _busy:
		var back := Kit.button("도시로 돌아가기", true, func(): cancel.emit())
		col.add_child(back)


func _legend() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	var per_day: Dictionary = GameData.economy.travel.power_per_day
	for road in ["highway", "wasteland", "collapsed"]:
		var sample := Control.new()
		sample.custom_minimum_size = Vector2(48, 24)
		sample.draw.connect(func():
			var c: Color = WorldMap.ROAD_COLORS[road]
			var dash: Array = WorldMap.ROAD_DASH[road]
			for i in 24:
				if i % (dash[0] + dash[1]) < dash[0]:
					sample.draw_rect(Rect2(i * 2, 12, 2, 2), c))
		grid.add_child(sample)
		grid.add_child(Kit.label("%s · 하루 %d셀" % [Kit.ROAD_NAMES[road], int(per_day.get(road, 0))], PixelTheme.TEXT_DIM))
	return grid


func _on_hover(id: String) -> void:
	if _board.hover_city != id:
		_board.hover_city = id
		_board.queue_redraw()


func _go(to: String) -> void:
	if _busy:
		return
	_busy = true
	for b in _buttons.values():
		b.disabled = true
	_board.hover_city = to
	await _board.animate_travel(to)
	travel.emit(to)
