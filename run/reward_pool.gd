class_name RewardPool
extends RefCounted

# 肉鸽奖励池（竖切 8 张：四种载体各 2 张）。
# 口径见 docs/ROGUELIKE-SPEC.md §5：统一一个池子、三选一、稀有度加权。
# 竖切阶段先做等权抽取（池小，加权没有意义），稀有度字段留作后续扩展。

const KIND_TOWER := "tower"
const KIND_RELIC := "relic"
const KIND_TALENT := "talent"
const KIND_TERRAIN := "terrain"

const CARDS := [
	{ "id": "t_frost", "kind": "tower", "name": "冰霜塔", "desc": "解锁冰霜塔：命中减速 50%，持续 2 秒", "bkind": 4, "rarity": "common" },
	{ "id": "t_lava", "kind": "tower", "name": "熔岩井", "desc": "解锁熔岩井：对半径 4 内全体造成伤害", "bkind": 8, "rarity": "rare" },
	{ "id": "r_convoy", "kind": "relic", "name": "长途税", "desc": "绕行赏金翻倍（路程折算 3 → 2）", "rarity": "legend" },
	{ "id": "r_leyline", "kind": "relic", "name": "地脉", "desc": "每层开始额外 +80 供给", "rarity": "common" },
	{ "id": "h_wide", "kind": "talent", "name": "广域震荡", "desc": "英雄震荡波半径 3 → 5", "rarity": "rare" },
	{ "id": "h_cd", "kind": "talent", "name": "短冷却", "desc": "英雄震荡波冷却 400 → 250 tick", "rarity": "rare" },
	{ "id": "g_fault", "kind": "terrain", "name": "断层", "desc": "手牌：3×3 区域整体升高 2 级", "rarity": "common" },
	{ "id": "g_pit", "kind": "terrain", "name": "陷坑", "desc": "手牌：3×3 区域整体降低 2 级", "rarity": "common" },
]

# 刷新手牌价（同一次间歇内递增，上限 4 次）
const REFRESH_COSTS := [30, 50, 70, 90]


## 按 id 取卡定义（不存在返回空字典）
static func by_id(cid: String) -> Dictionary:
	for c in CARDS:
		if String(c["id"]) == cid:
			return c
	return {}


## 抽 n 张互不重复的卡；exclude = 已持有/已解锁的 id（地形牌允许重复，调用方不排除即可）。
static func roll(rng: Rng, n: int, exclude: Array) -> Array:
	var pool: Array = []
	for c in CARDS:
		if exclude.has(String(c["id"])):
			continue
		pool.append(c)
	var out: Array = []
	var guard: int = 0
	while out.size() < n and guard < 64:
		guard += 1
		if pool.is_empty():
			break
		var i: int = rng.next_int(pool.size())
		out.append(pool[i])
		pool.remove_at(i)
	return out
