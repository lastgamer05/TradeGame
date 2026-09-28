extends Control
## 도시와 도로를 그리는 간단한 지도. 좌표는 data/routes.json의 0~100 값.

var data
var current_city: String = ""

const ROAD_COLORS := {
	"highway": Color(0.75, 0.75, 0.8),
	"wasteland": Color(0.85, 0.55, 0.3),
	"collapsed": Color(0.6, 0.4, 0.8),
}
const FACTION_COLORS := {
	"victor": Color(0.95, 0.8, 0.3),
	"rebel": Color(0.9, 0.3, 0.35),
	"displaced": Color(0.45, 0.8, 0.45),
	"lawless": Color(0.6, 0.6, 0.6),
	"neutral": Color(0.4, 0.7, 0.95),
}


func _to_local(p: Vector2) -> Vector2:
	var pad := 24.0
	return Vector2(pad, pad) + p / 100.0 * (size - Vector2(pad, pad) * 2)


func _draw() -> void:
	if data == null:
		return
	var font := get_theme_default_font()
	for r in data.routes:
		var a := _to_local(data.positions[r.a])
		var b := _to_local(data.positions[r.b])
		var near: bool = r.a == current_city or r.b == current_city
		var col: Color = ROAD_COLORS.get(r.road, Color.WHITE)
		draw_line(a, b, col if near else col.darkened(0.55), 3.0 if near else 1.5)
		draw_string(font, (a + b) / 2 + Vector2(4, -4), "%d일" % r.days, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.darkened(0.2))
	for id in data.positions:
		var p := _to_local(data.positions[id])
		var col: Color = FACTION_COLORS.get(data.cities[id].faction, Color.WHITE)
		if id == current_city:
			draw_circle(p, 11, Color.WHITE)
		draw_circle(p, 8, col)
		draw_string(font, p + Vector2(-60, 24), data.cities[id].name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color.WHITE)
