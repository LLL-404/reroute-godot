extends SceneTree

# C7 判定：音频三件套（窗口模式运行；headless 音频驱动为 Dummy，播放态不作数）。
# 链路：19 个 mp3 导入齐全 → 池结构（4 轮换 + 环境 + BGM）→ 环境音自启动循环 →
#      轮换/音量/缺失静默接口 → BGM 开关 → 真实事件触发链
#      （开战 BGM 自动开 / 放塔落石 / 出怪号角 / 击杀死亡 / 挖矿金击 / 技能怒吼 / 回标题停 BGM）。
# 跑法（cwd=reroute-godot）：godot -s res://tests/probes/probe_audio.gd
const ALL_MP3 := [
	"bgm_reroute.mp3",
	"build_stone_place.mp3",
	"dungeon_ambience.mp3",
	"gold_collect.mp3",
	"mining_gold_hit.mp3",
	"orc_chief_roar.mp3",
	"orc_death.mp3",
	"orc_hurt.mp3",
	"orc_step.mp3",
	"orc_warrior_attack.mp3",
	"orc_worker_effort.mp3",
	"room_door_open.mp3",
	"room_fire_loop.mp3",
	"zerg_blade_attack.mp3",
	"zerg_death.mp3",
	"zerg_hurt.mp3",
	"zerg_king_roar.mp3",
	"zerg_step.mp3",
	"zerg_worker_chitter.mp3",
]

var checks := 0
var bad := 0
var fail_list: Array = []


func _initialize() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for _i in 5:
		await process_frame # -s 模式：_ready 首帧才跑；set_process 须在 ready 之后调用才粘
	main.set_process(false)
	var view = main.view

	# ---- 1. mp3 导入齐全（19 个；最长时长抽查）----
	var loaded := 0
	var longest := 0.0
	for name in ALL_MP3:
		var s: AudioStream = load("res://assets/audio/sfx/" + name) as AudioStream
		if s != null:
			loaded += 1
			longest = maxf(longest, s.get_length())
		else:
			_fail("mp3 未导入：" + name)
	_cmp_i(loaded, ALL_MP3.size(), "19 个 mp3 全部可加载")
	_gcheck(longest > 1.0, "最长音频时长 > 1s（实测 %.2fs）" % longest)

	# ---- 2. 池结构（SFX 根 + 4 轮换 + 环境 + BGM）----
	_gcheck(view.has_node("SFX"), "SFX 根节点在树")
	_cmp_i(view.sfx_players.size(), 4, "SFX 轮换池 = 4")
	_gcheck(view.sfx_amb != null, "环境音源存在")
	_gcheck(view.bgm_player != null, "BGM 源存在")
	if view.has_node("SFX"):
		_cmp_i(view.get_node("SFX").get_child_count(), 6, "SFX 根子节点数 = 6")

	# ---- 3. 环境音自启动（循环 + 音量 0.22）；标题态 BGM 静默 ----
	_gcheck(view.sfx_amb.playing, "环境音自启动播放")
	var amb_stream: AudioStream = view.sfx_amb.stream
	var amb_mp3 := amb_stream as AudioStreamMP3
	_gcheck(amb_mp3 != null and amb_mp3.loop, "环境音循环开")
	_approx(view.sfx_amb.volume_db, linear_to_db(0.22), "环境音音量 = linear_to_db(0.22)")
	_gcheck(view.bgm_on == false and not view.bgm_player.playing, "标题态 BGM 静默")
	_gcheck(view.sfx_log.is_empty(), "启动零音效（无虚假触发）")

	# ---- 4. 轮换池接口：4 连播轮遍各源；音量映射；缺失静默 ----
	var i0: int = view._sfx_next
	var four := ["gold_collect.mp3", "orc_step.mp3", "zerg_step.mp3", "room_door_open.mp3"]
	for k in 4:
		view.play_sound(four[k], 0.8)
	_cmp_i(view._sfx_next, i0, "4 连播后轮换下标回绕")
	for k in 4:
		var p2: AudioStreamPlayer = view.sfx_players[(i0 + k) % 4]
		var ok2: bool = p2.stream != null and String(p2.stream.resource_path).ends_with(four[k])
		_gcheck(ok2, "轮换第 %d 发命中源 %d" % [k + 1, (i0 + k) % 4])
	var plast: AudioStreamPlayer = view.sfx_players[(i0 + 3) % 4]
	_gcheck(plast.playing, "流已起播（playing）")
	_approx(plast.volume_db, linear_to_db(0.8), "音量 = linear_to_db(0.8)")
	view.play_sound("orc_hurt.mp3", 0.5)
	var pnext: AudioStreamPlayer = view.sfx_players[i0]
	_approx(pnext.volume_db, linear_to_db(0.5), "音量 = linear_to_db(0.5)")
	var n_before: int = view._sfx_next
	view.play_sound("no_such_file.mp3", 0.8)
	_cmp_i(view._sfx_next, n_before, "缺失文件不占轮换槽")
	_gcheck(not view.sfx_log.has("no_such_file.mp3"), "缺失文件零日志")

	# ---- 5. 19 个名字全部可播（含 BGM/环境文件兼作 SFX；接口无报错）----
	for name2 in ALL_MP3:
		view.play_sound(name2, 0.8)
	var missed := 0
	for name3 in ALL_MP3:
		if not view.sfx_log.has(name3):
			missed += 1
	_cmp_i(missed, 0, "19 个名字全部进日志（无静默失败）")

	# ---- 6. BGM 接口 ----
	view.bgm(true)
	_gcheck(view.bgm_on and view.bgm_player.playing, "bgm(true) 播放中")
	var bm := view.bgm_player.stream as AudioStreamMP3
	_gcheck(bm != null and bm.loop, "BGM 循环开")
	_approx(view.bgm_player.volume_db, linear_to_db(0.34), "BGM 音量 = linear_to_db(0.34)")
	view.bgm(false)
	_gcheck(view.bgm_on == false and not view.bgm_player.playing, "bgm(false) 停播")

	# ---- 7. 真实事件链（触发点照母版）----
	var w = main.world
	main.start_match()
	_gcheck(view.bgm_on and view.bgm_player.playing, "start_match → BGM 自动开")

	# 放塔 → build_stone_place（母版 view3d L705）
	var c0: int = _cnt(view, "build_stone_place.mp3")
	var tower_cell: Vector2i = _find_open(w, 0, 0, 47, 47)
	_gcheck(tower_cell.x >= 0, "塔格扫描")
	if tower_cell.x >= 0:
		w.apply_command({ "kind": "tower", "x": tower_cell.x, "y": tower_cell.y })
		view.sync(w)
	_cmp_i(_cnt(view, "build_stone_place.mp3") - c0, 1, "放塔 → 落石音 1 次")

	# 出怪 → 号角（母版 view3d L664：单位数跳升 + 60t 节流）
	var c1: int = _cnt(view, "orc_chief_roar.mp3")
	var spawn_cell: Vector2i = _find_open(w, 4, 32, 44, 44)
	_gcheck(spawn_cell.x >= 0, "出怪格扫描")
	if spawn_cell.x >= 0:
		w.apply_command({ "kind": "spawn", "x": spawn_cell.x, "y": spawn_cell.y, "speed": 4, "kind_id": Sim.E_SWARM })
		view.sync(w)
	_cmp_i(_cnt(view, "orc_chief_roar.mp3") - c1, 1, "出怪 → 号角 1 次")

	# 击杀 → 死亡音（母版 view3d L861：实体从活表消失）
	var c2: int = _cnt(view, "zerg_death.mp3")
	if w.units.size() > 0:
		var u0: Dictionary = w.units[0]
		u0["hp"] = 0
		w.tick()
		view.sync(w)
	_cmp_i(_cnt(view, "zerg_death.mp3") - c2, 1, "击杀 → 死亡音 1 次")

	# 挖矿 → 挖金音（母版 view3d L655：矿石覆盖格消失）
	var c3: int = _cnt(view, "mining_gold_hit.mp3")
	var ore_cell: Vector2i = _find_ore_cover(view, w)
	_gcheck(ore_cell.x >= 0, "矿格扫描")
	if ore_cell.x >= 0:
		w.apply_command({ "kind": "dig", "x": ore_cell.x, "y": ore_cell.y })
		view.sync(w)
	_cmp_i(_cnt(view, "mining_gold_hit.mp3") - c3, 1, "挖矿 → 挖金音 1 次")

	# 技能 → 怒吼（母版 main.lua L244：main 技能回调）
	var c4: int = _cnt(view, "orc_chief_roar.mp3")
	main._on_hud_skill()
	_cmp_i(_cnt(view, "orc_chief_roar.mp3") - c4, 1, "技能 → 怒吼 1 次")

	# 回标题 → BGM 停；环境音仍在（母版 main.lua L187）
	main.to_title()
	_gcheck(view.bgm_on == false and not view.bgm_player.playing, "to_title → BGM 停")
	_gcheck(view.sfx_amb.playing, "回标题后环境音仍播")

	_finish()


# ---------------- 扫描辅助 ----------------

func _find_open(world, x0: int, y0: int, x1: int, y1: int) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not world.grid.passable(x, y):
				continue
			if world.building_at(x, y) != null:
				continue
			if not world.cell_vacant(x, y):
				continue
			var hr: Dictionary = world.hero
			if x == int(hr["x"]) and y == int(hr["y"]):
				continue
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_ore_cover(view, world) -> Vector2i:
	var rects := [[4, 40, 6, 43], [22, 20, 26, 20]]
	for r in rects:
		for y in range(int(r[1]), int(r[3]) + 1):
			for x in range(int(r[0]), int(r[2]) + 1):
				if world.grid.at(x, y) != Grid.COVER:
					continue
				if view.cover_nodes.has(x * 1000 + y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


# ---------------- 计数 / 判定辅助 ----------------

func _cnt(view, sname: String) -> int:
	return int(view.sfx_log.get(sname, 0))


func _fail(msg: String) -> void:
	bad += 1
	fail_list.append(msg)


func _gcheck(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		_fail(label)


func _cmp_i(got: int, want: int, label: String) -> void:
	checks += 1
	if got != want:
		_fail("%s got=%d want=%d" % [label, got, want])


func _approx(got: float, want: float, label: String) -> void:
	checks += 1
	if not is_equal_approx(got, want):
		_fail("%s got=%.4f want=%.4f" % [label, got, want])


func _finish() -> void:
	var ok := bad == 0 and checks >= 25
	print("[AUDIO] checks=", checks, " bad=", bad)
	for i in mini(fail_list.size(), 12):
		print("[AUDIO] fail: ", fail_list[i])
	print("[AUDIO] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
