extends RefCounted

# 真实资产模型管理（glb）——单位 / 金堆 / 瓦砾。
# 口径照母版：
#   ZergAssets.lua：length = 最长轴目标尺寸，统一缩放；包围盒底部中心对齐根节点。
#   GoldPile.lua：满堆缩到 1.2×0.4×1.2（各轴独立），root.scale 0.78 收进 0.94 格。
#   view3d.place_rubble：scale = footprint / max(size.x, size.z)，底部中心校准。
# 本文件不使用 class_name；调用方以 preload 实例化（规避 class_name 自引用类风险）。

# 单位（键 = Sim.E_*；length 单位米，照 ZergAssets.definitions）
const UNIT_SCENES := {
	1: "res://assets/models/zerg_worker.glb", # E_SWARM 幼生工虫
	2: "res://assets/models/zerg_blade.glb", # E_BLADE 镰爪战虫
	3: "res://assets/models/zerg_king.glb", # E_BEHEMOTH 重甲虫王
}
const UNIT_LENGTH := { 1: 0.8, 2: 1.6, 3: 2.6 }

# 金堆 4 档（满 → 残余；模型与目标尺寸照 GoldPile.stages）
const GOLD_SCENES := [
	"res://assets/models/gold_pile_full.glb",
	"res://assets/models/gold_pile_partial.glb",
	"res://assets/models/gold_pile_small.glb",
	"res://assets/models/gold_pile_low.glb",
]
const GOLD_SIZE := [
	Vector3(1.20, 0.40, 1.20),
	Vector3(1.04, 0.29, 1.04),
	Vector3(0.82, 0.21, 0.82),
	Vector3(0.48, 0.105, 0.48),
]
const GOLD_ROOT_SCALE := 0.78 # 满堆 1.2 宽由 root 缩放收进 0.94 格（母版 view3d 口径）

# 瓦砾 3 变体（沙土 / 棕土 / 灰碎石，照 RUBBLE_UUIDS 顺序）
const RUBBLE_SCENES := [
	"res://assets/models/rubble_sand.glb",
	"res://assets/models/rubble_brown.glb",
	"res://assets/models/rubble_gray.glb",
]

# 矿格矿石（2026-10-17 新建：multiview 直出砂金矿块，metallic 0.15 / roughness 0.75）
const ORE_SCENE := "res://assets/models/gold_ore.glb"

# 建筑 3 件（2026-10-17 text2model 直出；替代盒体拼接，spec §12 fallback 退役）
const BUILDING_SCENES := {
	"wall": "res://assets/models/wall_barrier.glb",
	"tower": "res://assets/models/tower_ballista.glb",
	"core": "res://assets/models/core_jade.glb",
}
# 目标口径（2026-10-20 建筑层级统一）：墙 1.15 < 塔 2.6 < 核心 3.2。
# 墙 = 0.94×1.15×0.94（footprint 满 0.94，连续墙由 view_entities 边缘段补齐）；
# 塔 = 等比到总高 2.6；核 = 等比到总高 3.2（核心明显大于普通建筑）。
const BUILDING_SIZE := {
	"wall": Vector3(0.94, 1.15, 0.94),
	"tower": Vector3(0.94, 2.60, 0.94),
	"core": Vector3(0.94, 3.20, 0.94),
}

var _cache: Dictionary = {}


# ---- LOD（2026-10-17，源 4 级）----
# 转换器（tools/umd2_to_gltf.py）把源 .mdl 的 4 级 LOD 导出为 lod0..lod3 四个并列
# MeshInstance3D 子节点（蒙皮件共享同一 skeleton/skin）。运行时按「对象屏高占比」切级：
# 阈值出自源管线 .lodgroup（screenSize 0.20/0.08/0.03，跌到该占比即切下一级）；
# LOD_AGGRESSIVENESS 乘在阈值上（>1 更早切低模，冲性能）。置 0 = 恒 LOD0（总回退开关）。
const LOD_LEVELS := 4
const LOD_SCREEN_FRACTIONS := [0.20, 0.08, 0.03]
const LOD_AGGRESSIVENESS := 1.3
const LOD_HYSTERESIS := 0.10 # 回升档需超过阈值 1.10 倍，防边界抖动
const LOD_TAN_HALF_FOV := 0.41421356 # tan(45°/2)：相机 fov 恒 45（view_core）


## LOD 旁支判定：lod1..lod3（校准口径只认 lod0——与 glb 化前逐像素一致）。
func _lod_decoy(n: Node) -> bool:
	var nm := String(n.name).to_lower()
	if not nm.begins_with("lod"):
		return false
	var rest := nm.substr(3)
	return rest.is_valid_int() and int(rest) > 0


## 纯函数：h = 对象屏高占比（包围球直径 / 视口高）→ 目标级别。带迟滞；aggr ≤ 0 → 恒 0。
func lod_index(h: float, current: int) -> int:
	var k: int = current
	if k < 0:
		k = 0
	while k < LOD_LEVELS - 1 and h < float(LOD_SCREEN_FRACTIONS[k]) * LOD_AGGRESSIVENESS:
		k += 1
	while k > 0 and h > float(LOD_SCREEN_FRACTIONS[k - 1]) * LOD_AGGRESSIVENESS * (1.0 + LOD_HYSTERESIS):
		k -= 1
	return k


## 绑定 glb 实例的 lod0..lod3（转换器约定命名），初态只显 LOD0。
## radius = 世界半径（包围球）。返回 { nodes:[MeshInstance3D×4], radius, idx }；
## 非 LOD 资产（旧单网格 glb）返回 {}。
func bind_lod(inst: Node, radius: float) -> Dictionary:
	var found: Dictionary = {}
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var nm := String(n.name).to_lower()
			if nm.begins_with("lod"):
				var rest := nm.substr(3)
				if rest.is_valid_int():
					found[int(rest)] = n
		for c in n.get_children():
			stack.append(c)
	if found.size() != LOD_LEVELS:
		return {}
	var nodes: Array = []
	for k in range(LOD_LEVELS):
		nodes.append(found[k])
	for k in range(LOD_LEVELS):
		(nodes[k] as MeshInstance3D).visible = (k == 0)
	return { "nodes": nodes, "radius": radius, "idx": 0 }


## 按屏幕占比切级；只在级跳变时写 visible。world_pos = 实例世界位置。
func update_lod(st: Dictionary, cam_pos: Vector3, world_pos: Vector3) -> void:
	if st.is_empty() or LOD_AGGRESSIVENESS <= 0.0:
		return
	var d: float = cam_pos.distance_to(world_pos)
	if d < 0.001:
		d = 0.001
	var h: float = float(st["radius"]) / (d * LOD_TAN_HALF_FOV)
	var k := lod_index(h, int(st["idx"]))
	if k != int(st["idx"]):
		var nodes: Array = st["nodes"]
		(nodes[int(st["idx"])] as MeshInstance3D).visible = false
		(nodes[k] as MeshInstance3D).visible = true
		st["idx"] = k


## 惰性加载 PackedScene（每次 load 有引擎缓存，这里再加一层字典省查找）。
func scene(path: String) -> PackedScene:
	if _cache.has(path):
		return _cache[path]
	var packed: PackedScene = load(path)
	_cache[path] = packed
	return packed


## 实例根空间下的合并 AABB：遍历 MeshInstance3D，逐级累积局部变换，
## 用 Mesh.get_aabb()（网格本地空间，语义明确）。
func mesh_aabb(inst: Node) -> AABB:
	var acc := AABB()
	var has := false
	if inst is MeshInstance3D and inst.mesh != null:
		acc = inst.mesh.get_aabb()
		has = true
	var stack: Array = []
	for c in inst.get_children():
		if c is Node3D:
			stack.append([c, c.transform])
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node3D = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and node.mesh != null and not _lod_decoy(node):
			var ta: AABB = xf * node.mesh.get_aabb()
			if has:
				acc = acc.merge(ta)
			else:
				acc = ta
				has = true
		for c2 in node.get_children():
			if c2 is Node3D:
				stack.append([c2, xf * c2.transform])
	return acc


## 深度查找 AnimationPlayer（glb 导入场景的层级不固定）。
func find_player(inst: Node) -> AnimationPlayer:
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


## 切换动画（只在变化时调；looped 只对 Crawl 为真，其余单发停在末帧）。
func play(player: AnimationPlayer, clip: String, looped: bool) -> void:
	if player == null:
		return
	if not player.get_animation_list().has(clip):
		return
	var anim := player.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	# 同一动作仍在播时要从头重播（塔连射 / 核心连续受击）
	if player.current_animation == clip and player.is_playing():
		player.seek(0.0, true)
	else:
		player.play(clip)


## 单位模型：wrapper（外部控制位置/朝向/脉冲缩放）+ 内部 glb 实例（缩放与底部中心校准）。
## 返回 { "node": wrapper, "player": AnimationPlayer }。
func spawn_unit(parent: Node, kind: int) -> Dictionary:
	var packed := scene(UNIT_SCENES[kind])
	var root := Node3D.new()
	root.name = "unit"
	parent.add_child(root)
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	var box := mesh_aabb(inst)
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s: float = float(UNIT_LENGTH[kind]) / longest
	inst.scale = Vector3(s, s, s)
	var c := box.get_center()
	inst.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	return { "node": root, "player": find_player(inst),
			"lod": bind_lod(inst, float(UNIT_LENGTH[kind]) * 0.5) }


## 金堆满档：root（世界位置 + 0.78 缩放）+ 内部各轴缩到 1.2×0.4×1.2、底部中心对齐。
func spawn_gold(parent: Node, pos: Vector3) -> Node3D:
	var packed := scene(GOLD_SCENES[0])
	var root := Node3D.new()
	root.name = "gold"
	root.position = pos
	root.scale = Vector3(GOLD_ROOT_SCALE, GOLD_ROOT_SCALE, GOLD_ROOT_SCALE)
	parent.add_child(root)
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	var box := mesh_aabb(inst)
	var target: Vector3 = GOLD_SIZE[0]
	var sx: float = target.x / box.size.x
	var sy: float = target.y / box.size.y
	var sz: float = target.z / box.size.z
	inst.scale = Vector3(sx, sy, sz)
	var c := box.get_center()
	inst.position = Vector3(-c.x * sx, -box.position.y * sy, -c.z * sz)
	root.set_meta("lod", bind_lod(inst,
			0.5 * maxf(target.x, maxf(target.y, target.z)) * GOLD_ROOT_SCALE))
	return root


## 瓦砾堆：scale = footprint / max(size.x, size.z)，底部中心对齐；root 摆到格位。
func spawn_rubble(parent: Node, variant: int, pos: Vector3, footprint: float) -> Node3D:
	var packed := scene(RUBBLE_SCENES[variant])
	var root := Node3D.new()
	root.name = "rubble"
	parent.add_child(root)
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	var box := mesh_aabb(inst)
	var s: float = footprint / maxf(box.size.x, box.size.z)
	inst.scale = Vector3(s, s, s)
	var c := box.get_center()
	inst.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	root.position = pos
	root.set_meta("lod", bind_lod(inst,
			0.5 * s * maxf(box.size.x, maxf(box.size.y, box.size.z))))
	return root


## 矿格矿石：同瓦砾口径（footprint 满 0.94 格），矿石比瓦砾高出约一格界线，辨识度优先。
func spawn_ore(parent: Node, pos: Vector3, footprint: float) -> Node3D:
	var packed := scene(ORE_SCENE)
	var root := Node3D.new()
	root.name = "ore"
	parent.add_child(root)
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	var box := mesh_aabb(inst)
	var s: float = footprint / maxf(box.size.x, box.size.z)
	inst.scale = Vector3(s, s, s)
	var c := box.get_center()
	inst.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	root.position = pos
	root.set_meta("lod", bind_lod(inst,
			0.5 * s * maxf(box.size.x, maxf(box.size.y, box.size.z))))
	return root


## 建筑 3 件（墙/塔/核）：返回已校准的 glb 实例（不建 wrapper、不挂父节点），
## 调用方挂到自己的 building_root 包装节点下（简化缩放/摆位/音效路径）。
## 墙各轴独立对齐 BUILDING_SIZE（footprint 优先）；塔/核等比缩放（细长晶体/塔柱不宜变形）。
## lod_override > 0 时强制显示该级 LOD（建筑幽灵预览用 lod3，省顶点）。
func spawn_building(kind_name: String, lod_override: int = 0) -> Node3D:
	var packed := scene(BUILDING_SCENES[kind_name])
	var inst: Node3D = packed.instantiate()
	var box := mesh_aabb(inst)
	var target: Vector3 = BUILDING_SIZE[kind_name]
	var s: Vector3
	if kind_name == "wall":
		s = Vector3(target.x / box.size.x, target.y / box.size.y, target.z / box.size.z)
	else:
		var u: float = target.y / box.size.y
		s = Vector3(u, u, u)
	inst.scale = s
	var c := box.get_center()
	inst.position = Vector3(-c.x * s.x, -box.position.y * s.y, -c.z * s.z)
	var st := bind_lod(inst, 0.5 * maxf(target.x, maxf(target.y, target.z)))
	if lod_override > 0 and not st.is_empty():
		var nodes: Array = st["nodes"]
		for k in range(LOD_LEVELS):
			(nodes[k] as MeshInstance3D).visible = (k == lod_override)
		st["idx"] = lod_override
	inst.set_meta("lod", st)
	return inst
