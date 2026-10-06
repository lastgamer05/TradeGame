extends VBoxContainer
## 지금 도시의 시장 표 (구역의 거래 서비스). 사고팔기는 신호로 알리고, 처리와 기록은 main이 한다.

signal buy(good_id: String, qty: int)
signal sell(good_id: String, qty: int)

const Kit := preload("res://scripts/ui/ui_kit.gd")
const ICON_SIZE := Vector2(36, 36)


func build(state: GameState) -> void:
	add_theme_constant_override("separation", 8)
	var city: Dictionary = GameData.cities[state.city]
	# 특산(▼)과 수요(▲)는 물품 이름 옆 표시로 보여 준다.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	for h in ["", "물품", "시세", "살 때", "팔 때", "보유(평균)", "", "", ""]:
		grid.add_child(Kit.label(h, PixelTheme.TEXT_DIM))

	var for_sale: Array = state.market.goods_for_sale(state.city)
	var ids: Array = for_sale.duplicate()
	for id in state.cargo.keys() + city.demands:
		if id not in ids:
			ids.append(id)

	for id in ids:
		var g: Dictionary = GameData.goods[id]
		var name_label := Kit.label(g.name)
		if id in city.specialties:
			name_label.text += " ▼"
		elif id in city.demands:
			name_label.text += " ▲"
			name_label.add_theme_color_override("font_color", PixelTheme.ACCENT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.clip_text = true
		name_label.tooltip_text = g.name
		grid.add_child(Kit.icon(Kit.GOOD_ICON % id, ICON_SIZE))
		grid.add_child(name_label)
		var can_buy: bool = id in for_sale
		var can_sell: bool = state.market.buys(state.city, id)
		var ratio := state.market.price_ratio(state.city, id)
		var ratio_color := PixelTheme.TEXT
		if ratio < 0.85:
			ratio_color = Kit.GOOD
		elif ratio > 1.15:
			ratio_color = PixelTheme.ACCENT
		var ratio_label := Kit.label("%d%%" % roundi(ratio * 100), ratio_color)
		ratio_label.tooltip_text = "기준가 대비 시세"
		grid.add_child(ratio_label)
		grid.add_child(Kit.label(str(state.market.buy_price(state.city, id)) if can_buy else "-"))
		var owned: int = state.cargo.get(id, 0)
		var sell_label := Kit.label("-")
		if can_sell:
			var sp := state.market.sell_price(state.city, id)
			sell_label.text = str(sp)
			if owned > 0:
				var avg := state.avg_cost(id)
				sell_label.add_theme_color_override("font_color", Kit.GOOD if sp > avg else Kit.BAD)
				sell_label.tooltip_text = "평균 구입가 %d" % roundi(avg)
		else:
			sell_label.text = "거부"
		grid.add_child(sell_label)
		var owned_label := Kit.label("")
		if owned > 0:
			owned_label.text = "%d (%d)" % [owned, roundi(state.avg_cost(id))]
			owned_label.tooltip_text = "보유 수량 (평균 구입가)"
		grid.add_child(owned_label)
		var max_buy := state.max_buyable(id) if can_buy else 0
		grid.add_child(Kit.button("사기", can_buy and max_buy > 0, func(): buy.emit(id, 1)))
		grid.add_child(Kit.button("최대", can_buy and max_buy > 0, func(): buy.emit(id, max_buy)))
		grid.add_child(Kit.button("팔기", can_sell and owned > 0, func(): sell.emit(id, owned)))
