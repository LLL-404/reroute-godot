extends RefCounted

# 《改道》视图层 · 实体域（D5-1 拆分自 view.gd）：对局装载（覆盖层/Solid/实体容器）、建筑剪影、
# 英雄、单位同步（插值 + 动作状态机）、死亡消散、震荡环、幽灵预览、赏金浮字与统计。
# 只读模拟状态；几何工具借 core，贴地/热层借 terrain，音效借 audio；节点挂点统一走 host。

const ViewCoreScript = preload("res://game/view_core.gd")
const ViewTerrainScript = preload("res://game/view_terrain.gd")
const ViewAudioScript = preload("res://game/view_audio.gd")

const RING_LIFE := 7 # 震荡波扩散环 0.35s
# 模型路径动作时长（tick，照母版 Z_TICKS：Attack 0.9s / Hurt 0.5s / Death 1.4s）
const Z_ATTACK := 18
const Z_HURT := 10
const Z_DEATH := 28
const Z_YAW := PI / 2.0 # 模型朝向修正（截面校准：模型 yaw=π/2 时头朝 +Z；母版 UrhoX 口径 0 在 Godot 下差 90°）
const CORE_HIT_THROTTLE := 30 # 核心受击音节流（tick）：多敌同时啃核心时不叠音
# 战斗音限流（tick，20Hz）：大群围攻时逐兵逐帧触发会音爆，必须双限流
const HURT_SFX_UNIT := 20 # 单兵受击音最小间隔 → 1.0s
const HURT_SFX_GLOBAL := 4 # 全局受击音最小间隔 → 5 次/秒
const ATTACK_SFX_GLOBAL := 4 # 全局攻击音最小间隔 → 5 次/秒
const GOLD_SFX_GLOBAL := 8 # 收金音最小间隔 → 2.5 次/秒
# 受击闪白（B2）：两档共享材质，避免逐帧改 alpha（共享材质改了会全体同闪）
const FLASH_TICKS := 6 # 闪白时长 = 受击脉冲同长（0.3s）
const FLASH_HI_LEVEL := 0.22 # 高档 ADD 加法强度（实测 0.30 起暗色单位会读成灰白，0.22 仍保留色相）
const FLASH_LO_LEVEL := 0.10 # 低档（脉冲后半程衰减）
# 震屏（B3）：只平移不旋转。核心受击 2 次/秒、技能 1 次/释放 —— 都是"力度大但不密集"的点。
const CORE_SHAKE_THROTTLE := 10 # 核心受击震屏节流（tick）
const CORE_SHAKE_AMP := 0.30 # 米（约 1.5% 屏高 @默认取景）
const CORE_SHAKE_DUR := 0.22
const SKILL_SHAKE_AMP := 0.45
const SKILL_SHAKE_DUR := 0.28
# 敌人 kind → 资产形态（照母版 view3d.ZFORM：虫群 → blade，蛮兽 → king）
const ZFORM := { 1: 2, 2: 3 }

var host: Node3D
var core: ViewCoreScript
var terrain: ViewTerrainScript
var audio: ViewAudioScript

var dyn: Node3D = null
var tiles: Node3D
var unit_root: Node3D
var building_root: Node3D

var cover_nodes: Dictionary = {} # cellkey -> { node, x, y }
var building_nodes: Dictionary = {} # id -> { node, kind }
var unit_nodes: Dictionary = {} # id -> { node, px, py, s, kind, hp, traveled, pulse }
var death_fx: Array = [] # 死亡消散中的单位条目（放大下沉后移除）
var fx_quality := 2 # 特效质量（0 低 / 1 中 / 2 高）：死亡消散时长（低 = 1 tick 即移除；默认高 = 原行为）
var hero = null # { node, px, py }
var ring = null # { node, born }

var ghost: Node3D = null
var ghost_mi: MeshInstance3D = null
var ghost_alive := false

# 建筑表现（2026-10-20）：实物幽灵预览 / 墙体边缘拼接 / 底座光环 / 射程 / 施工。
const WALL_RISE_MS := 300 # 墙升起动画（纯表现；模拟侧墙 build_ticks=0 不受影响）
const WALL_EDGE_H := 1.12
const WALL_EDGE_LEN := 0.66
const WALL_EDGE_THICK := 0.30 # 相邻墙共享边：厚段压进两侧墙身，补 6cm 缝
const WALL_EDGE_RIM := 0.18 # 外墙轮廓：窄压边，读作连续矮墙
var preview_root: Node3D = null
var _preview_sig := ""
var wall_edges_root: Node3D = null
var focus_ring: MeshInstance3D = null
var range_root: Node3D = null
var _wall_mat: Material = null
var _wall_cells: Dictionary = {} # cellkey -> Vector2i（当局活墙格）
var _wall_edges: Dictionary = {} # cellkey -> Node3D（边缘段容器，挂 wall_edges_root 下）
var _wall_entry_by_key: Dictionary = {} # cellkey -> building entry（边缘段更新用）
var _sync_once := false

var is_ore: Callable
var models = null # 真实资产模型管理器（ModelsScript 实例；_ready 建立）

## 击杀赏金浮字回调（R5 HUD 注入 (sx, sy, text)；未注入即空转）
var on_float: Callable

var _height_rev := -1
var _lod_cam := Transform3D() # 静态件 LOD 的相机变换缓存（变换未变即不刷）
var _lod_dirty := true # 新注册静态件（覆盖层/建筑）或重铺场地时置脏
var _hero_cd := 0
var _units_n := 0
var _horn_tick := -999
var _core_hp := -1 # 核心血量缓存（受击音检测；-1 = 未建档）
var _core_hit_tick := -999 # 最近核心受击音节流点
var _core_shake_tick := -999 # 最近核心受击震屏点（独立、更密的节流）
var _hurt_sfx_tick := -999 # 最近全局受击音 tick（限流）
var _attack_sfx_tick := -999 # 最近全局攻击音 tick（限流）
var _gold_sfx_tick := -999 # 最近收金音 tick（限流）
var _supply_seen := -1 # 上帧 supply 缓存（本帧增量 = 收金）
var _flash_hi: StandardMaterial3D = null # 闪白高档材质（共享，延迟建）
var _flash_lo: StandardMaterial3D = null # 闪白低档材质（共享，延迟建）
var _stat_solids := 0


## 构造注入：记宿主 + core/terrain/audio 组件（由 view._ready 组装）
func _init(p_host: Node3D, p_core: ViewCoreScript, p_terrain: ViewTerrainScript, p_audio: ViewAudioScript) -> void:
	host = p_host
	core = p_core
	terrain = p_terrain
	audio = p_audio


# ---- 对局装载 ----

## 铺一局的动态内容：覆盖层、实体容器；Solid 视觉已融入连续地面网格（仅计数）。
func build_terrain(pgrid: Grid) -> void:
	terrain.grid = pgrid
	_height_rev = pgrid.height_rev
	terrain._rebuild_field() # 地面网格与单位 ground_y 使用同一份模拟高度

	if dyn != null:
		dyn.free()
	dyn = Node3D.new()
	dyn.name = "Dyn"
	host.add_child(dyn)
	tiles = Node3D.new()
	tiles.name = "Tiles"
	dyn.add_child(tiles)
	unit_root = Node3D.new()
	unit_root.name = "Units"
	dyn.add_child(unit_root)
	building_root = Node3D.new()
	building_root.name = "Buildings"
	dyn.add_child(building_root)
	wall_edges_root = Node3D.new()
	wall_edges_root.name = "WallEdges"
	dyn.add_child(wall_edges_root)
	preview_root = Node3D.new()
	preview_root.name = "BuildPreview"
	dyn.add_child(preview_root)
	focus_ring = MeshInstance3D.new()
	focus_ring.name = "FocusRing"
	focus_ring.visible = false
	dyn.add_child(focus_ring)
	range_root = Node3D.new()
	range_root.name = "TowerRange"
	dyn.add_child(range_root)
	cover_nodes = {}
	building_nodes = {}
	unit_nodes = {}
	death_fx = []
	ring = null
	hero = null
	ghost = null
	ghost_mi = null
	ghost_alive = false
	_preview_sig = ""
	_wall_cells = {}
	_wall_edges = {}
	_wall_entry_by_key = {}
	_sync_once = false
	_hero_cd = 0
	_units_n = 0
	_horn_tick = -999
	_core_hp = -1
	_core_hit_tick = -999
	_hurt_sfx_tick = -999
	_attack_sfx_tick = -999
	_gold_sfx_tick = -999
	_supply_seen = -1
	_lod_dirty = true

	var n_solid := 0
	for y in pgrid.h:
		for x in pgrid.w:
			var c := pgrid.at(x, y)
			if c == Grid.SOLID:
				n_solid += 1 # SOLID 视觉融入连续地面网格：岩石色 + 1.6m 抬升
			elif c == Grid.COVER:
				_make_cover(x, y)
	_stat_solids = n_solid


## 覆盖层（真实资产）：矿格 = 砂金矿石巨砾（挖开即随覆盖层移除）；
## 表土/插口 = 瓦砾堆 3 变体（(x*7 + y*13) % 3 确定性取模，同母版口径）。
func _make_cover(x: int, y: int) -> void:
	var w := core.cell_to_world(x, y)
	var gy := terrain.ground_y(x, y)
	var node: Node3D
	if is_ore.call(x, y):
		node = models.spawn_ore(tiles, Vector3(w.x, gy, w.z), 0.94)
	else:
		var variant: int = (x * 7 + y * 13) % 3
		node = models.spawn_rubble(tiles, variant, Vector3(w.x, gy, w.z), 0.94)
	cover_nodes[x * 1000 + y] = { "node": node, "x": x, "y": y,
			"lod": node.get_meta("lod", {}) }
	_lod_dirty = true


# ---- 幽灵预览 ----

## 幽灵预览：cells = Array[Vector2i] 或空（藏起）；bad = 有效性染色；mode = wall/tower/...
## 保留逐格六边板（探针契约：ghost 子节点数 = cells.size），另在 preview_root 下叠真实模型：
## 墙 = 半透明连续墙段，塔 = 塔模型 + 12 格射程。mode 为空时退回旧口径（仅绿板）。
func show_ghost(cells: Array, bad: bool = false, mode: String = "") -> void:
	if cells.is_empty():
		if ghost_alive and ghost != null:
			ghost.free()
		ghost = null
		ghost_mi = null
		ghost_alive = false
		_preview_sig = ""
		_clear_preview()
		return
	if not ghost_alive or ghost == null:
		ghost = Node3D.new()
		ghost.name = "Ghost"
		ghost_mi = null
		dyn.add_child(ghost)
		ghost_alive = true
	core._ensure_hex_plate()
	while ghost.get_child_count() > cells.size():
		var extra: Node = ghost.get_child(ghost.get_child_count() - 1)
		ghost.remove_child(extra)
		extra.queue_free()
	while ghost.get_child_count() < cells.size():
		var fresh := MeshInstance3D.new()
		fresh.mesh = core.hex_plate_mesh
		ghost.add_child(fresh)
	var mat: Material = core.mats["ghost_bad"] if bad else core.mats["ghost_ok"]
	for i in cells.size():
		var c: Vector2i = cells[i]
		var w := core.cell_to_world(c.x, c.y)
		var mi: MeshInstance3D = ghost.get_child(i)
		mi.material_override = mat
		mi.position = Vector3(w.x, terrain.ground_y(c.x, c.y) + 0.12, w.z)
		mi.scale = Vector3(0.96, 0.24, 0.96)
	ghost_mi = ghost.get_child(0)
	_update_preview(cells, bad, mode)


## 幽灵实物预览 + 塔射程（2026-10-20）：按 mode 生成；相同输入不重建。
func _update_preview(cells: Array, bad: bool, mode: String) -> void:
	var sig := mode + "|" + ("1" if bad else "0") + "|w" + str(_wall_cells.size())
	for c in cells:
		sig += "|" + str(c.x) + "," + str(c.y)
	if sig == _preview_sig:
		return
	_preview_sig = sig
	_clear_preview()
	if mode != "wall" and mode != "tower":
		return
	var mmat: Material = core.mats["ghost_bad_model"] if bad else core.mats["ghost_ok_model"]
	if mode == "tower":
		var c0: Vector2i = cells[0]
		var w := core.cell_to_world(c0.x, c0.y)
		var node := Node3D.new()
		node.name = "pv_tower"
		node.position = Vector3(w.x, terrain.ground_y(c0.x, c0.y), w.z)
		node.scale = Vector3(0.96, 0.96, 0.96)
		var inst: Node3D = models.spawn_building("tower", 3)
		_apply_preview_material(inst, mmat)
		node.add_child(inst)
		preview_root.add_child(node)
		_build_range(c0)
		return
	# 墙：预览集合 = 现有墙 + 拖拽格，边缘段 + 本体都显示，和放下后的形态一致。
	var wall_set := {}
	for key in _wall_cells:
		wall_set[key] = true
	for c in cells:
		wall_set[c.x * 1000 + c.y] = true
	for c in cells:
		var w := core.cell_to_world(c.x, c.y)
		var node := Node3D.new()
		node.name = "pv_wall"
		node.position = Vector3(w.x, terrain.ground_y(c.x, c.y), w.z)
		node.scale = Vector3(0.96, 1.0, 0.96)
		var inst: Node3D = models.spawn_building("wall", 3)
		_apply_preview_material(inst, mmat)
		node.add_child(inst)
		var is_wall := func(px: int, py: int) -> bool: return wall_set.has(px * 1000 + py)
		_add_wall_edges(node, c.x, c.y, is_wall, mmat)
		preview_root.add_child(node)


## 清空实物预览 + 射程；ghost 绿板由 show_ghost 自己管理。
func _clear_preview() -> void:
	if preview_root != null:
		for c in preview_root.get_children():
			c.free()
	if range_root != null:
		for c in range_root.get_children():
			c.free()


# ---- 墙体连续化 / 底座光环 / 施工表现 ----

## 墙 glb 的 lod0 材质（只提取一次）；失败回退到程序化墙色。
func _wall_material() -> Material:
	if _wall_mat != null:
		return _wall_mat
	var fallback: Material = core.mats["wall"]
	if models == null:
		_wall_mat = fallback
		return _wall_mat
	var inst: Node3D = models.spawn_building("wall")
	var found: Material = _find_lod0_material(inst)
	inst.free()
	_wall_mat = found if found != null else fallback
	return _wall_mat


## 深度查找 lod0 网格的材质（优先 lod0，其次任意网格；取第 0 面）。
func _find_lod0_material(n: Node) -> Material:
	var mesh_nodes: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			mesh_nodes.append(cur)
		for c in cur.get_children():
			stack.append(c)
	for mi in mesh_nodes:
		if String(mi.name).to_lower() != "lod0":
			continue
		var m := _mesh_material(mi)
		if m != null:
			return m
	for mi in mesh_nodes:
		var m2 := _mesh_material(mi)
		if m2 != null:
			return m2
	return null


func _mesh_material(mi: MeshInstance3D) -> Material:
	var ov := mi.get_surface_override_material(0)
	if ov != null:
		return ov
	if mi.mesh != null and mi.mesh.get_surface_count() > 0:
		return mi.mesh.surface_get_material(0)
	return null


## 墙格边缘段：沿六边共享边摆窄盒。相邻墙补共享边（厚段压缝），空边补外轮廓压边。
## 共享边只由规范方向 k=0,1,2 一侧生成，避免两侧重复叠面。
func _add_wall_edges(parent: Node3D, x: int, y: int, is_wall: Callable, mat: Material) -> void:
	var here := core.cell_to_world(x, y)
	for k in 6:
		var nx := Grid.nx(x, y, k)
		var ny := Grid.ny(x, y, k)
		var shared: bool = is_wall.call(nx, ny)
		if shared and k >= 3:
			continue
		var nw := core.cell_to_world(nx, ny)
		var mid := (here + nw) * 0.5
		var tangent := Vector2(-(nw.z - here.z), nw.x - here.x).normalized()
		var mi := MeshInstance3D.new()
		mi.name = "wedge" + str(k)
		mi.mesh = core.box_mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(mid.x - here.x, WALL_EDGE_H * 0.5 - 0.015, mid.z - here.z)
		mi.scale = Vector3(WALL_EDGE_THICK if shared else WALL_EDGE_RIM, WALL_EDGE_H, WALL_EDGE_LEN)
		mi.rotation = Vector3(0.0, atan2(tangent.x, tangent.y), 0.0)
		parent.add_child(mi)


## 重建单格墙边缘段（新增/删除墙时连同 6 邻一起重算，保证共享边判定一致）。
func _rebuild_wall_cell(x: int, y: int) -> void:
	var key := x * 1000 + y
	var old = _wall_edges.get(key)
	if old != null:
		old.free()
		_wall_edges.erase(key)
	if not _wall_cells.has(key):
		return
	var node := Node3D.new()
	node.name = "we" + str(key)
	var w := core.cell_to_world(x, y)
	node.position = Vector3(w.x, terrain.ground_y(x, y), w.z)
	wall_edges_root.add_child(node)
	var mat := _wall_material()
	var is_wall := func(px: int, py: int) -> bool: return _wall_cells.has(px * 1000 + py)
	_add_wall_edges(node, x, y, is_wall, mat)
	_wall_edges[key] = node


## 六邻 cellkey（用于墙增删时标记需要重算边缘段的邻居）。
func _wall_neighbor_keys(x: int, y: int) -> Array:
	var out: Array = []
	for k in 6:
		out.append(Grid.nx(x, y, k) * 1000 + Grid.ny(x, y, k))
	return out


## 底座光环（墙金 / 塔青 / 核玉）：独立挂 building_root，不继承施工压扁。
func _make_base_ring(kind: int) -> MeshInstance3D:
	core._ensure_hex_ring()
	var mi := MeshInstance3D.new()
	mi.name = "basering"
	mi.mesh = core.hex_ring_mesh
	var s := 0.86
	if kind == Sim.B_TOWER:
		s = 0.96
		mi.material_override = core.mats["ring_tower"]
	elif kind == Sim.B_CORE:
		s = 1.12
		mi.material_override = core.mats["ring_core"]
	else:
		mi.material_override = core.mats["ring_wall"]
	mi.scale = Vector3(s, 1.0, s)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	building_root.add_child(mi)
	return mi


## 塔施工脚手架：六根立柱 + 两道六边箍 + 随进度上升的青色进度环。
func _make_build_fx(x: int, y: int) -> Node3D:
	var root := Node3D.new()
	root.name = "buildfx"
	var w := core.cell_to_world(x, y)
	root.position = Vector3(w.x, terrain.ground_y(x, y), w.z)
	building_root.add_child(root)
	var h := 2.70
	for i in 6:
		var c2: Vector2 = ViewCoreScript.HEX_CORNERS[i]
		var post := MeshInstance3D.new()
		post.mesh = core.box_mesh
		post.material_override = core.mats["scaffold"]
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post.position = Vector3(c2.x * 0.92, h * 0.5, c2.y * 0.92)
		post.scale = Vector3(0.045, h, 0.045)
		root.add_child(post)
	for yy in [0.62, 1.86]:
		var band := MeshInstance3D.new()
		band.mesh = core.hex_ring_mesh
		band.material_override = core.mats["scaffold"]
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		band.position = Vector3(0.0, float(yy), 0.0)
		band.scale = Vector3(0.90, 1.0, 0.90)
		root.add_child(band)
	var prog := MeshInstance3D.new()
	prog.name = "progress"
	prog.mesh = core.hex_ring_mesh
	prog.material_override = core.mats["ring_tower"]
	prog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prog.position = Vector3(0.0, 0.15, 0.0)
	prog.scale = Vector3(0.72, 1.0, 0.72)
	root.add_child(prog)
	return root


## 施工进度：进度环上升；完工即整组隐藏（节点保留到建筑拆除，避免反复建删）。
func _update_build_fx(entry: Dictionary, build_left: int, total: int) -> void:
	var fx = entry.get("fx")
	if fx == null:
		return
	var node: Node3D = fx
	if build_left <= 0:
		if node.visible:
			node.visible = false
		return
	node.visible = true
	var k := 1.0 - float(build_left) / float(maxi(total, 1))
	var prog = node.get_node_or_null("progress")
	if prog != null:
		(prog as Node3D).position.y = 0.15 + 2.30 * clampf(k, 0.0, 1.0)


## 墙升起系数（纯视觉墙钟 0..1；0.06 起步避免零缩放的退化基）。
func _wall_rise_k(entry: Dictionary) -> float:
	var t0 := int(entry.get("rise_ms", -1))
	if t0 < 0:
		return 1.0
	var age := Time.get_ticks_msec() - t0
	if age >= WALL_RISE_MS:
		entry["rise_ms"] = -1
		return 1.0
	var t := clampf(float(age) / float(WALL_RISE_MS), 0.0, 1.0)
	return 0.06 + 0.94 * smoothstep(0.0, 1.0, t)


## 递归把网格实例换成半透明幽灵材质（预览不投影）。
func _apply_preview_material(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_apply_preview_material(c, mat)


## 塔射程预览：六边距离球半径 = 建筑表 range（12）；逐格贴地填充 + 外圈亮带。
## 逐格而非单张平面六边形：高差地形上不会穿模/悬空，边界也天然贴合格形。
func _build_range(c: Vector2i) -> void:
	if range_root == null:
		return
	var r: int = int(Sim.BUILDINGS[Sim.B_TOWER - 1]["range"])
	if r <= 0:
		return
	core._ensure_hex_plate()
	var fills: Array = []
	for y in core.CELL_N:
		for x in core.CELL_N:
			if Grid.hex_dist(x, y, c.x, c.y) > r:
				continue
			var w := core.cell_to_world(x, y)
			# 1.0 宽无缝拼接（相邻六边共边），单层 18/255 alpha 叠在地形上。
			fills.append([Vector3(w.x, terrain.ground_y(x, y) + 0.07, w.z),
					Vector3(1.0, 0.05, 1.0)])
	var fm := core._make_multimesh(fills, core.mats["range_fill"], core.hex_plate_mesh)
	fm.name = "range_fill"
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_root.add_child(fm)
	# 外轮廓：只在“格内 → 格外出界”的共享边摆窄亮条，比整格亮带更细、不糊地形。
	var edge_root := Node3D.new()
	edge_root.name = "range_edge"
	range_root.add_child(edge_root)
	for y in core.CELL_N:
		for x in core.CELL_N:
			if Grid.hex_dist(x, y, c.x, c.y) != r:
				continue
			var here := core.cell_to_world(x, y)
			var gy := terrain.ground_y(x, y)
			for k in 6:
				var nx := Grid.nx(x, y, k)
				var ny := Grid.ny(x, y, k)
				if nx >= 0 and ny >= 0 and nx < core.CELL_N and ny < core.CELL_N:
					if Grid.hex_dist(nx, ny, c.x, c.y) <= r:
						continue
				var nw := core.cell_to_world(nx, ny)
				var mid := (here + nw) * 0.5
				var tangent := Vector2(-(nw.z - here.z), nw.x - here.x).normalized()
				var mi := MeshInstance3D.new()
				mi.mesh = core.box_mesh
				mi.material_override = core.mats["range_edge"]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.position = Vector3(mid.x, gy + 0.11, mid.z)
				mi.scale = Vector3(0.10, 0.05, 0.62)
				mi.rotation = Vector3(0.0, atan2(tangent.x, tangent.y), 0.0)
				edge_root.add_child(mi)


## 建筑悬停/拆除焦点环（hot = 红：拆除目标/不可建；false = 金：可交互）。
func set_focus(cell: Vector2i, hot: bool = true) -> void:
	if focus_ring == null:
		return
	if cell.x < 0:
		focus_ring.visible = false
		return
	core._ensure_hex_ring()
	focus_ring.mesh = core.hex_ring_mesh
	focus_ring.material_override = core.mats["ring_hot"] if hot else core.mats["ring_wall"]
	focus_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	focus_ring.scale = Vector3(1.02, 1.0, 1.02)
	var w := core.cell_to_world(cell.x, cell.y)
	focus_ring.position = Vector3(w.x, terrain.ground_y(cell.x, cell.y) + 0.055, w.z)
	focus_ring.visible = true


# ---- 每帧同步 ----

## 每帧同步：地形高度变化重建、热层刷新、覆盖层消失、建筑/英雄/单位/死亡消散/震荡环/相机取景
func sync(world: World) -> void:
	# 仅重建地面网格；高度增减总和相同也必须刷新，实体缓存不得被清掉。
	if terrain.grid != null and terrain.grid.height_rev != _height_rev:
		_height_rev = terrain.grid.height_rev
		terrain._rebuild_field()
	if terrain.heat_on and world.grid.rev != terrain.heat_rev:
		terrain.rebuild_heat(world)

	# 相机位置预取：单位逐帧切级；静态件在相机变换时统一刷。
	var cam: Camera3D = core.camera
	var cam_ok := cam != null
	var cam_pos := Vector3.ZERO
	if cam_ok:
		cam_pos = cam.global_position

	# 挖开的覆盖层消失（挖到矿格另有专属音；本帧挖矿则收金音让位，不叠响）
	var dug_this_frame := false
	for k in cover_nodes.keys():
		var cv: Dictionary = cover_nodes[k]
		if world.grid.at(cv["x"], cv["y"]) != Grid.COVER:
			if is_ore.call(cv["x"], cv["y"]):
				audio.play_sound("mining_gold_hit.mp3", 0.9)
				dug_this_frame = true
			var nd: Node = cv["node"]
			nd.free()
			cover_nodes.erase(k)
	# 收金音（A3）：supply 上涨 = 击杀奖励 / 矿产出到账；8t 限流防多矿同帧叠响
	var sup: int = world.supply
	if _supply_seen >= 0 and sup > _supply_seen and not dug_this_frame \
			and (world.tick_count - _gold_sfx_tick) >= GOLD_SFX_GLOBAL:
		audio.play_sound("gold_collect.mp3", 0.4)
		_gold_sfx_tick = world.tick_count
	_supply_seen = sup

	# 波次号角：单位数跳升 = 新一波进场上；60 tick 节流防连发（D1-7 换 wave_horn 专用音）
	var n_units := world.units.size()
	if n_units > _units_n and (world.tick_count - _horn_tick) > 60:
		audio.play_sound("wave_horn.mp3", 0.7)
		_horn_tick = world.tick_count
	_units_n = n_units

	# 建筑（真实资产 + 底座光环；塔施工压扁 + 脚手架；墙升起纯视觉 + 边缘拼接）。
	# 音效四路：新建（墙/塔，帧内去重）/ 拆除（含塌墙）/ 塔开火（cd 跳升）/ 核心受击（掉血+节流）。
	var seen_ids := {}
	var placed_wall := false
	var placed_tower := false
	var removed_any := false
	var tower_fired := false
	var wall_cells := {}
	for b in world.buildings:
		if int(b["hp"]) > 0 and int(b["kind"]) == Sim.B_WALL:
			wall_cells[int(b["x"]) * 1000 + int(b["y"])] = Vector2i(int(b["x"]), int(b["y"]))
	var changed := {}
	for key in wall_cells:
		if not _wall_cells.has(key):
			var c0: Vector2i = wall_cells[key]
			for nk in _wall_neighbor_keys(c0.x, c0.y):
				changed[nk] = true
	for key in _wall_cells:
		if not wall_cells.has(key):
			var c1: Vector2i = _wall_cells[key]
			for nk in _wall_neighbor_keys(c1.x, c1.y):
				changed[nk] = true
			var old_edge = _wall_edges.get(key)
			if old_edge != null:
				old_edge.free()
				_wall_edges.erase(key)
	_wall_cells = wall_cells
	_wall_entry_by_key = {}

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
				# 建筑 = 真实资产 3 件（2026-10-17：盒体拼接退役，spec §12 fallback 不再需要）
				var binst: Node3D = models.spawn_building(
					"tower" if kind == Sim.B_TOWER else ("core" if kind == Sim.B_CORE else "wall"))
				var body_root := Node3D.new()
				body_root.name = "body"
				body_root.add_child(binst)
				node.add_child(body_root)
				entry = { "node": node, "body": binst, "body_root": body_root, "kind": kind,
						"cd": int(b["cooldown"]), "lod": binst.get_meta("lod", {}),
						"fx": null, "ring": null, "cell": Vector2i(int(b["x"]), int(b["y"])),
						"build_total": maxi(int(b["build_left"]), 1), "rise_ms": -1, "rise_k": 1.0 }
				if kind == Sim.B_TOWER:
					entry["fx"] = _make_build_fx(int(b["x"]), int(b["y"]))
					placed_tower = true
				elif kind == Sim.B_WALL:
					if _sync_once:
						entry["rise_ms"] = Time.get_ticks_msec()
					_wall_entry_by_key[int(b["x"]) * 1000 + int(b["y"])] = entry
					placed_wall = true
				entry["ring"] = _make_base_ring(kind)
				_lod_dirty = true
				building_nodes[bid] = entry
			elif int(entry["kind"]) == Sim.B_TOWER:
				# 塔开火=冷却跳升（0 → 20）；递减序中任何回跳都只可能是刚射击
				var cdn: int = int(b["cooldown"])
				if cdn > int(entry["cd"]):
					tower_fired = true
				entry["cd"] = cdn
			if int(b["kind"]) == Sim.B_CORE:
				# 核心受击=血量下降；音效 30t 节流防多敌同啃叠音，震屏 10t 独立节流（要更密的反馈）
				var chp: int = int(b["hp"])
				if _core_hp >= 0 and chp < _core_hp:
					if (world.tick_count - _core_shake_tick) > CORE_SHAKE_THROTTLE:
						core.shake(CORE_SHAKE_AMP, CORE_SHAKE_DUR)
						_core_shake_tick = world.tick_count
					if (world.tick_count - _core_hit_tick) > CORE_HIT_THROTTLE:
						audio.play_sound("core_hit.mp3", 0.8)
						_core_hit_tick = world.tick_count
				_core_hp = chp
			var w := core.cell_to_world(int(b["x"]), int(b["y"]))
			var by := terrain.ground_y(int(b["x"]), int(b["y"]))
			var bnode: Node3D = entry["node"]
			bnode.position = Vector3(w.x, by, w.z)
			var kindn: int = int(b["kind"])
			var build_left: int = int(b["build_left"])
			if kindn == Sim.B_TOWER:
				if build_left > int(entry["build_total"]):
					entry["build_total"] = build_left # 首帧补记（视图可能晚一拍建档）
				var total: int = int(entry["build_total"])
				var yk := 1.0 if build_left <= 0 else 0.12 + 0.88 * (1.0 - float(build_left) / float(total))
				bnode.scale = Vector3(0.96, yk, 0.96)
				_update_build_fx(entry, build_left, total)
			else:
				bnode.scale = Vector3(0.96, 1.0, 0.96)
			if kindn == Sim.B_WALL:
				var rk := _wall_rise_k(entry)
				entry["rise_k"] = rk
				(entry["body_root"] as Node3D).scale = Vector3(1.0, rk, 1.0)
				var cont = _wall_edges.get(int(b["x"]) * 1000 + int(b["y"]))
				if cont != null:
					var cnode: Node3D = cont
					cnode.position = Vector3(w.x, by, w.z)
					cnode.scale = Vector3(1.0, rk, 1.0)
			var ringn = entry["ring"]
			if ringn != null:
				var roff := 0.035
				if kindn == Sim.B_TOWER:
					roff = 0.045
				elif kindn == Sim.B_CORE:
					roff = 0.050
				(ringn as Node3D).position = Vector3(w.x, by + roff, w.z)
	for bid2 in building_nodes.keys():
		if not seen_ids.has(bid2):
			var entry2: Dictionary = building_nodes[bid2]
			(entry2["node"] as Node).free()
			if entry2["ring"] != null:
				(entry2["ring"] as Node).free()
			if entry2["fx"] != null:
				(entry2["fx"] as Node).free()
			if int(entry2["kind"]) == Sim.B_WALL:
				var c2: Vector2i = entry2["cell"]
				building_nodes.erase(bid2)
				removed_any = true
				continue
			building_nodes.erase(bid2)
			if int(entry2["kind"]) != Sim.B_CORE:
				removed_any = true
	# 墙边缘段：受影响格（新增/删除墙自身 + 六邻）统一重算；新格即时套上升起系数。
	for nk2 in changed:
		var cc2: Vector2i = wall_cells.get(nk2, Vector2i(-1, -1))
		if cc2.x >= 0:
			_rebuild_wall_cell(cc2.x, cc2.y)
	for vk in _wall_entry_by_key:
		var vent: Dictionary = _wall_entry_by_key[vk]
		var vcont = _wall_edges.get(vk)
		if vcont != null:
			(vcont as Node3D).scale = Vector3(1.0, float(vent["rise_k"]), 1.0)
	_sync_once = true
	if placed_tower:
		audio.play_sound("build_stone_place.mp3", 0.8)
	elif placed_wall:
		audio.play_sound("wall_place.mp3", 0.8)
	if removed_any:
		audio.play_sound("building_remove.mp3", 0.8)
	if tower_fired:
		audio.play_sound("tower_shot.mp3", 0.6)

	# 英雄（腿/躯干/双肩/头 四盒合成，行走起伏 + 朝向；插值口径同单位）
	var h: Dictionary = world.hero
	if h.size() > 0:
		if hero == null:
			var hnode := Node3D.new()
			hnode.name = "hero"
			dyn.add_child(hnode)
			core._part(hnode, 0.0, 0.110, 0.0, 0.30, 0.22, 0.22, "hero_dark")
			core._part(hnode, 0.0, 0.410, 0.0, 0.36, 0.38, 0.24, "hero")
			core._part(hnode, -0.23, 0.600, 0.0, 0.14, 0.14, 0.14, "hero_dark")
			core._part(hnode, 0.23, 0.600, 0.0, 0.14, 0.14, 0.14, "hero_dark")
			core._part(hnode, 0.0, 0.700, 0.0, 0.20, 0.20, 0.20, "hero")
			hero = { "node": hnode, "px": int(h["x"]), "py": int(h["y"]) }
		var he: Dictionary = hero
		var frac := float((world.tick_count + 1) % int(Sim.HERO["speed_ticks"])) / float(Sim.HERO["speed_ticks"])
		var cw := core.cell_to_world(int(h["x"]), int(h["y"]))
		var pw := core.cell_to_world(int(he["px"]), int(he["py"]))
		var ix := pw.x + (cw.x - pw.x) * frac
		var iz := pw.z + (cw.z - pw.z) * frac
		var iy := terrain.ground_y(int(he["px"]), int(he["py"])) * (1.0 - frac) + terrain.ground_y(int(h["x"]), int(h["y"])) * frac
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
				var meshes: Array = [] # 闪白用：spawn 时收集一次，勿逐帧遍历
				_collect_meshes(unode, meshes)
				e = {
					"node": unode,
					"player": spawn["player"],
					"lod": spawn["lod"],
					"px": int(u["x"]),
					"py": int(u["y"]),
					"kind": int(u["kind"]),
					"hp": int(u["hp"]),
					"traveled": 0,
					"pulse": -1,
					"anim_until": -1,
					"meshes": meshes,
					"flash": -1,
					"sfx_hurt": -999,
				}
				unit_nodes[uid] = e
			var t: int = world.tick_count
			var player: AnimationPlayer = e["player"]
			if int(u["hp"]) < int(e["hp"]):
				e["pulse"] = t # 塔火命中 → 受击脉冲/受击动作
				e["anim_until"] = t + Z_HURT
				models.play(player, "Hurt", false)
				_play_hurt_sfx(e, t)
			# 动作状态机：单发到期回 Crawl；围攻中按确定性相位插 Attack（免 Rng）。
			if int(e["anim_until"]) >= 0 and t >= int(e["anim_until"]):
				e["anim_until"] = -1
				models.play(player, "Crawl", true)
			if int(e["anim_until"]) < 0 and int(u["atk_target"]) >= 0 and (t + uid) % 50 == 0:
				e["anim_until"] = t + Z_ATTACK
				models.play(player, "Attack", false)
				_play_attack_sfx(e, t)
			var frac2 := float((t + uid) % int(u["speed_ticks"])) / float(u["speed_ticks"])
			var cw2 := core.cell_to_world(int(u["x"]), int(u["y"]))
			var pw2 := core.cell_to_world(int(e["px"]), int(e["py"]))
			var ix2 := pw2.x + (cw2.x - pw2.x) * frac2
			var iz2 := pw2.z + (cw2.z - pw2.z) * frac2
			var iy2 := terrain.ground_y(int(e["px"]), int(e["py"])) * (1.0 - frac2) + terrain.ground_y(int(u["x"]), int(u["y"])) * frac2
			var m := 1.0
			var pulse_i: int = e["pulse"]
			if pulse_i >= 0:
				var a := 1.0 - float(t - pulse_i) / 6.0
				if a > 0.0:
					m = 1.0 + 0.6 * a
					_set_flash(e, 2 if a > 0.5 else 1) # 受击闪白随脉冲两档衰减
				else:
					e["pulse"] = -1
					_set_flash(e, 0)
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
			if cam_ok:
				models.update_lod(e["lod"], cam_pos, Vector3(ix2, iy2, iz2))
	for uid2 in unit_nodes.keys():
		if not useen.has(uid2):
			var e3: Dictionary = unit_nodes[uid2]
			var kind3: int = e3["kind"]
			audio.play_sound("zerg_death.mp3" if kind3 == Sim.E_SWARM else "orc_death.mp3", 0.85)
			e3["dying"] = world.tick_count
			models.play(e3["player"], "Death", false) # 模型走死亡动画（1.4s），不做放大下沉
			death_fx.append(e3)
			var nd3: Node3D = e3["node"]
			var scr := core.world_to_screen(nd3.position.x, nd3.position.y, nd3.position.z)
			if scr.x >= 0.0:
				var total: int = int(Sim.ENEMIES[kind3 - 1]["reward"]) + Lua64.lshr(int(e3["traveled"]), Sim.CONVOY_SHIFT)
				_float_bounty(scr, "+" + str(total))
			unit_nodes.erase(uid2)
	update_death_fx(world.tick_count)
	update_shock_ring(world)

	# 静态件（覆盖层/建筑）LOD：相机变换或新注册（脏标）时统一刷。
	if cam_ok:
		var lod_xf := cam.global_transform
		if _lod_dirty or lod_xf != _lod_cam:
			_lod_cam = lod_xf
			_lod_dirty = false
			for ck in cover_nodes.keys():
				var cv3: Dictionary = cover_nodes[ck]
				models.update_lod(cv3["lod"], cam_pos, (cv3["node"] as Node3D).global_position)
			for bk in building_nodes.keys():
				var be3: Dictionary = building_nodes[bk]
				models.update_lod(be3["lod"], cam_pos, (be3["node"] as Node3D).global_position)

	var vp := host.get_viewport().get_visible_rect().size
	if vp.x > 0.0 and vp.y > 0.0 and (vp.x != core._fit_w or vp.y != core._fit_h):
		core.fit_camera()


## 收集模型子树下的 MeshInstance3D（闪白用；spawn 时调一次，勿逐帧遍历）
func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)


## 受击音（A1）：单兵 1.0s + 全局 5 次/秒双限流。大群围攻逐兵逐帧触发必音爆，两条都要。
func _play_hurt_sfx(e: Dictionary, t: int) -> void:
	if (t - _hurt_sfx_tick) < HURT_SFX_GLOBAL:
		return
	if (t - int(e.get("sfx_hurt", -999))) < HURT_SFX_UNIT:
		return
	_hurt_sfx_tick = t
	e["sfx_hurt"] = t
	var sname := "zerg_hurt.mp3" if int(e["kind"]) == Sim.E_SWARM else "orc_hurt.mp3"
	audio.play_sound(sname, 0.5)


## 攻击音（A2）：全局 5 次/秒限流（攻击动作本身已按 (t+uid)%50 错峰）
func _play_attack_sfx(e: Dictionary, t: int) -> void:
	if (t - _attack_sfx_tick) < ATTACK_SFX_GLOBAL:
		return
	_attack_sfx_tick = t
	var sname := "zerg_blade_attack.mp3" if int(e["kind"]) == Sim.E_SWARM else "orc_warrior_attack.mp3"
	audio.play_sound(sname, 0.45)


## 闪白材质（共享单例）：material_overlay 只叠一层，不改原材质 → 不存在全体同闪。
func _flash_material(hi: bool) -> StandardMaterial3D:
	if hi:
		if _flash_hi == null:
			_flash_hi = _make_flash_material(FLASH_HI_LEVEL)
		return _flash_hi
	if _flash_lo == null:
		_flash_lo = _make_flash_material(FLASH_LO_LEVEL)
	return _flash_lo


## ADD 混合的提亮材质。两条实测结论（2026-10-21，shots/_tmp_flash_*.png 对照）：
## ① alpha 在 ADD 下不参与强度，强度必须写进颜色值；
## ② CULL_DISABLED 会让背面再叠一遍直接过曝成纯白，必须 CULL_BACK。
func _make_flash_material(level: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.albedo_color = Color(level, level, level, 1.0)
	return mat


## 闪白档位（-1/0 关 / 1 低 / 2 高）：只在档位变化时写 overlay，逐帧零开销。
## 低画质档（fx_quality 0）强制关：仍走一次写 null 的路径，避免残留上一次的亮层。
func _set_flash(e: Dictionary, lvl: int) -> void:
	if fx_quality <= 0:
		lvl = 0
	if int(e.get("flash", -1)) == lvl:
		return
	e["flash"] = lvl
	var mat: Material = null
	if lvl > 0:
		mat = _flash_material(lvl == 2)
	for mi in e.get("meshes", []):
		(mi as MeshInstance3D).material_overlay = mat


## 死亡消散：模型的死亡动画播完（Z_DEATH = 28 tick = 1.4s）后移除节点。
## 特效质量：中 = 半程 0.7s；低 = 1 tick 即移除（省瞬态节点/动画开销）；高 = 原口径。
func update_death_fx(tick: int) -> void:
	var life := Z_DEATH
	if fx_quality == 1:
		life = int(Z_DEATH * 0.5)
	elif fx_quality == 0:
		life = 1
	for i in range(death_fx.size() - 1, -1, -1):
		var e: Dictionary = death_fx[i]
		var age := tick - int(e["dying"])
		var dn: Node3D = e["node"]
		if age >= life:
			dn.free()
			death_fx.remove_at(i)


## 特效质量应用（0 低 / 1 中 / 2 高；由 view.apply_video 转发）。
func apply_fx_quality(level: int) -> void:
	fx_quality = clampi(level, 0, 2)


## 震荡波扩散环：英雄冷却跳升 = 刚施放；方框环贴地扩散到技能半径后移除。
func update_shock_ring(world: World) -> void:
	var h: Dictionary = world.hero
	if h.size() > 0:
		var hx: int = h["x"]
		var hy: int = h["y"]
		if int(h["skill_cd"]) > _hero_cd:
			core.shake(SKILL_SHAKE_AMP, SKILL_SHAKE_DUR) # 技能释放：一次性重震，无节流（释放本身有冷却）
			var w := core.cell_to_world(hx, hy)
			var g := Node3D.new()
			g.name = "shockring"
			g.position = Vector3(w.x, terrain.ground_y(hx, hy), w.z)
			var edges := [
				{ "x": 0.0, "z": 1.0, "sx": 2.0, "sz": 0.08 },
				{ "x": 0.0, "z": -1.0, "sx": 2.0, "sz": 0.08 },
				{ "x": 1.0, "z": 0.0, "sx": 0.08, "sz": 2.0 },
				{ "x": -1.0, "z": 0.0, "sx": 0.08, "sz": 2.0 },
			]
			for i in edges.size():
				var ed: Dictionary = edges[i]
				var n := MeshInstance3D.new()
				n.mesh = core.box_mesh
				n.material_override = core.mats["hero"]
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


# ---- 赏金浮字 / 统计 ----

## 击杀赏金浮字回调（转发给 HUD）
func _float_bounty(scr: Vector2, text: String) -> void:
	if on_float.is_valid():
		on_float.call(scr.x, scr.y, text)


## 探针用统计（C1/C2 判定）。
func debug_stats() -> Dictionary:
	return {
		"field": terrain._stat_field,
		"plain": terrain._stat_plain,
		"solids": _stat_solids,
		"covers": cover_nodes.size(),
		"cam": core.camera != null,
		"units": unit_nodes.size(),
		"buildings": building_nodes.size(),
		"death_fx": death_fx.size(),
		"hero": hero != null,
		"ring_fx": ring != null,
		"ghost": ghost_alive,
		"heat": terrain._stat_heat,
		"wall_edges": _wall_edges.size(),
		"wall_cells": _wall_cells.size(),
		"preview": preview_root.get_child_count() if preview_root != null else 0,
		"range": range_root.get_child_count() if range_root != null else 0,
		"rings": _count_rings(),
	}


## 底座光环计数（探针用；= 建筑节点数，核心/墙/塔各一环）。
func _count_rings() -> int:
	var n := 0
	for bid in building_nodes:
		if building_nodes[bid]["ring"] != null:
			n += 1
	return n
