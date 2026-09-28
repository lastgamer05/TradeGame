extends Control
## 진영 점유율 막대. 대항해시대의 항구 점유율처럼 진영 세력 비율을 한 줄로 보여 준다.

const WorldMap := preload("res://scripts/ui/world_map.gd")

var politics: Politics


func _draw() -> void:
	if politics == null:
		return
	var font := get_theme_default_font()
	var x := 0.0
	for f in politics.strength:
		var w := politics.share(f) * size.x
		var col: Color = WorldMap.FACTION_COLORS.get(f, Color.WHITE).darkened(0.2)
		draw_rect(Rect2(x, 0, w, size.y), col)
		draw_rect(Rect2(x, 0, w, size.y), Color(0, 0, 0, 0.7), false, 2.0)
		var label := "%s %d%%" % [politics.data.factions[f].name, roundi(politics.share(f) * 100)]
		draw_string(font, Vector2(x + 6, size.y / 2 + 5), label, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 12, Color(0.06, 0.05, 0.07))
		x += w
