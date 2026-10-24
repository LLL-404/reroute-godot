extends ProbeKit

# 世界种子入口判定闸（窗口模式运行）。
# 链路：探针旧口径 → 数字种子同图 → 换种子换图 → 文字种子 → 自动取种（随机/文字）
#      → 输入清洗 → 标题屏种子框 → 读档回显 → 肉鸽同通道 → 可用性判定。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_seed.gd
# 判定：exit 0 + stdout 含 `[SEED] PASS`。

const UserSettings = preload("res://game/core/user_settings.gd")
const SaveIO = preload("res://game/core/save_io.gd")
const TEST_SLOT := 9 # 专用测试槽（1..3 是玩家可见槽位，用 9 避免污染存档页）


func _initialize() -> void:
	SaveIO.delete_slot(TEST_SLOT) # 清掉上次异常退出可能留下的测试档
	var packed: PackedScene = load("res://game/app/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame # -s 模式：_ready 在首帧才跑；set_process 须在 ready 之后调用才粘
	main.set_process(false) # 探针独占推进
	main.start_match()
	var hud = main.hud

	# ---- A. 探针旧口径：种子仍 = BASE_SEED + 局号 ----
	main.run_index = 0
	main.new_game()
	cmp_int(int(main.world.sc.seed), main.BASE_SEED + 1, "探针口径 new_game() → BASE_SEED+1（得 %d）" % int(main.world.sc.seed))
	cmp_int(int(main.world.seed), main.BASE_SEED + 1, "world.seed 与旧口径一致")
	main.new_game()
	cmp_int(int(main.world.sc.seed), main.BASE_SEED + 2, "探针口径连开第二局 → BASE_SEED+2（得 %d）" % int(main.world.sc.seed))

	# ---- B. 数字种子：同种子同图 + HUD 文案 ----
	main.new_game(20261007)
	var fp7: int = main.sc.fingerprint(Canon.new())
	cmp_int(int(main.world.seed), 20261007, "指定种子 → world.seed=20261007")
	cmp_int(int(main.sc.seed), 20261007, "指定种子 → sc.seed=20261007")
	check(hud.seed_label.text == "种子 20261007", "HUD 种子文案（得 %s）" % hud.seed_label.text)
	main.new_game(20261007)
	cmp_int(main.sc.fingerprint(Canon.new()), fp7, "同数字种子两局剧本指纹一致（0x%08x）" % fp7)
	check(hud.seed_label.text == "种子 20261007", "第二局 HUD 种子仍为 20261007（得 %s）" % hud.seed_label.text)

	# ---- C. 换种子换图（20261008 若恰好同图则退到 20261009，实测未触发）----
	main.new_game(20261008)
	var fp8: int = main.sc.fingerprint(Canon.new())
	if fp8 == fp7:
		main.new_game(20261009)
		var fp9: int = main.sc.fingerprint(Canon.new())
		check(fp9 != fp7, "换种子换图（20261008 与 20261007 同图，改用 20261009：0x%08x）" % fp9)
	else:
		check(fp8 != fp7, "换种子换图（20261007 0x%08x vs 20261008 0x%08x）" % [fp7, fp8])

	# ---- D. 文字种子：锚点向量 + 等价数字种子同图 ----
	cmp_int(SeedCode.from_text("dragon"), 2014328350, "文字种子 dragon → 2014328350")
	main.new_game(2014328350)
	cmp_int(main.sc.fingerprint(Canon.new()), Scenario.new(2014328350).fingerprint(Canon.new()), "文字种子开局 == 数字种子 2014328350 同图")

	# ---- E. 自动取种（临时退出探针态，测完必须恢复）----
	main._is_probe_run = false
	main._settings["seed_text"] = ""
	var r1: int = main._auto_seed()
	var r2: int = main._auto_seed()
	check(r1 > 0 and r2 > 0, "留空自动随机 → 均为正数（%d, %d）" % [r1, r2])
	check(r1 != r2, "留空两次随机种子不同（%d vs %d）" % [r1, r2])
	main._settings["seed_text"] = "dragon"
	cmp_int(main._auto_seed(), 2014328350, "设置里填 dragon → 自动取种 = 2014328350")
	main._settings["seed_text"] = ""
	main._is_probe_run = true # 恢复探针态（后续断言依赖旧口径）

	# ---- F. 输入清洗：截到 24 字符，超长串哈希 = 前 24 字符哈希 ----
	var long_text := "abcdefghijklmnopqrstuvwxyz012345"
	cmp_int(UserSettings.clean_seed_text(long_text).length(), SeedCode.MAX_LEN, "超长输入清洗后 24 字符（得 %d）" % UserSettings.clean_seed_text(long_text).length())
	cmp_int(SeedCode.from_text(long_text), SeedCode.from_text(long_text.substr(0, SeedCode.MAX_LEN)), "超长串哈希 == 前 24 字符哈希")

	# ---- G. 标题屏种子框（结构 + 回写设置）----
	main.shell.open_title()
	await process_frame
	var page_title: Control = main.shell.pages["title"]
	var seed_input: LineEdit = page_title.get_node("col/seed_row/seed_input")
	check(seed_input != null, "标题屏种子输入框存在")
	if seed_input != null:
		cmp_int(seed_input.max_length, 24, "种子框 max_length = 24（得 %d）" % seed_input.max_length)
		check(seed_input.placeholder_text != "", "种子框有占位提示（得 %s）" % seed_input.placeholder_text)
	main._on_seed_changed("42")
	check(main._seed_text() == "42", "输入 42 → 设置回写（得 %s）" % main._seed_text())
	main._on_seed_changed("")
	check(main._seed_text() == "", "清空输入 → 设置复位（得 %s）" % main._seed_text())

	# ---- H. 读档回显：HUD 显示存档内的种子 ----
	main.new_game(20261013)
	check(main.save_game(TEST_SLOT), "存档到测试槽 %d 成功" % TEST_SLOT)
	main.new_game(20261014)
	check(main.load_game(TEST_SLOT), "读档测试槽 %d 成功" % TEST_SLOT)
	check(hud.seed_label.text == "种子 20261013", "读档后 HUD 显示存档种子（得 %s）" % hud.seed_label.text)
	SaveIO.delete_slot(TEST_SLOT)
	check(not FileAccess.file_exists(SaveIO.slot_path(TEST_SLOT)), "测试槽 %d 已清理" % TEST_SLOT)

	# ---- I. 肉鸽同通道（放最后：会切换 run 状态）----
	main.start_rogue(20261015)
	cmp_int(int(main.run.seed_val), 20261015, "肉鸽 run.seed_val = 20261015（得 %d）" % int(main.run.seed_val))
	check(main.run.sc.gen_failed == false, "肉鸽布局生成成功（gen_failed=false）")
	check(hud.seed_label.text == "种子 20261015", "肉鸽 HUD 种子文案（得 %s）" % hud.seed_label.text)

	# ---- J. 可用性判定 ----
	check(Scenario.usable(2014328350), "Scenario.usable(2014328350) = true")

	# ---- K. 顺延提示链路（真死种概率约百万分之一，这里只验提示接线与文案）----
	main._notify_seed_shift(111, 222)
	main._flush_seed_shift_msg()
	check(hud.hint_label.text == "种子 111 不可用，已改用 222", "顺延提示文案（得 %s）" % hud.hint_label.text)
	check(hud.hint_panel.visible, "顺延提示面板可见")

	finish("SEED", 22)
