extends SceneTree

# 资产接入探针：真实模型（单位/金堆/瓦砾）在游戏中的装载、缩放校准、动画状态机、渲染。
# 跑法（cwd=reroute-godot，窗口模式）：godot -s res://probe_asset.gd
#
# 判定：exit 0 + `[ASSET] PASS`；stderr 无 ERROR（外层校验）。
# 证据：shots/asset_game.png（对局全景）+ shots/asset_close.png（单位特写）。

var checks := 0
var bad := 0
var fail_list: Array = []


func _chk(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		fail_list.append(msg)


func _cmp_int(got: int, want: int, msg: String) -> void:
	_chk(got == want, msg + "（得 %d 望 %d）" % [got, want])


const ModelsScript = preload("res://game/models.gd")
const Sim = preload("res://sim/sim.gd")
const Grid = preload("res://sim/grid.gd")


func _initialize() -> void:
	# ---- 1. 模型装载：10 个 glb 全部可加载；3 个 zerg 有播放器与 5 动画 ----
	var models = ModelsScript.new()
	var zergs := {
		"worker": "res://assets/models/zerg_worker.glb",
		"blade": "res://assets/models/zerg_blade.glb",
		"king": "res://assets/models/zerg_king.glb",
	}
	for k in zergs:
		var packed: PackedScene = load(zergs[k])
		_chk(packed != null, "加载 " + str(k))
		if packed == null:
			continue
		var inst: Node3D = packed.instantiate()
		var player := models.find_player(inst)
		_chk(player != null, str(k) + " 有 AnimationPlayer")
		if player != null:
			var list := player.get_animation_list()
			for clip in ["Idle", "Crawl", "Attack", "Hurt", "Death"]:
				_chk(list.has(clip), str(k) + " 动画 " + clip)
		var box := models.mesh_aabb(inst)
		_chk(box.size.x > 0.01 and box.size.y > 0.01 and box.size.z > 0.01, str(k) + " 网格包围盒有效")
		inst.free()
	for p in ["gold_pile_full", "gold_pile_partial", "gold_pile_small", "gold_pile_low",
			"rubble_sand", "rubble_brown", "rubble_gray"]:
		var packed2: PackedScene = load("res://assets/models/" + p + ".glb")
		_chk(packed2 != null, "加载 " + p)
		if packed2 != null:
			packed2.instantiate().free()

	# ---- 2. 进对局（R6 起启动即标题屏）----
	var root := get_root()
	var main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame
	main.set_process(false) # 时序铁律：await 后再关（此前有效）
	main.start_match()
	for _i in 2:
		await process_frame
	var view = main.view
	var world = main.world

	# ---- 3. 单位接入：两种敌人各 spawn 一个，检查模型/校准/Crawl ----
	var spots := _free_spots(view, world, 2)
	_chk(spots.size() == 2, "找到 2 个出生格")
	var kinds := [Sim.E_SWARM, Sim.E_BEHEMOTH]
	for i in 2:
		world.apply_command({ "kind": "spawn", "x": spots[i].x, "y": spots[i].y, "speed": 4, "kind_id": kinds[i] })
	view.sync(world)
	# 校准长度按形态（view.ZFORM 映射：虫群→blade 1.6，蛮兽→king 2.6）
	var want_len := { Sim.E_SWARM: 1.6, Sim.E_BEHEMOTH: 2.6 }
	for u in world.units:
		if int(u["hp"]) > 0:
			var e = view.unit_nodes.get(int(u["id"]))
			_chk(e != null, "单位节点存在 id=" + str(u["id"]))
			if e == null:
				continue
			var player2: AnimationPlayer = e["player"]
			_chk(player2 != null, "单位 %d 有播放器" % int(u["id"]))
			if player2 != null:
				_chk(player2.current_animation == "Crawl", "单位 %d 基态 Crawl" % int(u["id"]))
			var wrap: Node3D = e["node"]
			_chk(wrap.get_child_count() == 1, "wrapper 单子（glb 实例）")
			if wrap.get_child_count() == 1:
				var inst2: Node3D = wrap.get_child(0)
				var sc := inst2.scale
				_chk(absf(sc.x - sc.y) < 1e-6 and absf(sc.y - sc.z) < 1e-6, "缩放各轴一致")
				var box2 := models.mesh_aabb(inst2)
				var longest: float = maxf(box2.size.x, maxf(box2.size.y, box2.size.z)) * sc.x
				var target: float = float(want_len[int(u["kind"])])
				_chk(absf(longest - target) < target * 0.02, "校准尺寸 %d 形态 %.3f ≈ %.1f" % [int(u["kind"]), longest, target])

	# ---- 4. 受击 → Hurt；到期回 Crawl ----
	var probe_id := -1
	for u in world.units:
		if int(u["hp"]) > 0 and int(u["kind"]) == Sim.E_BEHEMOTH:
			probe_id = int(u["id"])
	var u1 = _find_unit(world, probe_id)
	_chk(u1 != null, "取到受测单位")
	if u1 != null:
		u1["hp"] = int(u1["hp"]) - 1 # 白盒：制造受击
		world.tick()
		view.sync(world)
		var e1 = view.unit_nodes.get(probe_id)
		if e1 != null:
			var p3: AnimationPlayer = e1["player"]
			_chk(p3 != null and p3.current_animation == "Hurt", "受击动画 Hurt")
			var t_now: int = world.tick_count
			var until: int = int(e1["anim_until"])
			_chk(until == t_now + 10, "Hurt 到期 = t+10（得 %d）" % until)
			# 推满到期
			while world.tick_count < until:
				world.tick()
				view.sync(world)
			view.sync(world)
			_chk(p3.current_animation == "Crawl", "受击到期回 Crawl")

	# ---- 5. Attack 触发（白盒 atk_target + 确定性相位对齐）----
	if u1 != null and int(u1["hp"]) > 0:
		var uid: int = probe_id
		var guard := 0
		while (world.tick_count + uid) % 50 != 0 and guard < 60:
			world.tick()
			guard += 1
		u1["atk_target"] = int(world.core["id"]) # tick 后、sync 前注入（world 每 tick 会重算覆盖）
		view.sync(world)
		var e2 = view.unit_nodes.get(uid)
		if e2 != null:
			var p4: AnimationPlayer = e2["player"]
			_chk(p4 != null and p4.current_animation == "Attack", "围攻相位触发 Attack")
			var until2: int = int(e2["anim_until"])
			_chk(until2 == world.tick_count + 18, "Attack 到期 = t+18（得 %d）" % until2)
			while world.tick_count < until2:
				world.tick()
				view.sync(world)
			view.sync(world)
			_chk(p4.current_animation == "Crawl", "Attack 到期回 Crawl")

	# ---- 6. 覆盖层真实模型（金堆满档 + 瓦砾变体）----
	var n_ore := 0
	var n_rubble := 0
	var ore_nodes: Array = []
	var rub_nodes: Array = []
	for k in view.cover_nodes.keys():
		var cv: Dictionary = view.cover_nodes[k]
		if view.is_ore.call(cv["x"], cv["y"]):
			n_ore += 1
			ore_nodes.append(cv["node"])
		else:
			n_rubble += 1
			rub_nodes.append(cv["node"])
	_cmp_int(n_ore + n_rubble, 23, "覆盖层总数")
	_chk(n_ore >= 4 and n_rubble >= 4, "矿 %d / 瓦砾 %d 双类共存" % [n_ore, n_rubble])
	if ore_nodes.size() > 0:
		var gn: Node3D = ore_nodes[0]
		_chk(absf(gn.scale.x - 0.78) < 1e-6, "金堆 root 缩放 0.78")
		var gsub := _count_meshes(gn)
		_chk(gsub >= 1, "金堆含真实网格")
	if rub_nodes.size() > 0:
		var rn: Node3D = rub_nodes[0]
		var rsub := _count_meshes(rn)
		_chk(rsub >= 1, "瓦砾含真实网格")

	# ---- 7. 渲染存证 ----
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://shots/asset_game.png")
	# 特写：相机拉到第一个单位旁（拍完还原）
	if view.camera != null and u1 != null and int(u1["hp"]) > 0:
		var e3 = view.unit_nodes.get(probe_id)
		if e3 != null:
			var cam: Camera3D = view.camera
			var old_tf := cam.global_transform
			var upos: Vector3 = (e3["node"] as Node3D).position
			cam.look_at_from_position(upos + Vector3(2.2, 1.6, 2.2), upos + Vector3(0.0, 0.35, 0.0), Vector3.UP)
			for _i in 8:
				await process_frame
			root.get_texture().get_image().save_png("res://shots/asset_close.png")
			cam.global_transform = old_tf
			for _i in 4:
				await process_frame
	_chk(true, "截图存证")

	# ---- 收口 ----
	var ok := bad == 0
	print("[ASSET] checks=", checks, " bad=", bad)
	for m in fail_list.slice(0, 12):
		print("[ASSET] FAIL: ", m)
	print("[ASSET] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


## 数一棵子树里的 MeshInstance3D（真实网格证据）。
func _count_meshes(n: Node) -> int:
	var c := 0
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D:
			c += 1
		for ch in x.get_children():
			stack.append(ch)
	return c


func _find_unit(world, uid: int):
	if uid < 0:
		return null
	for u in world.units:
		if int(u["id"]) == uid:
			return u
	return null


## 找 n 个互相不重叠的自由可走格（远离核心，避免与既有实体叠加）。
func _free_spots(view, world, n: int) -> Array:
	var out: Array = []
	var cx: int = int(world.core["x"])
	var cy: int = int(world.core["y"])
	for y in range(4, 44):
		for x in range(4, 44):
			if out.size() >= n:
				return out
			if absi(x - cx) + absi(y - cy) < 10:
				continue
			if world.grid.at(x, y) != Grid.OPEN:
				continue
			var near := false
			for s in out:
				if absi(s.x - x) + absi(s.y - y) < 3:
					near = true
			if near:
				continue
			out.append(Vector2i(x, y))
	return out
