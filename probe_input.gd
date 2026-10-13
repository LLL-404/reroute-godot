extends SceneTree

# C4 判定：输入闭环端到端。
# 通过 Window.push_input 注入真实鼠标/键盘事件，断言 world 状态按预期变化：
#   单击放墙 / 拖拽放墙线 / 挖矿(矿+25) / 放塔(施工压扁) / 拆除(退 50%) /
#   英雄移动 / 原地目标被拒 / TAB 热层开关 / SOLID 格零副作用 / 暂停中零副作用。
# 跑法（cwd=reroute-godot）：godot --headless -s res://probe_input.gd
var checks := 0
var bad := 0
var first_bad := ""
var fail_list: Array = []
var vp_size := Vector2(1280.0, 720.0)


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame # -s 模式：_ready 在首帧才跑；set_process 须在 ready 之后调用才粘
	main.set_process(false) # 探针独占推进（无 tick 干扰）
	main.start_match() # 进入对局（R6 起启动即标题屏；本探针测对局内输入）
	var view = main.view
	var world = main.world
	vp_size = get_root().get_visible_rect().size
	print("[INPUT] viewport=", vp_size)

	# ---- 扫描可点击格（unproject → pick 回环一致，保证注入命中目标格）----
	var used: Array = []
	var row_cells: Array = []
	var row := _find_row(view, world, 8, 6, 36, 26, 4, used)
	_gcheck(row.x >= 0, "4 连可点击行")
	if row.x >= 0:
		for k in 4:
			row_cells.append(Vector2i(row.x + k, row.y))
		for c in row_cells:
			used.append(c) # 行格全部排除，防与单击/塔/英雄格重叠
	var cellA := _find_clickable(view, world, 8, 6, 36, 26, false, used)
	_gcheck(cellA.x >= 0, "单击墙格")
	used.append(cellA)
	var cellD := _find_clickable(view, world, 8, 6, 36, 26, false, used)
	_gcheck(cellD.x >= 0, "塔格")
	used.append(cellD)
	var cellE := _find_clickable(view, world, 8, 6, 36, 26, false, used)
	_gcheck(cellE.x >= 0, "英雄目标格")
	used.append(cellE)
	var ore_cell := _find_ore(view, world)
	_gcheck(ore_cell.x >= 0, "可点击矿格")
	var solid_cell := _find_solid_block(view, world)
	_gcheck(solid_cell.x >= 0, "可点击实心块格")
	if bad > 0:
		_finish()
		return

	# ---- 1. 单击放墙 ----
	main.set_mode("wall")
	var sup0: int = world.supply
	await _click(view, cellA)
	var bA = world.building_at(cellA.x, cellA.y)
	_gcheck(bA != null and int(bA["kind"]) == Sim.B_WALL, "单击放墙")
	_cmp_int(world.supply, sup0 - 10, "放墙扣费 10")
	view.sync(world)
	_cmp_int(view.building_nodes.size(), 2, "墙节点出现（核心+墙）")

	# ---- 2. 拖拽放墙线（4 连）----
	main.set_mode("wall")
	var sup1: int = world.supply
	var n0: int = world.buildings.size()
	await _drag(view, row_cells[0], row_cells[3])
	_cmp_int(world.buildings.size(), n0 + 4, "拖拽放墙 4 格")
	_cmp_int(world.supply, sup1 - 40, "拖拽扣费 40")

	# ---- 3. 挖矿 ----
	main.set_mode("dig")
	var sup2: int = world.supply
	await _click(view, ore_cell)
	_cmp_int(world.grid.at(ore_cell.x, ore_cell.y), Grid.OPEN, "矿格变 OPEN")
	_cmp_int(world.supply, sup2 + 25, "挖矿 +25")

	# ---- 4. 放塔（施工压扁）----
	main.set_mode("tower")
	var sup3: int = world.supply
	await _click(view, cellD)
	var bD = world.building_at(cellD.x, cellD.y)
	_gcheck(bD != null and int(bD["kind"]) == Sim.B_TOWER, "单击放塔")
	_cmp_int(world.supply, sup3 - 60, "放塔扣费 60")
	view.sync(world)
	var eD = view.building_nodes.get(int(bD["id"]))
	_gcheck(eD != null and absf(float(eD["node"].scale.y) - 0.35) < 0.001, "塔施工压扁 0.35")

	# ---- 5. 拆除（退 50%）----
	main.set_mode("remove")
	var sup4: int = world.supply
	await _click(view, cellA)
	_gcheck(world.building_at(cellA.x, cellA.y) == null, "拆除墙")
	_cmp_int(world.supply, sup4 + 5, "拆除退款 50%（5）")

	# ---- 6. 英雄移动 + 原地目标被拒 ----
	main.set_mode("hero")
	await _click(view, cellE)
	_cmp_int(int(world.hero["tx"]), cellE.x, "英雄目标 x")
	_cmp_int(int(world.hero["ty"]), cellE.y, "英雄目标 y")
	var tx_keep: int = int(world.hero["tx"])
	await _click(view, Vector2i(int(world.hero["x"]), int(world.hero["y"])))
	_cmp_int(int(world.hero["tx"]), tx_keep, "原地目标被拒")

	# ---- 7. TAB 热层 ----
	_gcheck(view.heat_enabled() == false, "初始热层关")
	await _key(KEY_TAB)
	_gcheck(view.heat_enabled() == true, "TAB 开热层")
	await _key(KEY_TAB)
	_gcheck(view.heat_enabled() == false, "TAB 关热层")

	# ---- 8. SOLID 格放墙被拒（零副作用）----
	main.set_mode("wall")
	var sup5: int = world.supply
	await _click(view, solid_cell)
	_cmp_int(world.supply, sup5, "SOLID 格零副作用")
	_gcheck(world.building_at(solid_cell.x, solid_cell.y) == null, "SOLID 格无建筑")

	# ---- 9. 暂停中点击被拒 ----
	main.paused = true
	main.set_mode("wall")
	var sup6: int = world.supply
	var cellP := _find_clickable(view, world, 8, 6, 36, 26, false, [])
	await _click(view, cellP)
	_cmp_int(world.supply, sup6, "暂停中零副作用")
	main.paused = false

	# ---- 10. 屏幕投影一致性（赏金浮字定位口径锁定）----
	for c in [Vector2i(10, 10), Vector2i(24, 24), Vector2i(40, 30)]:
		var w: Vector3 = view.cell_to_world(c.x, c.y)
		var gyw: float = view.ground_y(c.x, c.y)
		var a: Vector2 = view.world_to_screen(w.x, gyw, w.z)
		var b: Vector2 = view.camera.unproject_position(Vector3(w.x, gyw, w.z))
		_gcheck(a.x >= 0.0 and a.distance_to(b) < 1.0, "world_to_screen 与引擎投影一致 %s (a=%s b=%s)" % [str(c), str(a), str(b)])

	_finish()


# ---------------- 注入辅助 ----------------

func _sp_of(view, cell: Vector2i) -> Vector2:
	var w: Vector3 = view.cell_to_world(cell.x, cell.y)
	var gy: float = view.ground_y(cell.x, cell.y)
	return view.camera.unproject_position(Vector3(w.x, gy + 0.1, w.z))


func _click(view, cell: Vector2i) -> void:
	var sp := _sp_of(view, cell)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = sp
	get_root().push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = sp
	get_root().push_input(up)
	await process_frame


func _drag(view, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var sp0 := _sp_of(view, from_cell)
	var sp1 := _sp_of(view, to_cell)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = sp0
	get_root().push_input(down)
	await process_frame
	var mv := InputEventMouseMotion.new()
	mv.position = sp1
	get_root().push_input(mv)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = sp1
	get_root().push_input(up)
	await process_frame


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	get_root().push_input(ev)
	await process_frame


# ---------------- 扫描辅助 ----------------

## 点击回环一致：unproject 落在屏内且 pick_cell 能还原该格（保证注入命中目标）。
func _clickable(view, world, x: int, y: int) -> bool:
	if not world.grid.passable(x, y):
		return false
	if world.building_at(x, y) != null:
		return false
	if not world.cell_vacant(x, y):
		return false
	var hr: Dictionary = world.hero
	if x == int(hr["x"]) and y == int(hr["y"]):
		return false
	var sp := _sp_of(view, Vector2i(x, y))
	if sp.x < 0.0 or sp.y < 0.0 or sp.x >= vp_size.x or sp.y >= vp_size.y:
		return false
	var back: Vector2i = view.pick_cell(sp.x, sp.y)
	return back.x == x and back.y == y


func _find_clickable(view, world, x0: int, y0: int, x1: int, y1: int, _unused: bool, exclude: Array) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if exclude.has(Vector2i(x, y)):
				continue
			if _clickable(view, world, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_row(view, world, x0: int, y0: int, x1: int, y1: int, n: int, exclude: Array) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 - n + 2):
			var ok := true
			for k in n:
				if exclude.has(Vector2i(x + k, y)) or not _clickable(view, world, x + k, y):
					ok = false
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_ore(view, world) -> Vector2i:
	for y in 48:
		for x in 48:
			if world.grid.at(x, y) == Grid.COVER and world.sc.is_ore(x, y):
				if _clickable_cover(view, world, x, y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## 矿格是 COVER（不可通行）——单独的回环检查（不走 _clickable 的 passable 前置）。
func _clickable_cover(view, world, x: int, y: int) -> bool:
	var sp := _sp_of(view, Vector2i(x, y))
	if sp.x < 0.0 or sp.y < 0.0 or sp.x >= vp_size.x or sp.y >= vp_size.y:
		return false
	var back: Vector2i = view.pick_cell(sp.x, sp.y)
	return back.x == x and back.y == y


## 实心块中心格：4 邻全 SOLID（就算拾取偏一格也仍是 SOLID，零副作用断言不误伤）。
func _find_solid_block(view, world) -> Vector2i:
	for y in range(8, 40):
		for x in range(8, 40):
			if world.grid.at(x, y) != Grid.SOLID:
				continue
			if world.grid.at(x, y + 1) != Grid.SOLID or world.grid.at(x, y - 1) != Grid.SOLID or world.grid.at(x + 1, y) != Grid.SOLID or world.grid.at(x - 1, y) != Grid.SOLID:
				continue
			if _clickable_cover(view, world, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# ---------------- 判定辅助 ----------------

func _fail(msg: String) -> void:
	bad += 1
	if first_bad == "":
		first_bad = msg
	fail_list.append(msg)


func _gcheck(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		_fail(label)


func _cmp_int(got: int, want: int, label: String) -> void:
	checks += 1
	if got != want:
		_fail(label + " got=%d want=%d" % [got, want])


func _finish() -> void:
	var ok := bad == 0 and checks >= 15
	print("[INPUT] checks=", checks, " bad=", bad)
	for i in mini(fail_list.size(), 12):
		print("[INPUT] fail: ", fail_list[i])
	print("[INPUT] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
