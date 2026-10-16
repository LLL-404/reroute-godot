extends Node3D

# 3D 视图层门面（移植 reroute/scripts/view3d.lua；D5-1 拆分）：64² 战场渲染 + 拾取 + 相机取景
# + 蓝图配色/雾 + 实体视觉同步（单位插值/建筑剪影/英雄/死亡消散/震荡环/幽灵/热层）。
# 实现拆入四组件：view_core（坐标/相机/基建）/ view_terrain（蓝图/柱带/环带/热层/拾取）/
# view_entities（单位/建筑/英雄/死亡/幽灵）/ view_audio（SFX/环境音/BGM）。
# 本文件只做两件事：_ready 组装；把组件公共面原样转发为 view.xxx（外部访问零变化）。
# 视图层只读模拟状态，绝不回写；插值用的 prev 格存组件里，不进指纹。

const Blueprint = preload("res://game/blueprint.gd")
const ModelsScript = preload("res://game/models.gd")

const ViewCoreScript = preload("res://game/view_core.gd")
const ViewAudioScript = preload("res://game/view_audio.gd")
const ViewTerrainScript = preload("res://game/view_terrain.gd")
const ViewEntitiesScript = preload("res://game/view_entities.gd")

# 常量转发（探针经 view.H_STEP / view.Z_YAW 读取，语义同原 view.gd）
const H_STEP := ViewCoreScript.H_STEP
const Z_YAW := ViewEntitiesScript.Z_YAW

var core: ViewCoreScript
var audio: ViewAudioScript
var terrain: ViewTerrainScript
var entities: ViewEntitiesScript


func _ready() -> void:
	# 组件组装（顺序 = 原单文件初始化顺序：模型管理器 → 渲染基建 → 场地根 → 首局地貌 → 相机 → 音频）
	core = ViewCoreScript.new(self)
	audio = ViewAudioScript.new(self)
	terrain = ViewTerrainScript.new(self, core)
	entities = ViewEntitiesScript.new(self, core, terrain, audio)

	entities.models = ModelsScript.new() # 真实资产模型管理器
	core.setup()
	terrain.setup_roots()
	entities.is_ore = func(_x: int, _y: int) -> bool: return false
	# 首次地貌：canyon（同母版 View.init；逐局由 main.new_game 换装）
	terrain.apply_blueprint(Blueprint.get_preset("canyon"), 0)
	core._ensure_camera()
	core.fit_camera()
	audio._setup_audio()


# ============ 转发（公共面：外部 ~190 处 view.* 访问零变化）============

## 每帧同步（→ view_entities）
func sync(world: World) -> void:
	entities.sync(world)


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


## 应用蓝图（→ view_terrain）；anchor 可选：地标对齐当局 Scenario（见 blueprint.compose）
func apply_blueprint(bp: Dictionary, seed: int, anchor: Dictionary = {}) -> void:
	terrain.apply_blueprint(bp, seed, anchor)


## 铺一局的动态内容（→ view_entities）
func build_terrain(pgrid: Grid) -> void:
	entities.build_terrain(pgrid)


## 开关威胁热层（→ view_terrain）
func set_heat(on: bool) -> void:
	terrain.set_heat(on)


## 热层是否开启（→ view_terrain）
func heat_enabled() -> bool:
	return terrain.heat_enabled()


## 幽灵预览（→ view_entities）
func show_ghost(cells: Array, bad: bool = false) -> void:
	entities.show_ghost(cells, bad)


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
