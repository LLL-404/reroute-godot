extends Node3D

# 《改道》Godot 版主循环：20Hz 固定步长模拟、世界到视图同步与输入分发。
# 对局生命周期统一在这里管理；模拟规则归 sim/，绘制、HUD、页面、音频归 game/ 对应模块。

const Blueprint = preload("res://game/blueprint.gd")
const Selfcheck = preload("res://game/selfcheck.gd")

const TICK_DT := 1.0 / 20.0
const MAX_CATCHUP := 5 # 单帧最多补的 tick 数（追平上限，超出丢弃积压）
const BASE_SEED := 20261003

var view = null # View（preload 脚本实例）；动态引用
var world: World = null
var sc: Scenario = null
var run_index := 0
var acc := 0.0
var paused := true # R1 新局即跑（标题屏 R6 接入后恢复"启动即暂停"口径）
var time_scale := 1.0
var hud = null # HUD（game/hud.gd 实例）
var hud_layer: CanvasLayer
var shell = null # 界面壳（game/screens.gd 实例）
var over_shown := false

# ---- 输入状态（口径同母版 main.lua） ----
var mode := "wall"
var drag_start := Vector2i(-1, -1) # 拖拽起始格
var mouse_pos := Vector2(-1.0, -1.0)
var heat_on := false
## HUD 命中区提供者（R5 注入；未注入 = 无 HUD 区域）
var hud_regions_provider: Callable


func _ready() -> void:
	view = $View
	_setup_hud()
	_setup_shell()
	new_game()
	hud.set_visible_hud(false)
	shell.open_title() # 启动即标题：标题屏压着静态战场（母版口径，paused 初值 true）
	if _is_selfcheck():
		_run_selfcheck()


## 导出包自证触发检测（C8）：`--headless --selfcheck`（引擎参数后或 ++ 后均可）。
func _is_selfcheck() -> bool:
	return OS.get_cmdline_args().has("--selfcheck") or OS.get_cmdline_user_args().has("--selfcheck")


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
	})
	hud_regions_provider = Callable(hud, "hit_regions")
	view.on_float = Callable(hud, "float_bounty")


## 界面壳构建与接线（口径同母版 main.Start：Shell.init 注入回调）。
func _setup_shell() -> void:
	shell = preload("res://game/screens.gd").new()
	shell.name = "Shell"
	add_child(shell)
	shell.init({
		"start_match": Callable(self, "start_match"),
		"restart": Callable(self, "restart_game"),
		"resume": Callable(self, "resume_game"),
		"to_title": Callable(self, "to_title"),
		"pause": Callable(self, "pause_game"),
	}, hud)


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


func pause_game() -> void:
	if world.outcome != World.RUNNING or paused:
		return
	paused = true
	drag_start = Vector2i(-1, -1)
	shell.open_pause()


func resume_game() -> void:
	if not paused:
		return
	paused = false
	shell.resume()


func restart_game() -> void: # 暂停/结算 → 重开一局
	new_game()
	start_match()


func to_title() -> void: # 暂停/结算 → 标题：备一局新的压着静态战场
	paused = true
	drag_start = Vector2i(-1, -1)
	hud.set_visible_hud(false)
	view.bgm(false)
	new_game()
	shell.open_title()


func _on_hud_mode(m: String) -> void:
	set_mode(m)


func _on_hud_pause() -> void:
	pause_game()


func _on_hud_heat() -> void:
	toggle_heat()


func _on_hud_skill() -> void:
	if world != null and int(world.hero["skill_cd"]) == 0:
		world.apply_command({ "kind": "shock" }) # 冷却/终局守卫在模拟层
		view.play_sound("orc_chief_roar.mp3", 0.9)


func new_game() -> void:
	run_index += 1
	sc = Scenario.new()
	# 新局先清理上一局的视觉状态，避免热层跨局残留。
	view.set_heat(false)
	var picked: Array = Blueprint.pick(run_index)
	view.apply_blueprint(picked[0], picked[1])
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
	print("[Game] 新对局 run=", run_index, " seed=", BASE_SEED + run_index)


func _process(dt: float) -> void:
	if world == null:
		return
	if world.outcome == World.RUNNING and not paused:
		acc += dt * time_scale
		var steps := 0
		while acc >= TICK_DT and steps < MAX_CATCHUP:
			world.tick()
			acc -= TICK_DT
			steps += 1
		if steps == MAX_CATCHUP:
			acc = 0.0
	elif not paused and not over_shown:
		over_shown = true
		hud.set_visible_hud(false)
		shell.open_gameover(world.outcome == World.WON, world)
	view.sync(world)
	update_ghost()
	if not paused or shell.current_page() == "pause":
		hud.update(world) # 暂停时仍刷（面板静置）；标题/结算下 HUD 已整体隐藏
	shell.update()


# ---------------- 输入（移植 main.lua：拖拽放墙/塔、点覆盖层挖矿、点建筑拆除） ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				pointer_down(mb.position)
			else:
				pointer_up(mb.position)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		mouse_pos = mm.position
	elif event is InputEventKey:
		var mk: InputEventKey = event
		if mk.pressed and not mk.echo:
			if shell != null and shell.handle_key(mk.keycode):
				return
			if mk.keycode == KEY_TAB:
				toggle_heat()


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
		var def: Dictionary = Sim.BUILDINGS[(Sim.B_WALL if m == "wall" else Sim.B_TOWER) - 1]
		if world.supply < int(def["cost"]):
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


func set_mode(m: String) -> void:
	mode = m
	if hud != null:
		hud.set_mode(m)


func apply_mode_at(m: String, x: int, y: int) -> void:
	world.apply_command({ "kind": m, "x": x, "y": y })


func pointer_down(pos: Vector2) -> void:
	mouse_pos = pos
	if world == null or world.outcome != World.RUNNING or paused:
		return
	if in_hud_region(pos.x, pos.y):
		return
	var cell: Vector2i = view.pick_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	if mode == "wall" or mode == "tower":
		drag_start = cell
	else:
		apply_mode_at(mode, cell.x, cell.y)


func pointer_up(pos: Vector2) -> void:
	mouse_pos = pos
	if paused:
		drag_start = Vector2i(-1, -1)
		return
	if drag_start.x >= 0:
		var cell: Vector2i = view.pick_cell(pos.x, pos.y)
		if cell.x >= 0 and world.outcome == World.RUNNING:
			for c in line_cells(drag_start, cell):
				apply_mode_at(mode, c.x, c.y)
		drag_start = Vector2i(-1, -1)


## 幽灵预览（口径同母版 update_ghost）。
func update_ghost() -> void:
	if world == null or world.outcome != World.RUNNING or paused or mouse_pos.x < 0.0 or in_hud_region(mouse_pos.x, mouse_pos.y):
		view.show_ghost([], false)
		return
	var cell: Vector2i = view.pick_cell(mouse_pos.x, mouse_pos.y)
	if cell.x < 0:
		view.show_ghost([], false)
		return
	if (mode == "wall" or mode == "tower") and drag_start.x >= 0:
		var cells: Array = line_cells(drag_start, cell)
		var is_bad := false
		for c in cells:
			if not mode_valid(mode, c.x, c.y):
				is_bad = true
				break
		view.show_ghost(cells, is_bad)
	else:
		view.show_ghost([cell], not mode_valid(mode, cell.x, cell.y))


## 威胁热层开关（TAB / 顶栏按钮共用；仅进行中——标题/暂停/结算下不响应）。
func toggle_heat() -> void:
	if world == null or (shell != null and shell.current_page() != ""):
		return
	heat_on = not heat_on
	view.set_heat(heat_on)
	if hud != null:
		hud.set_heat_vis(heat_on)
