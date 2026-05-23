class_name ResourceStore
extends RefCounted

signal stock_changed(resource_name: String, amount: int)

var _resources: Dictionary = {"wood": 0, "food": 0}

func setup(wood: int, food: int) -> void:
	_resources["wood"] = wood
	_resources["food"] = food

func add_resource(type: String, amount: int) -> void:
	_resources[type] = _resources.get(type, 0) + amount
	stock_changed.emit(type, _resources[type])

func consume_resource(type: String, amount: int) -> int:
	var available: int = _resources.get(type, 0)
	var consumed: int = mini(available, amount)
	_resources[type] = available - consumed
	stock_changed.emit(type, _resources[type])
	return consumed

func get_resource(type: String) -> int:
	return _resources.get(type, 0)

func has_enough(type: String, amount: int) -> bool:
	return _resources.get(type, 0) >= amount
