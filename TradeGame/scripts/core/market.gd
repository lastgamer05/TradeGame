class_name Market
extends RefCounted
## 도시별 시세. 기본가 x 특산/수요 배율 x (1 - 판매 압력) x 일일 변동으로 가격을 낸다.
## 플레이어가 많이 팔면 압력이 쌓여 값이 떨어지고, 날이 지나면 압력이 풀린다.

var _data
var _cfg: Dictionary
var _rng: RandomNumberGenerator
## city -> good -> 판매 압력. 양수면 값이 떨어진다.
var _pressure: Dictionary = {}
## city -> good -> 오늘의 변동 배율
var _drift: Dictionary = {}
## 정세 사건의 시세 배율을 준다. 없으면 무시한다.
var politics: Politics


func _init(data, rng: RandomNumberGenerator) -> void:
	_data = data
	_cfg = data.economy.market
	_rng = rng
	for city_id in data.cities:
		_pressure[city_id] = {}
		_drift[city_id] = {}
	roll_drift()


## 이 도시에서 플레이어가 살 수 있는 물품 id 목록.
func goods_for_sale(city_id: String) -> Array:
	var city: Dictionary = _data.cities[city_id]
	if "sells_everything" in city.traits:
		return _data.goods.keys().filter(func(id):
			var g: Dictionary = _data.goods[id]
			return g.get("tradable_buy", true) and not g.get("contraband", false))
	return city.specialties.duplicate()


## 이 도시가 이 물품을 사 주는지.
func buys(city_id: String, good_id: String) -> bool:
	var city: Dictionary = _data.cities[city_id]
	if "strict_contraband" in city.traits and _data.goods[good_id].get("contraband", false):
		return false
	return true


## 기준가(base_price) 대비 현재 시세. 1.0 = 100%.
func price_ratio(city_id: String, good_id: String) -> float:
	return _price(city_id, good_id) / float(_data.goods[good_id].base_price)


## 플레이어가 살 때 값.
func buy_price(city_id: String, good_id: String) -> int:
	return maxi(1, roundi(_price(city_id, good_id)))


## 플레이어가 팔 때 값.
func sell_price(city_id: String, good_id: String) -> int:
	return maxi(1, roundi(_price(city_id, good_id) * _cfg.sell_ratio))


func on_bought(city_id: String, good_id: String, qty: int) -> void:
	_add_pressure(city_id, good_id, -_cfg.pressure_per_unit_bought * qty)


func on_sold(city_id: String, good_id: String, qty: int) -> void:
	_add_pressure(city_id, good_id, _cfg.pressure_per_unit_sold * qty)


## 하루가 지날 때 호출. 압력이 풀리고 시세가 새로 흔들린다.
func advance_day() -> void:
	for city_id in _pressure:
		for good_id in _pressure[city_id]:
			_pressure[city_id][good_id] *= _cfg.pressure_decay_per_day
	roll_drift()


func roll_drift() -> void:
	for city_id in _data.cities:
		var traits: Array = _data.cities[city_id].traits
		var vol: float = _cfg.volatility.normal
		if "stable_prices" in traits:
			vol = _cfg.volatility.stable
		elif "volatile_prices" in traits:
			vol = _cfg.volatility.volatile
		for good_id in _data.goods:
			_drift[city_id][good_id] = 1.0 + _rng.randf_range(-vol, vol)


func _price(city_id: String, good_id: String) -> float:
	var city: Dictionary = _data.cities[city_id]
	var mult: Dictionary = _data.economy.price_multipliers
	var m: float = mult.normal
	if good_id in city.specialties:
		m = mult.specialty
	elif good_id in city.demands:
		m = mult.demand
	var pressure: float = _pressure[city_id].get(good_id, 0.0)
	var crisis := politics.price_multiplier(city_id, good_id) if politics else 1.0
	return _data.goods[good_id].base_price * m * (1.0 - pressure) * _drift[city_id][good_id] * crisis


func _add_pressure(city_id: String, good_id: String, amount: float) -> void:
	var cap: float = _cfg.max_pressure
	var p: float = _pressure[city_id].get(good_id, 0.0) + amount
	_pressure[city_id][good_id] = clampf(p, -cap, cap)
