extends ProbeKit

# C6 判定：HUD 机械断言（窗口模式运行）。
# 断言组：hit_regions 数值口径 / 血条与文本跟随 / 波次文案与横幅调度 / 供给闪烁 /
#         模式钮状态与真实点击链路 / 技能钮冷却文案 / 浮字池生命周期 / 整体显隐 /
#         HUD 区域点击排除（含对照：战场点击有效）/ 窗口缩放一致性（S 与 hit_regions 重算）/
#         界面截图（人眼复核中文渲染）。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_hud.gd
# 判定：exit 0 + stdout 含 `[HUD] PASS`。
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
	check(absf(hud.S - 1.0) < 1e-6, "S=1.0（720/816 夹紧）")
	# 开局无横幅：整层复显不得误亮「空横幅」（2026-10-19 缺陷修复护栏；旧实现此处空卡片驻留）
	check(hud.banner_root.visible == false, "开局无横幅（空卡片不驻留）")
	var regions: Array = hud.hit_regions()
	cmp_rect(regions[0], Rect2(0, 0, 1280, 64), "命中区·顶栏条")
	cmp_rect(regions[1], Rect2(1280 - 268, 720 - 260, 268, 260), "命中区·右下指挥坞")
	var chars := "放墙改道 · 怪绕得越远死时赏金越高——修运河，别只堵路".length()
	cmp_int(chars, 28, "提示文本字符数")
	check(regions[2].position == Vector2(16, 64), "命中区·提示条起点")
	check(regions[2].size.x > 280.0 and regions[2].size.x < 330.0, "命中区·提示条宽度（得 %s）" % str(regions[2].size.x))
	check(regions[2].size.y > 20.0 and regions[2].size.y < 34.0, "命中区·提示条高度（得 %s）" % str(regions[2].size.y))

	# ---- 2. 血条/文本跟随 ----
	hud.update(world)
	check(hud.hp_text.text == "1200/1200", "初始血量文本")
	check(absf(hud.hp_bar.value - 1200.0) < 0.01, "初始血条值")
	world.core["hp"] = 950
	hud.update(world)
	check(hud.hp_text.text == "950/1200", "血量跟随")
	check(absf(hud.hp_bar.value - 950.0) < 0.01, "血条跟随")
	world.core["hp"] = 1200

	# ---- 3. 波次文案与横幅调度 ----
	world.tick_count = 0
	hud.update(world)
	check(hud.wave_text.text == "下一波 3s · 虫群×1", "波次文案 t=0（得 " + hud.wave_text.text + "）")
	world.tick_count = 50
	hud.update(world)
	check(hud.wave_text.text == "下一波 1s · 虫群×1", "波次文案 t=50（得 " + hud.wave_text.text + "）")
	world.tick_count = 60
	hud.update(world)
	check(hud.banner_root.visible == true, "横幅出现 t=60")
	check(hud.banner_title.text == "第 1 波", "横幅标题（得 " + hud.banner_title.text + "）")
	check(hud.banner_sub.text == "虫群×1", "横幅编成（得 " + hud.banner_sub.text + "）")
	world.tick_count = 100
	hud.update(world)
	check(hud.banner_root.visible == false, "横幅到期熄灭 t=100")
	world.route_opened = true
	hud.update(world)
	check(hud.banner_root.visible == true and hud.banner_title.text == "暗门已开", "暗门横幅登场")
	# 终局倒计时文案：波次表放完（tick 5000 > 末波 4860）才走"暗门已开 · 终局"分支
	world.tick_count = 5000
	hud.update(world)
	check(hud.wave_text.text == "暗门已开 · 终局 1:10", "终局倒计时文案（得 " + hud.wave_text.text + "）")
	# v2.4：教学提示条驻留 20s 后自动淡出（hit_regions 随之让位）
	check(hud._hint_hidden, "提示条 20s 后自动淡出")

	# ---- 4. 供给跳动 ----
	world.supply = 250
	hud.update(world)
	check(hud.supply_text.text == "250", "供给文本更新")
	var c_flash: Color = hud.supply_text.get_theme_color("font_color")
	check(c_flash.is_equal_approx(hud.DARK["text"]), "供给变化闪白")
	world.tick_count = 5005 # 向前推进（tick 单调增是真实对局口径）
	hud.update(world)
	var c_idle: Color = hud.supply_text.get_theme_color("font_color")
	check(c_idle.is_equal_approx(hud.DARK["supply"]), "闪烁结束回金色")

	# ---- 5. 模式钮状态 + 真实点击链路 ----
	check(hud.mode == "wall", "初始模式 wall")
	_check_btn_color(hud, "wall", true, "wall 按钮点亮")
	hud.set_mode("tower")
	_check_btn_color(hud, "tower", true, "set_mode 点亮 tower")
	_check_btn_color(hud, "wall", false, "set_mode 复原 wall")
	hud.set_mode("wall") # 复位，让"点击生效"有可观测的状态迁移
	check(hud.mode == "wall", "点击前复位 wall")
	check(hud.row_name["wall"].text == "墙" and hud.row_cost["wall"].text == "10", "墙行 名称/成本")
	check(hud.row_name["tower"].text == "塔" and hud.row_cost["tower"].text == "60", "塔行 名称/成本")
	check(hud.row_cost["fill"].text == "15" and hud.row_cost["lower"].text == "10", "填高/挖低 成本")
	# ---- 5a. 撤销 pill（5s 撤销窗浮钮：窗内可见 + 倒计时文案；收起复位） ----
	hud.set_undo_vis(true, 4)
	check(hud.undo_panel != null and hud.undo_panel.visible, "撤销 pill 窗内可见")
	check(String(hud.undo_panel.text).contains("4"), "撤销 pill 倒计时 4s")
	hud.set_undo_vis(false)
	check(not hud.undo_panel.visible, "撤销 pill 收起隐藏")
	hud.set_undo_vis(true, 9)
	check(hud.undo_panel.visible and String(hud.undo_panel.text).contains("9"), "撤销 pill 复显 + 文案刷新 9s")
	hud.set_undo_vis(false) # 复位（后续排除区/战场断言不受浮钮影响）
	check(not hud.undo_panel.visible, "撤销 pill 复位隐藏")
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
	check(hud.mode == "tower", "点击塔钮 → hud.mode")
	check(main.mode == "tower", "点击塔钮 → main.mode")
	_check_btn_color(hud, "tower", true, "点击后 tower 点亮")
	_check_btn_color(hud, "wall", false, "点击后 wall 复原")

	# ---- 6. 按钮矩形都在命中区内 ----
	var r_corner: Rect2 = regions[1]
	for key in hud.mode_buttons:
		var b: Button = hud.mode_buttons[key]
		check(r_corner.encloses(Rect2(b.global_position, b.size)), "模式钮 " + str(key) + " 在命中区内")
	check(r_corner.encloses(Rect2(hud.skill_btn.global_position, hud.skill_btn.size)), "技能钮在命中区内")
	var r_top: Rect2 = regions[0]
	check(r_top.encloses(Rect2(hud.heat_btn.global_position, hud.heat_btn.size)), "热层钮在顶栏带内")
	check(r_top.encloses(Rect2(hud.pause_btn.global_position, hud.pause_btn.size)), "暂停钮在顶栏带内")

	# ---- 7. 技能钮冷却文案 ----
	world.hero["skill_cd"] = 400
	hud.update(world)
	check(hud.row_cost["skill"].text == "20s" and hud.skill_btn.disabled, "技能冷却文案+禁用")
	world.hero["skill_cd"] = 0
	hud.update(world)
	check(hud.row_cost["skill"].text == "就绪" and not hud.skill_btn.disabled, "技能就绪复原")
	check(hud.row_cost["skill"].get_theme_color("font_color").is_equal_approx(hud.DARK["supply"]), "就绪成本金字")

	# ---- 7b. 指挥坞与成本可负担性（v2.4）----
	check(hud.dock != null and hud.dock.size.x > 0.0 and hud.dock.size.y > 0.0, "指挥坞已建")
	check(hud.dock.get_rect().encloses(Rect2(hud.mode_buttons["hero"].position, hud.mode_buttons["hero"].size)), "坞面板包住末行")
	# v2.5：3 行 2/3/3 图标格（图标子节点随钮换色）
	check(hud.dock_rows.size() == 3 and hud.dock_rows[0].size() == 2 and hud.dock_rows[1].size() == 3 and hud.dock_rows[2].size() == 3, "指挥盘 2/3/3 格")
	check(hud.row_icon.size() == 8 and hud.row_icon["wall"].kind == "wall", "八格图标齐备")
	hud.set_mode("tower")
	check(hud.row_icon["tower"].color.is_equal_approx(hud.DARK["on_gold"]), "选中格图标转深字")
	hud.set_mode("wall")
	world.supply = 5
	hud.update(world)
	check(hud.row_cost["tower"].get_theme_color("font_color").is_equal_approx(hud.DARK["danger"]), "供给不足 → 成本红")
	world.supply = 250
	hud.update(world)
	hud.set_mode("wall")
	check(hud.row_cost["wall"].get_theme_color("font_color").is_equal_approx(hud.DARK["on_gold"]), "供给充足 → 点亮行成本深字")
	check(hud.row_cost["tower"].get_theme_color("font_color").is_equal_approx(hud.DARK["muted"]), "供给充足 → 常态行成本 muted")

	# ---- 8. 浮字池生命周期 ----
	world.tick_count = 120
	hud.update(world)
	hud.float_bounty(100.0, 200.0, "+7")
	var f0: Dictionary = hud.floats[0]
	var el0: Label = f0["el"]
	check(f0["active"] == true and el0.visible and el0.text == "+7", "浮字激活")
	world.tick_count = 125
	hud.update(world)
	check(absf(el0.position.x - 86.0) < 0.01 and absf(el0.position.y - 175.0) < 0.01, "浮字上浮位置（得 " + str(el0.position) + "）")
	check(absf(el0.get_theme_color("font_color").a - (1.0 - 5.0 / 18.0)) < 0.01, "浮字透明度")
	world.tick_count = 138
	hud.update(world)
	check(f0["active"] == false and not el0.visible, "浮字到期熄灭")
	# v2.4：贴屏幕上缘的赏金浮字钳在顶栏下（不压 HUD 条）
	hud.float_bounty(100.0, 10.0, "+9")
	world.tick_count = 142
	hud.update(world)
	var f2: Dictionary = hud.floats[0]
	check(absf(f2["el"].position.y - (hud.TOP_STRIP_H + 4.0)) < 0.01, "浮字钳在顶栏下（得 " + str(f2["el"].position.y) + "）")

	# ---- 9. 整体显隐 ----
	hud.float_bounty(50.0, 50.0, "+3")
	hud.set_visible_hud(false)
	check(not hud.top_bar.visible and not hud.hint_panel.visible and not hud.mode_buttons["wall"].visible, "整体隐藏")
	check(hud.floats[1]["active"] == false, "隐藏时浮字熄灭")
	hud.set_visible_hud(true)
	check(hud.top_bar.visible and hud.mode_buttons["wall"].visible, "整体恢复")
	# 横幅随整层显隐：活动横幅隐藏后复显保留；清掉活动态后复显仍不亮（自管口径）
	hud.banner("测试横幅", "副标题", false)
	hud.set_visible_hud(false)
	check(not hud.banner_root.visible, "隐藏时活动横幅同隐")
	hud.set_visible_hud(true)
	check(hud.banner_root.visible, "复显时活动横幅保留")
	hud._banner_until = null
	hud.set_visible_hud(true)
	check(not hud.banner_root.visible, "无活动横幅时复显仍不亮")

	# ---- 10. HUD 点击排除（端到端，含对照） ----
	main.set_mode("wall")
	hud.set_mode("wall")
	var sup0: int = world.supply
	await _click_at(Vector2(640, 30)) # 顶栏面板区
	cmp_int(world.supply, sup0, "顶栏点击零副作用")
	await _click_at(Vector2(640, 60)) # 命中条内、面板外
	cmp_int(world.supply, sup0, "命中条点击零副作用")
	var cell := _find_clickable(main, world)
	check(cell.x >= 0, "对照用可点击格扫描")
	if cell.x >= 0:
		var sp: Vector2 = _sp_of(main, cell)
		await _click_at(sp)
		var b = world.building_at(cell.x, cell.y)
		check(b != null and int(b["kind"]) == Sim.B_WALL, "对照：战场点击放墙生效")
		cmp_int(world.supply, sup0 - 10, "对照：扣费 10")

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

	# ---- 12. 窗口缩放一致性（D5-4：S 与 hit_regions 随视口重算）----
	var s0: float = hud.S
	root.size = Vector2i(1024, 960)
	for _i in 3:
		await process_frame
	var nwin: Vector2 = get_root().get_visible_rect().size
	check(nwin.y >= 850.0, "视口已放大（得 %s）" % str(nwin))
	var want_s := clampf(nwin.y / 816.0, 1.0, 1.6)
	cmp_approx(hud.S, want_s, "缩放后 S")
	cmp_approx(hud.top_bar.size.y, hud.TOP_H * want_s, "缩放后顶栏高随 S")
	var wregions: Array = hud.hit_regions()
	cmp_rect(wregions[0], Rect2(0, 0, nwin.x, floorf(hud.TOP_STRIP_H * want_s)), "缩放后命中区·顶栏条")
	var cw := floorf(hud.CORNER_W * want_s)
	var ch := floorf(hud.CORNER_H * want_s)
	cmp_rect(wregions[1], Rect2(nwin.x - cw, nwin.y - ch, cw, ch), "缩放后命中区·右下钮簇")
	root.size = Vector2i(1280, 720)
	for _i in 3:
		await process_frame
	cmp_approx(hud.S, s0, "还原后 S")
	cmp_rect(hud.hit_regions()[0], Rect2(0, 0, 1280, 64), "还原后命中区·顶栏条")

	# ---- 13. 安全区（D1-5：注入刘海/手势条内边距，HUD 与命中区同步内缩）----
	var s_ins := Vector4(48.0, 24.0, 60.0, 36.0)
	hud.set_safe_insets_override(s_ins)
	await process_frame
	var sregions: Array = hud.hit_regions()
	cmp_rect(sregions[0], Rect2(48, 24, 1280 - 48 - 60, 64), "安全区·顶栏条内缩")
	var cw4 := floorf(hud.CORNER_W * hud.S)
	var ch4 := floorf(hud.CORNER_H * hud.S)
	cmp_rect(sregions[1], Rect2(1280 - 60 - cw4, 720 - 36 - ch4, cw4, ch4), "安全区·右下钮簇内缩")
	check(hud.top_bar.position.is_equal_approx(Vector2(48, 24)), "安全区·顶栏起点内缩")
	check(absf(hud.top_bar.size.x - (1280.0 - 48.0 - 60.0)) < 0.5, "安全区·顶栏宽度内缩")
	var mbtn: Button = hud.mode_buttons["wall"]
	# 首行 2 格居中：坞内偏移 = PAD + (内容宽 - 2 格宽) / 2
	var row_w0: float = 2.0 * hud.CELL_W + hud.CELL_GAP
	var want_bx: float = hud.dock.position.x + (hud.DOCK_PAD + (hud.DOCK_W - hud.DOCK_PAD * 2.0 - row_w0) * 0.5) * hud.S
	check(absf(mbtn.position.x - want_bx) < 0.5, "安全区·模式盘右缘内缩")
	hud.set_safe_insets_override(Vector4(-1.0, -1.0, -1.0, -1.0))
	await process_frame
	cmp_rect(hud.hit_regions()[0], Rect2(0, 0, 1280, 64), "安全区复位·顶栏条")

	# ---- 汇总 ----
	finish("HUD", 34)


# ---------------- 辅助 ----------------

func _check_btn_color(hud, key: String, active: bool, label: String) -> void:
	var btn: Button = hud.mode_buttons[key]
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") # v2.3：读 effective 样式盒（变体解析）
	var want: Color = hud.DARK["active"] if active else hud.DARK["btn"]
	check(sb.bg_color.is_equal_approx(want), label)


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
