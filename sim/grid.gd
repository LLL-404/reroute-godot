class_name Grid
extends RefCounted

# 格子三态与通行镜像。2026-10-17 六边形化（H 相）：
#   · 拓扑 = 尖顶（pointy-top）六边形，odd-r 偏移布局：奇数列右移半格（行 y 奇偶决定邻接）。
#   · 仍是 64×64 阵列、(x,y)=（列,行）语义、padded (W+2)×(H+2) 镜像——方形时代的
#     场景锚点/岩脊行/盆地矩形全部逐位保留，只有邻接关系与几何变了。
#   · 方向序（全项目唯一）：0E 1NE 2NW 3W 4SW 5SE；六向等权（流场统一步长 10）。
# 下标口径：内部数组 0 基，行列主序同旧版，指纹字段序不变（值当然全变，走重录）。
# Open=0 通行 / Cover=1 覆盖层（不可通行、可挖开）/ Solid=2 实心阻挡（不可挖）。
const OPEN := 0
const COVER := 1
const SOLID := 2

# 高度 u8 偏移编码（存档/canonical 用）：h ∈ [H_MIN, H_MAX] → v ∈ [0, H_MAX-H_MIN]
const H_OFFSET := 2 # = -Sim.H_MIN


## 高度 → 无符号字节值（负数不截断）
static func h_to_u8(h: int) -> int:
	return h + H_OFFSET


## 无符号字节值 → 高度
static func u8_to_h(v: int) -> int:
	return v - H_OFFSET

# odd-r 邻接增量表：[行奇偶（0=偶行/1=奇行）][方向 k]。DY 与行奇偶无关。
# 偶行：E(+1,0) NE(0,-1) NW(-1,-1) W(-1,0) SW(-1,+1) SE(0,+1)
# 奇行：E(+1,0) NE(+1,-1) NW(0,-1) W(-1,0) SW(0,+1) SE(+1,+1)
const DX := [[1, 0, -1, -1, -1, 0], [1, 1, 0, -1, 0, 1]]
const DY := [0, -1, -1, 0, 1, 1]


## 方向 k 在行 y 处的列增量。
static func dir_dx(k: int, y: int) -> int:
	return DX[y & 1][k]


## 方向 k 的行增量（与行奇偶无关）。
static func dir_dy(k: int) -> int:
	return DY[k]


## 单元 (x,y) 沿方向 k 的邻居列坐标。
static func nx(x: int, y: int, k: int) -> int:
	return x + DX[y & 1][k]


## 单元 (x,y) 沿方向 k 的邻居行坐标。
static func ny(x: int, y: int, k: int) -> int:
	return y + DY[k]


## odd-r 偏移坐标 → 轴向坐标（q 轴向列、r = 行）。q = x − (y − (y&1))/2。
static func to_axial(x: int, y: int) -> Vector2i:
	return Vector2i(x - ((y - (y & 1)) >> 1), y)


## 六边轴向距离（= 立方坐标切比雪夫距离）。
static func hex_dist(x1: int, y1: int, x2: int, y2: int) -> int:
	var a := to_axial(x1, y1)
	var b := to_axial(x2, y2)
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) >> 1

var w: int
var h: int
var stride: int
var cells: Array # 0..w*h-1，下标 = y*w + x
var pmap: Array # padded 通行镜像，1=通行；界外/未写 = null（当阻挡）
var hgt: Array # 高度层 -2..5（未加帧）
var hp: Array # padded 高度镜像（流场热循环）
var rev: int
var height_rev: int # 仅运行时改高递增；视图用它检测等量反向改高


## 建图：cells/hgt 初值填充 + padded 镜像（fill=OPEN 时 pmap 内区全通）
func _init(pw: int, ph: int, fill: int = OPEN) -> void:
	assert(pw > 0 and ph > 0, "地图尺寸必须为正，实得 %d×%d" % [pw, ph])
	w = pw
	h = ph
	stride = w + 2
	cells = []
	pmap = []
	hgt = []
	hp = []
	for i in w * h:
		cells.append(fill)
		hgt.append(0)
	var pad_n := stride * (h + 2)
	for i in pad_n:
		pmap.append(null)
		hp.append(null)
	for y in h:
		for x in w:
			var p := pad_idx(x, y)
			if fill == OPEN:
				pmap[p] = 1
			hp[p] = 0
	rev = 0
	height_rev = 0


## 高度（0 基格坐标）。set_h bump rev：改高即改道，所有流场自动重建。
func get_h(x: int, y: int) -> int:
	if not inb(x, y):
		return 0
	return hgt[y * w + x]


## 改格高度（rev / height_rev 双递增：改高即改道，流场全量重建）
func set_h(x: int, y: int, v: int) -> void:
	var i := y * w + x
	if hgt[i] == v:
		return
	hgt[i] = v
	hp[pad_idx(x, y)] = v
	rev += 1
	height_rev += 1


## 初始化某格高度（建图期用，不 bump rev；必须紧跟 new 之后、流场建立之前调用）
func init_h(x: int, y: int, v: int) -> void:
	hgt[y * w + x] = v
	hp[pad_idx(x, y)] = v


## 界内判定
func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


## 未加帧的格子下标（状态编码与测试口径）
func idx(x: int, y: int) -> int:
	return y * w + x


## padded 下标（流场热路径）。规范布局：padded 数组 (w+2)×(h+2)，内格 (x,y) →
## 行 y+1、列 x+1。注意与 Lua 母版的差异：母版公式多 +1（内格整体右移一列，
## 靠 Lua 的 nil-on-越界不报错兜底）；本移植用规范公式，邻居运算永不失越界，
## 图与母版同构，距离/指纹一致。
func pad_idx(x: int, y: int) -> int:
	return (y + 1) * stride + (x + 1)


## 格类型（界外 = SOLID）
func at(x: int, y: int) -> int:
	if not inb(x, y):
		return SOLID
	return cells[y * w + x]


## 可通行 = 界内且 Open。Cover 与 Solid 都挡行军。
func passable(x: int, y: int) -> bool:
	return inb(x, y) and cells[y * w + x] == OPEN


## 改格类型（pmap 同步 + rev 递增；值不变则空转）
func set_cell(x: int, y: int, cell: int) -> void:
	var i := y * w + x
	if cells[i] == cell:
		return
	cells[i] = cell
	pmap[pad_idx(x, y)] = 1 if cell == OPEN else 0
	rev += 1
