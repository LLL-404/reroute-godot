class_name Dims
extends RefCounted

# 地图尺寸唯一真源（2026-10-27 CAMERA-MAP B1，§11.48）：sim 布局/地形、视图坐标、
# 蓝图烘焙三处权威全部派生自这里——改 MAP_N 一处即全图换尺寸。
# 一致性由 test_dims 单测锁死（sc.w == core.CELL_N == blueprint 派生）。
# 注意：跨尺寸会作废黄金基线/剧本指纹/存档（schema 拒载），翻尺寸必须同步重录。
const MAP_N := 128 # 2026-10-27 B2：64→128 扩容（标定带同步 ×2，sweep 复测见 §11.48）
const MAP_HALF := MAP_N / 2.0 # 世界坐标半宽（米；六边格距 1m，odd-r 中心 +0.5）
