extends ProbeKit

# R9 全局冒烟（C9）：完整一局「标题 → 开战 → 真实主循环推进 → 收口 → 结算屏 →
# 终局冻结 → 干净退出」全程，窗口模式运行（真实渲染 + 真实音频路径）。
#
# 驱动口径：显式调 main._process(0.5)（set_process(false) 后引擎不再自动驱动），
# 每次调用按 20Hz 累积器与 MAX_CATCHUP=5 语义推进 5 tick；每渲染帧 4 次调用
# = 20 tick/帧，MAX_FRAMES 帧内跑完全程（含 8800 tick 硬上限兜底）。
#
# 最小防御：模拟玩家的底线操作——固定塔位（核心南侧主通道）+ 有钱即布，
# 保证对局覆盖击杀链（塔火/死亡消散/赏金浮动）与更深的波次表；塔位与节奏
# 全固定，种子固定 → 全程确定。
#
# 判定：exit 0 + `[SMOKE] PASS`；stderr 无 ERROR（外层校验）。
# 证据：全程统计（收口 tick/结局/峰值单位数/抽样对拍）+ shots/smoke_mid.png +
# shots/smoke_end.png。

const MAX_FRAMES := 700 # 14000 tick 预算（一局硬上限 8800）
const TOWER_COST := 60
## 塔位候选（核心南侧主通道，自西向东自近及远）；非法点自动跳过。
const TOWER_SPOTS := [
	Vector2i(32, 9),
	Vector2i(32, 12),
	Vector2i(30, 12),
	Vector2i(34, 12),
	Vector2i(29, 10),
	Vector2i(35, 10),
]

var tower_cursor := 0
var towers_placed := 0
var last_skill_tick := -99999
var skills_cast := 0


## 最小防御：有钱即按固定序列布塔（扣费成功=放置成功；非法点跳过不重试）。
func _defend(world) -> void:
	while tower_cursor < TOWER_SPOTS.size() and world.supply >= TOWER_COST:
		var spot: Vector2i = TOWER_SPOTS[tower_cursor]
		tower_cursor += 1
		var sup_before: int = world.supply
		world.apply_command({ "kind": "tower", "x": spot.x, "y": spot.y })
		if world.supply < sup_before:
			towers_placed += 1


## 最小防御：英雄技能（震荡波），每 500 tick 一次且仅在半径内有敌时施放
## （保证技能链覆盖到真实击退效果；冷却 400，真实玩家节奏）。
func _cast_skill(world) -> void:
	if world.tick_count - last_skill_tick < 500:
		return
	if int(world.hero["skill_cd"]) != 0:
		return
	var has_target := false
	for u in world.units:
		if int(u["hp"]) <= 0:
			continue
		var dx: int = int(u["x"]) - int(world.hero["x"])
		var dy: int = int(u["y"]) - int(world.hero["y"])
		if dx * dx + dy * dy > 0 and dx * dx + dy * dy <= 9:
			has_target = true
			break
	if not has_target:
		return
	world.apply_command({ "kind": "shock" })
	last_skill_tick = world.tick_count
	skills_cast += 1


func _initialize() -> void:
	var scene: PackedScene = load("res://game/main.tscn")
	var main = scene.instantiate()
	get_root().add_child(main)
	for _i in 3:
		await process_frame # 时序铁律：-s 模式 _ready 首帧才跑
	main.set_process(false) # 探针独占驱动

	var w = main.world
	var view = main.view
	print("[SMOKE] run=", main.run_index, " seed=", 20261003 + main.run_index)

	# ---- 1. 启动态：标题屏压着静态战场 ----
	check(main.shell.current_page() == "title", "启动即标题屏")
	cmp_int(w.tick_count, 0, "tick 从 0 起")
	check(w.outcome == World.RUNNING, "开局 RUNNING")
	check(main.paused == true, "标题态暂停")
	check(main.hud.top_bar.visible == false, "标题时 HUD 隐藏")
	cmp_int(int(w.core["hp"]), 1200, "核心满血 1200")

	# ---- 2. 开战 ----
	main.start_match()
	check(main.shell.current_page() == "", "进入对局（页栈空）")
	check(main.paused == false, "对局启动")
	check(main.hud.top_bar.visible == true, "HUD 显示")
	check(view.bgm_on == true, "BGM 开")

	# ---- 3. 真实主循环推进至收口 ----
	var frames := 0
	var samples := 0
	var unit_mismatch := 0
	var stalled := 0
	var monotonic := true
	var last_tick := 0
	var peak_units := 0
	var peak_kills := 0
	var mid_shot := false
	_defend(w) # 开局布防第一轮（300 供给 → 首批塔）
	while w.outcome == World.RUNNING and frames < MAX_FRAMES:
		var t_before: int = w.tick_count
		for _i in 4:
			main._process(0.5)
		frames += 1
		_defend(w) # 赏金进账即续塔（终局后 world.apply_command 自动空转）
		_cast_skill(w) # 英雄技能链（终局后自动空转）
		if w.tick_count < last_tick:
			monotonic = false
		last_tick = w.tick_count
		if w.tick_count == t_before:
			stalled += 1
		if w.units.size() > peak_units:
			peak_units = w.units.size()
		if w.kills > peak_kills:
			peak_kills = w.kills
		if frames % 10 == 0: # 每 ~200 tick 抽样对拍：视图节点数 == 世界活体数
			samples += 1
			var alive := 0
			for u in w.units:
				if int(u["hp"]) > 0:
					alive += 1
			var st: Dictionary = view.debug_stats()
			if int(st["units"]) != alive:
				unit_mismatch += 1
		if not mid_shot and w.tick_count >= 800: # 中场证据图（大战中）
			mid_shot = true
			await process_frame
			get_root().get_texture().get_image().save_png("res://shots/smoke_mid.png")
		if frames % 25 == 0:
			await process_frame # 渲染帧 + 消息泵

	# ---- 4. 收口断言 ----
	check(w.outcome != World.RUNNING, "一局跑至收口（outcome=%d）" % w.outcome)
	check(w.outcome == World.WON or w.outcome == World.LOST, "收口为终局三态之一")
	var end_tick: int = w.tick_count
	var end_kills: int = w.kills
	var end_supply: int = w.supply
	check(end_tick > 0 and end_tick <= 8800, "收口 tick 在 (0,8800]（得 %d）" % end_tick)
	check(frames < MAX_FRAMES, "推进帧数在预算内（%d/%d）" % [frames, MAX_FRAMES])

	# ---- 5. 结算闸与结算屏（main._process 终局分支）----
	main._process(0.5)
	check(main.over_shown == true, "结算闸触发")
	check(main.shell.current_page() == "gameover", "结算屏打开")
	check(main.hud.top_bar.visible == false, "结算时 HUD 隐藏")
	var won: bool = (w.outcome == World.WON)
	var want_title: String = "防线守住了！" if won else "防线失守"
	check(main.shell.go_title.text == want_title, "结算标题（得 %s）" % main.shell.go_title.text)
	check(main.shell.go_body.text.length() > 0, "结算统计非空")

	# ---- 6. 终局冻结：世界零副作用 ----
	for _i in 30:
		main._process(0.5)
	cmp_int(w.tick_count, end_tick, "终局冻结：tick 不再推进")
	cmp_int(w.kills, end_kills, "终局冻结：击杀数不变")
	cmp_int(w.supply, end_supply, "终局冻结：供给不变")

	# ---- 7. 冻结后视图/世界一致性 + 收尾截图 ----
	var alive_end := 0
	for u2 in w.units:
		if int(u2["hp"]) > 0:
			alive_end += 1
	cmp_int(int(view.debug_stats()["units"]), alive_end, "冻结后视图单位数与世界一致")
	for _i in 40:
		await process_frame # 等结算屏淡入完成（0.18s）
	get_root().get_texture().get_image().save_png("res://shots/smoke_end.png")

	# ---- 8. 全程统计 ----
	check(monotonic, "tick 单调增")
	check(stalled == 0, "推进永不卡死（stalled=%d）" % stalled)
	check(unit_mismatch == 0, "抽样对拍视图/世界单位数一致（%d 次采样）" % samples)
	check(peak_units > 0, "场上出现过敌人（峰值 %d）" % peak_units)
	check(mid_shot, "中场证据图已存")
	check(towers_placed >= 3, "最小防御布塔（%d 座）" % towers_placed)
	check(peak_kills > 0, "击杀链发生过（峰值击破 %d）" % peak_kills)
	check(skills_cast >= 1, "英雄技能链（震荡波有效施放 %d 次）" % skills_cast)
	print("[SMOKE] outcome=", ("WON" if won else "LOST"), " tick=", end_tick,
		" kills=", end_kills, " supply=", end_supply,
		" peak_units=", peak_units, " peak_kills=", peak_kills,
		" towers=", towers_placed, " skills=", skills_cast)
	print("[SMOKE] frames=", frames, " samples=", samples, " mismatch=", unit_mismatch)

	# ---- 9. 干净退出（R8 口径：停全音频 + 等混音回收）+ 收口 ----
	view.stop_all_audio()
	await create_timer(0.5).timeout
	finish("SMOKE", 20)
