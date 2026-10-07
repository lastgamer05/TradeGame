extends Control
## 도시 도착 장면. 도시 그림을 가리지 않게 위에 이름 띠, 아래에 들어가기 버튼만 둔다.
## 첫 방문 대화나 도착 이벤트는 main이 이 화면 위에 띄운다.

signal enter

const Kit := preload("res://scripts/ui/ui_kit.gd")


func build(state: GameState) -> void:
	var city: Dictionary = GameData.cities[state.city]
	var top := CenterContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 36
	add_child(top)
	var banner := PanelContainer.new()
	var box := PixelTheme.panel_box()
	box.bg_color.a = 0.8
	box.border_color = Kit.faction_color(city.faction).darkened(0.35)
	box.content_margin_left = 48
	box.content_margin_right = 48
	box.content_margin_top = 12
	box.content_margin_bottom = 16
	banner.add_theme_stylebox_override("panel", box)
	top.add_child(banner)
	var col := Kit.vbox(4)
	banner.add_child(col)
	var name_label := Kit.title(city.name, 48)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var first := not state.visited_cities.has(state.city)
	var sub := "%s 진영 · %d일차%s" % [GameData.factions[city.faction].name, state.day, " · 첫 방문" if first else ""]
	var sub_label := Kit.label(sub, PixelTheme.TEXT_DIM)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub_label)

	var bottom := CenterContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -72
	bottom.offset_bottom = -24
	add_child(bottom)
	var go := Kit.button("도시로 들어간다", true, func(): enter.emit())
	go.custom_minimum_size = Vector2(288, 48)
	bottom.add_child(go)

	# 등장 연출: 이름 띠가 위에서 내려오며 나타나고, 버튼은 조금 늦게 뜬다.
	banner.modulate.a = 0.0
	go.modulate.a = 0.0
	top.offset_top = 0
	var tw := create_tween().set_parallel()
	tw.tween_property(top, "offset_top", 36, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "modulate:a", 1.0, 0.7)
	tw.tween_property(go, "modulate:a", 1.0, 0.5).set_delay(0.6)
