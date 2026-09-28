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
	market.on_bought(city, good_id, qty)
	return ""


func sell(good_id: String, qty: int) -> String:
	if not market.buys(city, good_id):
		return "이 도시는 이 물건을 받지 않는다"
	if qty <= 0 or cargo.get(good_id, 0) < qty:
		return "가진 수량이 모자란다"
	power += _total_sell_income(good_id, qty)
	cargo[good_id] -= qty
	if cargo[good_id] == 0:
		cargo.erase(good_id)
	market.on_sold(city, good_id, qty)
	return ""


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
	market.advance_day()


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
