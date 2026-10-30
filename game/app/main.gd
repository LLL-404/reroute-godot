extends Node3D

# 《改道》Godot 版主循环：20Hz 固定步长模拟、世界到视图同步与输入分发。
# 对局生命周期统一在这里管理；模拟规则归 sim/，绘制、HUD、页面、音频归 game/ 对应模块。
# 唯一写模拟的入口：world.apply_command(Command.xxx(...))；未知 kind 在正式包按空操作。

# ---- 公开面（外部可调）----
# 流转与管理 11 个：start_match / start_rogue / pause_game / resume_game / restart_game / to_title /
# load_game / save_game / new_game / can_undo_build / do_undo_build。
# 输入与查询 9 个：in_hud_region / mode_valid / line_cells / set_mode / apply_mode_at /
# pointer_down / pointer_up / update_ghost / toggle_heat。
# ---- 探针契约（改名会破 tests/probes，勿动）----
# 探针直读字段：view / world / sc / run / run_ui / hex / hud / shell / danger / paused / mode /
# heat_on / run_index / tower_pick / terrain_card，并直接调上面这 20 个公开方法。

const Blueprint = preload("res://game/core/blueprint.gd")
const Selfcheck = preload("res://game/app/selfcheck.gd")
const UserSettings = preload("res://game/core/user_settings.gd")
const SaveIO = preload("res://game/core/save_io.gd")
const PrivacyGateScene = preload("res://game/ui/privacy_gate.tscn") # 隐私门场景（结构在 tscn）
const IntroScene = preload("res://game/ui/intro.tscn") # 开屏动画场景（结构在 tscn）
const HudScene = preload("res://game/ui/hud.tscn") # HUD 场景（结构在 tscn）
const ScreensScene = preload("res://game/ui/screens.tscn") # 界面壳场景（五页面 + 确认弹窗 + 过渡黑幕）
const RunUiScene = preload("res://game/ui/run_ui.tscn") # 肉鸽 HUD 场景（结构在 tscn）
const HexPickerScene = preload("res://game/ui/hex_picker.tscn") # 三选一面板场景（结构在 tscn）
const CameraControlScript = preload("res://game/view/camera_control.gd") # 相机操作层（输入 → 相机意图）

const TICK_DT := 1.0 / 20.0
const MAX_CATCHUP := 5 # 单帧最多补的 tick 数（追平上限，超出丢弃积压）
const BASE_SEED := 20261003
const SEED_RETRY_MAX := 256 # 种子顺延上限：撞上死图（64 盐耗尽）就 +1 再试，最多这么多次
# ---- 触屏手势（Android/iOS；桌面鼠标路径完全不受影响）----
const TOUCH_SLOP := 14.0 # 单指点按判定：位移超过此逻辑像素即视为拖动（平移）
const MENU_FPS := 60 # 菜单/标题/结算限帧（压风扇/GPU）；对局态 = 玩家上限（默认 0 不限，vsync 全速——用户口径 2026-10-17/18）

var view = null # View（preload 脚本实例）；动态引用
var camera_control = null # 相机操作层（game/view/camera_control.gd）
var world: World = null
var sc: Scenario = null
var run: RunState = null # 非空 = 当前是肉鸽局（world/sc 指向 run 内部实例）
var run_ui = null # 肉鸽 HUD（game/run_ui.gd）
var hex = null # 海克斯式三选一面板（game/hex_picker.gd）
var tower_pick := 0 # 肉鸽模式当前选中的塔种下标（run.tower_kinds）
var terrain_card := "" # 待落地形牌 id（点地图 3×3 中心生效）
var _last_run_phase := -1
var run_index := 0
var acc := 0.0
var paused := true # R1 新局即跑（标题屏 R6 接入后恢复"启动即暂停"口径）
var time_scale := 1.0
var hud = null # HUD（game/hud.gd 实例）
var hud_layer: CanvasLayer
var danger = null # 核心低血警告（game/danger_vignette.gd 实例，独立 CanvasLayer 15）
var shell = null # 界面壳（game/screens.gd 实例）
var over_shown := false

# ---- 输入状态（口径同母版 main.lua） ----
var mode := "wall"
var drag_start := Vector2i(-1, -1) # 拖拽起始格
var mouse_pos := Vector2(-1.0, -1.0)
var heat_on := false
# ---- 触屏手势状态 ----
var touch_pts := {} # 活跃手指 index → 屏幕位置
var touch_mode := "" # "" 空闲 / "single" 单指 / "multi" 双指以上
var touch_start := Vector2.ZERO # 首指落点（点按判定基准）
var touch_dragging := false # 单指已越过 TOUCH_SLOP（判定为拖动）
var touch_wall := false # 本次单指手势正在拖墙线
## HUD 命中区提供者（R5 注入；未注入 = 无 HUD 区域）
var hud_regions_provider: Callable
var _last_back_ms := 0 # Android 返回键双入口（通知 / ui_cancel 动作）去抖时间戳
var _undo_cells: Array = [] # 最近一次建造（单格/拖拽一条线）的格子；5s 窗口内可全额撤销
var _undo_tick := -99999 # 该次建造的 tick（撤销窗口 = World.UNDO_WINDOW_TICKS）
var _intro = null # 开屏动画层（game/intro.gd；仅冷启动非探针路径创建，播完自毁）
var _settings: Dictionary = {} # 玩家设置缓存（含 runs 跨会话局数；save_cfg 回写）
var _is_probe_run := false # 探针/自检运行：不读不写跨会话局数（保探针确定性与种子口径）
var _ore_intent := {} # M2-a 待开挖矿格意图：{ "ore": Vector2i, "stand": Vector2i }
var _transitioning := false # UI 过渡中（黑幕在屏上，吞掉重复点击）
var _seed_shift_msg := "" # 种子顺延提示文案（暂存；显示接线在后续任务，不在这里碰 hud/screens）


## 初始化：建 HUD/壳、开新局、显示标题屏；自检模式触发 export 验收
func _ready() -> void:
	view = $View
	# 相机操作层：输入翻译与相机状态都在这里；main 只注入「能否操控」判定
	camera_control = CameraControlScript.new(view, Callable(self, "_camera_free"))
	_is_probe_run = _detect_probe_run()
	_settings = UserSettings.load_cfg()
	# 隐私门（合规）：冷启动且未同意 → 先弹窗；此时不建 HUD/壳/肉鸽 UI、不开局、不播开屏，
	# 也不写 user://settings.cfg（同意动作由 _on_privacy_agreed 落盘）。
	# 探针/自检/headless 一律跳过，保 22 闸与 selfcheck 口径不变。
	# ⚠️ 2026-10-21 11:17 的 902277b（肉鸽编排层）重写 _ready 时把这段整段丢了，
	#    导致 v2.5 草稿包（1.0.1）里隐私门不生效 —— 此处恢复，勿再删。
	if not _is_probe_run and not bool(_settings.get("privacy_agreed", false)):
		UserSettings.apply_video(_settings) # 先按玩家设置摆正窗口，否则小窗把隐私卡片压到最小宽
		_show_privacy_gate()
		return
	_boot()


## 正常启动流程（原 _ready 主体）：隐私门通过后调用。
func _boot() -> void:
	_setup_hud()
	_setup_shell()
	_setup_run_ui()
	if _is_probe_run:
		view.core.shake_on = false # 震屏会抖偏截图：探针/selfcheck/headless 一律不启用（像素校验口径）
		view.fog.enabled = false # 迷雾遮罩会吃掉截图像素断言（check_shots 口径）：探针一律关雾
		UserSettings.apply_audio(_settings) # 探针只应用音量（显示/画质保持默认，保 gate 截图口径）
	else:
		UserSettings.apply_all(_settings) # 启动即应用玩家设置（音量 bus / 显示模式 / 分辨率 / 垂直同步）
		view.apply_video(_settings) # 画质/渲染缩放/AA/阴影/雾/景深/亮度
		view.core.shake_on = bool(_settings.get("screen_shake", true)) # 震屏跟随玩家开关（探针分支恒关，保截图口径）
		hud.apply_ui_scale(int(_settings.get("ui_pct", 100)))
		shell.apply_ui_scale(int(_settings.get("ui_pct", 100)))
	if not _is_probe_run:
		run_index = maxi(0, int(_settings.get("runs", 0))) # 跨会话续接已玩局数（标题预烘焙不算）
		# 先亮黑幕并让出两帧再动工（2026-10-22）：否则整段构建卡在 _ready 里，
		# 玩家面对的是没画过一帧的黑窗；手机端构建更久，必须先给可见反馈。
		shell.veil_show("正在生成战场…")
		await get_tree().process_frame
		await get_tree().process_frame
	new_game()
	hud.set_visible_hud(false)
	view.core.fit_camera() # 标题背景固定为标准俯视全图（不受窗口尺寸变化前的残留取景影响）
	shell.open_title() # 启动即标题：标题屏压着静态战场（母版口径，paused 初值 true）
	if _is_selfcheck():
		shell.veil_hide()
		_run_selfcheck()
	elif _intro_enabled():
		_play_intro()
		shell.veil_hide() # 开屏动画自带黑场接管，避免黑幕与开屏双重淡出
	elif not _is_probe_run:
		shell.veil_fade_out(0.3)


## 弹隐私门：同意 → 落盘 + 走正常启动；不同意 → 退出应用。
func _show_privacy_gate() -> void:
	var gate = PrivacyGateScene.instantiate()
	add_child(gate)
	gate.agreed.connect(_on_privacy_agreed)
	gate.declined.connect(_on_privacy_declined)


## 同意隐私政策：写盘（privacy/agreed=true）后继续启动。
func _on_privacy_agreed() -> void:
	_settings["privacy_agreed"] = true
	UserSettings.save_cfg(_settings)
	_boot()


## 不同意：直接退出（不留任何数据写入）。
func _on_privacy_declined() -> void:
	get_tree().quit(0)


## 开屏动画装载（探针零影响口径）：selfcheck / headless / 探针脚本主循环（-s res://tests/）
## 三类自动跳过——生产冷启动才播。判断探针 = 主循环脚本非空且路径在 res://tests/ 下
## （20 探针都以 `-s res://tests/probes/*.gd` 运行，主循环脚本非空可精确识别）。
func _intro_enabled() -> bool:
	if _is_selfcheck() or DisplayServer.get_name() == "headless":
		return false
	var ml = Engine.get_main_loop()
	if ml == null or ml.get_script() == null:
		return true
	return not String(ml.get_script().resource_path).begins_with("res://tests/")


## 播放开屏动画（一次性；层级在壳之上，播完自毁清引用）。
func _play_intro() -> void:
	_intro = IntroScene.instantiate()
	add_child(_intro)
	_intro.begin(Callable(view, "play_sound"), hud.DARK)
	_intro.on_done = func() -> void:
		_intro = null


## 导出包自证触发检测（C8）：`--headless --selfcheck`（引擎参数后或 ++ 后均可）。
func _is_selfcheck() -> bool:
	return OS.get_cmdline_args().has("--selfcheck") or OS.get_cmdline_user_args().has("--selfcheck")


## 探针/自检运行检测（与 _intro_enabled 同口径）：selfcheck / headless / -s res://tests/*
## 三类不读不写跨会话局数（保探针输出与首局种子确定性）。
func _detect_probe_run() -> bool:
	if _is_selfcheck() or DisplayServer.get_name() == "headless":
		return true
	var ml = Engine.get_main_loop()
	if ml == null or ml.get_script() == null:
		return false
	return String(ml.get_script().resource_path).begins_with("res://tests/")


## 跑自检并以其返回码退出（R8；headless 导出包验收用）。
## 退出前全停音频 + 等混音周期完成回收：带活动播放对象直接 quit 会在退出清理报
## Playback 泄漏 + "resources still in use"（实测），停播后需等音频侧回收生效再退。
func _run_selfcheck() -> void:
	var chk = Selfcheck.new()
	var code: int = chk.run(self)
	view.stop_all_audio()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(code)


## HUD 构建与接线（HUD 只管发 signal，具体动作全在 main）。
func _setup_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = HudScene.instantiate()
	hud_layer.add_child(hud)
	hud.setup()
	hud.mode_selected.connect(_on_hud_mode)
	hud.pause_requested.connect(_on_hud_pause)
	hud.heat_toggled.connect(_on_hud_heat)
	hud.skill_requested.connect(_on_hud_skill)
	hud.undo_requested.connect(_on_hud_undo)
	hud.worker_requested.connect(_on_hud_worker)
	hud_regions_provider = Callable(hud, "hit_regions")
	view.on_float = Callable(hud, "float_bounty")
	danger = preload("res://game/ui/danger_vignette.gd").new()
	danger.name = "DangerVignette"
	add_child(danger)


## 界面壳构建与接线（壳只发 signal / 提供取数口，具体动作全在 main）。
func _setup_shell() -> void:
	shell = ScreensScene.instantiate()
	shell.name = "Shell"
	add_child(shell)
	shell.setup(hud)
	shell.start_match_requested.connect(_ui_start_match)
	shell.start_rogue_requested.connect(_ui_start_rogue)
	shell.restart_requested.connect(restart_game)
	shell.resume_requested.connect(resume_game)
	shell.to_title_requested.connect(to_title)
	shell.pause_requested.connect(pause_game)
	shell.quit_requested.connect(_quit_game)
	shell.video_changed.connect(_on_video_changed)
	shell.ui_changed.connect(_on_ui_changed)
	shell.seed_changed.connect(_on_seed_changed)
	shell.shake_toggled.connect(_on_shake_toggled)
	# 取数口（要返回值，signal 带不了）
	shell.seed_text_provider = Callable(self, "_seed_text")
	shell.stats_provider = Callable(self, "_stats_card")
	shell.load_slot_provider = Callable(self, "load_game")
	shell.save_slot_provider = Callable(self, "save_game")


## 肉鸽 HUD 构建与接线（独立 CanvasLayer，不侵入 hud/screens）
func _setup_run_ui() -> void:
	run_ui = RunUiScene.instantiate()
	run_ui.name = "RunUi"
	add_child(run_ui)
	run_ui.setup(hud)
	run_ui.start_wave_requested.connect(_run_start_wave)
	run_ui.advance_requested.connect(_run_advance)
	run_ui.card_used.connect(_run_use_card)
	run_ui.card_picked.connect(_run_pick)
	hex = HexPickerScene.instantiate()
	hex.name = "HexPicker"
	add_child(hex)
	hex.setup(Callable(view, "play_sound"), hud)
	hex.card_picked.connect(_run_pick)
	hex.refresh_requested.connect(_run_refresh)
	hex.skip_requested.connect(_run_skip)


# ---------------- 屏幕流转（页状态 = 游戏状态：进行中 = 空态） ----------------

## 标题「经典对局」按钮：短黑场过渡（0.1s 淡入 → 切场 → 0.24s 揭示）。
## 探针直接走同步 start_match，保 probe_ui_flow 的即点即断言时序。
## p_seed_text = 标题屏种子框原文（留空 = 复用已预烘焙的那局，不重摇）。
func _ui_start_match(p_seed_text: String = "") -> void:
	if _is_probe_run:
		start_match()
		return
	if _transitioning:
		return
	_transitioning = true
	var v := SeedCode.from_text(p_seed_text)
	# 只有玩家给了与场上那局不同的种子才重生成；同图直接开（省一次地形重建）
	if v > 0 and sc != null and int(sc.seed) != v:
		shell.veil_show("正在生成战场…", 0.10)
		await get_tree().process_frame
		await get_tree().process_frame
		new_game(v)
	else:
		shell.veil_show("", 0.10)
		await get_tree().create_timer(0.12).timeout
	start_match()
	shell.veil_fade_out(0.24)
	await get_tree().create_timer(0.26).timeout
	_transitioning = false


## 标题「肉鸽模式」按钮：地形重建（约 2~3s）压在全黑幕下完成，点击后不再呈现冻屏。
## p_seed_text 口径同经典对局（留空 = 自动随机 / 取设置里的种子）。
func _ui_start_rogue(p_seed_text: String = "") -> void:
	if _is_probe_run:
		start_rogue()
		return
	if _transitioning:
		return
	_transitioning = true
	shell.veil_show("正在生成战场…", 0.12)
	await get_tree().create_timer(0.14).timeout
	start_rogue(SeedCode.from_text(p_seed_text))
	shell.veil_fade_out(0.26)
	await get_tree().create_timer(0.28).timeout
	_transitioning = false


## 标题 → 对局：用启动/回标题时备好的那局。
func start_match() -> void:
	paused = false
	acc = 0.0
	time_scale = 1.0
	drag_start = Vector2i(-1, -1)
	hud.reset()
	hud.set_visible_hud(true)
	_flush_seed_shift_msg() # 种子被顺延过的提示：HUD 可见后补一次
	view.bgm(true)
	shell.close_all()
	_persist_runs()
	_onboard_begin()


## 开一局肉鸽：新种子 → RunState（内含独立 Scenario + World）→ 切表现层
## p_seed = 0 → 自动（探针旧口径 / 玩家种子 / 随机）；撞上死图则 +1 顺延。
func start_rogue(p_seed: int = 0) -> void:
	run_index += 1
	var want := p_seed if p_seed > 0 else _auto_seed()
	# 顺延循环：换盐耗尽（gen_failed）就换下一个种子再试，最多 SEED_RETRY_MAX 次
	var used := want
	var r: RunState = null
	while used < want + SEED_RETRY_MAX:
		r = RunState.new(used)
		if not r.sc.gen_failed:
			break
		r = null
		used += 1
	if r == null:
		used = Scenario.DEFAULT_SEED # 全部失败：回落默认图（与 Scenario 内部回落同口径）
		r = RunState.new(used)
	if used != want:
		print("[Game] 种子顺延 %d → %d" % [want, used])
		_notify_seed_shift(want, used)
	run = r
	sc = run.sc
	world = run.world
	tower_pick = 0
	terrain_card = ""
	_last_run_phase = -1
	view.set_heat(false)
	var picked: Array = Blueprint.pick(run_index)
	view.apply_blueprint(picked[0], picked[1], _visual_anchor())
	view.is_ore = Callable(sc, "is_ore")
	view.build_terrain(world.grid)
	view.sync(world)
	acc = 0.0
	drag_start = Vector2i(-1, -1)
	heat_on = false
	over_shown = false
	if hud != null:
		hud.reset()
		hud.set_heat_vis(false)
		hud.set_seed(used) # 肉鸽局同样显示种子（top_bar 会隐藏，种子标签挂在根下不受影响）
	_reset_undo()
	paused = true # INTRO 阶段：等玩家点开始
	hud.set_visible_hud(true)
	hud.top_bar.visible = false # 经典顶栏的「终局 tick / 波次」在肉鸽局无意义，由 run_ui 接管
	_flush_seed_shift_msg() # 顺延提示：HUD 可见后补一次
	run_ui.show_run(run)
	shell.close_all()
	view.bgm(true)
	print("[Game] 肉鸽开局 seed=", used)
	_persist_runs()


# ---------------- 肉鸽回调（run_ui → RunState） ----------------

func _run_start_wave() -> void:
	if run == null:
		return
	run.start_wave()
	run_ui.refresh()


func _run_pick(idx: int) -> void:
	if run == null:
		return
	var card: Dictionary = run.pick(idx)
	if card.is_empty():
		return
	run_ui.refresh()


func _run_refresh() -> void:
	if run == null:
		return
	if not run.refresh_offers():
		run_ui.flash("供给不足或已刷满")
		return
	_open_hex() # 换牌后重播一次入场动画


func _run_skip() -> void:
	if run == null or run.phase != RunState.PHASE_PICK:
		return
	run.world.supply += 50
	run.offers = []
	run.start_wave()
	run_ui.refresh()


func _run_advance() -> void:
	if run == null:
		return
	run.advance_layer()
	run_ui.refresh()


func _run_use_card(cid: String) -> void:
	terrain_card = cid
	run_ui.flash("点地图选 3×3 中心")


## 跨会话局数落盘（进入对局才记：标题屏预烘焙的那局不算「玩过」；探针/自检跳过）。
func _persist_runs() -> void:
	if _is_probe_run or _settings.is_empty():
		return
	_settings["runs"] = run_index
	UserSettings.save_cfg(_settings)


# ---------------- 新手引导 FO（specs/onboarding-spec §3；纯编排层，sim/ 零改动） ----------------
# 四步：PORT 出怪口指认 → WALL 第一堵墙（推荐格仅视觉引导，任意放置算完成）→
# FOLLOW 看第一只怪绕路 → ECON 波末赏金来源。任意世界区点击 = 跳过当前步（识别>回忆，
# 比角落热区更大更防误触）。探针环境默认不激活（保像素口径），probe_onboarding 用 override 强开。
enum OnboardStage { NONE, PORT, WALL, FOLLOW, ECON, DONE }
var _onboard: int = OnboardStage.NONE
var _onboard_override := -1 # 探针注入：-1 自动（首局判定）/ 0 强制关 / 1 强制开
var _fo_t := 0.0 # 当前步已展示时长（PORT/ECON 的 4s 自推进）
var _fo_spawned := false # FOLLOW/ECON 用：见过活单位
var _fo_port_cell := Vector2i(-1, -1) # FO-0 高亮：首波出怪口
var _fo_wall_cell := Vector2i(-1, -1) # FO-1 推荐：出怪口↔核心门前锚点的几何中点近似


func _onboard_begin() -> void:
	var on := not _is_probe_run and int(_settings.get("runs", 0)) == 0
	if _onboard_override == 1:
		on = true
	elif _onboard_override == 0 or _is_probe_run:
		on = false
	_fo_spawned = false
	_fo_t = 0.0
	if not on:
		_onboard = OnboardStage.NONE
		return
	_onboard = OnboardStage.PORT
	if world == null or sc == null:
		_onboard = OnboardStage.NONE
		return
	_fo_port_cell = sc.wave_cell(0)
	_fo_wall_cell = _fo_midpath_cell()
	view.set_focus(_fo_port_cell, true)
	hud.hint("怪从这里来——点一下继续")


## FO-1 推荐格：出怪口 ↔ hero_spawn（核心门前锚点）的几何中点，向四周找无建筑的格。
## 简化口径：不沿流场走真路径（FlowField 邻格偏移是内部结构不外泄）；
## 推荐格只作视觉引导，玩家任意放置都算完成（specs/onboarding-spec 实现修订）。
func _fo_midpath_cell() -> Vector2i:
	if world == null or sc == null:
		return Vector2i(-1, -1)
	var a: Vector2i = sc.wave_cell(0)
	var b: Vector2i = sc.hero_spawn
	var mid := Vector2i((a.x + b.x) / 2, (a.y + b.y) / 2)
	for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
		var c: Vector2i = mid + off
		if world.building_at(c.x, c.y) == null:
			return c
	return mid


func _onboard_active() -> bool:
	return _onboard != OnboardStage.NONE and _onboard != OnboardStage.DONE


## 世界区任意点击 = 「知道了」：跳过当前步（FO-1 除外——放墙本身就是完成动作）。
func _onboard_click() -> void:
	if not _onboard_active():
		return
	match _onboard:
		OnboardStage.PORT:
			_fo_enter_wall()
		OnboardStage.FOLLOW:
			_fo_enter_econ()
		OnboardStage.ECON:
			_fo_finish()
		_:
			pass # WALL 步靠真实放墙完成；DONE/NONE 无动作


func _fo_enter_wall() -> void:
	_onboard = OnboardStage.WALL
	_fo_t = 0.0
	if _fo_wall_cell.x >= 0:
		view.set_focus(_fo_wall_cell, true)
	hud.hint("试着放一堵墙，挡住它的路")


func _fo_enter_follow() -> void:
	_onboard = OnboardStage.FOLLOW
	_fo_t = 0.0
	hud.hint("怪会绕开墙——看它改道")


func _fo_enter_econ() -> void:
	_onboard = OnboardStage.ECON
	_fo_t = 0.0
	hud.hint("你还让怪走得动核心，你才拿绕行的钱——修运河，别只堵路")


func _fo_finish() -> void:
	_onboard = OnboardStage.DONE
	_fo_t = 0.0


## FO 每帧驱动（PORT/ECON 4s 自推进；FOLLOW 看首单位走满 5 格或清场）。
func _onboard_tick(dt: float) -> void:
	if not _onboard_active() or world == null:
		return
	_fo_t += dt
	match _onboard:
		OnboardStage.PORT:
			if _fo_t >= 4.0:
				_fo_enter_wall()
		OnboardStage.FOLLOW:
			if not world.units.is_empty():
				_fo_spawned = true
			var far_enough := false
			for u in world.units:
				if int(u.get("traveled", 0)) >= 5:
					far_enough = true
					break
			if far_enough or (_fo_spawned and world.units.is_empty()):
				_fo_enter_econ()
		OnboardStage.ECON:
			if _fo_t >= 4.0:
				_fo_finish()
		_:
			pass


## 战绩卡三数落盘（终局调用；探针/自检跳过——probe_onboarding 直接调本函数断言）。
## best_wave 口径 = 已开波数（与 HUD 横幅波次序号同源：波表 tick ≤ tick_count 计数）。
func _persist_stats(won: bool) -> void:
	if _is_probe_run or _settings.is_empty():
		return
	var started := 0
	for w in sc.waves:
		if int(w[0]) <= world.tick_count:
			started += 1
	_settings["best_wave"] = maxi(int(_settings.get("best_wave", 0)), started)
	if won:
		_settings["wins"] = int(_settings.get("wins", 0)) + 1
	UserSettings.save_cfg(_settings)


## 标题页战绩卡取数（screens 经 stats_provider 调用）。
func _stats_card() -> Array:
	return [int(_settings.get("runs", 0)), int(_settings.get("best_wave", 0)), int(_settings.get("wins", 0))]


## 设置页视频/画质改动：同步缓存 + 立即应用（显示走 DisplayServer，画质走 view；
## 帧率改动下一帧由 _sync_fps_cap 接管）。
func _on_video_changed(cfg: Dictionary) -> void:
	for k in UserSettings.VIDEO_KEYS:
		_settings[k] = cfg[k]
	UserSettings.apply_video(_settings)
	view.apply_video(_settings)


## 设置页 UI 缩放改动：缓存 + HUD 立即重排 + 界面页离开设置页时按新 S 重建。
func _on_ui_changed(pct: int) -> void:
	_settings["ui_pct"] = pct
	hud.apply_ui_scale(pct)
	shell.apply_ui_scale(pct)


## 暂停（仅进行中且未暂停时有效；HUD 按钮 / Esc / 安卓返回共用）
func pause_game() -> void:
	if world.outcome != World.RUNNING or paused:
		return
	paused = true
	drag_start = Vector2i(-1, -1)
	shell.open_pause()


## 继续对局（暂停页「继续」按钮）
func resume_game() -> void:
	if not paused:
		return
	paused = false
	shell.resume()


## 暂停/结算 → 重开一局（肉鸽局重开仍是肉鸽）
## 设置里填了种子就重开仍用它；留空 = 每局随机（探针恒为 0，保旧口径）。
func restart_game() -> void:
	var v := _seed_from_settings()
	if run != null:
		start_rogue(v)
		return
	new_game(v)
	start_match()


## 暂停/结算 → 标题：备一局新的压着静态战场
func to_title() -> void:
	paused = true
	drag_start = Vector2i(-1, -1)
	run = null
	terrain_card = ""
	_last_run_phase = -1
	if run_ui != null:
		run_ui.hide_run()
	if hex != null:
		hex.close()
	hud.set_visible_hud(false)
	view.bgm(false)
	new_game(_seed_from_settings())
	view.core.fit_camera() # 回标题重置相机：与冷启动同口径（清掉玩家拖/缩/转后的视角）
	shell.open_title()


# ---------------- 存档 / 退出 / Android 返回 ----------------

## 读档开局：还原世界 + 蓝图视觉（Blueprint.pick 按存档 run 重放），直接进对局。
## 坏档/旧档读档失败返回 false（由存档页显示原因）。
func load_game(slot: int) -> bool:
	_onboard = OnboardStage.NONE # 读档不是首局：FO 显式关闭（specs/onboarding-spec §3）
	var w := SaveIO.load_slot(slot)
	if w == null:
		return false
	var meta := SaveIO.slot_meta(slot)
	run_index = int(meta.get("run", run_index))
	sc = w.sc
	world = w
	view.set_heat(false)
	var picked: Array = Blueprint.pick(run_index)
	view.apply_blueprint(picked[0], picked[1], _visual_anchor())
	view.is_ore = Callable(sc, "is_ore")
	view.build_terrain(world.grid)
	# 战争迷雾记忆还原（开局成长改造）：槽位旁路字段；缺失/尺寸不符 → 后续 sync 按现存实体重推导
	var fog_bytes := SaveIO.slot_fog(slot)
	if fog_bytes.size() > 0:
		view.fog.restore(fog_bytes)
	view.sync(world)
	acc = 0.0
	drag_start = Vector2i(-1, -1)
	heat_on = false
	over_shown = false
	if hud != null:
		hud.reset()
		hud.set_heat_vis(false)
	_reset_undo()
	start_match()
	if hud != null:
		hud.set_seed(int(world.sc.seed)) # 读档回显：显示存档内的种子（与地图一致）
	print("[Game] 读档 槽=", slot, " run=", run_index, " tick=", world.tick_count)
	return true


## 存档（仅进行中可存；返回布尔给存档页反馈）。
func save_game(slot: int) -> bool:
	if world == null or world.outcome != World.RUNNING:
		return false
	var ok := SaveIO.save_slot(slot, world, run_index, view.fog.snapshot()) # 迷雾位图旁路字段（探针关雾=空数组不写）
	print("[Game] 存档 槽=", slot, " ok=", ok, " tick=", world.tick_count)
	return ok


## 退出游戏（二次确认在壳层；抵达此处即退）。收尾口径同 selfcheck：全停音频 +
## 等混音周期回收，避免带活动播放对象直接 quit 报 Playback 泄漏。
func _quit_game() -> void:
	print("[Game] 退出游戏")
	view.stop_all_audio()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


## Android 返回键统一路由（通知 / ui_cancel 动作双入口，80ms 去抖防双触发）。
## 语义与 Esc 一致：暂停↔继续；进行中=暂停；存档/设置=回上级；结算=回标题；
## 标题=退出确认（桌面 Esc 在标题仍不响应，两者互不影响）。
func _android_back_handle() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_back_ms < 80:
		return
	_last_back_ms = now
	if _intro != null: # 开屏动画中：Android 返回 = 跳过 intro（不弹退出确认）
		_intro.skipping = true
		return
	if shell == null:
		return
	if shell.confirm_open():
		shell.close_confirm()
		return
	var page: String = shell.current_page()
	if page == "pause":
		resume_game()
	elif page == "":
		pause_game()
	elif page == "title":
		shell.open_quit_confirm()
	elif page == "gameover":
		to_title()
	else:
		shell.handle_key(KEY_ESCAPE)


## 系统通知入口：Android 返回手势统一路由 + 失焦自动暂停（其余通知忽略）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_android_back_handle()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		# 移动端切后台/来电：对局中自动暂停（specs/mobile-ux-spec §3；桌面 FOCUS_OUT 故意不接）
		if shell != null and not paused and shell.current_page() == "":
			pause_game()


## 设置页震屏开关回调：写配置 + 接线视图层（探针环境仍强制关闭）
func _on_shake_toggled(on: bool) -> void:
	_settings["screen_shake"] = on
	view.core.shake_on = on and not _is_probe_run


## HUD 回调：顶栏模式按钮 → 设置操作模式（肉鸽模式点两次「塔」= 轮换已解锁塔种）
func _on_hud_mode(m: String) -> void:
	if m == "tower" and run != null and run.tower_kinds.size() > 1:
		if mode == "tower":
			tower_pick = (tower_pick + 1) % run.tower_kinds.size()
			run_ui.flash("当前塔：" + _tower_name(_current_tower_kind()))
		set_mode(m)
		return
	set_mode(m)


## 肉鸽模式当前选中的塔 bkind
func _current_tower_kind() -> int:
	if run == null or run.tower_kinds.is_empty():
		return Sim.B_TOWER
	return int(run.tower_kinds[clampi(tower_pick, 0, run.tower_kinds.size() - 1)])


func _tower_name(bk: int) -> String:
	if world == null:
		return "?"
	var d: Dictionary = world.bdef(bk)
	return String(d.get("name", "?"))


## HUD 回调：顶栏暂停按钮 → 进暂停页
func _on_hud_pause() -> void:
	pause_game()


## HUD 回调：顶栏热层按钮 → 威胁热层开关
func _on_hud_heat() -> void:
	toggle_heat()


## HUD 回调：英雄技能按钮 → 下发冲击波命令（冷却/终局守卫在模拟层）
func _on_hud_skill() -> void:
	if world != null and int(world.hero["skill_cd"]) == 0:
		world.apply_command(Command.shock()) # 冷却/终局守卫在模拟层
		view.play_sound("orc_chief_roar.mp3", 0.9)


## HUD 回调：撤销按钮 → 撤销最近一次建造（同 Ctrl+Z）
func _on_hud_undo() -> void:
	do_undo_build()


## HUD 回调：矿工钮 → 即时购买一名矿工（开局成长改造）。
## 上限/缺钱守卫在模拟层（try_buy_worker 零副作用拒单）；到账音沿用收金音。
func _on_hud_worker() -> void:
	if world == null:
		return
	var n_before: int = world.workers.size()
	world.apply_command(Command.worker())
	if world.workers.size() > n_before:
		view.play_sound("gold_collect.mp3", 0.6)


# ---------------- 建造撤销（5s 全额退款；只由玩家输入触发） ----------------

## 记下一次建造（墙线/单塔）：作为「上一步」候选。成功放置才覆盖。
func _remember_build(cells: Array) -> void:
	if cells.is_empty():
		return
	_undo_cells = cells.duplicate()
	_undo_tick = world.tick_count
	if hud != null:
		hud.set_undo_vis(true, ceili(float(World.UNDO_WINDOW_TICKS) / 20.0))


## 撤销是否仍可用（窗口内 + 目标格建筑完好非核心）。
func can_undo_build() -> bool:
	if world == null or _undo_cells.is_empty() or world.outcome != World.RUNNING:
		return false
	if world.tick_count - _undo_tick > World.UNDO_WINDOW_TICKS:
		return false
	for c in _undo_cells:
		var b = world.building_at(c.x, c.y)
		if b == null or int(b["hp"]) <= 0 or int(b["kind"]) == Sim.B_CORE:
			return false
	return true


## 执行撤销：逐格下发 undo_build（模拟层守卫窗口/满血），成功与否都清候选。
func do_undo_build() -> bool:
	var ok := can_undo_build()
	if ok:
		for c in _undo_cells:
			world.apply_command(Command.undo_build(c.x, c.y))
		view.play_sound("building_remove.mp3", 0.6)
		_sync_wall_price()
	_undo_cells = []
	_undo_tick = -99999
	if hud != null:
		hud.set_undo_vis(false)
	return ok


## 撤销候选清空（新局/读档/暂停切页时调用）。
func _reset_undo() -> void:
	_undo_cells = []
	_undo_tick = -99999
	if hud != null:
		hud.set_undo_vis(false)


## 每帧刷新撤销提示：窗口内且有完好目标才亮；到点/失效就熄灭。
func _update_undo_ui() -> void:
	if hud == null or world == null:
		return
	var on := can_undo_build()
	var secs := 0
	if on:
		secs = maxi(1, ceili(float(World.UNDO_WINDOW_TICKS - (world.tick_count - _undo_tick)) / 20.0))
	else:
		_undo_cells = []
	hud.set_undo_vis(on, secs)


## 视觉地标锚点：岩脊/盆地/前哨峰对齐当局玩法图（纯表现层单向；sim 不知道本系统存在）。
## 历史模板：单一岩脊行 + 南向 gate_x；自由路径（ridge_y<0）：预设岩脊关闭 → 岩野山体
## （ridge_pts = 岩群聚类）+ 盆地 2D 凹陷 + 四侧视觉门（gate_pts，仅主口）。
func _visual_anchor() -> Dictionary:
	var gates: Array = []
	var gate_pts: Array = []
	var nm := maxi(sc.spawns.size() - 1, 0) # 主口数（末位 = 盆地口）
	for i in sc.spawns.size():
		var s: Vector2i = sc.spawns[i]
		var wx := float(s.x) - (Dims.MAP_HALF - 0.5) + 0.5 * float(s.y & 1) # 格 x → 世界 x（六边 odd-r：奇行 +0.5）
		var wz := float(s.y) - (Dims.MAP_HALF - 0.5)
		gates.append(wx)
		if i < nm:
			gate_pts.append(Vector2(wx, wz)) # 视觉门只对主口开（盆地口在场内，无外沿豁口）
	var a := { "core": sc.core }
	if sc.ridge_y >= 0:
		a["ridge_y"] = sc.ridge_y + 1 # 历史模板：岩脊地标对齐屏障行
		a["basin_y"] = float(sc.basin_rect.position.y) + float(sc.basin_rect.size.y - 1) * 0.5
		a["gate_x"] = gates
		return a
	var br := sc.basin_rect
	var bcx := float(br.position.x) + float(br.size.x - 1) * 0.5
	var bcy := float(br.position.y) + float(br.size.y - 1) * 0.5
	a["gate_pts"] = gate_pts
	a["ridge_off"] = true
	a["ridge_pts"] = _rock_ridges()
	a["basin_wx"] = bcx - (Dims.MAP_HALF - 0.5) + 0.5 * float(int(round(bcy)) & 1)
	a["basin_wz"] = bcy - (Dims.MAP_HALF - 0.5)
	a["basin_sig"] = float(maxi(br.size.x, br.size.y)) * 0.42
	return a


## 岩野山体锚点：岩群格 → 8×8 桶聚类（n≥6，按强度降序取前 10，同分按桶键）→
## [wx, wz, sigma, amp]；强度 w = min(n/30, 1)：sigma 2.3..4.0m、amp 0.8..1.7m。
## 2026-10-23 随机高度场：视觉山体只覆盖**实际 h≥1** 的岩群（簇内平均高度），
## 避免视觉山包落在玩法平地/坑上（地形起伏已由模拟高度层接管）。
func _rock_ridges() -> Array:
	var b := {}
	for c in sc.rock_cells():
		var cc: Vector2i = c
		@warning_ignore("integer_division")
		var key: int = (cc.x / 8) * 8 + cc.y / 8
		var t: Array = b.get(key, [0, 0.0, 0.0, 0.0])
		t[0] += 1
		t[1] += float(cc.x) - (Dims.MAP_HALF - 0.5) + 0.5 * float(cc.y & 1)
		t[2] += float(cc.y) - (Dims.MAP_HALF - 0.5)
		t[3] += float(sc.height_at(cc.x, cc.y))
		b[key] = t
	var keys: Array = b.keys()
	keys.sort()
	var pts: Array = []
	for key in keys:
		var t: Array = b[key]
		var n: int = int(t[0])
		if n < 6:
			continue
		if float(t[3]) / float(n) < 1.0:
			continue # 平地/坑上的岩群不叠视觉山包（新高度场已给出真实起伏）
		var w := minf(float(n) / 30.0, 1.0)
		pts.append([float(key), float(t[1]) / float(n), float(t[2]) / float(n), 2.3 + 1.7 * w, 0.8 + 0.9 * w])
	pts.sort_custom(func(a: Array, bb: Array) -> bool:
		if a[4] != bb[4]:
			return a[4] > bb[4]
		return a[0] < bb[0])
	if pts.size() > 10:
		pts.resize(10) # 上限：只留最强岩群，避免全图碎包
	var out: Array = []
	for p in pts:
		out.append([p[1], p[2], p[3], p[4]])
	return out


## 开局要用的种子：探针/自检 → 旧口径（基准 + 局号，逐字节不变）；
## 正常游玩 → 设置里的玩家种子，留空则摇一个 31 位正随机（0 已被「随机」占用，故 +1）。
func _auto_seed() -> int:
	if _is_probe_run:
		return BASE_SEED + run_index
	var v := SeedCode.from_text(String(_settings.get("seed_text", "")))
	if v > 0:
		return v
	return randi() % 2147483646 + 1


## 设置里的种子（文字→数字）；探针/自检恒为 0，保证闸的旧口径不掺玩家设置。
func _seed_from_settings() -> int:
	if _is_probe_run:
		return 0
	return SeedCode.from_text(String(_settings.get("seed_text", "")))


## 标题屏种子框回填文本（空串 = 每局随机）。
func _seed_text() -> String:
	return String(_settings.get("seed_text", ""))


## 标题屏种子框改动：清洗（去空白 + 截 24）后写设置缓存；探针模式不落盘（保闸确定性）。
func _on_seed_changed(t: String) -> void:
	_settings["seed_text"] = UserSettings.clean_seed_text(t)
	if not _is_probe_run:
		UserSettings.save_cfg(_settings)


## 按种子建剧本；撞上死图（64 次换盐仍不合法）就 +1 顺延，最多 SEED_RETRY_MAX 次。
## 返回 {"sc": Scenario, "seed": 实际生效的种子}（回落默认图时 seed = 默认种子）。
func _make_scenario(p_seed: int) -> Dictionary:
	var sd := p_seed
	for _attempt in SEED_RETRY_MAX:
		var s := Scenario.new(sd)
		if not s.gen_failed:
			if sd != p_seed:
				print("[Game] 种子顺延 %d → %d" % [p_seed, sd])
			return {"sc": s, "seed": sd}
		sd += 1
	# 256 次全失败：用默认图（Scenario 内部同样回落默认），种子记为默认种子
	print("[Game] 种子顺延 %d → %d" % [p_seed, Scenario.DEFAULT_SEED])
	return {"sc": Scenario.new(Scenario.DEFAULT_SEED), "seed": Scenario.DEFAULT_SEED}


## 种子被顺延时暂存中文提示（两个数字）；HUD 可见时由 _flush_seed_shift_msg 显示。
func _notify_seed_shift(want: int, used: int) -> void:
	_seed_shift_msg = "种子 %d 不可用，已改用 %d" % [want, used]


## 把暂存的顺延提示丢给 HUD（一次性，显示后清空；HUD 未建时留到下次开局）。
func _flush_seed_shift_msg() -> void:
	if _seed_shift_msg.is_empty() or hud == null:
		return
	hud.hint(_seed_shift_msg)
	_seed_shift_msg = ""


## 开新局：局号 +1 → 新玩法地图 + 蓝图视觉 + 世界重置（标题/重开共用）
## p_seed = 0 → 自动取种（探针旧口径 / 玩家种子 / 随机）；>0 → 玩家指定。
func new_game(p_seed: int = 0) -> void:
	run_index += 1
	var want := p_seed if p_seed > 0 else _auto_seed()
	var made: Dictionary = _make_scenario(want)
	sc = made["sc"] # 玩法地图 = 每局一套布局（同种子恒同图，确定性）
	var used: int = made["seed"] # 实际采用的种子（可能被顺延过）
	# 新局先清理上一局的视觉状态，避免热层跨局残留。
	view.set_heat(false)
	var picked: Array = Blueprint.pick(run_index)
	view.apply_blueprint(picked[0], picked[1], _visual_anchor())
	world = World.new(sc, used)
	if hud != null:
		hud.set_seed(used) # HUD 常驻显示本局实际种子（可能是顺延后的）
	view.is_ore = Callable(sc, "is_ore")
	view.build_terrain(world.grid)
	view.sync(world)
	acc = 0.0
	drag_start = Vector2i(-1, -1)
	heat_on = false
	over_shown = false
	if hud != null:
		hud.reset()
		hud.set_heat_vis(false)
	_reset_undo()
	print("[Game] 新对局 run=", run_index, " seed=", used, " sc_seed=", sc.seed)
	if used != want:
		_notify_seed_shift(want, used)


## 限帧：非对局态（标题/暂停/结算，判据同 _camera_free）取 min(玩家上限, 60) 压风扇/GPU；
## 对局态 = 玩家上限（0 = vsync 锁刷新率全速）。探针/自检恒用 0/60 口径（忽略玩家设置，
## 保 gate 确定性）。每帧幂等同步，无状态簿记。
func _sync_fps_cap() -> void:
	var cap: int = 0 if _is_probe_run else UserSettings.fps_cap(_settings) # 显式 int：preload 静态调用退回 Variant 会触发三元类型不兼容警告
	var want := cap
	if not _camera_free():
		want = MENU_FPS if cap <= 0 else mini(cap, MENU_FPS)
	if Engine.max_fps != want:
		Engine.max_fps = want


## 主循环：推进模拟 tick、终局检测、视图同步、HUD 更新
func _process(dt: float) -> void:
	_sync_fps_cap()
	if world == null:
		return
	_sync_run_phase()
	_onboard_tick(dt)
	if world.outcome == World.RUNNING and not paused:
		acc += dt * time_scale
		var steps := 0
		while acc >= TICK_DT and steps < MAX_CATCHUP:
			world.tick()
			_tick_ore_intent()
			if run != null:
				run.after_tick()
				if run.phase != RunState.PHASE_WAVE:
					acc = 0.0 # 阶段已切走：立即停止本帧补步，别让 tick 越过停顿点
					break
			acc -= TICK_DT
			steps += 1
		if steps == MAX_CATCHUP:
			acc = 0.0
	_sync_run_phase() # 循环内可能刚切到 PICK/OVER：同帧把暂停态与 HUD 追上
	_check_outcome()
	view.sync(world, clampf(acc / TICK_DT, 0.0, 1.0), dt) # tick_alpha 供单位/英雄帧间插值，delta 供虫群阻尼
	update_ghost()
	_update_undo_ui()
	_update_camera(dt)
	# 核心低血警告：暂停/标题/终局一律淡出（壳层本就压在上面，淡出是为了回对局时不残留）
	danger.update_hp(int(world.core["hp"]), dt, paused or world.outcome != World.RUNNING)
	if not paused or shell.current_page() == "pause":
		hud.update(world) # 暂停时仍刷（面板静置）；标题/结算下 HUD 已整体隐藏
	shell.update()


## 肉鸽阶段同步：阶段变化即重设暂停态并刷新 HUD（WAVE 之外一律不推进 tick）
func _sync_run_phase() -> void:
	if run == null:
		return
	var ph: int = run.phase
	if ph == _last_run_phase:
		return
	_last_run_phase = ph
	paused = ph != RunState.PHASE_WAVE
	if run_ui != null:
		run_ui.refresh()
	if ph == RunState.PHASE_PICK:
		_open_hex()
	elif hex != null:
		hex.close()


## 展开海克斯三选一（阶段制下唯一会盖满屏幕的交互）
func _open_hex() -> void:
	if hex == null:
		return
	if run == null or run.phase != RunState.PHASE_PICK or run.offers.is_empty():
		hex.close()
		return
	var cost := 0
	if run.refresh_used < RewardPool.REFRESH_COSTS.size():
		cost = int(RewardPool.REFRESH_COSTS[run.refresh_used])
	hex.open(run.offers, {
		"title": "第 %d 层 · 第 %d 波结束 · 选择一项强化" % [run.layer, run.wave_in_layer],
		"supply": run.world.supply,
		"refresh_cost": cost,
		"can_refresh": cost > 0,
	})


## 终局触发（胜/负）：结算屏 + 胜负音 + 结算 BGM；「未暂停且未展示过」时执行一次。
func _check_outcome() -> void:
	if world == null:
		return
	if run != null:
		if run.phase != RunState.PHASE_WON and run.phase != RunState.PHASE_OVER:
			return
		if over_shown:
			return
		over_shown = true
		paused = true
		hud.set_visible_hud(false)
		run_ui.hide_run()
		var ran_won: bool = run.phase == RunState.PHASE_WON
		_persist_stats(ran_won)
		shell.open_gameover(ran_won, world)
		view.play_sound("match_win.mp3" if ran_won else "match_lose.mp3", 0.85)
		view.bgm_settlement(true)
		return
	if world.outcome == World.RUNNING or paused or over_shown:
		return
	over_shown = true
	hud.set_visible_hud(false)
	_persist_stats(world.outcome == World.WON)
	shell.open_gameover(world.outcome == World.WON, world)
	view.play_sound("match_win.mp3" if world.outcome == World.WON else "match_lose.mp3", 0.85)
	view.bgm_settlement(true)


## 相机操控：WASD 平移 / QE 旋转（右键拖拽在 _unhandled_input 里直接跟手）。
## 纯表现层（不进模拟/指纹）；标题、暂停、结算下冻结视角。
func _update_camera(dt: float) -> void:
	camera_control.update(dt) # 键位状态与震屏顺序都搬进了操作层


# ---------------- 输入（移植 main.lua：拖拽放墙/塔、点覆盖层挖矿、点建筑拆除） ----------------

## 输入分发：鼠标按下/抬起（拖拽/点击/右键平移/滚轮缩放）、鼠标移动、键盘（TAB 热层、
## WASD/QE 相机、Esc 路由）、触屏手势（Android：点按建造 / 单指平移 / 双指平移+缩放+旋转）。
## Android 返回键可能以 ui_cancel 动作事件形态抵达，一并路由。
func _unhandled_input(event: InputEvent) -> void:
	# 触屏合成鼠标（device == -1，Godot 内部设备号）在 Android 上会先于 ScreenTouch 抵达，
	# 且每根手指各合成一次（含第二根）——若照单全收，双指手势会在两指落点各造一座塔。
	# 一律丢弃，世界区改由下面的原生触摸分支处理。
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1:
		return
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_onboard_click() # FO 引导：世界区按下 = 跳过当前步
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index, st.position)
		return
	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_touch_drag(sd.index, sd.position, sd.relative)
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_onboard_click() # FO 引导：世界区点击 = 跳过当前步（触屏经鼠标换算同路）
				pointer_down(mb.position)
			else:
				pointer_up(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			var hud_blocked := in_hud_region(mb.position.x, mb.position.y)
			if mb.pressed and drag_start.x >= 0:
				_cancel_drag() # 拖拽中右键 = 取消本次建造（不落子、不进平移）
				camera_control.rmb_button(false, mb.position, hud_blocked)
			else:
				# HUD 区内不启动平移；位置始终刷新（口径不变）
				camera_control.rmb_button(mb.pressed, mb.position, hud_blocked)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			# 中键 = 上下俯仰 / 左右旋转；HUD 区与左键建造拖拽期间不启动
			var mid_blocked := in_hud_region(mb.position.x, mb.position.y) or (mb.pressed and drag_start.x >= 0)
			camera_control.mmb_button(mb.pressed, mb.position, mid_blocked)
		elif (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and mb.pressed:
			if _camera_free() and not in_hud_region(mb.position.x, mb.position.y):
				camera_control.wheel_step(mb.button_index == MOUSE_BUTTON_WHEEL_UP)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		mouse_pos = mm.position
		camera_control.motion(mm.position)
	elif event is InputEventKey:
		var mk: InputEventKey = event
		if mk.echo:
			return
		if not mk.pressed:
			camera_control.key_up(mk.keycode)
			return
		var kc := mk.keycode
		if kc == KEY_ESCAPE or mk.is_action(&"ui_cancel"):
			kc = KEY_ESCAPE # 安卓返回键的键事件形态统一按 Esc 语义路由
		if (mk.ctrl_pressed or mk.meta_pressed) and kc == KEY_Z:
			if do_undo_build():
				return
		if kc == KEY_ESCAPE and drag_start.x >= 0:
			_cancel_drag() # 拖拽中 Esc = 取消本次建造（不落子、不进暂停）
			return
		if shell != null and shell.handle_key(kc):
			return
		if mk.keycode == KEY_TAB:
			toggle_heat()
			return
		camera_control.key_down(mk.keycode)
	elif event.is_action_pressed("ui_cancel"):
		_android_back_handle() # 安卓返回的动作事件形态（非键盘）
		get_viewport().set_input_as_handled()


# ---------------- 触屏手势（Android/iOS）----------------
# 语义：单指点按 = 建造/选择/拆除（与鼠标左键同口径，松手才落子）；
#      单指拖动 = 平移视角（建造模式下 = 拖墙线，平移改用双指）；
#      双指 = 中点位移平移 + 间距变化缩放 + 连线转角旋转（同时生效）。

## 单指按下。墙模式按下即起线（保留实时预览）；其余模式推迟到抬起判定「点按」，
## 这样单指拖动的第一段位移不会被当成建造。
func _touch_down(idx: int, p: Vector2) -> void:
	touch_pts[idx] = p
	if touch_pts.size() == 1:
		touch_mode = "single"
		touch_start = p
		touch_dragging = false
		touch_wall = false
		mouse_pos = p
		if mode == "wall" and _edit_allowed() and not in_hud_region(p.x, p.y):
			var cell: Vector2i = view.pick_cell(p.x, p.y)
			# 只有「这里真能起墙」才算拖线；否则这段拖动归平移（在岩石/水/建筑上滑屏不会白画空线）
			if cell.x >= 0 and mode_valid("wall", cell.x, cell.y):
				drag_start = cell
				touch_wall = true
		return
	# 第二指落下 → 升级为手势：撤销刚起的墙线，本次手势到全部抬指前不再响应单指语义
	if touch_wall:
		_cancel_drag()
		touch_wall = false
	touch_mode = "multi"
	touch_dragging = false
	mouse_pos = Vector2(-1.0, -1.0)
	view.show_ghost([], false, "")
	view.set_focus(Vector2i(-1, -1))
	_gesture_reset()


func _touch_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	if not touch_pts.has(idx):
		return
	touch_pts[idx] = p
	if touch_mode == "multi":
		_gesture_update()
		return
	if touch_mode != "single":
		return
	if not touch_dragging:
		if touch_start.distance_to(p) < TOUCH_SLOP:
			return
		touch_dragging = true
		if not touch_wall:
			mouse_pos = Vector2(-1.0, -1.0) # 判定为平移：撤掉幽灵预览
	if touch_wall:
		mouse_pos = p # 拖线：幽灵线跟手（update_ghost 每帧读 mouse_pos）
		return
	if _camera_free() and not in_hud_region(p.x, p.y):
		view.camera_pan_pixels(rel.x, rel.y)


func _touch_up(idx: int, p: Vector2) -> void:
	touch_pts.erase(idx)
	if touch_mode == "multi":
		if touch_pts.is_empty():
			touch_mode = ""
			mouse_pos = Vector2(-1.0, -1.0)
		return # 双指手势收尾：剩余手指抬起前不再触发建造
	if touch_mode != "single":
		return
	touch_mode = ""
	if touch_wall:
		pointer_up(p) # 提交墙线（内部清 drag_start）
		touch_wall = false
	elif not touch_dragging and not in_hud_region(p.x, p.y):
		pointer_down(p) # 点按：松手才落子
		pointer_up(p)
	mouse_pos = Vector2(-1.0, -1.0) # 手指离开后不留幽灵
	view.show_ghost([], false, "")
	view.set_focus(Vector2i(-1, -1))


## 双指基线（按手指 index 升序取前两根）→ 操作层记录中点/间距/夹角。
func _gesture_reset() -> void:
	camera_control.gesture_reset(touch_pts)


## 双指增量：中点位移 = 平移；间距比 = 缩放（拉开=拉近）；连线转角 = 旋转。
## 单帧幅度都夹住，防抖（实现已搬入操作层）。
func _gesture_update() -> void:
	camera_control.gesture_update(touch_pts)


## 相机操控是否可用（标题/暂停/结算冻结；滚轮缩放与 WASD 同口径）
func _camera_free() -> bool:
	if shell != null and shell.current_page() != "":
		return false
	if run != null:
		return true # 肉鸽模式：INTRO/PICK 停 tick 但仍要能环视战场
	return not paused


## 坐标是否落在 HUD 区域内（点击排除用）
func in_hud_region(x: float, y: float) -> bool:
	if not hud_regions_provider.is_valid():
		return false
	var regions: Array = hud_regions_provider.call()
	for r in regions:
		var rect: Rect2 = r
		if rect.has_point(Vector2(x, y)):
			return true
	return false


## 该格是否已探索（战争迷雾，开局成长改造）：迷雾关/未初始化 = 恒真。
## 未探索不可建/挖/填/挖低；英雄移动豁免——探路正是英雄的职责。
func _cell_explored(x: int, y: int) -> bool:
	if view == null or view.fog == null:
		return true
	return view.fog.is_explored(x, y)


## 模式合法性（口径同母版 mode_valid；非法 = 幽灵红色 + 命令被模拟层守卫拒绝）。
func mode_valid(m: String, x: int, y: int) -> bool:
	if m != "hero" and not _cell_explored(x, y):
		return false # 未探索只许派英雄（幽灵同步变红）
	if m == "wall" or m == "tower":
		var bk: int = Sim.B_WALL if m == "wall" else _current_tower_kind()
		var def: Dictionary = world.bdef(bk)
		if world.supply < int(def["cost"]):
			return false
		if world.tower_cap >= 0 and bk != Sim.B_CORE and world.live_buildings() >= world.tower_cap:
			return false
		if not world.grid.passable(x, y):
			return false
		if world.building_at(x, y) != null:
			return false
		if x == int(world.hero["x"]) and y == int(world.hero["y"]):
			return false
		return world.cell_vacant(x, y)
	elif m == "dig":
		return world.grid.at(x, y) == Grid.COVER
	elif m == "fill" or m == "lower":
		if not world.grid.passable(x, y):
			return false
		if world.building_at(x, y) != null:
			return false
		if not world.cell_vacant(x, y):
			return false
		if x == int(world.hero["x"]) and y == int(world.hero["y"]):
			return false
		var cur: int = world.grid.get_h(x, y)
		if m == "fill":
			return cur < Sim.H_MAX and world.supply >= Sim.FILL_COST
		return cur > Sim.H_MIN and world.supply >= Sim.LOWER_COST
	elif m == "hero":
		return world.grid.passable(x, y)
	elif m == "remove":
		var b = world.building_at(x, y)
		return b != null and int(b["kind"]) != Sim.B_CORE
	return false


## 拖拽线（Bresenham，上限 12 格；口径同母版 line_cells）。
func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var cells: Array = []
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - x0)
	var dy := -absi(b.y - y0)
	var sx := 1 if x0 < b.x else -1
	var sy := 1 if y0 < b.y else -1
	var err := dx + dy
	for _i in 16:
		cells.append(Vector2i(x0, y0))
		if (x0 == b.x and y0 == b.y) or cells.size() >= 12:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return cells


## 设置当前操作模式（墙/塔/挖矿/填/挖/拆/英雄）；换模式即取消未完成的拖拽。
func set_mode(m: String) -> void:
	if m != mode:
		_cancel_drag()
	mode = m
	if hud != null:
		hud.set_mode(m)
	if view != null:
		view.set_hero_range(m == "hero") # 英雄模式显示震荡波半径圈


## 取消当前拖拽（右键/Esc/换模式）：不落子，下一帧预览回到悬停单格。
func _cancel_drag() -> void:
	drag_start = Vector2i(-1, -1)
	if view != null:
		view.show_ghost([], false, "")


# ---------------- 矿格手动开挖（M2-a / DIGGING-SPEC §2.3）----------------
# 矿格是 COVER，不可通行，英雄只能站在六邻开挖。本阶段（M2-a）沿用旧 dig 语义：
# 到达即挖开 + 立即产出，不含 2.5s 进度条（M2-b 才做）。sim 层零改动。

## 该格是否为「尚未挖开的矿格」。
func _is_locked_ore(x: int, y: int) -> bool:
	if world == null or sc == null or not world.grid.inb(x, y):
		return false
	return world.grid.at(x, y) == Grid.COVER and sc.is_ore(x, y)


## 矿格六邻里离英雄最近、可站立且无建筑的一格；无解返回 (-1,-1)。
func _pick_ore_stand(x: int, y: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INT64_MAX
	var hx := int(world.hero["x"])
	var hy := int(world.hero["y"])
	for k in 6:
		var nx: int = Grid.nx(x, y, k)
		var ny: int = Grid.ny(x, y, k)
		if not world.grid.inb(nx, ny) or not world.grid.passable(nx, ny):
			continue
		if world.building_at(nx, ny) != null:
			continue
		var d: int = Grid.hex_dist(nx, ny, hx, hy)
		if d < best_d:
			best_d = d
			best = Vector2i(nx, ny)
	return best


## 下「去挖这一格」的意图：选站位 → 命令英雄前往。
func _order_ore_dig(x: int, y: int) -> bool:
	var stand := _pick_ore_stand(x, y)
	if stand.x < 0:
		return false
	_ore_intent = { "ore": Vector2i(x, y), "stand": stand }
	world.apply_command(Command.hero(stand.x, stand.y))
	return true


## 每 tick 后判定意图：英雄已到矿格邻位 → 代发 dig。
## M2-a 用纯距离判定（路过顺手挖）；M2-b 接入进度条时改为「站定且未移动」。
func _tick_ore_intent() -> void:
	if _ore_intent.is_empty() or world == null:
		return
	var ore: Vector2i = _ore_intent["ore"]
	if not _is_locked_ore(ore.x, ore.y):
		_ore_intent = {} # 已被挖开 / 地形变了：意图作废
		return
	var hx := int(world.hero["x"])
	var hy := int(world.hero["y"])
	if Grid.hex_dist(hx, hy, ore.x, ore.y) > 1:
		return # 还没走到（被顶开/绕路）：保留意图，等英雄靠近
	world.apply_command(Command.dig(ore.x, ore.y))
	_ore_intent = {}


## 在指定格执行当前模式对应的命令（填/挖成功 → 对应地形音；D1-7）。
func apply_mode_at(m: String, x: int, y: int) -> void:
	# 未探索权威拦截（战争迷雾）：sim 不认识探索态，改图命令必须在 view 入口拦下。
	# 英雄豁免（探路）；隔空挖矿的意图单也在这里一并拦住——未探索格连"是不是矿"都不该读。
	if m != "hero" and not _cell_explored(x, y):
		return
	# M2-a：矿格不接受隔空开挖，改为派英雄去邻格（D02）；普通土方保持原口径。
	if m == "dig" and _is_locked_ore(x, y):
		_order_ore_dig(x, y)
		return
	_ore_intent = {} # 任何其它操作都放弃未完成的矿格意图
	var h_before: int = world.grid.get_h(x, y)
	if m == "wall":
		var b_before = world.building_at(x, y) # FO-1 完成判据：真实放墙成功（specs/onboarding-spec）
		world.apply_command(Command.wall(x, y))
		if b_before == null and world.building_at(x, y) != null and _onboard == OnboardStage.WALL:
			_fo_enter_follow()
		return
	if m == "tower" and run != null:
		world.apply_command(Command.build(_current_tower_kind(), x, y))
		return
	# 显式映射：UI 模式名恰好与 kind 同名，但这里不再靠「同名巧合」直接传字符串
	match m:
		"dig": world.apply_command(Command.dig(x, y))
		"tower": world.apply_command(Command.tower(x, y))
		"fill": world.apply_command(Command.fill(x, y))
		"lower": world.apply_command(Command.lower(x, y))
		"remove": world.apply_command(Command.remove(x, y))
		"hero": world.apply_command(Command.hero(x, y))
	if m == "remove":
		_sync_wall_price() # 拆墙回收名额（阶梯价回落）
	if m == "fill" and world.grid.get_h(x, y) > h_before:
		view.play_sound("terrain_fill.mp3", 0.8)
	elif m == "lower" and world.grid.get_h(x, y) < h_before:
		view.play_sound("terrain_lower.mp3", 0.8)


## 批量落子（墙线/单塔）：逐格尝试，成功后把「本次成功格」记为可撤销一步。
func _commit_cells(m: String, cells: Array) -> void:
	var placed: Array = []
	for c in cells:
		var before = world.building_at(c.x, c.y)
		apply_mode_at(m, c.x, c.y)
		var after = world.building_at(c.x, c.y)
		if before == null and after != null:
			placed.append(c)
	if not placed.is_empty():
		_remember_build(placed)
	_sync_wall_price()


## 墙钮动态文案同步（刀②阶梯价）：建/拆/撤销后由 main 驱动 hud（hud 不读世界）。
func _sync_wall_price() -> void:
	if world != null and hud != null:
		hud.set_wall_price(world.wall_price())


## 是否允许编辑战场：肉鸽模式下 INTRO / PICK 阶段虽然不推进 tick，但必须能建造
func _edit_allowed() -> bool:
	if world == null or world.outcome != World.RUNNING:
		return false
	if shell != null and shell.current_page() != "":
		return false
	if not paused:
		return true
	return run != null and run.phase != RunState.PHASE_WAVE


## 鼠标按下：墙记录拖拽起点；塔立即单点落子（不做拖拽线）；其余立即执行单格操作。
func pointer_down(pos: Vector2) -> void:
	mouse_pos = pos
	if not _edit_allowed():
		return
	if in_hud_region(pos.x, pos.y):
		return
	var cell: Vector2i = view.pick_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	if terrain_card != "" and run != null:
		# 地形牌落点同样受迷雾约束（未探索不落牌，牌保留待选）
		if _cell_explored(cell.x, cell.y) and run.use_terrain(terrain_card, cell.x, cell.y):
			terrain_card = ""
			run_ui.refresh()
		return
	if mode == "wall":
		drag_start = cell
	elif mode == "tower":
		_commit_cells("tower", [cell])
	else:
		apply_mode_at(mode, cell.x, cell.y)


## 鼠标抬起：墙拖拽沿 Bresenham 线批量落子；塔/单格模式空转（按下即完成）。
func pointer_up(pos: Vector2) -> void:
	mouse_pos = pos
	if paused and not _edit_allowed():
		drag_start = Vector2i(-1, -1)
		return
	if drag_start.x >= 0:
		var cell: Vector2i = view.pick_cell(pos.x, pos.y)
		if cell.x >= 0 and world.outcome == World.RUNNING:
			_commit_cells("wall", line_cells(drag_start, cell))
		drag_start = Vector2i(-1, -1)


## 幽灵预览（口径同母版 update_ghost；2026-10-20 起墙/塔带实物模型与射程，悬停建筑加焦点环）。
func update_ghost() -> void:
	if not _edit_allowed() or mouse_pos.x < 0.0 or in_hud_region(mouse_pos.x, mouse_pos.y):
		view.show_ghost([], false, "")
		view.set_focus(Vector2i(-1, -1))
		return
	var cell: Vector2i = view.pick_cell(mouse_pos.x, mouse_pos.y)
	if cell.x < 0:
		view.show_ghost([], false, "")
		view.set_focus(Vector2i(-1, -1))
		return
	var hovered = world.building_at(cell.x, cell.y)
	if hovered != null and int(hovered["hp"]) > 0:
		view.set_focus(cell, mode == "remove") # 拆=红，其余=金（可交互提示）
	else:
		view.set_focus(Vector2i(-1, -1))
	if mode == "wall" and drag_start.x >= 0:
		var cells: Array = line_cells(drag_start, cell)
		var is_bad := false
		for c in cells:
			if not mode_valid(mode, c.x, c.y):
				is_bad = true
				break
		view.show_ghost(cells, is_bad, mode)
	else:
		view.show_ghost([cell], not mode_valid(mode, cell.x, cell.y), mode)


## 威胁热层开关（TAB / 顶栏按钮共用；仅进行中——标题/暂停/结算下不响应）。
func toggle_heat() -> void:
	if world == null or (shell != null and shell.current_page() != ""):
		return
	heat_on = not heat_on
	view.set_heat(heat_on)
	if hud != null:
		hud.set_heat_vis(heat_on)
