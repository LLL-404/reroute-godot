extends RefCounted

# 导出包自证（C8）：`--headless --selfcheck` 触发（main.gd _ready 尾部调用）。
# 断言链：引擎/构建模式 → 资源齐备（19 mp3 + CJK 字体打进包）→ sim 核心黄金回放
# 16 指纹逐位一致（含不变式看门狗与终局冻结自证）→ 确定性复跑 → 主场景构建完整
# （地形/相机/HUD/壳/世界）→ 音频接口 → tick 推进冒烟。
# 输出 `[SELFCHECK] PASS` + exit 0；任一失败 `[SELFCHECK] FAIL` + exit 1。
const ALL_MP3 := [
	"bgm_reroute.mp3",
	"build_stone_place.mp3",
	"dungeon_ambience.mp3",
	"gold_collect.mp3",
	"mining_gold_hit.mp3",
	"orc_chief_roar.mp3",
	"orc_death.mp3",
	"orc_hurt.mp3",
	"orc_step.mp3",
	"orc_warrior_attack.mp3",
	"orc_worker_effort.mp3",
	"room_door_open.mp3",
	"room_fire_loop.mp3",
	"zerg_blade_attack.mp3",
	"zerg_death.mp3",
	"zerg_hurt.mp3",
	"zerg_king_roar.mp3",
	"zerg_step.mp3",
	"zerg_worker_chitter.mp3",
]

var checks := 0
var bad := 0
var fail_list: Array = []


func run(main) -> int:
	var vi: Dictionary = Engine.get_version_info()
	print("[SELFCHECK] godot=", str(vi.get("string", "?")), " editor=", str(OS.has_feature("editor")))

	# ---- 1. 资源齐备（打进包的自证）----
	var loaded := 0
	for name in ALL_MP3:
		var s: AudioStream = load("res://assets/audio/sfx/" + name) as AudioStream
		if s != null and s.get_length() > 0.0:
			loaded += 1
		else:
			_fail("音频缺失/不可解码：" + name)
	_cmpi(loaded, ALL_MP3.size(), "19 个 mp3 打进包且可解码")
	var font: FontFile = load("res://assets/fonts/simhei.ttf") as FontFile
	_chk(font != null, "中文字体打进包")

	# ---- 2. sim 核心：黄金回放 16 指纹（含不变式 + 冻结自证）+ 确定性复跑 ----
	var samples: Array = []
	var golden_ok := false
	var res: Array = Verify.run_world(Scenario.new(), GoldenBaseline.SEED, Verify.SCRIPT_COMMANDS, GoldenBaseline.EVERY, true)
	if res[1] != "":
		_fail("run_world：" + str(res[1]))
	else:
		golden_ok = true
		samples = res[0]
		_cmpi(samples.size(), GoldenBaseline.FPS.size(), "黄金采样点数")
		var mism := 0
		for i in mini(samples.size(), GoldenBaseline.FPS.size()):
			var want: Array = GoldenBaseline.FPS[i]
			var got: Array = samples[i]
			if int(got[0]) != int(want[0]) or String(got[1]) != String(want[1]):
				mism += 1
				_fail("指纹失配 tick %d：得 %s 期 %s" % [int(want[0]), str(got[1]), str(want[1])])
		_cmpi(mism, 0, "16 指纹逐位一致（引擎黄金基线）")
	if golden_ok:
		var res2: Array = Verify.run_world(Scenario.new(), GoldenBaseline.SEED, Verify.SCRIPT_COMMANDS, GoldenBaseline.EVERY, false)
		if res2[1] != "":
			_fail("复跑：" + str(res2[1]))
		else:
			var s2: Array = res2[0]
			var same := true
			if s2.size() != samples.size():
				same = false
			else:
				for i in samples.size():
					if String(s2[i][1]) != String(samples[i][1]):
						same = false
						break
			_chk(same, "确定性复跑逐位一致")

	# ---- 3. 主场景构建完整 ----
	var view = main.view
	var st: Dictionary = view.debug_stats()
	_cmpi(int(st["field"]), 2304, "地形柱带 field=2304")
	_cmpi(int(st["ring"]), 4384, "环带 ring=4384")
	_chk(st["cam"] == true, "相机就绪")
	_cmpi(int(st["covers"]), 23, "覆盖层 covers=23")
	var gsolid := 0
	var g0 = main.world.grid
	for i in g0.cells.size():
		if int(g0.cells[i]) == Grid.SOLID:
			gsolid += 1
	_cmpi(int(st["solids"]), gsolid, "solids 与网格一致")
	_chk(main.world != null, "世界存在")
	_chk(main.hud != null, "HUD 构建")
	_chk(main.shell != null, "界面壳构建")
	_chk(main.world.hero != null and not main.world.hero.is_empty(), "英雄存在")
	_chk(main.world.core != null and not main.world.core.is_empty() and int(main.world.core["hp"]) > 0, "核心存在")

	# ---- 4. 音频接口（headless Dummy 驱动下须无报错）----
	var n0: int = int(view.sfx_log.get("orc_chief_roar.mp3", 0))
	view.play_sound("orc_chief_roar.mp3", 0.9)
	_cmpi(int(view.sfx_log.get("orc_chief_roar.mp3", 0)) - n0, 1, "SFX 接口计数")
	view.bgm(true)
	_chk(view.bgm_on == true, "BGM 开接口")
	view.bgm(false)
	_chk(view.bgm_on == false, "BGM 关接口")

	# ---- 5. tick 推进冒烟（40 tick + 视图同步）----
	var t0: int = main.world.tick_count
	for _i in 40:
		main.world.tick()
		view.sync(main.world)
	_cmpi(main.world.tick_count, t0 + 40, "40 tick 推进")
	_chk(main.world.outcome == World.RUNNING, "仍在进行中")

	print("[SELFCHECK] checks=", checks, " bad=", bad)
	for i in mini(fail_list.size(), 12):
		print("[SELFCHECK] fail: ", fail_list[i])
	print("[SELFCHECK] ", "PASS" if bad == 0 else "FAIL")
	return 0 if bad == 0 else 1


func _fail(msg: String) -> void:
	bad += 1
	fail_list.append(msg)


func _chk(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		_fail(label)


func _cmpi(got: int, want: int, label: String) -> void:
	checks += 1
	if got != want:
		_fail("%s got=%d want=%d" % [label, got, want])
