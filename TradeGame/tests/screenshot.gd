extends SceneTree
## 메인 화면을 띄워 스크린샷을 저장하고 종료한다. 창이 필요하므로 --headless 없이 실행한다.
## godot --path <프로젝트> --script res://tests/screenshot.gd -- <저장 경로.png>

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
