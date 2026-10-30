extends Node3D

# 3D 视图层门面（移植 reroute/scripts/view3d.lua；D5-1 拆分）：64² 战场渲染 + 拾取 + 相机取景
# + 蓝图配色/雾 + 实体视觉同步（单位插值/建筑剪影/英雄/死亡消散/震荡环/幽灵/热层）。
# 实现拆入四组件：view_core（坐标/相机/基建）/ view_terrain（蓝图/柱带/环带/热层/拾取）/
# view_entities（单位/建筑/英雄/死亡/幽灵）/ view_audio（SFX/环境音/BGM）。
# 本文件只做两件事：_ready 组装；把组件公共面原样转发为 view.xxx（外部访问零变化）。
# 视图层只读模拟状态，绝不回写；插值用的 prev 格存组件里，不进指纹。

# ---- 公开面（外部可调）：main / tests / probes 全部按 view.xxx 访问，不直接碰组件 ----
# 转发方法 26 个：sync / debug_stats / cell_to_world / ground_y / pick_cell / world_to_screen /
# camera_pan / camera_pan_pixels / camera_rotate / camera_zoom / camera_pitch_by / camera_pitch /
# shake / update_shake / apply_blueprint / apply_video / build_terrain / set_heat / heat_enabled /
# show_ghost / set_focus / set_hero_range / play_sound / bgm / bgm_settlement / stop_all_audio。
# 转发属性（只读；is_ore / on_float 可写）：unit_nodes / building_nodes / cover_nodes / death_fx /
# hero / ring / ghost / ghost_mi / ghost_alive / preview_root / range_root / wall_edges / focus_ring /
# camera / mats / field_root / heat_root / sfx_players / sfx_amb / bgm_player / bgm_on / sfx_log。
# 常量：H_STEP / Z_YAW。组件引用：core / audio / terrain / entities。
# ---- 探针契约（改名会破 tests/probes，勿动）----
# 上面方法与常量被 39 个探针共 140+ 处直读；view_core 的 cell_to_world / make_material 是
# 四组件共用工具，不得私有化。

const ModelsScript = preload("res://game/view/models.gd")

const ViewCoreScript = preload("res://game/view/view_core.gd")
const ViewAudioScript = preload("res://game/view/view_audio.gd")
const ViewTerrainScript = preload("res://game/view/view_terrain.gd")
const ViewEntitiesScript = preload("res://game/view/view_entities.gd")
const FogScript = preload("res://game/view/fog_of_war.gd")

# 常量转发（探针经 view.H_STEP / view.Z_YAW 读取，语义同原 view.gd）
const H_STEP := ViewCoreScript.H_STEP
const Z_YAW := ViewEntitiesScript.Z_YAW

var core: ViewCoreScript
var audio: ViewAudioScript
var terrain: ViewTerrainScript
var entities: ViewEntitiesScript
var fog: FogScript # 战争迷雾位图（开局成长改造 2026-10-28）：纯视图层；探针置 enabled=false 关闭


## 视图启动：组装四组件 + 首局 canyon 地貌 + 相机取景 + 音频（顺序 = 原单文件初始化）
func _ready() -> void:
	# 组件组装（顺序 = 原单文件初始化顺序：模型管理器 → 渲染基建 → 场地根 → 首局地貌 → 相机 → 音频）
	fog = FogScript.new()
	core = ViewCoreScript.new(self)
	audio = ViewAudioScript.new(self)
	terrain = ViewTerrainScript.new(self, core)
	# 地面高度回调注入（A1 最小视距用）：view_core 不直接引用 view_terrain，只持有 Callable。
	core.set_ground_height(Callable(terrain, "ground_h"))
	entities = ViewEntitiesScript.new(self, core, terrain, audio)
	entities.fog = fog # 战争迷雾位图注入（units 闸门/热层遮蔽用）

	entities.models = ModelsScript.new() # 真实资产模型管理器
	core.setup()
	terrain.setup_roots()
	entities.is_ore = func(_x: int, _y: int) -> bool: return false
	# 首帧不铺地貌：main._boot 紧接着就会 new_game 应用当局蓝图；预铺 canyon 纯属重复构建
	# （实测多花约 2s 冷启动，且一帧都看不到）。隐私门分支不建世界，显示为空白背景可接受。
	core._ensure_camera()
	core.fit_camera()
	audio._setup_audio()


# ============ 转发（公共面：外部 ~190 处 view.* 访问零变化）============

## 每帧同步（→ view_entities；tick_alpha = 渲染帧在两次模拟 tick 间的相位，delta = 帧间隔）
func sync(world: World, tick_alpha: float = 0.0, delta: float = 0.0) -> void:
	entities.sync(world, tick_alpha, delta)


## 探针用统计（→ view_entities）
func debug_stats() -> Dictionary:
	return entities.debug_stats()


## 格子坐标 → 世界坐标（→ view_core）
func cell_to_world(x: int, y: int) -> Vector3:
	return core.cell_to_world(x, y)


## 格子 → 视觉地面高度（→ view_terrain）
func ground_y(x: int, y: int) -> float:
	return terrain.ground_y(x, y)


## 屏幕坐标（像素）→ 战场格（→ view_terrain）
func pick_cell(screen_x: float, screen_y: float) -> Vector2i:
	return terrain.pick_cell(screen_x, screen_y)


## 世界坐标 → 屏幕像素（→ view_core）
func world_to_screen(wx: float, wy: float, wz: float) -> Vector2:
	return core.world_to_screen(wx, wy, wz)


## 相机平移（WASD；世界单位；→ view_core）
func camera_pan(dir_x: float, dir_y: float, dist: float) -> void:
	core.pan_world(dir_x, dir_y, dist)


## 相机像素平移（右键拖拽；→ view_core）
func camera_pan_pixels(dx: float, dy: float) -> void:
	core.pan_pixels(dx, dy)


## 相机水平旋转（QE；正 = 左旋；→ view_core）
func camera_rotate(delta: float) -> void:
	core.rotate_y(delta)


## 相机滚轮缩放（倍率因子；夹在 [0.6, 1.8]；→ view_core）
func camera_zoom(factor: float) -> void:
	core.zoom_by(factor)


## 相机俯仰（中键上下拖；增量弧度，正 = 更陡；→ view_core）
func camera_pitch_by(delta: float) -> void:
	core.pitch_by(delta)


## 当前俯仰角（弧度；中键拖拽/探针读取用；→ view_core）
func camera_pitch() -> float:
	return core.pitch()


## 震屏（B3，amp 米 / dur 秒；只平移不旋转；探针运行时由 main 关闭）
func shake(amp: float, dur: float) -> void:
	core.shake(amp, dur)


## 逐帧推进震屏（main 每帧调；无震动时零成本早退）
func update_shake(dt: float) -> void:
	core.update_shake(dt)


## 应用蓝图（→ view_terrain）；anchor 可选：地标对齐当局 Scenario（见 blueprint.compose）
func apply_blueprint(bp: Dictionary, bp_seed: int, anchor: Dictionary = {}) -> void:
	terrain.apply_blueprint(bp, bp_seed, anchor)


## 视频/画质应用（渲染缩放/抗锯齿/阴影/雾/景深/亮度 + 特效质量；→ view_core / view_entities）
func apply_video(cfg: Dictionary) -> void:
	core.apply_video(cfg)
	entities.apply_fx_quality(int(cfg.get("fx_q", 2)))


## 铺一局的动态内容（→ view_entities）
func build_terrain(pgrid: Grid) -> void:
	entities.build_terrain(pgrid)


## 开关威胁热层（→ view_terrain）
func set_heat(on: bool) -> void:
	terrain.set_heat(on)


## 热层是否开启（→ view_terrain）
func heat_enabled() -> bool:
	return terrain.heat_enabled()


## 幽灵预览（→ view_entities）；mode = "wall"/"tower" 时叠实物半透明模型（含射程/边缘拼接）
func show_ghost(cells: Array, bad: bool = false, mode: String = "") -> void:
	entities.show_ghost(cells, bad, mode)


## 建筑悬停/拆除焦点环（→ view_entities；cell.x < 0 隐藏）
func set_focus(cell: Vector2i, hot: bool = true) -> void:
	entities.set_focus(cell, hot)


## 英雄模式范围预览圈（→ view_entities；on = 选中英雄模式时显示震荡波半径）
func set_hero_range(on: bool) -> void:
	entities.set_hero_range(on)


## 播一个音效（→ view_audio）
func play_sound(sname: String, gain: float = 0.8) -> void:
	audio.play_sound(sname, gain)


## 对局 BGM 开关（→ view_audio）
func bgm(enabled: bool) -> void:
	audio.bgm(enabled)


## 结算 BGM 开关（→ view_audio）
func bgm_settlement(enabled: bool) -> void:
	audio.bgm_settlement(enabled)


## 全停音频（→ view_audio）
func stop_all_audio() -> void:
	audio.stop_all_audio()


# ---- 属性转发（组件状态；外部只读，is_ore/on_float 可写）----

var unit_nodes: Dictionary:
	get:
		return entities.unit_nodes

var building_nodes: Dictionary:
	get:
		return entities.building_nodes

var cover_nodes: Dictionary:
	get:
		return entities.cover_nodes

var death_fx: Array:
	get:
		return entities.death_fx

var hero: Variant:
	get:
		return entities.hero

var ring: Variant:
	get:
		return entities.ring

var ghost: Node3D:
	get:
		return entities.ghost

var ghost_mi: MeshInstance3D:
	get:
		return entities.ghost_mi

var ghost_alive: bool:
	get:
		return entities.ghost_alive

var preview_root: Node3D:
	get:
		return entities.preview_root

var range_root: Node3D:
	get:
		return entities.range_root

var wall_edges: Dictionary:
	get:
		return entities._wall_edges

var focus_ring: MeshInstance3D:
	get:
		return entities.focus_ring

var is_ore: Callable:
	get:
		return entities.is_ore
	set(v):
		entities.is_ore = v

var on_float: Callable:
	get:
		return entities.on_float
	set(v):
		entities.on_float = v

var camera: Camera3D:
	get:
		return core.camera

var mats: Dictionary:
	get:
		return core.mats

var field_root: Node3D:
	get:
		return terrain.field_root

var heat_root: Node3D:
	get:
		return terrain.heat_root

var sfx_players: Array:
	get:
		return audio.sfx_players

var sfx_amb: AudioStreamPlayer:
	get:
		return audio.sfx_amb

var bgm_player: AudioStreamPlayer:
	get:
		return audio.bgm_player

var bgm_on: bool:
	get:
		return audio.bgm_on

var sfx_log: Dictionary:
	get:
		return audio.sfx_log

var _sfx_next: int:
	get:
		return audio._sfx_next
