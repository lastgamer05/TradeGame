extends Node
## 정적 게임 데이터(data/*.json)를 읽어 id로 찾을 수 있게 들고 있는 autoload.

const DATA_DIR := "res://data"
const EVENTS_DIR := "res://data/events"
const DIALOGUES_DIR := "res://data/dialogues"

var factions: Dictionary = {}
var goods: Dictionary = {}
var cities: Dictionary = {}
var modules: Dictionary = {}
var events: Dictionary = {}
var economy: Dictionary = {}
var politics: Dictionary = {}
var combat: Dictionary = {}
var locations: Dictionary = {}
var npcs: Dictionary = {}
var companions: Dictionary = {}
var quests: Dictionary = {}
var dialogues: Dictionary = {}
## 도시 id -> 거리 배치 { id, gate, ground, npc_offset, doors: { 구역 id: x }, folk: [...] }
var towns: Dictionary = {}
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
	var pol = _read_json(DATA_DIR + "/politics.json")
	politics = pol if pol is Dictionary else {}
	var cmb = _read_json(DATA_DIR + "/combat.json")
	combat = cmb if cmb is Dictionary else {}
	locations = _index(_read_json(DATA_DIR + "/locations.json"), "locations")
	npcs = _index(_read_json(DATA_DIR + "/npcs.json"), "npcs")
	companions = _index(_read_json(DATA_DIR + "/companions.json"), "companions")
	quests = _index(_read_json(DATA_DIR + "/quests.json"), "quests")
	towns = _index(_read_json(DATA_DIR + "/towns.json"), "towns")
	dialogues = {}
	for file in DirAccess.get_files_at(DIALOGUES_DIR):
		if not file.ends_with(".json"):
			continue
		var dlg = _read_json(DIALOGUES_DIR + "/" + file)
		if not dlg is Dictionary or not dlg.has("id"):
			errors.append("dialogues/%s: 대화 id가 없다" % file)
			continue
		if dlg.id + ".json" != file:
			errors.append("dialogues/%s: 파일 이름과 id '%s'가 다르다" % [file, dlg.id])
		if dialogues.has(dlg.id):
			errors.append("dialogues/%s: 대화 id 중복 '%s'" % [file, dlg.id])
		dialogues[dlg.id] = dlg
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

	for f in politics.get("start_strength", {}):
		_check_ref("politics", "start_strength", f, factions)
	for c in politics.get("crises", []):
		var where: String = "politics/" + str(c.get("id"))
		_check_ref(where, "faction", c.get("faction"), factions)
		for p in c.get("prices", []):
			for id in p.get("goods", []):
				_check_ref(where, "prices.goods", id, goods)
			if str(p.get("cities")) != "all":
				for id in p.get("cities", []):
					_check_ref(where, "prices.cities", id, cities)

	for id in combat.get("encounters", {}):
		var enc: Dictionary = combat.encounters[id]
		var where: String = "combat/" + id
		_check_ref(where, "location", enc.get("location"), combat.get("locations", {}))
		for kind in enc.get("enemies", {}):
			_check_ref(where, "enemies", kind, combat.get("enemies", {}))
		for g in enc.get("loot", {}).get("goods", {}):
			_check_ref(where, "loot.goods", g, goods)
	for id in combat.get("enemies", {}):
		_check_ref("combat/enemies/" + id, "weapon", combat.enemies[id].get("weapon"), combat.get("weapons", {}))

	for ev in events.values():
		_validate_event(ev)

	_validate_city_content()


## 구역, NPC, 동료, 의뢰, 대화 (docs/city_spec.md 2절).
func _validate_city_content() -> void:
	for t in towns.values():
		var where: String = "towns/" + t.id
		_check_ref(where, "id", t.id, cities)
		for loc_id in t.get("doors", {}):
			_check_ref(where, "doors", loc_id, locations)
			if locations.get(loc_id, {}).get("city", t.id) != t.id:
				errors.append("%s: 구역 '%s'은 이 도시에 없다" % [where, loc_id])
	var markets := {}
	for loc in locations.values():
		var where: String = "locations/" + loc.id
		_check_ref(where, "city", loc.get("city"), cities)
		if loc.get("kind") not in Defs.LOCATION_KINDS:
			errors.append("%s: 알 수 없는 kind '%s'" % [where, loc.get("kind")])
		if loc.get("kind") == "market":
			markets[loc.get("city")] = markets.get(loc.get("city"), 0) + 1
		for sv in loc.get("services", []):
			if sv not in Defs.LOCATION_SERVICES:
				errors.append("%s: 알 수 없는 service '%s'" % [where, sv])
		_check_ref(where, "npc", loc.get("npc"), npcs)
		var npc: Dictionary = npcs.get(loc.get("npc"), {})
		if not npc.is_empty() and npc.get("location") != loc.id:
			errors.append("%s: npc '%s'의 location이 이 구역이 아니다 ('%s')" % [where, npc.id, npc.get("location")])
	if not locations.is_empty():
		for id in cities:
			if markets.get(id, 0) != 1:
				errors.append("locations: 도시 '%s'의 거래 구역(kind market)이 %d곳이다 (1곳이어야 한다)" % [id, markets.get(id, 0)])

	for npc in npcs.values():
		var where: String = "npcs/" + npc.id
		_check_ref(where, "city", npc.get("city"), cities)
		_check_ref(where, "location", npc.get("location"), locations)
		var loc: Dictionary = locations.get(npc.get("location"), {})
		if not loc.is_empty() and loc.get("city") != npc.get("city"):
			errors.append("%s: 구역 '%s'은 도시 '%s'에 있다" % [where, loc.id, loc.get("city")])
		if not dialogues.has(npc.get("dialogue")):
			errors.append("%s: 대화 파일이 없다 '%s' (data/dialogues/%s.json)" % [where, npc.get("dialogue"), npc.get("dialogue")])
		if str(npc.get("companion", "")) != "":
			_check_ref(where, "companion", npc.companion, companions)
		if npc.has("faction"):
			_check_ref(where, "faction", npc.faction, factions)
		for req in npc.get("requires", []):
			_validate_requirement(where, req)

	for c in companions.values():
		var where: String = "companions/" + c.id
		_check_ref(where, "npc", c.get("npc"), npcs)
		if npcs.has(c.get("npc")) and npcs[c.npc].get("companion") != c.id:
			errors.append("%s: npc '%s'의 companion이 이 동료가 아니다" % [where, c.npc])
		if c.has("origin"):
			_check_ref(where, "origin", c.origin, factions)
		var cb: Dictionary = c.get("combat", {})
		for key in ["hp", "focus", "might", "weapon"]:
			if not cb.has(key):
				errors.append("%s: combat.%s가 없다" % [where, key])
		if cb.has("weapon"):
			_check_ref(where, "combat.weapon", cb.weapon, combat.get("weapons", {}))
		if c.has("bonus_stat") and c.bonus_stat not in Defs.STATS:
			errors.append("%s: 알 수 없는 bonus_stat '%s'" % [where, c.bonus_stat])
		for req in c.get("leave_if", []):
			_validate_requirement(where + "/leave_if", req)

	for q in quests.values():
		var where: String = "quests/" + q.id
		_check_ref(where, "giver", q.get("giver"), npcs)
		if str(q.get("title", "")) == "":
			errors.append("%s: title이 없다" % where)
		var obj: Dictionary = q.get("objective", {})
		match obj.get("type"):
			"deliver":
				_check_ref(where, "objective.good", obj.get("good"), goods)
				if int(obj.get("qty", 0)) <= 0:
					errors.append("%s: objective.qty가 0 이하" % where)
				if obj.has("location"):
					_check_ref(where, "objective.location", obj.location, locations)
			"visit":
				_check_ref(where, "objective.location", obj.get("location"), locations)
			"flag":
				if str(obj.get("flag", "")) == "":
					errors.append("%s: objective.flag가 없다" % where)
			_:
				errors.append("%s: 알 수 없는 objective.type '%s'" % [where, obj.get("type")])
		for eff in q.get("reward", []):
			_validate_effect(where + "/reward", eff)

	for dlg in dialogues.values():
		_validate_dialogue(dlg)


func _validate_dialogue(dlg: Dictionary) -> void:
	var where: String = "dialogues/" + dlg.id
	var nodes = dlg.get("nodes")
	if not nodes is Dictionary or nodes.is_empty():
		errors.append("%s: nodes가 없다" % where)
		return
	if not nodes.has(dlg.get("start")):
		errors.append("%s: start가 없는 노드를 가리킨다 '%s'" % [where, dlg.get("start")])
	var variants: Array = dlg.get("variants", [])
	for i in variants.size():
		var v: Dictionary = variants[i]
		var vw: String = "%s/variants[%d]" % [where, i]
		if not nodes.has(v.get("start")):
			errors.append("%s: start가 없는 노드를 가리킨다 '%s'" % [vw, v.get("start")])
		for req in v.get("requires", []):
			_validate_requirement(vw, req)
	for node_id in nodes:
		var node: Dictionary = nodes[node_id]
		var nw: String = "%s/%s" % [where, node_id]
		var speaker = node.get("speaker", "narrator")
		if speaker not in Defs.DIALOGUE_SPEAKERS and not npcs.has(speaker):
			errors.append("%s: speaker가 NPC id도 player/narrator도 아니다 '%s'" % [nw, speaker])
		if str(node.get("text", "")) == "":
			errors.append("%s: text가 없다" % nw)
		for eff in node.get("effects", []):
			_validate_effect(nw, eff)
		if node.has("next"):
			_check_next(nw, "next", node.next, nodes)
		var choices: Array = node.get("choices", [])
		for i in choices.size():
			var ch: Dictionary = choices[i]
			var cw: String = "%s/choices[%d]" % [nw, i]
			if str(ch.get("text", "")) == "":
				errors.append("%s: text가 없다" % cw)
			if not ch.has("next"):
				errors.append("%s: next가 없다 (대화를 끝내려면 빈 문자열)" % cw)
			_check_next(cw, "next", ch.get("next", ""), nodes)
			if ch.has("fail_next"):
				_check_next(cw, "fail_next", ch.fail_next, nodes)
			for req in ch.get("requires", []):
				_validate_requirement(cw, req)
			_validate_cost(cw, ch.get("cost", []))
			if ch.has("check"):
				_validate_check(cw, ch.check)
			elif ch.has("fail_next") or ch.has("fail_effects"):
				errors.append("%s: check가 없는데 fail_next/fail_effects가 있다" % cw)
			for eff in ch.get("effects", []):
				_validate_effect(cw, eff)
			for eff in ch.get("fail_effects", []):
				_validate_effect(cw + "/fail", eff)


func _check_next(where: String, field: String, id, nodes: Dictionary) -> void:
	if str(id) != "" and not nodes.has(id):
		errors.append("%s: %s가 없는 노드를 가리킨다 '%s'" % [where, field, id])


func _validate_cost(where: String, costs: Array) -> void:
	for cost in costs:
		if cost.get("type") not in Defs.COST_TYPES:
			errors.append("%s: 알 수 없는 cost type '%s'" % [where, cost.get("type")])
		if cost.get("type") == "cargo":
			_check_ref(where, "cost.good", cost.get("good"), goods)
		if int(cost.get("amount", 0)) <= 0:
			errors.append("%s: cost.amount가 0 이하" % where)


func _validate_check(where: String, check: Dictionary) -> void:
	if check.get("stat") not in Defs.STATS:
		errors.append("%s: 알 수 없는 stat '%s'" % [where, check.get("stat")])
	if not check.has("dc"):
		errors.append("%s: check에 dc가 없다" % where)


func _validate_event(ev: Dictionary) -> void:
	var where: String = "events/" + ev.id
	var trigger: Dictionary = ev.get("trigger", {})
	if trigger.get("on") not in Defs.EVENT_TRIGGERS:
		errors.append("%s: 알 수 없는 trigger.on '%s'" % [where, trigger.get("on")])
	for road in trigger.get("road_types", []):
		if road not in Defs.ROAD_TYPES:
			errors.append("%s: 알 수 없는 road_type '%s'" % [where, road])
	for id in trigger.get("cities", []):
		_check_ref(where + "/trigger", "cities", id, cities)
	for id in trigger.get("locations", []):
		_check_ref(where + "/trigger", "locations", id, locations)
	for kind in trigger.get("kinds", []):
		if kind not in Defs.LOCATION_KINDS:
			errors.append("%s: 알 수 없는 trigger.kinds '%s'" % [where, kind])
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
		_validate_cost(cw, ch.get("cost", []))

		var outcomes: Dictionary = ch.get("outcomes", {})
		if not outcomes.has("success"):
			errors.append("%s: success 결과가 없다" % cw)
		if ch.has("check"):
			_validate_check(cw, ch.check)
			if not outcomes.has("failure"):
				errors.append("%s: 판정 선택지에 failure 결과가 없다" % cw)
		for key in outcomes:
			if key not in Defs.OUTCOMES:
				errors.append("%s: 알 수 없는 결과 '%s'" % [cw, key])
				continue
			for eff in outcomes[key].get("effects", []):
				_validate_effect("%s/%s" % [cw, key], eff)


func _validate_requirement(where: String, req: Dictionary) -> void:
	var t = req.get("type")
	match t:
		"cargo":
			_check_ref(where, "requires.good", req.get("good"), goods)
		"module":
			_check_ref(where, "requires.module", req.get("module"), modules)
		"reputation":
			_check_ref(where, "requires.city", req.get("city"), cities)
		"faction_reputation", "faction_share":
			_check_ref(where, "requires.faction", req.get("faction"), factions)
		"flag":
			if str(req.get("flag", "")) == "":
				errors.append("%s: flag 조건에 flag가 없다" % where)
		"companion":
			if str(req.get("companion", "")) != "":
				_check_ref(where, "requires.companion", req.companion, companions)
		"crisis":
			var ids: Array = politics.get("crises", []).map(func(c): return c.get("id"))
			if req.get("crisis") not in ids:
				errors.append("%s: requires.crisis가 없는 정세 사건을 가리킨다 '%s'" % [where, req.get("crisis")])
		"quest", "quest_ready":
			_check_ref(where, "requires.quest", req.get("quest"), quests)
			if t == "quest" and str(req.get("state", "active")) not in Defs.QUEST_STATES:
				errors.append("%s: 알 수 없는 quest state '%s'" % [where, req.get("state")])
		"day", "power", "animal":
			pass
		_:
			errors.append("%s: 알 수 없는 requirement '%s'" % [where, t])
			return
	if t in ["reputation", "faction_reputation", "faction_share", "day", "power"] and not req.has("min") and not req.has("max"):
		errors.append("%s: %s 조건에 min도 max도 없다" % [where, t])


func _validate_effect(where: String, eff: Dictionary) -> void:
	var t = eff.get("type")
	if t not in Defs.EFFECT_TYPES:
		errors.append("%s: 알 수 없는 effect '%s'" % [where, t])
		return
	match t:
		"reputation":
			_check_ref(where, "effect.city", eff.get("city"), cities)
		"start_combat":
			_check_ref(where, "effect.encounter", eff.get("encounter"), combat.get("encounters", {}))
		"vehicle_damage":
			_check_ref(where, "effect.part", eff.get("part"), combat.get("car", {}).get("parts", {}))
		"cargo_add", "cargo_remove":
			_check_ref(where, "effect.good", eff.get("good"), goods)
		"flag_set", "flag_clear":
			if str(eff.get("flag", "")) == "":
				errors.append("%s: %s 효과에 flag가 없다" % [where, t])
		"start_dialogue":
			if not dialogues.has(eff.get("dialogue")):
				errors.append("%s: effect.dialogue가 없는 대화를 가리킨다 '%s' (data/dialogues/%s.json)" % [
					where, eff.get("dialogue"), eff.get("dialogue")])
		"recruit":
			_check_ref(where, "effect.companion", eff.get("companion"), companions)
		"quest_start", "quest_complete":
			_check_ref(where, "effect.quest", eff.get("quest"), quests)
		"faction_strength":
			_check_ref(where, "effect.faction", eff.get("faction"), politics.get("start_strength", {}))
	if t in ["reputation", "power", "trust", "companion_trust", "faction_strength"] and not eff.has("delta"):
		errors.append("%s: %s 효과에 delta가 없다" % [where, t])


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
