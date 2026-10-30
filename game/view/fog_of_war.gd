extends RefCounted

# 战争迷雾（开局成长改造 2026-10-28）：纯视图层状态——不进 sim 状态/指纹/存档 schema。
# 经典两层口径：未探索=近黑（地形矿藏都看不见）；已探索但不在视野内=半暗；
# 敌人只在视野圈内现身（view_entities 按位图藏节点）；未探索不可建/挖（main 入口拦）。
# 探索记忆持久：塔拆了区域仍算探索过（位图只增不减）。
# 视野源与半径（六边距离圆）：核心 12 / 塔 9 / 矿工 5 / 英雄 10——英雄探路主力。
# 确定性纪律：位图由实体位置确定性派生，回放可从 tick0 重推导；
# 探针 fog=false 时全部查询恒真、遮罩不出图（截图口径，照 shake_on 先例）。

const VISION_CORE := 12
const VISION_TOWER := 9
const VISION_WORKER := 5
const VISION_HERO := 10

var enabled := true
var n := 0 # 方阵边长；0 = 未初始化（reset 前）
var explored := PackedByteArray() # 位图：n×n bit，探索记忆（只增不减，可持久化）
var visible := PackedByteArray() # 位图：n×n bit，当帧视野并集（每帧重算）
var dirty := false # 位图自上次出图后有变化（遮罩层重建用；terrain.rebuild_fog 消费后清）

var _visible_prev := PackedByteArray() # 上一帧视野快照（dirty 判定）


## 新局/换图重置：清空探索记忆（首帧 update 会揭开核心+英雄周边）
func reset(pn: int) -> void:
	n = pn
	var bytes: int = (pn * pn + 7) >> 3
	explored.resize(bytes)
	visible.resize(bytes)
	_visible_prev.resize(bytes)
	explored.fill(0)
	visible.fill(0)
	_visible_prev.fill(0)
	dirty = true


## 每帧更新：visible = 全部视野源并集，同时把揭到的格写进 explored；有变化置 dirty。
## 只读 world（视图纪律：绝不回写）。
func update(world: World) -> void:
	if n <= 0:
		return
	visible.fill(0)
	_reveal_circle(world.sc.core.x, world.sc.core.y, VISION_CORE)
	for b in world.buildings:
		if int(b["kind"]) == Sim.B_TOWER and int(b["hp"]) > 0:
			_reveal_circle(int(b["x"]), int(b["y"]), VISION_TOWER)
	for wk in world.workers:
		_reveal_circle(int(wk["x"]), int(wk["y"]), VISION_WORKER)
	_reveal_circle(int(world.hero["x"]), int(world.hero["y"]), VISION_HERO)
	if visible != _visible_prev:
		_visible_prev = visible.duplicate()
		dirty = true


## 揭开以 (cx,cy) 为心、六边距离 ≤ r 的圆（视野形状与六边格一致）。
## 行裁剪不能取 r−|dy|：odd-r 奇偶行错位下会漏角格（逐格精判，方框最大 (2r+1)² 量级）。
func _reveal_circle(cx: int, cy: int, r: int) -> void:
	var lo_y: int = maxi(0, cy - r)
	var hi_y: int = mini(n - 1, cy + r)
	var lo_x: int = maxi(0, cx - r)
	var hi_x: int = mini(n - 1, cx + r)
	for y in range(lo_y, hi_y + 1):
		for x in range(lo_x, hi_x + 1):
			if Grid.hex_dist(cx, cy, x, y) > r:
				continue
			var idx := y * n + x
			var byte := idx >> 3
			var bit := 1 << (idx & 7)
			if (explored[byte] & bit) == 0:
				explored[byte] = explored[byte] | bit
				dirty = true
			visible[byte] = visible[byte] | bit


## 该格是否已探索（迷雾关/未初始化 = 恒真，全部拦截与遮罩自动失效）
func is_explored(x: int, y: int) -> bool:
	if not enabled or n <= 0:
		return true
	var idx := y * n + x
	return (explored[idx >> 3] & (1 << (idx & 7))) != 0


## 该格当前是否在视野内
func is_visible(x: int, y: int) -> bool:
	if not enabled or n <= 0:
		return true
	var idx := y * n + x
	return (visible[idx >> 3] & (1 << (idx & 7))) != 0


## 存档快照（save_io 槽位 JSON 用；原字节，调用方自行 base64）
func snapshot() -> PackedByteArray:
	return explored.duplicate()


## 读档恢复探索记忆；尺寸不符返回 false（调用方回退为按现存实体重推导）
func restore(bytes: PackedByteArray) -> bool:
	if n <= 0 or bytes.size() != (n * n + 7) >> 3:
		return false
	explored = bytes.duplicate()
	dirty = true
	return true
