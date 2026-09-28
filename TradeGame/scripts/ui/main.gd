extends Control
## 교역 루프 프로토타입 화면. UI는 코드로 만들고, 상태가 바뀔 때마다 통째로 다시 그린다.

const FONT_PATH := "res://assets/fonts/NanumGothic-Regular.ttf"
const WorldMap := preload("res://scripts/ui/world_map.gd")

const CATEGORY_NAMES := {
	"necessity": "생필품", "tech": "기술품", "strategic": "전략품", "info": "정보", "contraband": "금지품",
}
const ROAD_NAMES := { "highway": "간선도로", "wasteland": "황무지", "collapsed": "붕괴 구간" }

var state: GameState
var _log: Array[String] = []

var _header: Label
var _city_info: Label
var _market_grid: GridContainer
var _routes_box: VBoxContainer
var _map: Control
var _log_label: Label


func _ready() -> void:
	_apply_font()
	_build_layout()
	_new_game()


func _apply_font() -> void:
	# 웹에는 시스템 폰트가 없어서 한글 폰트를 따로 넣어야 한다. 없으면 기본 폰트를 쓴다.
	var t := Theme.new()
	t.default_font_size = 16
	if ResourceLoader.exists(FONT_PATH):
		t.default_font = load(FONT_PATH)
	theme = t


func _new_game() -> void:
	state = GameState.new(GameData)
	_log.clear()
	_add_log("%s에서 출발한다. 전력 %s, 짐칸 %d칸." % [_city_name(state.city), _fmt_power(state.power), state.cargo_capacity])
	_refresh()


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.13, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_header = Label.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_theme_font_size_override("font_size", 18)
	top.add_child(_header)
	var restart := Button.new()
	restart.text = "새 게임"
	restart.pressed.connect(_new_game)
	top.add_child(restart)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	# 왼쪽: 시장
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	body.add_child(left)
	_city_info = Label.new()
	_city_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_city_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_market_grid = GridContainer.new()
	_market_grid.columns = 8
	_market_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_grid.add_theme_constant_override("h_separation", 10)
	scroll.add_child(_market_grid)

	# 오른쪽: 지도와 이동
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_map = WorldMap.new()
	_map.data = GameData
	_map.custom_minimum_size = Vector2(0, 300)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_map)
	var routes_title := Label.new()
	routes_title.text = "이동"
	right.add_child(routes_title)
	_routes_box = VBoxContainer.new()
	right.add_child(_routes_box)

	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(0, 90)
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	root.add_child(_log_label)


func _refresh() -> void:
	var city: Dictionary = GameData.cities[state.city]
	var faction: String = GameData.factions[city.faction].name
	_header.text = "잔류전력   |   %d일차   |   %s (%s)   |   전력 %s   |   짐칸 %d/%d   |   재산 %s" % [
		state.day, city.name, faction, _fmt_power(state.power),
		state.cargo_count(), state.cargo_capacity, _fmt_power(state.net_worth())]
	_city_info.text = "특산: %s\n수요: %s" % [_goods_names(city.specialties), _goods_names(city.demands)]
	_refresh_market(city)
	_refresh_routes()
	_map.current_city = state.city
	_map.queue_redraw()
	_log_label.text = "\n".join(_log.slice(-4))
	_check_stranded()


func _refresh_market(city: Dictionary) -> void:
	for c in _market_grid.get_children():
		c.queue_free()
	for h in ["물품", "분류", "살 때(셀)", "팔 때(셀)", "보유", "", "", ""]:
		var l := _label(h)
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		_market_grid.add_child(l)

	var for_sale: Array = state.market.goods_for_sale(state.city)
	var ids: Array = for_sale.duplicate()
	for id in state.cargo.keys() + city.demands:
		if id not in ids:
			ids.append(id)

	for id in ids:
		var g: Dictionary = GameData.goods[id]
		var tag := ""
		if id in city.specialties:
			tag = " ▼"
		elif id in city.demands:
			tag = " ▲"
		_market_grid.add_child(_label(g.name + tag))
		_market_grid.add_child(_label(CATEGORY_NAMES.get(g.category, g.category)))
		var can_buy: bool = id in for_sale
		var can_sell: bool = state.market.buys(state.city, id)
		_market_grid.add_child(_label(str(state.market.buy_price(state.city, id)) if can_buy else "-"))
		_market_grid.add_child(_label(str(state.market.sell_price(state.city, id)) if can_sell else "거부"))
		var owned: int = state.cargo.get(id, 0)
		_market_grid.add_child(_label(str(owned) if owned > 0 else ""))
		var max_buy := state.max_buyable(id) if can_buy else 0
		_market_grid.add_child(_button("사기", can_buy and max_buy > 0, _on_buy.bind(id, 1)))
		_market_grid.add_child(_button("최대(%d)" % max_buy, can_buy and max_buy > 0, _on_buy.bind(id, max_buy)))
		_market_grid.add_child(_button("전부 팔기", can_sell and owned > 0, _on_sell.bind(id, owned)))


func _refresh_routes() -> void:
	for c in _routes_box.get_children():
		c.queue_free()
	for r in state.routes_from_here():
		var text := "%s  ·  %s %d일  ·  전력 %s" % [_city_name(r.to), ROAD_NAMES.get(r.road, r.road), r.days, _fmt_power(r.power)]
		_routes_box.add_child(_button(text, r.power <= state.power, _on_travel.bind(r.to)))


func _on_buy(id: String, qty: int) -> void:
	var before := state.power
	var err := state.buy(id, qty)
	if err == "":
		_add_log("%s %d개를 샀다. (전력 -%d)" % [GameData.goods[id].name, qty, before - state.power])
	else:
		_add_log(err)
	_refresh()


func _on_sell(id: String, qty: int) -> void:
	var before := state.power
	var err := state.sell(id, qty)
	if err == "":
		_add_log("%s %d개를 팔았다. (전력 +%d)" % [GameData.goods[id].name, qty, state.power - before])
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
		_log_label.text = "\n".join(_log.slice(-4))


func _add_log(msg: String) -> void:
	_log.append(msg)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


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
