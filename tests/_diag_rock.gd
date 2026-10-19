extends SceneTree

# 临时诊断（拍2）：岩群/微丘分布 ASCII + 候选山体聚类（bucket 8×8）。
# 跑法：GODOT --headless --path P -s res://tests/_diag_rock.gd

const ScenarioScript = preload("res://sim/scenario.gd")

const CHARS := " .:-=+*#%@"


func _initialize() -> void:
	var seeds := [20261004, 20261005, 20261006, 20261007, 20261012]
	for s in seeds:
		var sc = ScenarioScript.new(s)
		print("=== seed %d ff=%s core=%s spawns=%s basin=%s rocks=%d hills=%d sparse=%d" % [
			s, str(sc._freeform), str(sc.core), str(sc.spawns), str(sc.basin_rect),
			sc._rock_arr.size(), sc._hill_arr.size(), sc._sparse_arr.size()])
		_dump(sc, sc._rock, "ROCK")
		_dump(sc, sc._hill, "HILL")
		_clusters(sc, sc._rock_arr, "rock")
		_clusters(sc, sc._hill_arr, "hill")
	quit()


func _dump(sc, table: Dictionary, tag: String) -> void:
	print("--- %s 16x16 (4x4 cells/char)" % tag)
	for by in 16:
		var line := ""
		for bx in 16:
			var n := 0
			for dy in 4:
				for dx in 4:
					var x := bx * 4 + dx
					var y := by * 4 + dy
					if table.has(str(x) + "," + str(y)):
						n += 1
			line += CHARS[clampi(n, 0, 9)]
		print(line)


func _clusters(sc, arr: Array, tag: String) -> void:
	var b := {}
	for c in arr:
		var ci: Vector2i = c
		var key: int = (ci.x / 8) * 8 + (ci.y / 8)
		if not b.has(key):
			b[key] = [0, 0, 0]
		var t: Array = b[key]
		t[0] += 1
		t[1] += ci.x
		t[2] += ci.y
	var pts: Array = []
	var keys: Array = b.keys()
	keys.sort()
	for key in keys:
		var t: Array = b[key]
		if t[0] < 4:
			continue
		var cx := float(t[1]) / float(t[0])
		var cy := float(t[2]) / float(t[0])
		var wx := cx - 31.5 + 0.5 * (int(round(cy)) & 1)
		var wz := cy - 31.5
		pts.append([t[0], cx, cy, wx, wz])
	print("--- %s clusters n>=4: %d" % [tag, pts.size()])
	for p in pts:
		print("    n=%3d cell=(%.1f,%.1f) world=(%.1f,%.1f)" % [p[0], p[1], p[2], p[3], p[4]])
