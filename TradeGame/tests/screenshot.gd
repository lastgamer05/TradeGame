extends SceneTree
## 메인 화면을 띄워 스크린샷을 저장하고 종료한다. 창이 필요하므로 --headless 없이 실행한다.
## godot --path <프로젝트> --script res://tests/screenshot.gd -- <저장 경로.png> [모드]
## 모드 (없으면 새 게임의 능력치 창):
##   demo                거래 몇 번과 정세 사건이 진행 중인 헬리오스 배급 시장
##   map                 도시 입구에서 연 큰 지도 (갈 수 있는 도시 하나에 마우스를 올린 모습)
##   travel:<도시 id>    시작 도시에서 그 도시로 이동한 직후 (이동 이벤트 창이나 도착 장면)
##   arrival[:도시 id]   도착 장면 (기본 헬리오스)
##   hub[:도시 id[:x]]   도시 거리 (기본 시작 도시). x를 주면 주인공이 그 자리에 선다
##   location:<구역 id>  구역 화면 (거래 구역이면 시장 표)
##   dialogue:<npc id>   그 NPC의 구역에서 대화를 연 모습
##   battle:<조우 id>    전투 화면
##   dice[:ready|roll|done]  판정 주사위 연출 (기본 done)
##   <이벤트 id>         그 이벤트 창


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mode: String = args[1] if args.size() > 1 else ""
	var arg := mode.get_slice(":", 1)
	var s: GameState = main.state
	var gd: Node = root.get_node("GameData")
	if mode != "":
		main._close_modal()
		_clear_popups(main)
	if mode == "demo":
		s.buy("raw_food", 12)
		s.travel("helios")
		s.visited_cities["greenhouse"] = true
		s.visited_cities["helios"] = true
		s.sell("raw_food", 6)
		s.politics.on_trade("undergrid", "chip_military", 2000, true)
		s.politics.update_crises()
		s.pending_news.clear()
		main._open_location("helios_market")
		_clear_popups(main)
		main._on_buy("suppressant", 2)
		_clear_popups(main)
	elif mode == "map":
		s.buy("raw_food", 8)
		main._enter_city()
		main._open_map()
		await process_frame
		var view: Node = main._body.get_child(main._body.get_child_count() - 1)
		view._on_hover(s.routes_from_here()[0].to)
	elif mode.begins_with("travel:"):
		# 큰 지도에서 이동을 누른 뒤 실제 흐름대로 보이는 화면 (이동 이벤트 또는 도착 장면)
		main._enter_city()
		main._open_map()
		main._on_travel(arg)
	elif mode.begins_with("arrival"):
		s.travel(arg if arg != "" else "helios")
		s.pending_news.clear()
		main._show_arrival(false)
		_clear_popups(main)
	elif mode.begins_with("hub"):
		if arg != "":
			s.city = arg
		s.vehicle_damage["engine"] = true
		main._enter_city()
		if mode.get_slice_count(":") > 2:
			main._town_pos[s.city] = float(mode.get_slice(":", 2))
			main._town = null
			main._refresh()
			_clear_popups(main)
	elif mode.begins_with("location:"):
		s.city = gd.locations[arg].city
		s.buy(s.market.goods_for_sale(s.city)[0], 3)
		main._enter_city()
		main._open_location(arg)
		_clear_popups(main)
	elif mode.begins_with("dialogue:"):
		var loc: String = gd.npcs[arg].location
		s.city = gd.locations[loc].city
		main._enter_city()
		main._open_location(loc)
		_clear_popups(main)
		main._on_talk(arg)
	elif mode.begins_with("dice"):
		main._enter_city()
		var dice: Control = load("res://scripts/ui/dice_roll_view.gd").new()
		main.add_child(dice)
		dice.play({ "d20": 14, "stat_name": "교섭", "base": 2, "bonus": 2, "bonus_name": "이안",
			"total": 18, "dc": 15, "success": true })
		if arg != "ready":
			dice._advance()
			for i in 20:
				await process_frame
			if arg != "roll":
				dice._advance()
				for i in 20:
					await process_frame
	elif mode.begins_with("battle:"):
		main._start_battle(arg)
		await process_frame
		var view = main._battle_view
		var b: Battle = view.battle
		# 한 턴 진행한 모습: 첫 유닛 앞으로 이동, 턴 종료
		var u: Dictionary = b.active_units("player")[0]
		var cells: Array = b.reachable(u).keys()
		cells.sort_custom(func(a, c): return a.x > c.x)
		b.move(u, cells[0])
		b.end_player_turn()
		view.speed = 20.0
		await view._play_events()
		view.speed = 1.0
		view._select_next()
		# 선택 유닛의 이동 경로 미리보기
		var sel: Dictionary = view._selected()
		var reach: Dictionary = b.reachable(sel)
		var far: Vector2i = sel.pos
		for c in reach:
			if reach[c].size() > reach.get(far, []).size():
				far = c
		view.hover = far
		view._refresh()
	elif mode != "":
		main._event_queue.append(gd.events[mode])
		main._show_next_event()
	for i in 10:
		await process_frame
	var path: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()


## 도착 대화, 무작위 구역 이벤트처럼 찍으려는 화면을 가리는 창을 닫는다.
func _clear_popups(main: Node) -> void:
	main._event_queue.clear()
	main._then.clear()
	main._overlay.visible = false
	if main._dialogue_view != null:
		main._dialogue_view.queue_free()
		main._dialogue_view = null
