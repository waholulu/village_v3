extends GutTest

var store: ResourceStore

func before_each() -> void:
	store = ResourceStore.new()
	store.setup(10, 8)

func test_initial_wood_is_set() -> void:
	assert_eq(store.get_resource("wood"), 10)

func test_initial_food_is_set() -> void:
	assert_eq(store.get_resource("food"), 8)

func test_add_wood() -> void:
	store.add_resource("wood", 5)
	assert_eq(store.get_resource("wood"), 15)

func test_consume_resource_returns_amount_consumed() -> void:
	var consumed = store.consume_resource("wood", 3)
	assert_eq(consumed, 3)

func test_consume_resource_reduces_stock() -> void:
	store.consume_resource("wood", 3)
	assert_eq(store.get_resource("wood"), 7)

func test_resource_never_negative() -> void:
	store.consume_resource("wood", 999)
	assert_eq(store.get_resource("wood"), 0)

func test_consume_more_than_available_returns_actual_consumed() -> void:
	var consumed = store.consume_resource("wood", 20)
	assert_eq(consumed, 10)

func test_has_enough_true() -> void:
	assert_true(store.has_enough("wood", 10))

func test_has_enough_false() -> void:
	assert_false(store.has_enough("wood", 11))

func test_stock_changed_signal_emitted_on_add() -> void:
	watch_signals(store)
	store.add_resource("food", 2)
	assert_signal_emitted(store, "stock_changed")

func test_stock_changed_signal_emitted_on_consume() -> void:
	watch_signals(store)
	store.consume_resource("food", 1)
	assert_signal_emitted(store, "stock_changed")
