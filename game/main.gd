extends Node3D

# 《改道》Godot 版主循环（移植 reroute/scripts/main.lua 的轻量档）。
# 20Hz 固定步长模拟（tick 语义同 warden 切片）+ 渲染帧同步。
# R1 范围：tick 推进 + 视图同步；输入/HUD/三屏/音频见后续轮。

const Blueprint = preload("res://game/blueprint.gd")

const TICK_DT := 1.0 / 20.0
const MAX_CATCHUP := 5 # 单帧最多补的 tick 数（追平上限，超出丢弃积压）
const BASE_SEED := 20261003

var view = null # View（preload 脚本实例）；动态引用（脚本未 class_name）
var world: World = null
var sc: Scenario = null
var run_index := 0
var acc := 0.0
var paused := true # R1 新局即跑（标题屏 R6 接入后恢复"启动即暂停"口径）
var time_scale := 1.0


func _ready() -> void:
	view = $View
	new_game()
	paused = false


func new_game() -> void:
	run_index += 1
	sc = Scenario.new()
	var picked: Array = Blueprint.pick(run_index)
	view.apply_blueprint(picked[0], picked[1])
	world = World.new(sc, BASE_SEED + run_index)
	view.is_ore = Callable(sc, "is_ore")
	view.build_terrain(world.grid)
	view.sync(world)
	acc = 0.0
	print("[Game] 新对局 run=", run_index, " seed=", BASE_SEED + run_index)


func _process(dt: float) -> void:
	if world == null:
		return
	if world.outcome == World.RUNNING and not paused:
		acc += dt * time_scale
		var steps := 0
		while acc >= TICK_DT and steps < MAX_CATCHUP:
			world.tick()
			acc -= TICK_DT
			steps += 1
		if steps == MAX_CATCHUP:
			acc = 0.0
	view.sync(world)
