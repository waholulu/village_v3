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
	set_resource("fresh_food", fresh_food)
	set_resource("stored_food", stored_food)
	_resources["food"] = maxi(0, fresh_food + stored_food)

func setup_strategic(population: int, food: int, wood: int, security: int, morale: int) -> void:
	set_resource("population", population)
	set_resource("food", food)
	set_resource("wood", wood)
	set_resource("security", security)
	set_resource("morale", morale)

func set_resource(type: String, amount: int) -> void:
	_resources[type] = maxi(0, amount)
	stock_changed.emit(type, _resources[type])

func add_resource(type: String, amount: int) -> void:
	_resources[type] = maxi(0, _resources.get(type, 0) + amount)
	stock_changed.emit(type, _resources[type])

func consume_resource(type: String, amount: int) -> int:
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
