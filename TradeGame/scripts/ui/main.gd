extends Control
## 게임 화면의 뼈대. 윗줄(날짜, 전력, 화물, 재산)은 늘 보이고, 그 아래 화면을 흐름에 따라 바꾼다.
## 큰 지도 -> 도착 장면 -> 도시 허브 -> 구역 (docs/city_spec.md 1절). 모달(이벤트, 정세 소식, 전투 결과),
## 전투, 대화는 모든 화면 위에 뜬다. 상태가 바뀔 때마다 지금 화면을 통째로 다시 만든다.
## 픽셀 퍼펙트: 모든 그림은 절반 해상도로 만들어 최근접 필터로 정확히 2배 보여 준다.

const BattleView := preload("res://scripts/combat/battle_view.gd")
const DialogueView := preload("res://scripts/ui/dialogue_view.gd")
const Kit := preload("res://scripts/ui/ui_kit.gd")
const WorldMapScreen := preload("res://scripts/ui/world_map_screen.gd")
const ArrivalView := preload("res://scripts/ui/arrival_view.gd")
const CityHubView := preload("res://scripts/ui/city_hub_view.gd")
const LocationView := preload("res://scripts/ui/location_view.gd")

const CITY_ART := "res://assets/art/cities/%s.png"
const LOCATION_ART := "res://assets/art/locations/%s.png"
## 화면마다 배경 그림을 어둡게 누르는 정도
const SHADE := { "arrival": 0.0, "hub": 0.15, "location": 0.15, "map": 0.6 }

var state: GameState
## 지금 화면: "arrival", "hub", "location", "map"
var screen := "arrival"
var _log: Array[String] = []
var _event_queue: Array = []
## 모달, 전투, 대화가 모두 끝나면 차례로 부를 일 (이동을 마친 뒤 도착 장면 등)
var _then: Array[Callable] = []
## 이동 이벤트를 보여 주는 동안 큰 지도에 밝힐 출발 도시
var _travel_from := ""

var _bg: TextureRect
var _shade: ColorRect
var _city_title: Label
var _companion_label: Label
var _day_label: Label
var _power_label: Label
var _cargo_label: Label
var _worth_label: Label
var _body: Control
var _log_panel: PanelContainer
var _log_label: Label
var _overlay: Control
var _modal: VBoxContainer
var _battle_view: Control
var _dialogue_view: Control


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PixelTheme.build()
	_build_layout()
	_new_game()


func _new_game() -> void:
	for v in [_battle_view, _dialogue_view]:
		if v != null:
			v.queue_free()
	_battle_view = null
	_dialogue_view = null
	state = GameState.new(GameData)
	_log.clear()
	_event_queue.clear()
	_then.clear()
	_travel_from = ""
	screen = "arrival"
	_add_log("%s에서 출발한다. 전력 %s, 짐칸 %d칸." % [Kit.city_name(state.city), Kit.fmt_power(state.power), state.cargo_capacity])
	# 시작 도시 안에서 시작한다: 짐칸이 빈 채로 큰 지도부터 보면 할 일이 없다.
	_then.append(_show_arrival.bind(false))
	_refresh()
	_show_character_creation()


# --- 화면 흐름 ---

## 도착 장면. 첫 방문이면 도착 대화, 아니면 도착 이벤트를 굴린다.
func _show_arrival(roll_event := true) -> void:
	state.leave_location()
	screen = "arrival"
	_refresh()
	var dlg := "arrival_" + state.city
	if not state.visited_cities.has(state.city) and GameData.dialogues.has(dlg):
		_open_dialogue(dlg)
	elif roll_event:
		var ev := EventRunner.pick_arrival_event(state)
		if not ev.is_empty():
			_event_queue.append(ev)
		_show_next_event()


func _enter_city() -> void:
	state.visited_cities[state.city] = true
	_travel_from = ""
	_enter_hub()


func _enter_hub() -> void:
	if state.location != "":
		state.leave_location()
	screen = "hub"
	_refresh()


func _open_location(location_id: String) -> void:
	state.enter_location(location_id)
	screen = "location"
	_refresh()
	var ev := EventRunner.pick_location_event(state, location_id)
	if not ev.is_empty():
		_event_queue.append(ev)
	_show_next_event()


func _open_map() -> void:
	state.leave_location()
	screen = "map"
	_refresh()


func _on_travel(to: String) -> void:
	var from := state.city
	var err := state.travel(to)
	if err != "":
		_add_log(err)
		_refresh()
		return
	_travel_from = from
	_add_log("%s에 도착했다. %d일차." % [Kit.city_name(to), state.day])
	var ev := EventRunner.pick_travel_event(state)
	if not ev.is_empty():
		_event_queue.append(ev)
	_then.append(_show_arrival)
	_refresh()
	_show_next_event()


func _on_talk(npc_id: String) -> void:
	_open_dialogue(GameData.npcs[npc_id].dialogue)


func _open_dialogue(dialogue_id: String) -> void:
	_dialogue_view = DialogueView.new()
	add_child(_dialogue_view)
	_dialogue_view.finished.connect(_on_dialogue_finished)
	_dialogue_view.start(state, dialogue_id)


func _on_dialogue_finished() -> void:
	_dialogue_view = null
	_refresh()
	_show_next_event()


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
	Kit.clear(_modal)
	_modal.add_child(Kit.title(title))
	_overlay.visible = true


func _modal_text(text: String, color := PixelTheme.TEXT) -> Label:
	var l := Kit.wrap(text, color, 770)
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
		var name_label := Kit.label(Defs.STAT_NAMES[s])
		name_label.custom_minimum_size = Vector2(120, 0)
		grid.add_child(name_label)
		grid.add_child(Kit.button("-", state.stats[s] > int(cfg.base_stat), _change_stat.bind(s, -1)))
		var v := Kit.label(str(state.stats[s]))
		v.custom_minimum_size = Vector2(40, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(v)
		grid.add_child(Kit.button("+", left > 0 and state.stats[s] < int(cfg.max_stat), _change_stat.bind(s, 1)))
	_modal.add_child(Kit.button("출발한다", left == 0, _close_modal))


func _change_stat(stat: String, delta: int) -> void:
	state.stats[stat] += delta
	_show_character_creation()


func _close_modal() -> void:
	_overlay.visible = false
	_refresh()
	_show_next_event()


## 밀린 일을 하나씩 보여 준다: 정세 소식, 전투, 대화, 이벤트. 다 끝나면 _then을 부른다.
func _show_next_event() -> void:
	if _overlay.visible or _battle_view != null or _dialogue_view != null:
		return
	if not state.pending_news.is_empty():
		var news: Dictionary = state.pending_news.pop_front()
		var c: Dictionary = news.crisis
		_open_modal(("정세 변화: %s" if news.started else "정세 변화: %s 종료") % c.name)
		_modal_text(c.start_text if news.started else c.end_text)
		_add_log("[정세] %s %s" % [c.name, "시작" if news.started else "종료"])
		_modal.add_child(Kit.button("계속", true, _close_modal))
		return
	# 동료가 떠나는 것 같은 알림 (엔진의 pending_notices: { type, title, text, ... })
	if "pending_notices" in state and not state.get("pending_notices").is_empty():
		var n: Dictionary = state.get("pending_notices").pop_front()
		_open_modal(n.get("title", "알림"))
		_modal_text(n.get("text", ""))
		_add_log("[알림] %s" % n.get("title", ""))
		_modal.add_child(Kit.button("계속", true, _close_modal))
		return
	if state.pending_combat != "":
		var enc := state.pending_combat
		state.pending_combat = ""
		_start_battle(enc)
		return
	# 엔진이 이벤트 결과로 대화를 걸어 두면 연다 (start_dialogue 효과).
	if "pending_dialogue" in state and str(state.get("pending_dialogue")) != "":
		var dlg: String = state.get("pending_dialogue")
		state.set("pending_dialogue", "")
		if GameData.dialogues.has(dlg):
			_open_dialogue(dlg)
			return
	if not _event_queue.is_empty():
		var ev: Dictionary = _event_queue.pop_front()
		_open_modal(ev.title)
		_modal_text(ev.text)
		for ch in ev.choices:
			var blocker := EventRunner.choice_blocker(state, ch)
			var b := Kit.button(EventRunner.choice_tags(state, ch) + ch.text, blocker == "", _on_choice.bind(ev, ch))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = blocker
			_modal.add_child(b)
		return
	if not _then.is_empty():
		_then.pop_front().call()


func _on_choice(ev: Dictionary, ch: Dictionary) -> void:
	var r := EventRunner.resolve(state, ch)
	_add_log("[%s] %s" % [ev.title, ch.text])
	_open_modal(ev.title)
	if r.roll_text != "":
		_modal_text(r.roll_text, PixelTheme.ACCENT if r.outcome == "success" else Kit.BAD)
	_modal_text(r.text)
	for line in r.effect_lines:
		_modal_text("· " + line, PixelTheme.TEXT_DIM)
		_add_log("  " + line)
	_modal.add_child(Kit.button("계속", true, _close_modal))


# --- 틀 ---

func _build_layout() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)

	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.1)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := Kit.vbox(12)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)
	root.add_child(_build_top_bar())

	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_body)

	_log_panel = PanelContainer.new()
	root.add_child(_log_panel)
	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(0, 52)
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	_log_panel.add_child(_log_label)

	_build_overlay()


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	var bar := Kit.hbox(20)
	panel.add_child(bar)
	bar.add_child(Kit.title("잔류전력"))
	_city_title = Label.new()
	_city_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_city_title.clip_text = true
	bar.add_child(_city_title)
	_companion_label = Kit.label("", PixelTheme.TEXT_DIM)
	bar.add_child(_companion_label)
	_day_label = Label.new()
	bar.add_child(_day_label)
	_power_label = _icon_stat(bar, "power_pack")
	_cargo_label = _icon_stat(bar, "cargo")
	_worth_label = Kit.label("", PixelTheme.TEXT_DIM)
	bar.add_child(_worth_label)
	bar.add_child(Kit.button("새 게임", true, _new_game))
	return panel


func _icon_stat(parent: Control, icon: String) -> Label:
	var box := Kit.hbox(4)
	box.add_child(Kit.icon(Kit.UI_ICON % icon, Vector2(36, 36)))
	var l := Label.new()
	box.add_child(l)
	parent.add_child(box)
	return l


func _refresh() -> void:
	var city: Dictionary = GameData.cities[state.city]
	match screen:
		"location":
			var loc: Dictionary = GameData.locations[state.location]
			_city_title.text = "%s · %s" % [city.name, loc.name]
		"map":
			_city_title.text = "큰 지도"
		_:
			_city_title.text = "%s  (%s)" % [city.name, GameData.factions[city.faction].name]
	var comp: Dictionary = GameData.companions.get(state.companion, {})
	_companion_label.text = "동료 " + comp.name if not comp.is_empty() else ""
	_companion_label.visible = not comp.is_empty()
	_day_label.text = "%d일차" % state.day
	_power_label.text = Kit.fmt_power(state.power)
	_cargo_label.text = "%d/%d" % [state.cargo_count(), state.cargo_capacity]
	_worth_label.text = "재산 %s" % Kit.fmt_power(state.net_worth())
	_refresh_background()
	_build_screen()
	_log_panel.visible = screen in ["hub", "location"]
	_log_label.text = "\n".join(_log.slice(-2))
	_check_stranded()


func _refresh_background() -> void:
	var tex: Texture2D = load(CITY_ART % state.city)
	var shade: float = SHADE.get(screen, 0.1)
	if screen == "location":
		var loc_tex := Kit.texture_or_null(LOCATION_ART % state.location)
		if loc_tex != null:
			tex = loc_tex
		else:
			shade = 0.45
	_bg.texture = tex
	_shade.color = Color(0.02, 0.015, 0.03, shade)


func _build_screen() -> void:
	Kit.clear(_body)
	var view: Control
	match screen:
		"arrival":
			view = ArrivalView.new()
			view.enter.connect(_enter_city)
		"hub":
			view = CityHubView.new()
			view.open_location.connect(_open_location)
			view.open_gate.connect(_open_map)
		"location":
			view = LocationView.new()
			view.back.connect(_enter_hub)
			view.talk.connect(_on_talk)
			view.buy.connect(_on_buy)
			view.sell.connect(_on_sell)
			view.repair.connect(_on_repair)
		"map":
			view = WorldMapScreen.new()
			view.travel.connect(_on_travel)
			view.cancel.connect(_enter_hub)
	_body.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	match screen:
		"location":
			view.build(state, state.location)
		"map":
			view.build(state, _travel_from)
		_:
			view.build(state)


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
	_modal.add_child(Kit.button("계속", true, _close_modal))


# --- 거래 ---

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
		parts.append("%s 평판 %+d" % [Kit.city_name(state.city), t.rep_delta])
	if t.influence > 0.05:
		parts.append("%s 세력 +%.1f" % [GameData.factions[t.faction].name, t.influence])
	return "" if parts.is_empty() else "  ·  " + "  ·  ".join(parts)


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
