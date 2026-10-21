extends ProbeKit

# 肉鸽模式竖切探针：跑通 L1–L2 两层、验证状态机 / 奖励 / 威胁升级 / 供给。
# 判定：exit 0 + stdout 含 `[ROGUE] PASS`。
# 无窗口依赖（纯模拟），可 headless 跑。
# bot 策略刻意极简：有钱就在核心南侧补箭塔，只为让流程跑完，不代表平衡。


const MAX_WAVE_TICKS := 1000
const LAYERS_TO_RUN := 2


func _initialize() -> void:
	var run := RunState.new(20261003)
	check(run.layer == 1, "初始层 = 1")
	check(run.phase == RunState.PHASE_INTRO, "初始阶段 = intro")
	check(run.world.btab.size() == 10, "扩展建筑表 10 项")
	check(run.active_gate_count() == 2, "L1 只有 2 个主口可用")

	var waves_done := 0
	var picks_done := 0
	var guard := 0
	while guard < 200:
		guard += 1
		if run.phase == RunState.PHASE_WON or run.phase == RunState.PHASE_OVER:
			break
		if run.layer > LAYERS_TO_RUN and run.phase == RunState.PHASE_LAYER_CLEAR:
			break
		if run.phase == RunState.PHASE_INTRO:
			_bot_build(run)
			run.start_wave()
		elif run.phase == RunState.PHASE_PICK:
			check(run.offers.size() == 3, "三选一必须是 3 张（layer=%d wave=%d）" % [run.layer, run.wave_in_layer])
			var picked: Dictionary = run.pick(0)
			check(not picked.is_empty(), "选牌生效")
			picks_done += 1
			_bot_build(run)
		elif run.phase == RunState.PHASE_WAVE:
			var t0: int = run.world.tick_count
			while run.phase == RunState.PHASE_WAVE and run.world.tick_count - t0 < MAX_WAVE_TICKS:
				run.world.tick()
				run.after_tick()
			waves_done += 1
		elif run.phase == RunState.PHASE_LAYER_CLEAR:
			if run.layer >= LAYERS_TO_RUN:
				break
			run.advance_layer()
			check(run.layer <= LAYERS_TO_RUN, "层级推进正确")
			check(run.world.supply > 0, "层补给已到账")
		else:
			break

	print("[ROGUE] layers=%d waves=%d picks=%d layer_now=%d phase=%s" % [
		run.layer, waves_done, picks_done, run.layer, run.phase_name()])
	print("[ROGUE] kills=%d supply=%d relics=%d talents=%d hand=%d towers=%d" % [
		run.world.kills, run.world.supply, run.relics.size(), run.talents.size(),
		run.hand.size(), run.tower_kinds.size()])

	check(run.layer >= LAYERS_TO_RUN, "至少跑到第 2 层")
	check(waves_done >= 4, "至少打完 4 波（实际 %d）" % waves_done)
	check(picks_done >= 2, "至少选过 2 次牌（实际 %d）" % picks_done)
	check(run.world.outcome == World.RUNNING or run.world.outcome == World.LOST, "结局状态合法")

	# L2 必须已打穿盆地插口（威胁升级生效）
	var plug_open: bool = run.world.grid.at(run.sc.basin_plug.x, run.sc.basin_plug.y) == Grid.OPEN
	check(plug_open, "L2 盆地插口已强制打通")
	check(run.active_gate_count() >= 3, "L2 出怪口增至 3 个（实际 %d）" % run.active_gate_count())

	# 确定性：同种子重跑一遍，波次与击杀数必须一致
	var a := _run_headless(20261003)
	var b := _run_headless(20261003)
	check(a == b, "同种子两遍结果一致（%s vs %s）" % [str(a), str(b)])

	finish("ROGUE")


## 纯流程复跑（不建塔、不选牌，只验证确定性）→ 返回 [层, 波, 击杀, 供给]
func _run_headless(pseed: int) -> Array:
	var run := RunState.new(pseed)
	var waves := 0
	var guard := 0
	while guard < 60:
		guard += 1
		if run.phase == RunState.PHASE_OVER or run.phase == RunState.PHASE_WON:
			break
		if run.phase == RunState.PHASE_INTRO:
			run.start_wave()
		elif run.phase == RunState.PHASE_PICK:
			run.pick(0)
		elif run.phase == RunState.PHASE_WAVE:
			var t0: int = run.world.tick_count
			while run.phase == RunState.PHASE_WAVE and run.world.tick_count - t0 < MAX_WAVE_TICKS:
				run.world.tick()
				run.after_tick()
			waves += 1
		elif run.phase == RunState.PHASE_LAYER_CLEAR:
			run.advance_layer()
		else:
			break
	return [run.layer, waves, run.world.kills, run.world.supply]


## 极简 bot：在核心南侧螺旋找空格补箭塔，直到钱不够
func _bot_build(run: RunState) -> void:
	var w: World = run.world
	var def: Dictionary = w.bdef(RunDefs.B_ARROW)
	var guard := 0
	while w.supply >= int(def["cost"]) and guard < 6:
		guard += 1
		var cell: Vector2i = _find_cell(w)
		if cell.x < 0:
			return
		w.apply_command({ "kind": "build", "bkind": RunDefs.B_ARROW, "x": cell.x, "y": cell.y })


func _find_cell(w: World) -> Vector2i:
	var core: Vector2i = w.sc.core
	for r in range(2, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x: int = core.x + dx
				var y: int = core.y + dy + 5
				if not w.grid.inb(x, y):
					continue
				if not w.grid.passable(x, y):
					continue
				if w.building_at(x, y) != null:
					continue
				if not w.cell_vacant(x, y):
					continue
				if x == int(w.hero["x"]) and y == int(w.hero["y"]):
					continue
				return Vector2i(x, y)
	return Vector2i(-1, -1)
