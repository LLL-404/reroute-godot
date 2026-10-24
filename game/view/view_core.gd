extends RefCounted

# 《改道》视图层 · 坐标与基建（D5-1 拆分自 view.gd）：64² 坐标映射、盒体/材质工具、
# 相机取景与屏幕投影、相机操控（WASD 平移 / 右键拖拽 / QE 旋转 / 滚轮缩放）。
# 零 sim 引用（只被 terrain/entities 当几何底座）；节点挂点统一走 host。

const CELL_N := 64
const HALF := 32.0
const H_STEP := 1.2 # sim 高度层 1.2m/级
const MAP_MIN_VISIBLE := 0.75 # 平移时地图至少占屏幕面积的比例（场外最多露 1/4）

# 取景留边（px 基准）：上让顶栏（实高 56）、右让按钮带（列宽 160）、下让提示余量（同母版口径）
# 2026-10-22：左留白归零 —— 原按左右对称各留 160px 推导，左侧纯属对称留白，画面左缘露出
# 一大片场外沙地（即玩家说的「太远、能看到地图外面空旷的地方」）。改为地图左缘贴屏幕左缘、
# 水平中心压到可交互区中心：镜头前进约 10%，地图占屏 +17%，顶部/底部场外同时收窄。
const RESERVE_TOP := 56.0
const RESERVE_RIGHT := 160.0
const RESERVE_BOTTOM := 22.0
const RESERVE_LEFT := 0.0
# 2026-10-23：俯角固定 42°（原 36..52 二分贴边）。FOV 45→30 后近大远小减半，
# 不再靠抬高俯角去撑满纵向——52° 会把高度差压平却没有消掉透视缩短。
const PITCH_DEG := 42.0
const CAM_FOV := 30.0

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

var host: Node3D

var box_mesh: BoxMesh
var mats: Dictionary = {}
var env: Environment
var sun: DirectionalLight3D
var _dof_attrs: CameraAttributesPractical = null # 景深属性（懒建；关闭时不挂相机）
var _post_q := 2 # 后期处理档（雾距倍率：低 1.6× / 中 1.25× / 高 1.0×）
var _fog_base := Vector2(55.0, 170.0) # 当前地图视觉动机的雾起止基准（view_terrain 应用调色板时写入）
var _fog_fit_mult := 1.0 # 取景视距外推系数：雾基准按横屏 ~76m 取景调；竖屏/小窗视距被推远时同步外推，否则地图被雾吞成纯背景色

var camera: Camera3D
var focus := Vector3.ZERO # 相机注视的地面点（y=0；平移/旋转围绕它）
var yaw := 0.0 # 水平旋转（绕 Y，正 = 左旋；QE 修改）
var _pitch := 0.0 # 基准俯角（rad，取景时定；操控不改）
var _dist := 0.0 # 相机到 focus 的基准距离（取景时定；滚轮缩放叠乘 _zoom）
var _zoom := 1.0 # 滚轮缩放倍率（0.6–1.8；取景重置 1.0）
var _fit_pull := 0.90 # 取景后的额外拉近系数（<1 = 更近）：0.90 = 地图四边各溢出约半格~一格，画面几乎全是地图
# 震屏（B3）：只做平移抖动，不旋转相机 —— 旋转会让 world_to_screen 缓存与 HUD 对位漂移。
var shake_on := true # 探针运行时关闭（截图不能被抖偏，像素校验口径）
var shake_t := 0.0 # 剩余时间（秒）
var shake_dur := 0.0 # 本次总时长（秒；衰减分母）
var shake_amp := 0.0 # 峰值幅度（米）
var shake_phase := 0.0 # 相位推进（秒×42）
var _fit: Dictionary = {}
var _fit_w := 0.0
var _fit_h := 0.0


## 构造注入：记宿主节点（环境/灯光/相机挂其下；由 view._ready 组装）
func _init(p_host: Node3D) -> void:
	host = p_host


## 渲染基建（原 view._ready 前段）：盒体原型 + 环境/雾/灯光 + 全色板材质。
func setup() -> void:
	box_mesh = BoxMesh.new()
	box_mesh.size = Vector3.ONE

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.44, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.42, 0.64) # 冷调天光：A8 减低饱和，暗部从蓝黑回到冷棕
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_ACES # 2026-10-21：线性 tonemap 下 1.45 的主光会削顶，换 ACES 收高光
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.60, 0.47, 0.34)
	env.fog_depth_begin = 55.0
	env.fog_depth_end = 170.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	host.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.84, 0.62) # 金色时刻暖阳（对齐宣传图）
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-46.0, -24.0, 0.0) # 2026-10-21：-58/10 → -46/-24。原角度投影几乎全被崖体自身遮住，斜侧主光让地面出现可见投影、拉出立体感
	# 2026-10-21：相机距地图中心约 81m，默认 100m + fade_start 0.8 → 主场区正好落在淡出区，投影在实机视角几乎不可见。
	# 拉长到 190m 并关掉淡出，让整片场地都在阴影覆盖内。
	sun.directional_shadow_max_distance = 190.0
	sun.directional_shadow_fade_start = 1.0
	# 法线偏移 2.0m 会把 1m 级岩块的投影整个推没（远景只能看到 3m 以上的大件才有影），收到 0.35m。
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.35
	host.add_child(sun)

	# 暖补光（A8 改造）：原先是从背侧补的冷光，背光崖壁仍被压成蓝黑；改为暖琥珀色侧补，
	# 让镜头可见的背光岩面读出「暗棕岩石」而不是黑洞。不投影，能量低于主光。
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(1.0, 0.78, 0.55)
	fill.light_energy = 0.42
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-24.0, 152.0, 0.0)
	host.add_child(fill)

	for k in MAT:
		var c: Array = MAT[k]
		mats[k] = make_material(c[0], c[1], c[2], [0.10, 0.55, 0.48] if k == "core" else null)
	# 建筑底座光环 / 射程预览 / 施工（2026-10-20 建筑表现轮）：全部 unshaded 半透明，
	# 不参与光照与投影；按类型分色，悬停/拆除时切红。
	mats["ring_wall"] = make_flat_material(Color8(200, 168, 108, 115))
	mats["ring_tower"] = make_flat_material(Color8(96, 208, 220, 130))
	mats["ring_core"] = make_flat_material(Color8(64, 200, 176, 165))
	mats["ring_hot"] = make_flat_material(Color8(228, 92, 72, 210))
	# 射程/幽灵模型剔除背面：六边板与 glb 都是闭合体，双面渲染会让半透明叠两层，
	# 实测 alpha 26 的填充会叠成 ~37% 的实色块、幽灵模型也会糊成实心。
	mats["range_fill"] = make_flat_material(Color8(96, 208, 220, 18), 0, BaseMaterial3D.CULL_BACK)
	mats["range_edge"] = make_flat_material(Color8(120, 224, 232, 130), 0, BaseMaterial3D.CULL_BACK)
	mats["scaffold"] = make_flat_material(Color8(224, 198, 140, 95))
	# 幽灵底板半透明（绿=可建 / 红=不可建）：让实物模型轮廓压过底板，而不是糊成一团实色。
	for gk in ["ghost_ok", "ghost_bad"]:
		var gm: StandardMaterial3D = mats[gk]
		gm.albedo_color = Color(gm.albedo_color.r, gm.albedo_color.g, gm.albedo_color.b, 0.62)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 实物幽灵模型：着色 + 弱自发光（有明暗面才有体积感；纯 unshaded 会糊成一块绿板）。
	mats["ghost_ok_model"] = make_ghost_model_material(Color8(110, 235, 140, 150))
	mats["ghost_bad_model"] = make_ghost_model_material(Color8(238, 96, 74, 150))


## 地图视觉动机应用调色板时写入雾基准；当前后期档决定实际雾距（换图/改档都幂等）。
func set_fog_base(start: float, end: float) -> void:
	_fog_base = Vector2(start, end)
	_apply_fog()


## 按后期档缩放雾距（低 1.6× / 中 1.25× / 高 1.0× = 美术原口径）
func _apply_fog() -> void:
	if env == null:
		return
	var mults: Array = [1.6, 1.25, 1.0]
	var m := float(mults[clampi(_post_q, 0, 2)]) * _fog_fit_mult
	env.fog_depth_begin = _fog_base.x * m
	env.fog_depth_end = _fog_base.y * m


## 视频/画质应用（纯表现层；探针/自检运行由 main 门控不调用——默认档 = 原行为，保截图 gate 口径）。
## 渲染缩放：scaling_3d_scale = render_pct/100；抗锯齿：关 / FXAA / TAA（use_taa）；
## 阴影质量：2/4 分裂 + 最大距离 45/80/100；后期处理：雾距 ×当前地图基准（低 1.6× / 中 1.25× / 高 1.0×）；
## 景深：远场轻虚化（默认关，CameraAttributesPractical）；画面亮度：Environment adjustment（100% 关闭）。
func apply_video(cfg: Dictionary) -> void:
	var aa := clampi(int(cfg.get("aa", 1)), 0, 2)
	var sq := clampi(int(cfg.get("shadow_q", 2)), 0, 2)
	var pq := clampi(int(cfg.get("post_q", 2)), 0, 2)
	var pct := clampi(int(cfg.get("render_pct", 100)), 50, 100)
	var bpct := clampi(int(cfg.get("bright_pct", 100)), 70, 130)
	var vp := host.get_viewport()
	if vp != null:
		vp.scaling_3d_scale = float(pct) / 100.0
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = aa == 2
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sq == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		var dists: Array = [110.0, 150.0, 190.0]
		sun.directional_shadow_max_distance = float(dists[sq])
	if env != null:
		_post_q = pq
		_apply_fog()
		env.adjustment_enabled = bpct != 100
		env.adjustment_brightness = float(bpct) / 100.0
	if camera != null:
		if bool(cfg.get("dof", false)):
			if _dof_attrs == null:
				_dof_attrs = CameraAttributesPractical.new()
				_dof_attrs.dof_blur_far_enabled = true
				_dof_attrs.dof_blur_far_distance = 80.0
				_dof_attrs.dof_blur_far_transition = 60.0
				_dof_attrs.dof_blur_amount = 0.06
			camera.attributes = _dof_attrs
		else:
			camera.attributes = null


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


## 创建无光照半透明材质（底座环/射程/脚手架）：双面、不投影、不写深度。
func make_flat_material(c: Color, priority: int = 0, cull: int = BaseMaterial3D.CULL_DISABLED) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = cull
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	m.render_priority = priority
	return m


## 建筑幽灵模型材质：半透明着色 + 弱自发光，既保留明暗体积感又在暗地形上够醒目。
func make_ghost_model_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 0.55
	m.disable_receive_shadows = true
	return m


## 在 parent 下添加一个盒体部件（位置 + 缩放 + 材质名）
func _part(parent: Node3D, px: float, py: float, pz: float, sx: float, sy: float, sz: float, matname: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh
	mi.material_override = mats[matname]
	mi.position = Vector3(px, py, pz)
	mi.scale = Vector3(sx, sy, sz)
	parent.add_child(mi)


# ---- 坐标映射（2026-10-17 六边形：pointy-top odd-r，奇行 +0.5 半格右移）----

## 六边形局部角点（x,z；尖顶朝北：上/下顶点 ±2/3，左右平边 ±1/2）。
## 与 sim 邻接表严格同构：E/W 同排相贴；NE/NW/SE/SW 与相邻行错半格相贴。
## 高度 = 2×2/3（行距 1.0 的 1.5 倍），比正六边形竖向拉伸 ~15%，换回整幅 [-32,32]² 世界口径不变。
const HEX_CORNERS := [
	Vector2(0.0, -2.0 / 3.0),
	Vector2(0.5, -1.0 / 3.0),
	Vector2(0.5, 1.0 / 3.0),
	Vector2(0.0, 2.0 / 3.0),
	Vector2(-0.5, 1.0 / 3.0),
	Vector2(-0.5, -1.0 / 3.0),
]

var hex_plate_mesh: ArrayMesh = null # 六边板（薄棱柱，中心原点，厚 1.0；幽灵/热层共用）
var hex_ring_mesh: ArrayMesh = null # 六边环（扁平，底座光环用；中心原点，y=0）


## 格子坐标 → 世界坐标（格中心；奇行（y 为奇数）+0.5 右移 = odd-r）
func cell_to_world(x: int, y: int) -> Vector3:
	return Vector3(float(x) - HALF + 0.5 + 0.5 * float(y & 1), 0.0, float(y) - HALF + 0.5)


## 世界坐标 → 格子坐标（精确六边包含判定：3×3 候选 + 逐边半平面测试）；界外/缝隙返回 (-1, -1)。
## 注意：六边平铺在矩形边界处有半格锯齿缝隙（odd-r 固有），缝隙内点击返回 (-1,-1)。
func world_to_cell(wx: float, wz: float) -> Vector2i:
	var fx := int(floor(wx + HALF))
	var fy := int(floor(wz + HALF))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cx := fx + dx
			var cy := fy + dy
			if cx < 0 or cy < 0 or cx >= CELL_N or cy >= CELL_N:
				continue
			if _in_hex(wx, wz, cx, cy):
				return Vector2i(cx, cy)
	return Vector2i(-1, -1)


## 点是否落在格 (x,y) 的六边形内（自然角点，不裁剪；半平面：x≤±0.5 + 四斜边 2|·|-3|·|≤2）。
func _in_hex(wx: float, wz: float, x: int, y: int) -> bool:
	var c := cell_to_world(x, y)
	var lx := wx - c.x
	var lz := wz - c.z
	if lx > 0.5 or lx < -0.5:
		return false
	if 2.0 * lx - 3.0 * lz > 2.0:
		return false
	if -2.0 * lx - 3.0 * lz > 2.0:
		return false
	if 2.0 * lx + 3.0 * lz > 2.0:
		return false
	if -2.0 * lx + 3.0 * lz > 2.0:
		return false
	return true


## 六边板网格（懒构建）：顶/底 + 6 侧；厚 1.0（±0.5）居中；横向 1.0 宽、竖向 4/3 高（贴合格口径）。
func _ensure_hex_plate() -> void:
	if hex_plate_mesh != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := 0.5
	# 顶面扇形（CW：自顶角起顺时针；与地面网格绕序口径一致）
	for i in 6:
		var p0: Vector2 = HEX_CORNERS[i]
		var p1: Vector2 = HEX_CORNERS[(i + 1) % 6]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0.0, hz, 0.0))
		st.add_vertex(Vector3(p0.x, hz, p0.y))
		st.add_vertex(Vector3(p1.x, hz, p1.y))
	# 底面扇形（反向绕序）
	for i2 in 6:
		var q0: Vector2 = HEX_CORNERS[i2]
		var q1: Vector2 = HEX_CORNERS[(i2 + 1) % 6]
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(0.0, -hz, 0.0))
		st.add_vertex(Vector3(q1.x, -hz, q1.y))
		st.add_vertex(Vector3(q0.x, -hz, q0.y))
	# 侧面（法线水平，逐条面算）
	for i3 in 6:
		var s0: Vector2 = HEX_CORNERS[i3]
		var s1: Vector2 = HEX_CORNERS[(i3 + 1) % 6]
		var d := Vector3(s1.x - s0.x, 0.0, s1.y - s0.y)
		var n := Vector3(d.z, 0.0, -d.x).normalized()
		var a := Vector3(s0.x, hz, s0.y)
		var b := Vector3(s1.x, hz, s1.y)
		var a2 := Vector3(s0.x, -hz, s0.y)
		var b2 := Vector3(s1.x, -hz, s1.y)
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(a2)
		st.add_vertex(b2)
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b2)
		st.add_vertex(b)
	hex_plate_mesh = st.commit()


## 六边环网格（懒构建）：外圈 1.05 / 内圈 0.955 的扁平环带，贴地 y=0。
## 底座光环用：墙金 / 塔青 / 核玉；比格宽 5%，建筑本体压不住。
func _ensure_hex_ring() -> void:
	if hex_ring_mesh != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := 1.05
	var inner := 0.955
	for i in 6:
		var a0: Vector2 = HEX_CORNERS[i] * outer
		var a1: Vector2 = HEX_CORNERS[(i + 1) % 6] * outer
		var b0: Vector2 = HEX_CORNERS[i] * inner
		var b1: Vector2 = HEX_CORNERS[(i + 1) % 6] * inner
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a0.x, 0.0, a0.y))
		st.add_vertex(Vector3(b0.x, 0.0, b0.y))
		st.add_vertex(Vector3(b1.x, 0.0, b1.y))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a0.x, 0.0, a0.y))
		st.add_vertex(Vector3(b1.x, 0.0, b1.y))
		st.add_vertex(Vector3(a1.x, 0.0, a1.y))
	hex_ring_mesh = st.commit()


## 构建 MultiMeshInstance3D（实例数组 + 材质；pmesh 缺省盒体，可传六边板等）
func _make_multimesh(insts: Array, mat: Material, pmesh: Mesh = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pmesh if pmesh != null else box_mesh
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


# ---- 相机取景 ----

## 确保相机存在（懒创建）
func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = CAM_FOV
	camera.near = 1.0
	camera.far = 400.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	host.add_child(camera)


## 取景：把 64² 地图横向撑满可交互区（上让顶栏、右让按钮带、下让余量）。
## 2026-10-23：俯角固定 42°（不再二分贴边），FOV 30° 收窄透视；纵向由竖直偏移平衡留白。
## 注意：取景会重置平移/旋转/缩放（窗口尺寸变化时由 sync 触发，回到默认北向全图视角）。
func fit_camera() -> void:
	_ensure_camera()
	var vp := host.get_viewport().get_visible_rect().size
	var W := vp.x
	var H := vp.y
	if W <= 0.0 or H <= 0.0:
		W = 1280.0
		H = 720.0
	var S := clampf(H / 816.0, 1.0, 1.6)
	var t45 := tan(deg_to_rad(camera.fov) / 2.0) # 跟随相机 FOV（原写死 45°，改 FOV 后取景必须同步，否则构图与本缓存口径分叉）
	var aspect := W / H
	# 水平不加对称留白：左缘贴屏、右缘贴按钮带。nl/nr 为可交互区左右归一化坐标，
	# hw 为其半宽（决定地图横向投影大小），nc 为其中心（决定相机横向偏移）。
	var nl := -1.0 + 2.0 * RESERVE_LEFT * S / W
	var nr := 1.0 - 2.0 * RESERVE_RIGHT * S / W
	var hw := maxf((nr - nl) * 0.5, 0.3)
	var y_b := -1.0 + 2.0 * RESERVE_BOTTOM * S / H
	var y_t := 1.0 - 2.0 * RESERVE_TOP * S / H
	var bc := (y_b + y_t) / 2.0
	var R := HALF

	var p := deg_to_rad(PITCH_DEG)
	var sr := sin(p)
	var cr := cos(p)
	var zc2 := R * cr
	var yc2 := R * sr
	var s := R / (hw * t45 * aspect) + zc2
	var zn2 := s - zc2
	var zf2 := s + zc2
	var yn := -yc2 / (zn2 * t45)
	var yf := yc2 / (zf2 * t45)
	var off := t45 * ((yn + yf) / 2.0 - bc) * 2.0 / (1.0 / zn2 + 1.0 / zf2)

	var cam_y := s * sr + off * cr
	var cam_z := s * cr - off * sr
	# 横向偏移：把地图水平中心（x=0）压到可交互区中心 nc。用近边深度 zn2 换算（近边透视最宽，
	# 贴边约束在这里成立）；yaw=0 时焦点与相机同向平移，视线仍平行 -Z，构图整体左移。
	var off_x := -(nl + nr) * 0.5 * zn2 * t45 * aspect
	_pitch = p
	# 焦点按标准取景求解后固定，再单独缩短相机距离（_fit_pull）→ 画面中心不跑，地图以焦点为中心均匀放大
	var d0 := cam_y / sr
	focus = Vector3(off_x, 0.0, cam_z - cr * d0)
	_dist = d0 * _fit_pull
	yaw = 0.0
	_zoom = 1.0
	_apply_cam()
	_fit_w = W
	_fit_h = H
	# 雾距按取景视距外推（只在取景时算，不进逐帧 _apply_cam：Environment 属性逐帧写会在移动端造成微卡顿）。
	# 基准雾 55..170m 按横屏约 76m 视距调；竖屏/小窗视距 250m 时不外推会把地图整片吞成背景色。
	_fog_fit_mult = clampf(_dist / 76.0, 1.0, 4.0)
	_apply_fog()


## 触发震屏（amp 单位米，dur 秒）。同帧多次触发取「更强 + 更久」各一项，幅值不叠加：
## 多塔同时打核心时叠加会直接晃吐，取 max 才是可以连续触发的口径。
func shake(amp: float, dur: float) -> void:
	if not shake_on:
		return
	shake_amp = maxf(shake_amp, amp)
	shake_dur = maxf(shake_dur, dur)
	shake_t = maxf(shake_t, dur)


## 逐帧推进震屏并重算相机；返回是否仍在震（调用方无需处理返回值，这里自己沉降）。
## 归零那一帧也要 _apply_cam()：把相机摆回无偏移位姿，否则会停在最后一帧的偏移上。
func update_shake(dt: float) -> bool:
	if shake_t <= 0.0:
		return false
	shake_phase += dt * 42.0
	shake_t = maxf(shake_t - dt, 0.0)
	if shake_t <= 0.0:
		shake_amp = 0.0
		shake_dur = 0.0
	_apply_cam()
	return true


## 由 (focus, yaw, 基准俯角/距离, 缩放) 沉降相机位姿，并刷新投影缓存。
func _apply_cam() -> void:
	var sr := sin(_pitch)
	var cr := cos(_pitch)
	var f := Vector3(0.0, -sr, -cr).rotated(Vector3.UP, yaw)
	var u := Vector3(0.0, cr, -sr).rotated(Vector3.UP, yaw)
	var d := _dist * _zoom
	camera.position = focus - f * d
	# 远裁面跟随视距（2026-10-22）：竖屏/窄窗口取景会算到 500m+ 视距，固定 far=400 会把整张地图裁掉只剩背景色。
	# 横屏正常取景约 76m，far 保持 400 不变；只在需要时放宽，避免无谓的深度精度损失。
	camera.far = maxf(400.0, d * 2.2)
	if shake_t > 0.0 and shake_amp > 0.0:
		var k := shake_t / maxf(shake_dur, 0.001)
		var a := shake_amp * k * k # 二次衰减：收尾干脆，不留尾巴
		# 两个不同频率的正弦叠加 = 不规则的抖，比单一正弦更像撞击
		var rx := sin(shake_phase * 1.7) + sin(shake_phase * 0.53) * 0.5
		var ry := cos(shake_phase * 1.31) + cos(shake_phase * 0.71) * 0.5
		var right := f.cross(Vector3.UP)
		if right.length_squared() < 1e-6:
			right = Vector3.RIGHT
		camera.position += (right.normalized() * rx + u.normalized() * ry) * a
	camera.look_at(camera.position + f * 100.0, u)
	_update_fit_cache()


## 从相机当前位姿刷新投影缓存（world_to_screen 闭式解用；旋转/平移后必须刷新）。
func _update_fit_cache() -> void:
	var xf := camera.global_transform
	var r := xf.basis.x
	var u := xf.basis.y
	var f := -xf.basis.z
	var vp := host.get_viewport().get_visible_rect().size
	var W := vp.x
	var H := vp.y
	if W <= 0.0 or H <= 0.0:
		W = 1280.0
		H = 720.0
	_fit = {
		"px": xf.origin.x,
		"py": xf.origin.y,
		"pz": xf.origin.z,
		"rx": r.x,
		"ry": r.y,
		"rz": r.z,
		"ux": u.x,
		"uy": u.y,
		"uz": u.z,
		"fx": f.x,
		"fy": f.y,
		"fz": f.z,
		"t45": tan(deg_to_rad(camera.fov) / 2.0),
		"a": W / H,
	}


## 水平前向（屏幕上方对应的地面方向；yaw=0 时为世界 -Z）。
func _flat_forward() -> Vector3:
	var f := Vector3(0.0, -sin(_pitch), -cos(_pitch)).rotated(Vector3.UP, yaw)
	return Vector3(f.x, 0.0, f.z).normalized()


## 地图在屏幕上的可见面积占比（0..1）：地图四角投影 → 轴对齐包围盒 ∩ 屏幕 / 屏幕面积。
## 四角必须在相机前方；任一角在后方时包围盒无意义，返回 0.0。
func _map_visible_ratio() -> float:
	var vp := host.get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(1280.0, 720.0)
	var screen := Rect2(Vector2.ZERO, vp)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in [Vector3(-HALF, 0.0, -HALF), Vector3(HALF, 0.0, -HALF), Vector3(HALF, 0.0, HALF), Vector3(-HALF, 0.0, HALF)]:
		if camera.is_position_behind(p):
			return 0.0
		var sp := camera.unproject_position(p)
		mn = Vector2(minf(mn.x, sp.x), minf(mn.y, sp.y))
		mx = Vector2(maxf(mx.x, sp.x), maxf(mx.y, sp.y))
	var box := Rect2(mn, mx - mn)
	return clampf(box.intersection(screen).get_area() / screen.get_area(), 0.0, 1.0)


## 平移焦点并夹在地图邻域内（防止把地图推出视野找不回来；缩放后允许的外圈更大）。
## 粗夹取后若地图占屏不足阈值，沿「当前焦点 → 地图中心」回退最小比例（二分 6 次逼近）。
## 阈值分两档：居中占比 ≥ MAP_MIN_VISIBLE 时用 MAP_MIN_VISIBLE（0.75）；
## 拉远到地图小于屏幕时退化为「居中占比的 90%」，保证居中仍达标、平移不被锁死。
func _move_focus(v: Vector3) -> void:
	var limit := HALF + 24.0
	focus += v
	focus.x = clampf(focus.x, -limit, limit)
	focus.z = clampf(focus.z, -limit, limit)
	_apply_cam()
	# 先测居中基准占比，得出本次允许的可见面积下限
	var cur := focus
	focus = Vector3.ZERO
	_apply_cam()
	var center_ratio := _map_visible_ratio()
	var thr := minf(MAP_MIN_VISIBLE, center_ratio * 0.9)
	# 回到粗夹取后的焦点，测其占比是否已达标
	focus = cur
	_apply_cam()
	if _map_visible_ratio() >= thr:
		return
	var lo := 0.0
	var hi := 1.0
	for _i in 6:
		var mid := (lo + hi) * 0.5
		focus = cur.lerp(Vector3.ZERO, mid)
		_apply_cam()
		if _map_visible_ratio() >= thr:
			hi = mid
		else:
			lo = mid
	focus = cur.lerp(Vector3.ZERO, hi)
	_apply_cam()


# ---- 相机操控（纯表现层；不进模拟、不进指纹）----

## WASD 平移：dir_x 右为正（D 键），dir_y 前为正（W 键），dist 为世界单位。
func pan_world(dir_x: float, dir_y: float, dist: float) -> void:
	if camera == null or _dist <= 0.0:
		return
	var fh := _flat_forward()
	var rt := Vector3(-fh.z, 0.0, fh.x)
	_move_focus((rt * dir_x + fh * dir_y) * dist)


## 右键拖拽：像素位移 → 地面平移（抓取感：内容跟手）。
func pan_pixels(dx: float, dy: float) -> void:
	if camera == null or _dist <= 0.0 or _fit.is_empty():
		return
	var vp := host.get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var upp := 2.0 * (_dist * _zoom) * float(_fit["t45"]) / vp.y # 焦平面处：世界单位/像素
	var fh := _flat_forward()
	var rt := Vector3(-fh.z, 0.0, fh.x)
	_move_focus(fh * (dy * upp) - rt * (dx * upp))


## 滚轮缩放（绕 focus 拉近/拉远；倍率夹在 [0.6, 1.8]；纯表现层，不进模拟/指纹）。
func zoom_by(factor: float) -> void:
	if camera == null or _dist <= 0.0:
		return
	_zoom = clampf(_zoom * factor, 0.6, 1.8)
	_apply_cam()


## Q/E 旋转（绕 focus；正 = 左旋）。
func rotate_y(delta: float) -> void:
	if camera == null:
		return
	yaw += delta
	_apply_cam()


## 世界坐标 → 屏幕像素（赏金浮字用）。视轴后方返回 Vector2(-1, -1)。
## 用相机完整基（右/上/前向量）投影，平移旋转后同样成立。
func world_to_screen(wx: float, wy: float, wz: float) -> Vector2:
	if _fit.is_empty():
		return Vector2(-1, -1)
	var dx := wx - float(_fit["px"])
	var dy := wy - float(_fit["py"])
	var dz := wz - float(_fit["pz"])
	var depth := dx * float(_fit["fx"]) + dy * float(_fit["fy"]) + dz * float(_fit["fz"])
	if depth <= 0.1:
		return Vector2(-1, -1)
	var hx := dx * float(_fit["rx"]) + dy * float(_fit["ry"]) + dz * float(_fit["rz"])
	var hy := dx * float(_fit["ux"]) + dy * float(_fit["uy"]) + dz * float(_fit["uz"])
	var nx := hx / (depth * float(_fit["t45"]) * float(_fit["a"]))
	var ny := hy / (depth * float(_fit["t45"]))
	var vp := host.get_viewport().get_visible_rect().size
	return Vector2((nx + 1.0) * 0.5 * vp.x, (1.0 - ny) * 0.5 * vp.y)
