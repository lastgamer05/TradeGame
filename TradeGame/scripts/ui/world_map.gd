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


## 지도는 절반 해상도 좌표로 그리고 2배로 키워, 선과 점이 화면의 다른 픽셀 그림과 같은 크기가 되게 한다.
func _to_local(p: Vector2) -> Vector2:
	var half := size / 2
	var pad := 12.0
	return (Vector2(pad, pad) + p / 100.0 * (half - Vector2(pad, pad) * 2)).round()


func _draw() -> void:
	if data == null:
		return
	draw_set_transform(Vector2.ZERO, 0, Vector2(2, 2))
	var font := get_theme_default_font()
	for r in data.routes:
		var a := _to_local(data.positions[r.a])
		var b := _to_local(data.positions[r.b])
		var near: bool = r.a == current_city or r.b == current_city
		var col: Color = ROAD_COLORS.get(r.road, Color.WHITE)
		draw_line(a, b, col if near else col.darkened(0.55), 1.0)
	# 작은 지도라 이름은 현재 도시에만 붙인다. 갈 수 있는 도시 이름은 이동 목록에 있다.
	var named := [current_city]
	for id in data.positions:
		var p := _to_local(data.positions[id])
		var col: Color = FACTION_COLORS.get(data.cities[id].faction, Color.WHITE)
		if id == current_city:
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(9, 9)), Color.WHITE)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(7, 7)), Color(0.05, 0.04, 0.07))
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), col)
		if id not in named:
			continue
		var city_name: String = data.cities[id].name
		var w := font.get_string_size(city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tp := (p + Vector2(-w / 2, 14)).round()
		draw_string(font, tp + Vector2(1, 1), city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.8))
		draw_string(font, tp, city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
