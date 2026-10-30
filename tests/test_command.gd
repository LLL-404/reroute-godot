extends RefCounted

# 命令工厂单测：kind 字符串是存档/剧本/探针共用的协议，工厂字段结构也不能漂。


## 三字段命令的通用断言（kind/x/y）
func _xy(kit: TestKit, cmd: Dictionary, kind: String, x: int, y: int) -> void:
	kit.eq(cmd["kind"], kind, kind + " kind")
	kit.eq(cmd["x"], x, kind + " x")
	kit.eq(cmd["y"], y, kind + " y")


func register(kit: TestKit) -> void:
	kit.module("command")

	kit.test("kinds", func():
		kit.eq(Command.ALL_KINDS.size(), 12, "kind 总数（开局成长改造 +worker）")
		kit.eq(Command.DIG, "dig", "DIG")
		kit.eq(Command.WALL, "wall", "WALL")
		kit.eq(Command.TOWER, "tower", "TOWER")
		kit.eq(Command.BUILD, "build", "BUILD")
		kit.eq(Command.REMOVE, "remove", "REMOVE")
		kit.eq(Command.UNDO_BUILD, "undo_build", "UNDO_BUILD")
		kit.eq(Command.HERO, "hero", "HERO")
		kit.eq(Command.SHOCK, "shock", "SHOCK")
		kit.eq(Command.FILL, "fill", "FILL")
		kit.eq(Command.LOWER, "lower", "LOWER")
		kit.eq(Command.SPAWN, "spawn", "SPAWN")
		kit.eq(Command.WORKER, "worker", "WORKER"))

	kit.test("xy-factories", func():
		_xy(kit, Command.dig(3, 4), "dig", 3, 4)
		_xy(kit, Command.wall(5, 6), "wall", 5, 6)
		_xy(kit, Command.tower(7, 8), "tower", 7, 8)
		_xy(kit, Command.remove(9, 10), "remove", 9, 10)
		_xy(kit, Command.undo_build(11, 12), "undo_build", 11, 12)
		_xy(kit, Command.hero(13, 14), "hero", 13, 14)
		_xy(kit, Command.fill(15, 16), "fill", 15, 16)
		_xy(kit, Command.lower(17, 18), "lower", 17, 18)
		_xy(kit, Command.make("dig", 19, 20), "dig", 19, 20))

	kit.test("shock", func():
		var cmd := Command.shock()
		kit.eq(cmd.size(), 1, "shock 只有 kind 字段")
		kit.eq(cmd["kind"], "shock", "shock kind"))

	kit.test("worker", func():
		var cmd := Command.worker()
		kit.eq(cmd.size(), 1, "worker 只有 kind 字段")
		kit.eq(cmd["kind"], "worker", "worker kind"))

	kit.test("build", func():
		var cmd := Command.build(Sim.B_TOWER, 21, 22)
		kit.eq(cmd["kind"], "build", "build kind")
		kit.eq(cmd["bkind"], Sim.B_TOWER, "build bkind")
		kit.eq(cmd["x"], 21, "build x")
		kit.eq(cmd["y"], 22, "build y"))

	kit.test("spawn", func():
		var cmd := Command.spawn(23, 24, 7, Sim.E_BEHEMOTH)
		kit.eq(cmd["kind"], "spawn", "spawn kind")
		kit.eq(cmd["x"], 23, "spawn x")
		kit.eq(cmd["y"], 24, "spawn y")
		kit.eq(cmd["speed"], 7, "spawn speed")
		kit.eq(cmd["kind_id"], Sim.E_BEHEMOTH, "spawn kind_id")
		var d := Command.spawn(1, 2) # 缺省：速度取表值、兵种虫群
		kit.eq(d["speed"], 0, "spawn 默认 speed=0")
		kit.eq(d["kind_id"], Sim.E_SWARM, "spawn 默认 kind_id=虫群"))

	kit.test("all-kinds-registered", func():
		# 每个工厂产出的 kind 都必须在白名单里（防止以后加命令漏登记）
		var built := [
			Command.dig(0, 0), Command.wall(0, 0), Command.tower(0, 0),
			Command.build(Sim.B_WALL, 0, 0), Command.remove(0, 0),
			Command.undo_build(0, 0), Command.hero(0, 0), Command.shock(),
			Command.fill(0, 0), Command.lower(0, 0), Command.spawn(0, 0),
			Command.worker(),
		]
		for cmd in built:
			kit.ok(cmd["kind"] in Command.ALL_KINDS, "工厂 kind 已登记：" + String(cmd["kind"])))
