class_name Sim
extends RefCounted

# 数值表：照搬 warden/Warden.Core/Defs.cs 与 SPEC-slice1 §4（合同镜像），
# 按 GAMEJAM-2026-PLAN D6–D9 裁定收缩：128²→64²（2026-10-16 世界重做）、敌 3→2 原型、一局 4–6 分钟。
const TICK_HZ := 20
const ORE_YIELD := 25 # 挖开一个矿格 +供给
const START_SUPPLY := 300

# 高度层（单向崖）：-2..5 整数（可挖出两层坑）；单位边可走 ⇔ 爬升 ≤ 兵种 climb_max
# （下崖任意）；英雄无视高度。
const H_MIN := -2
const H_MAX := 5
const FILL_COST := 15 # 填高 +1
const LOWER_COST := 10 # 挖低 −1

# 爬坡：每爬升一级，流场边权额外 +CLIMB_COST；跨过爬坡边后额外等待若干 tick。
const CLIMB_COST := 10
const CLIMB_EXTRA_TICKS := 2

# 建筑：墙 / 箭塔 / 核心（工坊砍掉：不做经济运营）
const BUILDINGS := [
	{ "name": "wall", "cost": 10, "hp": 120, "build_ticks": 0, "range": 0, "damage": 0, "cooldown": 0, "shoots": false },
	{ "name": "tower", "cost": 60, "hp": 200, "build_ticks": 120, "range": 12, "damage": 16, "cooldown": 20, "shoots": true },
	{ "name": "core", "cost": 0, "hp": 1200, "build_ticks": 0, "range": 0, "damage": 0, "cooldown": 0, "shoots": false },
]
const B_WALL := 1
const B_TOWER := 2
const B_CORE := 3

# 敌军 2 原型：啃墙的（蛮兽）+ 跑快的（虫群）。speed = 走一格要几 tick（越大越慢）。
const ENEMIES := [
	{ "name": "swarm", "hp": 30, "speed_ticks": 4, "damage": 8, "cooldown": 12, "reward": 3, "climb_max": 2 },
	{ "name": "behemoth", "hp": 240, "speed_ticks": 8, "damage": 60, "cooldown": 24, "reward": 14, "climb_max": 1 },
]
const E_SWARM := 1
const E_BEHEMOTH := 2

# 改道经济：击杀赏金 = reward + (traveled >> CONVOY_SHIFT)。
const CONVOY_SHIFT := 3

# 英雄（切片 1 最小形态：点地移动 + 单技能震荡波）。
const HERO := { "speed_ticks": 3, "skill_radius": 3, "skill_cooldown": 400 }
