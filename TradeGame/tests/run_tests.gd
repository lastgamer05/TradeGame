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
	test_battle_map()
	test_battle_rules()
	test_battle_simulation()
	test_city_locations()
	test_requirements()
	test_city_effects()
	test_city_triggers()
	test_dialogue_flow()
	test_quests()
	test_companions()
	test_city_validation()
	test_all_dialogues_run()
	test_dialogue_view()
	test_town_view()
	test_guide()
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


func test_battle_map() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 10)
	var ok := true
	for enc in data.combat.encounters:
		for i in 10:
			var b := s.start_battle(enc)
			if not b._fair():
				ok = false
			for u in b.units:
				if not b._in_bounds(u.pos) or b.tile(u.pos) != Battle.Tile.FLOOR:
					ok = false
	_expect(ok, "생성된 맵: 좌우 균형, 탈출 경로, 유닛이 빈 칸에 선다")
	data.free()


func test_battle_rules() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 11)
	var b := s.start_battle("raider_roadblock")
	# 빈 맵에서 규칙만 확인한다.
	for y in b.h:
		for x in b.w:
			b.tiles[y][x] = Battle.Tile.FLOOR
	_expect(Battle.hex_dist(Vector2i(2, 2), Vector2i(2, 3)) == 1 and Battle.hex_dist(Vector2i(2, 2), Vector2i(1, 3)) == 1, "육각 이웃 거리 1")
	_expect(Battle.hex_dist(Vector2i(0, 0), Vector2i(4, 0)) == 4 and Battle.hex_dist(Vector2i(0, 0), Vector2i(0, 4)) == 4, "육각 거리")
	_expect(b.neighbors(Vector2i(5, 5)).size() == 6 and b.neighbors(Vector2i(5, 4)).size() == 6, "이웃은 6칸")
	var me: Dictionary = b.units[0]
	var foe: Dictionary = b.active_units("enemy")[0]
	me.pos = Vector2i(6, 6)
	foe.pos = Vector2i(12, 6)
	var open := b.hit_chance(me, foe)
	b.tiles[6][11] = Battle.Tile.HALF
	var half := b.hit_chance(me, foe)
	_expect(half < open, "반 엄폐는 명중률을 낮춘다 (%d%% -> %d%%)" % [open, half])
	b.tiles[6][11] = Battle.Tile.FULL
	_expect(not b.has_los(me.pos, foe.pos), "완전 엄폐물은 시야를 가린다")
	b.tiles[6][11] = Battle.Tile.FLOOR
	foe.hidden = true
	_expect(b.hit_chance(me, foe) < open, "숨은 적은 맞히기 어렵다")
	foe.hidden = false
	var reach := b.reachable(me)
	_expect(reach.has(Vector2i(11, 6)) and not reach.has(Vector2i(12, 6)), "이동 범위 5칸, 적이 선 칸은 못 간다")
	_expect(b.move(me, Vector2i(8, 6)) and me.ap == 1, "이동하면 행동력 1 소모")
	_expect(b.attack(me, foe) and me.ap == 0, "공격하면 턴 종료")
	# 탑승과 탈출
	for u in b.active_units("player"):
		u.pos = b.escape_cells[b.units.find(u)]
		u.ap = 2
		_expect(b.board(u), "탈출 구역에서 탑승")
	b.end_player_turn()
	_expect(b.result == "escaped", "전원 탑승하면 도주 성공")
	data.free()


func test_battle_simulation() -> void:
	var data := _load_data()
	if data == null:
		return
	# 플레이어가 가장 가까운 적을 쏘기만 하는 전투를 여러 번 끝까지 돌려 본다.
	var results := {}
	for seed_value in 20:
		var s := GameState.new(data, 100 + seed_value)
		s.cargo_capacity = 40
		s.add_cargo("raw_food", 10)
		var enc: String = data.combat.encounters.keys()[seed_value % data.combat.encounters.size()]
		var b := s.start_battle(enc)
		var guard := 0
		while b.result == "" and guard < 60:
			guard += 1
			for u in b.active_units("player"):
				var target := {}
				for e in b.active_units("enemy"):
					if b.hit_chance(u, e) > 0:
						target = e
						break
				if not target.is_empty():
					b.attack(u, target)
				else:
					var moves := b.reachable(u)
					# 가장 가까운 적 쪽으로 (구조물에 막혀도 우회하도록 거리 기준)
					if b.active_units("enemy").is_empty():
						break
					var goal: Vector2i = b.active_units("enemy")[0].pos
					var best: Vector2i = u.pos
					for c in moves:
						if Battle.hex_dist(c, goal) < Battle.hex_dist(best, goal):
							best = c
					b.move(u, best)
					if u.ap > 0 and not b.active_units("enemy").is_empty():
						for e in b.active_units("enemy"):
							if b.hit_chance(u, e) > 0:
								b.attack(u, e)
								break
			b.end_player_turn()
		results[b.result] = results.get(b.result, 0) + 1
		s.apply_battle(b)
		if s.power < 0:
			_expect(false, "전투 뒤 전력이 음수")
	_expect(not results.has(""), "모든 전투가 끝난다 %s" % results)
	data.free()


# --- 도시 탐방 (docs/city_spec.md) ---

func test_city_locations() -> void:
	var data := _load_data()
	if data == null:
		return
	_expect(data.locations.size() == 32 and data.npcs.size() == 32, "구역 32곳, NPC 32명")
	var s := GameState.new(data, 20)
	var here := s.locations_here()
	_expect(here.size() == 4 and here.all(func(l): return l.city == "greenhouse"), "지금 도시의 구역 4곳")
	_expect(here[0].id == "greenhouse_market", "구역은 데이터 순서")
	s.enter_location("greenhouse_tower")
	_expect(s.location == "greenhouse_tower", "구역에 들어간다")
	s.leave_location()
	_expect(s.location == "", "허브로 돌아온다")
	_expect(s.npc_at("greenhouse_tower").get("id") == "ian", "정수탑에는 이안")
	s.recruit("ian")
	_expect(s.npc_at("greenhouse_tower").is_empty(), "태운 동료의 NPC는 구역에서 사라진다")
	s.dismiss_companion()
	_expect(s.npc_at("greenhouse_tower").get("id") == "ian", "내리면 다시 나타난다")
	data.npcs.ian["requires"] = [{ "type": "flag", "flag": "tower_open" }]
	_expect(s.npc_at("greenhouse_tower").is_empty(), "NPC requires가 안 맞으면 없다")
	s.flags["tower_open"] = true
	_expect(not s.npc_at("greenhouse_tower").is_empty(), "NPC requires가 맞으면 나타난다")
	_expect(s.npc_at("no_such_place").is_empty(), "없는 구역은 {}")
	data.free()


func test_requirements() -> void:
	var data := _load_data()
	if data == null:
		return
	_add_test_content(data)
	var s := GameState.new(data, 21)
	var met := func(r: Dictionary) -> bool: return EventRunner.requirements_met(s, [r])

	_expect(not met.call({ "type": "crisis", "crisis": "rebel_uprising" }), "사건 없음: crisis 불충족")
	_expect(met.call({ "type": "crisis", "crisis": "rebel_uprising", "active": false }), "사건 없음: active false 충족")
	s.politics.active["rebel_uprising"] = data.politics.crises[0]
	_expect(met.call({ "type": "crisis", "crisis": "rebel_uprising" }), "사건 중: crisis 충족")

	var share := s.politics.share("victor")
	_expect(met.call({ "type": "faction_share", "faction": "victor", "min": share - 0.01, "max": share + 0.01 }), "점유율 범위 안")
	_expect(not met.call({ "type": "faction_share", "faction": "victor", "min": share + 0.01 }), "점유율 min 미달")
	_expect(not met.call({ "type": "faction_share", "faction": "victor", "max": share - 0.01 }), "점유율 max 초과")

	_expect(met.call({ "type": "quest", "quest": "t_deliver", "state": "none" }), "의뢰 받기 전: none")
	_expect(not met.call({ "type": "quest", "quest": "t_deliver" }), "state 기본값은 active")
	s.quests["t_deliver"] = "active"
	_expect(met.call({ "type": "quest", "quest": "t_deliver" }), "의뢰 active")
	s.quests["t_deliver"] = "done"
	_expect(met.call({ "type": "quest", "quest": "t_deliver", "state": "done" }), "의뢰 done")

	_expect(not met.call({ "type": "companion", "companion": "" }), "동료 없음: 아무나 불충족")
	s.recruit("piece")
	_expect(met.call({ "type": "companion", "companion": "" }), "동료 있음: 아무나 충족")
	_expect(met.call({ "type": "companion", "companion": "piece" }), "그 동료가 타고 있다")
	_expect(not met.call({ "type": "companion", "companion": "ian" }), "다른 동료는 불충족")

	s.day = 10
	_expect(met.call({ "type": "day", "min": 5, "max": 10 }), "날짜 범위 안")
	_expect(not met.call({ "type": "day", "max": 9 }), "날짜 max 초과")
	s.power = 100
	_expect(met.call({ "type": "power", "min": 100 }) and not met.call({ "type": "power", "min": 101 }), "전력 min")
	_expect(met.call({ "type": "power", "max": 100 }) and not met.call({ "type": "power", "max": 99 }), "전력 max")

	s.reputation.helios = 20
	_expect(met.call({ "type": "reputation", "city": "helios", "max": 20 }), "평판 max 충족")
	_expect(not met.call({ "type": "reputation", "city": "helios", "max": 19 }), "평판 max 초과")
	_expect(not met.call({ "type": "faction_reputation", "faction": "victor", "max": 9 }), "진영 평판 max 초과 (헬리오스 20, 게이트7 0)")
	s.reputation.gate7 = 20
	_expect(met.call({ "type": "faction_reputation", "faction": "victor", "min": 20, "max": 20 }), "진영 평판 min과 max")

	var blocker := EventRunner.choice_blocker(s, { "requires": [{ "type": "companion", "companion": "ian" }] })
	_expect(blocker.contains("이안"), "막힌 이유에 조건이 드러난다 (%s)" % blocker)
	_expect(EventRunner.choice_tags(s, { "requires": [{ "type": "companion", "companion": "ian" }] }) == "[이안] ", "동료 조건 태그")
	_expect(EventRunner.josa("이안", "이", "가") == "이안이" and EventRunner.josa("피스", "이", "가") == "피스가", "조사 받침 처리")
	data.free()


func test_city_effects() -> void:
	var data := _load_data()
	if data == null:
		return
	_add_test_content(data)
	var s := GameState.new(data, 22)
	EventRunner.apply_effect(s, { "type": "start_dialogue", "dialogue": "t_other" })
	_expect(s.pending_dialogue == "t_other", "start_dialogue는 pending_dialogue에 남는다")

	var line := EventRunner.apply_effect(s, { "type": "recruit", "companion": "ian" })
	_expect(s.companion == "ian" and line.contains("이안"), "동료 영입 (%s)" % line)
	var lines := EventRunner.apply_effects(s, [{ "type": "recruit", "companion": "han" }])
	_expect(s.companion == "han" and lines.size() == 2, "다른 동료를 태우면 기존 동료는 내린다 %s" % [lines])
	EventRunner.apply_effect(s, { "type": "trust", "delta": 5 })
	EventRunner.apply_effect(s, { "type": "trust", "delta": -2 })
	_expect(s.trust.han == 3, "지금 동료의 신뢰 변화")
	EventRunner.apply_effect(s, { "type": "dismiss" })
	_expect(s.companion == "", "동료를 내린다")
	_expect(EventRunner.apply_effect(s, { "type": "trust", "delta": 5 }) == "", "동료가 없으면 신뢰 변화 없음")

	EventRunner.apply_effect(s, { "type": "quest_start", "quest": "t_deliver" })
	_expect(s.quest_state("t_deliver") == "active", "의뢰 시작")
	s.add_cargo("raw_food", 12)
	var p := s.power
	lines = EventRunner.apply_effects(s, [{ "type": "quest_complete", "quest": "t_deliver" }])
	_expect(s.quest_state("t_deliver") == "done", "의뢰 완료")
	_expect(s.cargo.raw_food == 2 and s.power == p + 120 and s.reputation.helios == 10, "납품 화물 차감과 보상 적용")
	_expect(lines.size() == 4, "완료 줄: 전달, 완료, 보상 둘 %s" % [lines])
	EventRunner.apply_effect(s, { "type": "quest_complete", "quest": "t_deliver" })
	_expect(s.power == p + 120, "끝난 의뢰는 보상을 두 번 주지 않는다")

	var before := s.politics.share("rebel")
	line = EventRunner.apply_effect(s, { "type": "faction_strength", "faction": "rebel", "delta": 200 })
	_expect(s.politics.share("rebel") > before and line.contains("+200"), "진영 세력 변화 (%s)" % line)
	_expect(s.politics.active.has("rebel_uprising") and not s.pending_news.is_empty(), "세력 변화로 정세 사건 시작")
	data.free()


func test_city_triggers() -> void:
	var data := _load_data()
	if data == null:
		return
	data.events = {}
	var ev := func(id: String, trigger: Dictionary) -> void:
		data.events[id] = { "id": id, "title": id, "text": "", "trigger": trigger,
			"choices": [{ "id": "ok", "text": "확인", "outcomes": { "success": { "text": "" } } }] }
	ev.call("legacy", { "on": "city", "cities": ["helios"] })
	ev.call("anywhere", { "on": "arrival" })
	ev.call("loc_market", { "on": "location", "kinds": ["market"] })
	ev.call("loc_tower", { "on": "location", "locations": ["greenhouse_tower"] })
	ev.call("loc_crisis", { "on": "location", "requires": [{ "type": "crisis", "crisis": "greenhouse_blockade" }] })
	data.economy.events.city_chance = 1.0
	var s := GameState.new(data, 23)
	var seen := {}
	for i in 30:
		seen[EventRunner.pick_arrival_event(s).get("id", "")] = true
	_expect(seen.has("anywhere") and not seen.has("legacy"), "cities가 비면 모든 도시, 다른 도시 이벤트는 안 뜬다")
	s.city = "helios"
	seen = {}
	for i in 30:
		seen[EventRunner.pick_arrival_event(s).get("id", "")] = true
	_expect(seen.has("legacy") and seen.has("anywhere"), "옛 trigger city는 arrival과 같다")
	data.economy.events.city_chance = 0.0
	_expect(EventRunner.pick_arrival_event(s).is_empty(), "확률이 0이면 도착 이벤트 없음")

	data.economy.events["location_chance"] = 1.0
	s.city = "greenhouse"
	seen = {}
	for i in 30:
		seen[EventRunner.pick_location_event(s, "greenhouse_market").get("id", "")] = true
	_expect(seen.has("loc_market") and not seen.has("loc_tower") and not seen.has("loc_crisis"), "구역 종류로 고른다 %s" % [seen.keys()])
	seen = {}
	for i in 30:
		seen[EventRunner.pick_location_event(s, "greenhouse_tower").get("id", "")] = true
	_expect(seen.has("loc_tower") and not seen.has("loc_market"), "구역 id로 고른다")
	s.politics.active["greenhouse_blockade"] = data.politics.crises[1]
	seen = {}
	for i in 30:
		seen[EventRunner.pick_location_event(s, "greenhouse_bunk").get("id", "")] = true
	_expect(seen.has("loc_crisis"), "정세 사건 중에만 뜨는 구역 이벤트")
	data.economy.events.erase("location_chance")
	var hits := 0
	for i in 200:
		if not EventRunner.pick_location_event(s, "greenhouse_market").is_empty():
			hits += 1
	_expect(hits > 25 and hits < 100, "location_chance 기본값 0.3 (%d/200)" % hits)

	# 반복 줄이기: 띄운 이벤트는 대기 일수 동안 다시 안 뜨고, 머무는 동안 구역 이벤트는 한 번, 같은 구역 재입장엔 없다.
	data.economy.events["location_chance"] = 1.0
	var first := EventRunner.pick_location_event(s, "greenhouse_tower")
	EventRunner.mark_shown(s, first)
	_expect(EventRunner.pick_location_event(s, "greenhouse_market").is_empty(), "머무는 동안 구역 이벤트는 한 번")
	s.stay_location_events = 0
	seen = {}
	for i in 30:
		seen[EventRunner.pick_location_event(s, "greenhouse_tower").get("id", "")] = true
	_expect(not seen.has(first.id), "띄운 이벤트는 대기 일수 동안 다시 안 뜬다")
	s.day += int(data.economy.events.cooldown_days)
	seen = {}
	for i in 30:
		seen[EventRunner.pick_location_event(s, "greenhouse_tower").get("id", "")] = true
	_expect(seen.has(first.id), "대기 일수가 지나면 다시 뜬다")
	s.enter_location("greenhouse_bunk")
	s.enter_location("greenhouse_bunk")
	_expect(EventRunner.pick_location_event(s, "greenhouse_bunk").is_empty(), "같은 구역에 다시 들어가면 이벤트 없음")
	data.economy.events.erase("location_chance")
	data.free()


func test_dialogue_flow() -> void:
	var data := _load_data()
	if data == null:
		return
	_add_test_content(data)
	var s := GameState.new(data, 24)
	s.player_name = "카이"
	s.power = 100
	var d := DialogueRunner.new(s, "t_dlg")
	var cur := d.current()
	_expect(d.node_id == "hello" and cur.speaker_name == "배급관 오르", "시작 노드와 화자 이름")
	_expect(cur.text == "어서 와, 카이.", "{player} 치환")
	_expect(s.flags.has("t_seen") and s.power == 105 and cur.entry_lines == ["전력 +5셀"], "노드에 들어서면 노드 효과 적용")
	_expect(cur.choices.size() == 5, "hide_if_blocked 선택지는 숨는다")
	_expect(cur.choices[0].tags == "[교섭 DC 15] ", "판정 태그")
	_expect(not cur.choices[2].enabled and cur.choices[2].blocker.contains("이안"), "막힌 선택지는 보이되 이유가 붙는다")
	_expect(d.choose(2).effect_lines.is_empty() and d.node_id == "hello", "막힌 선택지는 골라도 그대로")

	s.stats.negotiation = 30
	var r := d.choose(0)
	_expect(r.success and r.roll_text.contains("성공") and d.node_id == "win", "판정 성공은 next")
	_expect(s.reputation.helios == 3 and r.effect_lines == ["헬리오스 평판 +3"], "성공 효과")
	cur = d.current()
	_expect(cur.speaker_name == "카이" and cur.choices.is_empty(), "player 화자, 선택지 없는 노드")
	d.choose(0)
	_expect(d.is_finished() and d.current().is_empty(), "선택지 없는 노드는 계속하면 끝")

	# 다시 말을 걸면 variants로 시작한다.
	d = DialogueRunner.new(s, "t_dlg")
	_expect(d.node_id == "again", "조건이 맞는 variant로 시작")
	s.stats.negotiation = -30
	d = DialogueRunner.new(s, "t_dlg")
	d._enter("hello")
	r = d.choose(0)
	_expect(not r.success and d.node_id == "lose" and s.reputation.helios == 0, "판정 실패는 fail_next와 fail_effects")
	_expect(d.current().speaker_name == "" and d.current().speaker == "narrator", "narrator는 이름이 없다")
	d.choose(0)
	_expect(d.node_id == "hello", "선택지 없는 노드의 next")

	var p := s.power
	r = d.choose(1)
	_expect(s.power == p - 50 + 5 and d.node_id == "hello", "비용을 치르고 다음 노드 효과까지 적용")
	s.power = 10
	_expect(not d.current().choices[1].enabled, "전력이 모자라면 비용 선택지가 막힌다")

	s.recruit("ian")
	s.stats.tech = 1
	cur = d.current()
	_expect(cur.choices[2].enabled, "동료가 타면 동료 선택지가 열린다")
	r = d.choose(3)
	_expect(r.roll_text.contains("이안 2"), "동료 보너스가 판정에 붙는다 (%s)" % r.roll_text)

	d = DialogueRunner.new(s, "t_dlg")
	d._enter("hello")
	r = d.choose(4)
	_expect(d.dialogue_id == "t_other" and d.node_id == "start" and s.pending_dialogue == "", "대화 안의 start_dialogue는 바로 이어진다")
	d.choose(0)
	_expect(d.is_finished(), "next가 빈 문자열이면 끝")

	_expect(DialogueRunner.new(s, "no_such_dialogue").is_finished(), "없는 대화는 바로 끝")

	# 실제 데이터의 배급관 대화: 처음엔 greet, 다음엔 again
	var t := GameState.new(data, 25)
	d = DialogueRunner.new(t, "ration_clerk")
	_expect(d.node_id == "greet" and t.flags.has("met_ration_clerk"), "배급관 첫 대화")
	_expect(DialogueRunner.new(t, "ration_clerk").node_id == "again", "배급관 다시 대화")
	data.free()


func test_quests() -> void:
	var data := _load_data()
	if data == null:
		return
	_add_test_content(data)
	var s := GameState.new(data, 26)
	_expect(not s.quest_ready("t_deliver"), "맡기 전에는 준비 안 됨")
	s.quests["t_deliver"] = "active"
	s.quests["t_visit"] = "active"
	s.quests["t_flag"] = "active"
	s.add_cargo("raw_food", 10)
	_expect(not s.quest_ready("t_deliver"), "납품: 목표 구역 밖이면 안 됨")
	s.city = "helios"
	s.enter_location("helios_hq")
	_expect(s.quest_ready("t_deliver"), "납품: 목표 구역에서 화물이 있으면 됨")
	_expect(EventRunner.requirements_met(s, [{ "type": "quest_ready", "quest": "t_deliver" }]), "quest_ready 조건")
	_expect(EventRunner.requirements_met(s, [{ "type": "quest", "quest": "t_deliver", "state": "ready" }]), "quest state ready 조건")
	s.remove_cargo("raw_food", 1)
	_expect(not s.quest_ready("t_deliver"), "납품: 화물이 모자라면 안 됨")

	_expect(not s.quest_ready("t_visit"), "방문: 가기 전")
	s.leave_location()
	s.enter_location("helios_plaza")
	s.leave_location()
	_expect(s.quest_ready("t_visit"), "방문: 한 번 들르면 됨")

	_expect(not s.quest_ready("t_flag"), "플래그: 서기 전")
	s.flags["t_goal"] = true
	_expect(s.quest_ready("t_flag"), "플래그: 서면 됨")
	s.quests["t_flag"] = "done"
	_expect(not s.quest_ready("t_flag"), "끝난 의뢰는 준비 상태가 아니다")
	data.free()


func test_companions() -> void:
	var data := _load_data()
	if data == null:
		return
	var s := GameState.new(data, 27)
	_expect(s.battle_squad()[1].name == data.combat.mercenary.name, "동료가 없으면 임시 용병")
	s.recruit("morae")
	var mate: Dictionary = s.battle_squad()[1]
	_expect(mate.name == "모래" and mate.hp == 16 and mate.weapon == "rifle", "동료가 용병 자리를 대신한다")
	_expect(s.start_battle("raider_roadblock").units.any(func(u): return u.get("name") == "모래"), "전투에 동료가 나간다")
	_expect(s.stat_bonus("survival") == 2 and s.stat_bonus("tech") == 0, "동료 보너스는 bonus_stat에만")

	s.recruit("han")
	s.power = 100
	s._advance_day()
	_expect(s.companion == "han" and s.pending_notices.is_empty(), "조건이 안 맞으면 동료는 남는다")
	s.power = 20
	s._advance_day()
	_expect(s.companion == "" and s.flags.has("companion_left_han"), "leave_if가 맞으면 하루가 지날 때 떠난다")
	var n: Dictionary = s.pending_notices[0] if not s.pending_notices.is_empty() else {}
	_expect(n.get("type") == "companion_left" and n.get("companion") == "han" and n.get("text") == data.companions.han.leave_text, "동료 이탈 알림")
	_expect(s.battle_squad()[1].name == data.combat.mercenary.name, "떠나면 다시 임시 용병")

	# 여러 날 이동해도 한 번만 떠난다.
	var t := GameState.new(data, 28)
	t.recruit("ian")
	t.reputation.helios = 80
	t.travel("undergrid")
	_expect(t.companion == "" and t.pending_notices.size() == 1, "이동 중 하루에 한 번 확인, 알림 하나")
	data.free()


func test_city_validation() -> void:
	var data := _load_data()
	if data == null:
		return
	_add_test_content(data)
	data.errors.clear()
	data.validate()
	var own := Array(data.errors).filter(func(e): return e.contains("/t_"))
	_expect(own.is_empty(), "테스트용 대화·의뢰는 검증 통과 %s" % [own])

	data.dialogues["t_bad"] = { "id": "t_bad", "start": "nowhere", "nodes": {
		"a": { "speaker": "stranger", "text": "x", "choices": [
			{ "text": "가기", "next": "missing", "check": { "stat": "luck", "dc": 10 } },
			{ "text": "효과", "next": "", "requires": [{ "type": "quest", "quest": "no_quest" }],
				"effects": [{ "type": "recruit", "companion": "nobody" }, { "type": "start_dialogue", "dialogue": "no_dlg" }] },
		] } } }
	data.quests["t_badq"] = { "id": "t_badq", "giver": "nobody", "title": "나쁜 의뢰",
		"objective": { "type": "deliver", "good": "gold", "qty": 0 }, "reward": [{ "type": "power" }] }
	data.companions["t_badc"] = { "id": "t_badc", "npc": "ration_clerk", "combat": { "hp": 1, "focus": 1, "might": 1, "weapon": "laser" } }
	data.errors.clear()
	data.validate()
	var text := "\n".join(data.errors)
	var expect_err := func(needle: String, label: String) -> void:
		_expect(text.contains(needle), "검증: %s" % label)
	expect_err.call("dialogues/t_bad: start가 없는 노드", "start 노드")
	expect_err.call("speaker가 NPC id도", "speaker")
	expect_err.call("next가 없는 노드를 가리킨다 'missing'", "next 노드")
	expect_err.call("알 수 없는 stat 'luck'", "check stat")
	expect_err.call("requires.quest가 없는 id", "quest 조건")
	expect_err.call("effect.companion가 없는 id", "recruit 효과")
	expect_err.call("effect.dialogue가 없는 대화", "start_dialogue 효과")
	expect_err.call("quests/t_badq: giver", "의뢰 giver")
	expect_err.call("objective.good", "의뢰 목표 물품")
	expect_err.call("objective.qty", "의뢰 목표 수량")
	expect_err.call("quests/t_badq/reward: power 효과에 delta가 없다", "보상 효과")
	expect_err.call("companions/t_badc: combat.weapon", "동료 무기")
	expect_err.call("companions/t_badc: npc 'ration_clerk'의 companion", "동료와 NPC 연결")
	data.free()


## 실제 대화 데이터의 모든 노드, 모든 선택지가 오류 없이 실행된다.
func test_all_dialogues_run() -> void:
	var data := _load_data()
	if data == null:
		return
	var count := 0
	for id in data.dialogues:
		for node_id in data.dialogues[id].get("nodes", {}):
			var n: int = maxi(1, data.dialogues[id].nodes[node_id].get("choices", []).size())
			for i in n:
				var s := GameState.new(data, 30 + count)
				s.power = 1000
				var d := DialogueRunner.new(s, id)
				d._enter(node_id)
				d.current()
				d.choose(i)
				d.current()
				count += 1
	_expect(count > 0, "모든 대화 선택지 실행 (%d개)" % count)
	data.free()


func test_dialogue_view() -> void:
	var data := _load_data()
	if data == null:
		return
	_add_test_content(data)
	var s := GameState.new(data, 31)
	var view: Control = load("res://scripts/ui/dialogue_view.gd").new()
	root.add_child(view)
	var done := [false]
	view.finished.connect(func(): done[0] = true)
	view.start(s, "t_dlg")
	_expect(view._name_label.text == "배급관 오르" and view._text_label.text.contains("운반꾼"), "대화 창: 이름과 대사")
	_expect(view._buttons.size() == 5 and view._buttons[2].disabled, "대화 창: 선택지 버튼, 막힌 선택지는 비활성")
	_expect(view._portrait_frame.get_child_count() == 1, "대화 창: 초상화 또는 첫 글자 틀")
	_expect(view._result_box.get_child_count() == 1, "대화 창: 첫 노드 효과 줄")
	s.stats.negotiation = 30
	view._buttons[0].pressed.emit()
	# 판정이 있으면 주사위 연출이 뜬다: 굴리기 -> (바로) 결과 -> 계속
	var dice: Node = null
	for c in view.get_children():
		if c.has_method("play"):
			dice = c
	_expect(dice != null and view._buttons.is_empty(), "대화 창: 판정은 주사위 연출로, 그동안 선택지 없음")
	if dice != null:
		_expect(dice._chance() == 100 and dice._roll.dc == 15, "주사위: 난이도와 성공 확률 (%d%%)" % dice._chance())
		dice._advance()
		_expect(dice._phase == "rolling", "주사위: 굴리기 시작")
		dice._advance()
		_expect(dice._phase == "done" and dice._verdict.text.begins_with("대성공") or dice._verdict.text == "성공",
			"주사위: 결과 (%s)" % dice._verdict.text)
		dice._advance()
	_expect(view._buttons.size() == 1 and view._result_box.get_child_count() >= 2, "대화 창: 판정 뒤 결과와 계속 버튼")
	view._buttons[0].pressed.emit()
	_expect(view._text_label.text == "좋아.", "대화 창: 계속하면 다음 노드")
	view._buttons[0].pressed.emit()
	_expect(done[0], "대화 창: 끝나면 finished")
	data.free()


## 도시 거리: 모든 도시에서 도시 입구, 구역 입구 4곳, 대화할 수 있는 NPC가 거리에 놓이고,
## 입구 앞에서 E를 누르면 그 구역으로 들어간다.
func test_town_view() -> void:
	var gd: Node = root.get_node("GameData")
	if gd.cities.is_empty():
		gd.load_all()
	var s := GameState.new(gd, 32)
	for city_id in gd.cities:
		s.city = city_id
		var view: Control = load("res://scripts/ui/town_view.gd").new()
		view.size = Vector2(1280, 720)
		root.add_child(view)
		view.build(s)
		var kinds := {}
		for spot in view._spots:
			kinds[spot.kind] = kinds.get(spot.kind, 0) + 1
		_expect(kinds.get("gate", 0) == 1 and kinds.get("door", 0) == 4 and kinds.get("npc", 0) == 4,
			"거리 %s: 입구 1, 구역 4, NPC 4 (%s)" % [city_id, kinds])
		_expect(gd.towns.has(city_id) and view._width > 640.0, "거리 %s: 배치와 거리 그림" % city_id)
		view.queue_free()
	s.city = "helios"
	var view: Control = load("res://scripts/ui/town_view.gd").new()
	root.add_child(view)
	view.build(s, float(gd.towns.helios.doors.helios_plaza))
	var opened := [""]
	view.open_location.connect(func(id): opened[0] = id)
	view._update_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	view._unhandled_key_input(key)
	_expect(opened[0] == "helios_plaza", "거리: 입구 앞에서 E를 누르면 그 구역으로 (%s)" % opened[0])
	view.queue_free()


## 초반 안내: 도시에 들어서면 첫 목표를 알리고, 조건을 채우면 다음 목표로 넘어가며 알린다.
func test_guide() -> void:
	var data := _load_data()
	if data == null:
		return
	_expect(data.guide.size() >= 5 and data.dialogues.has("prologue"), "안내 단계와 프롤로그 데이터")
	var s := GameState.new(data, 33)
	s.update_guide()
	_expect(s.pending_notices.is_empty(), "도시에 들어서기 전엔 안내 없음")
	s.visited_cities[s.city] = true
	s.update_guide()
	_expect(s.pending_notices.size() == 1 and s.guide_step == 0, "첫 목표 안내")
	s.add_cargo("raw_food", 6)
	s.update_guide()
	_expect(s.guide_step == 1 and s.pending_notices.back().title == "목표 달성", "생식량을 사면 다음 목표")
	s.city = "helios"
	s.flags["met_aurel_beck"] = true
	s.update_guide()
	_expect(s.guide_step == 3, "여러 목표를 한 번에 넘긴다 (%d)" % s.guide_step)
	s.quests["beck_first_job"] = "done"
	s.quests["nova_first_job"] = "active"
	s.quests["soha_first_job"] = "active"
	s.update_guide()
	_expect(s.guide_step == 5, "의뢰 수 조건 (quest_count) (%d)" % s.guide_step)
	_expect(EventRunner.requirements_met(s, [{ "type": "quest_count", "state": "done", "min": 1 }])
		and not EventRunner.requirements_met(s, [{ "type": "quest_count", "state": "done", "min": 2 }]), "끝낸 의뢰만 센다")
	_expect(not EventRunner.requirements_met(s, [{ "type": "any_crisis" }]), "정세 사건 없음")
	data.free()


## 테스트용 의뢰와 대화. 실제 이야기 데이터와 겹치지 않게 t_ 로 시작한다.
func _add_test_content(data: Node) -> void:
	data.quests["t_deliver"] = { "id": "t_deliver", "giver": "aurel_beck", "title": "시험 납품", "summary": "",
		"objective": { "type": "deliver", "good": "raw_food", "qty": 10, "location": "helios_hq" },
		"reward": [{ "type": "power", "delta": 120 }, { "type": "reputation", "city": "helios", "delta": 10 }] }
	data.quests["t_visit"] = { "id": "t_visit", "giver": "aurel_beck", "title": "시험 방문", "summary": "",
		"objective": { "type": "visit", "location": "helios_plaza" }, "reward": [] }
	data.quests["t_flag"] = { "id": "t_flag", "giver": "aurel_beck", "title": "시험 플래그", "summary": "",
		"objective": { "type": "flag", "flag": "t_goal" }, "reward": [] }
	data.dialogues["t_dlg"] = { "id": "t_dlg", "start": "hello",
		"variants": [{ "requires": [{ "type": "flag", "flag": "t_seen" }, { "type": "day", "min": 1 }], "start": "again" }],
		"nodes": {
			"hello": { "speaker": "ration_clerk", "text": "어서 와, {player}.",
				"effects": [{ "type": "flag_set", "flag": "t_seen" }, { "type": "power", "delta": 5 }],
				"choices": [
					{ "text": "설득한다", "check": { "stat": "negotiation", "dc": 15 }, "next": "win", "fail_next": "lose",
						"effects": [{ "type": "reputation", "city": "helios", "delta": 3 }],
						"fail_effects": [{ "type": "reputation", "city": "helios", "delta": -3 }] },
					{ "text": "돈을 낸다", "cost": [{ "type": "power", "amount": 50 }], "next": "hello" },
					{ "text": "이안에게 맡긴다", "requires": [{ "type": "companion", "companion": "ian" }], "next": "" },
					{ "text": "고친다", "check": { "stat": "tech", "dc": 1 }, "next": "", "fail_next": "" },
					{ "text": "숨은 선택지", "requires": [{ "type": "flag", "flag": "t_never" }], "hide_if_blocked": true, "next": "" },
					{ "text": "다른 이야기", "next": "", "effects": [{ "type": "start_dialogue", "dialogue": "t_other" }] },
				] },
			"win": { "speaker": "player", "text": "좋아." },
			"lose": { "speaker": "narrator", "text": "말이 통하지 않았다.", "next": "hello" },
			"again": { "speaker": "ration_clerk", "text": "또 왔나.", "choices": [{ "text": "끝", "next": "" }] },
		} }
	data.dialogues["t_other"] = { "id": "t_other", "start": "start", "nodes": {
		"start": { "speaker": "narrator", "text": "다른 대화.", "choices": [{ "text": "끝", "next": "" }] } } }


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
