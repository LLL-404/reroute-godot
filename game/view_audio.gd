extends RefCounted

# 《改道》视图层 · 音频（D5-1 拆分自 view.gd）：4 轮换特效源 + 常驻环境音 + 对局 BGM（母版三件套）。
# 独立域：不引用 core/terrain/entities；由 view.gd 组装持有，节点挂点统一走 host。

const SFX_POOL_N := 4 # 母版 4 个轮换源，避免同帧多音互相掐断
const AUDIO_DIR := "res://assets/audio/sfx/"
const UserSettings = preload("res://game/user_settings.gd") # bus 名 + 音量应用（设置页共用）

var host: Node3D

var sfx_players: Array = [] # 轮换池（AudioStreamPlayer ×4）
var sfx_amb: AudioStreamPlayer = null # 常驻环境源（循环）
var bgm_player: AudioStreamPlayer = null # 对局 BGM 源
var bgm_on := false # 诊断：BGM 开关态（探针用）
var audio_on := true # headless 跳过实际播放（Dummy 驱动；见 _setup_audio 注释）
var sfx_log: Dictionary = {} # 诊断计数：文件名 → 播放次数（探针用，生产无害）
var _sfx_next := 0 # 轮换下标
var _streams: Dictionary = {} # 流缓存（每文件 load 一次）


func _init(p_host: Node3D) -> void:
	host = p_host


## 建音频三件套：4 轮换特效源 + 1 常驻环境源（循环）+ BGM 源。
## 环境音自 View 初始化即播（标题屏只留环境音）；BGM 由 main 经 bgm() 开关。
## headless（Dummy 音频驱动）跳过实际播放：听不见，且退出的播放对象回收存在竞态
## （ObjectDB 泄漏 + resources still in use，实测）——接口/资源/状态断言照常可测。
func _setup_audio() -> void:
	audio_on = DisplayServer.get_name() != "headless"
	# 用户音量 bus（BGM/SFX）：先确保存在再路由，设置页只改 bus 音量、不动逐音增益
	UserSettings.ensure_bus(UserSettings.BGM_BUS)
	UserSettings.ensure_bus(UserSettings.SFX_BUS)
	var sroot := Node.new()
	sroot.name = "SFX"
	host.add_child(sroot)
	for i in SFX_POOL_N:
		var p := AudioStreamPlayer.new()
		p.name = "sfx" + str(i + 1)
		p.bus = UserSettings.SFX_BUS
		sroot.add_child(p)
		sfx_players.append(p)
	sfx_amb = AudioStreamPlayer.new()
	sfx_amb.name = "amb"
	sfx_amb.bus = UserSettings.SFX_BUS
	sroot.add_child(sfx_amb)
	var amb: AudioStream = _load_stream("dungeon_ambience.mp3")
	if amb != null:
		var amb_mp3 := amb as AudioStreamMP3
		if amb_mp3 != null:
			amb_mp3.loop = true
		sfx_amb.stream = amb
		sfx_amb.volume_db = linear_to_db(0.22)
		if audio_on:
			sfx_amb.play()
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "bgm"
	bgm_player.bus = UserSettings.BGM_BUS
	sroot.add_child(bgm_player)


## 音频流缓存加载（文件/导入缺失静默返回 null——音频缺失绝不能停对局）。
func _load_stream(fname: String) -> AudioStream:
	if _streams.has(fname):
		return _streams[fname] as AudioStream
	var path := AUDIO_DIR + fname
	if not ResourceLoader.exists(path):
		_streams[fname] = null
		return null
	var s: AudioStream = load(path) as AudioStream
	_streams[fname] = s
	return s


## 播一个音效（assets/audio/sfx/ 下文件名）；轮换池避免同帧多音互相掐断。
func play_sound(sname: String, gain: float = 0.8) -> void:
	if sfx_players.is_empty():
		return
	var s: AudioStream = _load_stream(sname)
	if s == null:
		return
	var p: AudioStreamPlayer = sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % sfx_players.size()
	p.stream = s
	p.volume_db = linear_to_db(gain)
	if audio_on:
		p.play()
	sfx_log[sname] = int(sfx_log.get(sname, 0)) + 1


## 对局 BGM 开关（bgm_reroute.mp3，looped；曲子缺失静默）。
func bgm(enabled: bool) -> void:
	_bgm_play("bgm_reroute.mp3", enabled, 0.34)


## 结算 BGM 开关（bgm_settlement.mp3，looped；终局接替对局 BGM，重开/回标题由 bgm() 覆盖）。
func bgm_settlement(enabled: bool) -> void:
	_bgm_play("bgm_settlement.mp3", enabled, 0.40)


## BGM 通播：换曲 + 循环 + 音量；缺失静默；bgm_on 同步诊断态（探针断言用）。
func _bgm_play(fname: String, enabled: bool, gain: float) -> void:
	if bgm_player == null:
		return
	bgm_on = enabled
	if enabled:
		var s: AudioStream = _load_stream(fname)
		if s == null:
			return
		var s_mp3 := s as AudioStreamMP3
		if s_mp3 != null:
			s_mp3.loop = true
		bgm_player.stream = s
		bgm_player.volume_db = linear_to_db(gain)
		if audio_on:
			bgm_player.play()
	else:
		bgm_player.stop()


## 全停音频并解绑流（退出收尾用：带活动播放对象直接 quit 会报 Playback 泄漏/资源占用）。
func stop_all_audio() -> void:
	if sfx_amb != null:
		sfx_amb.stop()
		sfx_amb.stream = null
	for p in sfx_players:
		var ap: AudioStreamPlayer = p
		ap.stop()
		ap.stream = null
	if bgm_player != null:
		bgm_player.stop()
		bgm_player.stream = null
