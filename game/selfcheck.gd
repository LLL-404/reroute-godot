extends RefCounted

# 导出包自证（C8）：`--headless --selfcheck` 触发（main.gd _ready 尾部调用）。
# 断言链：引擎/构建模式 → 资源齐备（29 mp3 + CJK 字体打进包）→ sim 核心黄金回放
# 12 指纹逐位一致（含不变式看门狗与终局冻结自证）→ 确定性复跑 → 主场景构建完整
# （地形/相机/HUD/壳/世界）→ 音频接口 → tick 推进冒烟 → UI 样式工厂预设一致（v2.2）。
# 输出 `[SELFCHECK] PASS` + exit 0；任一失败 `[SELFCHECK] FAIL` + exit 1。
const UiStyle = preload("res://game/ui_style.gd")
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
	"bgm_settlement.mp3",
	"building_remove.mp3",
	"core_hit.mp3",
	"match_lose.mp3",
	"match_win.mp3",
	"terrain_fill.mp3",
	"terrain_lower.mp3",
	"tower_shot.mp3",
	"wall_place.mp3",
	"wave_horn.mp3",
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
	_cmpi(loaded, ALL_MP3.size(), "29 个 mp3 打进包且可解码")
	# 原断言只查「能加载」——加载成功但字体缺 CJK 字形时会渲染成豆腐块，照样报绿。
	# 改为实测关键字形存在性：Noto Sans SC（SIL OFL 1.1）覆盖常用汉字与标点。
	var font: FontFile = load("res://assets/fonts/NotoSansSC-Regular.otf") as FontFile
	var cjk_ok := font != null
	if cjk_ok:
		for c in "改道塔矿墙敌波金砂堆兽虫":
			if not font.has_char(c.unicode_at(0)):
				cjk_ok = false
	_chk(cjk_ok, "中文字体打进包且关键字形存在（非豆腐块）")
	# 标题衬线子集（Noto Serif SC Bold，OFL-1.1，见 CREDITS §3.3）同口径自证。
	var serif: FontFile = load("res://assets/fonts/NotoSerifSC-Bold-Sub.ttf") as FontFile
	var serif_ok := serif != null
	if serif_ok:
		for c in "改道守失档":
			if not serif.has_char(c.unicode_at(0)):
				serif_ok = false
	_chk(serif_ok, "标题衬线字体打进包且关键字形存在（非豆腐块）")

	# ---- 1b. 真实模型资产（glb）打进包 ----
	var model_paths := [
		"res://assets/models/zerg_worker.glb",
		"res://assets/models/zerg_blade.glb",
		"res://assets/models/zerg_king.glb",
		"res://assets/models/gold_pile_full.glb",
		"res://assets/models/rubble_sand.glb",
		"res://assets/models/gold_ore.glb",
		"res://assets/models/wall_barrier.glb",
		"res://assets/models/tower_ballista.glb",
		"res://assets/models/core_jade.glb",
	]
	var mloaded := 0
	for mp in model_paths:
		var packed: PackedScene = load(mp) as PackedScene
		if packed != null:
			mloaded += 1
		else:
			_fail("模型缺失：" + mp)
	_cmpi(mloaded, model_paths.size(), "9 个模型 glb 打进包")
	var blade_packed: PackedScene = load("res://assets/models/zerg_blade.glb") as PackedScene
	if blade_packed != null:
		var inst0: Node3D = blade_packed.instantiate()
		var has_player := false
		var st0: Array = [inst0]
		while not st0.is_empty():
			var n0: Node = st0.pop_back()
			if n0 is AnimationPlayer:
				has_player = true
				break
			for c0 in n0.get_children():
				st0.append(c0)
		_chk(has_player, "blade 含 AnimationPlayer（骨架动画管线）")
		inst0.free()

	# ---- 2. sim 核心：黄金回放（指纹表，含不变式 + 冻结自证）+ 确定性复跑 ----
	var samples: Array = []
	var golden_ok := false
	var sc_g: Scenario = Scenario.new()
	var cmds: Array = Verify.script_for(sc_g)
	var res: Array = Verify.run_world(sc_g, GoldenBaseline.SEED, cmds, GoldenBaseline.EVERY, true)
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
		_cmpi(mism, 0, "黄金指纹逐位一致（引擎黄金基线）")
	if golden_ok:
		var res2: Array = Verify.run_world(Scenario.new(), GoldenBaseline.SEED, cmds, GoldenBaseline.EVERY, false)
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
	_cmpi(int(st["field"]), 4096, "地面网格 field=4096")
	_cmpi(int(st["plain"]), 39820, "场外旷野 plain=39820（六边化：场内面片跳过，原 39312 已废止）")
	_chk(st["cam"] == true, "相机就绪")
	_cmpi(int(st["covers"]), 25, "覆盖层 covers=25")
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

	# ---- 6. UI 样式工厂一致性（v2.2：质感预设 + 变体接线不漂移）----
	var ui_c: Dictionary = main.hud.DARK
	var btn_st: Dictionary = UiStyle.button_states(ui_c, true)
	_cmpi(int(btn_st["pressed"].content_margin_top), 2, "A6 主钮按下下沉 2px")
	_cmpi(int(btn_st["normal"].shadow_size), 6, "A2 主钮投影档位")
	_chk(btn_st["normal"].shadow_color == UiStyle.SHADOW_BTN, "A2 主钮投影色 token")
	var ui_theme: Theme = main.shell.host.theme
	_chk(main.hud.theme == ui_theme, "hud/shell 同源共享主题实例")
	var card_sb: StyleBoxFlat = ui_theme.get_stylebox("panel", UiStyle.CARD_VAR)
	_chk(card_sb != null and card_sb.shadow_size >= 12 and card_sb.shadow_color == ui_c["shadow"], "A2 卡片投影档位")
	_chk(ui_theme.get_stylebox("normal", UiStyle.BTN_MENU_VAR) != null, "变体 MenuButton 已装")
	_chk(ui_theme.get_stylebox("slider", UiStyle.SLIDER_VAR) != null, "变体 GoldSlider 已装")
	_chk(UiStyle.grain_tex() != null and UiStyle.vignette_tex() != null, "A4/A5 氛围层纹理已生成")

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
