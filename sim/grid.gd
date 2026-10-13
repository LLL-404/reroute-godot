class_name Grid
extends RefCounted

# 格子三态与通行镜像，照搬 warden/Warden.Core/Grid.cs：
# Open=0 通行 / Cover=1 覆盖层（不可通行、可挖开）/ Solid=2 实心阻挡（不可挖）。
# 通行性加一帧 padded 镜像 ((W+2)×(H+2)，外环恒阻挡)，流场因此做纯下标邻域运算。
# 下标口径：内部数组 0 基（Lua 版 1 基），公式同构平移 -1；迭代序不变，指纹不受影响。
const OPEN := 0
const COVER := 1
const SOLID := 2

var w: int
var h: int
var stride: int
var cells: Array # 0..w*h-1，下标 = y*w + x
var pmap: Array # padded 通行镜像，1=通行；界外/未写 = null（当阻挡）
var hgt: Array # 高度层 0..5（未加帧）
var hp: Array # padded 高度镜像（流场热循环）
var rev: int


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


## 高度（0 基格坐标）。set_h bump rev：改高即改道，所有流场自动重建。
func get_h(x: int, y: int) -> int:
	if not inb(x, y):
		return 0
	return hgt[y * w + x]


func set_h(x: int, y: int, v: int) -> void:
	var i := y * w + x
	if hgt[i] == v:
		return
	hgt[i] = v
	hp[pad_idx(x, y)] = v
	rev += 1


## 初始化某格高度（建图期用，不 bump rev；必须紧跟 new 之后、流场建立之前调用）
func init_h(x: int, y: int, v: int) -> void:
	hgt[y * w + x] = v
	hp[pad_idx(x, y)] = v


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


func at(x: int, y: int) -> int:
	if not inb(x, y):
		return SOLID
	return cells[y * w + x]


## 可通行 = 界内且 Open。Cover 与 Solid 都挡行军。
func passable(x: int, y: int) -> bool:
	return inb(x, y) and cells[y * w + x] == OPEN


func set_cell(x: int, y: int, cell: int) -> void:
	var i := y * w + x
	if cells[i] == cell:
		return
	cells[i] = cell
	pmap[pad_idx(x, y)] = 1 if cell == OPEN else 0
	rev += 1
