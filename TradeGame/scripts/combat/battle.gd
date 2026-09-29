class_name Battle
extends RefCounted
## 분대 턴제 타일 전투의 규칙. 화면과 분리돼 있어 테스트에서 직접 돌린다.
## 판정: d20 + 명중(원거리 집중, 근접 완력) + 무기 명중 >= 방어 + 엄폐 + 숨기 + 거리 보정.

enum Tile { FLOOR, HALF, FULL, BARREL }

## 육각 격자 (pointy-top, odd-r 오프셋). 홀수 줄이 반 칸 오른쪽으로 밀린다.
## 좌표는 Vector2i(열, 줄). 거리와 시야는 큐브 좌표로 계산한다.
const DIRS_EVEN := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 1), Vector2i(-1, 1)]
const DIRS_ODD := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(0, 1)]

var cfg: Dictionary
var encounter: Dictionary
var encounter_id: String
var location: Dictionary
var rng: RandomNumberGenerator

var w: int
var h: int
var tiles: Array = []  # tiles[y][x]
var car_cells: Array = []
var escape_cells: Array = []
## 유닛: { id, side, name, pos, hp, max_hp, aim, might, weapon, melee_weapon, ap, hidden, overwatch, boarded, down, ai, defense }
var units: Array = []
var turn := 1
var grenades := 0
var messages: Array[String] = []
## 화면이 차례대로 재생할 사건. { type, ... } 형태. 화면이 읽고 비운다.
## move{id,path} shot{from,to,weapon,melee,hit,chance} damage{id,dmg,hp_after} explode{cell,radius}
## status{id,text} board{id} car_shot{from,hit,part} phase{side} text{text}
var events: Array = []
var _move_buf := {}
## "" 이면 진행 중. victory, surrender, escaped, wiped
var result := ""
## 이번 전투에서 새로 파손된 차량 부위
var car_hits: Array = []
## 이미 파손된 부위 (전투 전 상태)
var damaged_parts: Dictionary = {}
var _negotiation := 0
var _engine_delay_used := false


## squad: [{ name, hp, focus, might, weapon, melee_weapon }], vehicle_damage: 부위 id -> true
func _init(combat_cfg: Dictionary, enc_id: String, squad: Array, negotiation: int, vehicle_damage: Dictionary, random: RandomNumberGenerator) -> void:
	cfg = combat_cfg
	encounter_id = enc_id
	encounter = cfg.encounters[enc_id]
	location = cfg.locations[encounter.location]
	rng = random
	w = int(cfg.grid.w)
	h = int(cfg.grid.h)
	grenades = int(cfg.grenades)
	_negotiation = negotiation
	damaged_parts = vehicle_damage.duplicate()
	_generate_map()
	_spawn(squad)
	messages.append("%s — %s" % [encounter.name, location.name])


# --- 맵 생성 ---

func _generate_map() -> void:
	for attempt in 50:
		_try_generate()
		if _fair():
			return
	# 공정성을 못 맞추면 엄폐물만 줄인 맵이라도 쓴다.


func _try_generate() -> void:
	tiles = []
	for y in h:
		var row := []
		row.resize(w)
		row.fill(Tile.FLOOR)
		tiles.append(row)
	# 차는 왼쪽 가장자리 가운데 4칸, 탈출 구역은 차에 붙은 칸
	var mid := h / 2
	car_cells = [Vector2i(0, mid - 1), Vector2i(0, mid), Vector2i(1, mid), Vector2i(0, mid + 1)]
	escape_cells = []
	for c in car_cells:
		for n in neighbors(c):
			if n not in car_cells and n not in escape_cells:
				escape_cells.append(n)
	# 위쪽 절반에 뿌리고 아래쪽에 거울처럼 옮긴 뒤 일부를 흩뜨린다 (양쪽 측면 밀도 맞추기).
	_scatter(Tile.FULL, int(location.full) / 2)
	_scatter(Tile.HALF, int(location.half) / 2)
	_scatter(Tile.BARREL, int(location.barrels) / 2 + int(location.barrels) % 2)
	for y in h / 2:
		for x in w:
			var t: int = tiles[y][x]
			if t == Tile.FLOOR:
				continue
			var my := h - 1 - y
			var mx := clampi(x + rng.randi_range(-1, 1), 0, w - 1)
			var m := Vector2i(mx, my)
			if tiles[my][mx] == Tile.FLOOR and not _reserved(m):
				tiles[my][mx] = t
	# 시작 지점 근처 엄폐 보장
	for zone in [_player_spawn_cells(), _enemy_spawn_cells()]:
		var need := 2 - _cover_near(zone)
		for i in maxi(need, 0):
			var spot := _free_near(zone)
			if spot != Vector2i(-1, -1):
				tiles[spot.y][spot.x] = Tile.HALF


func _scatter(t: int, count: int) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < 400:
		tries += 1
		var p := Vector2i(rng.randi_range(4, w - 4), rng.randi_range(0, h / 2 - 1))
		if tiles[p.y][p.x] != Tile.FLOOR or _reserved(p):
			continue
		if t == Tile.BARREL and (_near_cells(p, _player_spawn_cells(), 2) or _near_cells(p, _enemy_spawn_cells(), 2)):
			continue
		tiles[p.y][p.x] = t
		placed += 1


func _reserved(p: Vector2i) -> bool:
	return p in car_cells or p in escape_cells or p in _player_spawn_cells() or p in _enemy_spawn_cells()


func _player_spawn_cells() -> Array:
	return [Vector2i(3, h / 2 - 3), Vector2i(3, h / 2 + 3)]


func _enemy_spawn_cells() -> Array:
	var out := []
	for y in range(1, h - 1, 2):
		out.append(Vector2i(w - 2, y))
	return out


func _near_cells(p: Vector2i, cells: Array, dist: int) -> bool:
	for c in cells:
		if hex_dist(p, c) <= dist:
			return true
	return false


func _cover_near(cells: Array) -> int:
	var n := 0
	for y in h:
		for x in w:
			if tiles[y][x] in [Tile.HALF, Tile.FULL] and _near_cells(Vector2i(x, y), cells, 2):
				n += 1
	return n


func _free_near(cells: Array) -> Vector2i:
	var options := []
	for c in cells:
		for p in cells_within(c, 2):
			if tiles[p.y][p.x] == Tile.FLOOR and not _reserved(p):
				options.append(p)
	return options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else Vector2i(-1, -1)


## 공정성: 적 시작점에서 탈출 구역까지 길이 이어져 있고, 위아래 측면 엄폐물 수가 비슷하다.
func _fair() -> bool:
	var left := 0
	var right := 0
	for y in h:
		for x in w:
			if tiles[y][x] in [Tile.HALF, Tile.FULL]:
				if y < h / 2:
					left += 1
				elif y > h / 2:
					right += 1
	if absi(left - right) > 2:
		return false
	var dist := _flood(_player_spawn_cells()[0])
	for c in escape_cells + _enemy_spawn_cells() + [_player_spawn_cells()[1]]:
		if not dist.has(c):
			return false
	return true


# --- 유닛 배치 ---

func _spawn(squad: Array) -> void:
	var spawns := _player_spawn_cells()
	for i in squad.size():
		var s: Dictionary = squad[i]
		units.append({
			"id": "p%d" % i, "side": "player", "kind": "player" if i == 0 else "mercenary", "name": s.name, "pos": spawns[i],
			"hp": int(s.hp), "max_hp": int(s.hp), "aim": int(s.focus), "might": int(s.might),
			"weapon": s.weapon, "melee_weapon": s.get("melee_weapon", ""), "defense": int(cfg.base_defense),
			"ap": int(cfg.ap_per_turn), "hidden": false, "overwatch": false, "boarded": false, "down": false, "ai": "",
		})
	var cells := _enemy_spawn_cells()
	cells.shuffle()
	var i := 0
	for kind in encounter.enemies:
		for n in int(encounter.enemies[kind]):
			var e: Dictionary = cfg.enemies[kind]
			var weapon: Dictionary = cfg.weapons[e.weapon]
			units.append({
				"id": "e%d" % i, "side": "enemy", "kind": kind, "name": e.name, "pos": cells[i % cells.size()] - Vector2i(i / cells.size(), 0),
				"hp": int(e.hp), "max_hp": int(e.hp), "aim": int(e.aim), "might": int(e.aim),
				"weapon": e.weapon if not weapon.get("melee", false) else "", "melee_weapon": e.weapon if weapon.get("melee", false) else "",
				"defense": int(e.get("defense", cfg.base_defense)),
				"ap": 0, "hidden": false, "overwatch": false, "boarded": false, "down": false, "ai": e.ai,
			})
			i += 1


# --- 조회 ---

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


static func to_cube(p: Vector2i) -> Vector3i:
	var q := p.x - (p.y - (p.y & 1)) / 2
	return Vector3i(q, p.y, -q - p.y)


static func from_cube(c: Vector3i) -> Vector2i:
	return Vector2i(c.x + (c.y - (c.y & 1)) / 2, c.y)


static func hex_dist(a: Vector2i, b: Vector2i) -> int:
	var d := to_cube(a) - to_cube(b)
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.z)))


## 격자 좌표를 평면 좌표로 (칸 중심 간격 약 1.7). 방향 계산과 화면 배치에 쓴다.
static func to_plane(p: Vector2i) -> Vector2:
	return Vector2(sqrt(3.0) * (p.x + 0.5 * (p.y & 1)), 1.5 * p.y)


func neighbors(p: Vector2i) -> Array:
	var out := []
	for d in (DIRS_ODD if p.y & 1 else DIRS_EVEN):
		var n: Vector2i = p + d
		if _in_bounds(n):
			out.append(n)
	return out


func cells_within(p: Vector2i, r: int) -> Array:
	var out := []
	for y in range(p.y - r, p.y + r + 1):
		for x in range(p.x - r - 1, p.x + r + 2):
			var c := Vector2i(x, y)
			if _in_bounds(c) and hex_dist(p, c) <= r:
				out.append(c)
	return out


func tile(p: Vector2i) -> int:
	return tiles[p.y][p.x]


func unit_at(p: Vector2i) -> Dictionary:
	for u in units:
		if u.pos == p and not u.down and not u.boarded:
			return u
	return {}


func active_units(side: String) -> Array:
	return units.filter(func(u): return u.side == side and not u.down and not u.boarded)


func is_walkable(p: Vector2i) -> bool:
	return _in_bounds(p) and tile(p) == Tile.FLOOR and p not in car_cells and unit_at(p).is_empty()


func _flood(from: Vector2i) -> Dictionary:
	var dist := { from: 0 }
	var queue := [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for n in neighbors(c):
			if not dist.has(n) and tile(n) == Tile.FLOOR and n not in car_cells:
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


## 한 번 이동으로 갈 수 있는 칸 -> 경로. 다른 유닛이 있는 칸은 지나갈 수 없다.
func reachable(u: Dictionary) -> Dictionary:
	var paths := { u.pos: [] }
	var queue := [u.pos]
	var limit := int(cfg.move_tiles)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if paths[c].size() >= limit:
			continue
		for n in neighbors(c):
			if not paths.has(n) and is_walkable(n):
				paths[n] = paths[c] + [n]
				queue.append(n)
	paths.erase(u.pos)
	return paths


## 시야: 완전 엄폐물과 차가 가린다.
func has_los(a: Vector2i, b: Vector2i) -> bool:
	var n := hex_dist(a, b)
	var nudge := Vector3(1e-4, 2e-4, -3e-4)
	var ca := Vector3(to_cube(a)) + nudge
	var cb := Vector3(to_cube(b)) + nudge
	for i in range(1, n):
		var p := from_cube(_cube_round(ca.lerp(cb, float(i) / n)))
		if tile(p) == Tile.FULL or p in car_cells:
			return false
	return true


static func _cube_round(c: Vector3) -> Vector3i:
	var r := Vector3i(roundi(c.x), roundi(c.y), roundi(c.z))
	var d := (Vector3(r) - c).abs()
	if d.x > d.y and d.x > d.z:
		r.x = -r.y - r.z
	elif d.y > d.z:
		r.y = -r.x - r.z
	else:
		r.z = -r.x - r.y
	return r


## 공격자 방향에서 대상 옆에 붙은 엄폐. 0 없음, 1 반, 2 완전
## 엄폐로 치는 칸은 대상 옆 6칸 중 공격자 쪽으로 60도 안에 있는 칸이다.
func cover_level(target: Vector2i, attacker: Vector2i) -> int:
	var best := 0
	var to_attacker := (to_plane(attacker) - to_plane(target)).normalized()
	for p in neighbors(target):
		if (to_plane(p) - to_plane(target)).normalized().dot(to_attacker) < 0.49:
			continue
		if tile(p) == Tile.FULL or p in car_cells:
			best = maxi(best, 2)
		elif tile(p) in [Tile.HALF, Tile.BARREL]:
			best = maxi(best, 1)
	return best


## 이 공격자가 이 대상을 칠 때 쓰는 무기. 사거리 밖이거나 시야가 없으면 "".
func weapon_for(a: Dictionary, target_pos: Vector2i) -> String:
	var d := hex_dist(a.pos, target_pos)
	if d == 1 and a.melee_weapon != "":
		return a.melee_weapon
	if a.weapon != "" and d <= int(cfg.weapons[a.weapon].range) and has_los(a.pos, target_pos):
		return a.weapon
	return ""


## 명중에 필요한 d20 눈. 21 이상이면 불가능.
func _needed_roll(a: Dictionary, target: Dictionary, weapon_id: String, extra_penalty := 0) -> int:
	var wpn: Dictionary = cfg.weapons[weapon_id]
	var melee: bool = wpn.get("melee", false)
	var bonus: int = (a.might if melee else a.aim) + int(wpn.aim)
	var defense: int = target.defense
	if not melee:
		var cover := cover_level(target.pos, a.pos)
		defense += [0, int(cfg.cover_bonus.half), int(cfg.cover_bonus.full)][cover]
		var over := hex_dist(a.pos, target.pos) - int(wpn.range) / 2
		defense += maxi(over, 0) * int(cfg.range_penalty_per_tile)
	if target.hidden:
		defense += int(cfg.hide_bonus)
	return defense + extra_penalty - bonus


func hit_chance(a: Dictionary, target: Dictionary) -> int:
	var wid := weapon_for(a, target.pos)
	if wid == "":
		return 0
	return _chance(_needed_roll(a, target, wid))


static func _chance(needed: int) -> int:
	return clampi((21 - needed) * 5, 5, 95)


# --- 플레이어 행동 ---

func can_act(u: Dictionary) -> bool:
	return result == "" and u.side == "player" and not u.down and not u.boarded and u.ap > 0


func move(u: Dictionary, to: Vector2i) -> bool:
	var paths := reachable(u)
	if not can_act(u) or not paths.has(to):
		return false
	u.ap -= 1
	u.hidden = false
	for step in paths[to]:
		_step(u, step)
		_trigger_overwatch(u, "enemy")
		if u.down:
			break
	_flush_move()
	_check_end()
	return true


func attack(u: Dictionary, target: Dictionary) -> bool:
	if not can_act(u) or target.down or weapon_for(u, target.pos) == "":
		return false
	_shoot(u, target, 0)
	u.ap = 0
	_check_end()
	return true


func hide(u: Dictionary) -> bool:
	if not can_act(u):
		return false
	u.hidden = true
	u.ap = 0
	messages.append("%s: 몸을 숨긴다." % u.name)
	events.append({ "type": "status", "id": u.id, "text": "숨기" })
	return true


func set_overwatch(u: Dictionary) -> bool:
	if not can_act(u) or u.weapon == "":
		return false
	u.overwatch = true
	u.ap = 0
	messages.append("%s: 경계 태세." % u.name)
	events.append({ "type": "status", "id": u.id, "text": "경계" })
	return true


func throw_grenade(u: Dictionary, at: Vector2i) -> bool:
	if not can_act(u) or grenades <= 0 or hex_dist(u.pos, at) > int(cfg.grenade.range) or not _in_bounds(at):
		return false
	grenades -= 1
	u.ap = 0
	messages.append("%s: 수류탄을 던진다." % u.name)
	_explode(at, cfg.grenade)
	_check_end()
	return true


func can_board(u: Dictionary) -> bool:
	return can_act(u) and u.pos in escape_cells


func board(u: Dictionary) -> bool:
	if not can_board(u):
		return false
	u.boarded = true
	u.ap = 0
	messages.append("%s: 차에 탄다." % u.name)
	events.append({ "type": "board", "id": u.id })
	return true


## 적 절반 이상이 쓰러졌을 때 교섭 판정으로 항복을 받아낸다.
func can_demand_surrender() -> bool:
	if not encounter.get("surrender", false):
		return false
	var total := units.filter(func(x): return x.side == "enemy").size()
	var down := units.filter(func(x): return x.side == "enemy" and x.down).size()
	return down * 2 >= total


func demand_surrender(u: Dictionary) -> bool:
	if not can_act(u) or not can_demand_surrender():
		return false
	u.ap = 0
	var dc := int(cfg.surrender.dc_base) + int(cfg.surrender.dc_per_enemy) * active_units("enemy").size()
	var d20 := rng.randi_range(1, 20)
	var ok := d20 + _negotiation >= dc
	messages.append("%s: 항복을 요구한다. d20 %d + 교섭 %d vs DC %d → %s" % [u.name, d20, _negotiation, dc, "성공" if ok else "실패"])
	events.append({ "type": "status", "id": u.id, "text": "항복 요구 " + ("성공" if ok else "실패") })
	if ok:
		result = "surrender"
		messages.append("적이 무기를 내려놓는다.")
	return true


## 플레이어 턴 종료 → 탈출 확인 → 적 턴 → 다음 플레이어 턴 준비.
func end_player_turn() -> void:
	if result != "":
		return
	var squad := units.filter(func(u): return u.side == "player" and not u.down)
	if not squad.is_empty() and squad.all(func(u): return u.boarded):
		if damaged_parts.has("engine") and not _engine_delay_used:
			_engine_delay_used = true
			messages.append("엔진이 헛돈다. 한 턴 더 버텨야 한다.")
		else:
			result = "escaped"
			messages.append("차가 먼지를 일으키며 빠져나간다.")
			return
	events.append({ "type": "phase", "side": "enemy" })
	_enemy_turn()
	if result != "":
		return
	events.append({ "type": "phase", "side": "player" })
	turn += 1
	for u in units:
		if u.side == "player":
			u.ap = int(cfg.ap_per_turn)
			u.hidden = false
			u.overwatch = false


# --- 적 턴 ---

func _enemy_turn() -> void:
	for e in active_units("enemy"):
		e.ap = int(cfg.ap_per_turn)
		e.hidden = false
		while e.ap > 0 and result == "" and not e.down:
			if not _enemy_act(e):
				break
		if result != "":
			return
		_maybe_shoot_car(e)
	_check_end()


## 적 하나의 행동 한 번. 할 게 없으면 false.
func _enemy_act(e: Dictionary) -> bool:
	var best := {}
	var best_chance := 0
	for p in active_units("player"):
		var c := hit_chance(e, p)
		if c > best_chance:
			best_chance = c
			best = p
	if not best.is_empty() and (best_chance >= 35 or e.ap == 1 or e.ai == "machine"):
		_shoot(e, best, 0)
		e.ap = 0
		_check_end()
		return true
	var dest := _choose_enemy_move(e)
	if dest == e.pos:
		if not best.is_empty():
			_shoot(e, best, 0)
			e.ap = 0
			return true
		return false
	var path: Array = reachable(e)[dest]
	e.ap -= 1
	for step in path:
		_step(e, step)
		_trigger_overwatch(e, "player")
		if e.down:
			break
	_flush_move()
	return true


func _choose_enemy_move(e: Dictionary) -> Vector2i:
	var targets := active_units("player")
	if targets.is_empty():
		return e.pos
	var best_pos: Vector2i = e.pos
	var best_score := -INF
	var options := reachable(e)
	options[e.pos] = []
	var melee: bool = e.weapon == ""
	for cell in options:
		var nearest := 999
		var nearest_pos := Vector2i.ZERO
		for t in targets:
			var d := hex_dist(cell, t.pos)
			if d < nearest:
				nearest = d
				nearest_pos = t.pos
		var score := -float(nearest)
		if melee:
			score = -float(nearest) * 3.0
		else:
			var wrange := int(cfg.weapons[e.weapon].range)
			if nearest <= wrange and has_los(cell, nearest_pos):
				score += 6.0
			if e.ai != "machine":
				score += [0.0, 2.5, 5.0][cover_level(cell, nearest_pos)]
		if e.ai == "raider":
			score -= hex_dist(cell, car_cells[0]) * 0.3
		score += rng.randf() * 0.5
		if score > best_score:
			best_score = score
			best_pos = cell
	return best_pos


func _maybe_shoot_car(e: Dictionary) -> void:
	if e.down or e.weapon == "":
		return
	var car_cfg: Dictionary = cfg.car
	var chance: float = car_cfg.raider_shot_chance if e.ai == "raider" else car_cfg.shot_chance
	var wpn: Dictionary = cfg.weapons[e.weapon]
	var target: Vector2i = car_cells[0]
	if hex_dist(e.pos, target) > int(wpn.range) or not has_los(e.pos, target) or rng.randf() >= chance:
		return
	var d20 := rng.randi_range(1, 20)
	if d20 + e.aim + int(wpn.aim) < int(car_cfg.defense):
		messages.append("%s의 총알이 차체를 스친다." % e.name)
		events.append({ "type": "car_shot", "from": e.id, "hit": false, "part": "" })
		return
	var intact: Array = car_cfg.parts.keys().filter(func(p): return not damaged_parts.has(p))
	if intact.is_empty():
		return
	var part: String = intact[rng.randi_range(0, intact.size() - 1)]
	damaged_parts[part] = true
	car_hits.append(part)
	messages.append("%s가 차를 맞혔다! %s 파손." % [e.name, car_cfg.parts[part].name])
	events.append({ "type": "car_shot", "from": e.id, "hit": true, "part": car_cfg.parts[part].name })


# --- 공통 ---

func _shoot(a: Dictionary, target: Dictionary, penalty: int) -> void:
	var wid := weapon_for(a, target.pos)
	if wid == "":
		return
	var wpn: Dictionary = cfg.weapons[wid]
	var needed := _needed_roll(a, target, wid, penalty)
	var d20 := rng.randi_range(1, 20)
	var hit := d20 >= needed or d20 == 20
	_flush_move()
	events.append({ "type": "shot", "from": a.id, "to": target.id, "weapon": wpn.name,
		"melee": wpn.get("melee", false), "hit": hit, "chance": _chance(needed) })
	if not hit:
		messages.append("%s → %s: %s 빗나감 (%d%%)" % [a.name, target.name, wpn.name, _chance(needed)])
		return
	var dmg := rng.randi_range(int(wpn.damage[0]), int(wpn.damage[1]))
	_damage(target, dmg, "%s → %s: %s 명중 %d" % [a.name, target.name, wpn.name, dmg])


func _damage(target: Dictionary, dmg: int, msg: String) -> void:
	target.hp = maxi(0, target.hp - dmg)
	messages.append(msg)
	events.append({ "type": "damage", "id": target.id, "dmg": dmg, "hp_after": target.hp })
	if target.hp == 0 and not target.down:
		target.down = true
		target.overwatch = false
		messages.append("%s 쓰러짐." % target.name)


## 움직이는 유닛을 경계 중인 반대편 유닛이 쏜다. 경계는 한 번 쏘면 풀린다.
func _trigger_overwatch(mover: Dictionary, watcher_side: String) -> void:
	for w_unit in active_units(watcher_side):
		if not w_unit.overwatch or w_unit.weapon == "":
			continue
		if hex_dist(w_unit.pos, mover.pos) > int(cfg.weapons[w_unit.weapon].range) or not has_los(w_unit.pos, mover.pos):
			continue
		w_unit.overwatch = false
		messages.append("%s의 경계 사격!" % w_unit.name)
		_flush_move()
		events.append({ "type": "status", "id": w_unit.id, "text": "경계 사격!" })
		_shoot(w_unit, mover, int(cfg.overwatch_penalty))
		if mover.down:
			return


func _explode(at: Vector2i, blast: Dictionary) -> void:
	var r := int(blast.radius)
	events.append({ "type": "explode", "cell": at, "radius": r })
	var chain := []
	for p in cells_within(at, r):
		var u := unit_at(p)
		if not u.is_empty():
			var dmg := rng.randi_range(int(blast.damage[0]), int(blast.damage[1]))
			_damage(u, dmg, "폭발: %s %d 피해" % [u.name, dmg])
		if tile(p) == Tile.HALF:
			tiles[p.y][p.x] = Tile.FLOOR
		elif tile(p) == Tile.BARREL:
			tiles[p.y][p.x] = Tile.FLOOR
			chain.append(p)
	for p in chain:
		messages.append("통이 연쇄 폭발한다!")
		_explode(p, cfg.barrel)


func _step(u: Dictionary, cell: Vector2i) -> void:
	if _move_buf.get("id", "") != u.id:
		_flush_move()
		_move_buf = { "type": "move", "id": u.id, "path": [u.pos] }
	u.pos = cell
	_move_buf.path.append(cell)


func _flush_move() -> void:
	if not _move_buf.is_empty():
		events.append(_move_buf)
		_move_buf = {}


func _check_end() -> void:
	if result != "":
		return
	if active_units("enemy").is_empty():
		result = "victory"
		messages.append("적을 모두 쓰러뜨렸다.")
	elif units.filter(func(u): return u.side == "player" and not u.down).is_empty():
		result = "wiped"
		messages.append("분대가 전멸했다.")
