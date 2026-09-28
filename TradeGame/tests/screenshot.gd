extends SceneTree
## 메인 화면을 띄워 스크린샷을 저장하고 종료한다. 창이 필요하므로 --headless 없이 실행한다.
## godot --path <프로젝트> --script res://tests/screenshot.gd -- <저장 경로.png> [이벤트 id]
## 이벤트 id를 주면 능력치 창을 닫고 그 이벤트 창을 띄운 화면을 찍는다.

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		main._event_queue.append(root.get_node("GameData").events[args[1]])
		main._close_modal()
	for i in 10:
		await process_frame
	var path: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
