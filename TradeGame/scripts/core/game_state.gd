class_name GameState
extends RefCounted
## 한 판의 진행 상태: 전력, 화물, 현재 도시, 날짜, 시세.
## 행동 함수는 실패하면 이유 문자열을, 성공하면 빈 문자열을 돌려준다.

var power: int
var cargo: Dictionary = {}
var cargo_capacity: int
var city: String
var day: int = 1
var market: Market
## 능력치 id -> 값. 판정은 d20 + 값 >= DC.
var stats: Dictionary = {}
## 도시 id -> 평판 (-100~100)
var reputation: Dictionary = {}
## 이벤트가 남기는 플래그. 값은 항상 true.
var flags: Dictionary = {}
## 장착한 차량 모듈 id 목록
var modules: Array = []
## 마지막 이동에 쓴 도로 종류. 이동 이벤트 선택에 쓴다.
var last_road: String = ""
## 진영 정세
var politics: Politics
## 물품 id -> 지금 가진 수량을 사는 데 든 총 전력. 평균 구입가 계산용.
var cost_basis: Dictionary = {}
## 마지막 거래의 결과. { good, qty, value, profit, rep_delta, faction, influence }
var last_trade: Dictionary = {}
## 아직 화면에 알리지 않은 정세 변화. [{ crisis, started }]
var pending_news: Array = []
## 파손된 차량 부위 id -> true. 정비소에서 고친다.
var vehicle_damage: Dictionary = {}
## 이벤트가 시작시킨 전투 encounter id. 화면이 전투를 띄우고 비운다.
var pending_combat: String = ""
## --- 도시 탐방 (docs/city_spec.md 4절) ---
## 지금 있는 구역, 도시 허브면 ""
var location: String = ""
## 태운 동료 id. 한 번에 한 명.
var companion: String = ""
## 동료 id -> 신뢰
var trust: Dictionary = {}
## 의뢰 id -> "active" | "done". 없으면 받기 전.
var quests: Dictionary = {}
## visit 목표를 채운 의뢰 id -> true
var quest_visited: Dictionary = {}
## 도시 id -> true (첫 도착 대화용)
var visited_cities: Dictionary = {}
## 이벤트 결과의 start_dialogue 효과가 남긴 대화 id. 화면이 결과 창을 닫은 뒤 대화를 열고 비운다.
## (대화 안에서 쓴 start_dialogue는 DialogueRunner가 바로 이어 가므로 여기 남지 않는다.)
var pending_dialogue: String = ""
## 아직 화면에 알리지 않은 알림 (정세 알림 pending_news와 별도).
## 동료 이탈: { type: "companion_left", companion, npc, title, text }
var pending_notices: Array = []
## 이벤트 id -> 마지막으로 띄운 날. 같은 이벤트가 economy.events.cooldown_days 안에 다시 뜨지 않게 한다.
var event_last_day: Dictionary = {}
## 이번에 도시에 머무는 동안 구역 id -> 들어간 횟수, 띄운 구역 이벤트 수. 도시를 떠나면 비운다.
var stay_visits: Dictionary = {}
var stay_location_events: int = 0
## 초반 안내 (data/guide.json): 지금 목표 단계, 첫 목표를 알렸는지
var guide_step: int = 0
var guide_announced: bool = false
## 주인공 이름 (대화의 {player})
var player_name: String = "운반꾼"
## 도시 id -> 평판으로 바뀌기 전 누적된 거래 실적
var _rep_progress: Dictionary = {}

var data
var rng := RandomNumberGenerator.new()


func _init(game_data, seed_value: int = -1) -> void:
	data = game_data
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var start: Dictionary = data.economy.start
	power = int(start.power)
	cargo_capacity = int(start.cargo_capacity)
	city = start.city
	market = Market.new(data, rng)
	politics = Politics.new(data)
	market.politics = politics
	for s in Defs.STATS:
		stats[s] = int(data.economy.character.base_stat)
	for id in data.cities:
		reputation[id] = 0


## 지금 목표. 다 끝냈으면 {}.
func current_goal() -> Dictionary:
	var steps: Array = data.guide
	return steps[guide_step] if guide_step < steps.size() else {}


## 목표를 채웠는지 보고 다음 단계로 넘긴다. 알릴 내용은 pending_notices에 { type: "guide" }로 쌓는다.
## 첫 목표는 도시에 처음 들어선 뒤(visited_cities가 생긴 뒤)에 알린다.
func update_guide() -> void:
	var steps: Array = data.guide
	if steps.is_empty() or visited_cities.is_empty():
		return
	if not guide_announced:
		guide_announced = true
		var first: Dictionary = steps[0]
		pending_notices.append({ "type": "guide", "title": "목표: " + first.title,
			"text": "%s\n\n%s" % [first.where, first.hint] })
	while guide_step < steps.size() and EventRunner.requirements_met(self, steps[guide_step].get("done", [])):
		var done: Dictionary = steps[guide_step]
		guide_step += 1
		var text := "달성: %s" % done.title
		var nxt := current_goal()
		if nxt.is_empty():
			text += "\n\n1막의 길은 여기까지다. 2막은 아직 쓰는 중이다. 교역은 계속할 수 있다."
		else:
			text += "\n\n다음 목표: %s\n%s\n\n%s" % [nxt.title, nxt.where, nxt.hint]
		pending_notices.append({ "type": "guide", "title": "목표 달성", "text": text })


func add_reputation(city_id: String, delta: int) -> void:
	var r: Dictionary = data.economy.reputation
	reputation[city_id] = clampi(reputation[city_id] + delta, int(r.min), int(r.max))


## 화물 추가. 짐칸이 모자라면 들어가는 만큼만 싣고 실은 수량을 돌려준다.
func add_cargo(good_id: String, qty: int) -> int:
	var fit := mini(qty, cargo_capacity - cargo_count())
	if fit > 0:
		cargo[good_id] = cargo.get(good_id, 0) + fit
	return maxi(fit, 0)


## 화물 제거. qty < 0이면 전부. 뺀 수량을 돌려준다.
func remove_cargo(good_id: String, qty: int) -> int:
	var have: int = cargo.get(good_id, 0)
	var n := have if qty < 0 else mini(qty, have)
	if n > 0:
		cost_basis[good_id] = cost_basis.get(good_id, 0.0) * (have - n) / have
		cargo[good_id] = have - n
		if cargo[good_id] == 0:
			cargo.erase(good_id)
	return n


func cargo_count() -> int:
	var total := 0
	for q in cargo.values():
		total += q
	return total


func buy(good_id: String, qty: int) -> String:
	if good_id not in market.goods_for_sale(city):
		return "이 도시에서는 팔지 않는다"
	if qty <= 0:
		return "수량이 없다"
	if cargo_count() + qty > cargo_capacity:
		return "짐칸이 모자란다"
	var cost := _total_buy_cost(good_id, qty)
	if cost > power:
		return "전력이 모자란다"
	power -= cost
	cargo[good_id] = cargo.get(good_id, 0) + qty
	cost_basis[good_id] = cost_basis.get(good_id, 0.0) + cost
	market.on_bought(city, good_id, qty)
	_after_trade(good_id, qty, cost, 0, false)
	return ""


func sell(good_id: String, qty: int) -> String:
	if not market.buys(city, good_id):
		return "이 도시는 이 물건을 받지 않는다"
	if qty <= 0 or cargo.get(good_id, 0) < qty:
		return "가진 수량이 모자란다"
	var income := _total_sell_income(good_id, qty)
	var basis: float = avg_cost(good_id) * qty
	power += income
	remove_cargo(good_id, qty)
	market.on_sold(city, good_id, qty)
	_after_trade(good_id, qty, income, income - roundi(basis), true)
	return ""


## 가진 물품의 평균 구입가. 이벤트로 공짜로 얻은 물건은 0으로 친다.
func avg_cost(good_id: String) -> float:
	var have: int = cargo.get(good_id, 0)
	return cost_basis.get(good_id, 0.0) / have if have > 0 else 0.0


## 거래가 평판과 진영 정세에 주는 영향.
func _after_trade(good_id: String, qty: int, value: int, profit: int, selling: bool) -> void:
	var r: Dictionary = data.economy.reputation
	var mult := 1.0
	if selling and good_id in data.cities[city].demands:
		mult = float(r.trade_demand_bonus)
	_rep_progress[city] = _rep_progress.get(city, 0.0) + value * mult / float(r.trade_cells_per_point)
	var rep_delta := floori(_rep_progress[city])
	_rep_progress[city] -= rep_delta
	add_reputation(city, rep_delta)
	if "trade_lowers_all_reputation" in data.cities[city].traits:
		for id in data.cities:
			if id != city:
				add_reputation(id, -1)
	var influence := politics.on_trade(city, good_id, value, selling)
	pending_news.append_array(politics.update_crises())
	last_trade = {
		"good": good_id, "qty": qty, "value": value, "profit": profit, "selling": selling,
		"rep_delta": rep_delta, "faction": data.cities[city].faction, "influence": influence,
	}


## 전력과 짐칸 안에서 최대로 살 수 있는 수량.
func max_buyable(good_id: String) -> int:
	var qty := 0
	while cargo_count() + qty < cargo_capacity and _total_buy_cost(good_id, qty + 1) <= power:
		qty += 1
	return qty


## 현재 도시에서 갈 수 있는 도로 목록. [{ to, road, days, power }]
func routes_from_here() -> Array:
	var out := []
	for r in data.routes:
		var to: String = ""
		if r.a == city:
			to = r.b
		elif r.b == city:
			to = r.a
		if to != "":
			out.append({ "to": to, "road": r.road, "days": int(r.days), "power": travel_cost(r) })
	return out


func travel_cost(route: Dictionary) -> int:
	return int(data.economy.travel.power_per_day[route.road]) * int(route.days)


func travel(to: String) -> String:
	for r in routes_from_here():
		if r.to != to:
			continue
		if r.power > power:
			return "전력이 모자란다"
		power -= r.power
		for i in r.days:
			_advance_day()
		city = to
		last_road = r.road
		stay_visits.clear()
		stay_location_events = 0
		return ""
	return "이어진 길이 없다"


## 전력 + 화물을 기본가로 환산한 재산.
func net_worth() -> int:
	var total := power
	for good_id in cargo:
		total += int(data.goods[good_id].base_price) * cargo[good_id]
	return total


func _advance_day() -> void:
	day += 1
	power -= floori(power * float(data.economy.self_discharge_per_day))
	if vehicle_damage.has("battery"):
		power = maxi(0, power - int(data.combat.car.battery_leak_per_day))
	market.advance_day()
	politics.advance_day()
	pending_news.append_array(politics.update_crises())
	_check_companion_leave()


## 한 개씩 살 때마다 값이 오르는 것을 반영한 총액. 시세를 바꾸지 않고 계산만 한다.
func _total_buy_cost(good_id: String, qty: int) -> int:
	var unit := market.buy_price(city, good_id)
	var step: float = data.economy.market.pressure_per_unit_bought
	var total := 0
	for i in qty:
		total += maxi(1, roundi(unit * (1.0 + step * i)))
	return total


func _total_sell_income(good_id: String, qty: int) -> int:
	var unit := market.sell_price(city, good_id)
	var step: float = data.economy.market.pressure_per_unit_sold
	var total := 0
	for i in qty:
		total += maxi(1, roundi(unit * (1.0 - step * i)))
	return total


# --- 차량과 전투 ---

## 차량 부위 파손. 적재함은 바로 화물 일부를 잃는다. 보여 줄 한 줄을 돌려준다.
func damage_vehicle(part: String) -> String:
	var car: Dictionary = data.combat.car
	var name: String = car.parts[part].name
	if vehicle_damage.has(part):
		return "%s이(가) 더 망가졌다" % name
	vehicle_damage[part] = true
	match part:
		"cargo_bay":
			var lost := 0
			for good_id in cargo.keys():
				lost += remove_cargo(good_id, ceili(cargo[good_id] * float(car.cargo_bay_loss)))
			return "적재함 파손: 화물 %d개를 잃었다" % lost
		"engine":
			return "엔진 파손: 전투에서 탈출이 한 턴 늦어진다"
		"battery":
			return "배터리 파손: 하루 %d셀씩 전력이 샌다" % int(car.battery_leak_per_day)
		"module":
			return "모듈 파손: 수리 전까지 모듈이 작동하지 않는다"
	return "%s 파손" % name


func can_repair_here() -> bool:
	return "repair" in data.cities[city].services


func repair_cost() -> int:
	var total := 0
	for part in vehicle_damage:
		total += int(data.combat.car.parts[part].repair)
	return total


func repair() -> String:
	if not can_repair_here():
		return "이 도시에는 정비소가 없다"
	if vehicle_damage.is_empty():
		return "고칠 곳이 없다"
	var cost := repair_cost()
	if cost > power:
		return "전력이 모자란다"
	power -= cost
	vehicle_damage.clear()
	return ""


## 전투에 나갈 분대. 주인공과 동료 (동료가 없으면 임시 용병).
func battle_squad() -> Array:
	var c: Dictionary = data.combat
	var mate: Dictionary = c.mercenary
	var mate_name: String = c.mercenary.name
	if companion != "":
		mate = data.companions[companion].combat
		mate_name = data.companions[companion].name
	return [
		{ "name": "나", "hp": int(c.player.hp_base) + int(c.player.hp_per_survival) * int(stats.survival),
			"focus": stats.focus, "might": stats.might, "weapon": c.player.weapon, "melee_weapon": c.player.melee_weapon },
		{ "name": mate_name, "hp": int(mate.hp), "focus": int(mate.focus),
			"might": int(mate.might), "weapon": mate.weapon },
	]


func start_battle(encounter_id: String) -> Battle:
	return Battle.new(data.combat, encounter_id, battle_squad(), int(stats.negotiation), vehicle_damage, rng)


## 끝난 전투의 결과를 반영하고 보여 줄 줄들을 돌려준다.
func apply_battle(b: Battle) -> Array:
	var lines := []
	for part in b.car_hits:
		lines.append(damage_vehicle(part))
	var loot: Dictionary = b.encounter.loot
	match b.result:
		"victory", "surrender":
			var share := 1.0 if b.result == "victory" else 0.5
			var p := roundi(rng.randi_range(int(loot.power[0]), int(loot.power[1])) * share)
			if p > 0:
				power += p
				lines.append("전리품: 전력 +%d셀" % p)
			for good_id in loot.goods:
				var n := roundi(rng.randi_range(int(loot.goods[good_id][0]), int(loot.goods[good_id][1])) * share)
				if n > 0:
					var got := add_cargo(good_id, n)
					lines.append("전리품: %s +%d%s" % [data.goods[good_id].name, got, "" if got == n else " (짐칸 부족)"])
		"escaped":
			lines.append("화물을 지키고 빠져나왔다. 전리품은 없다.")
		"wiped":
			var pen: Dictionary = data.combat.wipe_penalty
			var lost := 0
			for good_id in cargo.keys():
				lost += remove_cargo(good_id, ceili(cargo[good_id] * float(pen.cargo_loss)))
			var pl := floori(power * float(pen.power_loss))
			power -= pl
			for i in int(pen.days):
				_advance_day()
			lines.append("정신을 잃었다. %d일 뒤 %s에서 깨어났다." % [int(pen.days), data.cities[city].name])
			lines.append("화물 %d개, 전력 %d셀을 빼앗겼다." % [lost, pl])
	return lines


# --- 도시 탐방 ---

## 구역에 들어간다. visit 목표를 채운다. 구역 이벤트는 화면이 EventRunner.pick_location_event로 따로 고른다.
func enter_location(location_id: String) -> void:
	location = location_id
	stay_visits[location_id] = int(stay_visits.get(location_id, 0)) + 1
	for q in quests:
		if quests[q] != "active":
			continue
		var obj: Dictionary = data.quests.get(q, {}).get("objective", {})
		if obj.get("type") == "visit" and obj.get("location") == location_id:
			quest_visited[q] = true


func leave_location() -> void:
	location = ""


## 지금 도시의 구역 목록 (데이터 순서)
func locations_here() -> Array:
	return data.locations.values().filter(func(l): return l.city == city)


## 그 구역에 지금 나타나는 NPC. requires가 안 맞거나, 동료로 태운 인물이면 {}.
func npc_at(location_id: String) -> Dictionary:
	var loc: Dictionary = data.locations.get(location_id, {})
	var npc: Dictionary = data.npcs.get(loc.get("npc", ""), {})
	if npc.is_empty():
		return {}
	if companion != "" and npc.get("companion", "") == companion:
		return {}
	if not EventRunner.requirements_met(self, npc.get("requires", [])):
		return {}
	return npc


## "none" | "active" | "done"
func quest_state(quest_id: String) -> String:
	return quests.get(quest_id, "none")


## 맡은 의뢰의 목표를 지금 채웠는지. deliver는 목표 구역에 있고 화물이 있어야 한다.
func quest_ready(quest_id: String) -> bool:
	if quest_state(quest_id) != "active":
		return false
	var obj: Dictionary = data.quests.get(quest_id, {}).get("objective", {})
	match obj.get("type"):
		"deliver":
			if obj.has("location") and location != obj.location:
				return false
			return cargo.get(obj.good, 0) >= int(obj.qty)
		"visit":
			return quest_visited.has(quest_id) or location == obj.get("location")
		"flag":
			return flags.has(obj.get("flag"))
	return false


# --- 동료 ---

## 동료를 태운다. 이미 태운 동료가 있으면 내린다. 보여 줄 줄을 돌려준다.
func recruit(companion_id: String) -> String:
	if companion == companion_id:
		return ""
	var lines := []
	if companion != "":
		lines.append(dismiss_companion())
	companion = companion_id
	if not trust.has(companion_id):
		trust[companion_id] = int(data.companions[companion_id].get("trust", 0))
	lines.append("%s 동료가 되었다" % EventRunner.josa(data.companions[companion_id].name, "이", "가"))
	return "\n".join(lines)


func dismiss_companion() -> String:
	if companion == "":
		return ""
	var name: String = data.companions[companion].name
	companion = ""
	return "%s 차에서 내렸다" % EventRunner.josa(name, "이", "가")


## 태운 동료가 그 능력치 판정에 더해 주는 값.
func stat_bonus(stat: String) -> int:
	if companion == "":
		return 0
	var c: Dictionary = data.companions[companion]
	return int(c.get("bonus", 0)) if c.get("bonus_stat") == stat else 0


## 하루가 지날 때 동료의 leave_if를 확인한다. 하나라도 맞으면 떠나고 알림을 남긴다.
## 떠난 동료는 플래그 companion_left_<id>가 선다 (대화나 NPC requires에서 쓸 수 있다).
func _check_companion_leave() -> void:
	if companion == "":
		return
	var c: Dictionary = data.companions[companion]
	for r in c.get("leave_if", []):
		if not EventRunner.requirements_met(self, [r]):
			continue
		var id := companion
		companion = ""
		flags["companion_left_" + id] = true
		pending_notices.append({
			"type": "companion_left", "companion": id, "npc": c.get("npc", ""),
			"title": "%s 떠났다" % EventRunner.josa(c.name, "이", "가"), "text": c.get("leave_text", ""),
		})
		return
