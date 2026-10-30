extends RefCounted

# 槽位存档文件 I/O：user://save_slot1.json .. save_slot3.json（JSON 文本）。
# 分工：编码/校验/解码在 sim/save.gd（Save），本模块只管路径、读写、槽位列表。
# 本文件不使用 class_name；调用方以 preload 引用（同 blueprint.gd 口径）。

const SaveCodec = preload("res://sim/save.gd")
const SLOT_N := 3


## 宽容 JSON 解析：先做廉价结构预检（花括号包裹），截断/垃圾文件直接判坏，
## 避免 JSON.parse_string 在 stderr 刷引擎级报错。失败 = null（与解析失败同义）。
static func _parse_json(txt: String) -> Variant:
	var t := txt.strip_edges()
	if not (t.begins_with("{") and t.ends_with("}")):
		return null
	return JSON.parse_string(t)


## 槽位号 → 存档文件路径（user://save_slotN.json）
static func slot_path(slot: int) -> String:
	return "user://save_slot%d.json" % slot


## 全部槽位概览：Array[{ slot, empty, ok, reason, meta }]，固定 3 条。
static func list_slots() -> Array:
	var out: Array = []
	for i in range(1, SLOT_N + 1):
		out.append(slot_info(i))
	return out


## 单槽信息（空槽 / 损坏 / 有效三态；浅校验，不重建世界）。
static func slot_info(slot: int) -> Dictionary:
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return { "slot": slot, "empty": true, "ok": false, "reason": "", "meta": {} }
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return { "slot": slot, "empty": false, "ok": false, "reason": "存档无法打开", "meta": {} }
	var txt := f.get_as_text()
	f.close()
	var d = _parse_json(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return { "slot": slot, "empty": false, "ok": false, "reason": "存档损坏", "meta": {} }
	var ins: Dictionary = SaveCodec.inspect(d)
	ins["slot"] = slot
	ins["empty"] = false
	return ins


## 是否有任何非空槽位（标题「继续对局」可用性；含损坏档——进列表页可删）。
static func has_any() -> bool:
	for i in range(1, SLOT_N + 1):
		if not slot_info(i).get("empty", true):
			return true
	return false


## 读槽位 meta（读档还原 run_index 用；失败回 {}）。
static func slot_meta(slot: int) -> Dictionary:
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var d = _parse_json(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var m = d.get("meta", {})
	return m if typeof(m) == TYPE_DICTIONARY else {}


## 写档（补保存时间戳 + 战争迷雾位图旁路字段；成功返回 true）。
## fog_bits 为空（探针关雾）时不写该键——读档侧按现存实体重推导探索记忆。
## 迷雾是纯视图层状态：走 JSON 旁路键，不进 sim/save.gd 编码与 schema。
static func save_slot(slot: int, world: World, run_index: int, fog_bits: PackedByteArray = PackedByteArray()) -> bool:
	var d := SaveCodec.encode(world, run_index)
	var m: Dictionary = d["meta"]
	m["saved_at"] = int(Time.get_unix_time_from_system())
	m["saved_text"] = Time.get_datetime_string_from_system(false, true).substr(5, 11) # "10-16 14:30"
	if fog_bits.size() > 0:
		d["fog_b64"] = Marshalls.raw_to_base64(fog_bits)
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	return true


## 读档（返回 World；坏档/旧档/不存在 = null）。
static func load_slot(slot: int) -> World:
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	return SaveCodec.decode(_parse_json(txt))


## 读槽位的战争迷雾位图（fog_b64 旁路字段；无/坏 = 空数组，读档侧按现存实体重推导）。
static func slot_fog(slot: int) -> PackedByteArray:
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var txt := f.get_as_text()
	f.close()
	var d = _parse_json(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return PackedByteArray()
	var b64 = d.get("fog_b64", "")
	if typeof(b64) != TYPE_STRING or b64 == "":
		return PackedByteArray()
	return Marshalls.base64_to_raw(b64)


## 删除槽位文件（不存在 = 无操作）。
static func delete_slot(slot: int) -> void:
	var p := slot_path(slot)
	if FileAccess.file_exists(p):
		DirAccess.open("user://").remove("save_slot%d.json" % slot)
