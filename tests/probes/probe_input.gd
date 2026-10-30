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
	var packed: PackedScene = load("res://game/app/main.tscn")
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
	var cellD2 := _find_clickable(view, world, 8, 6, 36, 26, false, used)
	check(cellD2.x >= 0, "塔拖拽终点格（应被单点语义忽略）")
	used.append(cellD2)
	var cancelA := _find_clickable_h(view, world, 8, 30, 36, 44, used) # 取消测试：可点击即可
	if cancelA.x < 0:
		cancelA = _find_clickable(view, world, 8, 30, 36, 44, false, used)
	check(cancelA.x >= 0, "取消测试起步格")
	used.append(cancelA)
	var cancelB := _find_clickable(view, world, 8, 30, 36, 44, false, used)
	check(cancelB.x >= 0, "取消测试拖拽终点格")
	used.append(cancelB)
	var cellE := _find_clickable_h(view, world, 8, 6, 36, 26, used) # 第 12 段反向改高对需要「可挖低端」h > H_MIN
	if cellE.x < 0:
		cellE = _find_clickable(view, world, 8, 6, 36, 26, false, used) # 退路：该段自会判失败
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
	cmp_int(world.supply, sup0 - 5, "放墙扣费 5（阶梯价首面）")
	view.sync(world)
	cmp_int(view.building_nodes.size(), 2, "墙节点出现（核心+墙）")

	# ---- 1.5 悬停焦点环 + 建造中途取消（Esc / 右键都不落子）----
	main.mouse_pos = _sp_of(view, cellA)
	main.set_mode("remove")
	main.update_ghost()
	check(view.focus_ring.visible and view.focus_ring.material_override == view.mats["ring_hot"], "拆除悬停红焦点环")
	main.set_mode("wall")
	main.update_ghost()
	check(view.focus_ring.visible and view.focus_ring.material_override == view.mats["ring_wall"], "建造悬停金焦点环")
	main.mouse_pos = _sp_of(view, cancelA)
	main.update_ghost()
	check(not view.focus_ring.visible, "空悬停隐藏焦点环")
	var n_c: int = world.buildings.size()
	var s_c: int = world.supply
	await _drag_cancel(view, cancelA, cancelB, true)
	cmp_int(world.buildings.size(), n_c, "Esc 取消拖拽零建造")
	cmp_int(world.supply, s_c, "Esc 取消零扣费")
	check(not main.paused, "Esc 取消不误触暂停")
	await _drag_cancel(view, cancelA, cancelB, false)
	cmp_int(world.buildings.size(), n_c, "右键取消拖拽零建造")
	cmp_int(world.supply, s_c, "右键取消零扣费")

	# ---- 2. 拖拽放墙线（4 连）→ Ctrl+Z 整条撤销 → 重放 ----
	main.set_mode("wall")
	var sup1: int = world.supply
	var n0: int = _alive_count(world)
	await _drag(view, row_cells[0], row_cells[3])
	cmp_int(_alive_count(world), n0 + 4, "拖拽放墙 4 格")
	cmp_int(world.supply, sup1 - 20, "拖拽扣费 20（4 面 × 阶梯 5）")
	check(main.hud.undo_panel.visible, "建造后撤销提示出现")
	await _key_mod(KEY_Z, true)
	cmp_int(_alive_count(world), n0, "Ctrl+Z 撤销整条墙线")
	cmp_int(world.supply, sup1, "撤销墙线全额退款 20")
	check(not main.hud.undo_panel.visible, "撤销后提示消失")
	await _drag(view, row_cells[0], row_cells[3])
	cmp_int(_alive_count(world), n0 + 4, "重放墙线 4 格")
	cmp_int(world.supply, sup1 - 20, "重放扣费 20")

	# ---- 3. 挖矿（M2-a：矿格隔空点挖被拒，改为派英雄去邻格；开挖闭环见 probe_dig_intent）----
	main.set_mode("dig")
	var sup2: int = world.supply
	await _click(view, ore_cell)
	cmp_int(world.grid.at(ore_cell.x, ore_cell.y), Grid.COVER, "矿格隔空点挖被拒（仍 COVER）")
	cmp_int(world.supply, sup2, "隔空点挖零扣费")
	check(not main._ore_intent.is_empty(), "已记录矿格意图")
	var stand: Vector2i = main._ore_intent.get("stand", Vector2i(-1, -1))
	check(stand.x >= 0 and Grid.hex_dist(stand.x, stand.y, ore_cell.x, ore_cell.y) == 1, "站位为矿格六邻")
	cmp_int(int(world.hero["tx"]), stand.x, "英雄已收到前往命令 x")
	cmp_int(int(world.hero["ty"]), stand.y, "英雄已收到前往命令 y")

	# ---- 4. 放塔（单点语义：拖拽也只落起点一格；施工进度 0.12 起步）----
	# 探针沙盒白盒补供给：本闸测输入闭环不测经济，塔段断言全为相对差值。
	# 2026-10-28 新经济开局 60，前面墙 5+墙线 20 已花 25（剩 35 < 塔 60 被拒）；
	# 旧口径 300 供给时代无此问题。补到 300。
	world.supply = 300
	main.set_mode("tower")
	var sup3: int = world.supply
	var n_before_t: int = world.buildings.size()
	main.mouse_pos = _sp_of(view, cellD)
	main.update_ghost()
	cmp_int(view.preview_root.get_child_count(), 1, "塔预览模型")
	cmp_int(view.range_root.get_child_count(), 2, "塔射程预览")
	await _drag(view, cellD, cellD2)
	var bD = world.building_at(cellD.x, cellD.y)
	check(bD != null and int(bD["kind"]) == Sim.B_TOWER, "拖拽放塔（单点）")
	check(world.building_at(cellD2.x, cellD2.y) == null, "塔拖拽不沿线铺塔")
	cmp_int(world.buildings.size(), n_before_t + 1, "塔拖拽只落 1 格")
	if bD == null:
		finish("INPUT", 15)
		return
	cmp_int(world.supply, sup3 - 60, "放塔扣费 60")
	view.sync(world)
	var eD = view.building_nodes.get(int(bD["id"]))
	check(eD != null and absf(float(eD["node"].scale.y) - 0.12) < 0.02, "塔施工起步 0.12")
	check(eD != null and eD.get("fx") != null and eD["fx"].visible, "塔施工脚手架可见")
	# Ctrl+Z：单塔全额撤销
	var sup_t: int = world.supply
	await _key_mod(KEY_Z, true)
	check(world.building_at(cellD.x, cellD.y) == null, "Ctrl+Z 撤销塔")
	cmp_int(world.supply, sup_t + 60, "撤销塔全额退款 60")

	# ---- 5. 拆除（退 50%）----
	main.set_mode("remove")
	var sup4: int = world.supply
	await _click(view, cellA)
	check(world.building_at(cellA.x, cellA.y) == null, "拆除墙")
	cmp_int(world.supply, sup4 + 2, "拆除退款 50%（实付 5 退 2）")

	# ---- 6. 英雄移动 + 原地目标被拒 ----
	main.set_mode("hero")
	await _click(view, cellE)
	cmp_int(int(world.hero["tx"]), cellE.x, "英雄目标 x")
	cmp_int(int(world.hero["ty"]), cellE.y, "英雄目标 y")
	# 白盒逐 tick 把英雄真实走到 cellE 再测原地拒收。原因有二（均 128 图实测）：
	# ① 本探针自始 set_process(false)（无 tick 干扰），英雄不会自行走位；
	# ② 128 图英雄出生格紧贴核心北侧（seed 20261004：(41,73) vs core (41,75)），
	#    默认南向取景下出生格基点被核心台地遮挡、拾取回邻格（pick(41,73)→(42,74)），
	#    「点自身格」会点成邻格而假红。cellE 在可点击盒内，走到后拾取精确。
	var hx0: int = int(world.hero["x"])
	var hy0: int = int(world.hero["y"])
	var walks := 0
	while walks < 4000 and not (int(world.hero["x"]) == cellE.x and int(world.hero["y"]) == cellE.y):
		world.tick()
		view.sync(world)
		walks += 1
	var tx_keep: int = int(world.hero["tx"])
	await _click(view, Vector2i(int(world.hero["x"]), int(world.hero["y"])))
	cmp_int(int(world.hero["tx"]), tx_keep, "原地目标被拒")
	# 走回原位还原现场：§12 会对 cellE 挖低，英雄压格会被零副作用卫兵拒绝而假红
	world.apply_command({ "kind": "hero", "x": hx0, "y": hy0 })
	var walks_back := 0
	while walks_back < 4000 and not (int(world.hero["x"]) == hx0 and int(world.hero["y"]) == hy0):
		world.tick()
		view.sync(world)
		walks_back += 1

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
		# 2026-10-21 并台口径：填/挖格退出并台（回到 field_h 基准），视觉顶会有 ≤ 半档(PLATE_STEP)
		# 的基准漂移，断言按「升高量 ≈ H_STEP，容差半档」而非精确相等。
		check(absf((_terrain_top(view, cellA) - top_a) - view.H_STEP) <= 0.31, "填高格柱顶上升")
		check(absf((top_e - _terrain_top(view, cellE)) - view.H_STEP) <= 0.31, "挖低格柱顶下降")
		cmp_int(view.unit_nodes.size(), units_before, "改高不清空单位视觉缓存")
		cmp_int(view.building_nodes.size(), buildings_before, "改高不清空建筑视觉缓存")

	# ---- 13. 重开时热层同时清理逻辑、视图和 HUD 按钮 ----
	main.paused = false
	await _key(KEY_TAB)
	check(view.heat_enabled() and main.heat_on, "重开前热层开启")
	main.restart_game()
	check(not view.heat_enabled() and not main.heat_on, "重开后热层关闭")
	var heat_style: StyleBoxFlat = main.hud.heat_btn.get_theme_stylebox("normal") # v2.3 effective
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

	# 旋转按 dt 累积（CAM_ROT_SPEED=1.5rad/s）：帧计时在 2000+fps 机器上 10 帧只走数毫秒，
	# 断言必须按墙钟按住（400ms ≈ 0.6rad，对阈值 0.02 有约 20 倍余量）。
	var bz0: float = cam.global_transform.basis.z.x
	await _hold_key_ms(KEY_Q, 400)
	var bz1: float = cam.global_transform.basis.z.x
	check(bz1 > bz0 + 0.02, "Q 左旋（bz.x %.3f→%.3f）" % [bz0, bz1])

	await _hold_key_ms(KEY_E, 400)
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

	# ---- 14.5 拾取回环（钉扎位姿 + 平坦格；2026-10-20 重标定）----
	# 旧口径「任意位姿下 (24,24) 回拾」不稳：W 按帧/QE 按墙钟/拖拽按像素 → 位姿随帧率漂移；
	# 且 2 迭代拾取在相邻格高差大时合法收敛到邻格（实测 (24,24) 顶高 1.34、回拾 (23,23)）。
	# 新口径：钉扎 focus=格心、yaw=0、zoom=1；扫「自身与 6 邻高度差 ≤0.10」的平坦格
	# （= 2 迭代算法精确收敛域，全图 199/199 实测）；取 6 个不同行格做点击回环。
	# 同时冻结主循环：钉扎需 ~14 帧，若继续跑 tick（TICK_DT=1/20），快速机器上对局会在 §15 前
	# 推进到 gameover（page='gameover' → 滚轮被 _camera_free() 拦截 → §15 假红，实测复现）；
	# 相机/输入路径不经 _process，冻结不影响 §15 滚轮断言。
	main.set_process(false)
	var flat_cells: Array = []
	for yy in range(24, 41):
		for xx in range(24, 41):
			var g0: float = view.ground_y(xx, yy)
			var mx := 0.0
			# 2026-10-24 重标定：地形有真实高台后，半径 2 内的 1 级台地会挡住投影射线
			# （实测 (27,24) 被 (27,22) 的 h1 顶面截获）→ 平坦判定扩到半径 2。
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if Grid.hex_dist(xx, yy, xx + dx, yy + dy) <= 2:
						mx = maxf(mx, absf(view.ground_y(xx + dx, yy + dy) - g0))
			if mx <= 0.10:
				flat_cells.append(Vector2i(xx, yy))
	check(flat_cells.size() >= 20, "存在平坦格群（%d 格）" % flat_cells.size())
	var rows_used: Array = []
	var pin_n := 0
	for fc in flat_cells:
		if pin_n >= 6:
			break
		if rows_used.has(fc.y):
			continue
		rows_used.append(fc.y)
		view.core.focus = Vector3(view.cell_to_world(fc.x, fc.y).x, 0.0, view.cell_to_world(fc.x, fc.y).z)
		view.core.yaw = 0.0
		view.core._zoom = 1.0
		view.core._apply_cam()
		await _frames(2)
		var spf := _sp_of(view, fc)
		if spf.x < 0.0 or spf.x >= vp_size.x or spf.y < 0.0 or spf.y >= vp_size.y:
			continue
		var backf: Vector2i = view.pick_cell(spf.x, spf.y)
		check(backf == fc, "钉扎位姿平坦格回拾 %s→%s" % [str(fc), str(backf)])
		pin_n += 1
	check(pin_n >= 6, "至少 6 格完成回拾（实际 %d）" % pin_n)

	# ---- 15. 滚轮缩放（缩放值上下限 0.16–1.8；暂停与 HUD 区冻结）----
	# 2026-10-26 重钉：下限 0.16 时最小视距会沿视线把相机拉远，y 不再随 zoom 线性变化，
	# 旧「相机 y 比值」口径在下限附近失效 → 上下限直接断言 core._zoom。
	var yz0: float = cam.global_position.y
	await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	var yz1: float = cam.global_position.y
	check(yz1 < yz0 - 1.0, "滚轮拉近（y %.1f→%.1f）" % [yz0, yz1])
	await _wheel_at(vp_size * Vector2(0.5, 0.5), false)
	var yz2: float = cam.global_position.y
	# 还原带 2.5：滚轮步进不对称（上滚×0.9/下滚×1.1，camera_control.gd wheel_step）→
	# 单步往返 zoom 落 0.99；叠加 2026-10-27 缩放-俯角联动（view_core._pitch_for_zoom）
	# → y 残差 ≈ _dist×1%×sin42°。64 时代 _dist≈86 残差 ~0.9 过旧带 1.0；128 图 _dist≈173
	# 实测 y 115.9→114.2（残差 1.7，闭式验算 171.6×sin41.74°=114.2 吻合）→ 带重定 2.5。
	check(absf(yz2 - yz0) < 2.5, "滚轮拉远还原（y %.1f，基准 %.1f）" % [yz2, yz0])
	for _i in 20:
		await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	check(is_equal_approx(view.core._zoom, 0.16), "拉近限位 0.16（zoom %.4f）" % view.core._zoom)
	await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	check(is_equal_approx(view.core._zoom, 0.16), "下限再上滚仍 0.16（zoom %.4f）" % view.core._zoom)
	# 0.16×1.1^n 需要 n=26 才够夹到 1.8（24 次只有 1.576）：数值口径必须给足次数
	for _i in 26:
		await _wheel_at(vp_size * Vector2(0.5, 0.5), false)
	check(is_equal_approx(view.core._zoom, 1.8), "拉远限位 1.8（zoom %.4f）" % view.core._zoom)
	await _wheel_at(vp_size * Vector2(0.5, 0.5), false)
	check(is_equal_approx(view.core._zoom, 1.8), "上限再下滚仍 1.8（zoom %.4f）" % view.core._zoom)
	main.paused = true
	await _wheel_at(vp_size * Vector2(0.5, 0.5), true)
	check(is_equal_approx(view.core._zoom, 1.8), "暂停中滚轮冻结（zoom %.4f）" % view.core._zoom)
	main.paused = false
	# HUD 区冻结：先把缩放摆回中段（停在 1.8 时下滚本来就不变，断言会变成空转）
	view.core._zoom = 1.0
	view.core._apply_cam()
	await _wheel_at(_hud_pt(main), false)
	check(is_equal_approx(view.core._zoom, 1.0), "HUD 区滚轮冻结（zoom %.4f）" % view.core._zoom)

	# ---- 16. 俯角（18°..78° 夹取；实测视线角；最小视距只沿视线后退不改角度）----
	view.core.set_pitch(deg_to_rad(18.0))
	check(absf(rad_to_deg(view.core.pitch()) - 18.0) < 0.02, "俯角 set_pitch(18°) 读回 %.3f°" % rad_to_deg(view.core.pitch()))
	var dir_p: Vector3 = (view.core.focus - cam.global_position).normalized()
	var ang18: float = rad_to_deg(atan2(-dir_p.y, sqrt(dir_p.x * dir_p.x + dir_p.z * dir_p.z)))
	check(absf(ang18 - 18.0) < 0.05, "俯角 18° 实际视线角 %.3f°" % ang18)
	var clr18: float = cam.global_position.y - view.terrain.ground_h(cam.global_position.x, cam.global_position.z)
	check(clr18 >= 9.9, "俯角 18° 相机净空 %.2fm ≥9.9" % clr18)
	view.core.set_pitch(deg_to_rad(42.0))
	view.core._zoom = 1.0
	view.core._apply_cam()
	var y_nom42: float = view.core._dist * sin(deg_to_rad(42.0))
	check(absf(cam.global_position.y - y_nom42) < 0.05, "俯角 42° 默认档不触发最小视距（y %.3f / 名义 %.3f）" % [cam.global_position.y, y_nom42])
	view.core.set_pitch(deg_to_rad(5.0))
	check(absf(rad_to_deg(view.core.pitch()) - 18.0) < 0.02, "俯角 5° 夹到 18°（%.3f°）" % rad_to_deg(view.core.pitch()))
	view.core.set_pitch(deg_to_rad(85.0))
	check(absf(rad_to_deg(view.core.pitch()) - 78.0) < 0.02, "俯角 85° 夹到 78°（%.3f°）" % rad_to_deg(view.core.pitch()))
	var dir_h: Vector3 = (view.core.focus - cam.global_position).normalized()
	var ang78: float = rad_to_deg(atan2(-dir_h.y, sqrt(dir_h.x * dir_h.x + dir_h.z * dir_h.z)))
	check(absf(ang78 - 78.0) < 0.05, "俯角 78° 实际视线角 %.3f°" % ang78)
	# 近景（zoom 0.16）+ 18°：净空靠「沿视线后退」补足，俯角必须仍是 18°
	view.core._zoom = 0.16
	view.core.set_pitch(deg_to_rad(18.0))
	var clr_near: float = cam.global_position.y - view.terrain.ground_h(cam.global_position.x, cam.global_position.z)
	check(clr_near >= 9.9, "俯角 近景 18° 相机净空 %.2fm ≥9.9（最小视距生效）" % clr_near)
	var dir_n: Vector3 = (view.core.focus - cam.global_position).normalized()
	var ang_near: float = rad_to_deg(atan2(-dir_n.y, sqrt(dir_n.x * dir_n.x + dir_n.z * dir_n.z)))
	check(absf(ang_near - 18.0) < 0.05, "俯角 近景实际视线角仍 18°（%.3f°）" % ang_near)
	# 复位默认档（42° / zoom1 / yaw0）
	view.core._zoom = 1.0
	view.core.yaw = 0.0
	view.core.set_pitch(deg_to_rad(42.0))
	await _frames(1)

	# ---- 17. 中键拖拽（上下调俯角 / 左右调偏航；HUD 区与左键拖拽期间不启动）----
	# 灵敏度 0.005 rad/px：向下拖 100px = +0.5rad（俯角变陡），向右拖 = 偏航变大（跟手）。
	view.core.yaw = 0.0
	view.core._zoom = 1.0
	view.core.set_pitch(deg_to_rad(42.0))
	var cp: Vector2 = vp_size * Vector2(0.5, 0.5)
	var mb_p0: float = rad_to_deg(view.core.pitch())
	await _mmb(cp, true)
	await _mmb_move(cp + Vector2(0.0, 100.0))
	var mb_p1: float = rad_to_deg(view.core.pitch())
	await _mmb(cp + Vector2(0.0, 100.0), false)
	check(absf((mb_p1 - mb_p0) - rad_to_deg(0.5)) < 0.1, "中键下拖 100px 俯角 +28.65°（%.2f→%.2f）" % [mb_p0, mb_p1])
	var mb_y0: float = view.core.yaw
	await _mmb(cp, true)
	await _mmb_move(cp + Vector2(-80.0, 0.0))
	var mb_y1: float = view.core.yaw
	await _mmb(cp + Vector2(-80.0, 0.0), false)
	check(absf((mb_y1 - mb_y0) + 0.4) < 0.01, "中键右拖 -80px 偏航 -0.4rad（%.4f）" % (mb_y1 - mb_y0))
	var mb_h0: float = rad_to_deg(view.core.pitch())
	await _mmb_drag(_hud_pt(main), Vector2(0.0, 100.0))
	check(absf(rad_to_deg(view.core.pitch()) - mb_h0) < 0.01, "HUD 区中键不调俯角（%.2f°）" % rad_to_deg(view.core.pitch()))
	main.drag_start = Vector2i(24, 24)
	var mb_d0: float = rad_to_deg(view.core.pitch())
	await _mmb_drag(cp, Vector2(0.0, 100.0))
	check(absf(rad_to_deg(view.core.pitch()) - mb_d0) < 0.01, "左键拖拽占用时中键不调俯角（%.2f°）" % rad_to_deg(view.core.pitch()))
	main.drag_start = Vector2i(-1, -1)
	await _mmb(cp, true)
	await _rmb_tap(cp)
	check(main.camera_control.mmb == true, "右键点按不清中键拖拽态")
	var mb_r0: float = view.core.pitch()
	await _mmb_move(cp + Vector2(0.0, -50.0))
	var mb_r1: float = view.core.pitch()
	await _mmb(cp + Vector2(0.0, -50.0), false)
	check(absf((mb_r0 - mb_r1) - 0.25) < 0.05, "中键上拖 50px 俯角 -0.25rad（%.3f→%.3f）" % [mb_r0, mb_r1])

	# ---- 18. 低角拾取回环（18°/30°/42° × 平坦/崖壁/盆地/边缘格）----
	# 崖壁/盆地取「钉扎视角下顶面真实可见」的代表格：全图极值格在低角钉扎视角常被前方地形遮挡，
	# 遮挡不是拾取缺陷——拿「必须回到被遮挡的极值格」当判据本身是错的 oracle，故先按可见性筛代表格。
	# 筛选口径（固定顺序、确定性）：行优先遍历候选，崖壁 = 地面高 ≥3.5 且南侧 hex 邻格（y+1/y+2）
	# 低 ≥1.0（朝镜头方向有落差面）；盆地 = 地面高 ≤0.5；候选须在 18°/30°/42° 三角度都回拾为自身。
	var cliff_cands: Array = []
	var basin_cands: Array = []
	for yy in world.sc.h:
		for xx in world.sc.w:
			var gyy: float = view.ground_y(xx, yy)
			if gyy >= 3.5 and _south_drop(view, xx, yy, 1.0):
				cliff_cands.append(Vector2i(xx, yy))
			if gyy <= 0.5:
				basin_cands.append(Vector2i(xx, yy))
	var cliff_cell: Vector2i = await _visible_rep(view, cliff_cands)
	var basin_cell: Vector2i = await _visible_rep(view, basin_cands)
	if cliff_cell.x < 0:
		fail("崖壁类无三角度都可见的代表格（候选 %d 格）" % cliff_cands.size())
	if basin_cell.x < 0:
		fail("盆地类无三角度都可见的代表格（候选 %d 格）" % basin_cands.size())
	# 边缘格同口径可见性筛选：128 图北缘硬编码 (64,0) 的低角射线被内陆高台
	# （实测 (64,8) top>7.1）截住，回拾 (64,8)/(64,4)/(63,3) —— 按本节 oracle 原则
	# （遮挡不是拾取缺陷），边缘代表格改为行 0 上第一个三角度都回拾为自身的格。
	var edge_cands: Array = []
	for xx in range(2, Dims.MAP_N - 2):
		edge_cands.append(Vector2i(xx, 0))
	var edge_cell: Vector2i = await _visible_rep(view, edge_cands)
	if edge_cell.x < 0:
		fail("边缘类无三角度都可见的代表格（候选 %d 格）" % edge_cands.size())
	var kinds: Array = [
		["平坦", flat_cells[0]],
		["崖壁", cliff_cell],
		["盆地", basin_cell],
		["边缘", edge_cell],
	]
	for pd in [18.0, 30.0, 42.0]:
		for kind in kinds:
			var cell: Vector2i = kind[1]
			if cell.x < 0:
				continue # 该类别无代表格：上面已 fail 记明，这里不再造伪断言
			var back: Vector2i = await _pick_at(view, cell, pd)
			check(back == cell, "俯角%.0f° 拾取回环·%s %s→%s" % [pd, kind[0], str(cell), str(back)])
	# 复位默认档 + 焦点回地图中心
	view.core._zoom = 1.0
	view.core.yaw = 0.0
	view.core.focus = Vector3.ZERO
	view.core.set_pitch(deg_to_rad(42.0))
	await _frames(1)
	finish("INPUT", 47)


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


## 活建筑数（撤销只把 hp 置 0，尸体在本 tick 清理前仍留在 world.buildings 数组里）。
func _alive_count(world) -> int:
	var n := 0
	for b in world.buildings:
		if int(b["hp"]) > 0:
			n += 1
	return n


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


## 带 Ctrl 修饰的按键（撤销 Ctrl+Z）。
func _key_mod(code: Key, ctrl: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	get_root().push_input(ev)
	await process_frame


## 拖拽中途取消：esc=true 用 Esc；false 用右键。均不发左键起手后的落子。
func _drag_cancel(view, from_cell: Vector2i, to_cell: Vector2i, esc: bool) -> void:
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
	if esc:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.pressed = true
		get_root().push_input(ev)
		await process_frame
	else:
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		rmb.pressed = true
		rmb.position = sp1
		get_root().push_input(rmb)
		await process_frame
		rmb = InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		rmb.pressed = false
		rmb.position = sp1
		get_root().push_input(rmb)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = sp1
	get_root().push_input(up)
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


## 按住某键 ms 毫秒再松开（墙钟口径：旋转按 dt 累积，帧计时在高帧率机器上会漂移到毫秒级）。
func _hold_key_ms(code: Key, ms: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	get_root().push_input(down)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
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


## 中键按下/抬起（pos 处；中键 = 上下调俯角 / 左右调偏航）。
func _mmb(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = pressed
	ev.position = pos
	get_root().push_input(ev)
	await process_frame


## 鼠标移动注入（中键拖拽用位置差算增量，故不填 relative）。
func _mmb_move(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	get_root().push_input(mv)
	await process_frame


## 中键拖拽：按下 → 移动 delta → 松开。
func _mmb_drag(pos: Vector2, delta: Vector2) -> void:
	await _mmb(pos, true)
	await _mmb_move(pos + delta)
	await _mmb(pos + delta, false)


## 右键点按（按下 + 抬起，不移动；测中键/右键状态互不清）。
func _rmb_tap(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	down.position = pos
	get_root().push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	up.position = pos
	get_root().push_input(up)
	await process_frame


## HUD 点击排除区里、且**不压在控件上**的一点（右下角排除区贴右缘 4px 的空边）。
## 两个坑：① v2.5 指挥坞挪到右下角后，「右侧空地 (vp.x-30, 400)」已不在 hit_regions 内，
## 拿它测 HUD 冻结会空转；② 滚轮事件没有配对抬起，压在 STOP 控件（顶栏/HUD 钮）上会把 GUI
## 鼠标抓取粘住，此后所有鼠标事件都被那个控件吞掉（实测 §17 中键整段静默）→ 只能选无控件处。
func _hud_pt(main) -> Vector2:
	var rs: Array = main.hud.hit_regions()
	if rs.size() < 2:
		return Vector2(640.0, 28.0)
	var r: Rect2 = rs[1]
	return Vector2(r.end.x - 4.0, r.position.y + 100.0)


# ---------------- 扫描辅助 ----------------

## 南侧（y+1 / y+2 行、hex 相邻）是否存在比本格低 ≥drop 的邻格：本格朝镜头方向有落差面 = 崖壁候选。
func _south_drop(view, x: int, y: int, drop: float) -> bool:
	var g0: float = view.ground_y(x, y)
	for dy in [1, 2]:
		for dx in range(-1, 2):
			var nx: int = x + int(dx)
			var ny: int = y + int(dy)
			if nx < 0 or ny < 0 or nx >= Dims.MAP_N or ny >= Dims.MAP_N:
				continue
			if Grid.hex_dist(x, y, nx, ny) != 1:
				continue
			if g0 - view.ground_y(nx, ny) >= drop:
				return true
	return false


## 钉扎位姿（focus=格心 / yaw=0 / zoom=1 / 指定俯角）后投影该格顶面并回拾；屏外或未命中返回 (-1,-1)。
func _pick_at(view, cell: Vector2i, pitch_deg: float) -> Vector2i:
	view.core._zoom = 1.0
	view.core.yaw = 0.0
	view.core.set_pitch(deg_to_rad(pitch_deg))
	var w: Vector3 = view.cell_to_world(cell.x, cell.y)
	view.core.focus = Vector3(w.x, 0.0, w.z)
	view.core._apply_cam()
	await _frames(2)
	var sp: Vector2 = _sp_of(view, cell)
	if sp.x < 0.0 or sp.x >= vp_size.x or sp.y < 0.0 or sp.y >= vp_size.y:
		return Vector2i(-1, -1)
	return view.pick_cell(sp.x, sp.y)


## 行优先候选里第一个「18°/30°/42° 三角度都回拾为自身」的格（= 顶面真实可见）；没有则 (-1,-1)。
func _visible_rep(view, cands: Array) -> Vector2i:
	for cand in cands:
		var c: Vector2i = cand
		var ok := true
		for pd in [18.0, 30.0, 42.0]:
			var back: Vector2i = await _pick_at(view, c, pd)
			if back != c:
				ok = false
				break
		if ok:
			return c
	return Vector2i(-1, -1)


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
	# 取景拉近后地图边缘会压到 HUD 下：被 HUD 覆盖的格真实输入会被 main.in_hud_region 排除，不算可点击
	var mn = view.get_parent()
	if mn != null and mn.has_method("in_hud_region") and mn.in_hud_region(sp.x, sp.y):
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


## 窗口内找「可点击且 h > H_MIN」的格（反向改高对的挖低端；自由路径地图无固定台地可用）。
func _find_clickable_h(view, world, x0: int, y0: int, x1: int, y1: int, exclude: Array) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if exclude.has(Vector2i(x, y)):
				continue
			if world.grid.get_h(x, y) <= Sim.H_MIN:
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
	for y in world.sc.h:
		for x in world.sc.w:
			if world.grid.at(x, y) == Grid.COVER and world.sc.is_ore(x, y):
				if _clickable_cover(view, x, y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## 矿格是 COVER（不可通行）——单独的回环检查（不走 _clickable 的 passable 前置）。
func _clickable_cover(view, x: int, y: int) -> bool:
	var sp := _sp_of(view, Vector2i(x, y))
	if sp.x < 0.0 or sp.y < 0.0 or sp.x >= vp_size.x or sp.y >= vp_size.y:
		return false
	# 取景拉近后地图边缘会压到 HUD 下：被 HUD 覆盖的格真实输入会被 main.in_hud_region 排除，不算可点击
	var mn = view.get_parent()
	if mn != null and mn.has_method("in_hud_region") and mn.in_hud_region(sp.x, sp.y):
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
			if _clickable_cover(view, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)
