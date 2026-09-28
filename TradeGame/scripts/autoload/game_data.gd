extends Node
## 정적 게임 데이터(data/*.json)를 읽어 id로 찾을 수 있게 들고 있는 autoload.

const DATA_DIR := "res://data"
const EVENTS_DIR := "res://data/events"

var factions: Dictionary = {}
var goods: Dictionary = {}
var cities: Dictionary = {}
var modules: Dictionary = {}
var events: Dictionary = {}
var economy: Dictionary = {}
## 도시 간 도로. { a, b, road, days }
var routes: Array = []
## 도시 id -> Vector2 (0~100 지도 좌표)
var positions: Dictionary = {}

## 읽기나 검증 중 생긴 오류. 비어 있으면 데이터가 정상이다.
var errors: PackedStringArray = []


func _ready() -> void:
	load_all()
	for e in errors:
		push_error("GameData: " + e)


func load_all() -> void:
	errors.clear()
	factions = _index(_read_json(DATA_DIR + "/factions.json"), "factions")
	goods = _index(_read_json(DATA_DIR + "/goods.json"), "goods")
	cities = _index(_read_json(DATA_DIR + "/cities.json"), "cities")
	modules = _index(_read_json(DATA_DIR + "/modules.json"), "modules")
	var econ = _read_json(DATA_DIR + "/economy.json")
	economy = econ if econ is Dictionary else {}
	var map = _read_json(DATA_DIR + "/routes.json")
	routes = map.get("routes", []) if map is Dictionary else []
	positions = {}
	if map is Dictionary:
		for id in map.get("positions", {}):
			var p: Array = map.positions[id]
			positions[id] = Vector2(p[0], p[1])
	events = {}
	for file in DirAccess.get_files_at(EVENTS_DIR):
		if not file.ends_with(".json"):
			continue
		var ev = _read_json(EVENTS_DIR + "/" + file)
		if not ev is Dictionary or not ev.has("id"):
			errors.append("%s: 이벤트 id가 없다" % file)
			continue
		if events.has(ev.id):
			errors.append("%s: 이벤트 id 중복 '%s'" % [file, ev.id])
		events[ev.id] = ev
	validate()


func validate() -> void:
	for g in goods.values():
		if g.get("category") not in Defs.GOOD_CATEGORIES:
			errors.append("goods/%s: 알 수 없는 category '%s'" % [g.id, g.get("category")])
		if float(g.get("base_price", 0)) <= 0:
			errors.append("goods/%s: base_price가 0 이하" % g.id)

	for c in cities.values():
		var where: String = "cities/" + c.id
		_check_ref(where, "faction", c.get("faction"), factions)
		for id in c.get("specialties", []):
			_check_ref(where, "specialties", id, goods)
		for id in c.get("demands", []):
			_check_ref(where, "demands", id, goods)
			if id in c.get("specialties", []):
				errors.append("%s: '%s'가 특산과 수요에 둘 다 있다" % [where, id])
		if not positions.has(c.id):
			errors.append("%s: 지도 좌표가 없다" % where)

	for r in routes:
		var where: String = "routes/%s-%s" % [r.get("a"), r.get("b")]
		_check_ref(where, "a", r.get("a"), cities)
		_check_ref(where, "b", r.get("b"), cities)
		if r.get("road") not in Defs.ROAD_TYPES:
			errors.append("%s: 알 수 없는 road '%s'" % [where, r.get("road")])
		if int(r.get("days", 0)) <= 0:
			errors.append("%s: days가 0 이하" % where)

	for ev in events.values():
		_validate_event(ev)


func _validate_event(ev: Dictionary) -> void:
	var where: String = "events/" + ev.id
	var trigger: Dictionary = ev.get("trigger", {})
	if trigger.get("on") not in Defs.EVENT_TRIGGERS:
		errors.append("%s: 알 수 없는 trigger.on '%s'" % [where, trigger.get("on")])
	for road in trigger.get("road_types", []):
		if road not in Defs.ROAD_TYPES:
			errors.append("%s: 알 수 없는 road_type '%s'" % [where, road])
	for req in trigger.get("requires", []):
		_validate_requirement(where + "/trigger", req)

	var choices: Array = ev.get("choices", [])
	if choices.is_empty():
		errors.append("%s: 선택지가 없다" % where)
	var seen := {}
	for ch in choices:
		var cw: String = "%s/%s" % [where, ch.get("id", "?")]
		if seen.has(ch.get("id")):
			errors.append("%s: 선택지 id 중복" % cw)
		seen[ch.get("id")] = true
		for req in ch.get("requires", []):
			_validate_requirement(cw, req)
		for cost in ch.get("cost", []):
			if cost.get("type") not in Defs.COST_TYPES:
				errors.append("%s: 알 수 없는 cost type '%s'" % [cw, cost.get("type")])
			if cost.get("type") == "cargo":
				_check_ref(cw, "cost.good", cost.get("good"), goods)

		var outcomes: Dictionary = ch.get("outcomes", {})
		if not outcomes.has("success"):
			errors.append("%s: success 결과가 없다" % cw)
		if ch.has("check"):
			if ch.check.get("stat") not in Defs.STATS:
				errors.append("%s: 알 수 없는 stat '%s'" % [cw, ch.check.get("stat")])
			if not ch.check.has("dc"):
				errors.append("%s: check에 dc가 없다" % cw)
			if not outcomes.has("failure"):
				errors.append("%s: 판정 선택지에 failure 결과가 없다" % cw)
		for key in outcomes:
			if key not in Defs.OUTCOMES:
				errors.append("%s: 알 수 없는 결과 '%s'" % [cw, key])
				continue
			for eff in outcomes[key].get("effects", []):
				_validate_effect("%s/%s" % [cw, key], eff)


func _validate_requirement(where: String, req: Dictionary) -> void:
	match req.get("type"):
		"cargo":
			_check_ref(where, "requires.good", req.get("good"), goods)
		"module":
			_check_ref(where, "requires.module", req.get("module"), modules)
		"reputation":
			_check_ref(where, "requires.city", req.get("city"), cities)
		"faction_reputation":
			_check_ref(where, "requires.faction", req.get("faction"), factions)
		"flag", "companion", "animal":
			pass
		_:
			errors.append("%s: 알 수 없는 requirement '%s'" % [where, req.get("type")])


func _validate_effect(where: String, eff: Dictionary) -> void:
	var t = eff.get("type")
	if t not in Defs.EFFECT_TYPES:
		errors.append("%s: 알 수 없는 effect '%s'" % [where, t])
		return
	match t:
		"reputation":
			_check_ref(where, "effect.city", eff.get("city"), cities)
		"cargo_add", "cargo_remove":
			_check_ref(where, "effect.good", eff.get("good"), goods)


func _check_ref(where: String, field: String, id, table: Dictionary) -> void:
	if not table.has(id):
		errors.append("%s: %s가 없는 id를 가리킨다 '%s'" % [where, field, id])


func _index(list, label: String) -> Dictionary:
	var out := {}
	if not list is Array:
		errors.append("%s: 배열이 아니다" % label)
		return out
	for item in list:
		if not item is Dictionary or not item.has("id"):
			errors.append("%s: id 없는 항목" % label)
			continue
		if out.has(item.id):
			errors.append("%s: id 중복 '%s'" % [label, item.id])
		out[item.id] = item
	return out


func _read_json(path: String):
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: 파일을 읽을 수 없다" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
