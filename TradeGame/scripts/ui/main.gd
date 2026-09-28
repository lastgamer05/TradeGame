extends Control
## 교역 루프 프로토타입 화면. UI는 코드로 만들고, 상태가 바뀔 때마다 통째로 다시 그린다.

const WorldMap := preload("res://scripts/ui/world_map.gd")

const CITY_ART := "res://assets/art/cities/%s.png"
const GOOD_ICON := "res://assets/icons/goods/%s.png"
const UI_ICON := "res://assets/icons/ui/%s.png"
const ICON_SIZE := Vector2(36, 36)

const ROAD_NAMES := { "highway": "간선도로", "wasteland": "황무지", "collapsed": "붕괴 구간" }

var state: GameState
var _log: Array[String] = []

var _bg: TextureRect
var _city_title: Label
var _day_label: Label
var _power_label: Label
var _cargo_label: Label
var _worth_label: Label
var _city_info: Label
var _market_grid: GridContainer
var _routes_box: VBoxContainer
var _map: Control
var _log_label: Label


func _ready() -> void:
	theme = PixelTheme.build()
	_build_layout()
	_new_game()


func _new_game() -> void:
	state = GameState.new(GameData)
	_log.clear()
	_add_log("%s에서 출발한다. 전력 %s, 짐칸 %d칸." % [_city_name(state.city), _fmt_power(state.power), state.cargo_capacity])
	_refresh()


func _build_layout() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.1)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	# 왼쪽: 시장
	var market_panel := PanelContainer.new()
	market_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_panel.size_flags_stretch_ratio = 1.7
	body.add_child(market_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	market_panel.add_child(left)
	_city_info = Label.new()
	_city_info.add_theme_font_size_override("font_size", PixelTheme.SIZE_SMALL * 2)
	_city_info.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	left.add_child(_city_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_market_grid = GridContainer.new()
	_market_grid.columns = 8
	_market_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_grid.add_theme_constant_override("h_separation", 12)
	_market_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_market_grid)

	# 오른쪽: 지도와 이동
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	var map_panel := PanelContainer.new()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(map_panel)
	_map = WorldMap.new()
	_map.data = GameData
	_map.custom_minimum_size = Vector2(0, 220)
	map_panel.add_child(_map)
	var routes_panel := PanelContainer.new()
	right.add_child(routes_panel)
	_routes_box = VBoxContainer.new()
	_routes_box.add_theme_constant_override("separation", 6)
	routes_panel.add_child(_routes_box)

	var log_panel := PanelContainer.new()
	root.add_child(log_panel)
	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(0, 52)
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log_label.add_theme_font_size_override("font_size", PixelTheme.SIZE_SMALL * 2)
	_log_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	log_panel.add_child(_log_label)


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 20)
	panel.add_child(bar)

	var title := Label.new()
	title.text = "잔류전력"
	title.add_theme_font_override("font", PixelTheme.font(true))
	title.add_theme_color_override("font_color", PixelTheme.ACCENT)
	bar.add_child(title)
	_city_title = Label.new()
	_city_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_city_title)

	_day_label = Label.new()
	bar.add_child(_day_label)
	_power_label = _icon_stat(bar, "power_pack")
	_cargo_label = _icon_stat(bar, "cargo")
	_worth_label = Label.new()
	_worth_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	bar.add_child(_worth_label)

	var restart := Button.new()
	restart.text = "새 게임"
	restart.pressed.connect(_new_game)
	bar.add_child(restart)
	return panel


func _icon_stat(parent: Control, icon: String) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_icon(UI_ICON % icon, Vector2(32, 32)))
	var l := Label.new()
	box.add_child(l)
	parent.add_child(box)
	return l


func _refresh() -> void:
	var city: Dictionary = GameData.cities[state.city]
	_bg.texture = load(CITY_ART % state.city)
	_city_title.text = "%s  (%s)" % [city.name, GameData.factions[city.faction].name]
	_day_label.text = "%d일차" % state.day
	_power_label.text = _fmt_power(state.power)
	_cargo_label.text = "%d/%d" % [state.cargo_count(), state.cargo_capacity]
	_worth_label.text = "재산 %s" % _fmt_power(state.net_worth())
	_city_info.text = "특산 ▼ %s\n수요 ▲ %s" % [_goods_names(city.specialties), _goods_names(city.demands)]
	_refresh_market(city)
	_refresh_routes()
	_map.current_city = state.city
	_map.queue_redraw()
	_log_label.text = "\n".join(_log.slice(-2))
	_check_stranded()


func _refresh_market(city: Dictionary) -> void:
	for c in _market_grid.get_children():
		c.queue_free()
	for h in ["", "물품", "살 때", "팔 때", "보유", "", "", ""]:
		var l := _label(h)
		l.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
		_market_grid.add_child(l)

	var for_sale: Array = state.market.goods_for_sale(state.city)
	var ids: Array = for_sale.duplicate()
	for id in state.cargo.keys() + city.demands:
		if id not in ids:
			ids.append(id)

	for id in ids:
		var g: Dictionary = GameData.goods[id]
		var name_label := _label(g.name)
		if id in city.specialties:
			name_label.text += " ▼"
		elif id in city.demands:
			name_label.text += " ▲"
			name_label.add_theme_color_override("font_color", PixelTheme.ACCENT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		_market_grid.add_child(_icon(GOOD_ICON % id, ICON_SIZE))
		_market_grid.add_child(name_label)
		var can_buy: bool = id in for_sale
		var can_sell: bool = state.market.buys(state.city, id)
		_market_grid.add_child(_label(str(state.market.buy_price(state.city, id)) if can_buy else "-"))
		_market_grid.add_child(_label(str(state.market.sell_price(state.city, id)) if can_sell else "거부"))
		var owned: int = state.cargo.get(id, 0)
		_market_grid.add_child(_label(str(owned) if owned > 0 else ""))
		var max_buy := state.max_buyable(id) if can_buy else 0
		_market_grid.add_child(_button("사기", can_buy and max_buy > 0, _on_buy.bind(id, 1)))
		_market_grid.add_child(_button("최대", can_buy and max_buy > 0, _on_buy.bind(id, max_buy)))
		_market_grid.add_child(_button("팔기", can_sell and owned > 0, _on_sell.bind(id, owned)))


func _refresh_routes() -> void:
	for c in _routes_box.get_children():
		c.queue_free()
	var title := _label("이동")
	title.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	_routes_box.add_child(title)
	for r in state.routes_from_here():
		var text := "%s · %s %d일 · %s" % [_city_name(r.to), ROAD_NAMES.get(r.road, r.road), r.days, _fmt_power(r.power)]
		var b := _button(text, r.power <= state.power, _on_travel.bind(r.to))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_routes_box.add_child(b)


func _on_buy(id: String, qty: int) -> void:
	var before := state.power
	var err := state.buy(id, qty)
	if err == "":
		_add_log("%s %d개를 샀다. (전력 -%d셀)" % [GameData.goods[id].name, qty, before - state.power])
	else:
		_add_log(err)
	_refresh()


func _on_sell(id: String, qty: int) -> void:
	var before := state.power
	var err := state.sell(id, qty)
	if err == "":
		_add_log("%s %d개를 팔았다. (전력 +%d셀)" % [GameData.goods[id].name, qty, state.power - before])
	else:
		_add_log(err)
	_refresh()


func _on_travel(to: String) -> void:
	var err := state.travel(to)
	if err == "":
		_add_log("%s에 도착했다. %d일차." % [_city_name(to), state.day])
	else:
		_add_log(err)
	_refresh()


func _check_stranded() -> void:
	if not state.cargo.is_empty():
		return
	for r in state.routes_from_here():
		if r.power <= state.power:
			return
	for id in state.market.goods_for_sale(state.city):
		if state.max_buyable(id) > 0:
			return
	var msg := "전력이 바닥났다. 더는 움직일 수 없다. '새 게임'으로 다시 시작한다."
	if _log.back() != msg:
		_add_log(msg)
		_log_label.text = "\n".join(_log.slice(-2))


func _add_log(msg: String) -> void:
	_log.append(msg)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _icon(path: String, icon_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(path)
	r.custom_minimum_size = icon_size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


func _button(text: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


func _city_name(id: String) -> String:
	return GameData.cities[id].name


func _goods_names(ids: Array) -> String:
	if ids.is_empty():
		return "없음 (모든 물품을 평균가에 거래)"
	return ", ".join(ids.map(func(id): return GameData.goods[id].name))


## 셀 단위 전력을 "12팩 3셀" 형태로.
func _fmt_power(cells: int) -> String:
	var per_pack: int = GameData.economy.currency.cells_per_pack
	var packs := cells / per_pack
	var rest := cells % per_pack
	if packs == 0:
		return "%d셀" % rest
	return "%d팩 %d셀" % [packs, rest] if rest > 0 else "%d팩" % packs
