extends ProbeKit

# 触屏可点闸（窗口模式运行）：合成 InputEventScreenTouch 驱动关键按钮（依赖
# 桌面默认的 emulate_mouse_from_touch 换算），并静态扫描各页面按钮的
# custom_minimum_size 触达下限（高 ≥36px/宽 ≥58px @S=1，手指可点）。
# 链路：标题触屏开始 → HUD 暂停钮 → 触屏继续 → 再暂停 → 触屏重开 → 全页按钮尺寸矩阵。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_touch.gd
# 判定：exit 0 + stdout 含 `[TOUCH] PASS`。

var _S := 1.0


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.set_process(false)
	var shell = main.shell
	var hud = main.hud
	_S = shell.S
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
				continue # 全屏开关是行内小控件，不参与按钮矩阵
			total += 1
			var btn: Button = b
			check(btn.custom_minimum_size.y >= min_h and btn.custom_minimum_size.x >= min_w,
				"按钮 %s/%s 触达尺寸 %.0fx%.0f" % [key, btn.name, btn.custom_minimum_size.x, btn.custom_minimum_size.y])
	for b in shell.confirm_layer.find_children("", "Button", true, false):
		total += 1
		var btn: Button = b
		check(btn.custom_minimum_size.y >= min_h and btn.custom_minimum_size.x >= min_w,
			"按钮 confirm/%s 触达尺寸 %.0fx%.0f" % [btn.name, btn.custom_minimum_size.x, btn.custom_minimum_size.y])
	cmp_int(total, 22, "按钮矩阵总数（5+5+2+7+1+2）")

	finish("TOUCH", 26)


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
