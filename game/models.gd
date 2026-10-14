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

var _cache: Dictionary = {}


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
		if node is MeshInstance3D and node.mesh != null:
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
	return { "node": root, "player": find_player(inst) }


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
	return root
