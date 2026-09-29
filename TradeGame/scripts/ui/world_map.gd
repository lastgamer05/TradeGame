extends Control
## 큰 지도의 판. 원래 픽셀 크기(화면의 절반)로 그리고 world_map_screen이 SubViewport로 정확히 2배 확대한다.
## 좌표는 data/routes.json의 0~100 값. 도로는 1픽셀 선을 직접 찍어 그린다 (간선도로 실선, 황무지 긴 점선, 붕괴 구간 점선).

signal city_clicked(id: String)
signal city_hovered(id: String)

const ROAD_COLORS := {
	"highway": Color(0.78, 0.8, 0.86),
	"wasteland": Color(0.9, 0.58, 0.3),
	"collapsed": Color(0.66, 0.46, 0.88),
}
## 켜진 픽셀, 꺼진 픽셀 반복
const ROAD_DASH := { "highway": [1, 0], "wasteland": [4, 2], "collapsed": [1, 2] }
const FACTION_COLORS := {
	"victor": Color(0.95, 0.8, 0.3),
	"rebel": Color(0.9, 0.3, 0.35),
	"displaced": Color(0.45, 0.8, 0.45),
	"lawless": Color(0.6, 0.6, 0.6),
	"neutral": Color(0.4, 0.7, 0.95),
}
const PAD := Vector2(40, 24)
const BG := Color(0.075, 0.07, 0.1)
const GRID := Color(0.11, 0.105, 0.14)
const TEXT := Color(0.9, 0.87, 0.8)
const DIM := Color(0.5, 0.48, 0.46)
const ACCENT := Color(1.0, 0.72, 0.32)
const BAD := Color(0.9, 0.45, 0.4)

var data
var current_city: String = ""
## 갈 수 있는 도시 id -> { road, days, power, affordable }
var reach: Dictionary = {}
var hover_city: String = ""
## 방금 지나온 길의 출발 도시. 이동 이벤트를 보여 주는 동안 그 길을 밝힌다.
var came_from: String = ""
## 이동 애니메이션: 0~1, 음수면 없음
var car_t := -1.0
var car_to: String = ""

var _font: Font


func _ready() -> void:
	_font = PixelTheme.font()
	mouse_filter = Control.MOUSE_FILTER_STOP


func to_map(p: Vector2) -> Vector2:
	return (PAD + p / 100.0 * (size - PAD * 2)).round()


func city_at(p: Vector2) -> String:
	for id in data.positions:
		if to_map(data.positions[id]).distance_to(p) <= 9:
			return id
	return ""


## 도시까지 차가 달려가는 모습을 보여 준다.
func animate_travel(to: String) -> void:
	car_to = to
	var tw := create_tween()
	tw.tween_method(func(t): car_t = t; queue_redraw(), 0.0, 1.0, 0.7)
	await tw.finished


func _gui_input(ev: InputEvent) -> void:
	if car_t >= 0:
		return
	if ev is InputEventMouseMotion:
		var id := city_at(ev.position)
		if id != hover_city:
			hover_city = id
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if reach.has(id) else Control.CURSOR_ARROW
			city_hovered.emit(id)
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var id := city_at(ev.position)
		if reach.has(id) and reach[id].affordable:
			city_clicked.emit(id)


func _draw() -> void:
	if data == null:
		return
	_draw_ground()
	for r in data.routes:
		_draw_road(r)
	if car_t >= 0:
		var a := to_map(data.positions[current_city])
		var b := to_map(data.positions[car_to])
		var p := a.lerp(b, car_t).round()
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Color(0.05, 0.04, 0.07))
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), ACCENT)
	for id in data.positions:
		_draw_city(id)
	for id in data.positions:
		_draw_city_label(id)


func _draw_ground() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for x in range(8, int(size.x), 16):
		draw_rect(Rect2(x, 0, 1, size.y), GRID)
	for y in range(8, int(size.y), 16):
		draw_rect(Rect2(0, y, size.x, 1), GRID)
	# 진영 영역: 반투명 원을 겹쳐 깔끔한 색 단계를 만든다
	for id in data.positions:
		var col: Color = FACTION_COLORS.get(data.cities[id].faction, Color.WHITE)
		col.a = 0.045
		var p := to_map(data.positions[id])
		for rad in [46, 32, 20]:
			draw_circle(p, rad, col)


func _draw_road(r: Dictionary) -> void:
	var a := to_map(data.positions[r.a])
	var b := to_map(data.positions[r.b])
	var col: Color = ROAD_COLORS.get(r.road, Color.WHITE)
	var near: bool = r.a == current_city or r.b == current_city
	var other: String = r.b if r.a == current_city else r.a
	var lit := near and (other == hover_city or other == came_from or other == car_to)
	if lit:
		col = col.lightened(0.35)
	elif not near:
		col = col.darkened(0.6)
	var dash: Array = ROAD_DASH.get(r.road, [1, 0])
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	var period: int = dash[0] + dash[1]
	for i in steps + 1:
		if i % period >= dash[0]:
			continue
		var p := a.lerp(b, float(i) / maxf(steps, 1)).round()
		draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p, Vector2.ONE), col)
		if lit or (near and r.road == "highway"):
			draw_rect(Rect2(p + Vector2(1, 0), Vector2.ONE), col)


func _draw_city(id: String) -> void:
	var p := to_map(data.positions[id])
	var col: Color = FACTION_COLORS.get(data.cities[id].faction, Color.WHITE)
	var active := id == current_city or reach.has(id)
	if not active:
		col = col.darkened(0.45)
	if id == current_city:
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(11, 11)), TEXT)
		# 현재 위치 표시: 위를 가리키는 작은 삼각형
		for i in 3:
			draw_rect(Rect2(p + Vector2(-2 + i, -12 + i), Vector2(5 - i * 2, 1)), ACCENT)
	elif id == hover_city and reach.has(id):
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(11, 11)), ACCENT)
	draw_rect(Rect2(p - Vector2(4, 4), Vector2(9, 9)), Color(0.05, 0.04, 0.07))
	draw_rect(Rect2(p - Vector2(3, 3), Vector2(7, 7)), col)
	draw_rect(Rect2(p - Vector2(3, 3), Vector2(7, 1)), col.lightened(0.35))


func _draw_city_label(id: String) -> void:
	var p := to_map(data.positions[id])
	var active := id == current_city or reach.has(id)
	var lines := [[data.cities[id].name, TEXT if active else DIM]]
	if reach.has(id):
		var r: Dictionary = reach[id]
		lines.append(["%d일 · %d셀" % [r.days, r.power], ACCENT if r.affordable else BAD])
	var y := p.y + 8
	for line in lines:
		var w := _font.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tp := Vector2(roundf(p.x - w / 2), y + 10)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(_font, tp + o, line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.03, 0.025, 0.04))
		draw_string(_font, tp, line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, line[1])
		y += 13
