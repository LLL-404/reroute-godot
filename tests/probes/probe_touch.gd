extends ProbeKit

# 触屏可点 + 触屏拖线闸（窗口模式运行）：合成 InputEventScreenTouch/ScreenDrag 驱动
# 关键按钮与「按下→拖动→抬起」放墙线（依赖桌面默认的 emulate_mouse_from_touch 换算——
# 这条换算即是 D1-2 的复用路径，不加手写分支避免与模拟鼠标双击发），并静态扫描各页面
# 按钮的 custom_minimum_size 触达下限（高 ≥36px/宽 ≥58px @S=1，手指可点）。
# 链路：标题触屏开始 → HUD 暂停钮 → 触屏继续 → 再暂停 → 触屏重开 → 全页按钮尺寸矩阵
#      → 新建同局两实例：触屏拖线（含偏线绕行）与鼠标拖线对拍世界状态逐字节一致。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_touch.gd
# 判定：exit 0 + stdout 含 `[TOUCH] PASS`。

var _S := 1.0
var vp_size := Vector2(1280.0, 720.0)


func _initialize() -> void:
	print("[TOUCH] begin")
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.set_process(false)
	var shell = main.shell
	var hud = main.hud
	_S = shell.S
	vp_size = get_root().get_visible_rect().size
	var page_title: Control = shell.pages["title"]
	var page_pause: Control = null # 暂停页惰建：首次进暂停后才可取

	check(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)), "触屏→鼠标换算开启")
	check(shell.current_page() == "title", "启动即标题")

	# ---- 1. 触屏开战 ----
	await _tap_btn(page_title, "btn_start")
	check(shell.current_page() == "" and main.paused == false, "触屏点「开始对局」→ 对局")

	# ---- 2. 触屏 HUD 暂停 ----
	await _tap_ctl(hud.pause_btn)
	check(shell.current_page() == "pause" and main.paused == true, "触屏点 HUD 暂停钮 → 暂停")
	page_pause = shell.pages["pause"]

	# ---- 3. 触屏「继续」 ----
	await _tap_btn(page_pause, "btn_resume")
	check(shell.current_page() == "" and main.paused == false, "触屏点「继续」→ 对局")

	# ---- 4. 触屏「重开本局」 ----
	await _tap_ctl(hud.pause_btn)
	var run0: int = main.run_index
	await _tap_btn(page_pause, "btn_restart")
	check(shell.current_page() == "" and main.run_index == run0 + 1, "触屏点「重开本局」→ 新局")

	# ---- 5. 全页按钮尺寸矩阵（触达下限，S 随视口） ----
	shell._ensure("gameover") # 惰建缺页，保证矩阵齐
	var min_h := 36.0 * _S - 0.5
	var min_w := 58.0 * _S - 0.5
	var total := 0
	for key in ["title", "pause", "gameover", "slots", "settings"]:
		var page: Control = shell._ensure(key)
		for b in page.find_children("", "Button", true, false):
			if b is CheckButton:
				continue # 行内小开关（若有）不参与按钮矩阵
			total += 1
			var btn: Button = b
			check(btn.custom_minimum_size.y >= min_h and btn.custom_minimum_size.x >= min_w,
				"按钮 %s/%s 触达尺寸 %.0fx%.0f" % [key, btn.name, btn.custom_minimum_size.x, btn.custom_minimum_size.y])
	for b in shell.confirm_layer.find_children("", "Button", true, false):
		total += 1
		var btn2: Button = b
		check(btn2.custom_minimum_size.y >= min_h and btn2.custom_minimum_size.x >= min_w,
			"按钮 confirm/%s 触达尺寸 %.0fx%.0f" % [btn2.name, btn2.custom_minimum_size.x, btn2.custom_minimum_size.y])
	cmp_int(total, 56, "按钮矩阵总数（6+5+2+7+34+2；34 含 §11.34 隐私说明钮，title +1 = §11.35 期他会话新增肉鸽入口 btn_rogue）")

	# ---- 6. 触屏拖线（D1-4/6）：按下→拖动（含偏线绕行）→抬起；与鼠标路径世界状态逐字节一致 ----
	main.view.stop_all_audio()
	root.remove_child(main)
	main.queue_free()
	await process_frame
	var main_a = await _fresh_main()
	main_a.set_process(false) # 无 tick 干扰：同 run 两实例可比 canonical
	main_a.start_match()
	var supp_a: int = main_a.world.supply
	var row := _find_row(main_a.view, main_a.world, 8, 6, 36, 26, 4, [])
	check(row.x >= 0, "触屏拖线用 4 连可点行")
	if row.x < 0:
		finish("TOUCH", 67)
		return
	var pa := Vector2i(row.x, row.y)
	var pb := Vector2i(row.x + 3, row.y)
	var detour := Vector2i(row.x + 1, row.y + 3) # 偏线中途点：只应影响位移，不应影响落线
	var line: Array = main_a.line_cells(pa, pb)
	await _drag_touch(main_a.view, pa, detour, pb)
	cmp_int(_count_walls(main_a.world), 4, "触屏拖线建 4 格墙")
	var all_on_line := true
	for c: Vector2i in line:
		var bb = main_a.world.building_at(c.x, c.y)
		if bb == null or int(bb["kind"]) != Sim.B_WALL:
			all_on_line = false
	check(all_on_line, "触屏拖线逐格落在 Bresenham 线上")
	cmp_int(main_a.world.supply, supp_a - 40, "触屏拖线扣费 40")
	check(main_a.drag_start == Vector2i(-1, -1), "触屏拖线后起点已清")
	var canon_a: PackedByteArray = main_a.world.canonical_bytes().data
	var run_a: int = main_a.run_index
	main_a.view.stop_all_audio()
	root.remove_child(main_a)
	main_a.queue_free()
	await process_frame

	var main_b = await _fresh_main()
	main_b.set_process(false)
	main_b.start_match()
	var supp_b: int = main_b.world.supply
	cmp_int(main_b.run_index, run_a, "对照两局同 run（同蓝图/种子）")
	var row_b := _find_row(main_b.view, main_b.world, 8, 6, 36, 26, 4, [])
	check(row_b == row, "对照局扫描出同一行")
	await _drag_mouse(main_b.view, Vector2i(row_b.x, row_b.y), Vector2i(row_b.x + 1, row_b.y + 3), Vector2i(row_b.x + 3, row_b.y))
	cmp_int(_count_walls(main_b.world), 4, "鼠标拖线建 4 格墙（对照腿）")
	cmp_int(main_b.world.supply, supp_b - 40, "鼠标拖线扣费 40（对照腿）")
	var canon_b: PackedByteArray = main_b.world.canonical_bytes().data
	check(canon_a == canon_b, "触屏与鼠标路径世界状态逐字节一致")
	main_b.view.stop_all_audio()
	root.remove_child(main_b)
	main_b.queue_free()
	await process_frame

	finish("TOUCH", 67)


# ---------------- 实例辅助 ----------------

func _fresh_main():
	var packed: PackedScene = load("res://game/main.tscn")
	var m = packed.instantiate()
	root.add_child(m)
	for _i in 3:
		await process_frame
	return m


func _count_walls(world) -> int:
	var n := 0
	for b in world.buildings:
		if int(b["kind"]) == Sim.B_WALL:
			n += 1
	return n


# ---------------- 注入辅助 ----------------

func _tap_ctl(ctl: Control) -> void:
	var center: Vector2 = ctl.global_position + ctl.size * 0.5
	var td := InputEventScreenTouch.new()
	td.index = 0
	td.pressed = true
	td.position = center
	get_root().push_input(td)
	await process_frame
	var tu := InputEventScreenTouch.new()
	tu.index = 0
	tu.pressed = false
	tu.position = center
	get_root().push_input(tu)
	await process_frame
	await process_frame # 让页面切换/布局稳定


func _tap_btn(page: Control, btn_name: String) -> void:
	var b := page.find_child(btn_name, true, false)
	if b == null:
		check(false, "按钮缺失：" + btn_name)
		return
	await _tap_ctl(b)


## 触屏拖线：按下 → 途经 (偏线中途点, 线路 1/3 点, 终点) 拖动 → 抬起（口径同真实手势）。
## 走 Input.parse_input_event（真实设备链路：Input 单例做触摸→鼠标换算；
## get_root().push_input 会旁路换算，世界区拖拽到不了 main._unhandled_input）。
func _drag_touch(view, from_cell: Vector2i, mid_cell: Vector2i, to_cell: Vector2i) -> void:
	var sp0 := _sp_of(view, from_cell)
	var spm := _sp_of(view, mid_cell)
	var sp1 := _sp_of(view, to_cell)
	var td := InputEventScreenTouch.new()
	td.index = 0
	td.pressed = true
	td.position = sp0
	Input.parse_input_event(td)
	await process_frame
	var prev := sp0
	for sp in [spm, sp0.lerp(sp1, 1.0 / 3.0), sp1]:
		var dr := InputEventScreenDrag.new()
		dr.index = 0
		dr.position = sp
		dr.relative = sp - prev
		prev = sp
		Input.parse_input_event(dr)
		await process_frame
	var tu := InputEventScreenTouch.new()
	tu.index = 0
	tu.pressed = false
	tu.position = sp1
	Input.parse_input_event(tu)
	await process_frame


## 鼠标拖线对照腿：与 _drag_touch 同走位、同落点（事件形态不同，处理器同一）。
func _drag_mouse(view, from_cell: Vector2i, mid_cell: Vector2i, to_cell: Vector2i) -> void:
	var sp0 := _sp_of(view, from_cell)
	var spm := _sp_of(view, mid_cell)
	var sp1 := _sp_of(view, to_cell)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = sp0
	get_root().push_input(down)
	await process_frame
	for sp in [spm, sp0.lerp(sp1, 1.0 / 3.0), sp1]:
		var mv := InputEventMouseMotion.new()
		mv.position = sp
		mv.relative = sp - sp0
		get_root().push_input(mv)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = sp1
	get_root().push_input(up)
	await process_frame


# ---------------- 扫描辅助（口径同 probe_input） ----------------

## 格中心屏幕坐标：unproject 到地面 +0.1m（保证远离 z-fighting 平面）。
func _sp_of(view, cell: Vector2i) -> Vector2:
	var w: Vector3 = view.cell_to_world(cell.x, cell.y)
	var gy: float = view.ground_y(cell.x, cell.y)
	return view.camera.unproject_position(Vector3(w.x, gy + 0.1, w.z))


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
