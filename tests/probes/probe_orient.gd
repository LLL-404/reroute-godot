extends ProbeKit

# 朝向校准探针 v2（十字四向顶视）：四个单位按"游戏完整公式"摆位——
#   yaw = atan2(dx, dz) + Z_YAW（Z_YAW = PI/2，同 view.gd 常量）
# 分别朝东（+X）、南（+Z）、西（-X）、北（-Z）。相机顶视（画面↑=北、→=东）。
# 判定：图中每个单位的大钳应朝各自的移动方向（右 / 下 / 左 / 上）。
#       exit 0 + stdout 含 [ORIENT] PASS（机械部分：出帧成功）。

const ModelsScript = preload("res://game/models.gd")
const Z_YAW := PI / 2.0 # 同 view.Z_YAW


func _initialize() -> void:
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)

	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.6
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.21, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.62)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)

	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	plane.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.31, 0.34)
	plane.material_override = gm
	world.add_child(plane)

	var models = ModelsScript.new()
	# 东 / 南 / 西 / 北（dx, dz）
	var dirs := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	var offs := [Vector3(2.4, 0, 0), Vector3(0, 0, 2.4), Vector3(-2.4, 0, 0), Vector3(0, 0, -2.4)]
	for i in 4:
		var u: Dictionary = models.spawn_unit(world, 3) # king
		var node: Node3D = u["node"]
		node.position = offs[i]
		var d: Vector2 = dirs[i]
		node.rotation.y = atan2(d.x, d.y) + Z_YAW # 游戏完整公式
		models.play(u["player"], "Crawl", true)
	for _i in 30:
		await process_frame
	# 顶视：画面↑ = -Z（北）、画面→ = +X（东）
	cam.look_at_from_position(Vector3(0, 8.5, 0), Vector3.ZERO, Vector3(0, 0, -1))
	for _i in 10:
		await process_frame
	var img := root.get_texture().get_image()
	check(img != null, "取帧 orient_cross")
	if img != null:
		img.save_png("res://shots/orient_cross.png")
	print("[ORIENT] cross shot saved")
	finish("ORIENT")
