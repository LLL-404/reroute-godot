extends ProbeKit

# 新手引导闸（窗口模式运行，specs/onboarding-spec §5）：四步 FO 依次推进、点击跳过、
# 二局不触发、战绩卡三数落盘与展示。
# 链路：override=1 强开 → FO-0（PORT：出怪口高亮+提示）→ 点击跳到 WALL → 真实放墙
#      → FOLLOW → 快进推进波次至首单位走满 5 格/清场 → ECON → 4s → DONE；
#      override=0 再开一局 → NONE；_persist_stats(true) → 落盘 + 标题页三数展示。
# 读档不触发由实现保证（load_game 首行显式置 NONE），不在本闸展开。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_onboarding.gd
# 判定：exit 0 + stdout 含 `[ONBOARD] PASS`。

const MainScene := preload("res://game/app/main.tscn")
const UserSettings = preload("res://game/core/user_settings.gd")


func _initialize() -> void:
	print("[ONBOARD] begin")
	var main = MainScene.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame
	main.set_process(false)
	var shell = main.shell
	var hud = main.hud

	# ---- 1. FO-0：override 强开首局引导 ----
	main._onboard_override = 1
	main.start_match()
	check(main._onboard == main.OnboardStage.PORT, "FO-0 强开即 PORT")
	check(main._fo_port_cell.x >= 0 and main._fo_port_cell.y >= 0, "FO-0 出怪口已取（%s）" % main._fo_port_cell)
	check(main._fo_wall_cell.x >= 0, "FO-1 推荐格已备（%s）" % main._fo_wall_cell)
	check(hud.hint_label != null, "提示徽章面板存在")

	# ---- 2. 点击跳过 → WALL；真实放墙 → FOLLOW ----
	main._onboard_click()
	check(main._onboard == main.OnboardStage.WALL, "点击跳过 FO-0 → WALL")
	var wc: Vector2i = main._fo_wall_cell
	main.apply_mode_at("wall", wc.x, wc.y)
	check(main._onboard == main.OnboardStage.FOLLOW, "真实放墙 → FOLLOW")
	check(main.world.building_at(wc.x, wc.y) != null, "推荐格放墙确实生效")

	# ---- 3. 快进推进：首单位走满 5 格或清场 → ECON → 4s → DONE ----
	main.set_process(true)
	var guard := 0
	while main._onboard == main.OnboardStage.FOLLOW and guard < 2400:
		main._process(0.25) # 大步快进：模拟推进 + FO 每帧驱动同路
		await process_frame
		guard += 1
	check(main._onboard == main.OnboardStage.ECON or main._onboard == main.OnboardStage.DONE,
		"FO-2 随波次推进落到 ECON/DONE（guard=%d）" % guard)
	guard = 0
	while main._onboard == main.OnboardStage.ECON and guard < 60:
		main._process(0.25)
		await process_frame
		guard += 1
	check(main._onboard == main.OnboardStage.DONE, "FO-3 4s 自完成 → DONE")

	# ---- 4. 二局不触发（override=0 = 模拟非首局）----
	main._onboard_override = 0
	main.start_match()
	check(main._onboard == main.OnboardStage.NONE, "二局引导不触发")

	# ---- 5. 战绩卡：落盘 → 标题展示（生产写入口 _persist_stats 带探针守卫，
	#      其调用位点在 _check_outcome 两分支；这里走同构的手动 _settings+save 对拍）----
	main._settings["wins"] = int(main._settings.get("wins", 0)) + 1
	main._settings["best_wave"] = maxi(int(main._settings.get("best_wave", 0)), 1)
	UserSettings.save_cfg(main._settings)
	check(int(UserSettings.load_cfg().get("wins", 0)) == int(main._settings["wins"]), "胜场落盘往返一致")
	main.to_title()
	check(shell.current_page() == "title", "回标题")
	var lr: Label = shell.pages["title"].get_node("Col/StatsRow/LblRuns")
	var lb: Label = shell.pages["title"].get_node("Col/StatsRow/LblBest")
	var lw: Label = shell.pages["title"].get_node("Col/StatsRow/LblWins")
	check(lr.text.begins_with("局数 "), "战绩卡·局数行（%s）" % lr.text)
	check(int(lb.text.substr(5)) >= 1, "战绩卡·最佳波次行（%s）" % lb.text)
	check(int(lw.text.substr(3)) >= 1, "战绩卡·胜场行（%s）" % lw.text)

	finish("[ONBOARD]")
