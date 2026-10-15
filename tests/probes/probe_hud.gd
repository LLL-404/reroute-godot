extends SceneTree

# C6 判定：HUD 机械断言（窗口模式运行）。
# 断言组：hit_regions 数值口径 / 血条与文本跟随 / 波次文案与横幅调度 / 供给闪烁 /
#         模式钮状态与真实点击链路 / 技能钮冷却文案 / 浮字池生命周期 / 整体显隐 /
#         HUD 区域点击排除（含对照：战场点击有效）/ 界面截图（人眼复核中文渲染）。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_hud.gd
var checks := 0
var bad := 0
var fail_list: Array = []
var vp_size := Vector2(1280.0, 720.0)


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame # -s 模式：_ready 在首帧才跑；set_process 须在 ready 之后调用才粘
	main.set_process(false) # 探针独占推进
	main.start_match() # 进入对局（R6 起启动即标题屏）
	var world = main.world
	var hud = main.hud
	vp_size = get_root().get_visible_rect().size
	print("[HUD] viewport=", vp_size)

	# ---- 1. S 缩放与 hit_regions 数值口径 ----
	_gcheck(absf(hud.S - 1.0) < 1e-6, "S=1.0（720/816 夹紧）")
	var regions: Array = hud.hit_regions()
	_rect_eq(regions[0], Rect2(0, 0, 1280, 64), "命中区·顶栏条")
	_rect_eq(regions[1], Rect2(1120, 303, 160, 417), "命中区·右下钮簇")
	var chars := "放墙改道 · 怪绕得越远死时赏金越高——修运河，别只堵路".length()
	_cmp_i(chars, 28, "提示文本字符数")
	_rect_eq(regions[2], Rect2(0, 64, 284, 36), "命中区·提示徽章")

	# ---- 2. 血条/文本跟随 ----
	hud.update(world)
	_gcheck(hud.hp_text.text == "1200/1200", "初始血量文本")
	_gcheck(absf(hud.hp_bar.value - 1200.0) < 0.01, "初始血条值")
	world.core["hp"] = 950
	hud.update(world)
	_gcheck(hud.hp_text.text == "950/1200", "血量跟随")
	_gcheck(absf(hud.hp_bar.value - 950.0) < 0.01, "血条跟随")
	world.core["hp"] = 1200

	# ---- 3. 波次文案与横幅调度 ----
	world.tick_count = 0
	hud.update(world)
	_gcheck(hud.wave_text.text == "下一波 3s · 虫群×1", "波次文案 t=0（得 " + hud.wave_text.text + "）")
	world.tick_count = 50
	hud.update(world)
	_gcheck(hud.wave_text.text == "下一波 1s · 虫群×1", "波次文案 t=50（得 " + hud.wave_text.text + "）")
	world.tick_count = 60
	hud.update(world)
	_gcheck(hud.banner_root.visible == true, "横幅出现 t=60")
	_gcheck(hud.banner_title.text == "第 1 波", "横幅标题（得 " + hud.banner_title.text + "）")
	_gcheck(hud.banner_sub.text == "虫群×1", "横幅编成（得 " + hud.banner_sub.text + "）")
	world.tick_count = 100
	hud.update(world)
	_gcheck(hud.banner_root.visible == false, "横幅到期熄灭 t=100")
	world.route_opened = true
	hud.update(world)
	_gcheck(hud.banner_root.visible == true and hud.banner_title.text == "暗门已开", "暗门横幅登场")
	# 终局倒计时文案：波次表放完（tick 5000 > 末波 4860）才走"暗门已开 · 终局"分支
	world.tick_count = 5000
	hud.update(world)
	_gcheck(hud.wave_text.text == "暗门已开 · 终局 1:10", "终局倒计时文案（得 " + hud.wave_text.text + "）")

	# ---- 4. 供给跳动 ----
	world.supply = 250
	hud.update(world)
	_gcheck(hud.supply_text.text == "供给 250", "供给文本更新")
	var c_flash: Color = hud.supply_text.get_theme_color("font_color")
	_gcheck(c_flash.is_equal_approx(hud.DARK["text"]), "供给变化闪白")
	world.tick_count = 5005 # 向前推进（tick 单调增是真实对局口径）
	hud.update(world)
	var c_idle: Color = hud.supply_text.get_theme_color("font_color")
	_gcheck(c_idle.is_equal_approx(hud.DARK["supply"]), "闪烁结束回金色")

	# ---- 5. 模式钮状态 + 真实点击链路 ----
	_gcheck(hud.mode == "wall", "初始模式 wall")
	_check_btn_color(hud, "wall", true, "wall 按钮点亮")
	hud.set_mode("tower")
	_check_btn_color(hud, "tower", true, "set_mode 点亮 tower")
	_check_btn_color(hud, "wall", false, "set_mode 复原 wall")
	hud.set_mode("wall") # 复位，让"点击生效"有可观测的状态迁移
	_gcheck(hud.mode == "wall", "点击前复位 wall")
	_gcheck(hud.mode_buttons["wall"].text == "墙 ×10", "墙钮文案")
	_gcheck(hud.mode_buttons["tower"].text == "塔 ×60", "塔钮文案")
	_gcheck(hud.mode_buttons["fill"].text == "填高 ×15", "填高钮文案")
	# 点击"塔"按钮（真实事件）
	var btn_tower: Button = hud.mode_buttons["tower"]
	var center: Vector2 = btn_tower.global_position + btn_tower.size * 0.5
	var md := InputEventMouseButton.new()
	md.button_index = MOUSE_BUTTON_LEFT
	md.pressed = true
	md.position = center
	get_root().push_input(md)
	await process_frame
	var mu := InputEventMouseButton.new()
	mu.button_index = MOUSE_BUTTON_LEFT
	mu.pressed = false
	mu.position = center
	get_root().push_input(mu)
	await process_frame
	_gcheck(hud.mode == "tower", "点击塔钮 → hud.mode")
	_gcheck(main.mode == "tower", "点击塔钮 → main.mode")
	_check_btn_color(hud, "tower", true, "点击后 tower 点亮")
	_check_btn_color(hud, "wall", false, "点击后 wall 复原")

	# ---- 6. 按钮矩形都在命中区内 ----
	var r_corner: Rect2 = regions[1]
	for key in hud.mode_buttons:
		var b: Button = hud.mode_buttons[key]
		_gcheck(r_corner.encloses(Rect2(b.global_position, b.size)), "模式钮 " + str(key) + " 在命中区内")
	_gcheck(r_corner.encloses(Rect2(hud.skill_btn.global_position, hud.skill_btn.size)), "技能钮在命中区内")
	var r_top: Rect2 = regions[0]
	_gcheck(r_top.encloses(Rect2(hud.heat_btn.global_position, hud.heat_btn.size)), "热层钮在顶栏带内")
	_gcheck(r_top.encloses(Rect2(hud.pause_btn.global_position, hud.pause_btn.size)), "暂停钮在顶栏带内")

	# ---- 7. 技能钮冷却文案 ----
	world.hero["skill_cd"] = 400
	hud.update(world)
	_gcheck(hud.skill_btn.text == "冷却 20s" and hud.skill_btn.disabled, "技能冷却文案+禁用")
	world.hero["skill_cd"] = 0
	hud.update(world)
	_gcheck(hud.skill_btn.text == "震荡波" and not hud.skill_btn.disabled, "技能就绪复原")

	# ---- 8. 浮字池生命周期 ----
	world.tick_count = 120
	hud.update(world)
	hud.float_bounty(100.0, 200.0, "+7")
	var f0: Dictionary = hud.floats[0]
	var el0: Label = f0["el"]
	_gcheck(f0["active"] == true and el0.visible and el0.text == "+7", "浮字激活")
	world.tick_count = 125
	hud.update(world)
	_gcheck(absf(el0.position.x - 86.0) < 0.01 and absf(el0.position.y - 175.0) < 0.01, "浮字上浮位置（得 " + str(el0.position) + "）")
	_gcheck(absf(el0.get_theme_color("font_color").a - (1.0 - 5.0 / 18.0)) < 0.01, "浮字透明度")
	world.tick_count = 138
	hud.update(world)
	_gcheck(f0["active"] == false and not el0.visible, "浮字到期熄灭")

	# ---- 9. 整体显隐 ----
	hud.float_bounty(50.0, 50.0, "+3")
	hud.set_visible_hud(false)
	_gcheck(not hud.top_bar.visible and not hud.hint_panel.visible and not hud.mode_buttons["wall"].visible, "整体隐藏")
	_gcheck(hud.floats[1]["active"] == false, "隐藏时浮字熄灭")
	hud.set_visible_hud(true)
	_gcheck(hud.top_bar.visible and hud.mode_buttons["wall"].visible, "整体恢复")

	# ---- 10. HUD 点击排除（端到端，含对照） ----
	main.set_mode("wall")
	hud.set_mode("wall")
	var sup0: int = world.supply
	await _click_at(Vector2(640, 30)) # 顶栏面板区
	_cmp_i(world.supply, sup0, "顶栏点击零副作用")
	await _click_at(Vector2(640, 60)) # 命中条内、面板外
	_cmp_i(world.supply, sup0, "命中条点击零副作用")
	var cell := _find_clickable(main, world)
	_gcheck(cell.x >= 0, "对照用可点击格扫描")
	if cell.x >= 0:
		var sp: Vector2 = _sp_of(main, cell)
		await _click_at(sp)
		var b = world.building_at(cell.x, cell.y)
		_gcheck(b != null and int(b["kind"]) == Sim.B_WALL, "对照：战场点击放墙生效")
		_cmp_i(world.supply, sup0 - 10, "对照：扣费 10")

	# ---- 11. 展示态截图（人眼复核） ----
	world.hero["skill_cd"] = 400
	hud.update(world)
	hud.banner("第 1 波", "虫群×1", false)
	hud.float_bounty(700.0, 300.0, "+7")
	hud.float_bounty(760.0, 260.0, "+12")
	# 场地加两只单位 + 一面墙做底色
	var spots: Array = []
	for _i in 3:
		var c := _find_clickable(main, world, spots)
		if c.x >= 0:
			spots.append(c)
	if spots.size() >= 3:
		world.apply_command({ "kind": "spawn", "x": spots[0].x, "y": spots[0].y, "speed": 4, "kind_id": Sim.E_SWARM })
		world.apply_command({ "kind": "spawn", "x": spots[1].x, "y": spots[1].y, "speed": 8, "kind_id": Sim.E_BEHEMOTH })
		world.apply_command({ "kind": "tower", "x": spots[2].x, "y": spots[2].y })
	main.view.sync(world)
	for _i in 20:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://shots/hud.png")
	print("[HUD] shot saved ", img.get_width(), "x", img.get_height())

	# ---- 汇总 ----
	var ok := bad == 0 and checks >= 30
	print("[HUD] checks=", checks, " bad=", bad)
	for i in mini(fail_list.size(), 15):
		print("[HUD] fail: ", fail_list[i])
	print("[HUD] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


# ---------------- 辅助 ----------------

func _check_btn_color(hud, key: String, active: bool, label: String) -> void:
	var btn: Button = hud.mode_buttons[key]
	var sb: StyleBoxFlat = btn.get_meta("sb_normal")
	var want: Color = hud.DARK["active"] if active else hud.DARK["btn"]
	_gcheck(sb.bg_color.is_equal_approx(want), label)


func _click_at(pos: Vector2) -> void:
	var md := InputEventMouseButton.new()
	md.button_index = MOUSE_BUTTON_LEFT
	md.pressed = true
	md.position = pos
	get_root().push_input(md)
	await process_frame
	var mu := InputEventMouseButton.new()
	mu.button_index = MOUSE_BUTTON_LEFT
	mu.pressed = false
	mu.position = pos
	get_root().push_input(mu)
	await process_frame


func _sp_of(main, cell: Vector2i) -> Vector2:
	var view = main.view
	var w: Vector3 = view.cell_to_world(cell.x, cell.y)
	var gy: float = view.ground_y(cell.x, cell.y)
	return view.camera.unproject_position(Vector3(w.x, gy + 0.1, w.z))


func _find_clickable(main, world, exclude: Array = []) -> Vector2i:
	var view = main.view
	for y in range(6, 30):
		for x in range(8, 40):
			if exclude.has(Vector2i(x, y)):
				continue
			if not world.grid.passable(x, y):
				continue
			if world.building_at(x, y) != null:
				continue
			if not world.cell_vacant(x, y):
				continue
			var hr: Dictionary = world.hero
			if x == int(hr["x"]) and y == int(hr["y"]):
				continue
			var sp := _sp_of(main, Vector2i(x, y))
			if sp.x < 0.0 or sp.y < 0.0 or sp.x >= vp_size.x or sp.y >= vp_size.y:
				continue
			var back: Vector2i = view.pick_cell(sp.x, sp.y)
			if back.x == x and back.y == y:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _fail(msg: String) -> void:
	bad += 1
	fail_list.append(msg)


func _gcheck(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		_fail(label)


func _cmp_i(got: int, want: int, label: String) -> void:
	checks += 1
	if got != want:
		_fail(label + " got=%d want=%d" % [got, want])


func _rect_eq(got: Rect2, want: Rect2, label: String) -> void:
	checks += 1
	if absf(got.position.x - want.position.x) > 0.01 or absf(got.position.y - want.position.y) > 0.01 or absf(got.size.x - want.size.x) > 0.01 or absf(got.size.y - want.size.y) > 0.01:
		_fail(label + " got=%s want=%s" % [str(got), str(want)])
