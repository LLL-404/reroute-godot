extends RefCounted

# 《改道》视图层 · 地形域（D5-1 拆分自 view.gd）：蓝图配色/雾、场内高表（ground_h/ground_y）、
# 连续地面网格（单网格水密：场内 0.5m 细格 + 场外渐进格距；无包围圈、无方块缝）、
# 威胁热层、屏幕拾取。只读模拟（grid 高度/rev 仅取用）；
# 几何工具借 core；节点挂点统一走 host。
# 2026-10-16 世界重做：旧「柱带 + 环带」方块拼装（_rebuild_field 柱体 / _rebuild_ring /
# _collect_ring）已删除；SOLID 抬升融入同一网格（岩石色 + 1.6m）。
# 2026-10-16 世界重做②（方案 §11.16）：边框崖壁加「周向起伏 + 南面出怪口豁口」
# （_rim_scale，对齐当局 spawn 列），场外配色按高度岩化。
# 2026-10-17 三平面贴图：_ground_mat → ShaderMaterial（ground093c/rock061 CC0），
# 顶点色 a 位 = 岩石权值（沙/岩纹理按权混法线+色），rgb 维持既有分带/层理/抖动。
# 2026-10-17 六边化（H3）：场区渲染由「lattice 邻格 max-blend」改为**逐格六棱板网格**
# （_rebuild_hex：顶面 = 每格 7 顶点扇形 + 坡度法线；棱墙 = 朝低邻侧，界外壁双面 + 埋深 0.5）。
# 2026-10-17 T1 自然化：落差边改「圆唇 + 斜壁/边坡 + 确定性微扰」（edge_kind_at/edge_profile/
# _edge_color；分级按**模拟高度差**：同层=石阶、Δ1=暖色可爬坡、Δ≥2/实心=崖壁。顶面恒平不动）。
# lattice 网格保留场外渐进环 + **场内区改取蓝图高度函数平滑直填**（内部面片整体跳过，
# 只留最外圈 1 环缝合场外；欠缝/半格锯齿为 odd-r 固有，接受）。高度变化只重建六边网格。

const ViewCoreScript = preload("res://game/view_core.gd")
const Blueprint = preload("res://game/blueprint.gd")

# 地面贴图管线（2026-10-17，CC0·ambientCG）：双材质三平面 shader；顶点色 a 位 = 岩石权值
# （shader 按 a 混沙/岩纹理；rgb 维持补过 check_shots 校准的程序化分带色——见 terrain_ground.gdshader 头注）
const GROUND_SHADER = preload("res://game/terrain_ground.gdshader")
const TEX_SAND_COL = preload("res://assets/textures/terrain/ground093c_col.jpg")
const TEX_SAND_NRM = preload("res://assets/textures/terrain/ground093c_nrm.jpg")
const TEX_ROCK_COL = preload("res://assets/textures/terrain/rock061_col.jpg")
const TEX_ROCK_NRM = preload("res://assets/textures/terrain/rock061_nrm.jpg")

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

# 地面网格参数：场内 0.5m 细格（64² 格 → 129 条采样线）；场外渐进格距 P(i)=32+i+0.06i²
const FINE_STEP := 0.5
const OUT_RINGS := 54 # i=1..54 → 最远 ±260.96
const SOLID_BUMP := 1.6 # SOLID 格在网格内的抬升（原柱体口径：顶 = ground_y + 1.6）
const RIM_BUMP := 0.8 # 地图边框圈额外抬升：矮石墙围界（对齐头图矮墙+h 豁口），非崖壁
const RIM_MOUTH_W := 3.6 # 南面出怪口豁口半宽（m，spawn 列两侧高斯衰减）

# 六边棱边 → 角点表（CW 环序 Ca→Cb，与 core.HEX_CORNERS 下标对应）：
# E=C1-C2 / NE=C0-C1 / NW=C5-C0 / W=C4-C5 / SW=C3-C4 / SE=C2-C3
const HEX_EDGE_A := [1, 0, 5, 4, 3, 2]
const HEX_EDGE_B := [2, 1, 0, 5, 4, 3]
const WALL_EMBED := 0.5 # 界外壁底埋深（相对蓝图高度函数）

# 落差边自然化（2026-10-17 T1 阶段1）：圆唇 + 斜壁/边坡 + 确定性微扰。
# 每格落差边由「高格一侧」拥有（与既有棱墙归属一致）；顶面板本身不动（贴地/热层/拾取全走平顶）。
# 分级按**模拟高度差**（可爬性真值）：同层(微差)=保留石阶感，Δh=1 可爬=暖色渣坡，Δh≥2/实心=崖壁。
const EDGE_MICRO := 0 # 同层高差（蓝图起伏台阶；维持暗色石阶 + 圆唇）
const EDGE_RAMP := 1 # 模拟高度差 1（可爬；暖色边坡带，一眼可走）
const EDGE_CLIFF := 2 # 模拟高度差 ≥2 或触及实心/界外（不可爬；斜壁 + 层理色阶 + 渣坡裙脚）
const LIP_OUT := 0.07 # 圆唇外挑（m）
const LIP_V := 0.14 # 圆唇垂落（m，微差边按落差比例收窄）
const RAMP_RUN := 0.34 # 可爬边坡坡脚外伸基准（m，随视觉落差限幅缩放）
const BATTER := 0.12 # 崖壁底部外扩（斜壁坡率感，m）
const EDGE_J := 0.05 # 沿边微扰幅度（m；确定性 ihash，去镜面平整感）

var host: Node3D
var core: ViewCoreScript

var field_root: Node3D

var grid: Grid = null
var field_h: PackedFloat64Array
var height_fn: Callable
var cur_palette: Dictionary = {}
var _gates := PackedFloat64Array() # 南面出怪口世界 x（崖壁豁口对齐当局 spawn 列）

var heat_on := false
var heat_root: Node3D = null
var heat_rev := -1
var heat_mats: Array = []

var _stat_field := 0
var _stat_plain := 0
var _stat_heat := 0

# —— 地面网格数据（_heights：场外区由蓝图期静态写入，场内区每次重建覆写）——
var _lattice := PackedFloat64Array() # 每轴采样坐标（升序；场外渐进 + 场内 0.5m）
var _ln := 0 # 每轴采样线数
var _i0 := 0 # 场内采样线起始下标（= -HALF 线）
var _i1 := 0 # 场内采样线结束下标（= +HALF 线）
var _cell_top := PackedFloat64Array() # 每格视觉顶（蓝图高 + 模拟层 + SOLID 抬升）
var _heights := PackedFloat64Array()
var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _ground: MeshInstance3D = null
var _hex: MeshInstance3D = null # 场内六棱板网格（顶面扇形 + 棱墙；随 _cell_top 重建）
var _ground_mat: ShaderMaterial = null
var _col_lo := Color()
var _col_mid := Color()
var _col_hi := Color()
var _col_rock := Color()
var _band_lo := 0.0
var _band_hi := 0.0


## 构造注入：记宿主 + core（由 view._ready 组装）
func _init(p_host: Node3D, p_core: ViewCoreScript) -> void:
	host = p_host
	core = p_core


## 场地根容器（原 view._ready 中段）：整个连续地面网格挂 Field 下。
func setup_roots() -> void:
	field_root = Node3D.new()
	field_root.name = "Field"
	host.add_child(field_root)


## 世界坐标 → 视觉地面高度（连续；只在建网格时用；逐帧贴地走 ground_y 查表）
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

## 应用蓝图：换高度函数与场内高表、重建地面网格、重刷配色与雾。（R1 一次 + 每局一次）
## anchor：地标位置对齐当局 Scenario（ridge_y/basin_y/core）；空 = 预设坐标（探针口径）。
func apply_blueprint(bp: Dictionary, seed: int, anchor: Dictionary = {}) -> void:
	var composed: Array = Blueprint.compose(bp, seed, anchor)
	height_fn = composed[0]
	cur_palette = composed[1]
	_gates = PackedFloat64Array()
	var gx: Variant = anchor.get("gate_x", [])
	if typeof(gx) == TYPE_ARRAY:
		for v in gx:
			_gates.append(float(v))

	# 场内 64² 格高表：单位/建筑/幽灵/拾取的贴地全走这里
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
	var clo: Array = cur_palette["ground_lo"]
	var cmid: Array = cur_palette["ground"]
	var chi: Array = cur_palette["ground_hi"]
	var crock: Array = cur_palette["rock"]
	_col_lo = Color(clo[0], clo[1], clo[2])
	_col_mid = Color(cmid[0], cmid[1], cmid[2])
	_col_hi = Color(chi[0], chi[1], chi[2])
	_col_rock = Color(crock[0], crock[1], crock[2])
	_band_lo = float(cur_palette["band_lo_at"])
	_band_hi = float(cur_palette["band_hi_at"])
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = GROUND_SHADER
		_ground_mat.set_shader_parameter("sand_col", TEX_SAND_COL)
		_ground_mat.set_shader_parameter("sand_nrm", TEX_SAND_NRM)
		_ground_mat.set_shader_parameter("rock_col", TEX_ROCK_COL)
		_ground_mat.set_shader_parameter("rock_nrm", TEX_ROCK_NRM)

	if core.env != null:
		var fog: Array = cur_palette["fog"]
		core.env.fog_light_color = Color(fog[0], fog[1], fog[2])
		core.env.fog_depth_begin = float(cur_palette["fog_start"])
		core.env.fog_depth_end = float(cur_palette["fog_end"])
		# 天空/远霾：比雾色更亮的暖晕（金色时刻地平线）
		core.env.background_color = Color(minf(fog[0] * 1.32, 1.0), minf(fog[1] * 1.22, 1.0), minf(fog[2] * 1.08, 1.0))

	_build_lattice()
	_build_ground()


## 场外渐进格距坐标：P(i) = HALF + i + 0.06·i²（i=1..54；至 ±260.96）
func _out_pos(i: int) -> float:
	var fi := float(i)
	return core.HALF + fi + 0.06 * fi * fi


## 采样线表与索引表（常量格距，一生一次）
func _build_lattice() -> void:
	if _ln > 0:
		return
	_lattice = PackedFloat64Array()
	for i in range(OUT_RINGS, 0, -1):
		_lattice.append(-_out_pos(i))
	var n_fine := core.CELL_N * 2 + 1
	for k in n_fine:
		_lattice.append(-core.HALF + float(k) * FINE_STEP)
	for i in range(1, OUT_RINGS + 1):
		_lattice.append(_out_pos(i))
	_ln = _lattice.size()
	_i0 = OUT_RINGS
	_i1 = OUT_RINGS + n_fine - 1
	_stat_field = core.CELL_N * core.CELL_N
	# 场内区面片整体跳过（六边网格接管），只留最外圈缝合环 → 渲染面片 = 全场 - 跳过
	var skipped_side := core.CELL_N * 2 - 2
	_stat_plain = (_ln - 1) * (_ln - 1) - skipped_side * skipped_side
	_build_indices()


## 全场三角索引（规则网格；顶点一律共享 → 水密无裂缝）；场内区面片跳过（六边网格接管）。
func _build_indices() -> void:
	if not _indices.is_empty():
		return
	var e := _ln - 1
	var skip_lo := _i0 + 1
	var skip_hi := _i1 - 2
	var skip_n := skip_hi - skip_lo + 1
	_indices.resize((e * e - skip_n * skip_n) * 6)
	var w := 0
	for lj in e:
		var row := lj * _ln
		var row1 := row + _ln
		for li in e:
			if li >= skip_lo and li <= skip_hi and lj >= skip_lo and lj <= skip_hi:
				continue
			var a := row + li
			var b := a + 1
			var d := row1 + li
			var c := d + 1
			_indices[w] = a
			_indices[w + 1] = b
			_indices[w + 2] = c
			_indices[w + 3] = a
			_indices[w + 4] = c
			_indices[w + 5] = d
			w += 6


## 整网格构建（每局一次）：场外顶点静态全量 + 场内区 + 法线 + surface。
func _build_ground() -> void:
	var n2 := _ln * _ln
	if _heights.size() != n2:
		_heights.resize(n2)
		_positions.resize(n2)
		_normals.resize(n2)
		_colors.resize(n2)
	for lj in _ln:
		var pz := _lattice[lj]
		var row := lj * _ln
		for li in _ln:
			if li >= _i0 and li <= _i1 and lj >= _i0 and lj <= _i1:
				continue # 场内区由 _fill_field_region 负责
			var px := _lattice[li]
			var h := 0.0
			if not height_fn.is_null():
				h = height_fn.call(px, pz)
			_heights[row + li] = h
			_positions[row + li] = Vector3(px, h, pz)
			_colors[row + li] = _outside_color(px, pz, h)
	_fill_field_region()
	_recompute_normals(0, _ln - 1)
	if _ground == null:
		_ground = MeshInstance3D.new()
		_ground.name = "Ground"
		_ground.material_override = _ground_mat
		field_root.add_child(_ground)
	_apply_mesh()
	_rebuild_hex()


## 场内区采样线（2026-10-17 六边化）：整区取蓝图高度函数平滑直填（内部面片已跳过，
## 仅最外圈 1 环参与渲染缝合场外）；格顶/棱墙由 _rebuild_hex 独立成网格。
func _fill_field_region() -> void:
	if field_h.is_empty():
		return
	for lj in range(_i0, _i1 + 1):
		var pz := _lattice[lj]
		var row := lj * _ln
		for li in range(_i0, _i1 + 1):
			var px := _lattice[li]
			var h := ground_h(px, pz)
			_heights[row + li] = h
			_positions[row + li] = Vector3(px, h, pz)
			_colors[row + li] = _outside_color(px, pz, h)


# ---- 场内六棱板网格（2026-10-17 H3）----

## 每格视觉顶（蓝图高 + 模拟层 1.2m/级 + SOLID 抬升 + 边框围界）→ _cell_top。
func _compute_cell_top() -> void:
	if field_h.is_empty():
		return
	var n := core.CELL_N
	if _cell_top.size() != n * n:
		_cell_top.resize(n * n)
	for y in n:
		for x in n:
			var t := field_h[y * n + x]
			if grid != null:
				t += float(grid.get_h(x, y)) * core.H_STEP
				if grid.at(x, y) == Grid.SOLID:
					t += SOLID_BUMP
					if x == 0 or y == 0 or x == n - 1 or y == n - 1:
						t += RIM_BUMP * _rim_scale(x, y) # 边框围界（视觉围合；周向起伏 + 南口豁口）
			_cell_top[y * n + x] = t


## 重建六棱板网格：逐格顶面（中心 + 6 角扇形；坡度法线/顶点色）+ 落差边剖面
## （edge_kind_at/edge_profile：圆唇 + 斜壁/边坡/石阶 + 微扰，只朝低邻侧画、面朝邻居；
## 界外棱双面 + 底埋入场外地面）。挖/填/落墙后复跑。
func _rebuild_hex() -> void:
	if field_h.is_empty() or _ground == null:
		return # 蓝图尚未套用（正常流程 apply_blueprint 先于 build_terrain）
	_compute_cell_top()
	var n := core.CELL_N
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for y in n:
		for x in n:
			var w := core.cell_to_world(x, y)
			var t := _cell_top[y * n + x]
			var solid := grid != null and grid.at(x, y) == Grid.SOLID
			# 坡度法线 / 坡度值（6 邻；界外邻不计）
			var ga := 0.0
			var gb := 0.0
			var slope := 0.0
			for k in 6:
				var x2 := Grid.nx(x, y, k)
				var y2 := Grid.ny(x, y, k)
				if x2 < 0 or y2 < 0 or x2 >= n or y2 >= n:
					continue
				var dt := _cell_top[y2 * n + x2] - t
				slope = maxf(slope, absf(dt))
				var w2 := core.cell_to_world(x2, y2)
				var dx := w2.x - w.x
				var dz := w2.z - w.z
				var inv := 1.0 / sqrt(dx * dx + dz * dz)
				ga += dt * dx * inv
				gb += dt * dz * inv
			var nrm := Vector3(-ga * 0.3, 1.0, -gb * 0.3).normalized()
			var col := _field_color(t, solid, slope, x, y)
			# 顶面：中心 + 6 角（CW 环序 C0..C5），扇形 6 三角
			var base := verts.size()
			verts.append(Vector3(w.x, t, w.z))
			nrms.append(nrm)
			cols.append(col)
			for i in 6:
				var c2: Vector2 = core.HEX_CORNERS[i]
				verts.append(Vector3(w.x + c2.x, t, w.z + c2.y))
				nrms.append(nrm)
				cols.append(col)
			for i2 in 6:
				idx.append(base)
				idx.append(base + 1 + i2)
				idx.append(base + 1 + (i2 + 1) % 6)
			# 棱边剖面（2026-10-17 自然化 T1）：圆唇 + 斜壁/边坡 + 微扰；高格一侧拥有该边。
			for k2 in 6:
				var ca: Vector2 = core.HEX_CORNERS[HEX_EDGE_A[k2]]
				var cb: Vector2 = core.HEX_CORNERS[HEX_EDGE_B[k2]]
				var ax := w.x + ca.x
				var az := w.z + ca.y
				var bx := w.x + cb.x
				var bz := w.z + cb.y
				var nx2 := Grid.nx(x, y, k2)
				var ny2 := Grid.ny(x, y, k2)
				var t_lo := 0.0
				var both := false
				var inside := nx2 >= 0 and ny2 >= 0 and nx2 < n and ny2 < n
				if inside:
					var t2 := _cell_top[ny2 * n + nx2]
					if t <= t2 + 0.02:
						continue # 同高/我低（低侧由对面格画）
					t_lo = t2
				else:
					t_lo = minf(ground_h(ax, az), ground_h(bx, bz)) - WALL_EMBED # 界外：埋入场外地面
					both = true
				var kind := edge_kind_at(x, y, k2) if inside else EDGE_CLIFF
				var prof := edge_profile(x, y, k2, t, t_lo, kind)
				var wd := Vector3(cb.x - ca.x, 0.0, cb.y - ca.y)
				var wn := Vector3(wd.z, 0.0, -wd.x).normalized() # 面朝邻居（外法线）
				var wdn := wd.normalized() # 沿边方向（非顶层点外延闭角用）
				var n_strip := prof.size() / 2 - 1
				for sj in n_strip:
					var r_u := prof[sj * 2]
					var h_u := prof[sj * 2 + 1]
					var r_l := prof[sj * 2 + 2]
					var h_l := prof[sj * 2 + 3]
					var dr := r_l - r_u
					var dhh := h_l - h_u
					var dlen := maxf(sqrt(dr * dr + dhh * dhh), 0.0001)
					var n2r := -dhh / dlen
					var n2y := dr / dlen
					# 风格化软光：垂直面法线向上倾 0.30（借顶光，避免墙面在阴影侧压成死黑；纯光照项，无几何影响）
					var sn := Vector3(wn.x * n2r, n2y + 0.30, wn.z * n2r).normalized()
					var scol := _edge_color(kind, sj, col, (h_u + h_l) * 0.5, x, y, k2)
					# 非顶层点沿边方向外延 0.75×r：把相邻边在共享角处的楔形缝自然闭合成折缝
					# （P0 恒 r=0 → 顶缝无外延、精确重合；延伸量 < 面深 → 不产生新穿插）
					var eu := 0.75 * r_u
					var el := 0.75 * r_l
					var ua := Vector3(ax + wn.x * r_u - wdn.x * eu, h_u, az + wn.z * r_u - wdn.z * eu)
					var la := Vector3(ax + wn.x * r_l - wdn.x * el, h_l, az + wn.z * r_l - wdn.z * el)
					var lb := Vector3(bx + wn.x * r_l + wdn.x * el, h_l, bz + wn.z * r_l + wdn.z * el)
					var ub := Vector3(bx + wn.x * r_u + wdn.x * eu, h_u, bz + wn.z * r_u + wdn.z * eu)
					var wb := verts.size()
					verts.append(ua)
					verts.append(la)
					verts.append(lb)
					verts.append(ub)
					for _i3 in 4:
						nrms.append(sn)
						cols.append(scol)
					idx.append(wb)
					idx.append(wb + 1)
					idx.append(wb + 2)
					idx.append(wb)
					idx.append(wb + 2)
					idx.append(wb + 3)
					if both: # 界外壁双面（内视角可见）
						var wb2 := verts.size()
						verts.append(ub)
						verts.append(lb)
						verts.append(la)
						verts.append(ua)
						var sn2 := -sn
						for _i4 in 4:
							nrms.append(sn2)
							cols.append(scol)
						idx.append(wb2)
						idx.append(wb2 + 1)
						idx.append(wb2 + 2)
						idx.append(wb2)
						idx.append(wb2 + 2)
						idx.append(wb2 + 3)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _hex == null:
		_hex = MeshInstance3D.new()
		_hex.name = "HexField"
		_hex.material_override = _ground_mat
		field_root.add_child(_hex)
	_hex.mesh = mesh


## 落差边分级（模拟高度差 = 可爬性真值；界外/实心恒崖壁）。
## 探针读取面（口径与网格生成同源）。
func edge_kind_at(x: int, y: int, k: int) -> int:
	var n := core.CELL_N
	var nx := Grid.nx(x, y, k)
	var ny := Grid.ny(x, y, k)
	if nx < 0 or ny < 0 or nx >= n or ny >= n:
		return EDGE_CLIFF
	if grid == null:
		return EDGE_MICRO
	if grid.at(x, y) == Grid.SOLID or grid.at(nx, ny) == Grid.SOLID:
		return EDGE_CLIFF
	var dh: int = grid.get_h(x, y) - grid.get_h(nx, ny)
	if dh >= 2:
		return EDGE_CLIFF
	if dh == 1:
		return EDGE_RAMP
	return EDGE_MICRO


## 边剖面采样：返回 [r0,h0, r1,h1, ...]（r = 自边框线外伸；h = 世界高）。
## P0 = 顶面边框线（不动，且恒无微扰 → 顶面缝精确重合）；圆唇 P0→P1→P2；
## 面按分级：微差 = 近垂直石阶 / 可爬 = 暖色边坡 / 崖壁 = 斜壁。
func edge_profile(x: int, y: int, k: int, t: float, t_lo: float, kind: int) -> PackedFloat64Array:
	var delta := maxf(t - t_lo, 0.01)
	var lip_v := minf(LIP_V, delta * 0.6)
	var pts := PackedFloat64Array()
	pts.append(0.0)
	pts.append(t)
	pts.append(LIP_OUT + _edge_j(x, y, k, 1, 0.022, 3301))
	pts.append(t - lip_v * 0.5 + _edge_j(x, y, k, 1, 0.022, 3307))
	pts.append(LIP_OUT * 0.45 + _edge_j(x, y, k, 2, 0.012, 3313))
	pts.append(t - lip_v + _edge_j(x, y, k, 2, 0.018, 3319))
	if kind == EDGE_MICRO:
		pts.append(0.024 + _edge_j(x, y, k, 3, 0.010, 3323))
		pts.append(t_lo - 0.010)
	elif kind == EDGE_RAMP:
		var run := RAMP_RUN * clampf(delta / 1.2, 0.6, 1.5)
		var drop := delta - lip_v
		pts.append(run * 0.45 + _edge_j(x, y, k, 3, 0.02, 3323))
		pts.append(t - lip_v - drop * 0.5 + _edge_j(x, y, k, 3, 0.025, 3329))
		pts.append(run + _edge_j(x, y, k, 4, 0.03, 3331))
		pts.append(t_lo - 0.010)
	else:
		var drop2 := delta - lip_v
		var rel := 0.55 + 0.9 * Blueprint.ihash(x * 71 + k * 23, y * 97 + k * 11, 3347) # 面斜率签 0.55..1.45
		pts.append(BATTER * 0.5 * rel + _edge_j(x, y, k, 3, 0.016, 3323))
		var h3 := t - lip_v - drop2 * 0.5 + _edge_j(x, y, k, 3, 0.025, 3329)
		pts.append(h3)
		pts.append(BATTER * (2.0 + 1.2 * rel) + _edge_j(x, y, k, 4, 0.03, 3331)) # 渣坡裙脚外缘（贴地薄楔）
		# 裙脚高度自适应：恒低于 P3 且恒离地 ≥4mm（实心/微差边视觉落差极小时防非单调/防穿插）
		pts.append(maxf(minf(t_lo + 0.012 + _edge_j(x, y, k, 4, 0.008, 3337), h3 - 0.02), t_lo + 0.004))
		pts.append(BATTER * (0.7 + 0.6 * rel) + _edge_j(x, y, k, 5, 0.02, 3343)) # 回勾至沉底坡脚
		pts.append(t_lo - 0.010)
	return pts


## 边剖面确定性微扰（±amp；只作用于 P1 之后 → 顶面缝不受影响）。
func _edge_j(x: int, y: int, k: int, j: int, amp: float, salt: int) -> float:
	return (Blueprint.ihash(x * 97 + k * 13 + j * 5, y * 61 + j * 7, salt) - 0.5) * 2.0 * amp


## 边色阶：圆唇 = 顶色微暗两档；微差面 = 岩化石阶（层理明暗带）；
## 可爬坡 = 暖色渣土（一眼可走）；崖壁 = 岩化提亮 + 双频层理带 + 逐边明暗签（去「平」）。
## a 位 = 贴图岩权。全部输入（x,y,k,sj,h_mid）确定性。
func _edge_color(kind: int, sj: int, col: Color, h_mid: float, x: int, y: int, k: int) -> Color:
	var out: Color
	var a := col.a
	var tag := Blueprint.ihash(x * 53 + k * 17, y * 41 + k * 7, 5483) # 逐边明暗签
	if sj == 0:
		out = col.darkened(0.03)
	elif sj == 1:
		out = col.darkened(0.13)
	elif kind == EDGE_RAMP:
		out = col.lerp(_col_lo, 0.30).lightened(0.05) if sj == 2 else col.lerp(_col_lo, 0.46)
		a = minf(col.a * 0.45, 1.0)
	elif kind == EDGE_CLIFF:
		var band := 0.5 + 0.5 * sin(h_mid * 8.7 + float(x) * 0.7 + float(y) * 0.5 + float(sj) * 1.7)
		var band2 := 0.5 + 0.5 * sin(h_mid * 2.9 + float(x) * 0.23 + float(y) * 0.41)
		if sj == 4: # 裙脚回勾底面（近地暗缝，多为遮挡）
			out = col.lerp(_col_rock, 0.30).darkened(0.34)
		elif sj == 3: # 下段坡 + 渣坡裙脚：暖色碎渣带（掺沙纹，贴地碎屑感）
			var banda := 0.5 + 0.5 * sin(h_mid * 6.1 + float(x) * 0.51 + float(y) * 0.37)
			out = col.lerp(_col_lo, 0.26).darkened(0.06 - 0.08 * banda)
			out = Color(maxf(out.r, 0.22), maxf(out.g, 0.17), maxf(out.b, 0.12), out.a)
			a = minf(col.a + 0.18, 1.0)
		else:
			out = col.lerp(_col_rock, 0.26)
			out = out.darkened(0.02 if sj == 2 else 0.10)
			var tone := 0.96 + 0.11 * band + 0.07 * band2
			if tag < 0.24:
				tone += 0.08 # 明面（亮岩带）
			out = Color(maxf(out.r * tone, 0.24), maxf(out.g * tone, 0.19), maxf(out.b * tone, 0.13), out.a) # 暖色地板防死黑
			a = minf(col.a + 0.35, 1.0)
	else: # EDGE_MICRO
		var bandm := 0.5 + 0.5 * sin(h_mid * 7.3 + float(x) * 0.6 + float(y) * 0.45 + float(sj) * 2.1)
		var inm := col.lerp(_col_rock, 0.22).darkened(0.12 - 0.08 * bandm)
		out = Color(maxf(inm.r, 0.18), maxf(inm.g, 0.14), maxf(inm.b, 0.10), inm.a)
		a = minf(col.a + 0.30, 1.0)
	var kj := 0.97 + 0.06 * Blueprint.ihash(x * 29 + k * 11 + sj * 3, y * 23 + sj * 5, 4457)
	return Color(clampf(out.r * kj, 0.0, 1.0), clampf(out.g * kj, 0.0, 1.0), clampf(out.b * kj, 0.0, 1.0), a)


## 边框崖壁高度系数：周向确定性起伏（去直边皱褶感）+ 南面出怪口豁口（对齐当局 spawn 列，限南沿）。
func _rim_scale(x: int, y: int) -> float:
	var s := 0.70 + 0.55 * Blueprint.ihash(x * 7 + 3, y * 7 - 5, 5521)
	if y == core.CELL_N - 1 and not _gates.is_empty():
		var wx := core.cell_to_world(x, y).x # 六边 odd-r：奇行 +0.5，必须走统一映射
		var m := 0.0
		for gx in _gates:
			var u := (wx - gx) / RIM_MOUTH_W
			m = maxf(m, exp(-u * u))
		s *= 1.0 - 0.85 * m # 豁口处崖壁近乎归零（留 1.6m SOLID 门槛石）
	return s


## 场内顶点色：高程三档连续混色 + 坡度岩石化 + 层理与确定性明度抖动（对齐宣传图崖面观感）。
func _field_color(h: float, solid: bool, slope: float, cx: int, cy: int) -> Color:
	if solid:
		return _col_rock
	var t := 0.0
	if h >= _band_hi:
		t = 1.0
	elif h > _band_lo:
		t = (h - _band_lo) / (_band_hi - _band_lo)
	var base: Color
	if t < 0.5:
		base = _col_lo.lerp(_col_mid, Blueprint.smooth01(t * 2.0))
	else:
		base = _col_mid.lerp(_col_hi, Blueprint.smooth01((t - 0.5) * 2.0))
	var rock_mix := clampf((slope - 0.45) / 1.2, 0.0, 0.72)
	var patch := Blueprint.ihash(cx / 4, cy / 4, 4441) # 4 格块状干燥色斑（破单色台面）
	base = base.lerp(_col_lo, 0.13 * clampf((patch - 0.55) * 2.5, 0.0, 1.0))
	var strata := 0.5 + 0.5 * sin(h * 5.3 + float(cx) * 0.7 + float(cy) * 0.4)
	var k := (0.91 + 0.18 * Blueprint.ihash(cx * 3 + 11, cy * 3 - 7, 917)) * (0.94 + 0.07 * strata)
	# 贴图管线（2026-10-17）：a 位 = 坡度岩石化权值（shader 按权混岩纹理；SOLID 分支恒 a=1）
	return Color(base.r * k, base.g * k, base.b * k, rock_mix)


## 场外顶点色：rgb = 沙基调（层理微带 + 确定性明度抖动），岩石比例（a 位）随高度/坡度过渡；
## shader 端 a 混岩纹理（ground093c → rock061），层理带照乘。
func _outside_color(px: float, pz: float, h: float) -> Color:
	var d := maxf(absf(px), absf(pz)) - core.HALF
	var t := clampf((h - 0.6) / 7.5, 0.0, 1.0) # 低地=沙，高地=岩
	var slope := 0.0
	if not height_fn.is_null():
		var s1 := absf(height_fn.call(px + 2.0, pz) - h)
		var s2 := absf(height_fn.call(px, pz + 2.0) - h)
		slope = maxf(s1, s2) * 0.5 # 陡坡面岩化（台地崖壁/环山体内坡）
	var mix := clampf(0.16 + 0.30 * Blueprint.smooth01(d / 60.0) + 0.62 * t + 1.1 * clampf(slope / 3.0, 0.0, 0.75), 0.0, 1.0)
	var e := 1.0
	if h > 3.0:
		e = 0.86 + 0.14 * sin(h / 4.5 * 6.2831853 + px * 0.13) # 岩壁层理带（对齐 4.5m 台阶）
	var k := (0.90 + 0.18 * Blueprint.ihash(int(floor(px * 0.5)), int(floor(pz * 0.5)), 7331)) * e
	return Color(clampf(_col_lo.r * k, 0.0, 1.0), clampf(_col_lo.g * k, 0.0, 1.0), clampf(_col_lo.b * k, 0.0, 1.0), mix)


## 重建地表（挖/填/落墙后 height_rev 变）：lattice 为静态平滑底（蓝图期一次建成），
## 只重建场内六棱板网格（_cell_top 随 sim 高度层刷新）。
func _rebuild_field() -> void:
	if _ln == 0 or _ground == null:
		return # 蓝图尚未套用（正常流程 apply_blueprint 先于 build_terrain）
	_rebuild_hex()


## 法线：采样线坐标差 + 高度中心差（渐进格距按实际坐标差算，水密网格共享顶点自适应）
func _recompute_normals(lo: int, hi: int) -> void:
	lo = maxi(lo, 0)
	hi = mini(hi, _ln - 1)
	for lj in range(lo, hi + 1):
		var dz := maxf(_lattice[mini(lj + 1, _ln - 1)] - _lattice[maxi(lj - 1, 0)], 0.0001)
		var row := lj * _ln
		var row_p := maxi(lj - 1, 0) * _ln
		var row_n := mini(lj + 1, _ln - 1) * _ln
		for li in range(lo, hi + 1):
			var dx := maxf(_lattice[mini(li + 1, _ln - 1)] - _lattice[maxi(li - 1, 0)], 0.0001)
			var du := _heights[row_n + li] - _heights[row_p + li]
			var dv := _heights[row + mini(li + 1, _ln - 1)] - _heights[row + maxi(li - 1, 0)]
			_normals[row + li] = Vector3(-dv * dz, dx * dz, -du * dx).normalized()


## 以当前顶点数组重建 surface（索引与场外顶点静态；一次上传全量，56k 顶点量级）
func _apply_mesh() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ground.mesh = mesh


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
	core._ensure_hex_plate()
	for i in HEAT_N:
		var arr2: Array = groups[i]
		var mmi := core._make_multimesh(arr2, heat_mats[i], core.hex_plate_mesh)
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
