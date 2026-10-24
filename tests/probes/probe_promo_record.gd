extends SceneTree

# 投稿视频导演脚本（非闸）——A=实机视频长片 / B=讲解视频实机段（同默认图 seed 20261003，不同段落/机位）。
# 时间轴按模拟 tick 对齐（20Hz）；A 排期与 probe_promo_sim.gd 的 A3 计划逐条一致（含补刷顺序）。
#   预览：$env:PROMO_KIND='A'; $env:PROMO_MODE='shots'; godot --resolution 1920x1080 -s res://tests/probes/probe_promo_record.gd
#   录制：$env:PROMO_KIND='A'; $env:PROMO_MODE='movie'; godot --resolution 1920x1080 --write-movie out.avi --fixed-fps 30 -s res://tests/probes/probe_promo_record.gd
# 截图落在 res://shots/promo_test/，文件名含 T（脚本秒 = 成片时间）。

const TPS := 20.0 # 模拟 tick/秒

var main = null
var view = null
var world = null
var kind := "A"
var shots := false
var shot_dir := "res://shots/promo_test/"
var paths: Dictionary = {}
var plan: Array = []
var plan_ci := 0
var demo_walls: Array = []


func _initialize() -> void:
	kind = OS.get_environment("PROMO_KIND")
	if kind == "":
		kind = "A"
	shots = OS.get_environment("PROMO_MODE") == "shots"

	var packed: PackedScene = load("res://game/app/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame

	main.run_index = -1 # new_game() 内自增 1 → run0 → seed 20261003（默认经典图）
	main.new_game()
	main.start_match()
	view = main.view
	world = main.world

	if shots:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	print("[DIR] boot core=%s spawns=%s run=%d" % [world.sc.core, world.sc.spawns, main.run_index])

	var wd := create_timer(150.0)
	wd.timeout.connect(func() -> void:
		print("[PROMO] watchdog quit at t=%.1f" % (float(world.tick_count) / TPS))
		quit(0)
	)

	_trace_paths()
	demo_walls = _demo_walls()
	plan = _build_plan(demo_walls)
	print("[PROMO] paths=%d demo_walls=%s" % [paths.size(), demo_walls])

	if kind == "A":
		await _timeline_a()
	else:
		await _timeline_b()

	print("[PROMO] done kind=%s t=%.1f tick=%d hp=%d supply=%d kills=%d outcome=%d" % [
		kind, float(world.tick_count) / TPS, world.tick_count, int(world.core["hp"]), int(world.supply), int(world.kills), int(world.outcome)])
	quit(0)


# ---------------- 时间轴 A：实机视频（约 79s） ----------------

func _timeline_a() -> void:
	_cam_now(Vector2i(33, 30), 0.95)
	await _to(10)
	await _cam_to_tick(Vector2i(23, 47), 0.60, 60) # 0.5-3.5s 推近西线
	await _beat("push", true)

	var wf := [Vector2i(20, 45), Vector2i(21, 45), Vector2i(23, 45), Vector2i(24, 45)]
	await _to(72)
	view.show_ghost(wf, false)
	await _to(100) # 计划在 100 号盖西漏斗墙
	view.show_ghost([], false)
	await _beat("wall_w", true)

	await _ghost_build_tower(Vector2i(21, 40), 110)
	await _beat("tower1")
	await _ghost_build_tower(Vector2i(23, 40), 140)
	await _beat("tower2")
	await _ghost_build_tower(Vector2i(20, 41), 170)
	await _beat("tower3", true)

	var iw := [Vector2i(21, 43), Vector2i(23, 43)]
	await _to(190)
	view.show_ghost(iw, false)
	await _to(200)
	view.show_ghost([], false)
	await _beat("inner_w")

	await _cam_to_tick(Vector2i(23, 48), 0.58, 120) # →330
	await _to(320)
	await _beat("kill1", true) # 波3 击杀
	await _cam_to_tick(Vector2i(23, 49), 0.55, 100) # →420 推近击杀带
	await _to(430)
	await _beat("kill2", true) # 波4+补刷击杀
	await _cam_to_tick(Vector2i(23, 49), 0.56, 140) # →570
	await _to(580)
	view.show_ghost(demo_walls, false)
	await _to(600) # 计划在 600 号盖演示墙
	view.show_ghost([], false)
	await _beat("wall_demo", true)
	_set_heat(true)
	await _beat("reroute", true) # 30.3s 热层看改道
	await _to(680)
	await _beat("reroute2", true) # 34s 热层稳定后（色带可见）
	await _to(700)
	_set_heat(false)
	await _beat("heat_off")

	await _cam_to_tick(Vector2i(23, 47), 0.58, 100) # →800
	await _to(830)
	await _beat("bigwave", true) # 41.5s 大波（西 10 + 东 6）
	await _to(920)
	await _beat("battle", true) # 46s 会战
	await _cam_to_tick(Vector2i(23, 47), 0.58, 120) # →1040
	await _to(1050)
	await _beat("battle2", true)
	await _cam_to_tick(Vector2i(46, 47), 0.58, 120) # →1170 东线
	await _to(1210)
	await _beat("east", true)
	await _to(1290)
	await _beat("east_kill", true)
	await _cam_to_tick(Vector2i(33, 30), 0.95, 120) # →1410 拉远
	await _to(1440)
	await _beat("outro", true)
	await _to(1560)
	await _beat("outro2", true)
	print("[PROMO] A end hp=%d kills=%d supply=%d t=%.1f" % [int(world.core["hp"]), int(world.kills), int(world.supply), float(world.tick_count) / TPS])


# ---------------- 时间轴 B：讲解视频实机段（约 45s，南线机位） ----------------

func _timeline_b() -> void:
	_cam_now(Vector2i(23, 53), 0.78)
	await _to(10)
	await _cam_to_tick(Vector2i(23, 53), 0.60, 60) # 0.5-3.5s 推近西口
	await _beat("push_b", true)
	await _to(150)
	await _beat("march_b", true) # 行进
	_set_heat(true)
	await _beat("heat_on", true) # 热层：距离色带
	await _cam_to_tick(Vector2i(23, 51), 0.56, 170) # →320 缓慢北移
	await _to(340)
	await _beat("kill_b", true) # 波3 击杀 + 赏金
	await _to(380)
	_set_heat(false)
	await _cam_to_tick(Vector2i(23, 50), 0.58, 140) # →520
	await _to(560)
	await _beat("mid_b", true)
	await _to(580)
	view.show_ghost(demo_walls, false)
	await _to(600) # 计划盖演示墙
	view.show_ghost([], false)
	await _beat("wall_b", true)
	_set_heat(true)
	await _beat("reroute_b", true) # 放墙 → 改道
	await _to(680)
	await _beat("reroute2_b", true)
	await _to(700)
	_set_heat(false)
	await _beat("heat2_b")
	await _cam_to_tick(Vector2i(23, 53), 0.66, 100) # →800
	await _to(812)
	await _beat("bigwave_b", true) # 40.6s 波5 在西口出生（镜内）
	await _to(900)
	await _beat("end_b", true)
	print("[PROMO] B end hp=%d kills=%d supply=%d t=%.1f" % [int(world.core["hp"]), int(world.kills), int(world.supply), float(world.tick_count) / TPS])


# ---------------- 计划（与 probe_promo_sim.gd 一致） ----------------

func _build_plan(demo: Array) -> Array:
	var sc = world.sc
	var ore: Array = sc.mid_ore
	var bo: Array = sc.basin_ore
	var cw: Vector2i = sc.chokes[0]
	var ce: Vector2i = sc.chokes[1]
	var cx: int = sc.core.x
	var anchor: Vector2i = demo[3] if demo.size() >= 4 else Vector2i(-1, -1)
	var plan_list: Array = [
		[20, "dig", ore[0].x, ore[0].y], [20, "dig", ore[1].x, ore[1].y],
		[20, "dig", bo[2].x, bo[2].y], [20, "dig", bo[6].x, bo[6].y],
		[40, "dig", ore[2].x, ore[2].y], [40, "dig", ore[3].x, ore[3].y], [40, "dig", ore[4].x, ore[4].y],
		[40, "dig", bo[10].x, bo[10].y], [40, "dig", bo[1].x, bo[1].y],
		[60, "dig", bo[5].x, bo[5].y], [60, "dig", bo[9].x, bo[9].y], [60, "dig", bo[0].x, bo[0].y],
		[60, "dig", bo[4].x, bo[4].y], [60, "dig", bo[8].x, bo[8].y],
		[100, "multi_wall", [[cw.x - 2, cw.y + 3], [cw.x - 1, cw.y + 3], [cw.x + 1, cw.y + 3], [cw.x + 2, cw.y + 3]]],
		[110, "tower", cw.x - 1, cw.y - 2],
		[140, "tower", cw.x + 1, cw.y - 2],
		[170, "tower", cw.x - 2, cw.y - 1],
		[200, "multi_wall", [[cw.x - 1, cw.y + 1], [cw.x + 1, cw.y + 1]]],
		[220, "multi_wall", [[ce.x - 2, ce.y + 3], [ce.x - 1, ce.y + 3], [ce.x + 1, ce.y + 3], [ce.x + 2, ce.y + 3]]],
		[240, "tower", ce.x - 1, ce.y - 2],
		[260, "tower", ce.x + 1, ce.y - 2],
		[280, "tower", ce.x - 2, ce.y - 1],
		[300, "multi_wall", [[ce.x - 1, ce.y + 1], [ce.x + 1, ce.y + 1]]],
		[300, "tower", cx - 4, 12],
		[500, "tower", cx + 3, 12],
		[240, "spawn", 2, 18, 52],
		[400, "spawn", 3, 18, 52],
		[460, "spawn", 3, 18, 52],
		[620, "spawn", 3, 18, 52],
		[880, "spawn", 4, 18, 52],
		[1000, "spawn", 3, 18, 52],
		[1180, "spawn", 2, 44, 52],
		[1240, "spawn", 2, 44, 52],
	]
	if anchor.x > 0:
		plan_list.append([600, "multi_wall", [
			[anchor.x - 3, anchor.y], [anchor.x - 2, anchor.y], [anchor.x - 1, anchor.y],
			[anchor.x, anchor.y], [anchor.x + 1, anchor.y]]])
	plan_list.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	return plan_list


func _plan_advance(up_to: int) -> void:
	while plan_ci < plan.size() and int(plan[plan_ci][0]) <= up_to:
		var act: Array = plan[plan_ci]
		plan_ci += 1
		match String(act[1]):
			"dig", "wall", "tower":
				world.apply_command({ "kind": String(act[1]), "x": int(act[2]), "y": int(act[3]) })
			"multi_wall":
				for off in act[2]:
					world.apply_command({ "kind": "wall", "x": int(off[0]), "y": int(off[1]) })
			"spawn":
				for _i in int(act[2]):
					var c := _pick_free(int(act[3]) + 3, int(act[4]) + 1, 5)
					if c.x >= 0:
						world.apply_command({ "kind": "spawn", "x": c.x, "y": c.y, "speed": 4, "kind_id": Sim.E_SWARM })


# ---------------- 基础工具 ----------------

func _to(tick: int) -> void:
	var guard := 0
	while world.tick_count < tick and world.outcome == 0 and guard < 300000:
		guard += 1
		_plan_advance(world.tick_count)
		await process_frame
	_plan_advance(world.tick_count)


func _cam_now(cell: Vector2i, zoom: float) -> void:
	var w: Vector3 = view.cell_to_world(cell.x, cell.y)
	view.core.focus = Vector3(w.x, 0.0, w.z)
	view.core._zoom = zoom
	view.core._apply_cam()


func _cam_to_tick(cell: Vector2i, zoom: float, ticks: int) -> void:
	var t0: int = world.tick_count
	var t1: int = t0 + maxi(1, ticks)
	var f0: Vector3 = view.core.focus
	var z0: float = view.core._zoom
	var w: Vector3 = view.cell_to_world(cell.x, cell.y)
	var f1 := Vector3(w.x, 0.0, w.z)
	var guard := 0
	while world.tick_count < t1 and world.outcome == 0 and guard < 300000:
		guard += 1
		_plan_advance(world.tick_count)
		var k := float(world.tick_count - t0) / float(t1 - t0)
		if k > 1.0:
			k = 1.0
		view.core.focus = f0.lerp(f1, k)
		view.core._zoom = lerpf(z0, zoom, k)
		view.core._apply_cam()
		await process_frame
	view.core.focus = f1
	view.core._zoom = zoom
	view.core._apply_cam()


func _ghost_build_tower(cell: Vector2i, tick: int) -> void:
	await _to(tick - 8)
	view.show_ghost([cell], false)
	await _to(tick) # 计划在 tick 号盖塔
	view.show_ghost([], false)


func _set_heat(on: bool) -> void:
	view.set_heat(on)
	main.heat_on = on
	print("[PROMO] heat=%s at t=%.1f" % [on, float(world.tick_count) / TPS])


func _beat(name: String, snap: bool = false) -> void:
	print("[BEAT] %s t=%.1f tick=%d hp=%d supply=%d kills=%d" % [
		name, float(world.tick_count) / TPS, world.tick_count, int(world.core["hp"]), int(world.supply), int(world.kills)])
	if snap and shots:
		_snap(name)


func _snap(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("[SNAP] null image at ", name)
		return
	var p := "%s%s_%05.1f_%s.png" % [shot_dir, kind, float(world.tick_count) / TPS, name]
	img.save_png(p)
	print("[SNAP] ", p)


# ---------------- 路径/选址 ----------------

func _demo_walls() -> Array:
	# 从首帧路径里取西线 y=50 的路径格作为演示墙锚点（与模拟同一算法）
	var anchor := Vector2i(-1, -1)
	for p in paths:
		var v: Vector2i = p
		if v.y == 50 and v.x < 35:
			anchor = v
			break
	var out: Array = []
	if anchor.x < 0:
		return out
	for dx in range(-3, 2):
		out.append(Vector2i(anchor.x + dx, anchor.y))
	return out


func _path_cell_at_y(y: int, max_x: int) -> Vector2i:
	for p in paths:
		var v: Vector2i = p
		if v.y == y and v.x < max_x:
			return v
	return Vector2i(-1, -1)


func _trace_paths() -> void:
	paths.clear()
	for s in world.sc.spawns:
		var cur := Vector2i(s.x, s.y)
		for _i in 400:
			paths[cur] = true
			if cur.x == world.sc.core.x and cur.y == world.sc.core.y:
				break
			var best := -1
			var best_d := 1 << 30
			for k in 6:
				var nx: int = Grid.nx(cur.x, cur.y, k)
				var ny: int = Grid.ny(cur.x, cur.y, k)
				if not world.grid.passable(nx, ny):
					continue
				var d: int = world.field.dist_at(nx, ny)
				if d >= 0 and d < best_d:
					best_d = d
					best = k
			if best < 0:
				break
			cur = Vector2i(Grid.nx(cur.x, cur.y, best), Grid.ny(cur.x, cur.y, best))
	print("[PATH] cells=", paths.size())


func _pick_free(cx: int, cy: int, rad: int) -> Vector2i:
	for r in range(0, rad + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := cx + dx
				var y := cy + dy
				if x < 1 or x > 62 or y < 1 or y > 62:
					continue
				if not world.grid.passable(x, y):
					continue
				if world.building_at(x, y) != null:
					continue
				if not world.cell_vacant(x, y):
					continue
				if paths.has(Vector2i(x, y)):
					continue
				var hr: Dictionary = world.hero
				if x == int(hr["x"]) and y == int(hr["y"]):
					continue
				return Vector2i(x, y)
	return Vector2i(-1, -1)
