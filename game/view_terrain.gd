extends RefCounted

# 《改道》视图层 · 地形域（D5-1 拆分自 view.gd）：蓝图配色/雾、场内高表（ground_h/ground_y）、
# 连续地面网格（单网格水密：场内 0.5m 细格 + 场外渐进格距；无包围圈、无方块缝）、
# 威胁热层、屏幕拾取。只读模拟（grid 高度/rev 仅取用）；
# 几何工具借 core；节点挂点统一走 host。
# 2026-10-16 世界重做：旧「柱带 + 环带」方块拼装（_rebuild_field 柱体 / _rebuild_ring /
# _collect_ring）已删除；SOLID 抬升融入同一网格（岩石色 + 1.6m）。
# 2026-10-16 世界重做②（方案 §11.16）：边框崖壁加「周向起伏 + 出怪口豁口」
# （_rim_scale，对齐当局主口；2026-10-19 拍2 起四侧/世界坐标口径），场外配色按高度岩化。
# 2026-10-17 三平面贴图：_ground_mat → ShaderMaterial（ground093c/rock061 CC0），
# 顶点色 a 位 = 岩石权值（沙/岩纹理按权混法线+色），rgb 维持既有分带/层理/抖动。
# 2026-10-17 六边化（H3）：场区渲染由「lattice 邻格 max-blend」改为**逐格六棱板网格**
# （_rebuild_hex：顶面 = 每格 7 顶点扇形 + 坡度法线；棱墙 = 朝低邻侧，界外壁双面 + 埋深 0.5）。
# 2026-10-17 T1 自然化：落差边改「圆唇 + 斜壁/边坡 + 确定性微扰」（edge_kind_at/edge_profile/
# _edge_color；分级按**模拟高度差**：同层=石阶、Δ1..2=暖色可爬坡、Δ≥3/实心=崖壁。顶面恒平不动）。
# 2026-10-23 高度域 -2..5：分级口径对齐爬坡真值（落差 1~2 可爬、≥3 不可通行）。
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
# 角点 → 相邻两条棱边（E=C1-C2 / NE=C0-C1 / NW=C5-C0 / W=C4-C5 / SW=C3-C4 / SE=C2-C3）
const HEX_CORNER_EDGES := [[1, 2], [0, 1], [5, 0], [4, 5], [3, 4], [2, 3]]
const WALL_EMBED := 0.5 # 界外壁底埋深（相对蓝图高度函数）

# 落差边自然化（2026-10-17 T1 阶段1）：圆唇 + 斜壁/边坡 + 确定性微扰。
# 每格落差边由「高格一侧」拥有（与既有棱墙归属一致）；顶面板本身不动（贴地/热层/拾取全走平顶）。
# 分级按**模拟高度差**（可爬性真值）：同层(微差)=保留石阶感，Δh=1..2 可爬=暖色渣坡，Δh≥3/实心=崖壁。
const EDGE_MICRO := 0 # 同层高差（蓝图起伏台阶；维持暗色石阶 + 圆唇）
const EDGE_RAMP := 1 # 模拟高度差 1..2（可爬；暖色边坡带，一眼可走）
const EDGE_CLIFF := 2 # 模拟高度差 ≥3 或触及实心/界外（不可爬；斜壁 + 层理色阶 + 渣坡裙脚）
const LIP_OUT := 0.07 # 圆唇外挑（m）
const LIP_V := 0.14 # 圆唇垂落（m，微差边按落差比例收窄）
const RAMP_RUN := 0.34 # 可爬边坡坡脚外伸基准（m，随视觉落差限幅缩放）
const BATTER := 0.12 # 崖壁底部外扩（斜壁坡率感，m）
const EDGE_J := 0.05 # 沿边微扰幅度（m；确定性 ihash，去镜面平整感）
# 同层边「等高」阈值（2026-10-20）：旧 0.02 会把 0~2cm 高差当成等高、两侧都不画棱墙，
# 平顶间留一条透背景的细缝，远看即「六边地块边缘发光」。降到 1mm：只跳过真正等高，
# 任何可见高差都由高格画墙闭合；剖面 delta 另有 0.01 下限，薄墙会埋到低邻顶下，不会穿插。
const EDGE_MIN_DH := 0.001
# A8 顶面表现（2026-10-22）：
# 顶面不再逐格单色，改为「每顶点按世界坐标取色 + 微起伏 + 贴墙 AO」。
# 相邻格共享角点位置 → 角点高度/颜色恒等 → 大平面内部无拼板缝。
const TOP_RIPPLE_A := 0.055 # 缓丘主波幅（m；波长约 13m，全场连续）
const TOP_RIPPLE_B := 0.022 # 次波幅（m；斜向短波，打碎规则感）
const TOP_AO_CORNER := 0.26 # 单条贴墙边在角点处的 AO 压暗量（0=不压）
const TOP_AO_INNER := 0.12 # 同一方向内环（0.55r）处的压暗量（做窄一点的接触阴影）
# 空地散布（A8）：岩顶碎石之外，软地补极少量小碎石 + 干草丛，填满大片空地。
const PEBBLE_SALT := 913
const PEBBLE_DENSITY := 0.022
const GRASS_SALT := 947
const GRASS_DENSITY := 0.045
# 自然地形并台（2026-10-20 B；2026-10-21 扩为全场）：
# 场内相邻格先按「高度阈值 + 材质（SOLID/软地）」并块（块内取成员均值，消除逐格 5~15cm 的
# 拼板噪声），再把块高量化到 PLATE_STEP 的整倍（大块平面 + 干净踢脚，块内严格共面）。
# 只动 _cell_top / _plate_id（视觉层），不动 sim / ground_y / 拾取；边框圈不并；
# 玩家填/挖层（get_h≠0）不并，保证建造边缘和单位贴地零变化。
const PLATE_MERGE_DH := 0.42 # 原 0.16：只够吃掉噪声、吃不掉「一格一个高度」的蓝图起伏。提到 0.34 才能连成大片
const PLATE_STEP := 0.15 # 原 0.30：台阶差减半，痕迹更淡（H_STEP=1.2 仍是其整倍，填挖断言语义不变）
const PLATE_MAX_CELLS := 48 # 单块上限（格）：防止沿坡链式吞并把整张图并成一块
# 程序化岩块散布（2026-10-20 B2）：场内 SOLID 岩顶（台缘优先）与边框围墙顶撒低模碎岩——
# 打散拼板缝/锯齿顶。纯视觉、确定性哈希、单网格合并；RockProps 挂 HexField 子节点，
# 不改 sim/拾取，也不动 probe_scene/input 的 field_root 子节点结构。
const ROCK_PROP_SALT := 771
const ROCK_MOUTH_PAD := 0.6 # 出怪口沿周向额外留白（m）：在 RIM_MOUTH_W 豁口宽度上再让一圈
const ROCK_ICO_T := 1.618034
const ROCK_ICO_V := [
	Vector3(-1.0, ROCK_ICO_T, 0.0), Vector3(1.0, ROCK_ICO_T, 0.0),
	Vector3(-1.0, -ROCK_ICO_T, 0.0), Vector3(1.0, -ROCK_ICO_T, 0.0),
	Vector3(0.0, -1.0, ROCK_ICO_T), Vector3(0.0, 1.0, ROCK_ICO_T),
	Vector3(0.0, -1.0, -ROCK_ICO_T), Vector3(0.0, 1.0, -ROCK_ICO_T),
	Vector3(ROCK_ICO_T, 0.0, -1.0), Vector3(ROCK_ICO_T, 0.0, 1.0),
	Vector3(-ROCK_ICO_T, 0.0, -1.0), Vector3(-ROCK_ICO_T, 0.0, 1.0),
]
const ROCK_ICO_F := [
	Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
	Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
	Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
	Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
]

var host: Node3D
var core: ViewCoreScript

var field_root: Node3D

var grid: Grid = null
var field_h: PackedFloat64Array
var height_fn: Callable
var cur_palette: Dictionary = {}
var _gate_pts: Array = [] # 出怪口世界坐标（Vector2；四侧）：崖壁豁口对齐当局主口，空 = 无豁口

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
var _plate_id := PackedInt32Array() # 每格所属地块 ID（-1 = 不参与合并：边框圈/挖填层）；块内色相与高度共用
var _heights := PackedFloat64Array()
var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _ground: MeshInstance3D = null
var _hex: MeshInstance3D = null # 场内六棱板网格（顶面扇形 + 棱墙；随 _cell_top 重建）
var _rock_props: MeshInstance3D = null # 程序化岩块合并网格（HexField 子节点；随地形重建）
var _grass_props: MeshInstance3D = null # 干草丛合并网格（HexField 子节点；A8 软地散布）
var _grass_mat: StandardMaterial3D = null # 草材质（顶点色 albedo；双面；不投影）
var _rock_var_cache: Array = [] # 岩块变体 12 顶点缓存（几何与配色无关；配色在发射期上）
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
## anchor：地标位置对齐当局 Scenario（ridge_y/ridge_off/ridge_pts/basin_*/core gate_x/gate_pts）；
## 空 = 预设坐标（探针口径）。
func apply_blueprint(bp: Dictionary, bp_seed: int, anchor: Dictionary = {}) -> void:
	var composed: Array = Blueprint.compose(bp, bp_seed, anchor)
	height_fn = composed[0]
	cur_palette = composed[1]
	_gate_pts = []
	var gp: Variant = anchor.get("gate_pts", [])
	if typeof(gp) == TYPE_ARRAY and not gp.is_empty():
		for v in gp:
			var vv: Vector2 = v
			_gate_pts.append(vv)
	else:
		var gx: Variant = anchor.get("gate_x", []) # 历史锚：南向 x 列表（等价位 Vector2(gx, 32)）
		if typeof(gx) == TYPE_ARRAY:
			for v in gx:
				_gate_pts.append(Vector2(float(v), 32.0))

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
	if _grass_mat == null:
		# 干草：顶点色 = 根深梢浅；双面薄片，不投影（省移动端阴影预算）
		_grass_mat = StandardMaterial3D.new()
		# 2026-10-22 A8：细竖片在侧逆光下两面反差极大——受光面米白、背光面坠进冷调 ambient 读成黑点。
		# 改为不受光（亮度全由顶点色根深梢浅决定），远近、朝向都稳定，不再出现满地黑豇豆。
		_grass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_grass_mat.vertex_color_use_as_albedo = true
		_grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if core.env != null:
		var fog: Array = cur_palette["fog"]
		core.env.fog_light_color = Color(fog[0], fog[1], fog[2])
		core.set_fog_base(float(cur_palette["fog_start"]), float(cur_palette["fog_end"]))
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
	_sample_outside()
	_fill_field_region()
	_recompute_normals(0, _ln - 1)
	if _ground == null:
		_ground = MeshInstance3D.new()
		_ground.name = "Ground"
		_ground.material_override = _ground_mat
		field_root.add_child(_ground)
	_apply_mesh()
	_rebuild_hex()


## 场外区采样（2026-10-22 并行化）：每顶点 1 次高度 + 2 次邻域高度（`_outside_color` 求坡度）
## + 配色，实测占单局地形构建 ~60%。按行分段多线程计算（纯采样、不碰节点），再按行写回。
## 每个顶点仍按原顺序算同一公式 → 结果逐位一致（改前/改后截屏可像素级比对验证）。
func _sample_outside() -> void:
	var nt := clampi(OS.get_processor_count(), 1, 4) # 上限 4：再多人肉核收益小，且手机发热
	if nt <= 1 or _ln < 64:
		_merge_outside_chunk(_sample_outside_chunk(0, _ln))
		return
	var per := ceili(float(_ln) / float(nt))
	var threads: Array[Thread] = []
	for t in range(1, nt):
		var y0: int = t * per
		var y1: int = mini(y0 + per, _ln)
		if y0 >= y1:
			break
		var th := Thread.new()
		th.start(func() -> Dictionary:
			return _sample_outside_chunk(y0, y1))
		threads.append(th)
	# 主线程算第一段（与工作线程并行），再逐段回收
	_merge_outside_chunk(_sample_outside_chunk(0, mini(per, _ln)))
	for th in threads:
		_merge_outside_chunk(th.wait_to_finish())


## 采样 [y0, y1) 行里的场外行列（场内区留给 _fill_field_region）；返回分段数组。
func _sample_outside_chunk(y0: int, y1: int) -> Dictionary:
	var rows := y1 - y0
	var hs := PackedFloat64Array()
	var ps := PackedVector3Array()
	var cs := PackedColorArray()
	hs.resize(rows * _ln)
	ps.resize(rows * _ln)
	cs.resize(rows * _ln)
	var has_fn := not height_fn.is_null()
	for lj in range(y0, y1):
		var pz := _lattice[lj]
		var dst := (lj - y0) * _ln
		for li in _ln:
			if li >= _i0 and li <= _i1 and lj >= _i0 and lj <= _i1:
				continue
			var px := _lattice[li]
			var h := 0.0
			if has_fn:
				h = height_fn.call(px, pz)
			hs[dst + li] = h
			ps[dst + li] = Vector3(px, h, pz)
			cs[dst + li] = _outside_color(px, pz, h)
	return {"y0": y0, "y1": y1, "h": hs, "p": ps, "c": cs}


## 把分段采样结果写回整网格数组（场内区跳过）。
func _merge_outside_chunk(res: Dictionary) -> void:
	var y0: int = res["y0"]
	var y1: int = res["y1"]
	var hs: PackedFloat64Array = res["h"]
	var ps: PackedVector3Array = res["p"]
	var cs: PackedColorArray = res["c"]
	for lj in range(y0, y1):
		var src := (lj - y0) * _ln
		var dst := lj * _ln
		for li in _ln:
			if li >= _i0 and li <= _i1 and lj >= _i0 and lj <= _i1:
				continue
			_heights[dst + li] = hs[src + li]
			_positions[dst + li] = ps[src + li]
			_colors[dst + li] = cs[src + li]


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
	_merge_plate_tops()


## 自然地形并台（B，2026-10-21 扩为全场）：
## 场内所有「非边框圈、非挖填层」格按「高度（阈值内）+ 材质（SOLID/软地二分）」连通成块，
## 块内取高度均值后**量化到 PLATE_STEP 整倍** → 块内顶面严格等高 → _rebuild_hex 判同高、
## 不再画 1mm 级的逐格石阶唇线（原 EDGE_MIN_DH=0.001，5~15cm 的蓝图噪声导致满屏六边形格线）。
## 同时登记 _plate_id：_field_color 用它代替逐格坐标做哈希，块内色相完全一致。
## 只改 _cell_top / _plate_id；不碰 sim、ground_y、拾取。确定性：行主序种子 + 固定邻序。
func _merge_plate_tops() -> void:
	var n := core.CELL_N
	if grid == null or _cell_top.size() != n * n:
		return
	if _plate_id.size() != n * n:
		_plate_id.resize(n * n)
	_plate_id.fill(-1)
	var done := PackedByteArray()
	done.resize(n * n)
	var next_id := 0
	for y in n:
		for x in n:
			var i := y * n + x
			if done[i] == 1:
				continue
			# 边框圈不并（RIM_BUMP 周向起伏留给 A）；挖/填层不并（玩法要看见坑/堆）
			if x == 0 or y == 0 or x == n - 1 or y == n - 1 or grid.get_h(x, y) != 0:
				done[i] = 1
				continue
			var seed_h := _cell_top[i]
			var seed_solid: bool = grid.at(x, y) == Grid.SOLID
			var members: Array[int] = [i]
			var sum := seed_h
			done[i] = 1
			var qi := 0
			while qi < members.size() and members.size() < PLATE_MAX_CELLS:
				var j: int = members[qi]
				qi += 1
				var jx := j % n
				@warning_ignore("integer_division")
				var jy := j / n
				for k in 6:
					var nx := Grid.nx(jx, jy, k)
					var ny := Grid.ny(jx, jy, k)
					if nx <= 0 or ny <= 0 or nx >= n - 1 or ny >= n - 1:
						continue
					var i2 := ny * n + nx
					if done[i2] == 1 or grid.get_h(nx, ny) != 0:
						continue
					if (grid.at(nx, ny) == Grid.SOLID) != seed_solid:
						continue # 材质不同不并（沙地 / 岩顶 各自成块）
					if absf(_cell_top[i2] - seed_h) > PLATE_MERGE_DH:
						continue
					done[i2] = 1
					members.append(i2)
					sum += _cell_top[i2]
			var q := roundf((sum / float(members.size())) / PLATE_STEP) * PLATE_STEP
			for m in members:
				_cell_top[m] = q
				_plate_id[m] = next_id
			next_id += 1


## 岩块变体（惰性缓存）：二十面体 12 顶点径向抖动 + 压扁/拉宽（半径约 0.5m 的碎岩基形）。
func _rock_variant(vi: int) -> PackedVector3Array:
	while _rock_var_cache.size() <= vi:
		var idx := _rock_var_cache.size()
		var vs := PackedVector3Array()
		for i in 12:
			var v: Vector3 = ROCK_ICO_V[i]
			var r := 0.80 + 0.40 * Blueprint.ihash(idx * 17 + i, i * 29 + 7, 4811)
			var sx := 0.90 + 0.45 * Blueprint.ihash(i * 3 + 1, idx * 31 + 2, 9973)
			var sy := 0.55 + 0.40 * Blueprint.ihash(i * 5 + 4, idx * 37 + 6, 2027)
			vs.append(Vector3(v.x * r * sx, v.y * r * sy, v.z * r * sx) * 0.2629)
		_rock_var_cache.append(vs)
	return _rock_var_cache[vi]


## 发射一块岩：12 顶点变换（放大/压扁 + 绕 Y 旋转 + 抬升埋底）→ 20 面展平法线 + 逐面明度抖动。
## 顶点色 a=1（走地形 shader 的岩纹理三平面），rgb = 当前 palette 岩石色 × 面明度。
## bright：整体明度系数（岩石默认 1.35：岩纹理本就偏暗，乘上后暗面不再读成黑块）。
## flat_col：改按「浅沙石」常数上色（不走 palette 岩石色 / 岩纹理权值），供不受光的 GrassProps 网格用。
func _emit_rock(verts: PackedVector3Array, nrms: PackedVector3Array, cols: PackedColorArray, tri: PackedInt32Array, pos: Vector3, yaw: float, s: float, hs: float, vi: int, pid: int, bright: float = 1.35, flat_col: bool = false) -> void:
	var base := _rock_variant(vi)
	var cy := cos(yaw)
	var sy := sin(yaw)
	var tv := PackedVector3Array()
	for v in base:
		var lx := v.x * s
		var ly := v.y * s * hs + s * hs * 0.30 # 抬升：底部埋入顶面（不悬浮）
		var lz := v.z * s
		tv.append(Vector3(pos.x + lx * cy - lz * sy, pos.y + ly, pos.z + lx * sy + lz * cy))
	for fi in ROCK_ICO_F.size():
		var f: Vector3i = ROCK_ICO_F[fi]
		var va: Vector3 = tv[f.x]
		var vb: Vector3 = tv[f.y]
		var vc: Vector3 = tv[f.z]
		var nn := (vb - va).cross(vc - va)
		if nn.length_squared() < 1e-10:
			continue
		nn = nn.normalized()
		var k := 0.86 + 0.18 * Blueprint.ihash(pid * 131 + fi, pid * 17 + fi * 7, ROCK_PROP_SALT + 30)
		k *= 0.94 + 0.06 * (nn.y * 0.5 + 0.5) # 朝上面稍亮（低模岩石的轻明暗，不替代光照）
		k *= bright
		var c := Color(minf(_col_rock.r * k, 1.0), minf(_col_rock.g * k, 1.0), minf(_col_rock.b * k, 1.0), 1.0)
		if flat_col:
			# 浅沙石（A8 软地石粒）：GrassProps 走 unshaded，颜色即最终亮度，取沙地略偏暖的中调
			c = Color(minf(0.46 * k, 1.0), minf(0.38 * k, 1.0), minf(0.25 * k, 1.0), 1.0)
		var st := verts.size()
		verts.append(va)
		verts.append(vb)
		verts.append(vc)
		nrms.append(nn)
		nrms.append(nn)
		nrms.append(nn)
		cols.append(c)
		cols.append(c)
		cols.append(c)
		tri.append(st)
		tri.append(st + 1)
		tri.append(st + 2)


## 重建岩块散布（随地形重建）：场内 SOLID 岩顶台缘优先、密度低；边框围墙顶成带分布，
## 出怪口保留半径内不撒。全部走 Blueprint.ihash，同状态重建逐位一致。
func _rebuild_rock_props() -> void:
	if _hex == null or grid == null or _cell_top.size() != core.CELL_N * core.CELL_N:
		return
	if _rock_props == null:
		_rock_props = MeshInstance3D.new()
		_rock_props.name = "RockProps"
		_rock_props.material_override = _ground_mat
		_hex.add_child(_rock_props)
	var n := core.CELL_N
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var cols := PackedColorArray()
	var tri := PackedInt32Array()
	var pid := 0
	for y in n:
		for x in n:
			if grid.at(x, y) != Grid.SOLID:
				continue
			var i := y * n + x
			var t: float = _cell_top[i]
			var w := core.cell_to_world(x, y)
			if x == 0 or y == 0 or x == n - 1 or y == n - 1:
				# —— 边框围墙顶：成带岩脊，打散锯齿（出怪口豁口保留）——
				if Blueprint.ihash(x * 5 + 1, y * 5 + 3, ROCK_PROP_SALT) < 0.22:
					continue
				# 出怪口：gate_pts 是 spawn 格（径向坐标可落场内），只有侧别 + 切向坐标定义边框豁口；
				# 与 _rim_scale 同口径，沿切向留白 RIM_MOUTH_W + ROCK_MOUTH_PAD，避免碎石堵住视觉门。
				var rim_side := Blueprint.gate_side(w.x, w.z)
				var mouth := false
				for gp0 in _gate_pts:
					var gp: Vector2 = gp0
					if Blueprint.gate_side(gp.x, gp.y) != rim_side:
						continue
					var tang := absf(w.x - gp.x) if rim_side <= 1 else absf(w.z - gp.y)
					if tang < RIM_MOUTH_W + ROCK_MOUTH_PAD:
						mouth = true
						break
				if mouth:
					continue
				var s := 0.46 + 0.34 * Blueprint.ihash(x * 7 + 2, y * 7 + 5, ROCK_PROP_SALT + 1)
				var hs := 0.60 + 0.30 * Blueprint.ihash(x * 11 + 4, y * 11 + 6, ROCK_PROP_SALT + 2)
				var yaw := TAU * Blueprint.ihash(x * 13 + 8, y * 13 + 9, ROCK_PROP_SALT + 3)
				var ox := (Blueprint.ihash(x * 17 + 3, y * 17 + 4, ROCK_PROP_SALT + 4) - 0.5) * 0.22
				var oz := (Blueprint.ihash(x * 19 + 6, y * 19 + 7, ROCK_PROP_SALT + 5) - 0.5) * 0.26
				var vi := int(Blueprint.ihash(x * 23 + 9, y * 23 + 10, ROCK_PROP_SALT + 6) * 4.0)
				_emit_rock(verts, nrms, cols, tri, Vector3(w.x + ox, t - 0.06, w.z + oz), yaw, s, hs, vi, pid)
				pid += 1
				if Blueprint.ihash(x * 29 + 11, y * 29 + 12, ROCK_PROP_SALT + 7) < 0.30:
					var s2 := s * (0.55 + 0.25 * Blueprint.ihash(x * 31 + 13, y * 31 + 14, ROCK_PROP_SALT + 8))
					var yaw2 := yaw + 1.1 + Blueprint.ihash(x * 37 + 15, y * 37 + 16, ROCK_PROP_SALT + 9)
					var d2 := TAU * Blueprint.ihash(x * 43 + 19, y * 43 + 20, ROCK_PROP_SALT + 11)
					var o2 := 0.18 + 0.10 * Blueprint.ihash(x * 41 + 17, y * 41 + 18, ROCK_PROP_SALT + 10)
					var vi2 := int(Blueprint.ihash(x * 47 + 21, y * 47 + 22, ROCK_PROP_SALT + 12) * 4.0)
					_emit_rock(verts, nrms, cols, tri, Vector3(w.x + ox + cos(d2) * o2, t - 0.08, w.z + oz + sin(d2) * o2), yaw2, s2, hs * 0.9, vi2, pid)
					pid += 1
			else:
				# —— 场内岩顶：台缘（邻格非 SOLID 或台阶差 >5cm）优先，靠边放；块内稀疏点缀 ——
				var edge := false
				var ex := 0.0
				var ez := 0.0
				for k in 6:
					var nx := Grid.nx(x, y, k)
					var ny := Grid.ny(x, y, k)
					if nx < 0 or ny < 0 or nx >= n or ny >= n:
						continue
					var i2 := ny * n + nx
					if grid.at(nx, ny) != Grid.SOLID or absf(_cell_top[i2] - t) > 0.05:
						edge = true
						var w2 := core.cell_to_world(nx, ny)
						ex += w2.x - w.x
						ez += w2.z - w.z
				if Blueprint.ihash(x * 3 + 1, y * 3 + 2, ROCK_PROP_SALT + 20) >= (0.55 if edge else 0.26):
					continue
				var s := (0.30 + 0.24 * Blueprint.ihash(x * 7 + 1, y * 7 + 2, ROCK_PROP_SALT + 21)) * (1.15 if edge else 0.9)
				var hs := 0.55 + 0.35 * Blueprint.ihash(x * 11 + 3, y * 11 + 4, ROCK_PROP_SALT + 22)
				var yaw := TAU * Blueprint.ihash(x * 13 + 5, y * 13 + 6, ROCK_PROP_SALT + 23)
				var px := 0.0
				var pz := 0.0
				if edge and absf(ex) + absf(ez) > 0.001:
					var l := sqrt(ex * ex + ez * ez)
					px = ex / l * 0.17
					pz = ez / l * 0.17
				else:
					px = (Blueprint.ihash(x * 17 + 7, y * 17 + 8, ROCK_PROP_SALT + 24) - 0.5) * 0.30
					pz = (Blueprint.ihash(x * 19 + 9, y * 19 + 10, ROCK_PROP_SALT + 25) - 0.5) * 0.36
				var vi := int(Blueprint.ihash(x * 23 + 11, y * 23 + 12, ROCK_PROP_SALT + 26) * 4.0)
				_emit_rock(verts, nrms, cols, tri, Vector3(w.x + px, t - 0.05, w.z + pz), yaw, s, hs, vi, pid)
				pid += 1
				if Blueprint.ihash(x * 29 + 13, y * 29 + 14, ROCK_PROP_SALT + 27) < 0.30:
					var s2 := s * (0.55 + 0.25 * Blueprint.ihash(x * 31 + 15, y * 31 + 16, ROCK_PROP_SALT + 28))
					var yaw2 := yaw + 1.4 + Blueprint.ihash(x * 37 + 17, y * 37 + 18, ROCK_PROP_SALT + 29)
					var d2 := TAU * Blueprint.ihash(x * 43 + 21, y * 43 + 22, ROCK_PROP_SALT + 13)
					var o2 := 0.16 + 0.10 * Blueprint.ihash(x * 41 + 19, y * 41 + 20, ROCK_PROP_SALT + 14)
					var vi2 := int(Blueprint.ihash(x * 47 + 23, y * 47 + 24, ROCK_PROP_SALT + 15) * 4.0)
					_emit_rock(verts, nrms, cols, tri, Vector3(w.x + px + cos(d2) * o2, t - 0.07, w.z + pz + sin(d2) * o2), yaw2, s2, hs * 0.9, vi2, pid)
					pid += 1
	# —— 地块边缘碎石（2026-10-21 并台配套）：非 SOLID 的块边界沿法向压一圈低矮碎石，
	# 把「六边形折线」遮掉，让地块轮廓看起来是自然岩缘而不是拼板。密度低于岩顶，尺寸更小。
	if _plate_id.size() == n * n:
		for y in range(1, n - 1):
			for x in range(1, n - 1):
				if grid.at(x, y) == Grid.SOLID:
					continue
				var pi0 := y * n + x
				var t0: float = _cell_top[pi0]
				var my_id := _plate_id[pi0]
				var ex0 := 0.0
				var ez0 := 0.0
				var dv_max := 0.0
				for kk in 6:
					var nx := Grid.nx(x, y, kk)
					var ny := Grid.ny(x, y, kk)
					if nx <= 0 or ny <= 0 or nx >= n - 1 or ny >= n - 1:
						continue
					var ni := ny * n + nx
					if _plate_id[ni] != my_id:
						var dv := t0 - _cell_top[ni]
						if dv > dv_max:
							dv_max = dv
							var w2 := core.cell_to_world(nx, ny)
							ex0 += w2.x
							ez0 += w2.z
				# 只在「真台阶」边缘撒（高差 ≥ 2 档 ≈ 0.6m 以上）；1 档缓坡边保持干净，
				# 否则沿缓坡排一圈碎石会变成地上的黑麻点，比原折线更难看。
				if dv_max < 0.50: # 绝对值（不随 PLATE_STEP 变）：只有半个身位以上的真台阶边缘才撒碎石
					continue
				if Blueprint.ihash(x * 3 + 5, y * 3 + 7, ROCK_PROP_SALT + 40) >= 0.55:
					continue
				var w0 := core.cell_to_world(x, y)
				var l0 := maxf(sqrt(ex0 * ex0 + ez0 * ez0), 0.001)
				var s0 := 0.26 + 0.20 * Blueprint.ihash(x * 7 + 3, y * 7 + 9, ROCK_PROP_SALT + 41)
				var hs0 := 0.55 + 0.32 * Blueprint.ihash(x * 11 + 5, y * 11 + 6, ROCK_PROP_SALT + 42)
				var yaw0 := TAU * Blueprint.ihash(x * 13 + 7, y * 13 + 8, ROCK_PROP_SALT + 43)
				var vi0 := int(Blueprint.ihash(x * 23 + 9, y * 23 + 12, ROCK_PROP_SALT + 44) * 4.0)
				_emit_rock(verts, nrms, cols, tri, Vector3(w0.x + ex0 / l0 * 0.80, t0 - 0.05, w0.z + ez0 / l0 * 0.80), yaw0, s0, hs0, vi0, pid)
				pid += 1
	# —— 软地小石粒（A8）已移交 GrassProps（见 _rebuild_grass_props）：岩石网格吃光影，
	# 几厘米的碎粒只剩背光侧壁会读成黑点/黑框，改由不受光的网格以浅沙石色绘制。
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = tri
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rock_props.mesh = mesh


## 重建干草丛散布（A8）：软地开阔格低密度、靠岩/台缘略密；确定性哈希，单网格合并。
## 与 RockProps 分开节点（probe_scene 约定 RockProps 单 surface 且顶点预算不变）；
## 薄片双面、不投影，挂 HexField 子节点，不进 field_root 直接子节点。
func _rebuild_grass_props() -> void:
	if _hex == null or grid == null or _cell_top.size() != core.CELL_N * core.CELL_N:
		return
	if _grass_props == null:
		_grass_props = MeshInstance3D.new()
		_grass_props.name = "GrassProps"
		_grass_props.material_override = _grass_mat
		_grass_props.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hex.add_child(_grass_props)
	var n := core.CELL_N
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var cols := PackedColorArray()
	var tri := PackedInt32Array()
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			if grid.at(x, y) == Grid.SOLID or grid.get_h(x, y) != 0:
				continue
			var t: float = _cell_top[y * n + x]
			# 靠岩/台缘加密：邻格是 SOLID 或与本地块有高差 → 草丛沿边缘聚拢
			var near := 0
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx < 0 or ny < 0 or nx >= n or ny >= n:
					continue
				if grid.at(nx, ny) == Grid.SOLID or absf(_cell_top[ny * n + nx] - t) > 0.05:
					near += 1
			var dens := GRASS_DENSITY + 0.045 * float(near)
			if Blueprint.ihash(x * 5 + 2, y * 5 + 7, GRASS_SALT) >= dens:
				continue
			var w := core.cell_to_world(x, y)
			var tufts := 1 + int(Blueprint.ihash(x * 31 + 3, y * 31 + 4, GRASS_SALT + 1) * 2.0)
			for j in tufts:
				var ox := (Blueprint.ihash(x * 13 + j * 7, y * 13 + j, GRASS_SALT + 2) - 0.5) * 0.55
				var oz := (Blueprint.ihash(x * 17 + j * 5, y * 17 + j * 3, GRASS_SALT + 3) - 0.5) * 0.60
				var s := 1.0 + 0.55 * Blueprint.ihash(x * 19 + j, y * 19 + j * 5, GRASS_SALT + 4) # 单簇整体放大约 1.3×（远看不再像噪点）
				var yaw := TAU * Blueprint.ihash(x * 23 + j * 3, y * 23 + j * 7, GRASS_SALT + 5)
				_emit_grass(verts, nrms, cols, tri, Vector3(w.x + ox, t - 0.015, w.z + oz), yaw, s, x * 7 + y * 13 + j)
	# —— 软地小石粒（A8）：与草同一不受光网格，浅沙石色，填掉空地的大片空白。
	# 确定性哈希；尺寸远小于岩顶碎石，密度低。
	var pid := 0
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			if grid.at(x, y) == Grid.SOLID or grid.get_h(x, y) != 0:
				continue
			if Blueprint.ihash(x * 7 + 5, y * 7 + 9, PEBBLE_SALT) >= PEBBLE_DENSITY:
				continue
			var t1: float = _cell_top[y * n + x]
			var w1 := core.cell_to_world(x, y)
			var s1 := 0.13 + 0.09 * Blueprint.ihash(x * 11 + 2, y * 11 + 3, PEBBLE_SALT + 1)
			var hs1 := 0.30 + 0.15 * Blueprint.ihash(x * 13 + 4, y * 13 + 6, PEBBLE_SALT + 2)
			var yaw1 := TAU * Blueprint.ihash(x * 17 + 7, y * 17 + 8, PEBBLE_SALT + 3)
			var ox1 := (Blueprint.ihash(x * 19 + 1, y * 19 + 2, PEBBLE_SALT + 4) - 0.5) * 0.50
			var oz1 := (Blueprint.ihash(x * 23 + 3, y * 23 + 5, PEBBLE_SALT + 6) - 0.5) * 0.55
			var vi1 := int(Blueprint.ihash(x * 29 + 8, y * 29 + 9, PEBBLE_SALT + 7) * 4.0)
			_emit_rock(verts, nrms, cols, tri, Vector3(w1.x + ox1, t1 - 0.008, w1.z + oz1), yaw1, s1, hs1, vi1, pid, 1.0, true)
			pid += 1
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = tri
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_grass_props.mesh = mesh


## 发射一簇干草：3 片交叉薄片（根窄梢宽、向上收尖），顶点色根深梢浅；法线统一朝上（软受光）。
func _emit_grass(verts: PackedVector3Array, nrms: PackedVector3Array, cols: PackedColorArray, tri: PackedInt32Array, pos: Vector3, yaw: float, s: float, variant_seed: int) -> void:
	var hgt := (0.26 + 0.18 * Blueprint.ihash(variant_seed, 11, GRASS_SALT + 10)) * s
	var half := (0.036 + 0.020 * Blueprint.ihash(variant_seed, 13, GRASS_SALT + 11)) * s
	var lean := (0.06 + 0.07 * Blueprint.ihash(variant_seed, 17, GRASS_SALT + 12)) * s
	var dry := Blueprint.ihash(variant_seed, 19, GRASS_SALT + 13)
	# 干草配色（A8）：枯黄。GrassProps 走 unshaded（见 _grass_mat 注释），顶点色即最终亮度，
	# 故取「沙地略暗一档」的中调：太亮会成白棍，太暗会成黑点。
	var base_c := Color(0.13 + 0.04 * dry, 0.115 + 0.03 * dry, 0.055 + 0.015 * dry, 1.0)
	var tip_c := Color(0.26 + 0.05 * dry, 0.23 + 0.045 * dry, 0.105 + 0.02 * dry, 1.0)
	for p in 3:
		var ang := yaw + float(p) * 1.0471976
		var dx := cos(ang)
		var dz := sin(ang)
		# 垂直薄片方向 + 倾斜方向
		var px := -dz * half
		var pz := dx * half
		var lx := dx * lean
		var lz := dz * lean
		var b0 := verts.size()
		verts.append(Vector3(pos.x - px, pos.y, pos.z - pz))
		verts.append(Vector3(pos.x + px, pos.y, pos.z + pz))
		verts.append(Vector3(pos.x + px * 0.35 + lx, pos.y + hgt, pos.z + pz * 0.35 + lz))
		verts.append(Vector3(pos.x - px * 0.35 + lx, pos.y + hgt, pos.z - pz * 0.35 + lz))
		for _i in 4:
			nrms.append(Vector3.UP)
		cols.append(base_c)
		cols.append(base_c)
		cols.append(tip_c)
		cols.append(tip_c)
		tri.append(b0)
		tri.append(b0 + 1)
		tri.append(b0 + 2)
		tri.append(b0)
		tri.append(b0 + 2)
		tri.append(b0 + 3)


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
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# 逐格复用（避免 4096 次小数组分配）
	var wall := PackedByteArray()
	var tlo := PackedFloat64Array()
	var inb := PackedByteArray()
	var nbr := PackedInt32Array()
	wall.resize(6)
	tlo.resize(6)
	inb.resize(6)
	nbr.resize(6)
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
			# 2026-10-21：色阶按「原始连续高度」取（field_h），只让几何走并台量化值。
			# 否则块高跨档会让 _col_lo/_col_hi（差 2.4 倍）整块跳色，出现刺眼的大色补丁。
			var col := _field_color(field_h[y * n + x], solid, slope, x, y, _plate_id[y * n + x] if _plate_id.size() == n * n else -1)
			# —— 棱边判定（顶面 AO 与棱墙共用；墙仅由高格一侧拥有）——
			for k3 in 6:
				var nx3 := Grid.nx(x, y, k3)
				var ny3 := Grid.ny(x, y, k3)
				if nx3 >= 0 and ny3 >= 0 and nx3 < n and ny3 < n:
					inb[k3] = 1
					nbr[k3] = ny3 * n + nx3
					var t3 := _cell_top[ny3 * n + nx3]
					tlo[k3] = t3
					wall[k3] = 1 if t > t3 + EDGE_MIN_DH else 0
				else:
					inb[k3] = 0
					nbr[k3] = -1
					var ca3: Vector2 = core.HEX_CORNERS[HEX_EDGE_A[k3]]
					var cb3: Vector2 = core.HEX_CORNERS[HEX_EDGE_B[k3]]
					tlo[k3] = minf(ground_h(w.x + ca3.x, w.z + ca3.y), ground_h(w.x + cb3.x, w.z + cb3.y)) - WALL_EMBED
					# 2026-10-23 负高度：界外地面可能高于本格顶（本格是低侧）。此时不画反向剖面
					# （否则剖面末点被抬回 t_lo-0.01 → 高于顶面的向上尖楔），由更高的界外地面自闭合。
					wall[k3] = 1 if t > tlo[k3] + EDGE_MIN_DH else 0
			# —— 顶面：中心 + 内环(0.55r) + 角环，逐顶点世界取色/起伏/AO ——
			# 角环高度差恒为 0：相邻格共享角点，大平面内不会出现拼板缝；棱墙仍以角环高为顶。
			# 角点色用「共享该角的 3 格 field_h 均值」→ 三格各自算出的结果相同（无色差缝）。
			var h0 := field_h[y * n + x]
			var low: bool = grid != null and grid.get_h(x, y) < 0 # 负高度坑底（色阶走低洼沙色，不刷岩面）
			var base := verts.size()
			var r0 := _top_ripple(w.x, w.z)
			verts.append(Vector3(w.x, t + r0.x, w.z))
			nrms.append((nrm + Vector3(-r0.y, 0.0, -r0.z)).normalized())
			cols.append(_field_color_at(w.x, w.z, h0, solid, slope, low))
			uvs.append(Vector2(1.0, 0.0))
			for i in 6:
				var ew: Array = HEX_CORNER_EDGES[i]
				var e0: int = ew[0]
				var e1: int = ew[1]
				var hsum := h0
				var hcnt := 1
				if nbr[e0] >= 0:
					hsum += field_h[nbr[e0]]
					hcnt += 1
				if nbr[e1] >= 0:
					hsum += field_h[nbr[e1]]
					hcnt += 1
				var hc := hsum / float(hcnt)
				var c2: Vector2 = core.HEX_CORNERS[i]
				var ax := w.x + c2.x * 0.55
				var az := w.z + c2.y * 0.55
				var r1 := _top_ripple(ax, az)
				verts.append(Vector3(ax, t + r1.x * 0.62, az))
				nrms.append((nrm + Vector3(-r1.y, 0.0, -r1.z) * 0.62).normalized())
				cols.append(_field_color_at(ax, az, lerpf(h0, hc, 0.55), solid, slope, low))
				var ao_in := 1.0 - TOP_AO_INNER * (float(wall[e0]) + float(wall[e1])) * 0.5
				uvs.append(Vector2(ao_in, 0.0))
			for i in 6:
				var c3: Vector2 = core.HEX_CORNERS[i]
				var bx := w.x + c3.x
				var bz := w.z + c3.y
				var ew2: Array = HEX_CORNER_EDGES[i]
				var e0b: int = ew2[0]
				var e1b: int = ew2[1]
				var hsum2 := h0
				var hcnt2 := 1
				if nbr[e0b] >= 0:
					hsum2 += field_h[nbr[e0b]]
					hcnt2 += 1
				if nbr[e1b] >= 0:
					hsum2 += field_h[nbr[e1b]]
					hcnt2 += 1
				verts.append(Vector3(bx, t, bz))
				nrms.append(nrm)
				cols.append(_field_color_at(bx, bz, hsum2 / float(hcnt2), solid, slope, low))
				var ao_out := 1.0 - TOP_AO_CORNER * (float(wall[e0b]) + float(wall[e1b])) * 0.5
				uvs.append(Vector2(maxf(ao_out, 0.35), 0.0))
			# 中心 → 内环扇形（顶点序号：base=中心，base+1+i=内环，base+7+i=角环）
			for i2 in 6:
				idx.append(base)
				idx.append(base + 1 + i2)
				idx.append(base + 1 + (i2 + 1) % 6)
			# 内环 → 角环环带
			for i2 in 6:
				var j2 := (i2 + 1) % 6
				idx.append(base + 1 + i2)
				idx.append(base + 7 + i2)
				idx.append(base + 7 + j2)
				idx.append(base + 1 + i2)
				idx.append(base + 7 + j2)
				idx.append(base + 1 + j2)
			# 棱边剖面（2026-10-17 自然化 T1）：圆唇 + 斜壁/边坡 + 微扰；高格一侧拥有该边。
			for k2 in 6:
				if wall[k2] == 0:
					continue # 同高/我低（低侧由对面格画）
				var ca: Vector2 = core.HEX_CORNERS[HEX_EDGE_A[k2]]
				var cb: Vector2 = core.HEX_CORNERS[HEX_EDGE_B[k2]]
				var ax := w.x + ca.x
				var az := w.z + ca.y
				var bx := w.x + cb.x
				var bz := w.z + cb.y
				var t_lo := tlo[k2]
				var both := inb[k2] == 0
				var kind := edge_kind_at(x, y, k2) if both == false else EDGE_CLIFF
				var prof := edge_profile(x, y, k2, t, t_lo, kind)
				var wd := Vector3(cb.x - ca.x, 0.0, cb.y - ca.y)
				var wn := Vector3(wd.z, 0.0, -wd.x).normalized() # 面朝邻居（外法线）
				var wdn := wd.normalized() # 沿边方向（非顶层点外延闭角用）
				@warning_ignore("integer_division")
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
						uvs.append(Vector2(1.0, 0.0))
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
							uvs.append(Vector2(1.0, 0.0))
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
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _hex == null:
		_hex = MeshInstance3D.new()
		_hex.name = "HexField"
		_hex.material_override = _ground_mat
		field_root.add_child(_hex)
	_hex.mesh = mesh
	_rebuild_rock_props()
	_rebuild_grass_props()


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
	# 2026-10-23 高度域 -2..5：可爬性真值 = 落差 1..2 可爬（流场边权 +10/级），≥3 不可通行。
	if dh >= 3:
		return EDGE_CLIFF
	if dh >= 1:
		return EDGE_RAMP
	# 2026-10-21 并台：同一模拟层内也会出现 0.30 的视觉台阶（PLATE_STEP 量化产物）。
	# 差 1 档 → 缓坡（可走感连续）；差 2 档以上 → 当崖壁处理。
	if _cell_top.size() == n * n:
		var dv := absf(_cell_top[y * n + x] - _cell_top[ny * n + nx])
		if dv > 0.08:
			return EDGE_RAMP if dv <= 0.45 else EDGE_CLIFF
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
		# 2026-10-21：并台小台阶（delta ≤ 0.55）拉长到 0.85m 跨度 → 约 19°，接近自然缓起伏；
		# 模拟层的 1.2m 落差仍走原比例，跨度不变、不侵入邻格。
		if delta <= 0.55:
			run = maxf(run, 0.85)
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
		# 2026-10-21：缓坡/微差边的圆唇不再压暗 13%（那是台阶痕迹的主体），只有崖壁保留
		out = col.darkened(0.13 if kind == EDGE_CLIFF else 0.045)
	elif kind == EDGE_RAMP:
		out = col.lerp(_col_lo, 0.10) if sj == 2 else col.lerp(_col_lo, 0.16)
		a = minf(col.a * 0.45, 1.0)
	elif kind == EDGE_CLIFF:
		var band := 0.5 + 0.5 * sin(h_mid * 8.7 + float(x) * 0.7 + float(y) * 0.5 + float(sj) * 1.7)
		var band2 := 0.5 + 0.5 * sin(h_mid * 2.9 + float(x) * 0.23 + float(y) * 0.41)
		if sj == 4: # 裙脚回勾底面（近地暗缝，多为遮挡）
			out = col.lerp(_col_rock, 0.30).darkened(0.34)
		elif sj == 3: # 下段坡 + 渣坡裙脚：暖色碎渣带（掺沙纹，贴地碎屑感）
			var banda := 0.5 + 0.5 * sin(h_mid * 6.1 + float(x) * 0.51 + float(y) * 0.37)
			out = col.lerp(_col_lo, 0.26).darkened(0.06 - 0.08 * banda)
			out = Color(maxf(out.r, 0.30), maxf(out.g, 0.25), maxf(out.b, 0.16), out.a)
			a = minf(col.a + 0.18, 1.0)
		else:
			out = col.lerp(_col_rock, 0.26)
			out = out.darkened(0.02 if sj == 2 else 0.10)
			var tone := 0.96 + 0.11 * band + 0.07 * band2
			if tag < 0.24:
				tone += 0.08 # 明面（亮岩带）
			out = Color(maxf(out.r * tone, 0.32), maxf(out.g * tone, 0.27), maxf(out.b * tone, 0.19), out.a) # 暖色地板防死黑
			a = minf(col.a + 0.35, 1.0)
	else: # EDGE_MICRO
		var bandm := 0.5 + 0.5 * sin(h_mid * 7.3 + float(x) * 0.6 + float(y) * 0.45 + float(sj) * 2.1)
		var inm := col.lerp(_col_rock, 0.22).darkened(0.12 - 0.08 * bandm)
		out = Color(maxf(inm.r, 0.26), maxf(inm.g, 0.21), maxf(inm.b, 0.15), inm.a)
		a = minf(col.a + 0.30, 1.0)
	var kj := 0.97 + 0.06 * Blueprint.ihash(x * 29 + k * 11 + sj * 3, y * 23 + sj * 5, 4457)
	return Color(clampf(out.r * kj, 0.0, 1.0), clampf(out.g * kj, 0.0, 1.0), clampf(out.b * kj, 0.0, 1.0), a)


## 边框崖壁高度系数：周向确定性起伏（去直边皱褶感）+ 出怪口豁口（对齐当局主口，四侧：
## 本格侧别与口侧别一致才吃横向高斯；南向历史锚等价位 Vector2(gx, 32)）。
func _rim_scale(x: int, y: int) -> float:
	var s := 0.70 + 0.55 * Blueprint.ihash(x * 7 + 3, y * 7 - 5, 5521)
	if not _gate_pts.is_empty():
		var w := core.cell_to_world(x, y) # 六边 odd-r：奇行 +0.5，必须走统一映射
		var side := Blueprint.gate_side(w.x, w.z)
		var m := 0.0
		for gp0 in _gate_pts:
			var gp: Vector2 = gp0
			if Blueprint.gate_side(gp.x, gp.y) != side:
				continue
			var u := 0.0
			if side <= 1:
				u = (w.x - gp.x) / RIM_MOUTH_W # 南/北口：横向沿 x
			else:
				u = (w.z - gp.y) / RIM_MOUTH_W # 东/西口：横向沿 z
			m = maxf(m, exp(-u * u))
		s *= 1.0 - 0.85 * m # 豁口处崖壁近乎归零（留 1.6m SOLID 门槛石）
	return s


## 顶面缓丘：世界坐标连续双波（返回 (高度, d/dx, d/dz)）。
## 角点必须始终为 0（调用方只取中心/内环 → 相邻格共享角点高度恒等，无拼板台阶）。
func _top_ripple(px: float, pz: float) -> Vector3:
	var a := TOP_RIPPLE_A
	var b := TOP_RIPPLE_B
	var c1 := cos(px * 0.47 + 0.8) * cos(pz * 0.41 - 0.35)
	var c2 := cos((px + pz) * 1.03 + 1.7)
	var h := a * sin(px * 0.47 + 0.8) * cos(pz * 0.41 - 0.35) + b * sin((px + pz) * 1.03 + 1.7)
	var dx := a * 0.47 * c1 + b * 1.03 * c2
	var dz := -a * 0.41 * sin(px * 0.47 + 0.8) * sin(pz * 0.41 - 0.35) + b * 1.03 * c2
	return Vector3(h, dx, dz)


## 场内顶点色（A8 逐顶点版）：输入世界坐标 → 相邻格共享角点颜色恒等，消除逐格色块。
## 与 _field_color 的差别：色斑/层理/明度全部用世界坐标正弦（连续），不再按格/块哈希。
## low = 负高度坑底（2026-10-23）：抬高坡度岩权会把坑底刷成深色岩块，视觉上读成「凸起的石板」；
## 这里压回低岩权并掺一点低洼沙色 → 坑底仍是沙地，靠坑壁阴影读下沉。
func _field_color_at(px: float, pz: float, h: float, solid: bool, slope: float, low: bool = false) -> Color:
	var patch := 0.5 + 0.5 * sin(px * 0.21 + pz * 0.17 + 1.1) * sin(pz * 0.19 - px * 0.13 + 0.4)
	if solid:
		var rk := 0.94 + 0.10 * patch
		return Color(clampf(_col_rock.r * rk, 0.0, 1.0), clampf(_col_rock.g * rk, 0.0, 1.0), clampf(_col_rock.b * rk, 0.0, 1.0), 1.0)
	var t := 0.0
	if h >= _band_hi:
		t = 1.0
	elif h > _band_lo:
		t = (h - _band_lo) / maxf(_band_hi - _band_lo, 0.001)
	var base: Color
	if t < 0.5:
		base = _col_lo.lerp(_col_mid, Blueprint.smooth01(t * 2.0))
	else:
		base = _col_mid.lerp(_col_hi, Blueprint.smooth01((t - 0.5) * 2.0))
	base = base.lerp(_col_lo, 0.05 * clampf((patch - 0.5) * 2.0, 0.0, 1.0))
	var strata := 0.5 + 0.5 * sin(h * 5.3 + px * 0.27 + pz * 0.19)
	var k := (0.985 + 0.035 * (patch - 0.5) * 2.0) * (0.99 + 0.02 * strata)
	var rock_mix := clampf((slope - 0.45) / 1.2, 0.0, 0.72)
	if low:
		rock_mix = minf(rock_mix, 0.18)
		base = base.lerp(_col_lo, 0.18)
	return Color(clampf(base.r * k, 0.0, 1.0), clampf(base.g * k, 0.0, 1.0), clampf(base.b * k, 0.0, 1.0), rock_mix)


## 场内顶点色：高程三档连续混色 + 坡度岩石化 + 层理与确定性明度抖动（对齐宣传图崖面观感）。
func _field_color(h: float, solid: bool, slope: float, cx: int, cy: int, pid: int = -1) -> Color:
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
	# 色斑/层理/明度抖动：并入地块后按块 ID 取哈希（块内完全一致 → 看起来是一整片地面）；
	# 边框圈与挖填层（pid < 0）退回逐格口径，保持原表现。
	var hx := cx
	var hy := cy
	if pid >= 0:
		hx = pid % 97
		@warning_ignore("integer_division")
		hy = pid / 97
	@warning_ignore("integer_division")
	var patch := Blueprint.ihash(hx / 4, hy / 4, 4441) # 块状干燥色斑（破单色台面）
	# 2026-10-21 并台后：色斑/明度按「块」取值，块会变得很大，幅度必须比逐格时代小，
	# 否则相邻块之间会出现明显的亮暗补丁（0.13/±9% → 0.07/±3%）。
	base = base.lerp(_col_lo, 0.07 * clampf((patch - 0.55) * 2.5, 0.0, 1.0))
	var strata := 0.5 + 0.5 * sin(h * 5.3 + float(hx) * 0.7 + float(hy) * 0.4)
	var k := (0.97 + 0.06 * Blueprint.ihash(hx * 3 + 11, hy * 3 - 7, 917)) * (0.98 + 0.04 * strata)
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
