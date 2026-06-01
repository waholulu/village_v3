class_name ResourceStore
extends RefCounted

signal stock_changed(resource_name: String, amount: int)

var _resources: Dictionary = {
	"population": 0,
	"food": 0,
	"wood": 0,
	"security": 0,
	"morale": 0,
	"fresh_food": 0,
	"stored_food": 0,
}

func setup(wood: int, fresh_food: int, stored_food: int) -> void:
	set_resource("wood", wood)
	_resources["fresh_food"] = maxi(0, fresh_food)
	_resources["stored_food"] = maxi(0, stored_food)
	_resources["food"] = get_total_food()
	_emit_food_changed()

func setup_strategic(population: int, food: int, wood: int, security: int, morale: int) -> void:
	set_resource("population", population)
	_set_food_total(food)
	set_resource("wood", wood)
	set_resource("security", security)
	set_resource("morale", morale)

func set_resource(type: String, amount: int) -> void:
	if type == "food":
		_set_food_total(amount)
		return
	if type == "fresh_food" or type == "stored_food":
		_resources[type] = maxi(0, amount)
		_resources["food"] = get_total_food()
		stock_changed.emit(type, _resources[type])
		stock_changed.emit("food", _resources["food"])
		return
	_resources[type] = maxi(0, amount)
	stock_changed.emit(type, _resources[type])

func add_resource(type: String, amount: int) -> void:
	if type == "food":
		add_stored_food(amount)
		return
	if type == "fresh_food":
		add_fresh_food(amount)
		return
	if type == "stored_food":
		add_stored_food(amount)
		return
	_resources[type] = maxi(0, _resources.get(type, 0) + amount)
	stock_changed.emit(type, _resources[type])

func consume_resource(type: String, amount: int) -> int:
	if type == "food":
		return consume_food(amount)["total"]
	if type == "fresh_food" or type == "stored_food":
		var available_food_bucket: int = _resources.get(type, 0)
		var consumed_food_bucket: int = mini(available_food_bucket, maxi(0, amount))
		_resources[type] = available_food_bucket - consumed_food_bucket
		_resources["food"] = get_total_food()
		stock_changed.emit(type, _resources[type])
		stock_changed.emit("food", _resources["food"])
		return consumed_food_bucket
	var available: int = _resources.get(type, 0)
	var consumed: int = mini(available, amount)
	_resources[type] = available - consumed
	stock_changed.emit(type, _resources[type])
	return consumed

func get_resource(type: String) -> int:
	return _resources.get(type, 0)

func get_total_food() -> int:
	return _resources.get("fresh_food", 0) + _resources.get("stored_food", 0)

func has_enough(type: String, amount: int) -> bool:
	return _resources.get(type, 0) >= amount

func add_fresh_food(amount: int) -> void:
	if amount <= 0:
		return
	_resources["fresh_food"] = _resources.get("fresh_food", 0) + amount
	_resources["food"] = get_total_food()
	stock_changed.emit("fresh_food", _resources["fresh_food"])
	stock_changed.emit("food", _resources["food"])

func add_stored_food(amount: int) -> void:
	if amount <= 0:
		return
	_resources["stored_food"] = _resources.get("stored_food", 0) + amount
	_resources["food"] = get_total_food()
	stock_changed.emit("stored_food", _resources["stored_food"])
	stock_changed.emit("food", _resources["food"])

func consume_food(amount: int, prefer_fresh: bool = true) -> Dictionary:
	var remaining: int = maxi(0, amount)
	var consumed_fresh := 0
	var consumed_stored := 0
	if prefer_fresh:
		consumed_fresh = _consume_food_bucket("fresh_food", remaining)
		remaining -= consumed_fresh
		consumed_stored = _consume_food_bucket("stored_food", remaining)
	else:
		consumed_stored = _consume_food_bucket("stored_food", remaining)
		remaining -= consumed_stored
		consumed_fresh = _consume_food_bucket("fresh_food", remaining)
	var total := consumed_fresh + consumed_stored
	_resources["food"] = get_total_food()
	if consumed_fresh > 0:
		stock_changed.emit("fresh_food", _resources["fresh_food"])
	if consumed_stored > 0:
		stock_changed.emit("stored_food", _resources["stored_food"])
	if total > 0 or amount > 0:
		stock_changed.emit("food", _resources["food"])
	return {
		"fresh": consumed_fresh,
		"stored": consumed_stored,
		"total": total,
	}

func spoil_fresh_food(amount: int) -> int:
	var consumed: int = _consume_food_bucket("fresh_food", maxi(0, amount))
	if consumed <= 0:
		return 0
	_resources["food"] = get_total_food()
	stock_changed.emit("fresh_food", _resources["fresh_food"])
	stock_changed.emit("food", _resources["food"])
	return consumed

func reconcile_food_buckets(authoritative_food: int) -> void:
	_set_food_total(authoritative_food)

func _consume_food_bucket(type: String, amount: int) -> int:
	var available: int = _resources.get(type, 0)
	var consumed: int = mini(available, amount)
	_resources[type] = available - consumed
	return consumed

func _set_food_total(amount: int) -> void:
	var total: int = maxi(0, amount)
	var fresh: int = mini(_resources.get("fresh_food", 0), total)
	_resources["fresh_food"] = fresh
	_resources["stored_food"] = total - fresh
	_resources["food"] = total
	_emit_food_changed()

func _emit_food_changed() -> void:
	stock_changed.emit("fresh_food", _resources["fresh_food"])
	stock_changed.emit("stored_food", _resources["stored_food"])
	stock_changed.emit("food", _resources["food"])
