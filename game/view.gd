extends Node3D

# 3D 视图层（移植 reroute/scripts/view3d.lua）：48² 战场渲染 + 拾取 + 相机取景 + 蓝图配色/雾
# + 实体视觉同步（单位插值/建筑剪影/英雄/死亡消散/震荡环/幽灵/热层）。
# 视图层只读模拟状态，绝不回写；插值用的 prev 格存这里，不进指纹。

const Blueprint = preload("res://game/blueprint.gd")
const ModelsScript = preload("res://game/models.gd")

const CELL_N := 48
const HALF := 24.0
const H_STEP := 1.2 # sim 高度层 1.2m/级

# 取景留边（px 基准）：上让顶栏、右让按钮带、下让提示行（同母版口径）
const RESERVE_TOP := 60.0
const RESERVE_RIGHT := 170.0
const RESERVE_BOTTOM := 28.0

const RING_LIFE := 7 # 震荡波扩散环 0.35s
# 模型路径动作时长（tick，照母版 Z_TICKS：Attack 0.9s / Hurt 0.5s / Death 1.4s）
const Z_ATTACK := 18
const Z_HURT := 10
const Z_DEATH := 28
const Z_YAW := PI / 2.0 # 模型朝向修正（截面校准：模型 yaw=π/2 时头朝 +Z；母版 UrhoX 口径 0 在 Godot 下差 90°）
# 敌人 kind → 资产形态（照母版 view3d.ZFORM：虫群 → blade，蛮兽 → king）
const ZFORM := { 1: 2, 2: 3 }

# 威胁热层：敌人流场"距核心步数"分带染色（d 小=近核心=红，d 大=绕得远=蓝）
const HEAT_N := 6
const HEAT_COLORS := [
	[0.68, 0.13, 0.11],
	[0.64, 0.22, 0.14],
	[0.60, 0.33, 0.15],
	[0.47, 0.36, 0.18],
	[0.22, 0.33, 0.35],
	[0.16, 0.28, 0.45],
]

# 色板（albedo）。ground_lo/ground/ground_hi/rock 每局被蓝图 palette 覆盖；
# gold/rubble 为占位块色（真实资产后续轮替换）。
const MAT := {
	"ground": [0.215, 0.205, 0.170],
	"ground_lo": [0.150, 0.140, 0.115],
	"ground_hi": [0.290, 0.280, 0.235],
	"rock": [0.165, 0.155, 0.145],
	"solid": [0.310, 0.300, 0.270],
	"wall": [0.640, 0.565, 0.420],
	"wall_cap": [0.520, 0.450, 0.330],
	"tower": [0.200, 0.340, 0.620],
	"tower_cap": [0.150, 0.250, 0.470],
	"core": [0.160, 0.760, 0.660],
	"hero": [0.950, 0.790, 0.250],
	"hero_dark": [0.420, 0.340, 0.130],
	"swarm": [0.92, 0.38, 0.30],
	"behemoth": [0.56, 0.22, 0.52],
	"ghost_ok": [0.32, 0.92, 0.42],
	"ghost_bad": [0.95, 0.32, 0.30],
	"gold": [0.86, 0.68, 0.26],
	"rubble": [0.300, 0.280, 0.250],
}

var box_mesh: BoxMesh
var mats: Dictionary = {}
var env: Environment
var sun: DirectionalLight3D

var field_root: Node3D
var world_root: Node3D
var dyn: Node3D = null
var tiles: Node3D
var unit_root: Node3D
var building_root: Node3D
var solids_mmi: MultiMeshInstance3D

var cover_nodes: Dictionary = {} # cellkey -> { node, x, y }
var building_nodes: Dictionary = {} # id -> { node, kind }
var unit_nodes: Dictionary = {} # id -> { node, px, py, s, kind, hp, traveled, pulse }
var death_fx: Array = [] # 死亡消散中的单位条目（放大下沉后移除）
var hero = null # { node, px, py }
var ring = null # { node, born }

var heat_on := false
var heat_root: Node3D = null
var heat_rev := -1
var heat_mats: Array = []
var ghost: Node3D = null
var ghost_mi: MeshInstance3D = null
var ghost_alive := false

var grid: Grid = null
var field_h: PackedFloat64Array
var height_fn: Callable
var cur_palette: Dictionary = {}
var is_ore: Callable
var models = null # 真实资产模型管理器（ModelsScript 实例；_ready 建立）

## 击杀赏金浮字回调（R5 HUD 注入 (sx, sy, text)；未注入即空转）
var on_float: Callable

var camera: Camera3D
var _fit: Dictionary = {}
var _fit_w := 0.0
var _fit_h := 0.0

var _height_rev := -1
var _hero_cd := 0
var _units_n := 0
var _horn_tick := -999
var _stat_field := 0
var _stat_ring := 0
var _stat_solids := 0
var _stat_heat := 0

# ---- 音频（母版三件套：4 轮换特效源 + 常驻环境音 + 对局 BGM）----
const SFX_POOL_N := 4 # 母版 4 个轮换源，避免同帧多音互相掐断
const AUDIO_DIR := "res://assets/audio/sfx/"

var sfx_players: Array = [] # 轮换池（AudioStreamPlayer ×4）
var sfx_amb: AudioStreamPlayer = null # 常驻环境源（循环）
var bgm_player: AudioStreamPlayer = null # 对局 BGM 源
var bgm_on := false # 诊断：BGM 开关态（探针用）
var audio_on := true # headless 跳过实际播放（Dummy 驱动；见 _setup_audio 注释）
var sfx_log: Dictionary = {} # 诊断计数：文件名 → 播放次数（探针用，生产无害）
var _sfx_next := 0 # 轮换下标
var _streams: Dictionary = {} # 流缓存（每文件 load 一次）


func _ready() -> void:
	models = ModelsScript.new()
	box_mesh = BoxMesh.new()
	box_mesh.size = Vector3.ONE

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.24, 0.23, 0.215)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.52, 0.48)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.305, 0.285, 0.265)
	env.fog_depth_begin = 55.0
	env.fog_depth_end = 170.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	add_child(sun)

	for k in MAT:
		var c: Array = MAT[k]
		mats[k] = make_material(c[0], c[1], c[2], [0.10, 0.55, 0.48] if k == "core" else null)

	field_root = Node3D.new()
	field_root.name = "Field"
	add_child(field_root)
	world_root = Node3D.new()
	world_root.name = "WorldRing"
	add_child(world_root)

	is_ore = func(_x: int, _y: int) -> bool: return false

	# 首次地貌：canyon（同母版 View.init；逐局由 main.new_game 换装）
	apply_blueprint(Blueprint.get_preset("canyon"), 0)
	_ensure_camera()
	fit_camera()
	_setup_audio()


## 创建标准 PBR 材质（可选自发光）
func make_material(r: float, g: float, b: float, emissive: Variant = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(r, g, b, 1.0)
	m.metallic = 0.0
	m.roughness = 0.65
	if emissive != null:
		var e: Array = emissive
		m.emission_enabled = true
		m.emission = Color(e[0], e[1], e[2], 1.0)
	return m


## 在 parent 下添加一个盒体部件（位置 + 缩放 + 材质名）
func _part(parent: Node3D, px: float, py: float, pz: float, sx: float, sy: float, sz: float, matname: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh
	mi.material_override = mats[matname]
	mi.position = Vector3(px, py, pz)
	mi.scale = Vector3(sx, sy, sz)
	parent.add_child(mi)


# ---- 坐标映射 ----

## 格子坐标 → 世界坐标（格中心）
func cell_to_world(x: int, y: int) -> Vector3:
	return Vector3(float(x) - HALF + 0.5, 0.0, float(y) - HALF + 0.5)


## 世界坐标 → 格子坐标；界外返回 (-1, -1)
func world_to_cell(wx: float, wz: float) -> Vector2i:
	var cx := int(floor(wx + HALF))
	var cy := int(floor(wz + HALF))
	if cx < 0 or cy < 0 or cx >= CELL_N or cy >= CELL_N:
		return Vector2i(-1, -1)
	return Vector2i(cx, cy)


## 世界坐标 → 视觉地面高度（连续；只在建柱/环带时用；逐帧贴地走 ground_y 查表）
func ground_h(wx: float, wz: float) -> float:
	if height_fn.is_null():
		return 0.0
	return height_fn.call(wx, wz)


## 格子 → 该格视觉地面高度（蓝图预计算 + sim 高度层 1.2m/级；单位/建筑/英雄贴地全走这里）
func ground_y(x: int, y: int) -> float:
	if field_h.is_empty():
		return 0.0
	var gy := field_h[y * CELL_N + x]
	if grid != null:
		gy += float(grid.get_h(x, y)) * H_STEP
	return gy


# ---- 蓝图 / 地形 ----

## 应用蓝图：换高度函数与场内高表、重建地形柱带与环带、重刷配色与雾。（R1 一次 + 每局一次）
func apply_blueprint(bp: Dictionary, seed: int) -> void:
	var composed: Array = Blueprint.compose(bp, seed)
	height_fn = composed[0]
	cur_palette = composed[1]

	# 场内 48² 格高表：单位/建筑/幽灵/拾取的贴地全走这里
	field_h = PackedFloat64Array()
	field_h.resize(CELL_N * CELL_N)
	for y in CELL_N:
		for x in CELL_N:
			var w := cell_to_world(x, y)
			field_h[y * CELL_N + x] = height_fn.call(w.x, w.z)

	# 地形相关配色（palette；墙体/单位等其余材质不归蓝图管）
	for k in ["ground_lo", "ground", "ground_hi", "rock"]:
		var c: Array = cur_palette[k]
		mats[k] = make_material(c[0], c[1], c[2])

	if env != null:
		var fog: Array = cur_palette["fog"]
		env.fog_light_color = Color(fog[0], fog[1], fog[2])
		env.fog_depth_begin = float(cur_palette["fog_start"])
		env.fog_depth_end = float(cur_palette["fog_end"])
		env.background_color = Color(fog[0] * 0.80, fog[1] * 0.80, fog[2] * 0.84)

	_rebuild_field()
	_rebuild_ring()


## 重建战场柱带（三档高程分色）+ 外围环带（同一高度函数保证衔接）。
func _rebuild_field() -> void:
	for c in field_root.get_children():
		c.free()
	var bands := { "ground_lo": [], "ground": [], "ground_hi": [] }
	var lo_at: float = float(cur_palette["band_lo_at"])
	var hi_at: float = float(cur_palette["band_hi_at"])
	for y in CELL_N:
		for x in CELL_N:
			var h := field_h[y * CELL_N + x]
			if grid != null:
				h += float(grid.get_h(x, y)) * H_STEP
			var band := "ground"
			if h < lo_at:
				band = "ground_lo"
			elif h > hi_at:
				band = "ground_hi"
			var w := cell_to_world(x, y)
			bands[band].append([Vector3(w.x, (h - 2.5) / 2.0, w.z), Vector3(1.0, h + 2.5, 1.0)])
	var total := 0
	for band in ["ground_lo", "ground", "ground_hi"]:
		var arr: Array = bands[band]
		var mmi := _make_multimesh(arr, mats[band])
		mmi.name = "Band_" + band
		field_root.add_child(mmi)
		total += arr.size()
	_stat_field = total


## 重建外围环带（两圈：近圈贴战场边缘、远圈延展地平线）
func _rebuild_ring() -> void:
	for c in world_root.get_children():
		c.free()
	var insts: Array = []
	_collect_ring(insts, -50, 50, 2, HALF - 0.5)
	_collect_ring(insts, -150, 150, 6, 50.0)
	var mmi := _make_multimesh(insts, mats["rock"])
	mmi.name = "Ring"
	world_root.add_child(mmi)
	_stat_ring = insts.size()


## 收集环带方块实例（界外距离 > inner 的格位）
func _collect_ring(out: Array, lo: int, hi: int, step: int, inner: float) -> void:
	for wz in range(lo, hi + 1, step):
		for wx in range(lo, hi + 1, step):
			if float(maxi(absi(wx), absi(wz))) > inner:
				var h := ground_h(float(wx), float(wz))
				out.append([Vector3(float(wx), (h - 6.0) / 2.0, float(wz)), Vector3(float(step), h + 6.0, float(step))])


## 构建 MultiMeshInstance3D（实例数组 + 材质）
func _make_multimesh(insts: Array, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box_mesh
	mm.instance_count = insts.size()
	for i in insts.size():
		var it: Array = insts[i]
		var pos: Vector3 = it[0]
		var scl: Vector3 = it[1]
		var xf := Transform3D.IDENTITY.scaled(scl)
		xf.origin = pos
		mm.set_instance_transform(i, xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


## 铺一局的动态内容：覆盖层、Solid 与实体容器；仅换局时整体重建。
func build_terrain(pgrid: Grid) -> void:
	grid = pgrid
	_height_rev = grid.height_rev
	_rebuild_field() # 战场柱顶与单位 ground_y 使用同一份模拟高度

	if dyn != null:
		dyn.free()
	dyn = Node3D.new()
	dyn.name = "Dyn"
	add_child(dyn)
	tiles = Node3D.new()
	tiles.name = "Tiles"
	dyn.add_child(tiles)
	unit_root = Node3D.new()
	unit_root.name = "Units"
	dyn.add_child(unit_root)
	building_root = Node3D.new()
	building_root.name = "Buildings"
	dyn.add_child(building_root)
	cover_nodes = {}
	building_nodes = {}
	unit_nodes = {}
	death_fx = []
	ring = null
	hero = null
	ghost = null
	ghost_mi = null
	ghost_alive = false
	_hero_cd = 0
	_units_n = 0
	_horn_tick = -999

	var solid_insts: Array = []
	for y in grid.h:
		for x in grid.w:
			var c := grid.at(x, y)
			if c == Grid.SOLID:
				var w := cell_to_world(x, y)
				var gy := ground_y(x, y)
				solid_insts.append([Vector3(w.x, gy + 0.8, w.z), Vector3(1.0, 1.6, 1.0)])
			elif c == Grid.COVER:
				_make_cover(x, y)

	solids_mmi = _make_multimesh(solid_insts, mats["solid"])
	solids_mmi.name = "Solids"
	dyn.add_child(solids_mmi)
	_stat_solids = solid_insts.size()


## 覆盖层（真实资产）：矿格 = 砂金堆满档（挖开即随覆盖层移除）；
## 表土/插口 = 瓦砾堆 3 变体（(x*7 + y*13) % 3 确定性取模，同母版口径）。
func _make_cover(x: int, y: int) -> void:
	var w := cell_to_world(x, y)
	var gy := ground_y(x, y)
	var node: Node3D
	if is_ore.call(x, y):
		node = models.spawn_gold(tiles, Vector3(w.x, gy, w.z))
	else:
		var variant: int = (x * 7 + y * 13) % 3
		node = models.spawn_rubble(tiles, variant, Vector3(w.x, gy, w.z), 0.94)
	cover_nodes[x * 1000 + y] = { "node": node, "x": x, "y": y }


# ---- 威胁热层 ----

## 开关威胁热层（关时立即移除热层节点）
func set_heat(on: bool) -> void:
	heat_on = on
	if not on:
		if heat_root != null:
			heat_root.free()
			heat_root = null
		heat_rev = -1
		_stat_heat = 0


## 热层是否开启
func heat_enabled() -> bool:
	return heat_on


## 按 grid.rev 重建热层板（rev 变 = 落墙/挖矿/填挖）。
func rebuild_heat(pworld: World) -> void:
	if heat_root != null:
		heat_root.free()
		heat_root = null
	var dists := PackedInt32Array()
	dists.resize(CELL_N * CELL_N)
	var maxd := 0
	for y in CELL_N:
		for x in CELL_N:
			var d := pworld.field.dist_at(x, y)
			if d > maxd:
				maxd = d
			dists[y * CELL_N + x] = d
	heat_rev = pworld.grid.rev
	_stat_heat = 0
	if maxd <= 0:
		return
	heat_root = Node3D.new()
	heat_root.name = "Heat"
	add_child(heat_root)
	var groups: Array = []
	for _i in HEAT_N:
		groups.append([])
	if heat_mats.is_empty():
		for c in HEAT_COLORS:
			heat_mats.append(make_material(c[0], c[1], c[2]))
	for y in CELL_N:
		for x in CELL_N:
			var d := dists[y * CELL_N + x]
			if d >= 0:
				var band := mini(HEAT_N, 1 + (d * HEAT_N) / (maxd + 1))
				var arr: Array = groups[band - 1]
				var w := cell_to_world(x, y)
				arr.append([Vector3(w.x, ground_y(x, y) + 0.05, w.z), Vector3(0.94, 0.05, 0.94)])
	for i in HEAT_N:
		var arr2: Array = groups[i]
		var mmi := _make_multimesh(arr2, heat_mats[i])
		mmi.name = "H" + str(i + 1)
		heat_root.add_child(mmi)
		_stat_heat += arr2.size()


# ---- 幽灵预览 ----

## cells = Array[Vector2i] 或空（藏起）；bad = 有效性染色。
func show_ghost(cells: Array, bad: bool = false) -> void:
	if cells.is_empty():
		if ghost_alive and ghost != null:
			ghost.free()
		ghost = null
		ghost_mi = null
		ghost_alive = false
		return
	if not ghost_alive or ghost == null:
		ghost = Node3D.new()
		ghost.name = "Ghost"
		ghost_mi = MeshInstance3D.new()
		ghost_mi.mesh = box_mesh
		ghost.add_child(ghost_mi)
		dyn.add_child(ghost)
		ghost_alive = true
	var first: Vector2i = cells[0]
	var last: Vector2i = cells[cells.size() - 1]
	var fw := cell_to_world(first.x, first.y)
	var lw := cell_to_world(last.x, last.y)
	var cx := (fw.x + lw.x) / 2.0
	var cz := (fw.z + lw.z) / 2.0
	var sx := maxf(absf(lw.x - fw.x), 0.9) + 0.06
	var sz := maxf(absf(lw.z - fw.z), 0.9) + 0.06
	var gy := maxf(ground_y(first.x, first.y), ground_y(last.x, last.y))
	ghost.position = Vector3(cx, gy + 0.12, cz)
	ghost.scale = Vector3(sx, 0.24, sz)
	ghost_mi.material_override = mats["ghost_bad"] if bad else mats["ghost_ok"]


# ---- 每帧同步 ----

## 每帧同步：地形高度变化重建、热层刷新、覆盖层消失、建筑/英雄/单位/死亡消散/震荡环/相机取景
func sync(world: World) -> void:
	# 仅重建地面柱带；高度增减总和相同也必须刷新，实体缓存不得被清掉。
	if grid != null and grid.height_rev != _height_rev:
		_height_rev = grid.height_rev
		_rebuild_field()
	if heat_on and world.grid.rev != heat_rev:
		rebuild_heat(world)

	# 挖开的覆盖层消失
	for k in cover_nodes.keys():
		var cv: Dictionary = cover_nodes[k]
		if world.grid.at(cv["x"], cv["y"]) != Grid.COVER:
			if is_ore.call(cv["x"], cv["y"]):
				play_sound("mining_gold_hit.mp3", 0.9)
			var nd: Node = cv["node"]
			nd.free()
			cover_nodes.erase(k)

	# 出怪号角：单位数跳升 = 新一波进场上；60 tick 节流防连发
	var n_units := world.units.size()
	if n_units > _units_n and (world.tick_count - _horn_tick) > 60:
		play_sound("orc_chief_roar.mp3", 0.45)
		_horn_tick = world.tick_count
	_units_n = n_units

	# 建筑（剪影：容器贴地 + 多盒组合；施工中整体压扁 0.35，完工弹起）
	var seen_ids := {}
	for b in world.buildings:
		if int(b["hp"]) > 0:
			var bid: int = b["id"]
			seen_ids[bid] = true
			var entry = building_nodes.get(bid)
			if entry == null:
				var node := Node3D.new()
				node.name = "b" + str(bid)
				building_root.add_child(node)
				var kind: int = b["kind"]
				if kind == Sim.B_TOWER:
					_part(node, 0.0, 0.225, 0.0, 1.00, 0.45, 1.00, "tower_cap")
					_part(node, 0.0, 1.300, 0.0, 0.70, 1.70, 0.70, "tower")
					_part(node, 0.0, 2.375, 0.0, 0.94, 0.45, 0.94, "tower_cap")
					_part(node, 0.0, 2.850, 0.0, 0.26, 0.50, 0.26, "hero")
				elif kind == Sim.B_CORE:
					_part(node, 0.0, 0.200, 0.0, 1.15, 0.40, 1.15, "solid")
					_part(node, 0.0, 1.150, 0.0, 0.85, 1.50, 0.85, "core")
					_part(node, 0.0, 2.250, 0.0, 0.45, 0.45, 0.45, "core")
				else:
					_part(node, 0.0, 0.525, 0.0, 0.94, 1.05, 0.94, "wall")
					_part(node, 0.0, 1.190, 0.0, 1.00, 0.28, 1.00, "wall_cap")
				entry = { "node": node, "kind": kind }
				building_nodes[bid] = entry
				if kind != Sim.B_CORE:
					play_sound("build_stone_place.mp3", 0.8)
			var w := cell_to_world(int(b["x"]), int(b["y"]))
			var by := ground_y(int(b["x"]), int(b["y"]))
			var bnode: Node3D = entry["node"]
			bnode.position = Vector3(w.x, by, w.z)
			var k := 0.35 if int(b["build_left"]) > 0 else 1.0
			bnode.scale = Vector3(0.96, k, 0.96)
	for bid2 in building_nodes.keys():
		if not seen_ids.has(bid2):
			var entry2: Dictionary = building_nodes[bid2]
			var nd2: Node = entry2["node"]
			nd2.free()
			building_nodes.erase(bid2)

	# 英雄（腿/躯干/双肩/头 四盒合成，行走起伏 + 朝向；插值口径同单位）
	var h: Dictionary = world.hero
	if h.size() > 0:
		if hero == null:
			var hnode := Node3D.new()
			hnode.name = "hero"
			dyn.add_child(hnode)
			_part(hnode, 0.0, 0.110, 0.0, 0.30, 0.22, 0.22, "hero_dark")
			_part(hnode, 0.0, 0.410, 0.0, 0.36, 0.38, 0.24, "hero")
			_part(hnode, -0.23, 0.600, 0.0, 0.14, 0.14, 0.14, "hero_dark")
			_part(hnode, 0.23, 0.600, 0.0, 0.14, 0.14, 0.14, "hero_dark")
			_part(hnode, 0.0, 0.700, 0.0, 0.20, 0.20, 0.20, "hero")
			hero = { "node": hnode, "px": int(h["x"]), "py": int(h["y"]) }
		var he: Dictionary = hero
		var frac := float((world.tick_count + 1) % int(Sim.HERO["speed_ticks"])) / float(Sim.HERO["speed_ticks"])
		var cw := cell_to_world(int(h["x"]), int(h["y"]))
		var pw := cell_to_world(int(he["px"]), int(he["py"]))
		var ix := pw.x + (cw.x - pw.x) * frac
		var iz := pw.z + (cw.z - pw.z) * frac
		var iy := ground_y(int(he["px"]), int(he["py"])) * (1.0 - frac) + ground_y(int(h["x"]), int(h["y"])) * frac
		var moving := (cw.x != pw.x or cw.z != pw.z)
		var bob := 0.0
		if moving:
			bob = 0.03 * sin(frac * 6.283)
		var hn: Node3D = he["node"]
		hn.position = Vector3(ix, iy + bob, iz)
		if moving:
			hn.rotation = Vector3(0.0, atan2(cw.x - pw.x, cw.z - pw.z), 0.0)
		he["px"] = int(h["x"])
		he["py"] = int(h["y"])

	# 单位（真实模型 + 动作状态机；帧间插值 prev 格存视图层；受击脉冲用 tick 计龄）
	var useen := {}
	for u in world.units:
		if int(u["hp"]) > 0:
			var uid: int = u["id"]
			useen[uid] = true
			var e = unit_nodes.get(uid)
			if e == null:
				var spawn: Dictionary = models.spawn_unit(unit_root, int(ZFORM[int(u["kind"])]))
				var unode: Node3D = spawn["node"]
				unode.name = "u" + str(uid)
				models.play(spawn["player"], "Crawl", true)
				e = {
					"node": unode,
					"player": spawn["player"],
					"px": int(u["x"]),
					"py": int(u["y"]),
					"kind": int(u["kind"]),
					"hp": int(u["hp"]),
					"traveled": 0,
					"pulse": -1,
					"anim_until": -1,
				}
				unit_nodes[uid] = e
			var t: int = world.tick_count
			var player: AnimationPlayer = e["player"]
			if int(u["hp"]) < int(e["hp"]):
				e["pulse"] = t # 塔火命中 → 受击脉冲/受击动作
				e["anim_until"] = t + Z_HURT
				models.play(player, "Hurt", false)
			# 动作状态机：单发到期回 Crawl；围攻中按确定性相位插 Attack（免 Rng）。
			if int(e["anim_until"]) >= 0 and t >= int(e["anim_until"]):
				e["anim_until"] = -1
				models.play(player, "Crawl", true)
			if int(e["anim_until"]) < 0 and int(u["atk_target"]) >= 0 and (t + uid) % 50 == 0:
				e["anim_until"] = t + Z_ATTACK
				models.play(player, "Attack", false)
			var frac2 := float((t + uid) % int(u["speed_ticks"])) / float(u["speed_ticks"])
			var cw2 := cell_to_world(int(u["x"]), int(u["y"]))
			var pw2 := cell_to_world(int(e["px"]), int(e["py"]))
			var ix2 := pw2.x + (cw2.x - pw2.x) * frac2
			var iz2 := pw2.z + (cw2.z - pw2.z) * frac2
			var iy2 := ground_y(int(e["px"]), int(e["py"])) * (1.0 - frac2) + ground_y(int(u["x"]), int(u["y"])) * frac2
			var m := 1.0
			var pulse_i: int = e["pulse"]
			if pulse_i >= 0:
				var a := 1.0 - float(t - pulse_i) / 6.0
				if a > 0.0:
					m = 1.0 + 0.6 * a
				else:
					e["pulse"] = -1
			var und: Node3D = e["node"]
			und.position = Vector3(ix2, iy2 + 0.02, iz2) # 模型底部贴脚点（母版口径）
			und.scale = Vector3(m, m, m)
			var dx := cw2.x - pw2.x
			var dz := cw2.z - pw2.z
			if dx * dx + dz * dz > 1e-9:
				und.rotation = Vector3(0.0, atan2(dx, dz) + Z_YAW, 0.0)
			e["px"] = int(u["x"])
			e["py"] = int(u["y"])
			e["hp"] = int(u["hp"])
			e["traveled"] = int(u["traveled"])
	for uid2 in unit_nodes.keys():
		if not useen.has(uid2):
			var e3: Dictionary = unit_nodes[uid2]
			var kind3: int = e3["kind"]
			play_sound("zerg_death.mp3" if kind3 == Sim.E_SWARM else "orc_death.mp3", 0.85)
			e3["dying"] = world.tick_count
			models.play(e3["player"], "Death", false) # 模型走死亡动画（1.4s），不做放大下沉
			death_fx.append(e3)
			var nd3: Node3D = e3["node"]
			var scr := world_to_screen(nd3.position.x, nd3.position.y, nd3.position.z)
			if scr.x >= 0.0:
				var total: int = int(Sim.ENEMIES[kind3 - 1]["reward"]) + Lua64.lshr(int(e3["traveled"]), Sim.CONVOY_SHIFT)
				_float_bounty(scr, "+" + str(total))
			unit_nodes.erase(uid2)
	update_death_fx(world.tick_count)
	update_shock_ring(world)

	var vp := get_viewport().get_visible_rect().size
	if vp.x > 0.0 and vp.y > 0.0 and (vp.x != _fit_w or vp.y != _fit_h):
		fit_camera()


## 死亡消散：放大下沉后移除（box 路径；模型动画路径在资产轮接入）。
## 死亡消散：模型的死亡动画播完（Z_DEATH = 28 tick = 1.4s）后移除节点。
func update_death_fx(tick: int) -> void:
	for i in range(death_fx.size() - 1, -1, -1):
		var e: Dictionary = death_fx[i]
		var age := tick - int(e["dying"])
		var dn: Node3D = e["node"]
		if age >= Z_DEATH:
			dn.free()
			death_fx.remove_at(i)


## 震荡波扩散环：英雄冷却跳升 = 刚施放；方框环贴地扩散到技能半径后移除。
func update_shock_ring(world: World) -> void:
	var h: Dictionary = world.hero
	if h.size() > 0:
		var hx: int = h["x"]
		var hy: int = h["y"]
		if int(h["skill_cd"]) > _hero_cd:
			var w := cell_to_world(hx, hy)
			var g := Node3D.new()
			g.name = "shockring"
			g.position = Vector3(w.x, ground_y(hx, hy), w.z)
			var edges := [
				{ "x": 0.0, "z": 1.0, "sx": 2.0, "sz": 0.08 },
				{ "x": 0.0, "z": -1.0, "sx": 2.0, "sz": 0.08 },
				{ "x": 1.0, "z": 0.0, "sx": 0.08, "sz": 2.0 },
				{ "x": -1.0, "z": 0.0, "sx": 0.08, "sz": 2.0 },
			]
			for i in edges.size():
				var ed: Dictionary = edges[i]
				var n := MeshInstance3D.new()
				n.mesh = box_mesh
				n.material_override = mats["hero"]
				n.position = Vector3(float(ed["x"]), 0.12, float(ed["z"]))
				n.scale = Vector3(float(ed["sx"]), 0.08, float(ed["sz"]))
				g.add_child(n)
			dyn.add_child(g)
			ring = { "node": g, "born": world.tick_count }
		_hero_cd = int(h["skill_cd"])
	if ring != null:
		var rn: Node3D = ring["node"]
		var k := float(world.tick_count - int(ring["born"])) / float(RING_LIFE)
		if k >= 1.0:
			rn.free()
			ring = null
		else:
			rn.scale = Vector3(0.3 + 2.7 * k, 1.0, 0.3 + 2.7 * k)


# ---- 相机取景 ----

## 确保相机存在（懒创建）
func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 45.0
	camera.near = 1.0
	camera.far = 400.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)


## 取景：把 48² 地图撑满可交互区（上让 60px、右让 170px、下让提示行；口径同母版闭式推导）。
## 二分俯角找"宽、深同时贴边"的平衡点（夹在 [35°,50°]），再解视距与竖向平移。
func fit_camera() -> void:
	_ensure_camera()
	var vp := get_viewport().get_visible_rect().size
	var W := vp.x
	var H := vp.y
	if W <= 0.0 or H <= 0.0:
		W = 1280.0
		H = 720.0
	var S := clampf(H / 816.0, 1.0, 1.6)
	var t45 := tan(deg_to_rad(45.0) / 2.0)
	var aspect := W / H
	var half_w := maxf(1.0 - 2.0 * RESERVE_RIGHT * S / W, 0.3)
	var y_b := -1.0 + 2.0 * RESERVE_BOTTOM * S / H
	var y_t := 1.0 - 2.0 * RESERVE_TOP * S / H
	var bc := (y_b + y_t) / 2.0
	var R := HALF

	var p_lo := deg_to_rad(35.0)
	var p_hi := deg_to_rad(50.0)
	for _i in 12:
		var pm := (p_lo + p_hi) / 2.0
		var zc := R * cos(pm)
		var yc := R * sin(pm)
		var s_w := R / (half_w * t45 * aspect) + zc
		var lo := zc + 0.5
		var hi := 600.0
		for _j in 40:
			var mid := (lo + hi) / 2.0
			var zn := mid - zc
			var zf := mid + zc
			var hval := (-yc / (zn * t45) - y_b) * zn - (yc / (zf * t45) - y_t) * zf
			if hval >= 0.0:
				hi = mid
			else:
				lo = mid
		if s_w >= hi:
			p_lo = pm
		else:
			p_hi = pm

	var p := p_lo
	var sr := sin(p)
	var cr := cos(p)
	var zc2 := R * cr
	var yc2 := R * sr
	var s := R / (half_w * t45 * aspect) + zc2
	var zn2 := s - zc2
	var zf2 := s + zc2
	var yn := -yc2 / (zn2 * t45)
	var yf := yc2 / (zf2 * t45)
	var off := t45 * ((yn + yf) / 2.0 - bc) * 2.0 / (1.0 / zn2 + 1.0 / zf2)

	camera.position = Vector3(0.0, s * sr + off * cr, s * cr - off * sr)
	camera.look_at(camera.position + Vector3(0.0, -sr * 100.0, -cr * 100.0))
	_fit = {
		"px": 0.0,
		"py": s * sr + off * cr,
		"pz": s * cr - off * sr,
		"fy": -sr,
		"fz": -cr,
		"uy": cr,
		"uz": -sr,
		"t45": t45,
		"a": aspect,
	}
	_fit_w = W
	_fit_h = H


## 世界坐标 → 屏幕像素（赏金浮字用）。视轴后方返回 Vector2(-1, -1)。
func world_to_screen(wx: float, wy: float, wz: float) -> Vector2:
	if _fit.is_empty():
		return Vector2(-1, -1)
	var dx := wx - float(_fit["px"])
	var dy := wy - float(_fit["py"])
	var dz := wz - float(_fit["pz"])
	var depth := dy * float(_fit["fy"]) + dz * float(_fit["fz"])
	if depth <= 0.1:
		return Vector2(-1, -1)
	var nx := dx / (depth * float(_fit["t45"]) * float(_fit["a"]))
	var ny := (dy * float(_fit["uy"]) + dz * float(_fit["uz"])) / (depth * float(_fit["t45"]))
	var vp := get_viewport().get_visible_rect().size
	return Vector2((nx + 1.0) * 0.5 * vp.x, (1.0 - ny) * 0.5 * vp.y)


## 拾取：屏幕坐标（像素）→ 战场格。地面有程序化起伏：先按 y=0 求交，取命中格高度再求交，
## 两轮收敛（地势 ±1.2m、俯角 ≥35° 足够）。返回 Vector2i(-1,-1) = 未命中。
## 注意：Godot 的 project_ray_* 取像素坐标（非 0..1 归一化；传小值会被当左上角像素 → 射线全偏）。
func pick_cell(screen_x: float, screen_y: float) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var pt := Vector2(screen_x, screen_y)
	var origin := camera.project_ray_origin(pt)
	var dir := camera.project_ray_normal(pt)
	if absf(dir.y) < 0.001:
		return Vector2i(-1, -1)
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	for _i in 2:
		var cell := world_to_cell(origin.x + dir.x * t, origin.z + dir.z * t)
		var gh := 0.0
		if cell.x >= 0:
			gh = ground_y(cell.x, cell.y)
		var t2 := -(origin.y - gh) / dir.y
		if t2 <= 0.0:
			break
		t = t2
	return world_to_cell(origin.x + dir.x * t, origin.z + dir.z * t)


# ---- 音频（母版 view3d.lua：SFX 轮换池 / 常驻环境音 / 对局 BGM）----

## 建音频三件套：4 轮换特效源 + 1 常驻环境源（循环）+ BGM 源。
## 环境音自 View 初始化即播（标题屏只留环境音）；BGM 由 main 经 bgm() 开关。
## headless（Dummy 音频驱动）跳过实际播放：听不见，且退出的播放对象回收存在竞态
## （ObjectDB 泄漏 + resources still in use，实测）——接口/资源/状态断言照常可测。
func _setup_audio() -> void:
	audio_on = DisplayServer.get_name() != "headless"
	var sroot := Node.new()
	sroot.name = "SFX"
	add_child(sroot)
	for i in SFX_POOL_N:
		var p := AudioStreamPlayer.new()
		p.name = "sfx" + str(i + 1)
		sroot.add_child(p)
		sfx_players.append(p)
	sfx_amb = AudioStreamPlayer.new()
	sfx_amb.name = "amb"
	sroot.add_child(sfx_amb)
	var amb: AudioStream = _load_stream("dungeon_ambience.mp3")
	if amb != null:
		var amb_mp3 := amb as AudioStreamMP3
		if amb_mp3 != null:
			amb_mp3.loop = true
		sfx_amb.stream = amb
		sfx_amb.volume_db = linear_to_db(0.22)
		if audio_on:
			sfx_amb.play()
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "bgm"
	sroot.add_child(bgm_player)


## 音频流缓存加载（文件/导入缺失静默返回 null——音频缺失绝不能停对局）。
func _load_stream(fname: String) -> AudioStream:
	if _streams.has(fname):
		return _streams[fname] as AudioStream
	var path := AUDIO_DIR + fname
	if not ResourceLoader.exists(path):
		_streams[fname] = null
		return null
	var s: AudioStream = load(path) as AudioStream
	_streams[fname] = s
	return s


## 播一个音效（assets/audio/sfx/ 下文件名）；轮换池避免同帧多音互相掐断。
func play_sound(sname: String, gain: float = 0.8) -> void:
	if sfx_players.is_empty():
		return
	var s: AudioStream = _load_stream(sname)
	if s == null:
		return
	var p: AudioStreamPlayer = sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % sfx_players.size()
	p.stream = s
	p.volume_db = linear_to_db(gain)
	if audio_on:
		p.play()
	sfx_log[sname] = int(sfx_log.get(sname, 0)) + 1


## 对局 BGM 开关（bgm_reroute.mp3，looped；曲子缺失静默）。
func bgm(enabled: bool) -> void:
	if bgm_player == null:
		return
	bgm_on = enabled
	if enabled:
		var s: AudioStream = _load_stream("bgm_reroute.mp3")
		if s == null:
			return
		var s_mp3 := s as AudioStreamMP3
		if s_mp3 != null:
			s_mp3.loop = true
		bgm_player.stream = s
		bgm_player.volume_db = linear_to_db(0.34)
		if audio_on:
			bgm_player.play()
	else:
		bgm_player.stop()


## 全停音频并解绑流（退出收尾用：带活动播放对象直接 quit 会报 Playback 泄漏/资源占用）。
func stop_all_audio() -> void:
	if sfx_amb != null:
		sfx_amb.stop()
		sfx_amb.stream = null
	for p in sfx_players:
		var ap: AudioStreamPlayer = p
		ap.stop()
		ap.stream = null
	if bgm_player != null:
		bgm_player.stop()
		bgm_player.stream = null


## 击杀赏金浮字回调（转发给 HUD）
func _float_bounty(scr: Vector2, text: String) -> void:
	if on_float.is_valid():
		on_float.call(scr.x, scr.y, text)


## 探针用统计（C1/C2 判定）。
func debug_stats() -> Dictionary:
	return {
		"field": _stat_field,
		"ring": _stat_ring,
		"solids": _stat_solids,
		"covers": cover_nodes.size(),
		"cam": camera != null,
		"units": unit_nodes.size(),
		"buildings": building_nodes.size(),
		"death_fx": death_fx.size(),
		"hero": hero != null,
		"ring_fx": ring != null,
		"ghost": ghost_alive,
		"heat": _stat_heat,
	}
