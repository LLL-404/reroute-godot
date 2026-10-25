extends RefCounted

# save 单测：往返一致性 / 续跑连续性 / int64 保真 / 坏档拒绝面。
# 方法：真实 64² 场景 + 固定命令剧本（确定性）；JSON 字符串往返走真实 I/O 形态。
# 白盒仅用于制造边界（tick 推进、找格），行为断言一律走 apply_command/tick。


func _tick(w: World, n: int) -> void:
	for _i in n:
		w.tick()


## 找一个「通行 + 空置 + 无建筑 + 非英雄 + 指定高度」的格子（-1,-1 = 无）。
func _find_cell(w: World, want_h: int) -> Vector2i:
	for y in w.grid.h:
		for x in w.grid.w:
			if w.grid.passable(x, y) and w.grid.get_h(x, y) == want_h and w.building_at(x, y) == null and w.cell_vacant(x, y) and not (x == w.hero["x"] and y == w.hero["y"]):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## 固定命令剧本：挖矿 / 建墙 / 开暗门 / 填高 / 挖低（覆盖格子与高度两类状态）。
func _scripted(w: World) -> void:
	w.apply_command({ "kind": "dig", "x": w.sc.mid_ore[0].x, "y": w.sc.mid_ore[0].y })
	w.apply_command({ "kind": "wall", "x": w.sc.core.x, "y": 20 })
	w.apply_command({ "kind": "dig", "x": w.sc.basin_plug.x, "y": w.sc.basin_plug.y })
	var c_fill := _find_cell(w, 0)
	if c_fill.x >= 0:
		w.apply_command({ "kind": "fill", "x": c_fill.x, "y": c_fill.y })
	var c_low := _find_cell(w, Sim.H_MIN + 3)
	if c_low.x >= 0:
		w.apply_command({ "kind": "lower", "x": c_low.x, "y": c_low.y })


## JSON 字符串往返（真实存档路径形态：数字变 float，int64 走字符串）。
func _json_rt(d: Dictionary):
	return JSON.parse_string(JSON.stringify(d))


func register(kit: TestKit) -> void:
	kit.module("save")

	kit.test("encode-fields", func():
		var w := World.new(Scenario.new(), 123)
		var d := Save.encode(w, 2)
		kit.eq(d["format"], 5, "格式版本")
		kit.eq(d["schema"], Canon.STATE_SCHEMA, "状态版本")
		kit.eq(d["sc_fp"], 2432575960, "剧本指纹 0x90fe29d8")
		kit.eq(d["meta"]["run"], 2, "meta.run")
		kit.eq(d["meta"]["tick"], 0, "meta.tick")
		kit.eq(d["meta"]["wave"], 0, "meta.wave 开局 0")
		kit.eq(d["state"]["seed"], "123", "seed 字符串编码")
		kit.eq(d["state"]["sc_seed"], "20261003", "sc_seed 字符串编码")
		var ins := Save.inspect(d)
		kit.eq(ins["ok"], true, "inspect 新档通过"))

	kit.test("roundtrip-fresh", func():
		var w := World.new(Scenario.new(), 20261004)
		var d: Dictionary = _json_rt(Save.encode(w, 1))
		var w2 := Save.decode(d)
		kit.ok(w2 != null, "读档非空")
		kit.eq(w2.fingerprint(), w.fingerprint(), "canonical 指纹往返一致")
		kit.eq(w2.tick_count, w.tick_count, "tick")
		kit.eq(w2.supply, w.supply, "供给")
		kit.eq(w2.seed, w.seed, "seed")
		kit.eq(w2.route_opened, w.route_opened, "开门态"))

	kit.test("roundtrip-mid", func():
		var w := World.new(Scenario.new(), 777)
		_scripted(w)
		_tick(w, 800)
		var d: Dictionary = _json_rt(Save.encode(w, 3))
		var w2 := Save.decode(d)
		kit.ok(w2 != null, "中期档读档非空")
		kit.eq(w2.fingerprint(), w.fingerprint(), "中期 canonical 一致")
		kit.eq(w2.supply, w.supply, "供给一致")
		kit.eq(w2.kills, w.kills, "击杀一致")
		kit.eq(w2.units.size(), w.units.size(), "单位数一致")
		kit.eq(w2.buildings.size(), w.buildings.size(), "建筑数一致")
		kit.eq(w2.route_opened, w.route_opened, "开门态一致")
		kit.eq(w2.hero["x"], w.hero["x"], "英雄 x"))

	kit.test("continuity", func():
		var w := World.new(Scenario.new(), 555)
		_scripted(w)
		_tick(w, 800)
		var w2 := Save.decode(_json_rt(Save.encode(w, 4)))
		kit.ok(w2 != null, "连续性档非空")
		_tick(w, 100)
		_tick(w2, 100)
		kit.eq(w2.fingerprint(), w.fingerprint(), "续跑 900 tick 指纹一致")
		_tick(w, 700)
		_tick(w2, 700)
		kit.eq(w2.fingerprint(), w.fingerprint(), "续跑 1600 tick 指纹一致")
		kit.eq(w2.kills, w.kills, "续跑击杀一致")
		kit.eq(w2.supply, w.supply, "续跑供给一致"))

	kit.test("rng-continuity", func():
		var w := World.new(Scenario.new(), 999)
		_tick(w, 500)
		var w2 := Save.decode(_json_rt(Save.encode(w, 1)))
		kit.ok(w2 != null, "rng 档非空")
		var seq1: Array = []
		var seq2: Array = []
		for _i in 5:
			seq1.append(w.rng.next_u64())
			seq2.append(w2.rng.next_u64())
		kit.seq(seq2, seq1, "rng 续序列一致（int64 无精度损失）"))

	kit.test("next-ids-and-spawn", func():
		var w := World.new(Scenario.new(), 42)
		_scripted(w)
		_tick(w, 300)
		var w2 := Save.decode(_json_rt(Save.encode(w, 1)))
		kit.ok(w2 != null, "id 档非空")
		kit.eq(w2.next_unit_id, w.next_unit_id, "next_unit_id 保留")
		kit.eq(w2.next_building_id, w.next_building_id, "next_building_id 保留")
		var cell := _find_cell(w, 0)
		if cell.x >= 0 and w2.grid.passable(cell.x, cell.y) and w2.cell_vacant(cell.x, cell.y):
			w.spawn_unit(cell.x, cell.y, 0, Sim.E_SWARM)
			w2.spawn_unit(cell.x, cell.y, 0, Sim.E_SWARM)
			var uid1: int = w.units[w.units.size() - 1]["id"]
			var uid2: int = w2.units[w2.units.size() - 1]["id"]
			kit.eq(uid2, uid1, "读档后新单位 id 与源世界一致"))

	kit.test("grid-hgt-preserved", func():
		var w := World.new(Scenario.new(), 8)
		_scripted(w)
		var w2 := Save.decode(_json_rt(Save.encode(w, 1)))
		kit.ok(w2 != null, "地形档非空")
		var cells_same := true
		var hgt_same := true
		for i in w.grid.w * w.grid.h:
			if w2.grid.cells[i] != w.grid.cells[i]:
				cells_same = false
				break
			if w2.grid.hgt[i] != w.grid.hgt[i]:
				hgt_same = false
				break
		kit.ok(cells_same, "cells 全量一致（含挖矿/开门）")
		kit.ok(hgt_same, "hgt 全量一致（含填高/挖低）"))

	kit.test("tamper-cell-rejected", func():
		var w := World.new(Scenario.new(), 3)
		var d := Save.encode(w, 1)
		var raw := Marshalls.base64_to_raw(d["state"]["cells"])
		raw[100] = (raw[100] + 1) % 3
		d["state"]["cells"] = Marshalls.raw_to_base64(raw)
		kit.ok(Save.decode(_json_rt(d)) == null, "改一格状态即拒绝"))

	kit.test("tamper-checksum-rejected", func():
		var w := World.new(Scenario.new(), 3)
		var d := Save.encode(w, 1)
		d["checksum"] = int(d["checksum"]) + 1
		kit.ok(Save.decode(_json_rt(d)) == null, "校验和被改即拒绝"))

	kit.test("negative-height-roundtrip", func():
		var w := World.new(Scenario.new(), 12)
		var c := _find_cell(w, 0)
		kit.ok(c.x >= 0, "找到平地格")
		if c.x >= 0:
			w.apply_command({ "kind": "lower", "x": c.x, "y": c.y })
			w.apply_command({ "kind": "lower", "x": c.x, "y": c.y })
			kit.eq(w.grid.get_h(c.x, c.y), -2, "两次挖低到 h-2")
		var w2 := Save.decode(_json_rt(Save.encode(w, 1)))
		kit.ok(w2 != null, "负高度档读档非空")
		kit.eq(w2.fingerprint(), w.fingerprint(), "负高度 canonical 一致")
		var same := true
		for i in w.grid.w * w.grid.h:
			if w2.grid.hgt[i] != w.grid.hgt[i]:
				same = false
				break
		kit.ok(same, "hgt 含负值逐格一致")
		if c.x >= 0:
			kit.eq(w2.grid.get_h(c.x, c.y), -2, "读回后负高度保真"))

	kit.test("climb-wait-roundtrip", func():
		var w := World.new(Scenario.new(), 13)
		var c := _find_cell(w, 0)
		if c.x >= 0:
			w.spawn_unit(c.x, c.y, 4, Sim.E_SWARM)
			w.units[0]["climb_wait"] = 5 # 白盒：制造后摇窗口
		var w2 := Save.decode(_json_rt(Save.encode(w, 1)))
		kit.ok(w2 != null, "后摇档读档非空")
		kit.eq(w2.units.size(), w.units.size(), "单位数一致")
		if w2.units.size() > 0:
			kit.eq(w2.units[0]["climb_wait"], 5, "climb_wait 往返保真")
		kit.eq(w2.fingerprint(), w.fingerprint(), "含 climb_wait 的 canonical 一致"))

	kit.test("reject-version-mismatch", func():
		var w := World.new(Scenario.new(), 3)
		var d1 := Save.encode(w, 1)
		d1["format"] = 99
		kit.ok(Save.decode(_json_rt(d1)) == null, "格式版本不符拒绝")
		var d0 := Save.encode(w, 1)
		d0["format"] = 2
		kit.ok(Save.decode(_json_rt(d0)) == null, "旧 format 2 拒载")
		var d2 := Save.encode(w, 1)
		d2["schema"] = 99
		kit.ok(Save.decode(_json_rt(d2)) == null, "状态版本不符拒绝")
		var d0s := Save.encode(w, 1)
		d0s["schema"] = 6
		kit.ok(Save.decode(_json_rt(d0s)) == null, "旧 schema 6 拒载")
		var d3 := Save.encode(w, 1)
		d3["sc_fp"] = 0
		kit.ok(Save.decode(_json_rt(d3)) == null, "剧本指纹不符拒绝"))

	kit.test("reject-truncated", func():
		var w := World.new(Scenario.new(), 3)
		var d1 := Save.encode(w, 1)
		d1["state"].erase("units")
		kit.ok(Save.decode(_json_rt(d1)) == null, "缺 units 拒绝")
		var d2 := Save.encode(w, 1)
		d2.erase("checksum")
		kit.ok(Save.decode(_json_rt(d2)) == null, "缺 checksum 拒绝")
		kit.ok(Save.decode("garbage") == null, "非字典拒绝")
		kit.ok(Save.decode(null) == null, "null 拒绝")
		kit.ok(Save.decode({}) == null, "空字典拒绝"))

	kit.test("inspect-bad", func():
		kit.eq(Save.inspect({})["ok"], false, "空字典 inspect 拒绝")
		var d := Save.encode(World.new(Scenario.new(), 1), 1)
		d["schema"] = 0
		kit.eq(Save.inspect(d)["ok"], false, "版本不符 inspect 拒绝"))
