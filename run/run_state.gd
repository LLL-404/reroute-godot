class_name RunState
extends RefCounted

# 肉鸽模式编排层：层/波/阶段状态机 + 奖励抽取 + 供给结算。
# 不修改任何 sim 语义：World 的规则、tick 次序、胜负判定全部原样复用；
# 本层只做三件事——
#   ① 接管发波（world.wave_driver = _drive_wave，替代 sc.waves 时间表）
#   ② 接管胜负（sc.end_tick / hard_cap 拉高到不可能达到，核心被毁仍由 World 判 LOST）
#   ③ 在波间停住，等玩家选牌/建造，再由 player 显式 start_wave()
# 阶段口径见 docs/ROGUELIKE-SPEC.md §2。

const PHASE_INTRO := 0 # 层开局：预告威胁，可自由建造，等玩家点「开始」
const PHASE_WAVE := 1 # 波内：世界按 20Hz 推进
const PHASE_PICK := 2 # 波后停住：三选一 + 建造
const PHASE_LAYER_CLEAR := 3 # 层通关结算
const PHASE_WON := 4 # 五层通关
const PHASE_OVER := 5 # 核心被毁

const LAYER_WAVES := [3, 4, 4, 4, 5]
const MAX_LAYER := 5
const WAVE_TICKS := 800 # 单波上限 40 s（清场即提前结束）
const WAVE_MIN_TICKS := 200 # 波最短时长：防出怪口被堵死时误判清场
const LAYER_SUPPLY := 50
const LAYER_CLEAR_SUPPLY := 60
const PICK_SIZE := 3
# Boss 血量倍率（%）：240 血的原型在 L5 会成纸，靠层倍率撑住
const BOSS_HP_PCT := [0, 300, 380, 460, 560, 680]

var seed_val: int
var sc: Scenario
var world: World
var run_rng: Rng

var layer: int
var wave_in_layer: int
var phase: int

var gates: Array # 出怪口（含盆地口，末位恒为盆地口）
var batches: Array # 本波待发批次 [[波内相对 tick, 口下标, 敌型, 数量]]
var batch_i: int
var wave_start: int
var wave_end: int

var unlocked: Array # 已解锁塔卡 id
var tower_kinds: Array # 已解锁塔 bkind（供 HUD 施工）
var relics: Array
var talents: Array
var hand: Array # 地形牌手牌（可重复）

var offers: Array # 当前三选一
var refresh_used: int
var boss_spawned: bool
var threat_info: Dictionary
var log_lines: Array


## 建一局：新地图（同 seed 确定性）+ 扩展建筑表 + 接管发波
func _init(pseed: int) -> void:
	seed_val = pseed
	sc = Scenario.new(pseed)
	sc.waves = [] # 波次由本层接管，清空以关闭 World.run_waves 的时间表路径
	sc.end_tick = 1 << 40 # 拉高：胜负不由 tick 数决定
	sc.hard_cap_tick = 1 << 41
	sc.trickle_every = 0 # 渗怪关闭（威胁升级已显式开新口）
	world = World.new(sc, pseed)
	world.btab = RunDefs.TOWERS.duplicate(true)
	world.wave_driver = Callable(self, "_drive_wave")
	run_rng = Rng.new(pseed ^ 0x5EED)

	layer = 0
	wave_in_layer = 0
	phase = PHASE_INTRO
	gates = sc.spawns.duplicate()
	batches = []
	batch_i = 0
	wave_start = 0
	wave_end = 0
	unlocked = []
	tower_kinds = [RunDefs.B_ARROW] # 箭塔自带，不需要抽卡
	relics = []
	talents = []
	hand = []
	offers = []
	refresh_used = 0
	threat_info = {}
	log_lines = []
	begin_layer()


# ---------------- 层 ----------------

## 进入下一层：发层补给 + 地形威胁升级 + 等玩家点开始
func begin_layer() -> void:
	layer += 1
	wave_in_layer = 0
	world.supply += LAYER_SUPPLY
	if relics.has("r_leyline"):
		world.supply += 80
	# 塔位随层放开：后期「塔位比钱紧」是肉鸽的决策压力来源（规格 §7）
	world.tower_cap = 8 + (layer - 1) * 4
	threat_info = Threat.apply(world, layer)
	var gate: Vector2i = threat_info.get("gate", Vector2i(-1, -1))
	if gate.x >= 0 and layer >= 3:
		gates.append(gate) # L3+ 的新爆破口登记为可用出怪口
	phase = PHASE_INTRO
	log_lines.append("第 %d 层 · %s" % [layer, String(threat_info.get("note", ""))])


## 层通关 → 下一层（UI 点「进入下一层」）
func advance_layer() -> void:
	if phase != PHASE_LAYER_CLEAR:
		return
	begin_layer()


# ---------------- 波 ----------------

## 开一波（UI 点「开始」/ 选牌后自动调用）
func start_wave() -> void:
	if phase != PHASE_INTRO and phase != PHASE_PICK:
		return
	wave_in_layer += 1
	wave_start = world.tick_count
	wave_end = wave_start + WAVE_TICKS
	# 敌人强度随层抬升（spawn_unit 读 sc.wave_scale_pct 缩放 hp）
	sc.wave_scale_pct = 100 + (layer - 1) * 15
	batches = _make_batches()
	batch_i = 0
	boss_spawned = false
	offers = []
	phase = PHASE_WAVE


## 本波出怪批次：三批铺开，避免一次性放完；Boss 波 = 1 只大怪 + 两批随从
func _make_batches() -> Array:
	var out: Array = []
	var n_gate: int = active_gate_count()
	if n_gate <= 0:
		return out
	var boss_wave: bool = wave_in_layer >= int(LAYER_WAVES[clampi(layer - 1, 0, MAX_LAYER - 1)])
	if boss_wave:
		out.append([0, 0, Sim.E_BEHEMOTH, 1])
		out.append([120, 1 % n_gate, Sim.E_SWARM, 4 + layer * 2])
		out.append([320, 2 % n_gate, Sim.E_SWARM, 4 + layer * 2])
		out.append([520, 0, Sim.E_BEHEMOTH, 1])
		return out
	var total: int = 8 + layer * 5
	var per: int = maxi(3, total / 3)
	var base: int = wave_in_layer % n_gate
	out.append([0, base, Sim.E_SWARM, per])
	out.append([180, (base + 1) % n_gate, Sim.E_SWARM, per])
	out.append([360, (base + 2) % n_gate, Sim.E_SWARM, total - per * 2])
	if layer >= 3:
		out.append([540, (base + 1) % n_gate, Sim.E_BEHEMOTH, 1 + (layer - 3)])
	return out


## 当前可用的出怪口数量。L1 只有主口能出（盆地口要等 L2 打穿插口）。
func active_gate_count() -> int:
	if layer <= 1:
		return maxi(1, gates.size() - 1)
	return gates.size()


## wave_driver：由 World.tick() 在「② 波次导演」位置回调，保持 tick 内次序不变
func _drive_wave() -> void:
	var t: int = world.tick_count - wave_start
	while batch_i < batches.size():
		var bt: Array = batches[batch_i]
		if int(bt[0]) > t:
			break
		var gi: int = int(bt[1]) % active_gate_count()
		var before: int = world.units.size()
		world.emit_wave_at(gates[gi], int(bt[2]), int(bt[3]))
		if int(bt[2]) == Sim.E_BEHEMOTH and _is_boss_wave():
			for k in range(before, world.units.size()):
				var bu: Dictionary = world.units[k]
				bu["hp"] = Lua64.idiv(int(bu["hp"]) * int(BOSS_HP_PCT[clampi(layer, 1, MAX_LAYER)]), 100)
		batch_i += 1


## 本波是否层末 Boss 波
func _is_boss_wave() -> bool:
	return wave_in_layer >= int(LAYER_WAVES[clampi(layer - 1, 0, MAX_LAYER - 1)])


## 每 tick 之后由主循环调用：判波结束 / 判终局
func after_tick() -> void:
	if phase != PHASE_WAVE:
		return
	if world.outcome != World.RUNNING:
		phase = PHASE_OVER
		return
	if batch_i >= batches.size() and world.units.size() == 0 and world.tick_count - wave_start >= WAVE_MIN_TICKS:
		_finish_wave()


func _finish_wave() -> void:
	var n: int = int(LAYER_WAVES[clampi(layer - 1, 0, MAX_LAYER - 1)])
	if wave_in_layer >= n:
		world.supply += LAYER_CLEAR_SUPPLY
		if layer >= MAX_LAYER:
			phase = PHASE_WON
		else:
			phase = PHASE_LAYER_CLEAR
		log_lines.append("第 %d 层守住（击杀 %d）" % [layer, world.kills])
		return
	_roll_offers()
	phase = PHASE_PICK


# ---------------- 奖励 ----------------

func _roll_offers() -> void:
	var exclude: Array = []
	exclude.append_array(unlocked)
	exclude.append_array(relics)
	exclude.append_array(talents)
	offers = RewardPool.roll(run_rng, PICK_SIZE, exclude)
	refresh_used = 0


## 花供给刷新三选一（同一次间歇内价格递增）
func refresh_offers() -> bool:
	if phase != PHASE_PICK or refresh_used >= RewardPool.REFRESH_COSTS.size():
		return false
	var cost: int = int(RewardPool.REFRESH_COSTS[refresh_used])
	if world.supply < cost:
		return false
	world.supply -= cost
	refresh_used += 1
	var exclude: Array = []
	exclude.append_array(unlocked)
	exclude.append_array(relics)
	exclude.append_array(talents)
	offers = RewardPool.roll(run_rng, PICK_SIZE, exclude)
	return true


## 选一张（选完立刻开下一波）
func pick(idx: int) -> Dictionary:
	if phase != PHASE_PICK or idx < 0 or idx >= offers.size():
		return {}
	var card: Dictionary = offers[idx]
	_apply_card(card)
	offers = []
	start_wave()
	return card


func _apply_card(card: Dictionary) -> void:
	var cid: String = String(card["id"])
	var kind: String = String(card["kind"])
	if kind == RewardPool.KIND_TOWER:
		unlocked.append(cid)
		tower_kinds.append(int(card["bkind"]))
	elif kind == RewardPool.KIND_RELIC:
		relics.append(cid)
		if cid == "r_convoy":
			world.bounty_shift = 2
	elif kind == RewardPool.KIND_TALENT:
		talents.append(cid)
		if cid == "h_wide":
			world.hero_radius = 5
		elif cid == "h_cd":
			world.hero_cd_max = 250
	elif kind == RewardPool.KIND_TERRAIN:
		hand.append(cid)
	log_lines.append("获得：" + String(card["name"]))


# ---------------- 地形牌 ----------------

## 使用一张地形牌（以 cx,cy 为 3×3 中心）。成功返回 true。
func use_terrain(cid: String, cx: int, cy: int) -> bool:
	var i: int = hand.find(cid)
	if i < 0:
		return false
	var delta: int = 0
	if cid == "g_fault":
		delta = 2
	elif cid == "g_pit":
		delta = -2
	else:
		return false
	_raise_area(cx, cy, delta)
	hand.remove_at(i)
	return true


## 3×3 区域内可通行格整体升降（夹在 H_MIN..H_MAX）；不可通行格跳过。
func _raise_area(cx: int, cy: int, delta: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = cx + dx
			var y: int = cy + dy
			if not world.grid.inb(x, y):
				continue
			if not world.grid.passable(x, y):
				continue
			var h: int = world.grid.get_h(x, y)
			var v: int = clampi(h + delta, Sim.H_MIN, Sim.H_MAX)
			if v != h:
				world.grid.set_h(x, y, v)


# ---------------- 查询 ----------------

## 状态快照（HUD/UI 只读）
func summary() -> Dictionary:
	var wmax: int = int(LAYER_WAVES[clampi(layer - 1, 0, MAX_LAYER - 1)])
	return {
		"layer": layer,
		"layer_max": MAX_LAYER,
		"wave": wave_in_layer,
		"wave_max": wmax,
		"phase": phase,
		"supply": world.supply,
		"unlocked": unlocked.size(),
		"relics": relics.size(),
		"talents": talents.size(),
		"hand": hand.size(),
		"tower_kinds": tower_kinds.duplicate(),
	}


## 阶段名（调试/日志）
func phase_name() -> String:
	match phase:
		PHASE_INTRO:
			return "intro"
		PHASE_WAVE:
			return "wave"
		PHASE_PICK:
			return "pick"
		PHASE_LAYER_CLEAR:
			return "layer_clear"
		PHASE_WON:
			return "won"
		_:
			return "over"
