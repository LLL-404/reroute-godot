extends ProbeKit

# 触屏视角闸（窗口模式）：验证 Android 手势映射，且手势绝不误触建造。
#   单指点按（墙模式）→ 落 1 格墙、扣 10；点按在岩石/建筑上 → 零副作用
#   单指拖动（非墙模式）→ 相机平移，世界零变化
#   单指拖动（墙模式）→ 拖线建墙（旧有玩法不回归）
#   双指平移 / 捏合 / 拧 → 相机 focus/zoon/yaw 变化，世界零变化
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_gesture.gd
# 判定：exit 0 + stdout 含 `[GESTURE] PASS`。
var vp_size := Vector2(1280.0, 720.0)


func _initialize() -> void:
	print("[GESTURE] begin")
	var packed: PackedScene = load("res://game/app/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame
	main.set_process(false)
	main.start_match()
	var view = main.view
	var world = main.world
	var core = view.core
	vp_size = get_root().get_visible_rect().size
	print("[GESTURE] viewport=", vp_size, " mode=", main.mode)

	# ---- 1. 单指点按（墙）→ 落 1 格 ----
	var cell := _find_clickable(view, world, 8, 6, 36, 26, [])
	check(cell.x >= 0, "扫描到可点建墙格")
	if cell.x < 0:
		finish("GESTURE", 20)
		return
	var sp := _sp_of(view, cell)
	var n0: int = world.buildings.size()
	var s0: int = world.supply
	await _tap(sp)
	cmp_int(world.buildings.size(), n0 + 1, "单指点按落 1 格建筑")
	cmp_int(world.supply, s0 - 10, "单指点按扣费 10")
	check(main.drag_start == Vector2i(-1, -1), "点按后拖拽起点已清")
	check(main.touch_mode == "", "点按后手势状态归零")

	# ---- 2. 单指拖动（非墙模式）= 平移，世界零变化 ----
	main.mode = "dig"
	var f0: Vector3 = core.focus
	var n1: int = world.buildings.size()
	var s1: int = world.supply
	await _swipe(Vector2(vp_size.x * 0.5, vp_size.y * 0.55), Vector2(120.0, 70.0), 6)
	check(core.focus != f0, "单指拖动平移了相机")
	check(core.focus.x < f0.x - 0.2, "右拖 → 焦点左移（内容跟手）")
	check(core.focus.z < f0.z - 0.1, "下拖 → 焦点后移（内容跟手）")
	cmp_int(world.buildings.size(), n1, "平移不产生建筑")
	cmp_int(world.supply, s1, "平移不扣费")
	check(absf(core._zoom - 1.0) < 0.001, "平移不改缩放")
	check(main.touch_mode == "", "拖动结束后手势状态归零")

	# ---- 3. 单指拖动（墙模式）= 拖线建墙（旧玩法不回归）----
	main.mode = "wall"
	var row := _find_row(view, world, 8, 6, 36, 26, 3, [cell])
	check(row.x >= 0, "扫描到 3 连可拖行")
	if row.x >= 0:
		var n2: int = world.buildings.size()
		var s2: int = world.supply
		await _drag_cells(view, Vector2i(row.x, row.y), Vector2i(row.x + 2, row.y))
		cmp_int(world.buildings.size(), n2 + 3, "墙模式单指拖动建 3 格墙")
		cmp_int(world.supply, s2 - 30, "墙模式拖线扣费 30")

	# ---- 4. 双指平移 = 视角平移，零建造 ----
	main.mode = "wall" # 故意留在墙模式：双指手势必须压过建造
	var n3: int = world.buildings.size()
	var s3: int = world.supply
	var f1: Vector3 = core.focus
	await _two_finger(Vector2(vp_size.x * 0.5, vp_size.y * 0.5), Vector2(80.0, 40.0), 1.0, 0.0, 6, Vector2(-90.0, 0.0))
	check(core.focus != f1, "双指平移移动了相机")
	check(core.focus.x > f1.x + 0.2, "双指右移 → 焦点右移（内容跟手）")
	cmp_int(world.buildings.size(), n3, "双指平移不产生建筑")
	cmp_int(world.supply, s3, "双指平移不扣费")
	check(main.drag_start == Vector2i(-1, -1), "双指手势已撤销单指起线")

	# ---- 5. 双指捏合（拉开）= 拉近（_zoom 变小），零建造 ----
	var z0: float = core._zoom
	var n4: int = world.buildings.size()
	await _two_finger(Vector2(vp_size.x * 0.5, vp_size.y * 0.5), Vector2(60.0, 0.0), 1.75, 0.0, 8, Vector2.ZERO)
	check(core._zoom < z0 - 0.05, "双指拉开 → 拉近（zoom %.3f → %.3f）" % [z0, core._zoom])
	cmp_int(world.buildings.size(), n4, "捏合不产生建筑")

	# ---- 6. 双指拧（顺时针）= yaw 正向变化，零建造 ----
	var y0: float = core.yaw
	var n5: int = world.buildings.size()
	await _two_finger(Vector2(vp_size.x * 0.5, vp_size.y * 0.5), Vector2(120.0, 0.0), 1.0, 0.75, 8, Vector2.ZERO)
	check(core.yaw > y0 + 0.3, "顺时针拧 → yaw 增大（%.3f → %.3f）" % [y0, core.yaw])
	cmp_int(world.buildings.size(), n5, "旋转不产生建筑")
	check(main.touch_mode == "" and main.touch_pts.is_empty(), "全部抬指后手势状态清空")

	# ---- 7. 极限平移：焦点被回拉到地图邻域，但绝不被夹死 ----
	# 先回到标准取景，保证下限走 MAP_MIN_VISIBLE 分支（而非「居中占比的 90%」退化分支）。
	core.fit_camera()
	var f_init: Vector3 = core.focus
	var pans: Array = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]
	for k in pans.size():
		var dir: Vector2 = pans[k]
		core.pan_world(dir.x, dir.y, 40.0) # 单次跨过地图半宽
		var ratio: float = core._map_visible_ratio()
		check(ratio >= 0.749, "第 %d 次长距平移后地图可见占比 %.3f ≥ 0.749" % [k + 1, ratio])
		if k == 0:
			check(core.focus != f_init, "长距平移后焦点未被夹死（%s → %s）" % [str(f_init), str(core.focus)])

	main.view.stop_all_audio()
	finish("GESTURE", 20)


# ---------------- 注入辅助（走 Input 单例 = 真实设备链路，含触摸→鼠标模拟） ----------------

func _tap(p: Vector2) -> void:
	_touch(0, p, true)
	await process_frame
	_touch(0, p, false)
	await process_frame


## 单指拖动：按下 → 分 steps 步走 total → 抬起。
func _swipe(p: Vector2, total: Vector2, steps: int) -> void:
	_touch(0, p, true)
	await process_frame
	var prev := p
	for k in steps:
		var q := p + total * float(k + 1) / float(steps)
		_drag(0, q, q - prev)
		prev = q
		await process_frame
	_touch(0, prev, false)
	await process_frame


## 单指沿格子拖线（墙模式用）。
func _drag_cells(view, a: Vector2i, b: Vector2i) -> void:
	var pa := _sp_of(view, a)
	var pb := _sp_of(view, b)
	await _swipe(pa, pb - pa, 5)


## 双指手势：中点以 center 起、平移 by（分 steps）、间距乘 spread、连线转 rot（rad）。
func _two_finger(center: Vector2, half: Vector2, spread: float, rot: float, steps: int, by: Vector2) -> void:
	var a0 := center - half
	var b0 := center + half
	_touch(0, a0, true)
	await process_frame
	_touch(1, b0, true)
	await process_frame
	for k in steps:
		var t := float(k + 1) / float(steps)
		var off := by * t
		var ang := PI * 0.5 + rot * t
		var d := half.length() * lerpf(1.0, spread, t)
		var a := center + off + Vector2(cos(ang), sin(ang)) * d
		var b := center + off - Vector2(cos(ang), sin(ang)) * d
		_drag(0, a, a - a0)
		_drag(1, b, b - b0)
		a0 = a
		b0 = b
		await process_frame
	_touch(0, a0, false)
	await process_frame
	_touch(1, b0, false)
	await process_frame


func _touch(idx: int, p: Vector2, pressed: bool) -> void:
	var st := InputEventScreenTouch.new()
	st.index = idx
	st.position = p
	st.pressed = pressed
	Input.parse_input_event(st)


func _drag(idx: int, p: Vector2, rel: Vector2) -> void:
	var sd := InputEventScreenDrag.new()
	sd.index = idx
	sd.position = p
	sd.relative = rel
	Input.parse_input_event(sd)


# ---------------- 扫描辅助（口径同 probe_touch / probe_input） ----------------

func _sp_of(view, cell: Vector2i) -> Vector2:
	var w: Vector3 = view.cell_to_world(cell.x, cell.y)
	var gy: float = view.ground_y(cell.x, cell.y)
	return view.camera.unproject_position(Vector3(w.x, gy + 0.1, w.z))


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
	# 取景拉近后地图边缘会压到 HUD 下：被 HUD 覆盖的格真实输入会被 main.in_hud_region 排除，不算可点击
	var mn = view.get_parent()
	if mn != null and mn.has_method("in_hud_region") and mn.in_hud_region(sp.x, sp.y):
		return false
	var back: Vector2i = view.pick_cell(sp.x, sp.y)
	return back.x == x and back.y == y


func _find_clickable(view, world, x0: int, y0: int, x1: int, y1: int, exclude: Array) -> Vector2i:
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
