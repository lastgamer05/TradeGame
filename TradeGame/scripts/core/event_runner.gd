class_name EventRunner
extends RefCounted
## 이벤트 고르기, 선택지 조건 확인, d20 판정, 결과 적용.
## 판정: d20 + 능력치 (+ 동료 보너스) >= DC 이면 성공. 부분 성공은 아직 쓰지 않는다.
## 요구 조건과 효과는 이벤트, 대화(DialogueRunner), NPC requires, 동료 leave_if가 같이 쓴다.


## 이동을 마친 뒤 호출. 확률에 걸리면 조건에 맞는 이동 이벤트 하나를 가중치로 고른다.
static func pick_travel_event(state: GameState) -> Dictionary:
	if state.rng.randf() >= float(state.data.economy.events.travel_chance) + state.politics.travel_event_bonus():
		return {}
	return _pick(state, func(t: Dictionary):
		return t.get("on") == "travel" and (not t.has("road_types") or state.last_road in t.road_types))


## 옛 이름. pick_arrival_event와 같다.
static func pick_city_event(state: GameState) -> Dictionary:
	return pick_arrival_event(state)


## 도시에 도착했을 때 호출 (docs/city_spec.md 2.6). trigger.on "arrival" 또는 옛 "city".
## cities가 비어 있으면 모든 도시에서 뜬다.
static func pick_arrival_event(state: GameState) -> Dictionary:
	if state.rng.randf() >= float(state.data.economy.events.city_chance):
		return {}
	return _pick(state, func(t: Dictionary):
		var cities: Array = t.get("cities", [])
		return t.get("on") in ["arrival", "city"] and (cities.is_empty() or state.city in cities))


## 구역에 들어갈 때 호출. locations나 kinds 중 하나에 맞으면 후보, 둘 다 비면 모든 구역.
## 한 도시에 머무는 동안 구역 이벤트는 location_events_per_stay번까지, 같은 구역에 다시 들어가면 뜨지 않는다.
static func pick_location_event(state: GameState, location_id: String) -> Dictionary:
	var loc: Dictionary = state.data.locations.get(location_id, {})
	if loc.is_empty():
		return {}
	var cfg: Dictionary = state.data.economy.events
	if int(state.stay_visits.get(location_id, 0)) > 1:
		return {}
	if state.stay_location_events >= int(cfg.get("location_events_per_stay", 1)):
		return {}
	if state.rng.randf() >= float(cfg.get("location_chance", 0.3)):
		return {}
	return _pick(state, func(t: Dictionary):
		if t.get("on") != "location":
			return false
		var ids: Array = t.get("locations", [])
		var kinds: Array = t.get("kinds", [])
		if ids.is_empty() and kinds.is_empty():
			return true
		return location_id in ids or loc.kind in kinds)


## 이벤트를 실제로 띄울 때 화면이 부른다. 재등장 대기와 머무는 동안의 구역 이벤트 수를 센다.
static func mark_shown(state: GameState, ev: Dictionary) -> void:
	state.event_last_day[ev.id] = state.day
	if ev.get("trigger", {}).get("on") == "location":
		state.stay_location_events += 1


## 최근 cooldown_days(이벤트의 trigger.cooldown_days가 있으면 그 값) 안에 띄운 이벤트인지. trigger.once면 한 번 뜬 뒤로 다시 뜨지 않는다.
static func on_cooldown(state: GameState, ev: Dictionary) -> bool:
	if not state.event_last_day.has(ev.id):
		return false
	if ev.get("trigger", {}).get("once", false):
		return true
	var days := int(ev.get("trigger", {}).get("cooldown_days", state.data.economy.events.get("cooldown_days", 10)))
	return state.day - int(state.event_last_day[ev.id]) < days


static func _pick(state: GameState, match_trigger: Callable) -> Dictionary:
	var pool := []
	var total := 0
	for ev in state.data.events.values():
		var t: Dictionary = ev.get("trigger", {})
		if not match_trigger.call(t) or not requirements_met(state, t.get("requires", [])):
			continue
		if on_cooldown(state, ev):
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


# --- 요구 조건 ---

static func requirements_met(state: GameState, reqs: Array) -> bool:
	return first_unmet(state, reqs).is_empty()


## 맞지 않는 첫 조건. 모두 맞으면 {}.
static func first_unmet(state: GameState, reqs: Array) -> Dictionary:
	for r in reqs:
		if not _requirement_met(state, r):
			return r
	return {}


static func _requirement_met(state: GameState, r: Dictionary) -> bool:
	match r.type:
		"cargo":
			return state.cargo.get(r.good, 0) >= int(r.get("amount", 1))
		"module":
			return r.module in state.modules
		"reputation":
			return _in_range(state.reputation.get(r.city, 0), r)
		"faction_reputation":
			return _in_range(faction_reputation(state, r.faction), r)
		"flag":
			# set: false면 플래그가 없을 때 참
			return state.flags.has(r.flag) == bool(r.get("set", true))
		"crisis":
			return state.politics.active.has(r.crisis) == bool(r.get("active", true))
		"faction_share":
			return _in_range(state.politics.share(r.faction), r)
		"quest":
			var want: String = r.get("state", "active")
			if want == "ready":
				return state.quest_ready(r.quest)
			return state.quest_state(r.quest) == want
		"quest_ready":
			return state.quest_ready(r.quest)
		"companion":
			var id: String = r.get("companion", "")
			return state.companion != "" if id == "" else state.companion == id
		"day":
			return _in_range(state.day, r)
		"power":
			return _in_range(state.power, r)
	# 동물은 아직 없다.
	return false


## min, max 둘 다 받는다. 하나만 있어도 된다.
static func _in_range(value: float, r: Dictionary) -> bool:
	if r.has("min") and value < float(r.min):
		return false
	if r.has("max") and value > float(r.max):
		return false
	return true


## 같은 진영 도시 평판의 평균.
static func faction_reputation(state: GameState, faction: String) -> int:
	var sum := 0
	var n := 0
	for id in state.data.cities:
		if state.data.cities[id].faction == faction:
			sum += state.reputation[id]
			n += 1
	return sum / n if n > 0 else 0


## 조건을 플레이어에게 보여 줄 한 줄로. 선택지가 막힌 이유에 쓴다.
static func requirement_text(state: GameState, r: Dictionary) -> String:
	var d = state.data
	match r.type:
		"cargo":
			return "%s %d개가 있어야 한다" % [d.goods[r.good].name, int(r.get("amount", 1))]
		"module":
			return "%s 모듈이 있어야 한다" % d.modules[r.module].name
		"reputation":
			return "%s 평판 %s" % [d.cities[r.city].name, _range_text(r)]
		"faction_reputation":
			return "%s 평판 %s" % [d.factions[r.faction].name, _range_text(r)]
		"faction_share":
			return "%s 점유율 %s" % [d.factions[r.faction].name, _range_text(r, true)]
		"crisis":
			var name: String = _crisis_name(state, r.crisis)
			return "%s 중이어야 한다" % name if bool(r.get("active", true)) else "%s 중에는 안 된다" % name
		"quest", "quest_ready":
			var title: String = d.quests.get(r.quest, {}).get("title", r.quest)
			match "ready" if r.type == "quest_ready" else str(r.get("state", "active")):
				"none":
					return "'%s' 의뢰를 받기 전이어야 한다" % title
				"done":
					return "'%s' 의뢰를 끝내야 한다" % title
				"ready":
					return "'%s' 의뢰 목표를 채워야 한다" % title
			return "'%s' 의뢰를 맡고 있어야 한다" % title
		"companion":
			var id: String = r.get("companion", "")
			if id == "":
				return "동승자가 있어야 한다"
			return "%s 타고 있어야 한다" % josa(d.companions[id].name, "이", "가")
		"day":
			return "날짜가 %s" % _range_text(r)
		"power":
			return "전력 %s" % _range_text(r)
		"flag":
			return "아직 때가 아니다"
	return "조건이 맞지 않는다"


static func _range_text(r: Dictionary, percent := false) -> String:
	var f := func(v) -> String: return "%d%%" % roundi(float(v) * 100) if percent else str(int(v))
	if r.has("min") and r.has("max"):
		return "%s~%s 사이여야 한다" % [f.call(r.min), f.call(r.max)]
	if r.has("max"):
		return "%s 이하여야 한다" % f.call(r.max)
	return "%s 이상이어야 한다" % f.call(r.get("min", 0))


static func _crisis_name(state: GameState, crisis_id: String) -> String:
	for c in state.data.politics.get("crises", []):
		if c.id == crisis_id:
			return c.name
	return crisis_id


# --- 선택지 ---

## 선택지를 고를 수 있으면 "", 아니면 이유.
static func choice_blocker(state: GameState, choice: Dictionary) -> String:
	var unmet := first_unmet(state, choice.get("requires", []))
	if not unmet.is_empty():
		return requirement_text(state, unmet)
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
				var id: String = r.get("companion", "")
				tags.append(state.data.companions[id].name if id != "" else "동승자")
			"animal":
				tags.append("동물")
	return "" if tags.is_empty() else "[%s] " % ", ".join(tags)


## 선택지 비용을 치른다.
static func pay_cost(state: GameState, choice: Dictionary) -> void:
	for c in choice.get("cost", []):
		if c.type == "power":
			state.power -= int(c.amount)
		elif c.type == "cargo":
			state.remove_cargo(c.good, int(c.amount))


## d20 판정. 태운 동료의 bonus_stat이면 보너스를 더한다. { success, text }
static func roll_check(state: GameState, check: Dictionary) -> Dictionary:
	var stat: String = check.stat
	var d20 := state.rng.randi_range(1, 20)
	var base := int(state.stats[stat])
	var bonus := state.stat_bonus(stat)
	var total := d20 + base + bonus
	var dc := int(check.dc)
	var ok := total >= dc
	var bonus_text := ""
	if bonus != 0:
		bonus_text = " + %s %d" % [state.data.companions[state.companion].name, bonus]
	return {
		"success": ok,
		"text": "d20 %d + %s %d%s = %d  vs  DC %d  →  %s" % [
			d20, Defs.STAT_NAMES[stat], base, bonus_text, total, dc, "성공" if ok else "실패"],
	}


## 선택지를 실행한다. 비용을 치르고, 판정하고, 결과 효과를 적용한다.
## 돌려주는 값: { outcome, text, roll_text, effect_lines }
static func resolve(state: GameState, choice: Dictionary) -> Dictionary:
	pay_cost(state, choice)
	var outcome := "success"
	var roll_text := ""
	if choice.has("check"):
		var roll := roll_check(state, choice.check)
		outcome = "success" if roll.success else "failure"
		roll_text = roll.text

	var result: Dictionary = choice.outcomes.get(outcome, choice.outcomes.success)
	var lines := apply_effects(state, result.get("effects", []))
	return { "outcome": outcome, "text": result.get("text", ""), "roll_text": roll_text, "effect_lines": lines }


# --- 효과 ---

## 효과 목록을 차례로 적용하고 보여 줄 줄들을 돌려준다.
static func apply_effects(state: GameState, effects: Array) -> Array:
	var lines := []
	for eff in effects:
		_apply(state, eff, lines)
	return lines


## 효과 하나를 적용하고 플레이어에게 보여 줄 줄을 돌려준다 (여러 줄이면 줄바꿈으로 잇는다).
static func apply_effect(state: GameState, eff: Dictionary) -> String:
	var lines := []
	_apply(state, eff, lines)
	return "\n".join(lines)


static func _apply(state: GameState, eff: Dictionary, lines: Array) -> void:
	var line := _apply_one(state, eff, lines)
	if line != "":
		lines.append_array(line.split("\n"))


static func _apply_one(state: GameState, eff: Dictionary, lines: Array) -> String:
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
		"start_dialogue":
			state.pending_dialogue = eff.dialogue
		"recruit":
			return state.recruit(eff.companion)
		"dismiss":
			return state.dismiss_companion()
		"quest_start":
			if state.quest_state(eff.quest) != "none":
				return ""
			state.quests[eff.quest] = "active"
			return "의뢰 시작: %s" % d.quests[eff.quest].title
		"quest_complete":
			if state.quest_state(eff.quest) == "done":
				return ""
			var q: Dictionary = d.quests[eff.quest]
			var obj: Dictionary = q.get("objective", {})
			if obj.get("type") == "deliver":
				var n := state.remove_cargo(obj.good, int(obj.qty))
				if n > 0:
					lines.append("%s -%d (전달)" % [d.goods[obj.good].name, n])
			state.quests[eff.quest] = "done"
			lines.append("의뢰 완료: %s" % q.title)
			for r in q.get("reward", []):
				_apply(state, r, lines)
		"trust", "companion_trust":
			if state.companion == "":
				return ""
			var delta := int(eff.delta)
			state.trust[state.companion] = state.trust.get(state.companion, 0) + delta
			return "%s 신뢰 %+d" % [d.companions[state.companion].name, delta]
		"faction_strength":
			if not state.politics.strength.has(eff.faction):
				return ""
			var delta := float(eff.delta)
			state.politics.strength[eff.faction] = maxf(0.0, state.politics.strength[eff.faction] + delta)
			state.pending_news.append_array(state.politics.update_crises())
			return "%s 세력 %+d" % [d.factions[eff.faction].name, roundi(delta)]
	return ""


## 받침에 따라 조사를 붙인다. josa("이안", "이", "가") -> "이안이"
static func josa(word: String, with_final: String, without_final: String) -> String:
	if word.is_empty():
		return word
	var code := word.unicode_at(word.length() - 1)
	var has_final := code >= 0xAC00 and code <= 0xD7A3 and (code - 0xAC00) % 28 != 0
	return word + (with_final if has_final else without_final)
