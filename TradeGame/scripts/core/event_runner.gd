class_name EventRunner
extends RefCounted
## 이벤트 고르기, 선택지 조건 확인, d20 판정, 결과 적용.
## 판정: d20 + 능력치 >= DC 이면 성공. 부분 성공은 아직 쓰지 않는다.


## 이동을 마친 뒤 호출. 확률에 걸리면 조건에 맞는 이동 이벤트 하나를 가중치로 고른다.
static func pick_travel_event(state: GameState) -> Dictionary:
	if state.rng.randf() >= float(state.data.economy.events.travel_chance) + state.politics.travel_event_bonus():
		return {}
	return _pick(state, func(t: Dictionary):
		return t.get("on") == "travel" and (not t.has("road_types") or state.last_road in t.road_types))


## 도시에 도착했을 때 호출.
static func pick_city_event(state: GameState) -> Dictionary:
	if state.rng.randf() >= float(state.data.economy.events.city_chance):
		return {}
	return _pick(state, func(t: Dictionary):
		return t.get("on") == "city" and state.city in t.get("cities", []))


static func _pick(state: GameState, match_trigger: Callable) -> Dictionary:
	var pool := []
	var total := 0
	for ev in state.data.events.values():
		var t: Dictionary = ev.get("trigger", {})
		if not match_trigger.call(t) or not requirements_met(state, t.get("requires", [])):
			continue
		var w := int(t.get("weight", 1))
		pool.append([ev, w])
		total += w
	if total == 0:
		return {}
	var roll := state.rng.randi_range(1, total)
	for entry in pool:
		roll -= entry[1]
		if roll <= 0:
			return entry[0]
	return {}


static func requirements_met(state: GameState, reqs: Array) -> bool:
	for r in reqs:
		if not _requirement_met(state, r):
			return false
	return true


static func _requirement_met(state: GameState, r: Dictionary) -> bool:
	match r.type:
		"cargo":
			return state.cargo.get(r.good, 0) >= int(r.get("amount", 1))
		"module":
			return r.module in state.modules
		"reputation":
			return state.reputation.get(r.city, 0) >= int(r.get("min", 0))
		"faction_reputation":
			return faction_reputation(state, r.faction) >= int(r.get("min", 0))
		"flag":
			return state.flags.has(r.flag)
	# 동승자, 동물은 아직 없다.
	return false


## 같은 진영 도시 평판의 평균.
static func faction_reputation(state: GameState, faction: String) -> int:
	var sum := 0
	var n := 0
	for id in state.data.cities:
		if state.data.cities[id].faction == faction:
			sum += state.reputation[id]
			n += 1
	return sum / n if n > 0 else 0


## 선택지를 고를 수 있으면 "", 아니면 이유.
static func choice_blocker(state: GameState, choice: Dictionary) -> String:
	if not requirements_met(state, choice.get("requires", [])):
		return "조건이 맞지 않는다"
	for c in choice.get("cost", []):
		if c.type == "power" and state.power < int(c.amount):
			return "전력이 모자란다"
		if c.type == "cargo" and state.cargo.get(c.good, 0) < int(c.amount):
			return "화물이 모자란다"
	return ""


## 선택지 앞에 붙는 태그. 예) [교섭 DC 15], [전력 1팩], [밀수칸]
static func choice_tags(state: GameState, choice: Dictionary) -> String:
	var tags := []
	if choice.has("check"):
		tags.append("%s DC %d" % [Defs.STAT_NAMES[choice.check.stat], int(choice.check.dc)])
	for c in choice.get("cost", []):
		if c.type == "power":
			tags.append("전력 %d셀" % int(c.amount))
		elif c.type == "cargo":
			tags.append("%s %d개" % [state.data.goods[c.good].name, int(c.amount)])
	for r in choice.get("requires", []):
		match r.type:
			"module":
				tags.append(state.data.modules[r.module].name)
			"cargo":
				tags.append(state.data.goods[r.good].name)
			"reputation":
				tags.append("%s 우호" % state.data.cities[r.city].name)
			"faction_reputation":
				tags.append("%s 우호" % state.data.factions[r.faction].name)
			"companion":
				tags.append("동승자")
			"animal":
				tags.append("동물")
	return "" if tags.is_empty() else "[%s] " % ", ".join(tags)


## 선택지를 실행한다. 비용을 치르고, 판정하고, 결과 효과를 적용한다.
## 돌려주는 값: { outcome, text, roll_text, effect_lines }
static func resolve(state: GameState, choice: Dictionary) -> Dictionary:
	for c in choice.get("cost", []):
		if c.type == "power":
			state.power -= int(c.amount)
		elif c.type == "cargo":
			state.remove_cargo(c.good, int(c.amount))

	var outcome := "success"
	var roll_text := ""
	if choice.has("check"):
		var stat: String = choice.check.stat
		var d20 := state.rng.randi_range(1, 20)
		var total: int = d20 + int(state.stats[stat])
		var dc := int(choice.check.dc)
		outcome = "success" if total >= dc else "failure"
		roll_text = "d20 %d + %s %d = %d  vs  DC %d  →  %s" % [
			d20, Defs.STAT_NAMES[stat], state.stats[stat], total, dc, "성공" if outcome == "success" else "실패"]

	var result: Dictionary = choice.outcomes.get(outcome, choice.outcomes.success)
	var lines := []
	for eff in result.get("effects", []):
		var line := apply_effect(state, eff)
		if line != "":
			lines.append(line)
	return { "outcome": outcome, "text": result.get("text", ""), "roll_text": roll_text, "effect_lines": lines }


## 효과 하나를 적용하고 플레이어에게 보여 줄 한 줄을 돌려준다.
static func apply_effect(state: GameState, eff: Dictionary) -> String:
	var d = state.data
	match eff.type:
		"reputation":
			state.add_reputation(eff.city, int(eff.delta))
			return "%s 평판 %+d" % [d.cities[eff.city].name, int(eff.delta)]
		"power":
			var before := state.power
			state.power = maxi(0, state.power + int(eff.delta))
			return "전력 %+d셀" % (state.power - before)
		"cargo_add":
			var n := state.add_cargo(eff.good, int(eff.amount))
			if n < int(eff.amount):
				return "%s +%d (짐칸이 모자라 %d개는 버렸다)" % [d.goods[eff.good].name, n, int(eff.amount) - n]
			return "%s +%d" % [d.goods[eff.good].name, n]
		"cargo_remove":
			var qty := -1 if str(eff.amount) == "all" else int(eff.amount)
			var n := state.remove_cargo(eff.good, qty)
			return "%s -%d" % [d.goods[eff.good].name, n] if n > 0 else ""
		"flag_set":
			state.flags[eff.flag] = true
		"flag_clear":
			state.flags.erase(eff.flag)
		"vehicle_damage":
			return state.damage_vehicle(eff.part)
		"start_combat":
			state.pending_combat = eff.encounter
			return "전투가 벌어진다: %s" % d.combat.encounters[eff.encounter].name
		"companion_trust":
			return "동승자 신뢰 변화 (미구현)"
	return ""
