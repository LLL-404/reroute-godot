class_name StubScenario
extends Scenario

# 测试夹具：小尺寸全通行图 + 永火波次 + 无渗漏（对应 reroute/tests/test_world.lua 的 stub）。
# 通过继承保持 World._init(psc: Scenario) 的类型契约。
# opts：size / solid（Vector2i 列表）/ cover / height（[x,y,v] 三元组列表）/ waves /
#       end_tick / hard_cap_tick / trickle_every / wave_scale_pct / plug / spawn3
var opts: Dictionary


func _init(popts: Dictionary = {}) -> void:
	opts = popts
	var size: int = opts.get("size", 8)
	w = size
	h = size
	core = Vector2i(0, 0)
	hero_spawn = Vector2i(1, 1)
	spawns = [
		Vector2i(size - 2, size - 2),
		Vector2i(size - 1, size - 1),
		opts.get("spawn3", Vector2i(5, 5)),
	]
	basin_plug = opts.get("plug", Vector2i(-1, -1))
	waves = opts.get("waves", [[100000, 1, Sim.E_SWARM, 1]])
	end_tick = opts.get("end_tick", 100000)
	hard_cap_tick = opts.get("hard_cap_tick", 200000)
	trickle_every = opts.get("trickle_every", 0)
	wave_scale_pct = opts.get("wave_scale_pct", 100)
	ore_cells = []


func build_grid() -> Grid:
	var g := Grid.new(w, h)
	for c in opts.get("solid", []):
		g.set_cell(c.x, c.y, Grid.SOLID)
	for c in opts.get("cover", []):
		g.set_cell(c.x, c.y, Grid.COVER)
	for hh in opts.get("height", []):
		g.init_h(hh[0], hh[1], hh[2])
	return g


func is_ore(x: int, y: int) -> bool:
	return false
