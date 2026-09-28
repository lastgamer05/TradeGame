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


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
