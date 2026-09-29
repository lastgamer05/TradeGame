extends SceneTree
## 메인 화면을 띄워 스크린샷을 저장하고 종료한다. 창이 필요하므로 --headless 없이 실행한다.
## godot --path <프로젝트> --script res://tests/screenshot.gd -- <저장 경로.png> [이벤트 id]
## 이벤트 id를 주면 능력치 창을 닫고 그 이벤트 창을 띄운 화면을 찍는다.

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and args[1] == "demo":
		# 거래 몇 번과 정세 사건이 진행 중인 화면
		var s: GameState = main.state
		s.buy("raw_food", 12)
		s.travel("helios")
		s.sell("raw_food", 6)
		s.politics.on_trade("undergrid", "chip_military", 2000, true)
		s.politics.update_crises()
		s.pending_news.clear()
		main._event_queue.clear()
		main._on_buy("suppressant", 2)
		main._close_modal()
	elif args.size() > 1 and args[1].begins_with("battle:"):
		main._close_modal()
		main._start_battle(args[1].trim_prefix("battle:"))
		await process_frame
		var view = main._battle_view
		var b: Battle = view.battle
		# 한 턴 진행한 모습: 첫 유닛 앞으로 이동, 턴 종료
		var u: Dictionary = b.active_units("player")[0]
		var cells: Array = b.reachable(u).keys()
		cells.sort_custom(func(a, c): return a.y < c.y)
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
	elif args.size() > 1:
		main._event_queue.append(root.get_node("GameData").events[args[1]])
		main._close_modal()
	for i in 10:
		await process_frame
	var path: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
