extends SceneTree

# C5 判定：三屏流转全链（窗口模式运行）。
# 链路：标题(启动态) →「开始对局」→ 对局 → HUD「暂停」→ 暂停 → ESC → 对局
#      → ESC → 暂停 →「继续」→ 对局 → ESC →「重开本局」→ 对局(新局)
#      → 手动终局(胜) → 结算 → ESC 不响应 → 「回标题」→ 标题 → ESC 不响应
#      →「开始对局」→ 对局 → 手动终局(负) → 结算(负) →「再来一局」→ 对局
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_ui_flow.gd
var checks := 0
var bad := 0
var fail_list: Array = []


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame # -s 模式：_ready 在首帧才跑；set_process 须在 ready 之后调用才粘
	main.set_process(false) # 探针独占推进
	var shell = main.shell
	var hud = main.hud

	# ---- 1. 启动态：标题屏压着静态战场 ----
	_gcheck(shell.current_page() == "title", "启动即标题")
	_gcheck(main.paused == true, "标题时暂停态")
	_gcheck(hud.top_bar.visible == false, "标题时 HUD 隐藏")
	var page_title: Control = shell.pages["title"]
	_gcheck(page_title != null and page_title.visible, "标题页可见")
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://shots/title.png")

	# ---- 2. 开始对局 ----
	var old_world = main.world
	var run0: int = main.run_index
	await _click_btn(page_title, "btn_start")
	_gcheck(shell.current_page() == "", "开战后空屏态")
	_gcheck(main.paused == false, "开战后运行态")
	_gcheck(hud.top_bar.visible == true, "开战后 HUD 显示")
	_gcheck(page_title.visible == false, "标题页已关")

	# ---- 3. 手动推进时间（模拟帧）----
	var t0: int = main.world.tick_count
	for _i in 3:
		main._process(0.2)
	_gcheck(main.world.tick_count > t0, "对局推进 tick（%d → %d）" % [t0, main.world.tick_count])

	# ---- 4. HUD「暂停」按钮 → 暂停屏 ----
	await _click_ctl(hud.pause_btn)
	_gcheck(shell.current_page() == "pause", "HUD 暂停钮 → 暂停屏")
	_gcheck(main.paused == true, "暂停态")
	_gcheck(hud.top_bar.visible == true, "暂停时 HUD 保留")
	var page_pause: Control = shell.pages["pause"]
	_gcheck(page_pause != null and page_pause.visible, "暂停页可见")

	# ---- 5. ESC → 继续（handle_key 路径）----
	await _press_esc()
	_gcheck(shell.current_page() == "", "ESC 从暂停恢复")
	_gcheck(main.paused == false, "恢复运行态")
	_gcheck(page_pause.visible == false, "暂停页已关")

	# ---- 6. ESC → 暂停；「继续」按钮 → 恢复 ----
	await _press_esc()
	_gcheck(shell.current_page() == "pause", "ESC 进暂停")
	await _click_btn(page_pause, "btn_resume")
	_gcheck(shell.current_page() == "" and main.paused == false, "「继续」按钮恢复")

	# ---- 7. ESC → 暂停；「重开本局」→ 对局(新局) ----
	await _press_esc()
	var run1: int = main.run_index
	await _click_btn(page_pause, "btn_restart")
	_gcheck(shell.current_page() == "" and main.paused == false, "重开后回对局")
	_cmp_i(main.run_index, run1 + 1, "重开 run_index+1")
	_gcheck(main.world != old_world, "重开换新世界")
	_gcheck(main.world.supply == 300, "新局供给复位 300")

	# ---- 8. 手动终局（胜）→ 结算屏 ----
	var w = main.world
	var sup0: int = w.supply
	w.supply = 250
	main.over_shown = false
	w.outcome = World.WON
	main._process(0.05)
	_gcheck(shell.current_page() == "gameover", "终局 → 结算屏")
	_gcheck(hud.top_bar.visible == false, "结算时 HUD 隐藏")
	var page_go: Control = shell.pages["gameover"]
	_gcheck(page_go != null and page_go.visible, "结算页可见")
	_gcheck(shell.go_title.text == "防线守住了！", "胜利标题（得 " + shell.go_title.text + "）")
	_gcheck(shell.go_title.get_theme_color("font_color").is_equal_approx(hud.DARK["hp"]), "胜利标题色=青")
	_gcheck(shell.go_body.text.begins_with("坚持 ") and shell.go_body.text.contains("绕行赏金"), "结算统计文案（得 " + shell.go_body.text + "）")
	for _i in 20:
		await process_frame # 等入场淡入完成（0.18s）
	root.get_texture().get_image().save_png("res://shots/gameover.png")
	w.supply = sup0

	# ---- 9. 结算屏 ESC 不响应 ----
	await _press_esc()
	_gcheck(shell.current_page() == "gameover", "结算屏 ESC 不响应")

	# ---- 10.「回标题」→ 标题 ----
	var run2: int = main.run_index
	await _click_btn(page_go, "btn_to_title2")
	_gcheck(shell.current_page() == "title", "回标题")
	_gcheck(main.paused == true and hud.top_bar.visible == false, "标题态复位")
	_cmp_i(main.run_index, run2 + 1, "回标题备新局 run_index+1")

	# ---- 11. 标题屏 ESC 不响应 ----
	await _press_esc()
	_gcheck(shell.current_page() == "title", "标题屏 ESC 不响应")

	# ---- 12. 再开一局 → 终局（负）→ 结算 ----
	await _click_btn(page_title, "btn_start")
	_gcheck(shell.current_page() == "" and main.paused == false, "二次开战")
	w = main.world
	main.over_shown = false
	w.outcome = World.LOST
	main._process(0.05)
	_gcheck(shell.current_page() == "gameover", "失败 → 结算屏")
	_gcheck(shell.go_title.text == "防线失守", "失败标题（得 " + shell.go_title.text + "）")
	_gcheck(shell.go_title.get_theme_color("font_color").is_equal_approx(hud.DARK["danger"]), "失败标题色=红")

	# ---- 13.「再来一局」→ 对局 ----
	var run3: int = main.run_index
	await _click_btn(page_go, "btn_again")
	_gcheck(shell.current_page() == "" and main.paused == false, "再来一局回对局")
	_cmp_i(main.run_index, run3 + 1, "再来一局 run_index+1")

	# ---- 汇总 ----
	var ok := bad == 0 and checks >= 25
	print("[FLOW] checks=", checks, " bad=", bad)
	for i in mini(fail_list.size(), 12):
		print("[FLOW] fail: ", fail_list[i])
	print("[FLOW] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


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
		_fail("按钮缺失：" + btn_name)
		checks += 1
		return
	await _click_ctl(b)


func _press_esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	get_root().push_input(ev)
	await process_frame
	await process_frame


# ---------------- 判定辅助 ----------------

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
