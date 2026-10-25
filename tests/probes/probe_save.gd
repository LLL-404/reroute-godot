extends ProbeKit

# 存档/设置/退出/安卓返回 判定闸（窗口模式运行）。
# 链路：清场归一 → 标题禁用态 → 开局 → 暂停 → 保存(空槽/覆盖确认/取消) → 回标题
#      → 「继续对局」启用 → 读档(列表/空槽无响应/恢复 tick·run·供给·实体) → 再存替换
#      → 删除(确认/取消) → 损坏档(拒载+可删) → 设置(音量落盘+bus dB/全屏开合/ESC 回退)
#      → 退出确认(取消/spy 确定) → 安卓返回路由(标题/对局/暂停/动作事件/去抖/结算)
#      → 清场还原。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_save.gd
# 判定：exit 0 + stdout 含 `[SAVE] PASS`。

const SaveIO = preload("res://game/core/save_io.gd")
const UserSettings = preload("res://game/core/user_settings.gd")


func _initialize() -> void:
	_clean_slots()
	var orig_cfg := UserSettings.load_cfg()
	UserSettings.save_cfg(UserSettings.default_cfg())
	UserSettings.apply_all(UserSettings.default_cfg())

	var packed: PackedScene = load("res://game/app/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.set_process(false)
	var shell = main.shell
	var hud = main.hud
	var page_title: Control = shell.pages["title"]

	# ---- A. 接线与初始态 ----
	check(shell.cb.has("quit") and shell.cb.has("load_slot") and shell.cb.has("save_slot"), "壳回调接线齐（quit/load_slot/save_slot）")
	var btn_continue: Button = page_title.find_child("BtnContinue", true, false)
	check(btn_continue != null and btn_continue.disabled, "无存档时「继续对局」禁用")

	# ---- B. 开局 → 暂停 → 保存 ----
	await _click_btn(page_title, "BtnStart")
	check(shell.current_page() == "" and main.paused == false, "开战运行态")
	for _i in 3:
		main._process(0.2)
	var tick0: int = main.world.tick_count
	var sup0: int = main.world.supply
	var units0: int = main.world.units.size()
	var run_saved: int = main.run_index
	check(tick0 > 0, "对局已推进 tick=%d" % tick0)
	await _press_esc()
	check(shell.current_page() == "pause", "ESC 进暂停")
	var page_pause: Control = shell.pages["pause"]
	await _click_btn(page_pause, "BtnSave")
	check(shell.current_page() == "slots" and shell.slots_mode == "save", "「保存进度」→ 存档页(save)")
	var page_slots: Control = shell.pages["slots"]
	var del1: Button = page_slots.find_child("BtnSlotDel1", true, false)
	check(not del1.visible, "save 模式隐藏删除钮")
	check(_row_text(shell, 1).contains("空"), "槽 1 初始为空（%s）" % _row_text(shell, 1))
	await _click_btn(page_slots, "BtnSlot1")
	check(FileAccess.file_exists(SaveIO.slot_path(1)), "空槽点击直存（文件落盘）")
	check(_status(shell) == "已保存到槽 1", "存后状态文案（%s）" % _status(shell))
	check(_row_text(shell, 1).contains("槽 1") and _row_text(shell, 1).contains("开局"), "槽 1 行文案（%s）" % _row_text(shell, 1))
	cmp_int(int(SaveIO.slot_meta(1).get("tick", -1)), tick0, "存档 meta.tick == 暂停时 tick")

	# ---- C. 覆盖确认（取消不落盘 / 确定重写） ----
	await _click_btn(page_slots, "BtnSlot1")
	check(shell.confirm_open(), "占用槽再存 → 弹覆盖确认")
	check(shell.confirm_text.text.contains("覆盖"), "确认文案含「覆盖」（%s）" % shell.confirm_text.text)
	await _click_btn(shell.confirm_layer, "BtnConfirmCancel")
	check(not shell.confirm_open(), "取消关闭弹窗")
	check(SaveIO.slot_info(1).get("ok", false), "取消后旧档仍在")
	await _click_btn(page_slots, "BtnSlot1")
	check(shell.confirm_open(), "再次点击 → 确认再弹")
	await _click_btn(shell.confirm_layer, "BtnConfirmOk")
	check(not shell.confirm_open() and _status(shell) == "已保存到槽 1", "确定覆盖 → 保存成功")

	# ---- D. 回标题 → 继续对局 → 读档 ----
	await _click_btn(page_slots, "BtnSlotsBack")
	check(shell.current_page() == "pause", "存档页「返回」→ 暂停（from）")
	await _click_btn(page_pause, "BtnToTitle")
	check(shell.current_page() == "title", "暂停「回标题」")
	check(not btn_continue.disabled, "有档 → 「继续对局」启用")
	await _click_btn(page_title, "BtnContinue")
	check(shell.current_page() == "slots" and shell.slots_mode == "load", "「继续对局」→ 读档页(load)")
	check(del1.visible, "load 模式显示删除钮")
	check(_row_text(shell, 1).contains("开局"), "槽 1 行含阶段（%s）" % _row_text(shell, 1))
	for _i in 20:
		await process_frame # 等淡入完成
	root.get_texture().get_image().save_png("res://shots/slots.png")
	await _click_btn(page_slots, "BtnSlot2")
	check(shell.current_page() == "slots", "空槽在 load 模式无响应")
	await _click_btn(page_slots, "BtnSlot1")
	check(shell.current_page() == "" and main.paused == false, "读档成功 → 直接进对局")
	cmp_int(main.world.tick_count, tick0, "读档恢复 tick")
	cmp_int(main.run_index, run_saved, "读档恢复 run_index")
	cmp_int(main.world.supply, sup0, "读档恢复供给")
	cmp_int(main.world.units.size(), units0, "读档恢复实体数")
	check(hud.top_bar.visible, "读档后 HUD 可见")

	# ---- E. 再存（覆盖为新 tick）→ 删除（取消/确认）----
	for _i in 2:
		main._process(0.2)
	var tick2: int = main.world.tick_count
	check(tick2 > tick0, "续跑推进 tick（%d → %d）" % [tick0, tick2])
	await _press_esc()
	await _click_btn(page_pause, "BtnSave")
	await _click_btn(page_slots, "BtnSlot1")
	await _click_btn(shell.confirm_layer, "BtnConfirmOk")
	cmp_int(int(SaveIO.slot_meta(1).get("tick", -1)), tick2, "覆盖存新进度（meta.tick）")
	await _click_btn(page_slots, "BtnSlotsBack")
	await _click_btn(page_pause, "BtnToTitle")
	await _click_btn(page_title, "BtnContinue")
	await _click_btn(page_slots, "BtnSlotDel1")
	check(shell.confirm_open() and shell.confirm_text.text.contains("删除"), "删除 → 确认文案（%s）" % shell.confirm_text.text)
	await _click_btn(shell.confirm_layer, "BtnConfirmCancel")
	check(FileAccess.file_exists(SaveIO.slot_path(1)), "取消删除后文件仍在")
	await _click_btn(page_slots, "BtnSlotDel1")
	await _click_btn(shell.confirm_layer, "BtnConfirmOk")
	check(SaveIO.slot_info(1).get("empty", false), "确定删除 → 槽 1 空")
	check(_row_text(shell, 1).contains("空"), "删除后行文案（%s）" % _row_text(shell, 1))
	check(_status(shell) == "已删除槽 1", "删除状态文案（%s）" % _status(shell))
	await _click_btn(page_slots, "BtnSlotsBack")
	check(shell.current_page() == "title" and btn_continue.disabled, "全空 → 返回标题且「继续对局」禁用")

	# ---- F. 损坏档：计入非空可进列表，点选拒载可删 ----
	_write_corrupt(2)
	shell.open_title() # 刷「继续对局」态
	check(not btn_continue.disabled, "损坏档也算非空 → 继续启用")
	await _click_btn(page_title, "BtnContinue")
	check(_row_text(shell, 2).contains("损坏"), "损坏槽行文案（%s）" % _row_text(shell, 2))
	await _click_btn(page_slots, "BtnSlot2")
	check(shell.current_page() == "slots", "损坏档点选不读档")
	check(_status(shell) == "存档损坏", "损坏档状态文案（%s）" % _status(shell))
	await _click_btn(page_slots, "BtnSlotDel2")
	await _click_btn(shell.confirm_layer, "BtnConfirmOk")
	check(_row_text(shell, 2).contains("空"), "损坏档可删除（行：%s）" % _row_text(shell, 2))
	await _click_btn(page_slots, "BtnSlotsBack")
	check(shell.current_page() == "title" and btn_continue.disabled, "清空后返回标题禁用")

	# ---- G. 设置：音量落盘/bus/全屏/ESC 回退 ----
	await _click_btn(page_title, "BtnSettings")
	check(shell.current_page() == "settings", "标题「设置」→ 设置页")
	var page_set: Control = shell.pages["settings"]
	var sld_music: HSlider = page_set.find_child("SldMusic", true, false)
	var sld_sfx: HSlider = page_set.find_child("SldSfx", true, false)
	var lbl_music: Label = page_set.find_child("LblMusicVal", true, false)
	var sld_render: HSlider = page_set.find_child("SldRenderPct", true, false)
	var sld_ui: HSlider = page_set.find_child("SldUiPct", true, false)
	var sld_bright: HSlider = page_set.find_child("SldBrightPct", true, false)
	cmp_approx(sld_music.value, 100.0, "默认音乐音量 100")
	check(lbl_music.text == "100", "音量读数标签（%s）" % lbl_music.text)
	cmp_approx(sld_render.value, 100.0, "默认渲染缩放 100")
	cmp_approx(sld_ui.value, 100.0, "默认 UI 缩放 100")
	cmp_approx(sld_bright.value, 100.0, "默认画面亮度 100")
	sld_music.value = 40.0
	check(int(UserSettings.load_cfg()["music"]) == 40, "拖动音乐滑杆即落盘")
	var bgm_idx := AudioServer.get_bus_index("BGM")
	check(bgm_idx >= 0, "BGM bus 存在")
	cmp_approx(AudioServer.get_bus_volume_db(bgm_idx), linear_to_db(0.4), "BGM bus dB=linear(0.4)")
	check(lbl_music.text == "40", "音乐读数跟进（%s）" % lbl_music.text)
	sld_sfx.value = 0.0
	cmp_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), -80.0, "SFX bus 0 → 静音 -80dB")
	check(int(UserSettings.load_cfg()["sfx"]) == 0, "音效 0 落盘")
	await _click_btn(page_set, "BtnDisplayMode1")
	check(int(UserSettings.load_cfg()["display_mode"]) == 1, "无边框显示模式落盘")
	await _click_btn(page_set, "BtnDisplayMode0")
	check(int(UserSettings.load_cfg()["display_mode"]) == 0, "窗口化显示模式落盘")
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "显示模式回窗口化")
	var chk_shake: CheckButton = page_set.find_child("ChkShake", true, false)
	check(chk_shake != null and chk_shake.button_pressed == true, "震屏默认开（mobile-ux §4）")
	chk_shake.button_pressed = false
	check(bool(UserSettings.load_cfg()["screen_shake"]) == false, "关震屏即落盘")
	check(main.view.core.shake_on == false, "关震屏 → 视图层接线关闭")
	chk_shake.button_pressed = true
	check(main.view.core.shake_on == false, "重开震屏但探针环境豁免优先（截图口径优先于玩家开关）")
	for _i in 20:
		await process_frame
	root.get_texture().get_image().save_png("res://shots/settings.png")
	await _press_esc()
	check(shell.current_page() == "title", "设置 ESC → 回标题（from）")

	# ---- H. 退出确认（取消 / spy 确定） ----
	await _click_btn(page_title, "BtnQuit")
	check(shell.confirm_open(), "「退出游戏」→ 确认弹窗")
	check(shell.confirm_text.text.contains("退出"), "退出确认文案（%s）" % shell.confirm_text.text)
	await _press_esc()
	check(not shell.confirm_open() and shell.current_page() == "title", "ESC 取消退出确认")
	await _click_btn(page_title, "BtnQuit")
	var called := [false]
	var old_quit: Callable = shell.cb["quit"]
	shell.cb["quit"] = func() -> void: called[0] = true # spy：防真退
	await _click_btn(shell.confirm_layer, "BtnConfirmOk")
	check(called[0], "「确定」触发 quit 回调")
	shell.cb["quit"] = old_quit

	# ---- I. 安卓返回路由 ----
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.confirm_open(), "返回键@标题 → 退出确认")
	shell.close_confirm()
	await _click_btn(page_title, "BtnStart")
	check(shell.current_page() == "" and main.paused == false, "再次开战")
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.current_page() == "pause", "返回键@对局 → 暂停")
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.current_page() == "" and main.paused == false, "返回键@暂停 → 继续")
	main._notification(main.NOTIFICATION_APPLICATION_PAUSED)
	check(main.paused == true and shell.current_page() == "pause", "失焦自动暂停（mobile-ux §3 模拟通知）")
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.current_page() == "" and main.paused == false, "失焦暂停后返回键 → 继续")
	main._last_back_ms = 0
	var act := InputEventAction.new()
	act.action = &"ui_cancel"
	act.pressed = true
	get_root().push_input(act)
	await process_frame
	await process_frame
	check(shell.current_page() == "pause", "ui_cancel 动作事件 → 暂停（动作形态入口）")
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.current_page() == "", "返回继续")
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.current_page() == "pause", "返回暂停（去抖前）")
	main._android_back_handle()
	check(shell.current_page() == "pause", "80ms 内重复返回被去抖")
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.current_page() == "", "去抖窗口过后正常处理")
	var w = main.world
	main.over_shown = false
	w.outcome = World.WON
	main._process(0.05)
	check(shell.current_page() == "gameover", "手动终局 → 结算")
	main._last_back_ms = 0
	main._android_back_handle()
	check(shell.current_page() == "title", "返回键@结算 → 回标题")

	# ---- J. 清场还原 ----
	_clean_slots()
	check(not SaveIO.has_any(), "清场后无残留槽位")
	UserSettings.save_cfg(orig_cfg)
	UserSettings.apply_all(orig_cfg)

	finish("SAVE", 77)


# ---------------- 辅助 ----------------

func _clean_slots() -> void:
	for i in range(1, SaveIO.SLOT_N + 1):
		SaveIO.delete_slot(i)


func _write_corrupt(slot: int) -> void:
	var f := FileAccess.open(SaveIO.slot_path(slot), FileAccess.WRITE)
	f.store_string("{broken json")
	f.close()


func _row_text(shell, slot: int) -> String:
	var b: Button = shell.pages["slots"].find_child("BtnSlot%d" % slot, true, false)
	return b.text if b != null else "<missing>"


func _status(shell) -> String:
	var l: Label = shell.pages["slots"].find_child("LabelSlotStatus", true, false)
	return l.text if l != null else "<missing>"


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
