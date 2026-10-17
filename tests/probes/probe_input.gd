extends ProbeKit

# C4 判定：输入闭环端到端。
# 通过 Window.push_input 注入真实鼠标/键盘事件，断言 world 状态按预期变化：
#   单击放墙 / 拖拽放墙线 / 挖矿(矿+25) / 放塔(施工压扁) / 拆除(退 50%) /
#   英雄移动 / 原地目标被拒 / TAB 热层开关 / SOLID 格零副作用 / 暂停中零副作用 /
#   相机操控（WASD 平移 / QE 旋转 / 右键拖拽跟手 / 拾取回环 + 投影一致）。
# 跑法（cwd=reroute-godot，窗口模式）：godot -s res://tests/probes/probe_input.gd
# 判定：exit 0 + stdout 含 `[INPUT] PASS`。
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
	check(row.x >= 0, "4 连可点击行")
	if row.x >= 0:
		for k in 4:
			row_cells.append(Vector2i(row.x + k, row.y))
		for c in row_cells:
			used.append(c) # 行格全部排除，防与单击/塔/英雄格重叠
	var cellA := _find_clickable(view, world, 8, 6, 36, 26, false, used)
	check(cellA.x >= 0, "单击墙格")
	used.append(cellA)
	var cellD := _find_clickable(view, world, 8, 6, 36, 26, false, used)
	check(cellD.x >= 0, "塔格")
	used.append(cellD)
	var cellE := _find_clickable(view, world, 8, 6, 36, 26, false, used)
	check(cellE.x >= 0, "英雄目标格")
	used.append(cellE)
	var ore_cell := _find_ore(view, world)
	check(ore_cell.x >= 0, "可点击矿格")
	var solid_cell := _find_solid_block(view, world)
	check(solid_cell.x >= 0, "可点击实心块格")
	if bad > 0:
		finish("INPUT", 15)
		return

	# ---- 1. 单击放墙 ----
	main.set_mode("wall")
	var sup0: int = world.supply
	await _click(view, cellA)
	var bA = world.building_at(cellA.x, cellA.y)
	check(bA != null and int(bA["kind"]) == Sim.B_WALL, "单击放墙")
	cmp_int(world.supply, sup0 - 10, "放墙扣费 10")
	view.sync(world)
	cmp_int(view.building_nodes.size(), 2, "墙节点出现（核心+墙）")

	# ---- 2. 拖拽放墙线（4 连）----
	main.set_mode("wall")
	var sup1: int = world.supply
	var n0: int = world.buildings.size()
	await _drag(view, row_cells[0], row_cells[3])
	cmp_int(world.buildings.size(), n0 + 4, "拖拽放墙 4 格")
	cmp_int(world.supply, sup1 - 40, "拖拽扣费 40")

	# ---- 3. 挖矿 ----
	main.set_mode("dig")
	var sup2: int = world.supply
	await _click(view, ore_cell)
	cmp_int(world.grid.at(ore_cell.x, ore_cell.y), Grid.OPEN, "矿格变 OPEN")
	cmp_int(world.supply, sup2 + 25, "挖矿 +25")

	# ---- 4. 放塔（施工压扁）----
	main.set_mode("tower")
	var sup3: int = world.supply
	await _click(view, cellD)
	var bD = world.building_at(cellD.x, cellD.y)
	check(bD != null and int(bD["kind"]) == Sim.B_TOWER, "单击放塔")
	if bD == null:
		finish("INPUT", 15)
		return
	cmp_int(world.supply, sup3 - 60, "放塔扣费 60")
	view.sync(world)
	var eD = view.building_nodes.get(int(bD["id"]))
	check(eD != null and absf(float(eD["node"].scale.y) - 0.35) < 0.001, "塔施工压扁 0.35")

	# ---- 5. 拆除（退 50%）----
	main.set_mode("remove")
	var sup4: int = world.supply
	await _click(view, cellA)
	check(world.building_at(cellA.x, cellA.y) == null, "拆除墙")
	cmp_int(world.supply, sup4 + 5, "拆除退款 50%（5）")

	# ---- 6. 英雄移动 + 原地目标被拒 ----
	main.set_mode("hero")
	await _click(view, cellE)
	cmp_int(int(world.hero["tx"]), cellE.x, "英雄目标 x")
	cmp_int(int(world.hero["ty"]), cellE.y, "英雄目标 y")
	var tx_keep: int = int(world.hero["tx"])
	await _click(view, Vector2i(int(world.hero["x"]), int(world.hero["y"])))
	cmp_int(int(world.hero["tx"]), tx_keep, "原地目标被拒")

	# ---- 7. TAB 热层 ----
	check(view.heat_enabled() == false, "初始热层关")
	await _key(KEY_TAB)
	check(view.heat_enabled() == true, "TAB 开热层")
	await _key(KEY_TAB)
	check(view.heat_enabled() == false, "TAB 关热层")

	# ---- 8. SOLID 格放墙被拒（零副作用）----
	main.set_mode("wall")
	var sup5: int = world.supply
	await _click(view, solid_cell)
	cmp_int(world.supply, sup5, "SOLID 格零副作用")
	check(world.building_at(solid_cell.x, solid_cell.y) == null, "SOLID 格无建筑")

	# ---- 9. 暂停中点击被拒 ----
	main.paused = true
	main.set_mode("wall")
	var sup6: int = world.supply
	var cellP := _find_clickable(view, world, 8, 6, 36, 26, false, [])
	await _click(view, cellP)
	cmp_int(world.supply, sup6, "暂停中零副作用")
	main.paused = false

	# ---- 10. 建造预览与模拟守卫一致：英雄脚下不可建 ----
	var hx: int = int(world.hero["x"])
	var hy: int = int(world.hero["y"])
	check(not main.mode_valid("wall", hx, hy), "英雄脚下墙预览为无效")
	check(not main.mode_valid("tower", hx, hy), "英雄脚下塔预览为无效")

	# ---- 11. 屏幕投影一致性（赏金浮字定位口径锁定）----
	for c in [Vector2i(10, 10), Vector2i(24, 24), Vector2i(40, 30)]:
		var w: Vector3 = view.cell_to_world(c.x, c.y)
		var gyw: float = view.ground_y(c.x, c.y)
		var a: Vector2 = view.world_to_screen(w.x, gyw, w.z)
		var b: Vector2 = view.camera.unproject_position(Vector3(w.x, gyw, w.z))
		check(a.x >= 0.0 and a.distance_to(b) < 1.0, "world_to_screen 与引擎投影一致 %s (a=%s b=%s)" % [str(c), str(a), str(b)])

	# ---- 12. 等量反向改高：视图地面随格高更新，不能因高度总和不变漏重建 ----
	var ha0: int = world.grid.get_h(cellA.x, cellA.y)
	var he0: int = world.grid.get_h(cellE.x, cellE.y)
	check(ha0 < Sim.H_MAX and he0 > Sim.H_MIN, "地形双格具备反向改高空间")
	if ha0 < Sim.H_MAX and he0 > Sim.H_MIN:
		view.sync(world) # 先让上一段（拆除）的视觉清理落定，再取基线
		var top_a := _terrain_top(view, cellA)
		var top_e := _terrain_top(view, cellE)
		var units_before: int = view.unit_nodes.size()
		var buildings_before: int = view.building_nodes.size()
		var sum_before := 0
		for h in world.grid.hgt:
			sum_before += int(h)
		world.apply_command({ "kind": "fill", "x": cellA.x, "y": cellA.y })
		world.apply_command({ "kind": "lower", "x": cellE.x, "y": cellE.y })
		var sum_after := 0
		for h in world.grid.hgt:
			sum_after += int(h)
		cmp_int(sum_after, sum_before, "正反改高后高度总和相同")
		view.sync(world)
		check(is_equal_approx(_terrain_top(view, cellA), top_a + view.H_STEP), "填高格柱顶上升")
		check(is_equal_approx(_terrain_top(view, cellE), top_e - view.H_STEP), "挖低格柱顶下降")
		cmp_int(view.unit_nodes.size(), units_before, "改高不清空单位视觉缓存")
		cmp_int(view.building_nodes.size(), buildings_before, "改高不清空建筑视觉缓存")

	# ---- 13. 重开时热层同时清理逻辑、视图和 HUD 按钮 ----
	main.paused = false
	await _key(KEY_TAB)
	check(view.heat_enabled() and main.heat_on, "重开前热层开启")
	main.restart_game()
	check(not view.heat_enabled() and not main.heat_on, "重开后热层关闭")
	var heat_style: StyleBoxFlat = main.hud.heat_btn.get_meta("sb_normal")
	check(heat_style.bg_color == main.hud.DARK["btn"], "重开后 HUD 热层钮熄灭")

	# ---- 14. 相机操控（WASD 平移 / QE 旋转 / 右键拖拽；纯表现层）----
	main.set_process(true) # 相机推进在 _process；本段恢复主循环（允许 tick 推进）
	var cam: Camera3D = view.camera
	await _frames(6)
	var sup_cam: int = world.supply
	var buildings_cam: int = world.buildings.size()

	var p0: Vector3 = cam.global_position
	await _hold_key(KEY_W, 14)
	var p1: Vector3 = cam.global_position
	check(p1.z < p0.z - 0.2, "W 前移（z %.2f→%.2f）" % [p0.z, p1.z])

	await _hold_key(KEY_D, 10)
	var p2: Vector3 = cam.global_position
	check(p2.x > p1.x + 0.15, "D 右移（x %.2f→%.2f）" % [p1.x, p2.x])

	var bz0: float = cam.global_transform.basis.z.x
	await _hold_key(KEY_Q, 10)
	var bz1: float = cam.global_transform.basis.z.x
	check(bz1 > bz0 + 0.02, "Q 左旋（bz.x %.3f→%.3f）" % [bz0, bz1])

	await _hold_key(KEY_E, 10)
	var bz2: float = cam.global_transform.basis.z.x
	check(bz2 < bz1 - 0.02, "E 右旋（bz.x %.3f→%.3f）" % [bz1, bz2])

	# 投影一致性：屏内格动态选取（W 平移量随真实帧时长漂移，固定格可能出屏——
	# 出屏换格不判失败；判据本体 = 闭式解与引擎 unproject 逐位一致，机器速度无关）
	var proj_ok := false
	for c2 in [Vector2i(24, 24), Vector2i(30, 20), Vector2i(20, 30), Vector2i(28, 28)]:
		var w2: Vector3 = view.cell_to_world(c2.x, c2.y)
		var gy2: float = view.ground_y(c2.x, c2.y)
		var a2: Vector2 = view.world_to_screen(w2.x, gy2, w2.z)
		if a2.x < 0.0 or a2.x >= vp_size.x or a2.y < 0.0 or a2.y >= vp_size.y:
			continue # 视口外（W 平移量随机器帧速漂移）：换格
		var b2: Vector2 = cam.unproject_position(Vector3(w2.x, gy2, w2.z))
		check(a2.distance_to(b2) < 1.0, "旋转后 world_to_screen 一致 %s (a=%s b=%s)" % [str(c2), str(a2), str(b2)])
		proj_ok = true
		break
	check(proj_ok, "旋转后至少一格屏内可做投影对照")

	# 右键拖拽跟手：拖拽是纯几何事件（无 dt 参与），1:1 只在焦平面精确成立——
	# 故改测焦点平面点（透视放大率恒 =1；旧口径测固定格 (24,24)，其视轴深度
	# 随 W 平移漂移 → 透视放大 1.43×，帧速慢即假失败）。附带焦点几何直检：
	# 焦点位移必须逐位等于 80×upp（pan_pixels 的定义式）。
	var f0: Vector3 = view.core.focus
	var wcp: Vector3 = Vector3(f0.x, 0.0, f0.z)
	var s0: Vector2 = view.world_to_screen(wcp.x, 0.0, wcp.z)
	await _rmb_drag(vp_size * 0.5, Vector2(80.0, 0.0))
	var f1: Vector3 = view.core.focus
	var upp: float = 2.0 * (view.core._dist * view.core._zoom) * float(view.core._fit["t45"]) / vp_size.y
	check(absf((f0.x - f1.x) - 80.0 * upp) < 0.01, "拖拽焦点位移 = 80×upp（得 %.4f/%.4f）" % [f0.x - f1.x, 80.0 * upp])
	var s1: Vector2 = view.world_to_screen(wcp.x, 0.0, wcp.z)
	check(absf((s1.x - s0.x) - 80.0) < 25.0, "右键拖拽内容跟手·焦平面（Δx=%.1f）" % (s1.x - s0.x))

	cmp_int(world.supply, sup_cam, "相机操控不影响供给")
	cmp_int(world.buildings.size(), buildings_cam, "相机操控不影响建筑数")

	var sp24 := _sp_of(view, Vector2i(24, 24))
	if sp24.x >= 0.0 and sp24.x < vp_size.x and sp24.y >= 0.0 and sp24.y < vp_size.y:
		var back24: Vector2i = view.pick_cell(sp24.x, sp24.y)
		check(back24 == Vector2i(24, 24), "新视角下拾取回环 %s" % str(back24))

	# ---- 15. 滚轮缩放（拉近/还原/限位 0.6–1.8；暂停与 HUD 区冻结）----
	var yz0: float = cam.global_position.y
	await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	var yz1: float = cam.global_position.y
	check(yz1 < yz0 - 1.0, "滚轮拉近（y %.1f→%.1f）" % [yz0, yz1])
	await _wheel_at(vp_size * Vector2(0.5, 0.5), false)
	var yz2: float = cam.global_position.y
	check(absf(yz2 - yz0) < 1.0, "滚轮拉远还原（y %.1f，基准 %.1f）" % [yz2, yz0])
	for _i in 14:
		await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	var yz3: float = cam.global_position.y
	await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	var yz4: float = cam.global_position.y
	check(absf(yz4 - yz3) < 0.3 and yz3 < yz0 * 0.75, "拉近限位 0.6（y %.1f→%.1f）" % [yz3, yz4])
	for _i in 24:
		await _wheel_at(vp_size * Vector2(0.5, 0.5), false)
	var yz5: float = cam.global_position.y
	await _wheel_at(vp_size * Vector2(0.5, 0.5), false)
	var yz6: float = cam.global_position.y
	check(absf(yz6 - yz5) < 0.5 and yz5 > yz0 * 1.5, "拉远限位 1.8（y %.1f→%.1f）" % [yz5, yz6])
	main.paused = true
	await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	check(absf(cam.global_position.y - yz6) < 0.2, "暂停中滚轮冻结")
	main.paused = false
	await _wheel_at(Vector2(vp_size.x - 30.0, 400.0), false)
	check(absf(cam.global_position.y - yz6) < 0.2, "HUD 区滚轮冻结")
	finish("INPUT", 21)


## 读取特定战场格中心处的六棱板顶面顶点高度（独立于 ground_y，防止自我对拍）。
## 2026-10-17 六边化：场内高度由 "HexField" 六棱板网格承担（中心为顶面扇形顶点）。
func _terrain_top(view, cell: Vector2i) -> float:
	var pos: Vector3 = view.cell_to_world(cell.x, cell.y)
	for node in view.field_root.get_children():
		if not (node is MeshInstance3D) or node.name != "HexField":
			continue
		var mesh: Mesh = node.mesh
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				if absf(v.x - pos.x) < 0.01 and absf(v.z - pos.z) < 0.01:
					return v.y
	fail("地面网格缺格中心顶点：" + str(cell))
	return NAN


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


## 滚轮注入：pos 处一次上滚（拉近）/ 下滚（拉远）。
func _wheel_at(pos: Vector2, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = pos
	get_root().push_input(ev)
	await process_frame


## 等 n 帧（相机推进在 _process 里，需要真实帧时间累积）。
func _frames(n: int) -> void:
	for _i in n:
		await process_frame


## 按住某键 n 帧再松开（相机 WASD/QE 为「按住持续」语义）。
func _hold_key(code: Key, frames: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	get_root().push_input(down)
	await _frames(frames)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	get_root().push_input(up)
	await process_frame


## 右键拖拽：按下 → 移动 delta → 松开（与真实鼠标路径一致）。
func _rmb_drag(from: Vector2, delta: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	down.position = from
	get_root().push_input(down)
	await process_frame
	var mv := InputEventMouseMotion.new()
	mv.position = from + delta
	mv.relative = delta
	get_root().push_input(mv)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	up.position = from + delta
	get_root().push_input(up)
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
			var row_ok := true
			for k in n:
				if exclude.has(Vector2i(x + k, y)) or not _clickable(view, world, x + k, y):
					row_ok = false
					break
			if row_ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_ore(view, world) -> Vector2i:
	for y in 64:
		for x in 64:
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
## 64² 场景里成片实心在岩脊 y40..42（含 4 邻的中心行 = y41），扫描窗须覆盖。
func _find_solid_block(view, world) -> Vector2i:
	for y in range(8, 45):
		for x in range(8, 45):
			if world.grid.at(x, y) != Grid.SOLID:
				continue
			if world.grid.at(x, y + 1) != Grid.SOLID or world.grid.at(x, y - 1) != Grid.SOLID or world.grid.at(x + 1, y) != Grid.SOLID or world.grid.at(x - 1, y) != Grid.SOLID:
				continue
			if _clickable_cover(view, world, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)
