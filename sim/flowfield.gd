class_name FlowField
extends RefCounted

# 流场：多目标 Dijkstra（直 10 / 斜 14，贴角禁穿）+ 距离桶队列（Dial 变体）。
# 照搬 warden/Warden.Core/FlowField.cs 语义，含三条确定性纪律：
#   · 贴角禁穿：对角步要求两侧正交邻格都可通行；
#   · DirAt 平手取方向序号最小（严格 < 判定）；
#   · 纯整数运算，无浮点无 libm。
# 方向序（全项目唯一）：0E 1NE 2N 3NW 4W 5SW 6S 7SE（0 基）。
const STRAIGHT := 10
const DIAGONAL := 14
const DX := [1, 1, 0, -1, -1, -1, 0, 1]
const DY := [0, 1, 1, 1, 0, -1, -1, -1]
const INT64_MAX := 9223372036854775807

var grid: Grid
var ignore_h: bool
var dist: Array # padded 距离，-1 = 不可达（未写 = null 视同不可达）
var settled: Array
var max_d: int
var head: Array # 距离桶：head[d] 槽链表头，-1 = 空
var slot_cell: Array
var slot_next: Array
var off: Array
var side_a: Array
var side_b: Array
var cur: int
var max_bucket: int
var pending: int
var slots: int
var pops: int


func _init(pgrid: Grid, pignore_h: bool = false) -> void:
	grid = pgrid
	ignore_h = pignore_h
	var stride: int = grid.stride
	var pad_n: int = stride * (grid.h + 2)
	dist = []
	settled = []
	for i in pad_n:
		dist.append(-1)
		settled.append(0)
	# 距离上界（可证明）：最短路径绝不重复经过任一格（边权恒正）→ 至多 w*h−1 步 ×14。
	# 旧值 14×(w+h)+16 曾被蛇形长廊型地图突破而被 push 静默丢弃（见单测 snake-corridor）。
	max_d = DIAGONAL * grid.w * grid.h
	head = []
	for d in max_d + 1:
		head.append(-1)
	slot_cell = []
	slot_next = []
	# 邻居与对角两侧的 padded 下标增量（构造期算好，热循环纯加法）
	off = []
	side_a = []
	side_b = []
	for k in 8:
		var dx: int = DX[k]
		var dy: int = DY[k]
		off.append(dy * stride + dx)
		var diag := dx != 0 and dy != 0
		side_a.append(dy * stride if diag else 0)
		side_b.append(dx if diag else 0)
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


func relax(p: int, d: int) -> void:
	settled[p] = 1
	var pmap := grid.pmap
	var hp := grid.hp
	var ignore := ignore_h
	for k in 8:
		var nb: int = p + off[k]
		if pmap[nb] == 1:
			var diag := k % 2 == 1 # 0 基方向序：奇数=对角（NE/NW/SW/SE），偶数=直行
			if not (diag and (pmap[p + side_a[k]] == 0 or pmap[p + side_b[k]] == 0)):
				# 扩张边 = nb→p（nb 处单位跨入 p）：爬 ≤1、下崖任意（单向崖）
				if ignore or (hp[p] - hp[nb] <= 1):
					if settled[nb] == 0:
						var nd := d + (DIAGONAL if diag else STRAIGHT)
						if dist[nb] == -1 or nd < dist[nb]:
							dist[nb] = nd
							push(nd, nb)


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


func next_nonempty_bucket(from: int) -> int:
	if from < 0:
		from = 0
	for i in range(from, max_bucket + 1):
		if head[i] >= 0:
			return i
	return -1


func dist_at(x: int, y: int) -> int:
	if not grid.inb(x, y):
		return -1
	return dist[grid.pad_idx(x, y)]


## 朝目标的下降方向 0..7（方向序下标）；已在目标/不可达/不可通行返回 -1。平手取方向序号最小（确定性）。
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
	for k in 8:
		var nb: int = p + off[k]
		if pmap[nb] == 1:
			var diag := k % 2 == 1 # 0 基方向序：奇数=对角
			if not (diag and (pmap[p + side_a[k]] == 0 or pmap[p + side_b[k]] == 0)):
				if ignore or (hp[nb] - hp[p] <= 1):
					var nd: int = dist[nb]
					if nd >= 0 and nd < best_d:
						best_d = nd
						best = k
	return best


## 封死回退：目标不可达时，按切比雪夫环 r=0..3 逐格螺旋找首个"可达且本单位跨得进去"的通行格；找不到返回 -1。
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
