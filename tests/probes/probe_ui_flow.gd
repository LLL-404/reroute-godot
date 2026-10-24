extends ProbeKit

# C5 判定：三屏流转全链（窗口模式运行）。
# 链路：标题(启动态) →「开始对局」→ 对局 → HUD「暂停」→ 暂停 → ESC → 对局
#      → ESC → 暂停 →「继续」→ 对局 → ESC →「重开本局」→ 对局(新局)
#      → 手动终局(胜) → 结算 → ESC 不响应 → 「回标题」→ 标题 → ESC 不响应
#      →「开始对局」→ 对局 → 手动终局(负) → 结算(负) →「再来一局」→ 对局
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_ui_flow.gd
# 判定：exit 0 + stdout 含 `[UI_FLOW] PASS`。


func _initialize() -> void:
	var packed: PackedScene = load("res://game/app/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame # -s 模式：_ready 在首帧才跑；set_process 须在 ready 之后调用才粘
	main.set_process(false) # 探针独占推进
	var shell = main.shell
	var hud = main.hud

	# ---- 1. 启动态：标题屏压着静态战场 ----
	check(shell.current_page() == "title", "启动即标题")
	check(main.paused == true, "标题时暂停态")
	check(hud.top_bar.visible == false, "标题时 HUD 隐藏")
	var page_title: Control = shell.pages["title"]
	check(page_title != null and page_title.visible, "标题页可见")
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://shots/title.png")

	# ---- 2. 开始对局 ----
	var old_world = main.world
	var run0: int = main.run_index
	await _click_btn(page_title, "BtnStart")
	check(shell.current_page() == "", "开战后空屏态")
	check(main.paused == false, "开战后运行态")
	check(hud.top_bar.visible == true, "开战后 HUD 显示")
	check(page_title.visible == false, "标题页已关")

	# ---- 3. 手动推进时间（模拟帧）----
	var t0: int = main.world.tick_count
	for _i in 3:
		main._process(0.2)
	check(main.world.tick_count > t0, "对局推进 tick（%d → %d）" % [t0, main.world.tick_count])

	# ---- 4. HUD「暂停」按钮 → 暂停屏 ----
	await _click_ctl(hud.pause_btn)
	check(shell.current_page() == "pause", "HUD 暂停钮 → 暂停屏")
	check(main.paused == true, "暂停态")
	check(hud.top_bar.visible == true, "暂停时 HUD 保留")
	var page_pause: Control = shell.pages["pause"]
	check(page_pause != null and page_pause.visible, "暂停页可见")

	# ---- 5. ESC → 继续（handle_key 路径）----
	await _press_esc()
	check(shell.current_page() == "", "ESC 从暂停恢复")
	check(main.paused == false, "恢复运行态")
	check(page_pause.visible == false, "暂停页已关")

	# ---- 6. ESC → 暂停；「继续」按钮 → 恢复 ----
	await _press_esc()
	check(shell.current_page() == "pause", "ESC 进暂停")
	await _click_btn(page_pause, "BtnResume")
	check(shell.current_page() == "" and main.paused == false, "「继续」按钮恢复")

	# ---- 7. ESC → 暂停；「重开本局」→ 对局(新局) ----
	await _press_esc()
	var run1: int = main.run_index
	await _click_btn(page_pause, "BtnRestart")
	check(shell.current_page() == "" and main.paused == false, "重开后回对局")
	cmp_int(main.run_index, run1 + 1, "重开 run_index+1")
	check(main.world != old_world, "重开换新世界")
	check(main.world.supply == 300, "新局供给复位 300")

	# ---- 8. 手动终局（胜）→ 结算屏 ----
	var w = main.world
	var sup0: int = w.supply
	w.supply = 250
	main.over_shown = false
	w.outcome = World.WON
	main._process(0.05)
	check(shell.current_page() == "gameover", "终局 → 结算屏")
	check(hud.top_bar.visible == false, "结算时 HUD 隐藏")
	var page_go: Control = shell.pages["gameover"]
	check(page_go != null and page_go.visible, "结算页可见")
	check(shell.go_title.text == "防线守住了！", "胜利标题（得 " + shell.go_title.text + "）")
	check(shell.go_title.get_theme_color("font_color").is_equal_approx(hud.DARK["hp"]), "胜利标题色=青")
	check(shell.go_body.text.begins_with("坚持 ") and shell.go_body.text.contains("绕行赏金"), "结算统计文案（得 " + shell.go_body.text + "）")
	for _i in 20:
		await process_frame # 等入场淡入完成（0.18s）
	root.get_texture().get_image().save_png("res://shots/gameover.png")
	w.supply = sup0

	# ---- 9. 结算屏 ESC 不响应 ----
	await _press_esc()
	check(shell.current_page() == "gameover", "结算屏 ESC 不响应")

	# ---- 10.「回标题」→ 标题 ----
	var run2: int = main.run_index
	var core = main.view.core
	var std_focus: Vector3 = core.focus # 回标题前（对局内）标准取景值
	var std_dist: float = core._dist
	var seed_before: int = main.sc.seed
	# 人为打乱视角：回标题必须强制复位到标准取景，而不是保留玩家视角
	core.yaw = 0.7
	core._zoom = 1.5
	core.focus = Vector3(20.0, 0.0, 20.0)
	core._apply_cam()
	await _click_btn(page_go, "BtnToTitle2")
	check(shell.current_page() == "title", "回标题")
	check(main.paused == true and hud.top_bar.visible == false, "标题态复位")
	cmp_int(main.run_index, run2 + 1, "回标题备新局 run_index+1")
	check(core.yaw == 0.0, "回标题 yaw 复位 0（得 %.3f）" % core.yaw)
	check(core._zoom == 1.0, "回标题 zoom 复位 1（得 %.3f）" % core._zoom)
	check(core.focus.distance_to(std_focus) < 0.01, "回标题 focus 回到标准取景（%s → %s）" % [str(std_focus), str(core.focus)])
	check(absf(core._dist - std_dist) < 0.01, "回标题 _dist 回到标准取景（%.3f → %.3f）" % [std_dist, core._dist])
	check(main.sc.seed != seed_before, "回标题背景地图随局号轮换（seed %d → %d）" % [seed_before, main.sc.seed])

	# ---- 11. 标题屏 ESC 不响应 ----
	await _press_esc()
	check(shell.current_page() == "title", "标题屏 ESC 不响应")

	# ---- 12. 再开一局 → 终局（负）→ 结算 ----
	await _click_btn(page_title, "BtnStart")
	check(shell.current_page() == "" and main.paused == false, "二次开战")
	w = main.world
	main.over_shown = false
	w.outcome = World.LOST
	main._process(0.05)
	check(shell.current_page() == "gameover", "失败 → 结算屏")
	check(shell.go_title.text == "防线失守", "失败标题（得 " + shell.go_title.text + "）")
	check(shell.go_title.get_theme_color("font_color").is_equal_approx(hud.DARK["danger"]), "失败标题色=红")

	# ---- 13.「再来一局」→ 对局 ----
	var run3: int = main.run_index
	await _click_btn(page_go, "BtnAgain")
	check(shell.current_page() == "" and main.paused == false, "再来一局回对局")
	cmp_int(main.run_index, run3 + 1, "再来一局 run_index+1")

	# ---- 汇总 ----
	finish("UI_FLOW", 25)


# ---------------- 注入辅助 ----------------

func _click_ctl(ctl: Control) -> void:
	var center: Vector2 = ctl.global_position + ctl.size * 0.5
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
	await process_frame # 让页面切换/布局稳定


func _click_btn(page: Control, btn_name: String) -> void:
	var b := page.find_child(btn_name, true, false)
	if b == null:
		check(false, "按钮缺失：" + btn_name)
		return
	await _click_ctl(b)


func _press_esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	get_root().push_input(ev)
	await process_frame
	await process_frame
