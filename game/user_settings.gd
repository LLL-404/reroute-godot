extends RefCounted

# 玩家设置（音量 / 全屏）持久化与应用：user://settings.cfg（ConfigFile）。
# 纯数据 + 应用函数；不引用任何视图模块（音频 bus 按名查找 / 创建）。
# 音量口径：滑杆 0..100 → 线性增益 v/100 → dB（0 = -80dB 静音）；默认 100 保现状响度。
# 全屏：PC 有效；Android / headless 跳过（Android 恒全屏）。
# 本文件不使用 class_name；调用方以 preload 引用（同 blueprint.gd 口径）。

const CFG_PATH := "user://settings.cfg"
const BGM_BUS := "BGM"
const SFX_BUS := "SFX"
const VOL_MIN := 0
const VOL_MAX := 100
const MUTE_DB := -80.0


## 默认配置：音量满格 / 非全屏（首次启动与原行为一致）
static func default_cfg() -> Dictionary:
	return { "music": VOL_MAX, "sfx": VOL_MAX, "fullscreen": false }


## 读配置（缺失文件 / 字段一律回默认，绝不抛）。
static func load_cfg() -> Dictionary:
	var cfg := default_cfg()
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		cfg["music"] = clampi(int(cf.get_value("audio", "music", cfg["music"])), VOL_MIN, VOL_MAX)
		cfg["sfx"] = clampi(int(cf.get_value("audio", "sfx", cfg["sfx"])), VOL_MIN, VOL_MAX)
		cfg["fullscreen"] = bool(cf.get_value("video", "fullscreen", cfg["fullscreen"]))
	return cfg


## 写配置（值先夹取到合法域）。
static func save_cfg(cfg: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music", clampi(int(cfg.get("music", VOL_MAX)), VOL_MIN, VOL_MAX))
	cf.set_value("audio", "sfx", clampi(int(cfg.get("sfx", VOL_MAX)), VOL_MIN, VOL_MAX))
	cf.set_value("video", "fullscreen", bool(cfg.get("fullscreen", false)))
	cf.save(CFG_PATH)


## 确保具名 bus 存在，返回其下标（缺则新建追加）。
static func ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	return idx


## 应用音量到 BGM / SFX 两条 bus（bus 缺失则先建）。
static func apply_audio(cfg: Dictionary) -> void:
	_set_bus_volume(BGM_BUS, int(cfg.get("music", VOL_MAX)))
	_set_bus_volume(SFX_BUS, int(cfg.get("sfx", VOL_MAX)))


## 设单条 bus 音量：0 → -80dB 静音；否则线性增益转 dB
static func _set_bus_volume(bus_name: String, vol: int) -> void:
	var idx := ensure_bus(bus_name)
	var v := clampi(vol, VOL_MIN, VOL_MAX)
	AudioServer.set_bus_volume_db(idx, MUTE_DB if v <= 0 else linear_to_db(float(v) / 100.0))


## 应用全屏开关（PC 有效；Android / headless 跳过）。
static func apply_video(cfg: Dictionary) -> void:
	if OS.get_name() == "Android" or DisplayServer.get_name() == "headless":
		return
	var want_fs := bool(cfg.get("fullscreen", false))
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fs != is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)


## 应用全部设置（启动即用 / 设置页改动后的统一入口）
static func apply_all(cfg: Dictionary) -> void:
	apply_audio(cfg)
	apply_video(cfg)
