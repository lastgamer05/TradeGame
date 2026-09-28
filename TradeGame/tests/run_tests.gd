extends SceneTree
## 헤드리스 테스트 실행기.
## godot --headless --path <프로젝트> --script res://tests/run_tests.gd

var _failures := 0


func _initialize() -> void:
	test_game_data_loads_without_errors()
	test_city_references()
	test_trade_loop()
	test_sell_pressure_and_recovery()
	test_travel()
	test_events()
	test_trade_effects()
	test_politics()
	print("\n%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _load_data() -> Node:
	var script: GDScript = load("res://scripts/autoload/game_data.gd")
	if script == null or not script.can_instantiate():
		return null
	var data: Node = script.new()
	data.load_all()
	return data


func test_game_data_loads_without_errors() -> void:
	var data := _load_data()
	_expect(data != null, "game_data.gd 로드")
	if data == null:
		return
	for e in data.errors:
		print("  data error: ", e)
	_expect(data.errors.is_empty(), "데이터 검증 오류 없음")
	_expect(data.cities.size() == 8, "도시 8곳")
	_expect(data.events.has("helios_checkpoint"), "검문소 이벤트 로드")
	data.free()


func test_city_references() -> void:
	var data := _load_data()
	if data == null:
		return
	_expect(data.cities.helios.faction == "victor", "헬리오스는 승전 진영")
	_expect("raw_food" in data.cities.greenhouse.specialties, "그린하우스 특산에 생식량")
	data.free()


func test_trade_loop() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 1)
	_expect(s.city == "greenhouse", "그린하우스에서 시작")
	var start_power := s.power
	_expect(s.buy("raw_food", 5) == "", "생식량 5개 구매")
	_expect(s.cargo.raw_food == 5 and s.power < start_power, "화물과 전력 반영")
	_expect(s.buy("ammo", 1) != "", "특산이 아닌 물품은 못 산다")
	_expect(s.buy("raw_food", 999) != "", "짐칸 초과 구매 거부")
	_expect(s.sell("raw_food", 6) != "", "가진 것보다 많이 못 판다")
	_expect(s.travel("helios") == "", "헬리오스로 이동")
	var before := s.power
	_expect(s.sell("raw_food", 5) == "", "헬리오스에서 생식량 판매")
	_expect(s.power > before and s.cargo.is_empty(), "판매 대금 반영")
	# 입문 교역로(그린하우스 식량 -> 헬리오스)는 남는 장사여야 한다.
	var g := GameState.new(data, 2)
	var buy_cost := g.market.buy_price("greenhouse", "raw_food")
	var sell_income := g.market.sell_price("helios", "raw_food")
	_expect(sell_income > buy_cost, "입문 교역로 이익 (%d -> %d)" % [buy_cost, sell_income])
	_expect(not g.market.buys("helios", "hacking_tool"), "헬리오스는 금지품을 안 산다")
	data.free()


func test_sell_pressure_and_recovery() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 3)
	var p0 := s.market.sell_price("helios", "metal")
	s.market.on_sold("helios", "metal", 10)
	var p1 := s.market.sell_price("helios", "metal")
	_expect(p1 < p0, "많이 팔면 값이 떨어진다 (%d -> %d)" % [p0, p1])
	for i in 20:
		s.market.advance_day()
	var p2 := s.market.sell_price("helios", "metal")
	_expect(p2 > p1, "시간이 지나면 값이 회복된다 (%d -> %d)" % [p1, p2])
	data.free()


func test_travel() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 4)
	_expect(s.travel("scrapyard") != "", "이어지지 않은 도시로는 못 간다")
	var p := s.power
	_expect(s.travel("undergrid") == "", "황무지 3일 이동")
	_expect(s.day == 4, "날짜가 3일 지난다")
	_expect(s.power < p - 18 + 1, "전력 소모와 자연 방전")
	s.power = 0
	_expect(s.travel("greenhouse") != "", "전력이 없으면 못 간다")
	data.free()


func test_events() -> void:
	var data := _load_data()
	if data == null:
		return
	data.economy.events.travel_chance = 1.0
	data.economy.events.city_chance = 1.0
	var s := GameState.new(data, 5)
	var checkpoint: Dictionary = data.events.helios_checkpoint
	_expect(not EventRunner.requirements_met(s, checkpoint.trigger.requires), "억제제가 없으면 검문소 이벤트 조건 불충족")
	s.add_cargo("suppressant", 3)
	_expect(EventRunner.requirements_met(s, checkpoint.trigger.requires), "억제제가 있으면 조건 충족")

	var choices := {}
	for ch in checkpoint.choices:
		choices[ch.id] = ch
	_expect(EventRunner.choice_blocker(s, choices.smuggle_compartment) != "", "밀수칸 없으면 선택 불가")
	_expect(EventRunner.choice_tags(s, choices.talk).begins_with("[교섭 DC 15]"), "판정 태그 표시")

	s.stats.negotiation = 30
	var r := EventRunner.resolve(s, choices.talk)
	_expect(r.outcome == "success" and s.cargo.get("suppressant", 0) == 3, "판정 성공이면 화물 유지")
	s.stats.negotiation = -30
	r = EventRunner.resolve(s, choices.talk)
	_expect(r.outcome == "failure" and not s.cargo.has("suppressant"), "판정 실패면 억제제 압수")
	_expect(s.reputation.helios == -10, "실패 시 헬리오스 평판 -10")

	var p := s.power
	EventRunner.resolve(s, choices.bribe)
	_expect(s.power == p - 10 and s.flags.has("corrupt_soldier"), "뇌물: 전력 차감과 플래그")

	# 이동 이벤트는 도로 종류에 맞는 것만 뜬다.
	s.last_road = "wasteland"
	for i in 20:
		var ev := EventRunner.pick_travel_event(s)
		if ev.is_empty() or not ev.trigger.has("road_types"):
			continue
		if "wasteland" not in ev.trigger.road_types:
			_expect(false, "도로 종류가 안 맞는 이벤트 '%s'" % ev.id)
			break
	_expect(true, "도로 종류에 맞는 이벤트만 선택")

	# 모든 이벤트의 모든 선택지가 오류 없이 실행된다.
	for ev in data.events.values():
		for ch in ev.choices:
			var t := GameState.new(data, 6)
			t.power = 1000
			EventRunner.resolve(t, ch)
	_expect(true, "모든 선택지 실행")
	data.free()


func test_trade_effects() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 7)
	s.buy("raw_food", 10)
	var paid: int = s.last_trade.value
	_expect(absf(s.avg_cost("raw_food") - paid / 10.0) < 0.01, "평균 구입가 기록")
	s.travel("helios")
	s.sell("raw_food", 10)
	var t := s.last_trade
	_expect(t.profit == t.value - paid, "판매 이익 = 판매액 - 구입액 (%d)" % t.profit)
	_expect(s.reputation.helios > 0, "수요품을 팔면 도시 평판 상승 (%+d)" % s.reputation.helios)
	_expect(s.market.price_ratio("greenhouse", "raw_food") < 1.0, "특산품 시세는 100% 미만")

	# 스크랩야드와 거래하면 다른 도시 평판이 모두 떨어진다.
	var y := GameState.new(data, 8)
	y.city = "scrapyard"
	y.buy("stolen_module", 1)
	_expect(y.reputation.helios == -1 and y.reputation.undergrid == -1, "스크랩야드 거래는 다른 도시 평판 하락")
	data.free()


func test_politics() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 9)
	var before := s.politics.share("rebel")
	s.city = "undergrid"
	s.add_cargo("chip_military", 10)
	s.sell("chip_military", 10)
	_expect(s.politics.share("rebel") > before, "언더그리드에 칩을 팔면 반란 점유율 상승 (%d%% -> %d%%)" % [
		roundi(before * 100), roundi(s.politics.share("rebel") * 100)])
	s.politics.on_trade("undergrid", "chip_military", 2000, true)
	s.pending_news.append_array(s.politics.update_crises())
	_expect(s.politics.active.has("rebel_uprising"), "문턱을 넘으면 반란 격화 시작")
	_expect(s.pending_news.size() > 0 and s.pending_news[0].started, "정세 변화 알림 대기")
	var ratio_before := s.market.price_ratio("helios", "ammo")
	s.politics.active.erase("rebel_uprising")
	_expect(ratio_before > s.market.price_ratio("helios", "ammo") * 1.4, "반란 격화 중 탄약 시세 상승")
	s.politics.active["rebel_uprising"] = data.politics.crises[0]
	for i in 200:
		s.politics.advance_day()
	s.politics.update_crises()
	_expect(not s.politics.active.has("rebel_uprising"), "시간이 지나면 세력이 돌아오고 사건이 끝난다")
	data.free()


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
