extends RefCounted

# 《改道》视图层 · 地形域（D5-1 拆分自 view.gd）：蓝图配色/雾、场内高表（ground_h/ground_y）、
# 战场柱带、外围环带、威胁热层、屏幕拾取。只读模拟（grid 高度/rev 仅取用）；
# 几何工具借 core；节点挂点统一走 host。

const ViewCoreScript = preload("res://game/view_core.gd")
const Blueprint = preload("res://game/blueprint.gd")

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

var host: Node3D
var core: ViewCoreScript

var field_root: Node3D
var world_root: Node3D

var grid: Grid = null
var field_h: PackedFloat64Array
var height_fn: Callable
var cur_palette: Dictionary = {}

var heat_on := false
var heat_root: Node3D = null
var heat_rev := -1
var heat_mats: Array = []

var _stat_field := 0
var _stat_ring := 0
var _stat_heat := 0


func _init(p_host: Node3D, p_core: ViewCoreScript) -> void:
	host = p_host
	core = p_core


## 场地根容器（原 view._ready 中段）：Field 柱带 / WorldRing 环带。
func setup_roots() -> void:
	field_root = Node3D.new()
	field_root.name = "Field"
	host.add_child(field_root)
	world_root = Node3D.new()
	world_root.name = "WorldRing"
	host.add_child(world_root)


## 世界坐标 → 视觉地面高度（连续；只在建柱/环带时用；逐帧贴地走 ground_y 查表）
func ground_h(wx: float, wz: float) -> float:
	if height_fn.is_null():
		return 0.0
	return height_fn.call(wx, wz)


## 格子 → 该格视觉地面高度（蓝图预计算 + sim 高度层 1.2m/级；单位/建筑/英雄贴地全走这里）
func ground_y(x: int, y: int) -> float:
	if field_h.is_empty():
		return 0.0
	var gy := field_h[y * core.CELL_N + x]
	if grid != null:
		gy += float(grid.get_h(x, y)) * core.H_STEP
	return gy


# ---- 蓝图 / 地形 ----

## 应用蓝图：换高度函数与场内高表、重建地形柱带与环带、重刷配色与雾。（R1 一次 + 每局一次）
func apply_blueprint(bp: Dictionary, seed: int) -> void:
	var composed: Array = Blueprint.compose(bp, seed)
	height_fn = composed[0]
	cur_palette = composed[1]

	# 场内 48² 格高表：单位/建筑/幽灵/拾取的贴地全走这里
	field_h = PackedFloat64Array()
	field_h.resize(core.CELL_N * core.CELL_N)
	for y in core.CELL_N:
		for x in core.CELL_N:
			var w := core.cell_to_world(x, y)
			field_h[y * core.CELL_N + x] = height_fn.call(w.x, w.z)

	# 地形相关配色（palette；墙体/单位等其余材质不归蓝图管）
	for k in ["ground_lo", "ground", "ground_hi", "rock"]:
		var c: Array = cur_palette[k]
		core.mats[k] = core.make_material(c[0], c[1], c[2])

	if core.env != null:
		var fog: Array = cur_palette["fog"]
		core.env.fog_light_color = Color(fog[0], fog[1], fog[2])
		core.env.fog_depth_begin = float(cur_palette["fog_start"])
		core.env.fog_depth_end = float(cur_palette["fog_end"])
		core.env.background_color = Color(fog[0] * 0.80, fog[1] * 0.80, fog[2] * 0.84)

	_rebuild_field()
	_rebuild_ring()


## 重建战场柱带（三档高程分色）+ 外围环带（同一高度函数保证衔接）。
func _rebuild_field() -> void:
	for c in field_root.get_children():
		c.free()
	var bands := { "ground_lo": [], "ground": [], "ground_hi": [] }
	var lo_at: float = float(cur_palette["band_lo_at"])
	var hi_at: float = float(cur_palette["band_hi_at"])
	for y in core.CELL_N:
		for x in core.CELL_N:
			var h := field_h[y * core.CELL_N + x]
			if grid != null:
				h += float(grid.get_h(x, y)) * core.H_STEP
			var band := "ground"
			if h < lo_at:
				band = "ground_lo"
			elif h > hi_at:
				band = "ground_hi"
			var w := core.cell_to_world(x, y)
			bands[band].append([Vector3(w.x, (h - 2.5) / 2.0, w.z), Vector3(1.0, h + 2.5, 1.0)])
	var total := 0
	for band in ["ground_lo", "ground", "ground_hi"]:
		var arr: Array = bands[band]
		var mmi := core._make_multimesh(arr, core.mats[band])
		mmi.name = "Band_" + band
		field_root.add_child(mmi)
		total += arr.size()
	_stat_field = total


## 重建外围环带（两圈：近圈贴战场边缘、远圈延展地平线）
func _rebuild_ring() -> void:
	for c in world_root.get_children():
		c.free()
	var insts: Array = []
	_collect_ring(insts, -50, 50, 2, core.HALF - 0.5)
	_collect_ring(insts, -150, 150, 6, 50.0)
	var mmi := core._make_multimesh(insts, core.mats["rock"])
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
	dists.resize(core.CELL_N * core.CELL_N)
	var maxd := 0
	for y in core.CELL_N:
		for x in core.CELL_N:
			var d := pworld.field.dist_at(x, y)
			if d > maxd:
				maxd = d
			dists[y * core.CELL_N + x] = d
	heat_rev = pworld.grid.rev
	_stat_heat = 0
	if maxd <= 0:
		return
	heat_root = Node3D.new()
	heat_root.name = "Heat"
	host.add_child(heat_root)
	var groups: Array = []
	for _i in HEAT_N:
		groups.append([])
	if heat_mats.is_empty():
		for c in HEAT_COLORS:
			heat_mats.append(core.make_material(c[0], c[1], c[2]))
	for y in core.CELL_N:
		for x in core.CELL_N:
			var d := dists[y * core.CELL_N + x]
			if d >= 0:
				var band := mini(HEAT_N, 1 + (d * HEAT_N) / (maxd + 1))
				var arr: Array = groups[band - 1]
				var w := core.cell_to_world(x, y)
				arr.append([Vector3(w.x, ground_y(x, y) + 0.05, w.z), Vector3(0.94, 0.05, 0.94)])
	for i in HEAT_N:
		var arr2: Array = groups[i]
		var mmi := core._make_multimesh(arr2, heat_mats[i])
		mmi.name = "H" + str(i + 1)
		heat_root.add_child(mmi)
		_stat_heat += arr2.size()


# ---- 拾取 ----

## 拾取：屏幕坐标（像素）→ 战场格。地面有程序化起伏：先按 y=0 求交，取命中格高度再求交，
## 两轮收敛（地势 ±1.2m、俯角 ≥35° 足够）。返回 Vector2i(-1,-1) = 未命中。
## 注意：Godot 的 project_ray_* 取像素坐标（非 0..1 归一化；传小值会被当左上角像素 → 射线全偏）。
func pick_cell(screen_x: float, screen_y: float) -> Vector2i:
	if core.camera == null:
		return Vector2i(-1, -1)
	var pt := Vector2(screen_x, screen_y)
	var origin := core.camera.project_ray_origin(pt)
	var dir := core.camera.project_ray_normal(pt)
	if absf(dir.y) < 0.001:
		return Vector2i(-1, -1)
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	for _i in 2:
		var cell := core.world_to_cell(origin.x + dir.x * t, origin.z + dir.z * t)
		var gh := 0.0
		if cell.x >= 0:
			gh = ground_y(cell.x, cell.y)
		var t2 := -(origin.y - gh) / dir.y
		if t2 <= 0.0:
			break
		t = t2
	return core.world_to_cell(origin.x + dir.x * t, origin.z + dir.z * t)
