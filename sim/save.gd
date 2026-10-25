class_name Save
extends RefCounted

# 存档编解码（纯逻辑、无文件 I/O）：world ↔ JSON 友好字典（D6-UI 槽位存档用）。
# 口径与铁律：
#   · int64 字段（seed / rng.state）编码为十进制字符串——JSON number 走 double 会丢精度；
#   · grid.cells / grid.hgt 用 base64（Marshalls.raw_to_base64），4096×2 字节紧凑可控；
#   · encode 内嵌「剧本指纹 + canonical 指纹（checksum）」；decode 全量校验，
#     重建世界后 canonical_bytes 指纹必须与存前逐位一致，否则返回 null（坏档/旧档拒载）；
#   · 派生态（pmap/hp/by_cell/field/siege/hero_field/rev）不进存储，读档后重建；
#   · 本模块零行为变化：不触碰既有模拟路径，probe_golden 指纹不受影响。

# v2（2026-10-16 世界生成）：state 增 sc_seed（布局种子），读档按种子重建校验；旧档自然拒载。
# v3（2026-10-23 挖坑/爬坡）：高度改 u8 偏移编码（支持 -2..5），单位行增 climb_wait（11 字段）。
# v4（2026-10-25 改道经济换轨）：单位行增 bare_dist（12 字段），旧档拒载。
# v5（2026-10-25 墙阶梯价）：建筑行增 paid（8 字段），旧档拒载。
# v6（2026-10-25 英雄强化）：单位行增 stun（13 字段），旧档拒载。
# v7（2026-10-25 采矿改形 C）：state 增 workers（7 字段行）与 ore（余量表），旧档拒载。
const FORMAT_VERSION := 7


## 世界 → 存档字典。run_index 供读档还原蓝图视觉（Blueprint.pick(run_index) 派生）。
## 存档前把摊销补场的欠账同步补完（仅派生态，不进 canonical）：否则「暂停瞬间存档」
## 落在补场窗口内时，原世界后续几 tick 的 dir_at 与读档即完成的场不一致，续跑会漂。
static func encode(world: World, run_index: int) -> Dictionary:
	if world.rebuilding or world.rebuilding_heavy or world.field_rev != world.grid.rev or world.field_heavy_rev != world.grid.rev:
		world._rebuild_field_sync()
	var cells := PackedByteArray(world.grid.cells)
	# 高度逐元素偏移编码（PackedByteArray(Array) 会把负值截断成 0..255 的非预期值）
	var hgt := PackedByteArray()
	for i in world.grid.w * world.grid.h:
		hgt.append(Grid.h_to_u8(world.grid.hgt[i]))
	var units: Array = []
	for u in world.units:
		units.append([
			u["id"], u["x"], u["y"], u["speed_ticks"], u["stuck_ticks"],
			u["kind"], u["hp"], u["atk_cd"], u["atk_target"], u["traveled"],
			u["climb_wait"], u["bare_dist"], u["stun"],
		])
	var builds: Array = []
	for b in world.buildings:
		builds.append([b["id"], b["kind"], b["x"], b["y"], b["hp"], b["build_left"], b["cooldown"], b["paid"]])
	var workers: Array = []
	for wk in world.workers:
		workers.append([wk["id"], wk["x"], wk["y"], wk["state"], wk["target"], wk["carrying"], wk["mine_cd"]])
	var ore: Array = []
	for i in world.sc.ore_cells.size():
		var oc: Vector2i = world.sc.ore_cells[i]
		ore.append(int(world.ore_left.get(world.grid.idx(oc.x, oc.y), 0)))
	var wave := 0
	for wv in world.sc.waves:
		if int(wv[0]) <= world.tick_count:
			wave += 1
	return {
		"format": FORMAT_VERSION,
		"schema": Canon.STATE_SCHEMA,
		"sc_fp": world.sc.fingerprint(Canon.new()),
		"checksum": world.fingerprint(),
		"meta": {
			"run": run_index,
			"tick": world.tick_count,
			"wave": wave,
			"time_s": world.tick_count / 20,
			"kills": world.kills,
			"seed": str(world.seed),
		},
		"state": {
			"seed": str(world.seed),
			"sc_seed": str(world.sc.seed),
			"rng": str(world.rng.state),
			"tick": world.tick_count,
			"supply": world.supply,
			"outcome": world.outcome,
			"route": 1 if world.route_opened else 0,
			"kills": world.kills,
			"convoy": world.convoy_earned,
			"lost": world.buildings_lost,
			"gw": world.grid.w,
			"gh": world.grid.h,
			"cells": Marshalls.raw_to_base64(cells),
			"hgt": Marshalls.raw_to_base64(hgt),
			"units": units,
			"buildings": builds,
			"next_unit": world.next_unit_id,
			"next_building": world.next_building_id,
			"hero": [world.hero["x"], world.hero["y"], world.hero["tx"], world.hero["ty"], world.hero["skill_cd"]],
			"workers": workers,
			"ore": ore,
		},
	}


## 存档字典 → 世界。任何校验失败（格式/版本/剧本/字段/校验和）一律返回 null，绝不半载。
static func decode(d) -> World:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	if int(d.get("format", -1)) != FORMAT_VERSION:
		return null
	if int(d.get("schema", -1)) != Canon.STATE_SCHEMA:
		return null
	if not (d.has("state") and d.has("checksum") and d.has("sc_fp")):
		return null
	var st: Dictionary = d["state"]
	for k in ["seed", "sc_seed", "rng", "tick", "supply", "outcome", "route", "kills", "convoy", "lost", "gw", "gh", "cells", "hgt", "units", "buildings", "next_unit", "next_building", "hero", "workers", "ore"]:
		if not st.has(k):
			return null
	var sc := Scenario.new(int(str(st["sc_seed"])))
	if sc.fingerprint(Canon.new()) != int(d["sc_fp"]):
		return null
	if int(st["gw"]) != sc.w or int(st["gh"]) != sc.h:
		return null
	var cells := Marshalls.base64_to_raw(str(st["cells"]))
	var hgt := Marshalls.base64_to_raw(str(st["hgt"]))
	if cells.size() != sc.w * sc.h or hgt.size() != sc.w * sc.h:
		return null

	var world := World.new(sc, int(str(st["seed"])))
	world.rng.restore(int(str(st["rng"])))
	world.tick_count = int(st["tick"])
	world.supply = int(st["supply"])
	world.outcome = int(st["outcome"])
	world.route_opened = int(st["route"]) != 0
	world.kills = int(st["kills"])
	world.convoy_earned = int(st["convoy"])
	world.buildings_lost = int(st["lost"])

	# 格子状态整写 + padded 镜像重建（pmap/hp 为派生热副本）
	for i in sc.w * sc.h:
		world.grid.cells[i] = cells[i]
		world.grid.hgt[i] = Grid.u8_to_h(hgt[i])
	for y in sc.h:
		for x in sc.w:
			var p := world.grid.pad_idx(x, y)
			world.grid.pmap[p] = 1 if world.grid.cells[y * sc.w + x] == Grid.OPEN else 0
			world.grid.hp[p] = world.grid.hgt[y * sc.w + x]
	world.grid.rev = 0
	world.grid.height_rev = 0

	world.units = []
	for row in st["units"]:
		if typeof(row) != TYPE_ARRAY or row.size() != 13:
			return null
		world.units.append({
			"id": int(row[0]), "x": int(row[1]), "y": int(row[2]),
			"speed_ticks": int(row[3]), "stuck_ticks": int(row[4]),
			"kind": int(row[5]), "hp": int(row[6]), "atk_cd": int(row[7]),
			"atk_target": int(row[8]), "traveled": int(row[9]),
			"climb_wait": int(row[10]), "bare_dist": int(row[11]), "stun": int(row[12]),
		})
	world.buildings = []
	world.by_cell = {}
	world.core = {}
	for row in st["buildings"]:
		if typeof(row) != TYPE_ARRAY or row.size() != 8:
			return null
		var b := {
			"id": int(row[0]), "kind": int(row[1]), "x": int(row[2]), "y": int(row[3]),
			"hp": int(row[4]), "build_left": int(row[5]), "cooldown": int(row[6]),
			"paid": int(row[7]),
		}
		world.buildings.append(b)
		world.by_cell[world.grid.idx(b["x"], b["y"])] = b
		if b["kind"] == Sim.B_CORE:
			world.core = b
	world.workers = []
	for row in st["workers"]:
		if typeof(row) != TYPE_ARRAY or row.size() != 7:
			return null
		world.workers.append({
			"id": int(row[0]), "x": int(row[1]), "y": int(row[2]),
			"state": int(row[3]), "target": int(row[4]),
			"carrying": int(row[5]), "mine_cd": int(row[6]),
			"field": null, "field_rev": -1, "field_goal": -1, "pick_rev": -1,
		})
	if world.workers.size() != Sim.WORKER_COUNT:
		return null
	world.ore_left = {}
	if st["ore"].size() != sc.ore_cells.size():
		return null
	for i in sc.ore_cells.size():
		var oc: Vector2i = sc.ore_cells[i]
		world.ore_left[world.grid.idx(oc.x, oc.y)] = int(st["ore"][i])
	if world.core.is_empty():
		return null
	world.next_unit_id = int(st["next_unit"])
	world.next_building_id = int(st["next_building"])
	var h = st["hero"]
	if typeof(h) != TYPE_ARRAY or h.size() != 5:
		return null
	world.hero = { "x": int(h[0]), "y": int(h[1]), "tx": int(h[2]), "ty": int(h[3]), "skill_cd": int(h[4]) }

	# 派生态复位：主场同步重建；围攻场 / 英雄场惰性（rev=-1 触发下次重建）
	world.rebuilding = false
	world.rebuilding_heavy = false
	world.siege = null
	world.siege_rev = -1
	world.siege_stamp = -1
	world.siege_heavy = null
	world.siege_heavy_rev = -1
	world.siege_heavy_stamp = -1
	world.hero_field_rev = -1
	world.hero_goal_tx = -1
	world.hero_goal_ty = -1
	world._rebuild_field_sync()

	# 终审：canonical 指纹逐位一致才算读档成功
	if world.fingerprint() != int(d["checksum"]):
		return null
	return world


## 浅校验（列表页用，不重建世界）：返回 { ok, reason, meta }。
static func inspect(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return { "ok": false, "reason": "存档内容不是字典", "meta": {} }
	if int(d.get("format", -1)) != FORMAT_VERSION:
		return { "ok": false, "reason": "存档格式版本不符", "meta": {} }
	if int(d.get("schema", -1)) != Canon.STATE_SCHEMA:
		return { "ok": false, "reason": "状态版本不符", "meta": {} }
	if not (d.has("meta") and d.has("state") and d.has("checksum") and d.has("sc_fp")):
		return { "ok": false, "reason": "存档字段缺失", "meta": {} }
	var sc_seed: int = Scenario.DEFAULT_SEED
	if typeof(d["state"]) == TYPE_DICTIONARY and d["state"].has("sc_seed"):
		sc_seed = int(str(d["state"]["sc_seed"]))
	if Scenario.new(sc_seed).fingerprint(Canon.new()) != int(d["sc_fp"]):
		return { "ok": false, "reason": "存档来自旧版本剧本", "meta": {} }
	return { "ok": true, "reason": "", "meta": d["meta"] }
