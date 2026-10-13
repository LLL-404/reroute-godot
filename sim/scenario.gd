class_name Scenario
extends RefCounted

# 数值表 + 48² 手搓夹具地图 + 压缩波次表。照搬 reroute/scripts/sim/scenario.lua：
# 核心在北岸中上；岩脊横贯 y=30..32，两个咽喉口；南岸双出怪口；
# 西南盆地密闭岩环（插口是唯一覆盖格，内部藏矿）= 开门陷阱；中场安全矿。
# 波次：细流教学开局 → 5 波递进 → 末波双口开闸（dam break）。20Hz；终局 5'20"。

var w: int
var h: int
var core: Vector2i
var hero_spawn: Vector2i
var spawns: Array # 出怪口下标 1 基：1=西咽喉外、2=东咽喉外、3=盆地内（玩家自己挖开插口才生效）
var basin_plug: Vector2i
var ore_cells: Array
var waves: Array # 条目 = [tick, 出怪口(1基), 敌型, 数量]
var end_tick: int
var hard_cap_tick: int
var trickle_every: int
var wave_scale_pct: int


func _init() -> void:
	w = 48
	h = 48
	core = Vector2i(24, 6)
	hero_spawn = Vector2i(24, 8) # 核心门前两格（build_grid 强制 OPEN）
	spawns = [Vector2i(12, 40), Vector2i(36, 40), Vector2i(5, 41)]
	basin_plug = Vector2i(5, 37)
	ore_cells = []
	# 盆地内矿（诱饵：挖插口才够得着）
	for x in range(4, 7):
		for y in range(40, 44):
			ore_cells.append(Vector2i(x, y))
	# 中场矿（安全保底，北岸）
	for x in range(22, 27):
		ore_cells.append(Vector2i(x, 20))
	# 同波多条目错开 15~30 tick：怪列成"流"而不是团（总量 ~220 只）
	waves = [
		[60, 1, Sim.E_SWARM, 1],
		[160, 1, Sim.E_SWARM, 1],
		[260, 1, Sim.E_SWARM, 1],
		[360, 1, Sim.E_SWARM, 1],
		[800, 1, Sim.E_SWARM, 10],
		[830, 2, Sim.E_SWARM, 6],
		[1700, 1, Sim.E_SWARM, 14],
		[1700, 2, Sim.E_SWARM, 10],
		[1850, 2, Sim.E_BEHEMOTH, 1],
		[2700, 1, Sim.E_SWARM, 14],
		[2700, 2, Sim.E_SWARM, 12],
		[2850, 1, Sim.E_SWARM, 4],
		[2850, 2, Sim.E_BEHEMOTH, 2],
		[3700, 1, Sim.E_SWARM, 14],
		[3700, 2, Sim.E_SWARM, 14],
		[3850, 1, Sim.E_SWARM, 10],
		[3850, 2, Sim.E_BEHEMOTH, 3],
		[4700, 1, Sim.E_SWARM, 14],
		[4715, 1, Sim.E_SWARM, 14],
		[4730, 1, Sim.E_SWARM, 12],
		[4700, 2, Sim.E_SWARM, 12],
		[4715, 2, Sim.E_SWARM, 12],
		[4730, 2, Sim.E_SWARM, 10],
		[4860, 1, Sim.E_BEHEMOTH, 4],
		[4860, 2, Sim.E_BEHEMOTH, 4],
	]
	end_tick = 6400
	hard_cap_tick = 8800
	trickle_every = 300 # 开门后每 300 tick 从盆地渗 2 只虫群（开门有代价，但可守）
	wave_scale_pct = 100


static func _is_choke(x: int) -> bool:
	return (x >= 10 and x <= 12) or (x >= 35 and x <= 37)


## 高度夹具：北岸台地 h1；核心山头 h3 + 南向两级台阶（h2）；双咽喉谷口 y30 爬出 h1；
## 南岸低地/咽喉谷道/盆地坑 h0。与岩脊 SOLID 叠加成"峡谷+高原"。
func height_at(x: int, y: int) -> int:
	if y <= 9 and x >= 21 and x <= 27:
		return 3
	if y <= 12 and x >= 22 and x <= 26:
		return 2
	if y <= 29:
		return 1
	if y == 30 and Scenario._is_choke(x):
		return 1
	return 0


static func _is_ridge(x: int, y: int) -> bool:
	return y >= 30 and y <= 32 and x >= 1 and x <= 46


## 初始地形：三态一次性写入（命令层之后才登场）。
func build_grid() -> Grid:
	var g := Grid.new(w, h)
	var ore := {}
	for o in ore_cells:
		ore[str(o.x) + "," + str(o.y)] = true
	for y in h:
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				g.set_cell(x, y, Grid.SOLID)
			elif ore.has(str(x) + "," + str(y)):
				g.set_cell(x, y, Grid.COVER) # 矿格先于岩脊判定，否则会被写成不可挖的实心
			elif Scenario._is_ridge(x, y) and not Scenario._is_choke(x):
				g.set_cell(x, y, Grid.SOLID)
			elif x >= 2 and x <= 9 and y >= 37 and y <= 45:
				# 盆地：密闭岩环（只有插口是覆盖层），内部空腔藏矿与第三出怪口
				var ring := x == 2 or x == 9 or y == 37 or y == 45
				if ring:
					g.set_cell(x, y, Grid.COVER if (x == basin_plug.x and y == basin_plug.y) else Grid.SOLID)
			elif y > 12 and y < 26 and x % 9 == 4 and y % 11 == 6:
				g.set_cell(x, y, Grid.COVER) # 稀疏表土纹理：可挖但不给矿，不遮挡咽喉与建造走廊
	g.set_cell(core.x, core.y, Grid.SOLID) # 核心占地
	g.set_cell(hero_spawn.x, hero_spawn.y, Grid.OPEN) # 英雄落位格恒通行
	for i in range(0, 2): # 主出怪口保持通行（盆地口不在此列；Lua 版 for i=1,2 的 0 基对应）
		g.set_cell(spawns[i].x, spawns[i].y, Grid.OPEN)
	for y in h: # 高度夹具（建图期写入，不参与 rev 计数口径）
		for x in w:
			g.init_h(x, y, height_at(x, y))
	return g


## 该格是否为矿格（静态数据，不进状态）。
func is_ore(x: int, y: int) -> bool:
	for o in ore_cells:
		if o.x == x and o.y == y:
			return true
	return false


## 剧本指纹：静态数据的 FNV-1a（换剧本必须换 baseline 的守门数据）。
## 字段定序与 Lua 版逐行对齐；引擎侧现值 scenario_fp=0x12715062（可对拍）。
func fingerprint(canon: Canon) -> int:
	var b := canon.buffer()
	b.put_i32(w)
	b.put_i32(h)
	b.put_i32(core.x)
	b.put_i32(core.y)
	b.put_i32(hero_spawn.x)
	b.put_i32(hero_spawn.y)
	b.put_u32(spawns.size())
	for s in spawns:
		b.put_i32(s.x)
		b.put_i32(s.y)
	b.put_i32(basin_plug.x)
	b.put_i32(basin_plug.y)
	b.put_i32(end_tick)
	b.put_i32(hard_cap_tick)
	b.put_i32(trickle_every)
	b.put_i32(wave_scale_pct)
	for y in h: # 高度夹具入指纹（换地形必须换基线）
		for x in w:
			b.put_u8(height_at(x, y))
	b.put_u32(ore_cells.size())
	for o in ore_cells:
		b.put_i32(o.x)
		b.put_i32(o.y)
	b.put_u32(waves.size())
	for wv in waves:
		b.put_i32(wv[0])
		b.put_i32(wv[1])
		b.put_i32(wv[2])
		b.put_i32(wv[3])
	return b.fingerprint()
