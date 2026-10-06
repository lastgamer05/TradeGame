extends HBoxContainer
## 구역 화면. 왼쪽은 구역 이름과 NPC, 오른쪽은 서비스(거래 표, 정비, 소문, 고용).
## 거래 구역이 아니면 오른쪽 위를 비워 구역 그림이 보이게 한다.

signal back
signal talk(npc_id: String)
signal buy(good_id: String, qty: int)
signal sell(good_id: String, qty: int)
signal repair

const Kit := preload("res://scripts/ui/ui_kit.gd")
const MarketPanel := preload("res://scripts/ui/market_panel.gd")
const LEFT_WIDTH := 360
const SERVICE_TEXT_WIDTH := 840


func build(state: GameState, location_id: String) -> void:
	add_theme_constant_override("separation", 12)
	var loc: Dictionary = GameData.locations[location_id]
	var left := Kit.vbox(12)
	left.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	add_child(left)

	var info := Kit.panel()
	left.add_child(info)
	info.add_child(Kit.title(loc.name))

	var npc := state.npc_at(location_id)
	if not npc.is_empty():
		left.add_child(_npc_panel(state, npc))
	left.add_child(Kit.spacer())
	left.add_child(Kit.button("거리로 나간다", true, func(): back.emit()))

	var right := Kit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	if "trade" in loc.services:
		var mp := Kit.panel()
		mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right.add_child(mp)
		var market := MarketPanel.new()
		market.build(state)
		market.buy.connect(func(id, qty): buy.emit(id, qty))
		market.sell.connect(func(id, qty): sell.emit(id, qty))
		mp.add_child(market)
		return
	right.add_child(Kit.spacer())
	for s in loc.services:
		match s:
			"repair":
				right.add_child(_repair_panel(state))
			"rumors":
				right.add_child(_rumor_panel(state))
			"recruit":
				right.add_child(_service_panel("용병 고용", ["아직 고용할 용병이 없다."]))


func _npc_panel(state: GameState, npc: Dictionary) -> Control:
	var p := Kit.panel()
	var row := Kit.hbox(12)
	p.add_child(row)
	row.add_child(Kit.portrait(npc))
	var col := Kit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(Kit.label(npc.name))
	var dlg: String = npc.get("dialogue", "")
	var can_talk := dlg != "" and GameData.dialogues.has(dlg)
	var b := Kit.button("대화", can_talk, func(): talk.emit(npc.id))
	if not can_talk:
		b.tooltip_text = "지금은 할 말이 없다"
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(96, 0)
	col.add_child(b)
	return p


func _service_panel(title: String, lines: Array) -> PanelContainer:
	var p := Kit.panel(0.85)
	var col := Kit.vbox(6)
	p.add_child(col)
	col.add_child(Kit.title(title))
	for line in lines:
		col.add_child(Kit.wrap(line, PixelTheme.TEXT, SERVICE_TEXT_WIDTH))
	return p


func _repair_panel(state: GameState) -> Control:
	var p := _service_panel("정비", [])
	var col: VBoxContainer = p.get_child(0)
	if state.vehicle_damage.is_empty():
		col.add_child(Kit.label("차에 손볼 곳이 없다.", PixelTheme.TEXT_DIM))
		return p
	var parts := state.vehicle_damage.keys().map(func(part): return GameData.combat.car.parts[part].name)
	col.add_child(Kit.wrap("차량 파손: " + ", ".join(parts), Kit.BAD, SERVICE_TEXT_WIDTH))
	var cost := state.repair_cost()
	var b := Kit.button("수리한다 · %s" % Kit.fmt_power(cost), cost <= state.power, func(): repair.emit())
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(b)
	return p


func _rumor_panel(state: GameState) -> Control:
	return _service_panel("소문", rumor_lines(state))


## 쓸모 있는 소문: 진행 중인 정세 사건, 여기서 사서 남길 수 있는 물건, 싣고 있는 물건의 가장 좋은 판로.
static func rumor_lines(state: GameState) -> Array:
	var lines := []
	for c in state.politics.active.values():
		var sentences: PackedStringArray = str(c.start_text).split(". ", false)
		lines.append("「%s」 %s" % [c.name, sentences[sentences.size() - 1].trim_suffix(".") + "."])
	var best := _best_deal(state, state.market.goods_for_sale(state.city))
	if not best.is_empty():
		lines.append("%s: 여기 %d셀, %s %d셀." % [
			GameData.goods[best.good].name, best.buy, Kit.city_name(best.city), best.sell])
	for good_id in state.cargo:
		if not best.is_empty() and good_id == best.good:
			continue
		var top_city := ""
		for city_id in GameData.cities:
			if state.market.buys(city_id, good_id) and (top_city == ""
					or state.market.sell_price(city_id, good_id) > state.market.sell_price(top_city, good_id)):
				top_city = city_id
		if top_city != "" and top_city != state.city:
			lines.append("싣고 있는 %s: %s에서 %d셀." % [
				GameData.goods[good_id].name, Kit.city_name(top_city), state.market.sell_price(top_city, good_id)])
			break
	if lines.is_empty():
		lines.append("요즘은 조용하다.")
	return lines.slice(0, 2)


## 주어진 물품 중 다른 도시에 팔 때 가장 많이 남는 것. { good, buy, city, sell }
static func _best_deal(state: GameState, goods: Array) -> Dictionary:
	var best := {}
	var best_gain := 0
	for good_id in goods:
		var bp := state.market.buy_price(state.city, good_id)
		for city_id in GameData.cities:
			if city_id == state.city or not state.market.buys(city_id, good_id):
				continue
			var sp := state.market.sell_price(city_id, good_id)
			if sp - bp > best_gain:
				best_gain = sp - bp
				best = { "good": good_id, "buy": bp, "city": city_id, "sell": sp }
	return best
