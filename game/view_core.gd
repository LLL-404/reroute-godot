extends RefCounted

# 《改道》视图层 · 坐标与基建（D5-1 拆分自 view.gd）：64² 坐标映射、盒体/材质工具、
# 相机取景与屏幕投影、相机操控（WASD 平移 / 右键拖拽 / QE 旋转 / 滚轮缩放）。
# 零 sim 引用（只被 terrain/entities 当几何底座）；节点挂点统一走 host。

const CELL_N := 64
const HALF := 32.0
const H_STEP := 1.2 # sim 高度层 1.2m/级

# 取景留边（px 基准）：上让顶栏（实高 56）、右让按钮带（列宽 160）、下让提示余量（同母版口径）
const RESERVE_TOP := 56.0
const RESERVE_RIGHT := 160.0
const RESERVE_BOTTOM := 22.0

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

var camera: Camera3D
var focus := Vector3.ZERO # 相机注视的地面点（y=0；平移/旋转围绕它）
var yaw := 0.0 # 水平旋转（绕 Y，正 = 左旋；QE 修改）
var _pitch := 0.0 # 基准俯角（rad，取景时定；操控不改）
var _dist := 0.0 # 相机到 focus 的基准距离（取景时定；滚轮缩放叠乘 _zoom）
var _zoom := 1.0 # 滚轮缩放倍率（0.6–1.8；取景重置 1.0）
var _fit: Dictionary = {}
var _fit_w := 0.0
var _fit_h := 0.0


func _init(p_host: Node3D) -> void:
	host = p_host


## 渲染基建（原 view._ready 前段）：盒体原型 + 环境/雾/灯光 + 全色板材质。
func setup() -> void:
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
	host.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	host.add_child(sun)

	for k in MAT:
		var c: Array = MAT[k]
		mats[k] = make_material(c[0], c[1], c[2], [0.10, 0.55, 0.48] if k == "core" else null)


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
	host.add_child(camera)


## 取景：把 64² 地图撑满可交互区（上让顶栏、右让按钮带、下让余量；口径同母版闭式推导）。
## 二分俯角找"宽、深同时贴边"的平衡点（夹在 [35°,50°]），再解视距与竖向平移。
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

	var cam_y := s * sr + off * cr
	var cam_z := s * cr - off * sr
	_pitch = p
	_dist = cam_y / sr
	focus = Vector3(0.0, 0.0, cam_z - cr * _dist)
	yaw = 0.0
	_zoom = 1.0
	_apply_cam()
	_fit_w = W
	_fit_h = H


## 由 (focus, yaw, 基准俯角/距离, 缩放) 沉降相机位姿，并刷新投影缓存。
func _apply_cam() -> void:
	var sr := sin(_pitch)
	var cr := cos(_pitch)
	var f := Vector3(0.0, -sr, -cr).rotated(Vector3.UP, yaw)
	var u := Vector3(0.0, cr, -sr).rotated(Vector3.UP, yaw)
	var d := _dist * _zoom
	camera.position = focus - f * d
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


## 平移焦点并夹在地图邻域内（防止把地图推出视野找不回来；缩放后允许的外圈更大）。
func _move_focus(v: Vector3) -> void:
	var limit := HALF + 24.0
	focus += v
	focus.x = clampf(focus.x, -limit, limit)
	focus.z = clampf(focus.z, -limit, limit)
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
