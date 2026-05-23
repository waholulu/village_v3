extends Node2D

const TILE_SIZE = 48
const GRID_SIZE = 12

var _sim: VillageSimulation
var _tilemap: TileMapController
var _villager_view: VillagerView
var _save_manager: SaveManager

func _ready() -> void:
	var balance = BalanceData.new()
	balance.load_from_file("res://data/balance.json")

	var wg = WorldGenerator.new()
	wg.generate_fixed()

	var pf = PathfindingService.new()
	pf.setup(wg)

	var world_scene = preload("res://scenes/world/world.tscn").instantiate()
	# Offset world to leave room for HUD at top
	world_scene.position = Vector2(8, 60)
	add_child(world_scene)

	_tilemap = world_scene.get_node("TileMapController")
	_tilemap.setup(wg)

	_sim = VillageSimulation.new()
	add_child(_sim)
	_sim.setup(balance, wg, pf)
	_sim.game_won.connect(_on_game_won)
	_sim.game_lost.connect(_on_game_lost)

	# Refresh exactly the changed tile when world_gen mutates (no full-grid scan).
	_sim.tile_changed.connect(_on_tile_changed)

	_villager_view = world_scene.get_node("VillagerView")
	_villager_view.setup(_sim.villagers)

	# Forward Events signals
	_sim.store.stock_changed.connect(_on_stock_changed)
	_sim.game_time.night_started.connect(Events.night_started.emit)
	_sim.game_time.day_started.connect(Events.day_started.emit)

	var hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	hud.update_resources(balance.starting_wood, balance.starting_food)

	var dbg = preload("res://scenes/ui/debug_overlay.tscn").instantiate()
	add_child(dbg)
	dbg.setup(_sim)

	_save_manager = SaveManager.new()

func _on_tile_changed(pos: Vector2i, new_type: int) -> void:
	_tilemap.refresh_tile(pos, new_type)

func _on_stock_changed(resource_name: String, amount: int) -> void:
	Events.stock_changed.emit(resource_name, amount)

func _on_game_won() -> void:
	Events.game_won.emit()
	get_tree().paused = true

func _on_game_lost(reason: String) -> void:
	Events.game_lost.emit(reason)
	get_tree().paused = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F5:
				_save_manager.save(_sim)
			KEY_F9:
				_save_manager.load_into(_sim)
