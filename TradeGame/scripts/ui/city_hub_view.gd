extends HBoxContainer
## 도시 허브. 왼쪽은 도시 형편(진영, 평판, 특산·수요, 동료, 정세), 오른쪽은 구역 카드 4장과 도시 입구.

signal open_location(location_id: String)
signal open_gate

const Kit := preload("res://scripts/ui/ui_kit.gd")
const STATUS_WIDTH := 360
## 구역 카드의 글 폭: (허브 오른쪽 폭 876 - 간격 12) / 2 - 여백 24 - 초상화 100 - 간격 12
const CARD_TEXT_WIDTH := 296


func build(state: GameState) -> void:
	add_theme_constant_override("separation", 12)
	add_child(_status(state))

	var right := Kit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	right.add_child(grid)
	for loc in state.locations_here():
		grid.add_child(_card(state, loc))

	var gate := Kit.button("도시 입구  ·  큰 지도에서 다음 목적지를 고른다", true, func(): open_gate.emit())
	gate.custom_minimum_size = Vector2(0, 48)
	right.add_child(gate)


func _status(state: GameState) -> Control:
	var city: Dictionary = GameData.cities[state.city]
	var p := Kit.panel()
	p.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	var col := Kit.vbox(6)
	p.add_child(col)
	col.add_child(Kit.title(city.name))
	var rep: int = state.reputation[state.city]
	col.add_child(Kit.label("%s 진영" % GameData.factions[city.faction].name, Kit.faction_color(city.faction)))
	col.add_child(Kit.label("평판 %+d (%s)" % [rep, Kit.reputation_word(rep)]))
	col.add_child(Kit.wrap("특산 ▼ " + Kit.goods_names(city.specialties), PixelTheme.TEXT_DIM, STATUS_WIDTH - 28))
	col.add_child(Kit.wrap("수요 ▲ " + Kit.goods_names(city.demands), PixelTheme.TEXT_DIM, STATUS_WIDTH - 28))
	if state.companion != "" and GameData.companions.has(state.companion):
		col.add_child(Kit.label("동료: %s (신뢰 %d)" % [GameData.companions[state.companion].name,
			int(state.trust.get(state.companion, 0))]))
	var active: Array = state.quests.keys().filter(func(q): return state.quests[q] == "active" and GameData.quests.has(q))
	for q in active.slice(0, 2):
		col.add_child(Kit.wrap("의뢰: " + GameData.quests[q].title, PixelTheme.ACCENT, STATUS_WIDTH - 28))
	if not state.vehicle_damage.is_empty():
		var parts := state.vehicle_damage.keys().map(func(part): return GameData.combat.car.parts[part].name)
		col.add_child(Kit.wrap("차량 파손: " + ", ".join(parts), Kit.BAD, STATUS_WIDTH - 28))
	col.add_child(Kit.spacer())
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 24)
	for s in Defs.STATS:
		stats.add_child(Kit.label("%s %d" % [Defs.STAT_NAMES[s], state.stats[s]], PixelTheme.TEXT_DIM))
	col.add_child(stats)
	col.add_child(Kit.politics_block(state))
	return p


## 구역 카드. 카드 전체가 버튼이다.
func _card(state: GameState, loc: Dictionary) -> Control:
	var card := Button.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 150)
	var normal := PixelTheme.panel_box()
	normal.bg_color.a = 0.8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = PixelTheme.ACCENT
	hover.bg_color = Color(0.1, 0.085, 0.09, 0.88)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.pressed.connect(func(): open_location.emit(loc.id))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(margin)
	var row := Kit.hbox(12)
	margin.add_child(row)
	var npc := state.npc_at(loc.id)
	if not npc.is_empty():
		row.add_child(Kit.portrait(npc))
	var col := Kit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(Kit.title(loc.name))
	var tags: Array = [Kit.KIND_NAMES.get(loc.kind, loc.kind)]
	for s in loc.services:
		tags.append(Kit.SERVICE_NAMES.get(s, s))
	col.add_child(Kit.label(" · ".join(tags), PixelTheme.TEXT_DIM))
	if not npc.is_empty():
		col.add_child(Kit.label(npc.name))
		var role := Kit.label(npc.get("role", ""), PixelTheme.TEXT_DIM)
		role.clip_text = true
		role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(role)
		var mark := _npc_mark(state, npc)
		if mark != "":
			col.add_child(Kit.label(mark, PixelTheme.ACCENT))
	else:
		col.add_child(Kit.label("아무도 없다", PixelTheme.TEXT_DIM))
	if str(loc.get("description", "")) != "":
		var desc := Kit.wrap(loc.description, PixelTheme.TEXT_DIM, CARD_TEXT_WIDTH)
		desc.max_lines_visible = 2
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(desc)
	_ignore_mouse(margin)
	return card


## 의뢰 완료 가능, 진행 중인 의뢰, 동료 후보 표시.
func _npc_mark(state: GameState, npc: Dictionary) -> String:
	for q in GameData.quests.values():
		if q.get("giver") != npc.id:
			continue
		if state.quest_ready(q.id):
			return "! 의뢰 보고"
		if state.quests.get(q.id, "") == "active":
			return "… 의뢰 진행 중"
	if npc.get("companion", "") != "" and state.companion != npc.companion:
		return "+ 동료 후보"
	return ""


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse(c)
