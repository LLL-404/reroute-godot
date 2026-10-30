class_name Sim
extends RefCounted

# 数值表：照搬 warden/Warden.Core/Defs.cs 与 SPEC-slice1 §4（合同镜像），
# 按 GAMEJAM-2026-PLAN D6–D9 裁定收缩：128²→64²（2026-10-16 世界重做）、敌 3→2 原型、一局 4–6 分钟。
const TICK_HZ := 20
# 采矿改形 C（2026-10-25）：挖开矿格不再即时入账——矿由工人沿流场搬运回核心结算。
# 单格储量 ORE_STORE，工人每 ORE_RATE_TICKS 采 ORE_RATE 进随身载量，满 WORKER_LOAD 回核心入账；
# 经济上限 17 格 × 40 = 680（原即时口径 425）。
const ORE_STORE := 40
const ORE_RATE := 5
const ORE_RATE_TICKS := 20
# 开局成长改造（2026-10-28）：工人改购买制（原 WORKER_COUNT=2 免费开局退役）。
# 开局 60 = 2 矿工（WORKER_COST×2）= 1 塔（塔 60 不变）——开局的主分支选择。
const WORKER_CAP := 6 # 矿工购买上限（工人性能/画面密度软顶；矿总量 680 天然封顶收入）
const WORKER_COST := 30
const WORKER_SPEED_TICKS := 3
const WORKER_LOAD := 20
const START_SUPPLY := 60

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

# 墙阶梯价（2026-10-25 刀②）：存活墙数 < WALL_TIER_CHEAP 面单价 WALL_TIER_CHEAP_COST，
# 之后恢复基准价（BUILDINGS.cost）；达 WALL_TIER_CAP 后不可再建。
# 早期封墙半价买容错（配合 effdetour 让运河起手成立），无限海墙被硬顶住。
const WALL_TIER_CHEAP := 20
const WALL_TIER_CHEAP_COST := 5
const WALL_TIER_CAP := 35

# 敌军 2 原型：啃墙的（蛮兽）+ 跑快的（虫群）。speed = 走一格要几 tick（越大越慢）。
const ENEMIES := [
	{ "name": "swarm", "hp": 30, "speed_ticks": 4, "damage": 8, "cooldown": 12, "reward": 3, "climb_max": 2 },
	{ "name": "behemoth", "hp": 240, "speed_ticks": 8, "damage": 60, "cooldown": 24, "reward": 14, "climb_max": 1 },
]
const E_SWARM := 1
const E_BEHEMOTH := 2

# 工人状态机（采矿改形 C）：TO_MINE 走单目标场去矿格 → MINING 站定开采 →
# TO_CORE 沿主战场回核心入账。工人是独立实体（同英雄：不进 units/buildings）。
const W_TO_MINE := 0
const W_MINING := 1
const W_TO_CORE := 2

# 改道经济（2026-10-25 换轨）：击杀赏金 = reward + 有效绕行折算。
# 有效绕行 = traveled + 死位主场剩余距离 − 出生格裸图基线（任一端不可达记 0），
# 折算后加成封顶 2×基础赏金——堵死拿不到绕行钱，改道多走的路才给钱。
const CONVOY_SHIFT := 3
const BOUNTY_CAP_MULT := 2

# 英雄（切片 1 最小形态：点地移动 + 单技能震荡波）。
# 2026-10-25 刀④强化：半径 3→4、冷却 400→300、击退 1→2 格、新增眩晕（完全冻结）——
# 「易空放」主因是缺范围指示（表现层修），数值强化让罩到就有真实回报。
const HERO := { "speed_ticks": 3, "skill_radius": 4, "skill_cooldown": 300 }
const STUN_TICKS := 40 # 震荡波命中眩晕：不动/不啃/atk_cd 不走（完全冻结）
