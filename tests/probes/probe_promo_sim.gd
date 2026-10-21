extends SceneTree

# 投稿视频防线配平模拟（非闸，headless）：打印波次/经济，跑黄金脚本对拍，再跑 A3 视频排期。
# 跑法：godot --headless --path . -s res://tests/probes/probe_promo_sim.gd

const TICKS := 1680 # 84s（成片 80s + 余量）


func _initialize() -> void:
	var sc := Scenario.new(20261003)
	print("[SIM] waves n=", sc.waves.size())
	for w in sc.waves:
		print("[SIM] wave ", w)
	print("[SIM] ORE_YIELD=", Sim.ORE_YIELD, " hard_cap=", sc.hard_cap_tick, " mid_ore=", sc.mid_ore, " basin_ore=", sc.basin_ore, " plug=", sc.basin_plug, " chokes=", sc.chokes)
	_golden_run(sc)
	_a3_run(sc)
	quit(0)


func _golden_run(sc: Scenario) -> void:
	var w := World.new(sc, 20261003)
	var cmds: Array = Verify.script_for(sc)
	var ci := 0
	var min_hp := 1 << 30
	for t in range(0, TICKS + 1):
		while ci < cmds.size() and int(cmds[ci][0]) <= t + 1:
			var c: Array = cmds[ci]
			var cmd := { "kind": c[1], "x": c[2], "y": c[3] }
			if c.size() > 4:
				cmd["kind_id"] = c[4]
			w.apply_command(cmd)
			ci += 1
		w.tick()
		min_hp = mini(min_hp, int(w.core["hp"]))
		if w.outcome != 0:
			break
	print("[SIM] GOLDEN t=%.1f hp=%d min=%d outcome=%d supply=%d kills=%d units=%d" % [
		float(w.tick_count) / 20.0, int(w.core["hp"]), min_hp, int(w.outcome), int(w.supply), int(w.kills), w.units.size()])


func _a3_run(sc: Scenario) -> void:
	var w := World.new(sc, 20261003)
	var paths := _trace_paths(w)
	var demo_cell := _path_cell_at_y(paths, 50, 35)
	print("[SIM] A3 demo wall anchor path cell = ", demo_cell)
	var plan: Array = _plan_a3(sc, demo_cell)
	plan.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var pi := 0
	var hp_steps: Array = []
	var min_hp := 1 << 30
	for t in range(0, TICKS + 1):
		while pi < plan.size() and int(plan[pi][0]) <= t:
			var act: Array = plan[pi]
			pi += 1
			match String(act[1]):
				"dig":
					w.apply_command({ "kind": "dig", "x": int(act[2]), "y": int(act[3]) })
				"wall":
					w.apply_command({ "kind": "wall", "x": int(act[2]), "y": int(act[3]) })
				"tower":
					w.apply_command({ "kind": "tower", "x": int(act[2]), "y": int(act[3]) })
				"multi_wall":
					for off in act[2]:
						w.apply_command({ "kind": "wall", "x": int(off[0]), "y": int(off[1]) })
				"spawn":
					for _i in int(act[2]):
						var c2 := _pick_free(w, paths, int(act[3]) + 3, int(act[4]) + 1, 5)
						if c2.x >= 0:
							w.apply_command({ "kind": "spawn", "x": c2.x, "y": c2.y, "speed": 4, "kind_id": Sim.E_SWARM })
		w.tick()
		if w.outcome != 0:
			print("[SIM] A3 DIED at t=%.1f tick=%d" % [float(t) / 20.0, w.tick_count])
			break
		if t % 100 == 0:
			hp_steps.append("%d:%d" % [int(t / 20.0), int(w.core["hp"])])
		min_hp = mini(min_hp, int(w.core["hp"]))
	var census := { "wall": 0, "tower": 0, "core": 0 }
	for b in w.buildings:
		var bkind := int(b["kind"])
		if bkind == Sim.B_WALL:
			census["wall"] += 1
		elif bkind == Sim.B_TOWER:
			census["tower"] += 1
		elif bkind == Sim.B_CORE:
			census["core"] += 1
	print("[SIM] A3 hp5s=%s" % ",".join(hp_steps))
	print("[SIM] A3 min=%d final_hp=%d outcome=%d supply=%d kills=%d units=%d census=%s" % [
		min_hp, int(w.core["hp"]), int(w.outcome), int(w.supply), int(w.kills), w.units.size(), census])
	# 存活单位明细（看有没有卡死/未进场）
	for u in w.units:
		print("[SIM] A3 unit kind=%d at=(%d,%d) hp=%d traveled=%d" % [
			int(u["kind"]), int(u["x"]), int(u["y"]), int(u["hp"]), int(u["traveled"])])


func _plan_a3(sc: Scenario, demo_cell: Vector2i) -> Array:
	var ore: Array = sc.mid_ore
	var bo: Array = sc.basin_ore
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var cx := sc.core.x
	var plan: Array = [
		# 经济：挖矿（t=1~3s）
		[20, "dig", ore[0].x, ore[0].y], [20, "dig", ore[1].x, ore[1].y],
		[20, "dig", bo[2].x, bo[2].y], [20, "dig", bo[6].x, bo[6].y],
		[40, "dig", ore[2].x, ore[2].y], [40, "dig", ore[3].x, ore[3].y], [40, "dig", ore[4].x, ore[4].y],
		[40, "dig", bo[10].x, bo[10].y], [40, "dig", bo[1].x, bo[1].y],
		[60, "dig", bo[5].x, bo[5].y], [60, "dig", bo[9].x, bo[9].y], [60, "dig", bo[0].x, bo[0].y],
		[60, "dig", bo[4].x, bo[4].y], [60, "dig", bo[8].x, bo[8].y],
		# 西咽喉：漏斗墙 + 三塔（t=5~8.5s）
		[100, "multi_wall", [[cw.x - 2, cw.y + 3], [cw.x - 1, cw.y + 3], [cw.x + 1, cw.y + 3], [cw.x + 2, cw.y + 3]]],
		[110, "tower", cw.x - 1, cw.y - 2],
		[140, "tower", cw.x + 1, cw.y - 2],
		[170, "tower", cw.x - 2, cw.y - 1],
		[200, "multi_wall", [[cw.x - 1, cw.y + 1], [cw.x + 1, cw.y + 1]]],
		# 东咽喉：漏斗墙 + 三塔（t=11~15s）
		[220, "multi_wall", [[ce.x - 2, ce.y + 3], [ce.x - 1, ce.y + 3], [ce.x + 1, ce.y + 3], [ce.x + 2, ce.y + 3]]],
		[240, "tower", ce.x - 1, ce.y - 2],
		[260, "tower", ce.x + 1, ce.y - 2],
		[280, "tower", ce.x - 2, ce.y - 1],
		[300, "multi_wall", [[ce.x - 1, ce.y + 1], [ce.x + 1, ce.y + 1]]],
		# 核心区两塔（漏网补刀）
		[300, "tower", cx - 4, 12],
		[500, "tower", cx + 3, 12],
		# 视频演示墙：改道（t=30s，5 格压线 + 两侧留口）
		[600, "multi_wall", [[demo_cell.x - 3, demo_cell.y], [demo_cell.x - 2, demo_cell.y], [demo_cell.x - 1, demo_cell.y], [demo_cell.x, demo_cell.y], [demo_cell.x + 1, demo_cell.y]]],
		# 补刷（西口，密度用）
		[240, "spawn", 2, 18, 52],
		[400, "spawn", 3, 18, 52],
		[460, "spawn", 3, 18, 52],
		[620, "spawn", 3, 18, 52],
		[880, "spawn", 4, 18, 52],
		[1000, "spawn", 3, 18, 52],
		# 补刷（东口，东线镜头用）
		[1180, "spawn", 2, 44, 52],
		[1240, "spawn", 2, 44, 52],
	]
	return plan


func _path_cell_at_y(paths: Dictionary, y: int, max_x: int) -> Vector2i:
	for p in paths:
		var v: Vector2i = p
		if v.y == y and v.x < max_x:
			return v
	return Vector2i(-1, -1)


func _trace_paths(w) -> Dictionary:
	var paths: Dictionary = {}
	for s in w.sc.spawns:
		var cur := Vector2i(s.x, s.y)
		for _i in 400:
			paths[cur] = true
			if cur.x == w.sc.core.x and cur.y == w.sc.core.y:
				break
			var best := -1
			var best_d := 1 << 30
			for k in 6:
				var nx: int = Grid.nx(cur.x, cur.y, k)
				var ny: int = Grid.ny(cur.x, cur.y, k)
				if not w.grid.passable(nx, ny):
					continue
				var d: int = w.field.dist_at(nx, ny)
				if d >= 0 and d < best_d:
					best_d = d
					best = k
			if best < 0:
				break
			cur = Vector2i(Grid.nx(cur.x, cur.y, best), Grid.ny(cur.x, cur.y, best))
	return paths


func _pick_free(w, paths: Dictionary, cx: int, cy: int, rad: int) -> Vector2i:
	for r in range(0, rad + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := cx + dx
				var y := cy + dy
				if x < 1 or x > 62 or y < 1 or y > 62:
					continue
				if not w.grid.passable(x, y):
					continue
				if w.building_at(x, y) != null:
					continue
				if not w.cell_vacant(x, y):
					continue
				if paths.has(Vector2i(x, y)):
					continue
				var hr: Dictionary = w.hero
				if x == int(hr["x"]) and y == int(hr["y"]):
					continue
				return Vector2i(x, y)
	return Vector2i(-1, -1)
