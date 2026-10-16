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
var hero = null # { node, px, py }
var ring = null # { node, born }

var ghost: Node3D = null
var ghost_mi: MeshInstance3D = null
var ghost_alive := false

var is_ore: Callable
var models = null # 真实资产模型管理器（ModelsScript 实例；_ready 建立）

## 击杀赏金浮字回调（R5 HUD 注入 (sx, sy, text)；未注入即空转）
var on_float: Callable

var _height_rev := -1
var _hero_cd := 0
var _units_n := 0
var _horn_tick := -999
var _core_hp := -1 # 核心血量缓存（受击音检测；-1 = 未建档）
var _core_hit_tick := -999 # 最近核心受击音节流点
var _stat_solids := 0


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
	_core_hp = -1
	_core_hit_tick = -999

	var n_solid := 0
	for y in pgrid.h:
		for x in pgrid.w:
			var c := pgrid.at(x, y)
			if c == Grid.SOLID:
				n_solid += 1 # SOLID 视觉融入连续地面网格：岩石色 + 1.6m 抬升
			elif c == Grid.COVER:
				_make_cover(x, y)
	_stat_solids = n_solid


## 覆盖层（真实资产）：矿格 = 砂金堆满档（挖开即随覆盖层移除）；
## 表土/插口 = 瓦砾堆 3 变体（(x*7 + y*13) % 3 确定性取模，同母版口径）。
func _make_cover(x: int, y: int) -> void:
	var w := core.cell_to_world(x, y)
	var gy := terrain.ground_y(x, y)
	var node: Node3D
	if is_ore.call(x, y):
		node = models.spawn_gold(tiles, Vector3(w.x, gy, w.z))
	else:
		var variant: int = (x * 7 + y * 13) % 3
		node = models.spawn_rubble(tiles, variant, Vector3(w.x, gy, w.z), 0.94)
	cover_nodes[x * 1000 + y] = { "node": node, "x": x, "y": y }


# ---- 幽灵预览 ----

## cells = Array[Vector2i] 或空（藏起）；bad = 有效性染色。
## 逐格一个方块（斜线不覆盖线外格，各自贴合所在柱顶）；ghost_mi 指向首格网格。
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
		ghost_mi = null
		dyn.add_child(ghost)
		ghost_alive = true
	while ghost.get_child_count() > cells.size():
		var extra: Node = ghost.get_child(ghost.get_child_count() - 1)
		ghost.remove_child(extra)
		extra.queue_free()
	while ghost.get_child_count() < cells.size():
		var fresh := MeshInstance3D.new()
		fresh.mesh = core.box_mesh
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


# ---- 每帧同步 ----

## 每帧同步：地形高度变化重建、热层刷新、覆盖层消失、建筑/英雄/单位/死亡消散/震荡环/相机取景
func sync(world: World) -> void:
	# 仅重建地面网格；高度增减总和相同也必须刷新，实体缓存不得被清掉。
	if terrain.grid != null and terrain.grid.height_rev != _height_rev:
		_height_rev = terrain.grid.height_rev
		terrain._rebuild_field()
	if terrain.heat_on and world.grid.rev != terrain.heat_rev:
		terrain.rebuild_heat(world)

	# 挖开的覆盖层消失
	for k in cover_nodes.keys():
		var cv: Dictionary = cover_nodes[k]
		if world.grid.at(cv["x"], cv["y"]) != Grid.COVER:
			if is_ore.call(cv["x"], cv["y"]):
				audio.play_sound("mining_gold_hit.mp3", 0.9)
			var nd: Node = cv["node"]
			nd.free()
			cover_nodes.erase(k)

	# 波次号角：单位数跳升 = 新一波进场上；60 tick 节流防连发（D1-7 换 wave_horn 专用音）
	var n_units := world.units.size()
	if n_units > _units_n and (world.tick_count - _horn_tick) > 60:
		audio.play_sound("wave_horn.mp3", 0.7)
		_horn_tick = world.tick_count
	_units_n = n_units

	# 建筑（剪影：容器贴地 + 多盒组合；施工中整体压扁 0.35，完工弹起）。
	# 音效四路：新建（墙/塔，帧内去重）/ 拆除（含塌墙）/ 塔开火（cd 跳升）/ 核心受击（掉血+节流）。
	var seen_ids := {}
	var placed_wall := false
	var placed_tower := false
	var removed_any := false
	var tower_fired := false
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
					core._part(node, 0.0, 0.225, 0.0, 1.00, 0.45, 1.00, "tower_cap")
					core._part(node, 0.0, 1.300, 0.0, 0.70, 1.70, 0.70, "tower")
					core._part(node, 0.0, 2.375, 0.0, 0.94, 0.45, 0.94, "tower_cap")
					core._part(node, 0.0, 2.850, 0.0, 0.26, 0.50, 0.26, "hero")
				elif kind == Sim.B_CORE:
					core._part(node, 0.0, 0.200, 0.0, 1.15, 0.40, 1.15, "solid")
					core._part(node, 0.0, 1.150, 0.0, 0.85, 1.50, 0.85, "core")
					core._part(node, 0.0, 2.250, 0.0, 0.45, 0.45, 0.45, "core")
				else:
					core._part(node, 0.0, 0.525, 0.0, 0.94, 1.05, 0.94, "wall")
					core._part(node, 0.0, 1.190, 0.0, 1.00, 0.28, 1.00, "wall_cap")
				entry = { "node": node, "kind": kind, "cd": int(b["cooldown"]) }
				building_nodes[bid] = entry
				if kind == Sim.B_TOWER:
					placed_tower = true
				elif kind == Sim.B_WALL:
					placed_wall = true
			elif int(entry["kind"]) == Sim.B_TOWER:
				# 塔开火=冷却跳升（0 → 20）；递减序中任何回跳都只可能是刚射击
				var cdn: int = int(b["cooldown"])
				if cdn > int(entry["cd"]):
					tower_fired = true
				entry["cd"] = cdn
			if int(b["kind"]) == Sim.B_CORE:
				# 核心受击=血量下降；30t 节流防多敌同啃叠音（首次建档不响）
				var chp: int = int(b["hp"])
				if _core_hp >= 0 and chp < _core_hp and (world.tick_count - _core_hit_tick) > CORE_HIT_THROTTLE:
					audio.play_sound("core_hit.mp3", 0.8)
					_core_hit_tick = world.tick_count
				_core_hp = chp
			var w := core.cell_to_world(int(b["x"]), int(b["y"]))
			var by := terrain.ground_y(int(b["x"]), int(b["y"]))
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
			if int(entry2["kind"]) != Sim.B_CORE:
				removed_any = true
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

	var vp := host.get_viewport().get_visible_rect().size
	if vp.x > 0.0 and vp.y > 0.0 and (vp.x != core._fit_w or vp.y != core._fit_h):
		core.fit_camera()


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
	}
