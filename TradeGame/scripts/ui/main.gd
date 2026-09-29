extends Control
## 교역 루프 프로토타입 화면. UI는 코드로 만들고, 상태가 바뀔 때마다 통째로 다시 그린다.

const WorldMap := preload("res://scripts/ui/world_map.gd")
const PoliticsBar := preload("res://scripts/ui/politics_bar.gd")
const BattleView := preload("res://scripts/combat/battle_view.gd")

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
var _overlay: Control
var _modal: VBoxContainer
var _event_queue: Array = []
var _politics_bar: Control
var _crisis_label: Label
var _vehicle_box: VBoxContainer
var _battle_view: Control


func _ready() -> void:
	# 모든 그림을 절반 해상도로 만들어 2배로 보여 준다. 흐려지지 않게 최근접 필터.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PixelTheme.build()
	_build_layout()
	_new_game()


func _new_game() -> void:
	state = GameState.new(GameData)
	_log.clear()
	_event_queue.clear()
	_add_log("%s에서 출발한다. 전력 %s, 짐칸 %d칸." % [_city_name(state.city), _fmt_power(state.power), state.cargo_capacity])
	_refresh()
	_show_character_creation()


# --- 모달 창 (능력치 분배, 이벤트) ---

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	var box := PixelTheme.panel_box()
	box.bg_color.a = 0.95
	box.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)
	_modal = VBoxContainer.new()
	_modal.add_theme_constant_override("separation", 12)
	panel.add_child(_modal)


func _open_modal(title: String) -> void:
	for c in _modal.get_children():
		c.queue_free()
	var t := _label(title)
	t.add_theme_font_override("font", PixelTheme.font(true))
	t.add_theme_color_override("font_color", PixelTheme.ACCENT)
	_modal.add_child(t)
	_overlay.visible = true


func _modal_text(text: String, color := PixelTheme.TEXT) -> Label:
	var l := _label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(770, 0)
	l.add_theme_color_override("font_color", color)
	_modal.add_child(l)
	return l


func _show_character_creation() -> void:
	var cfg: Dictionary = GameData.economy.character
	var spent := 0
	for s in Defs.STATS:
		spent += state.stats[s] - int(cfg.base_stat)
	var left: int = int(cfg.bonus_points) - spent
	_open_modal("운반꾼의 능력치")
	_modal_text("판정은 d20 + 능력치가 난이도(DC) 이상이면 성공한다. 남은 포인트: %d" % left, PixelTheme.TEXT_DIM)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	_modal.add_child(grid)
	for s in Defs.STATS:
		var name_label := _label(Defs.STAT_NAMES[s])
		name_label.custom_minimum_size = Vector2(120, 0)
		grid.add_child(name_label)
		grid.add_child(_button("-", state.stats[s] > int(cfg.base_stat), _change_stat.bind(s, -1)))
		var v := _label(str(state.stats[s]))
		v.custom_minimum_size = Vector2(40, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(v)
		grid.add_child(_button("+", left > 0 and state.stats[s] < int(cfg.max_stat), _change_stat.bind(s, 1)))
	var go := _button("출발한다", left == 0, _close_modal)
	_modal.add_child(go)


func _change_stat(stat: String, delta: int) -> void:
	state.stats[stat] += delta
	_show_character_creation()


func _close_modal() -> void:
	_overlay.visible = false
	_refresh()
	_show_next_event()


func _show_next_event() -> void:
	if not state.pending_news.is_empty():
		var news: Dictionary = state.pending_news.pop_front()
		var c: Dictionary = news.crisis
		_open_modal(("정세 변화: %s" if news.started else "정세 변화: %s 종료") % c.name)
		_modal_text(c.start_text if news.started else c.end_text)
		_add_log("[정세] %s %s" % [c.name, "시작" if news.started else "종료"])
		_modal.add_child(_button("계속", true, _close_modal))
		return
	if state.pending_combat != "":
		var enc := state.pending_combat
		state.pending_combat = ""
		_start_battle(enc)
		return
	if _event_queue.is_empty():
		return
	var ev: Dictionary = _event_queue.pop_front()
	_open_modal(ev.title)
	_modal_text(ev.text)
	for ch in ev.choices:
		var blocker := EventRunner.choice_blocker(state, ch)
		var b := _button(EventRunner.choice_tags(state, ch) + ch.text, blocker == "", _on_choice.bind(ev, ch))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = blocker
		_modal.add_child(b)


func _on_choice(ev: Dictionary, ch: Dictionary) -> void:
	var r := EventRunner.resolve(state, ch)
	_add_log("[%s] %s" % [ev.title, ch.text])
	_open_modal(ev.title)
	if r.roll_text != "":
		_modal_text(r.roll_text, PixelTheme.ACCENT if r.outcome == "success" else Color(0.9, 0.45, 0.4))
	_modal_text(r.text)
	for line in r.effect_lines:
		_modal_text("· " + line, PixelTheme.TEXT_DIM)
		_add_log("  " + line)
	_modal.add_child(_button("계속", true, _close_modal))


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
	_market_grid.columns = 9
	_market_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_grid.add_theme_constant_override("h_separation", 12)
	_market_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_market_grid)

	# 오른쪽: 지도와 이동
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	var politics_panel := PanelContainer.new()
	right.add_child(politics_panel)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 6)
	politics_panel.add_child(pbox)
	var prow := HBoxContainer.new()
	pbox.add_child(prow)
	var ptitle := _label("진영 정세")
	ptitle.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	ptitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(ptitle)
	_crisis_label = _label("")
	prow.add_child(_crisis_label)
	_politics_bar = PoliticsBar.new()
	_politics_bar.custom_minimum_size = Vector2(0, 24)
	pbox.add_child(_politics_bar)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(map_panel)
	_map = WorldMap.new()
	_map.data = GameData
	_map.custom_minimum_size = Vector2(0, 150)
	map_panel.add_child(_map)
	var routes_panel := PanelContainer.new()
	right.add_child(routes_panel)
	var routes_col := VBoxContainer.new()
	routes_col.add_theme_constant_override("separation", 6)
	routes_panel.add_child(routes_col)
	_vehicle_box = VBoxContainer.new()
	routes_col.add_child(_vehicle_box)
	_routes_box = VBoxContainer.new()
	_routes_box.add_theme_constant_override("separation", 6)
	routes_col.add_child(_routes_box)

	var log_panel := PanelContainer.new()
	root.add_child(log_panel)
	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(0, 78)
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log_label.add_theme_font_size_override("font_size", PixelTheme.SIZE_SMALL * 2)
	_log_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	log_panel.add_child(_log_label)

	_build_overlay()


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
	box.add_child(_icon(UI_ICON % icon, Vector2(36, 36)))
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
	var stat_text := "  ".join(Defs.STATS.map(func(s): return "%s %d" % [Defs.STAT_NAMES[s], state.stats[s]]))
	_city_info.text = "특산 ▼ %s\n수요 ▲ %s\n평판 %+d   |   %s" % [
		_goods_names(city.specialties), _goods_names(city.demands), state.reputation[state.city], stat_text]
	_refresh_market(city)
	_refresh_routes()
	_refresh_vehicle()
	_map.current_city = state.city
	_politics_bar.politics = state.politics
	_politics_bar.queue_redraw()
	var crises := state.politics.active.values().map(func(c): return c.name)
	_crisis_label.text = ", ".join(crises) if not crises.is_empty() else "큰 사건 없음"
	_crisis_label.add_theme_color_override("font_color", PixelTheme.ACCENT if not crises.is_empty() else PixelTheme.TEXT_DIM)
	_map.queue_redraw()
	_log_label.text = "\n".join(_log.slice(-3))
	_check_stranded()


func _refresh_market(city: Dictionary) -> void:
	for c in _market_grid.get_children():
		c.queue_free()
	for h in ["", "물품", "시세", "살 때", "팔 때", "보유(평균)", "", "", ""]:
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
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.clip_text = true
		name_label.tooltip_text = g.name
		_market_grid.add_child(_icon(GOOD_ICON % id, ICON_SIZE))
		_market_grid.add_child(name_label)
		var can_buy: bool = id in for_sale
		var can_sell: bool = state.market.buys(state.city, id)
		var ratio := state.market.price_ratio(state.city, id)
		var ratio_color := PixelTheme.TEXT
		if ratio < 0.85:
			ratio_color = Color(0.55, 0.85, 0.5)
		elif ratio > 1.15:
			ratio_color = PixelTheme.ACCENT
		var ratio_label := _label("%d%%" % roundi(ratio * 100))
		ratio_label.add_theme_color_override("font_color", ratio_color)
		ratio_label.tooltip_text = "기준가 대비 시세"
		_market_grid.add_child(ratio_label)
		_market_grid.add_child(_label(str(state.market.buy_price(state.city, id)) if can_buy else "-"))
		var owned: int = state.cargo.get(id, 0)
		var sell_label := _label("-")
		if can_sell:
			var sp := state.market.sell_price(state.city, id)
			sell_label.text = str(sp)
			if owned > 0:
				var avg := state.avg_cost(id)
				sell_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.5) if sp > avg else Color(0.9, 0.45, 0.4))
				sell_label.tooltip_text = "평균 구입가 %d" % roundi(avg)
		else:
			sell_label.text = "거부"
		_market_grid.add_child(sell_label)
		var owned_label := _label("")
		if owned > 0:
			owned_label.text = "%d (%d)" % [owned, roundi(state.avg_cost(id))]
			owned_label.tooltip_text = "보유 수량 (평균 구입가)"
		_market_grid.add_child(owned_label)
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


func _refresh_vehicle() -> void:
	for c in _vehicle_box.get_children():
		c.queue_free()
	if state.vehicle_damage.is_empty():
		return
	var parts := state.vehicle_damage.keys().map(func(p): return GameData.combat.car.parts[p].name)
	var l := _label("차량 파손: " + ", ".join(parts))
	l.add_theme_color_override("font_color", Color(0.9, 0.45, 0.4))
	_vehicle_box.add_child(l)
	if state.can_repair_here():
		_vehicle_box.add_child(_button("정비소에서 수리 · %s" % _fmt_power(state.repair_cost()),
			state.repair_cost() <= state.power, _on_repair))


func _on_repair() -> void:
	var cost := state.repair_cost()
	var err := state.repair()
	_add_log("정비소에서 차를 고쳤다. 전력 -%d셀" % cost if err == "" else err)
	_refresh()


# --- 전투 ---

func _start_battle(encounter_id: String) -> void:
	var b := state.start_battle(encounter_id)
	_battle_view = BattleView.new()
	add_child(_battle_view)
	_battle_view.setup(b)
	_battle_view.finished.connect(_on_battle_finished)


func _on_battle_finished(b: Battle) -> void:
	_battle_view.queue_free()
	_battle_view = null
	var lines := state.apply_battle(b)
	_open_modal("전투 결과: %s" % BattleView.RESULT_NAMES.get(b.result, b.result))
	for line in lines:
		_modal_text("· " + line, PixelTheme.TEXT_DIM)
		_add_log("  " + line)
	_add_log("[전투] %s: %s" % [b.encounter.name, BattleView.RESULT_NAMES.get(b.result, b.result)])
	_modal.add_child(_button("계속", true, _close_modal))


func _on_buy(id: String, qty: int) -> void:
	var err := state.buy(id, qty)
	if err == "":
		var t := state.last_trade
		_add_log("%s %d개를 샀다. 전력 -%d셀%s" % [GameData.goods[id].name, qty, t.value, _trade_effects(t)])
	else:
		_add_log(err)
	_refresh()
	_show_next_event()


func _on_sell(id: String, qty: int) -> void:
	var err := state.sell(id, qty)
	if err == "":
		var t := state.last_trade
		_add_log("%s %d개를 팔았다. 전력 +%d셀 (이익 %+d)%s" % [GameData.goods[id].name, qty, t.value, t.profit, _trade_effects(t)])
	else:
		_add_log(err)
	_refresh()
	_show_next_event()


## 거래가 남긴 평판, 정세 변화를 한 줄로.
func _trade_effects(t: Dictionary) -> String:
	var parts := []
	if t.rep_delta != 0:
		parts.append("%s 평판 %+d" % [_city_name(state.city), t.rep_delta])
	if t.influence > 0.05:
		parts.append("%s 세력 +%.1f" % [GameData.factions[t.faction].name, t.influence])
	return "" if parts.is_empty() else "  ·  " + "  ·  ".join(parts)


func _on_travel(to: String) -> void:
	var err := state.travel(to)
	if err == "":
		_add_log("%s에 도착했다. %d일차." % [_city_name(to), state.day])
		for ev in [EventRunner.pick_travel_event(state), EventRunner.pick_city_event(state)]:
			if not ev.is_empty():
				_event_queue.append(ev)
	else:
		_add_log(err)
	_refresh()
	_show_next_event()


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
		_log_label.text = "\n".join(_log.slice(-3))


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
