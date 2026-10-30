class_name Command
extends RefCounted

# 模拟层命令的唯一「字典表」：kind 常量 + 静态工厂。
# 背景：World.apply_command 是全游戏唯一能改动模拟状态的入口，但命令一直是手写字典。
#   拼错 kind 不报错（未知命令按空操作处理），加新命令也无处核对。这里把 11 个 kind
#   和字段结构集中到一处，生产代码一律经工厂构造；工厂只是拼字典，无状态、无浮点。
# 纪律：kind 字符串值是存档/剧本/探针共用的协议，一个字都不能改（verify 的剧本数组
#   直接存 kind 原文，黄金指纹也依赖既有行为）。
#   本文件不引用任何 game/ 下的东西（sim ← game 单向依赖）。

const DIG := "dig"
const WALL := "wall"
const TOWER := "tower"
const BUILD := "build"
const REMOVE := "remove"
const UNDO_BUILD := "undo_build"
const HERO := "hero"
const SHOCK := "shock"
const FILL := "fill"
const LOWER := "lower"
const SPAWN := "spawn"
const WORKER := "worker" # 2026-10-28 开局成长改造追加；既有 kind 值是存档/剧本协议，一字不动

const ALL_KINDS := [
	DIG, WALL, TOWER, BUILD, REMOVE, UNDO_BUILD,
	HERO, SHOCK, FILL, LOWER, SPAWN, WORKER,
]


## 通用构造：给剧本驱动的动态 kind（verify 的 c[1]）用；开发期替你把拼写错误咬出来。
static func make(kind: String, x: int, y: int) -> Dictionary:
	assert(kind in ALL_KINDS)
	return { "kind": kind, "x": x, "y": y }


## 挖开覆盖格（矿/暗门）；能否真挖由模拟层守卫判定
static func dig(x: int, y: int) -> Dictionary:
	return { "kind": DIG, "x": x, "y": y }


## 放墙（走阶梯价，拒建由模拟层判定）
static func wall(x: int, y: int) -> Dictionary:
	return { "kind": WALL, "x": x, "y": y }


## 放经典塔（成本见 Sim.BUILDINGS）
static func tower(x: int, y: int) -> Dictionary:
	return { "kind": TOWER, "x": x, "y": y }


## 肉鸽模式按显式塔种建造（8 种塔；经典模式不发此命令）
static func build(bkind: int, x: int, y: int) -> Dictionary:
	return { "kind": BUILD, "bkind": bkind, "x": x, "y": y }


## 拆除建筑（退款按实付造价）
static func remove(x: int, y: int) -> Dictionary:
	return { "kind": REMOVE, "x": x, "y": y }


## 撤销刚落下的建筑（5s 窗口，全额退款）
static func undo_build(x: int, y: int) -> Dictionary:
	return { "kind": UNDO_BUILD, "x": x, "y": y }


## 点地移动英雄
static func hero(x: int, y: int) -> Dictionary:
	return { "kind": HERO, "x": x, "y": y }


## 英雄震荡波（冷却/终局守卫在模拟层）
static func shock() -> Dictionary:
	return { "kind": SHOCK }


## 填高一级（扣供给，上限见 Sim.H_MAX）
static func fill(x: int, y: int) -> Dictionary:
	return { "kind": FILL, "x": x, "y": y }


## 挖低一级（扣供给，下限见 Sim.H_MIN）
static func lower(x: int, y: int) -> Dictionary:
	return { "kind": LOWER, "x": x, "y": y }


## 生成敌人（波次导演与测试用；speed=0 表示取兵种表默认值）
static func spawn(x: int, y: int, speed_ticks: int = 0, kind_id: int = Sim.E_SWARM) -> Dictionary:
	return { "kind": SPAWN, "x": x, "y": y, "speed": speed_ticks, "kind_id": kind_id }


## 购买一名矿工（扣 WORKER_COST，出生核心邻格；上限/缺钱守卫在模拟层）
static func worker() -> Dictionary:
	return { "kind": WORKER }
