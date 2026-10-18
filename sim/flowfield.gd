class_name FlowField
extends RefCounted

# 流场：多目标 Dijkstra（2026-10-17 六边形化：六向等权 10，无斜向贴角问题）+ 距离桶队列（Dial 变体）。
# 拓扑 = 尖顶六边形 odd-r（见 grid.gd）；方向序（全项目唯一）：0E 1NE 2NW 3W 4SW 5SE。
# 固定侦察纪律：
#   · 六边网格边永远共享整条边，无需贴角禁穿判定（方形时代的 side_a/side_b 规则随拓扑废止）；
#   · DirAt 平手取方向序号最小（严格 < 判定）；
#   · 纯整数运算，无浮点无 libm。
# 距离上界（可证明）：最短路径绝不重复经过任一格（边权恒正）→ 至多 w*h−1 步 ×10。
const STRAIGHT := 10
const INT64_MAX := 9223372036854775807

var grid: Grid
var ignore_h: bool
var dist: Array # padded 距离，-1 = 不可达（未写 = null 视同不可达）
var settled: Array
var max_d: int
var head: Array # 距离桶：head[d] 槽链表头，-1 = 空
var slot_cell: Array
var slot_next: Array
var off_e: Array # 偶行邻居 padded 增量（6 向，构造期算好）
var off_o: Array # 奇行邻居 padded 增量
var par: Array # padded 下标 → 内部行奇偶（热路径选增量表）
var cur: int
var max_bucket: int
var pending: int
var slots: int
var pops: int


## 初始化：padded 距离/定稿表 + 6 向邻居增量（按行奇偶）+ 桶头；begin 前 dist 全 -1
func _init(pgrid: Grid, pignore_h: bool = false) -> void:
	grid = pgrid
	ignore_h = pignore_h
	var stride: int = grid.stride
	var pad_n: int = stride * (grid.h + 2)
	dist = []
	settled = []
	par = []
	for i in pad_n:
		dist.append(-1)
		settled.append(0)
		par.append((Lua64.idiv(i, stride) - 1) & 1)
	max_d = STRAIGHT * grid.w * grid.h
	head = []
	for d in max_d + 1:
		head.append(-1)
	slot_cell = []
	slot_next = []
	off_e = []
	off_o = []
	for k in 6:
		off_e.append(Grid.DY[k] * stride + Grid.DX[0][k])
		off_o.append(Grid.DY[k] * stride + Grid.DX[1][k])
	cur = -1
	max_bucket = 0
	pending = 0
	slots = 0
	pops = 0


## 多目标置零入桶。目标格本身可为不可通行格（核心/建筑占地），扩张仍受通行规则约束。
func begin(goals: Array) -> void:
	for i in dist.size():
		dist[i] = -1
	for i in settled.size():
		settled[i] = 0
	for d in max_d + 1:
		head[d] = -1
	cur = -1
	max_bucket = 0
	pending = 0
	for g in goals:
		var x: int = g.x
		var y: int = g.y
		if grid.inb(x, y):
			var p := grid.pad_idx(x, y)
			if dist[p] != 0:
				dist[p] = 0
				push(0, p)


## 是否收敛：待处理桶项清空（校验/探针的循环终止判据）
func done() -> bool:
	return pending == 0


## 消化至多 budget 次出桶（含陈旧项跳过）。最终结果与预算切分方式无关。
func step(budget: int) -> void:
	var work := 0
	while pending > 0 and work < budget:
		if cur < 0 or head[cur] < 0:
			cur = next_nonempty_bucket(cur + 1)
			if cur < 0:
				break # 保险：pending 与桶失同步（正常不可达）
		var slot: int = head[cur]
		head[cur] = slot_next[slot]
		pending -= 1
		work += 1
		pops += 1
		var cell: int = slot_cell[slot]
		if settled[cell] == 0:
			relax(cell, cur) # 陈旧项：首次出桶已定稿，跳过


## 定稿 p 并六向扩张：实走边 p→nb 爬 ≤1、下崖任意（单向崖）；ignore_h 免高度检查
func relax(p: int, d: int) -> void:
	settled[p] = 1
	var pmap := grid.pmap
	var hp := grid.hp
	var ignore := ignore_h
	var off := off_o if par[p] == 1 else off_e
	for k in 6:
		var nb: int = p + off[k]
		if pmap[nb] == 1:
			# 扩张边 = nb→p（nb 处单位跨入 p）：爬 ≤1、下崖任意（单向崖）
			if ignore or (hp[p] - hp[nb] <= 1):
				if settled[nb] == 0:
					var nd := d + STRAIGHT
					if dist[nb] == -1 or nd < dist[nb]:
						dist[nb] = nd
						push(nd, nb)


## 入桶（距离 d 的链表头插，惰性删除）；超理论上界丢弃 = 宁可得不到这条路
func push(d: int, cell: int) -> void:
	if d > max_d:
		return # 超出理论距离上界 = 编程错误，宁可得不到这条路
	var s := slots
	slots += 1
	slot_cell.append(cell)
	slot_next.append(head[d])
	head[d] = s
	if d > max_bucket:
		max_bucket = d
	pending += 1


## 找 ≥from 的下一个非空桶（无则 -1）
func next_nonempty_bucket(from: int) -> int:
	if from < 0:
		from = 0
	for i in range(from, max_bucket + 1):
		if head[i] >= 0:
			return i
	return -1


## 查询距离（界外 / 未达 = -1）
func dist_at(x: int, y: int) -> int:
	if not grid.inb(x, y):
		return -1
	return dist[grid.pad_idx(x, y)]


## 朝目标的下降方向 0..5（方向序下标）；已在目标/不可达/不可通行返回 -1。平手取方向序号最小（确定性）。
## 实走边 = p→nb：爬 ≤1、下崖任意（单向崖）；英雄场 ignore_h 免查。
func dir_at(x: int, y: int) -> int:
	if not grid.passable(x, y):
		return -1
	var p := grid.pad_idx(x, y)
	var d: int = dist[p]
	if d <= 0:
		return -1
	var best := -1
	var best_d := d
	var pmap := grid.pmap
	var hp := grid.hp
	var ignore := ignore_h
	var off := off_o if (y & 1) == 1 else off_e
	for k in 6:
		var nb: int = p + off[k]
		if pmap[nb] == 1:
			if ignore or (hp[nb] - hp[p] <= 1):
				var nd: int = dist[nb]
				if nd >= 0 and nd < best_d:
					best_d = nd
					best = k
	return best


## 封死回退：目标不可达时，按切比雪夫环 r=0..3 逐格螺旋找首个"可达且本单位跨得进去"的通行格；找不到返回 -1。
## 邻域口径 = 切比雪夫窗（与六边拓扑无关的兜底收口，保旧确定性螺旋序）。
## 返回未加帧的格子序号（与 Grid:idx 一致，0 基）。
func fallback_near(x: int, y: int) -> int:
	var hp := grid.hp
	var from := grid.pad_idx(x, y)
	for r in 4:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					var nx := x + dx
					var ny := y + dy
					if grid.passable(nx, ny):
						var to := grid.pad_idx(nx, ny)
						if dist[to] >= 0 and (ignore_h or hp[to] - hp[from] <= 1):
							return ny * grid.w + nx
	return -1
