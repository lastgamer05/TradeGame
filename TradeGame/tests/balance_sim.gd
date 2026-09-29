## 전투 밸런스 확인용. 조우마다 40판을 간단한 봇(엄폐 찾아 사격, 도주 안 함)으로 돌려 결과를 출력한다.
## godot --headless --path <프로젝트> --script res://tests/balance_sim.gd
extends SceneTree
func _initialize():
	var data = load("res://scripts/autoload/game_data.gd").new()
	data.load_all()
	for enc in data.combat.encounters:
		var res := {}
		var turns := 0
		for sd in 40:
			var s := GameState.new(data, 1000 + sd)
			s.stats.focus = 3
			s.stats.survival = 2
			var b := s.start_battle(enc)
			var g := 0
			while b.result == "" and g < 60:
				g += 1
				for u in b.active_units("player"):
					# 엄폐된 칸 중 적을 쏠 수 있는 곳으로 이동 후 사격
					var best_t := {}
					var best_c := 0
					for e in b.active_units("enemy"):
						var c = b.hit_chance(u, e)
						if c > best_c: best_c = c; best_t = e
					if best_c >= 40:
						b.attack(u, best_t); continue
					var moves = b.reachable(u)
					var bestpos: Vector2i = u.pos
					var bestscore := -999.0
					for cell in moves:
						var sc := 0.0
						var near := 99
						for e in b.active_units("enemy"):
							near = mini(near, Battle.hex_dist(cell, e.pos))
							sc += b.cover_level(cell, e.pos) * 3
						sc -= abs(near - 6)
						if sc > bestscore: bestscore = sc; bestpos = cell
					b.move(u, bestpos)
					best_c = 0
					for e in b.active_units("enemy"):
						var c = b.hit_chance(u, e)
						if c > best_c: best_c = c; best_t = e
					if best_c > 0: b.attack(u, best_t)
					elif u.ap > 0: b.hide(u)
				b.end_player_turn()
			turns += b.turn
			res[b.result] = res.get(b.result, 0) + 1
		print(enc, " ", res, " avg turns ", turns / 40.0)
	quit()
