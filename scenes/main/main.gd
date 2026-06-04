extends Node2D

const DisplayMetrics = preload("res://scripts/world/display_metrics.gd")
const TILE_SIZE = DisplayMetrics.TILE_SIZE
const HUD_HEIGHT := 112.0
const CAMERA_PAN_SPEED := 520.0
const CAMERA_ZOOMS := [Vector2.ONE, Vector2(2.0, 2.0)]
var GRID_WIDTH: int = WorldGenerator.WIDTH
var GRID_HEIGHT: int = WorldGenerator.HEIGHT

var _sim: VillageSimulation
var _tilemap: TileMapController
var _villager_view: VillagerView
var _wildlife_view: WildlifeView
var _feature_view: FeatureView
var _world_scene: Node2D
var _save_manager: SaveManager
var _camera: Camera2D
var _hud
var _dragging_camera := false
var _selected_tile: Vector2i = Vector2i(-1, -1)
var _has_selected_tile := false

func _ready() -> void:
	Engine.time_scale = 1.0
	var balance = BalanceData.new()
	balance.load_from_file("res://data/balance.json")

	var wg = WorldGenerator.new()
	wg.generate_from_balance(balance)

	var pf = PathfindingService.new()
	pf.setup(wg)

	var world_scene = preload("res://scenes/world/world.tscn").instantiate()
	_world_scene = world_scene
	# Offset world to leave room for HUD at top
	world_scene.position = Vector2(0, HUD_HEIGHT)
	add_child(world_scene)

	_tilemap = world_scene.get_node("TileMapController")
	_tilemap.setup(wg)
	_feature_view = world_scene.get_node("FeatureView")
	_feature_view.setup(wg)

	_sim = VillageSimulation.new()
	add_child(_sim)
	_sim.setup(balance, wg, pf)
	_sim.game_won.connect(_on_game_won)
	_sim.game_lost.connect(_on_game_lost)

	# Refresh exactly the changed tile when world_gen mutates (no full-grid scan).
	_sim.tile_changed.connect(_on_tile_changed)
	_sim.wildlife_changed.connect(_on_wildlife_changed)

	_villager_view = world_scene.get_node("VillagerView")
	_villager_view.setup(_sim.villagers)

	_wildlife_view = world_scene.get_node("WildlifeView")
	_wildlife_view.setup_animals([])
	_sim.wildlife_changed.emit(_sim.nature.get_animals_as_dicts() if _sim.nature else [])

	# Forward Events signals
	_sim.store.stock_changed.connect(_on_stock_changed)
	_sim.game_time.night_started.connect(Events.night_started.emit)
	_sim.game_time.day_started.connect(Events.day_started.emit)
	_sim.game_time.clock_changed.connect(_on_world_clock_changed)

	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	# hud.setup() wires all label updaters to sim signals internally — no
	# per-frame polling and no double-update from this caller.
	_hud.setup(_sim)
	_hud.enable_blocking_choices()

	var dbg = preload("res://scenes/ui/debug_overlay.tscn").instantiate()
	add_child(dbg)
	dbg.setup(_sim)

	_save_manager = SaveManager.new()
	_setup_camera()

func _on_tile_changed(pos: Vector2i, new_type: int) -> void:
	_tilemap.refresh_tile(pos, new_type)
	_feature_view.refresh_tile(pos, new_type)
	if _has_selected_tile and pos == _selected_tile:
		_refresh_selected_tile(true)

func _on_wildlife_changed(animals: Array[Dictionary]) -> void:
	_wildlife_view.setup_animals(animals)
	if _has_selected_tile:
		_refresh_selected_tile(true)

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
		if _hud != null and _hud.is_blocking() and event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
			return
		match event.keycode:
			KEY_1:
				_set_time_scale(1.0)
			KEY_2:
				_set_time_scale(2.0)
			KEY_3:
				_set_time_scale(4.0)
			KEY_4:
				_set_time_scale(10.0)
			KEY_F5:
				_save_manager.save(_sim)
			KEY_F9:
				if _save_manager.load_into(_sim):
					_hud.sync_after_load()
					_refresh_selected_tile(true)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_camera = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _hud == null or not _hud.is_screen_point_over_ui(event.position):
				_set_camera_zoom(2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _hud == null or not _hud.is_screen_point_over_ui(event.position):
				_set_camera_zoom(1)
	elif event is InputEventMouseMotion and _dragging_camera:
		_move_camera(-event.relative)

func _process(delta: float) -> void:
	if _has_selected_tile:
		_refresh_selected_tile()
	if _camera == null:
		return
	if _hud != null and _hud.is_blocking():
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
		_move_camera(direction.normalized() * CAMERA_PAN_SPEED * real_delta)

func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "WorldCamera"
	_camera.enabled = true
	_camera.zoom = CAMERA_ZOOMS[1]
	add_child(_camera)
	_camera.make_current()
	var campfire_center := Vector2(WorldGenerator.CAMPFIRE_POS) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	_camera.global_position = campfire_center + Vector2(0, HUD_HEIGHT)
	_clamp_camera()

func _move_camera(offset: Vector2) -> void:
	_camera.global_position += offset
	_clamp_camera()

func _clamp_camera() -> void:
	var viewport_size := get_viewport_rect().size
	var half_view := viewport_size * 0.5 / _camera.zoom
	var world_size := Vector2(WorldGenerator.WIDTH, WorldGenerator.HEIGHT) * TILE_SIZE
	var min_pos := Vector2(half_view.x, HUD_HEIGHT + half_view.y)
	var max_pos := Vector2(world_size.x - half_view.x, HUD_HEIGHT + world_size.y - half_view.y)
	if max_pos.x < min_pos.x:
		min_pos.x = world_size.x * 0.5
		max_pos.x = min_pos.x
	if max_pos.y < min_pos.y:
		min_pos.y = HUD_HEIGHT + world_size.y * 0.5
		max_pos.y = min_pos.y
	_camera.global_position = Vector2(
		clampf(_camera.global_position.x, min_pos.x, max_pos.x),
		clampf(_camera.global_position.y, min_pos.y, max_pos.y)
	)

func _set_time_scale(value: float) -> void:
	Engine.time_scale = value
	Events.speed_changed.emit(value)

func has_selected_tile() -> bool:
	return _has_selected_tile

func get_selected_tile() -> Vector2i:
	return _selected_tile

func _handle_left_click(screen_pos: Vector2) -> void:
	if not get_viewport_rect().has_point(screen_pos):
		_clear_selected_tile()
		return
	if _hud != null and _hud.is_screen_point_over_ui(screen_pos):
		return
	var tile := _screen_to_tile(screen_pos)
	if not _sim.world_gen.is_in_bounds(tile):
		_clear_selected_tile()
		return
	_select_tile(tile)

func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world_pos := get_canvas_transform().affine_inverse() * screen_pos
	var tile_local := _tilemap.to_local(world_pos)
	return Vector2i(floori(tile_local.x / float(TILE_SIZE)), floori(tile_local.y / float(TILE_SIZE)))

func _set_camera_zoom(multiplier: int) -> void:
	_camera.zoom = CAMERA_ZOOMS[1] if multiplier >= 2 else CAMERA_ZOOMS[0]
	_clamp_camera()

func get_camera_zoom_multiplier() -> int:
	return int(round(_camera.zoom.x)) if _camera != null else 1

func _on_world_clock_changed(_day: int, phase: GameTime.Phase, minute_of_day: int) -> void:
	if _world_scene == null:
		return
	if phase == GameTime.Phase.NIGHT:
		var midnight_distance := absf(float(minute_of_day - 1440 if minute_of_day > 720 else minute_of_day))
		var darkness := clampf(1.0 - midnight_distance / 720.0, 0.0, 1.0)
		_world_scene.modulate = Color(0.72, 0.78, 0.92).lerp(Color(0.48, 0.55, 0.78), darkness)
	else:
		_world_scene.modulate = Color.WHITE

func _select_tile(tile: Vector2i) -> void:
	_selected_tile = tile
	_has_selected_tile = true
	_tilemap.set_selected_tile(tile)
	_refresh_selected_tile(true)

func _clear_selected_tile() -> void:
	_has_selected_tile = false
	_selected_tile = Vector2i(-1, -1)
	_tilemap.clear_selected_tile()
	if _hud != null:
		_hud.clear_tile_inspector()

func _refresh_selected_tile(force: bool = false) -> void:
	if not _has_selected_tile or _hud == null:
		return
	var info := _sim.inspect_tile(_selected_tile)
	if not force and not info.get("in_bounds", false):
		return
	_hud.update_tile_inspector(info)
