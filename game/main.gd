extends Node3D

# 《改道》Godot 版主循环：20Hz 固定步长模拟、世界到视图同步与输入分发。
# 对局生命周期统一在这里管理；模拟规则归 sim/，绘制、HUD、页面、音频归 game/ 对应模块。

const Blueprint = preload("res://game/blueprint.gd")
const Selfcheck = preload("res://game/selfcheck.gd")
const UserSettings = preload("res://game/user_settings.gd")
const SaveIO = preload("res://game/save_io.gd")

const TICK_DT := 1.0 / 20.0
const MAX_CATCHUP := 5 # 单帧最多补的 tick 数（追平上限，超出丢弃积压）
const BASE_SEED := 20261003
const CAM_PAN_SPEED := 24.0 # WASD 平移速度（世界单位/秒）
const CAM_ROT_SPEED := 1.5 # Q/E 旋转速度（rad/s）
const CAM_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E] # 相机键（不参与对局操作）
# ---- 触屏手势（Android/iOS；桌面鼠标路径完全不受影响）----
const TOUCH_SLOP := 14.0 # 单指点按判定：位移超过此逻辑像素即视为拖动（平移）
const TOUCH_PINCH_STEP := 0.14 # 双指缩放单帧变化上限（防抖动跳变）
const TOUCH_ROT_DEADZONE := 0.04 # 双指旋转单帧死区（rad；滤手指抖动）
const TOUCH_ROT_LIMIT := 0.5 # 双指旋转单帧上限（rad；两指接近重合时角度噪声过大）
const MENU_FPS := 60 # 菜单/标题/结算限帧（压风扇/GPU）；对局态 = 玩家上限（默认 0 不限，vsync 全速——用户口径 2026-10-17/18）

var view = null # View（preload 脚本实例）；动态引用
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
var cam_keys := {} # 按下的相机键（WASD/QE；事件驱动，无 OS 轮询）
var rmb_panning := false # 右键拖拽平移中
var rmb_last := Vector2.ZERO # 右键拖拽上一帧位置（用位置差算位移，不依赖 relative）
# ---- 触屏手势状态 ----
var touch_pts := {} # 活跃手指 index → 屏幕位置
var touch_mode := "" # "" 空闲 / "single" 单指 / "multi" 双指以上
var touch_start := Vector2.ZERO # 首指落点（点按判定基准）
var touch_dragging := false # 单指已越过 TOUCH_SLOP（判定为拖动）
var touch_wall := false # 本次单指手势正在拖墙线
var _g_prev := Vector2.ZERO # 双指上一帧中点
var _g_dist := 1.0 # 双指上一帧间距
var _g_ang := 0.0 # 双指上一帧连线夹角
## HUD 命中区提供者（R5 注入；未注入 = 无 HUD 区域）
var hud_regions_provider: Callable
var _last_back_ms := 0 # Android 返回键双入口（通知 / ui_cancel 动作）去抖时间戳
var _undo_cells: Array = [] # 最近一次建造（单格/拖拽一条线）的格子；5s 窗口内可全额撤销
var _undo_tick := -99999 # 该次建造的 tick（撤销窗口 = World.UNDO_WINDOW_TICKS）
var _intro = null # 开屏动画层（game/intro.gd；仅冷启动非探针路径创建，播完自毁）
var _settings: Dictionary = {} # 玩家设置缓存（含 runs 跨会话局数；save_cfg 回写）
var _is_probe_run := false # 探针/自检运行：不读不写跨会话局数（保探针确定性与种子口径）
var _ore_intent := {} # M2-a 待开挖矿格意图：{ "ore": Vector2i, "stand": Vector2i }


## 初始化：建 HUD/壳、开新局、显示标题屏；自检模式触发 export 验收
func _ready() -> void:
	view = $View
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
	if _is_probe_run:
		UserSettings.apply_audio(_settings) # 探针只应用音量（显示/画质保持默认，保 gate 截图口径）
	else:
		UserSettings.apply_all(_settings) # 启动即应用玩家设置（音量 bus / 显示模式 / 分辨率 / 垂直同步）
		view.apply_video(_settings) # 画质/渲染缩放/AA/阴影/雾/景深/亮度
		hud.apply_ui_scale(int(_settings.get("ui_pct", 100)))
		shell.apply_ui_scale(int(_settings.get("ui_pct", 100)))
	if not _is_probe_run:
		run_index = maxi(0, int(_settings.get("runs", 0))) # 跨会话续接已玩局数（标题预烘焙不算）
	new_game()
	hud.set_visible_hud(false)
	shell.open_title() # 启动即标题：标题屏压着静态战场（母版口径，paused 初值 true）
	if _is_selfcheck():
		_run_selfcheck()
	elif _intro_enabled():
		_play_intro()


## 弹隐私门：同意 → 落盘 + 走正常启动；不同意 → 退出应用。
func _show_privacy_gate() -> void:
	var gate = load("res://game/privacy_gate.gd").new()
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
	var Intro = load("res://game/intro.gd")
	_intro = Intro.new()
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


## HUD 构建与接线（口径同母版 main.Start：hud.init + 回调注入）。
func _setup_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = preload("res://game/hud.gd").new()
	hud_layer.add_child(hud)
	hud.build({
		"on_mode": Callable(self, "_on_hud_mode"),
		"on_pause": Callable(self, "_on_hud_pause"),
		"on_heat": Callable(self, "_on_hud_heat"),
		"on_skill": Callable(self, "_on_hud_skill"),
		"on_undo": Callable(self, "_on_hud_undo"),
	})
	hud_regions_provider = Callable(hud, "hit_regions")
	view.on_float = Callable(hud, "float_bounty")
	danger = preload("res://game/danger_vignette.gd").new()
	danger.name = "DangerVignette"
	add_child(danger)


## 界面壳构建与接线（口径同母版 main.Start：Shell.init 注入回调）。
func _setup_shell() -> void:
	shell = preload("res://game/screens.gd").new()
	shell.name = "Shell"
	add_child(shell)
	shell.init({
		"start_match": Callable(self, "start_match"),
		"start_rogue": Callable(self, "start_rogue"),
		"restart": Callable(self, "restart_game"),
		"resume": Callable(self, "resume_game"),
		"to_title": Callable(self, "to_title"),
		"pause": Callable(self, "pause_game"),
		"quit": Callable(self, "_quit_game"),
		"load_slot": Callable(self, "load_game"),
		"save_slot": Callable(self, "save_game"),
		"video_changed": Callable(self, "_on_video_changed"),
		"ui_changed": Callable(self, "_on_ui_changed"),
	}, hud)


## 肉鸽 HUD 构建与接线（独立 CanvasLayer，不侵入 hud/screens）
func _setup_run_ui() -> void:
	run_ui = preload("res://game/run_ui.gd").new()
	run_ui.name = "RunUi"
	add_child(run_ui)
	run_ui.init({
		"start_wave": Callable(self, "_run_start_wave"),
		"pick": Callable(self, "_run_pick"),
		"refresh": Callable(self, "_run_refresh"),
		"skip": Callable(self, "_run_skip"),
		"advance": Callable(self, "_run_advance"),
		"use_card": Callable(self, "_run_use_card"),
	}, hud)
	hex = preload("res://game/hex_picker.gd").new()
	hex.name = "HexPicker"
	add_child(hex)
	hex.init({ "sfx": Callable(view, "play_sound") }, hud)


# ---------------- 屏幕流转（页状态 = 游戏状态：进行中 = 空态） ----------------

## 标题 → 对局：用启动/回标题时备好的那局。
func start_match() -> void:
	paused = false
	acc = 0.0
	time_scale = 1.0
	drag_start = Vector2i(-1, -1)
	hud.reset()
	hud.set_visible_hud(true)
	view.bgm(true)
	shell.close_all()
	_persist_runs()


## 开一局肉鸽：新种子 → RunState（内含独立 Scenario + World）→ 切表现层
func start_rogue() -> void:
	run_index += 1
	run = RunState.new(BASE_SEED + run_index)
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
	_reset_undo()
	paused = true # INTRO 阶段：等玩家点开始
	hud.set_visible_hud(true)
	hud.top_bar.visible = false # 经典顶栏的「终局 tick / 波次」在肉鸽局无意义，由 run_ui 接管
	run_ui.show_run(run)
	shell.close_all()
	view.bgm(true)
	print("[Game] 肉鸽开局 seed=", BASE_SEED + run_index)
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
func restart_game() -> void:
	if run != null:
		start_rogue()
		return
	new_game()
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
	new_game()
	shell.open_title()


# ---------------- 存档 / 退出 / Android 返回 ----------------

## 读档开局：还原世界 + 蓝图视觉（Blueprint.pick 按存档 run 重放），直接进对局。
## 坏档/旧档读档失败返回 false（由存档页显示原因）。
func load_game(slot: int) -> bool:
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
	print("[Game] 读档 槽=", slot, " run=", run_index, " tick=", world.tick_count)
	return true


## 存档（仅进行中可存；返回布尔给存档页反馈）。
func save_game(slot: int) -> bool:
	if world == null or world.outcome != World.RUNNING:
		return false
	var ok := SaveIO.save_slot(slot, world, run_index)
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


## 系统通知入口：Android 返回手势统一路由（其余通知忽略）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_android_back_handle()


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
		world.apply_command({ "kind": "shock" }) # 冷却/终局守卫在模拟层
		view.play_sound("orc_chief_roar.mp3", 0.9)


## HUD 回调：撤销按钮 → 撤销最近一次建造（同 Ctrl+Z）
func _on_hud_undo() -> void:
	do_undo_build()


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
			world.apply_command({ "kind": "undo_build", "x": c.x, "y": c.y })
		view.play_sound("building_remove.mp3", 0.6)
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
		var wx := float(s.x) - 31.5 + 0.5 * float(s.y & 1) # 格 x → 世界 x（六边 odd-r：奇行 +0.5）
		var wz := float(s.y) - 31.5
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
	a["basin_wx"] = bcx - 31.5 + 0.5 * float(int(round(bcy)) & 1)
	a["basin_wz"] = bcy - 31.5
	a["basin_sig"] = float(maxi(br.size.x, br.size.y)) * 0.42
	return a


## 岩野山体锚点：岩群格 → 8×8 桶聚类（n≥6，按强度降序取前 10，同分按桶键）→
## [wx, wz, sigma, amp]；强度 w = min(n/30, 1)：sigma 2.3..4.0m、amp 0.8..1.7m。
func _rock_ridges() -> Array:
	var b := {}
	for c in sc.rock_cells():
		var cc: Vector2i = c
		var key: int = (cc.x / 8) * 8 + cc.y / 8
		var t: Array = b.get(key, [0, 0.0, 0.0])
		t[0] += 1
		t[1] += float(cc.x) - 31.5 + 0.5 * float(cc.y & 1)
		t[2] += float(cc.y) - 31.5
		b[key] = t
	var keys: Array = b.keys()
	keys.sort()
	var pts: Array = []
	for key in keys:
		var t: Array = b[key]
		var n: int = int(t[0])
		if n < 6:
			continue
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


## 开新局：局号 +1 → 新玩法地图 + 蓝图视觉 + 世界重置（标题/重开共用）
func new_game() -> void:
	run_index += 1
	sc = Scenario.new(BASE_SEED + run_index) # 玩法地图 = 每局一套布局（与 RNG 种子同源，确定性）
	# 新局先清理上一局的视觉状态，避免热层跨局残留。
	view.set_heat(false)
	var picked: Array = Blueprint.pick(run_index)
	view.apply_blueprint(picked[0], picked[1], _visual_anchor())
	world = World.new(sc, BASE_SEED + run_index)
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
	print("[Game] 新对局 run=", run_index, " seed=", BASE_SEED + run_index, " sc_seed=", sc.seed)


## 限帧：非对局态（标题/暂停/结算，判据同 _camera_free）取 min(玩家上限, 60) 压风扇/GPU；
## 对局态 = 玩家上限（0 = vsync 锁刷新率全速）。探针/自检恒用 0/60 口径（忽略玩家设置，
## 保 gate 确定性）。每帧幂等同步，无状态簿记。
func _sync_fps_cap() -> void:
	var cap := 0 if _is_probe_run else UserSettings.fps_cap(_settings)
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
	}, {
		"pick": Callable(self, "_run_pick"),
		"refresh": Callable(self, "_run_refresh"),
		"skip": Callable(self, "_run_skip"),
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
		shell.open_gameover(ran_won, world)
		view.play_sound("match_win.mp3" if ran_won else "match_lose.mp3", 0.85)
		view.bgm_settlement(true)
		return
	if world.outcome == World.RUNNING or paused or over_shown:
		return
	over_shown = true
	hud.set_visible_hud(false)
	shell.open_gameover(world.outcome == World.WON, world)
	view.play_sound("match_win.mp3" if world.outcome == World.WON else "match_lose.mp3", 0.85)
	view.bgm_settlement(true)


## 相机操控：WASD 平移 / QE 旋转（右键拖拽在 _unhandled_input 里直接跟手）。
## 纯表现层（不进模拟/指纹）；标题、暂停、结算下冻结视角。
func _update_camera(dt: float) -> void:
	if not _camera_free():
		return
	var mvx := 0.0
	var mvy := 0.0
	if cam_keys.has(KEY_D):
		mvx += 1.0
	if cam_keys.has(KEY_A):
		mvx -= 1.0
	if cam_keys.has(KEY_W):
		mvy += 1.0
	if cam_keys.has(KEY_S):
		mvy -= 1.0
	if mvx != 0.0 or mvy != 0.0:
		view.camera_pan(mvx, mvy, CAM_PAN_SPEED * dt)
	var rot := 0.0
	if cam_keys.has(KEY_Q):
		rot += 1.0
	if cam_keys.has(KEY_E):
		rot -= 1.0
	if rot != 0.0:
		view.camera_rotate(rot * CAM_ROT_SPEED * dt)
	# 震屏放最后：pan/rotate 各自会 _apply_cam()，震动必须叠在它们之上，否则被覆盖
	view.update_shake(dt)


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
				pointer_down(mb.position)
			else:
				pointer_up(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and drag_start.x >= 0:
				_cancel_drag() # 拖拽中右键 = 取消本次建造（不落子、不进平移）
				rmb_panning = false
			else:
				rmb_panning = mb.pressed and not in_hud_region(mb.position.x, mb.position.y)
			rmb_last = mb.position
		elif (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and mb.pressed:
			if _camera_free() and not in_hud_region(mb.position.x, mb.position.y):
				view.camera_zoom(0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		mouse_pos = mm.position
		if rmb_panning:
			var d := mm.position - rmb_last
			rmb_last = mm.position
			if d != Vector2.ZERO:
				view.camera_pan_pixels(d.x, d.y)
	elif event is InputEventKey:
		var mk: InputEventKey = event
		if mk.echo:
			return
		if not mk.pressed:
			cam_keys.erase(mk.keycode)
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
		if CAM_KEYS.has(mk.keycode):
			cam_keys[mk.keycode] = true
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


## 双指基线（按手指 index 升序取前两根）。
func _gesture_reset() -> void:
	var ks := touch_pts.keys()
	ks.sort()
	if ks.size() < 2:
		return
	var a: Vector2 = touch_pts[ks[0]]
	var b: Vector2 = touch_pts[ks[1]]
	_g_prev = (a + b) * 0.5
	_g_dist = maxf(a.distance_to(b), 1.0)
	_g_ang = atan2(b.y - a.y, b.x - a.x)


## 双指增量：中点位移 = 平移（抓取感，与右键拖拽同向）；间距比 = 缩放（拉开=拉近）；
## 连线转角 = 旋转（顺时针拧 = 场景顺时针转）。单帧幅度都夹住，防抖。
func _gesture_update() -> void:
	var ks := touch_pts.keys()
	ks.sort()
	if ks.size() < 2:
		return
	var a: Vector2 = touch_pts[ks[0]]
	var b: Vector2 = touch_pts[ks[1]]
	var c := (a + b) * 0.5
	var d := maxf(a.distance_to(b), 1.0)
	var ang := atan2(b.y - a.y, b.x - a.x)
	if _camera_free():
		var dp := c - _g_prev
		if dp != Vector2.ZERO:
			view.camera_pan_pixels(dp.x, dp.y)
		var r := clampf(d / _g_dist, 1.0 - TOUCH_PINCH_STEP, 1.0 + TOUCH_PINCH_STEP)
		if absf(r - 1.0) > 0.002:
			view.camera_zoom(1.0 / r) # 间距变大 = 拉近
		var da := wrapf(ang - _g_ang, -PI, PI)
		if absf(da) > TOUCH_ROT_DEADZONE and absf(da) < TOUCH_ROT_LIMIT:
			view.camera_rotate(da)
	_g_prev = c
	_g_dist = d
	_g_ang = ang


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


## 模式合法性（口径同母版 mode_valid；非法 = 幽灵红色 + 命令被模拟层守卫拒绝）。
func mode_valid(m: String, x: int, y: int) -> bool:
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
	world.apply_command({ "kind": "hero", "x": stand.x, "y": stand.y })
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
	world.apply_command({ "kind": "dig", "x": ore.x, "y": ore.y })
	_ore_intent = {}


## 在指定格执行当前模式对应的命令（填/挖成功 → 对应地形音；D1-7）。
func apply_mode_at(m: String, x: int, y: int) -> void:
	# M2-a：矿格不接受隔空开挖，改为派英雄去邻格（D02）；普通土方保持原口径。
	if m == "dig" and _is_locked_ore(x, y):
		_order_ore_dig(x, y)
		return
	_ore_intent = {} # 任何其它操作都放弃未完成的矿格意图
	var h_before: int = world.grid.get_h(x, y)
	if m == "tower" and run != null:
		world.apply_command({ "kind": "build", "bkind": _current_tower_kind(), "x": x, "y": y })
		return
	world.apply_command({ "kind": m, "x": x, "y": y })
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
		if run.use_terrain(terrain_card, cell.x, cell.y):
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
