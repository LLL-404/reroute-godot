extends ProbeKit

# 蓝图动机池验收（G2 V2）：六预设结构完备 / 组合采样有限 / 配色与形貌两两可辨 /
# run_index 轮换口径（前三维不变、模 6 循环）/ 组合确定性 /
# 拍2 视觉联动锚点面（岩野山体 ridge_pts / ridge_off / 2D 盆地 / 四侧出怪口 gate_pts）。
# 判定：exit 0 + stdout 含 `[BLUEPRINT] PASS`。

const Blueprint = preload("res://game/blueprint.gd")
const SAMPLE_N := 17 # 世界坐标 -32..32 步长 4


func _initialize() -> void:
	check(Blueprint.ORDER.size() == 6, "ORDER size 6")
	var names: Array = Blueprint.ORDER
	check(names[0] == "canyon" and names[1] == "shale" and names[2] == "ember", "前三序位不变（run1..3 口径冻结）")
	var uniq := {}
	for n in names:
		uniq[n] = true
	check(uniq.size() == 6, "预设名唯一")

	var palettes := {}
	var shapes := {}
	var all_ok := true
	for n in names:
		var bp: Dictionary = Blueprint.get_preset(n)
		var keys_ok: bool = bp.has("schema") and bp.has("landmarks") and bp.has("world") and bp.has("micro") and bp.has("palette")
		var kinds := {}
		for lm in bp["landmarks"]:
			kinds[lm["kind"]] = true
		if not keys_ok or not (kinds.has("ridge") and kinds.has("basin") and kinds.has("peak")):
			all_ok = false
		var pal: Dictionary = bp["palette"]
		for ck in ["ground_lo", "ground", "ground_hi", "rock", "fog"]:
			var c: Array = pal[ck]
			if c.size() != 3:
				all_ok = false
				continue
			for v in c:
				if float(v) < 0.0 or float(v) > 1.0:
					all_ok = false
		var comp: Array = Blueprint.compose(bp, 12345, {})
		var h_fn: Callable = comp[0]
		var hs := PackedFloat32Array()
		var finite := true
		for i in SAMPLE_N:
			for j in SAMPLE_N:
				var v := float(h_fn.call(-32.0 + i * 4.0, -32.0 + j * 4.0))
				if not is_finite(v):
					finite = false
				hs.append(v)
		if not finite:
			all_ok = false
		palettes[n] = [float(pal["ground"][0]), float(pal["ground"][1]), float(pal["ground"][2])]
		shapes[n] = hs
	check(all_ok, "六预设结构/配色域/组合采样有限")

	var pal_min := 9.0
	var shp_min := 9.0
	var pal_pair := ""
	var shp_pair := ""
	var new_set := { "ochre": true, "slate": true, "dusk": true }
	for a in names.size():
		for b in range(a + 1, names.size()):
			var na: String = names[a]
			var nb: String = names[b]
			# 旧三角（canyon/shale/ember）互为同系变奏（ember 本就是 canyon 的暖红重调），
			# 互辨阈值只对新预设参与的配对生效；新预设对任一预设都必须可辨。
			if not (new_set.has(na) or new_set.has(nb)):
				continue
			var pa: Array = palettes[na]
			var pb: Array = palettes[nb]
			var pd := (absf(pa[0] - pb[0]) + absf(pa[1] - pb[1]) + absf(pa[2] - pb[2])) / 3.0
			if pd < pal_min:
				pal_min = pd
				pal_pair = na + "/" + nb
			var sa: PackedFloat32Array = shapes[na]
			var sb: PackedFloat32Array = shapes[nb]
			var sd := 0.0
			for i in sa.size():
				sd += absf(sa[i] - sb[i])
			sd /= float(sa.size())
			if sd < shp_min:
				shp_min = sd
				shp_pair = na + "/" + nb
	check(pal_min >= 0.05, "配色两两可辨（min %.3f @%s）" % [pal_min, pal_pair])
	check(shp_min >= 0.05, "形貌两两可辨（min %.3f @%s）" % [shp_min, shp_pair])

	# 轮换口径：pick(1)=canyon、pick(4)=ochre、pick(6)=dusk、pick(7) 回到 canyon
	check(str(Blueprint.pick(1)[0]["name"]) == "canyon", "pick(1) canyon")
	check(str(Blueprint.pick(4)[0]["name"]) == "ochre", "pick(4) ochre")
	check(str(Blueprint.pick(6)[0]["name"]) == "dusk", "pick(6) dusk")
	check(str(Blueprint.pick(7)[0]["name"]) == "canyon", "pick 模 6 循环")

	# ---- 拍2 视觉联动锚点面（自由路径）：岩野山体 / 2D 盆地 / 四侧出怪口豁口 ----
	check(Blueprint.gate_side(0.0, 28.0) == 0 and Blueprint.gate_side(0.0, -28.0) == 1
		and Blueprint.gate_side(28.0, 0.0) == 2 and Blueprint.gate_side(-28.0, 0.0) == 3, "侧别分类 南/北/东/西")
	var bp: Dictionary = Blueprint.get_preset("canyon")
	var base: Callable = Blueprint.compose(bp, 4242, {})[0]
	# 岩野山体：聚类点抬高、远点逐位不变；ridge_off 关闭预设岩脊条带
	var with_rp: Callable = Blueprint.compose(bp, 4242, { "ridge_off": true, "ridge_pts": [[0.0, 0.0, 3.0, 1.5]] })[0]
	check(float(with_rp.call(0.0, 0.0)) > float(base.call(0.0, 0.0)) + 0.2, "ridge_pts 山包抬高")
	check(absf(float(with_rp.call(25.0, -25.0)) - float(base.call(25.0, -25.0))) < 1e-9, "ridge_pts 远点不变")
	var off: Callable = Blueprint.compose(bp, 4242, { "ridge_off": true })[0]
	check(float(off.call(0.0, 9.5)) < float(base.call(0.0, 9.5)) - 0.1, "ridge_off 关闭预设岩脊")
	# 2D 盆地：中心凹陷；同 z 远端不再吃 z 向条带
	var b2: Callable = Blueprint.compose(bp, 4242, { "basin_wx": -11.5, "basin_wz": -1.5, "basin_sig": 4.0 })[0]
	check(float(b2.call(-11.5, -1.5)) < float(base.call(-11.5, -1.5)) - 0.5, "2D 盆地中心凹陷")
	check(absf(float(b2.call(20.0, -1.5)) - float(base.call(20.0, -1.5))) < 0.1, "2D 盆地无横贯条带")
	# 四侧出怪口：同点南北/东西锚互比（环山体豁口只开在口所在侧）
	var a_s: Callable = Blueprint.compose(bp, 4242, { "gate_pts": [Vector2(0.0, 28.0)] })[0]
	var a_n: Callable = Blueprint.compose(bp, 4242, { "gate_pts": [Vector2(0.0, -28.0)] })[0]
	check(float(a_s.call(0.0, 42.0)) < float(a_n.call(0.0, 42.0)) - 0.2, "南口豁开（北口锚不误开）")
	check(float(a_n.call(0.0, -42.0)) < float(a_s.call(0.0, -42.0)) - 0.2, "北口豁开（南口锚不误开）")
	var a_e: Callable = Blueprint.compose(bp, 4242, { "gate_pts": [Vector2(28.0, 0.0)] })[0]
	var a_w: Callable = Blueprint.compose(bp, 4242, { "gate_pts": [Vector2(-28.0, 0.0)] })[0]
	check(float(a_e.call(42.0, 0.0)) < float(a_w.call(42.0, 0.0)) - 0.2, "东口豁开（西口锚不误开）")
	check(float(a_w.call(-42.0, 0.0)) < float(a_e.call(-42.0, 0.0)) - 0.2, "西口豁开（东口锚不误开）")

	# 确定性：同预设同种子两次组合逐样本一致（同容器逐位比较，规避 f32/f64 截断假阴性）
	var comp2: Array = Blueprint.compose(Blueprint.get_preset("dusk"), 12345, {})
	var h2: Callable = comp2[0]
	var det := true
	var again := PackedFloat32Array()
	for i in SAMPLE_N:
		for j in SAMPLE_N:
			again.append(float(h2.call(-32.0 + i * 4.0, -32.0 + j * 4.0)))
	check(again == shapes["dusk"], "组合确定性")

	finish("BLUEPRINT", 21, "pal_min=%.3f@%s shp_min=%.3f@%s" % [pal_min, pal_pair, shp_min, shp_pair])
