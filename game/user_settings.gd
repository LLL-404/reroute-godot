extends RefCounted

# 玩家设置（音频 / 显示 / 画质 / 性能 UI）持久化与应用：user://settings.cfg（ConfigFile）。
# 纯数据 + 应用函数；不引用任何视图/UI 模块（音频 bus 按名查找；显示走 DisplayServer）。
# 音量口径：滑杆 0..100 → 线性增益 v/100 → dB（0 = -80dB 静音）；默认 100 保现状响度。
# 显示：display_mode（0 窗口化 / 1 无边框 / 2 全屏）+ res_idx（0 原生 = 桌面可用区 … 4 = 1280×720）
#       + vsync；安卓恒全屏：显示模式/分辨率忽略（设置页对应行隐藏），渲染精度由 render_pct 承担。
# 帧率：fps（0 = 不限）；PC 候选 30/60/120，安卓仅 30/60。菜单/标题/结算恒 ≤60（main 组合）。
# 画质：quality 预设 0 低 / 1 中 / 2 高 / 3 极高 → 一键写入 shadow_q/fx_q/aa/post_q/render_pct
#       （子项仍可单独改，预设只是一键模板）；渲染/画质应用在 view_core.apply_video。
# UI：ui_pct 80..130（HUD 与界面 S 的倍率）；bright_pct 70..130（Environment 亮度）。
# 本文件不使用 class_name；调用方以 preload 引用（同 blueprint.gd 口径）。

const CFG_PATH := "user://settings.cfg"
const BGM_BUS := "BGM"
const SFX_BUS := "SFX"
const VOL_MIN := 0
const VOL_MAX := 100
const MUTE_DB := -80.0
const FPS_OPTS := [0, 30, 60, 120] # PC 帧率上限候选（0 = 不限）
const FPS_OPTS_ANDROID := [30, 60] # 安卓仅 30/60
const QUALITY_OPTS := [0, 1, 2, 3] # 画质预设：低 / 中 / 高 / 极高
const AA_OPTS := [0, 1, 2] # 抗锯齿：关 / FXAA / TAA
const AA_OPTS_ANDROID := [0, 1] # 安卓 Mobile 渲染器无 TAA
const RES_OPTS := [[0, 0], [2560, 1440], [1920, 1080], [1600, 900], [1280, 720]] # [0] = 原生
const VIDEO_KEYS := [
	"display_mode", "res_idx", "vsync", "fps", "quality", "shadow_q", "fx_q",
	"aa", "post_q", "dof", "render_pct", "ui_pct", "bright_pct",
]

# 画质预设一键模板（索引 = quality 档）：只写画质子项，不动显示/帧率/UI 缩放
const QUALITY_PRESETS := [
	{ "shadow_q": 0, "fx_q": 0, "aa": 0, "post_q": 0, "render_pct": 70 }, # 低
	{ "shadow_q": 1, "fx_q": 1, "aa": 1, "post_q": 1, "render_pct": 85 }, # 中
	{ "shadow_q": 2, "fx_q": 2, "aa": 1, "post_q": 2, "render_pct": 100 }, # 高
	{ "shadow_q": 2, "fx_q": 2, "aa": 2, "post_q": 2, "render_pct": 100 }, # 极高
]

# UI 缩放倍率（静态：hud/screens 的 S 计算共用；由 main 在设置变动时写入）
static var ui_scale := 1.0


## 默认配置：音量满格 / 窗口化 720p / 开垂直同步 / 不限帧（安卓 60）/ 画质高（安卓中）/
## UI·亮度 100%。安卓按移动端口径：预设中（阴影/特效/后期中，渲染缩放 85%，60 帧），保流畅与续航。
static func default_cfg() -> Dictionary:
	var android := OS.get_name() == "Android"
	return {
		"music": VOL_MAX,
		"sfx": VOL_MAX,
		"display_mode": 0,
		"res_idx": 4,
		"vsync": true,
		"fps": 60 if android else 0,
		"quality": 1 if android else 2,
		"shadow_q": 1 if android else 2,
		"fx_q": 1 if android else 2,
		"aa": 1,
		"post_q": 1 if android else 2,
		"dof": false,
		"render_pct": 85 if android else 100,
		"ui_pct": 100,
		"bright_pct": 100,
		"runs": 0,
		"privacy_agreed": false,
		"seed_text": "", # 世界种子输入原样（空串 = 每局随机；文字由 SeedCode 哈希）
	}


## 种子文本清洗：去首尾空白 + 截到 SeedCode.MAX_LEN（读档 / 写盘 / 输入三处同一口径）
static func clean_seed_text(text: String) -> String:
	var s := text.strip_edges()
	return s.substr(0, SeedCode.MAX_LEN) if s.length() > SeedCode.MAX_LEN else s


## 平台抗锯齿候选（安卓 Mobile 渲染器无 TAA）
static func aa_opts() -> Array:
	return AA_OPTS_ANDROID if OS.get_name() == "Android" else AA_OPTS


## 抗锯齿合法化（越界/平台不支持 → 回 FXAA）
static func aa_level(v: int) -> int:
	var a := clampi(v, 0, 2)
	return a if aa_opts().has(a) else 1


## 平台帧率候选（安卓仅 30/60；0 = 不限仅 PC）
static func fps_opts() -> Array:
	return FPS_OPTS_ANDROID if OS.get_name() == "Android" else FPS_OPTS


## 读配置（缺失文件 / 字段一律回默认，绝不抛；旧版 video/fullscreen 迁移到 display_mode）。
static func load_cfg() -> Dictionary:
	var cfg := default_cfg()
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		cfg["music"] = clampi(int(cf.get_value("audio", "music", cfg["music"])), VOL_MIN, VOL_MAX)
		cfg["sfx"] = clampi(int(cf.get_value("audio", "sfx", cfg["sfx"])), VOL_MIN, VOL_MAX)
		var legacy_fs := bool(cf.get_value("video", "fullscreen", false)) # v2 旧键 → 全屏档
		cfg["display_mode"] = clampi(int(cf.get_value("video", "display_mode", 2 if legacy_fs else cfg["display_mode"])), 0, 2)
		cfg["res_idx"] = clampi(int(cf.get_value("video", "res_idx", cfg["res_idx"])), 0, RES_OPTS.size() - 1)
		cfg["vsync"] = bool(cf.get_value("video", "vsync", cfg["vsync"]))
		var f := int(cf.get_value("video", "fps", cfg["fps"]))
		cfg["fps"] = f if fps_opts().has(f) else int(cfg["fps"])
		cfg["quality"] = clampi(int(cf.get_value("video", "quality", cfg["quality"])), 0, QUALITY_OPTS.size() - 1)
		# v2 旧档只有 quality：缺失的子项按该预设补齐（避免「预设档与子项错配」）；
		# v3 档五个子项齐全，各自保留，允许脱离预设单独调。
		var preset: Dictionary = QUALITY_PRESETS[int(cfg["quality"])]
		cfg["shadow_q"] = clampi(int(cf.get_value("video", "shadow_q", preset["shadow_q"])), 0, 2)
		cfg["fx_q"] = clampi(int(cf.get_value("video", "fx_q", preset["fx_q"])), 0, 2)
		cfg["aa"] = aa_level(int(cf.get_value("video", "aa", preset["aa"])))
		cfg["post_q"] = clampi(int(cf.get_value("video", "post_q", preset["post_q"])), 0, 2)
		cfg["dof"] = bool(cf.get_value("video", "dof", cfg["dof"]))
		cfg["render_pct"] = clampi(int(cf.get_value("video", "render_pct", preset["render_pct"])), 50, 100)
		cfg["ui_pct"] = clampi(int(cf.get_value("video", "ui_pct", cfg["ui_pct"])), 80, 130)
		cfg["bright_pct"] = clampi(int(cf.get_value("video", "bright_pct", cfg["bright_pct"])), 70, 130)
		cfg["runs"] = maxi(0, int(cf.get_value("progress", "runs", cfg["runs"])))
		cfg["privacy_agreed"] = bool(cf.get_value("privacy", "agreed", cfg["privacy_agreed"]))
		cfg["seed_text"] = clean_seed_text(str(cf.get_value("game", "seed_text", cfg["seed_text"])))
	return cfg


## 写配置（值先夹取到合法域）。先读旧档保留未给出的键（如 runs 进度：设置页保存不吞进度）。
static func save_cfg(cfg: Dictionary) -> void:
	var cf := ConfigFile.new()
	var prev_runs := 0
	var prev_agreed := false
	if cf.load(CFG_PATH) == OK:
		prev_runs = maxi(0, int(cf.get_value("progress", "runs", 0)))
		prev_agreed = bool(cf.get_value("privacy", "agreed", false))
	var def := default_cfg() # 平台默认（安卓中画质/85% 渲染；PC 高画质/100%）
	cf.set_value("audio", "music", clampi(int(cfg.get("music", VOL_MAX)), VOL_MIN, VOL_MAX))
	cf.set_value("audio", "sfx", clampi(int(cfg.get("sfx", VOL_MAX)), VOL_MIN, VOL_MAX))
	cf.set_value("video", "display_mode", clampi(int(cfg.get("display_mode", def["display_mode"])), 0, 2))
	cf.set_value("video", "res_idx", clampi(int(cfg.get("res_idx", def["res_idx"])), 0, RES_OPTS.size() - 1))
	cf.set_value("video", "vsync", bool(cfg.get("vsync", def["vsync"])))
	var f := int(cfg.get("fps", def["fps"]))
	cf.set_value("video", "fps", f if fps_opts().has(f) else int(def["fps"]))
	cf.set_value("video", "quality", clampi(int(cfg.get("quality", def["quality"])), 0, QUALITY_OPTS.size() - 1))
	cf.set_value("video", "shadow_q", clampi(int(cfg.get("shadow_q", def["shadow_q"])), 0, 2))
	cf.set_value("video", "fx_q", clampi(int(cfg.get("fx_q", def["fx_q"])), 0, 2))
	cf.set_value("video", "aa", aa_level(int(cfg.get("aa", def["aa"]))))
	cf.set_value("video", "post_q", clampi(int(cfg.get("post_q", def["post_q"])), 0, 2))
	cf.set_value("video", "dof", bool(cfg.get("dof", def["dof"])))
	cf.set_value("video", "render_pct", clampi(int(cfg.get("render_pct", def["render_pct"])), 50, 100))
	cf.set_value("video", "ui_pct", clampi(int(cfg.get("ui_pct", def["ui_pct"])), 80, 130))
	cf.set_value("video", "bright_pct", clampi(int(cfg.get("bright_pct", def["bright_pct"])), 70, 130))
	cf.set_value("progress", "runs", maxi(0, int(cfg.get("runs", prev_runs))))
	cf.set_value("privacy", "agreed", bool(cfg.get("privacy_agreed", prev_agreed)))
	cf.set_value("game", "seed_text", clean_seed_text(str(cfg.get("seed_text", "")))) # 写盘前统一清洗
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


## 应用显示设置：显示模式 / 分辨率 / 垂直同步（headless 跳过；安卓只应用垂直同步）。
## 分辨率只在窗口化/无边框生效（全屏由引擎取桌面）；改尺寸后居中到可用区。
static func apply_video(cfg: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(cfg.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	if OS.get_name() == "Android":
		return # 安卓恒全屏：显示模式/分辨率项隐藏（渲染精度走 render_pct）
	var mode := clampi(int(cfg.get("display_mode", 0)), 0, 2)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == 1)
	var want_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if mode == 2 else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want_mode:
		DisplayServer.window_set_mode(want_mode)
	if mode == 2:
		return # 全屏分辨率由桌面决定
	var res: Array = RES_OPTS[clampi(int(cfg.get("res_idx", 4)), 0, RES_OPTS.size() - 1)]
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var target := usable.size if int(res[0]) == 0 else Vector2i(int(res[0]), int(res[1]))
	if target.x > 0 and target.y > 0 and DisplayServer.window_get_size() != target:
		DisplayServer.window_set_size(target)
		DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)


## 应用全部设置（启动即用 / 设置页改动后的统一入口）
static func apply_all(cfg: Dictionary) -> void:
	apply_audio(cfg)
	apply_video(cfg)


## 帧率上限（0 = 不限；非法值回平台默认）。菜单/对局组合取法在 main._sync_fps_cap，本文件只做合法性。
static func fps_cap(cfg: Dictionary) -> int:
	var f := int(cfg.get("fps", 0))
	return f if fps_opts().has(f) else int(default_cfg()["fps"])
