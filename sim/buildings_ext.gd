class_name RunDefs
extends RefCounted

# 肉鸽模式建筑扩展表（8 种塔 + 墙 + 核心）。
# 用途：World.btab 指向本表，bdef(kind) 按 1 基下标取定义。
# 下标约定（与经典表兼容，核心恒为 3）：
#   1 wall / 2 arrow(=经典 tower) / 3 core / 4 frost / 5 ballista
#   6 spike / 7 repeater / 8 lava / 9 tesla / 10 totem
# 注：behavior 字段只有肉鸽表带，经典表没有 ⇒ World.towers_and_build 的
# 扩展分支在经典模式下永不被调用。

const B_WALL := 1
const B_ARROW := 2
const B_CORE := 3
const B_FROST := 4
const B_BALLISTA := 5
const B_SPIKE := 6
const B_REPEATER := 7
const B_LAVA := 8
const B_TESLA := 9
const B_TOTEM := 10

const TOWERS := [
	{ "name": "wall", "cost": 10, "hp": 120, "build_ticks": 0, "range": 0, "damage": 0, "cooldown": 0, "shoots": false },
	{ "name": "arrow", "cost": 60, "hp": 200, "build_ticks": 120, "range": 12, "damage": 16, "cooldown": 20, "shoots": true },
	{ "name": "core", "cost": 0, "hp": 1200, "build_ticks": 0, "range": 0, "damage": 0, "cooldown": 0, "shoots": false },
	{ "name": "frost", "cost": 70, "hp": 160, "build_ticks": 120, "range": 10, "damage": 4, "cooldown": 24, "shoots": true, "behavior": "slow", "slow_ticks": 40 },
	{ "name": "ballista", "cost": 90, "hp": 180, "build_ticks": 160, "range": 18, "damage": 45, "cooldown": 45, "shoots": true },
	{ "name": "spike", "cost": 40, "hp": 240, "build_ticks": 0, "range": 0, "damage": 12, "cooldown": 12, "shoots": false },
	{ "name": "repeater", "cost": 80, "hp": 150, "build_ticks": 140, "range": 14, "damage": 8, "cooldown": 8, "shoots": true, "behavior": "pierce", "pierce_n": 3 },
	{ "name": "lava", "cost": 100, "hp": 220, "build_ticks": 180, "range": 4, "damage": 22, "cooldown": 30, "shoots": true, "behavior": "aoe" },
	{ "name": "tesla", "cost": 110, "hp": 170, "build_ticks": 160, "range": 11, "damage": 14, "cooldown": 26, "shoots": true, "behavior": "pierce", "pierce_n": 2 },
	{ "name": "totem", "cost": 100, "hp": 260, "build_ticks": 140, "range": 5, "damage": 0, "cooldown": 0, "shoots": false },
]
