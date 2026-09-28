class_name Politics
extends RefCounted
## 진영 정세. 플레이어가 어느 진영 도시에 무엇을 팔고 사는지에 따라 진영 세력이 커지고,
## 점유율이 문턱을 넘으면 정세 사건(반란 격화, 봉쇄 등)이 시작돼 시세가 바뀐다.

var data
## 진영 id -> 세력 (중립 제외)
var strength: Dictionary = {}
## 진행 중인 정세 사건 id -> 사건 데이터
var active: Dictionary = {}


func _init(game_data) -> void:
	data = game_data
	for f in data.politics.start_strength:
		strength[f] = float(data.politics.start_strength[f])


func share(faction: String) -> float:
	var total := 0.0
	for v in strength.values():
		total += v
	return strength.get(faction, 0.0) / total if total > 0 else 0.0


## 거래 한 번이 진영 세력에 주는 영향. 판매는 그 진영을 먹여 살리고, 구매는 덜 돕는다.
func on_trade(city_id: String, good_id: String, value: int, selling: bool) -> float:
	var faction: String = data.cities[city_id].faction
	if not strength.has(faction):
		return 0.0
	var cfg: Dictionary = data.politics.influence
	var amount: float = value / float(cfg.cells_per_point)
	amount *= float(cfg.category_weight.get(data.goods[good_id].category, 1.0))
	if selling:
		if good_id in data.cities[city_id].demands:
			amount *= float(cfg.demand_bonus)
	else:
		amount *= float(cfg.buy_ratio)
	strength[faction] += amount
	return amount


## 하루마다 세력이 시작값 쪽으로 조금씩 돌아간다.
func advance_day() -> void:
	var rate: float = data.politics.decay_per_day
	for f in strength:
		var start := float(data.politics.start_strength[f])
		strength[f] += (start - strength[f]) * rate


## 문턱을 넘은 사건을 시작하고, 내려간 사건을 끝낸다. [{ crisis, started }] 를 돌려준다.
func update_crises() -> Array:
	var changes := []
	for c in data.politics.crises:
		var s := share(c.faction)
		if not active.has(c.id) and s >= float(c.start_share):
			active[c.id] = c
			changes.append({ "crisis": c, "started": true })
		elif active.has(c.id) and s < float(c.end_share):
			active.erase(c.id)
			changes.append({ "crisis": c, "started": false })
	return changes


func price_multiplier(city_id: String, good_id: String) -> float:
	var m := 1.0
	for c in active.values():
		for p in c.get("prices", []):
			if good_id in p.goods and (str(p.cities) == "all" or city_id in p.cities):
				m *= float(p.mult)
	return m


func travel_event_bonus() -> float:
	var b := 0.0
	for c in active.values():
		b += float(c.get("travel_event_bonus", 0.0))
	return b
