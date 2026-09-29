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
## --- 도시 탐방 (docs/city_spec.md 4절). 틀만 있고 엔진 담당이 채운다 ---
## 지금 있는 구역, 도시 허브면 ""
var location: String = ""
## 태운 동료 id
var companion: String = ""
## 동료 id -> 신뢰
var trust: Dictionary = {}
## 의뢰 id -> "active" | "done"
var quests: Dictionary = {}
## 도시 id -> true (첫 도착 대화용)
var visited_cities: Dictionary = {}
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


## 전투에 나갈 분대. 주인공과 임시 용병.
func battle_squad() -> Array:
	var c: Dictionary = data.combat
	return [
		{ "name": "나", "hp": int(c.player.hp_base) + int(c.player.hp_per_survival) * int(stats.survival),
			"focus": stats.focus, "might": stats.might, "weapon": c.player.weapon, "melee_weapon": c.player.melee_weapon },
		{ "name": c.mercenary.name, "hp": int(c.mercenary.hp), "focus": int(c.mercenary.focus),
			"might": int(c.mercenary.might), "weapon": c.mercenary.weapon },
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


# --- 도시 탐방 (틀) ---

func enter_location(location_id: String) -> void:
	location = location_id


func leave_location() -> void:
	location = ""


## 지금 도시의 구역 목록 (데이터 순서)
func locations_here() -> Array:
	return data.locations.values().filter(func(l): return l.city == city)


## 그 구역에 지금 나타나는 NPC. 조건(requires)은 엔진 담당이 확인하게 만든다.
func npc_at(location_id: String) -> Dictionary:
	var loc: Dictionary = data.locations.get(location_id, {})
	return data.npcs.get(loc.get("npc", ""), {})


func quest_ready(quest_id: String) -> bool:
	return false
