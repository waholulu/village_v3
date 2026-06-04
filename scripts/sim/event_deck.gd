class_name EventDeck
extends RefCounted

const CATEGORIES := [
	"weather",
	"beasts",
	"disease",
	"food",
	"villager_conflict",
]

var events: Array[Dictionary] = []
var _events_by_id: Dictionary = {}

func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("EventDeck: file not found at " + path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("EventDeck: JSON parse error in " + path)
		return false
	var data = json.get_data()
	var raw_events: Array = []
	if data is Dictionary:
		raw_events = data.get("events", [])
	elif data is Array:
		raw_events = data
	else:
		push_error("EventDeck: expected an array or { events: [...] } in " + path)
		return false
	events.clear()
	_events_by_id.clear()
	for item in raw_events:
		if item is Dictionary:
			var event: Dictionary = item.duplicate(true)
			events.append(event)
			_events_by_id[event.get("id", "")] = event
	var errors := validate()
	for error in errors:
		push_warning("EventDeck: %s" % error.get("message", "invalid event deck"))
	return errors.is_empty()

func validate() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var ids := {}
	var category_counts := {}
	for category in CATEGORIES:
		category_counts[category] = 0
	if events.size() != 25:
		errors.append(_error("deck_size", "Event deck must contain exactly 25 cards."))
	for event in events:
		var id: String = str(event.get("id", ""))
		var category: String = str(event.get("category", ""))
		if id == "":
			errors.append(_error("missing_id", "Event is missing an id."))
		elif ids.has(id):
			errors.append(_error("duplicate_id", "Duplicate event id: " + id))
		ids[id] = true
		if not category in CATEGORIES:
			errors.append(_error("bad_category", "Event %s has invalid category %s." % [id, category]))
		else:
			category_counts[category] += 1
		if str(event.get("title", "")) == "":
			errors.append(_error("missing_title", "Event %s is missing a title." % id))
		if str(event.get("text", "")) == "":
			errors.append(_error("missing_text", "Event %s is missing text." % id))
		if int(event.get("weight", 0)) <= 0:
			errors.append(_error("bad_weight", "Event %s must have positive weight." % id))
		var options: Array = event.get("options", [])
		if options.size() < 2 or options.size() > 3:
			errors.append(_error("bad_option_count", "Event %s must have 2 or 3 options." % id))
		for option in options:
			_validate_option(errors, id, option)
	for category in CATEGORIES:
		if int(category_counts[category]) != 5:
			errors.append(_error("bad_category_count", "Category %s must contain exactly 5 cards." % category))
	return errors

func get_event(id: String) -> Dictionary:
	if not _events_by_id.has(id):
		return {}
	return (_events_by_id[id] as Dictionary).duplicate(true)

func draw_for_day(seed: int, day: int, active_effects: Array[Dictionary]) -> Dictionary:
	if events.is_empty():
		return {}
	var weighted: Array[Dictionary] = []
	var total_weight := 0
	for event in events:
		var weight := _modified_event_weight(event, day, active_effects)
		if weight <= 0:
			continue
		weighted.append({
			"event": event,
			"weight": weight,
		})
		total_weight += weight
	if total_weight <= 0:
		return {}
	var roll: int = _hash_roll("event_draw:%d:%d" % [seed, day], total_weight)
	var cursor := 0
	for entry in weighted:
		cursor += int(entry["weight"])
		if roll < cursor:
			return (entry["event"] as Dictionary).duplicate(true)
	return (weighted[weighted.size() - 1]["event"] as Dictionary).duplicate(true)

func _validate_option(errors: Array[Dictionary], event_id: String, option) -> void:
	if not option is Dictionary:
		errors.append(_error("bad_option", "Event %s has a non-dictionary option." % event_id))
		return
	var opt: Dictionary = option
	var option_id: String = str(opt.get("id", ""))
	if option_id == "":
		errors.append(_error("missing_option_id", "Event %s has an option without id." % event_id))
	if str(opt.get("label", "")) == "":
		errors.append(_error("missing_option_label", "Event %s option %s is missing a label." % [event_id, option_id]))
	if str(opt.get("result_text", "")) == "":
		errors.append(_error("missing_result_text", "Event %s option %s is missing result text." % [event_id, option_id]))
	var immediate: Array = opt.get("immediate", [])
	if immediate.is_empty():
		errors.append(_error("missing_immediate", "Event %s option %s needs at least one immediate effect." % [event_id, option_id]))
	if opt.has("short_term") and opt["short_term"] != null and not opt["short_term"] is Dictionary:
		errors.append(_error("bad_short_term", "Event %s option %s short_term must be null or one dictionary." % [event_id, option_id]))

func _modified_event_weight(event: Dictionary, day: int, active_effects: Array[Dictionary]) -> int:
	var weight := float(event.get("weight", 0))
	var category: String = str(event.get("category", ""))
	for effect in active_effects:
		if str(effect.get("type", "")) != "event_weight_multiplier":
			continue
		if not _effect_is_active(effect, day):
			continue
		var effect_category: String = str(effect.get("category", "all"))
		if effect_category != "all" and effect_category != category:
			continue
		weight *= float(effect.get("multiplier", 1.0))
	return maxi(0, int(round(weight)))

func _effect_is_active(effect: Dictionary, day: int) -> bool:
	return int(effect.get("remaining_days", 0)) > 0 and int(effect.get("starts_on_day", 1)) <= day

func _hash_roll(value: String, modulo: int) -> int:
	if modulo <= 0:
		return 0
	return absi(value.hash()) % modulo

func _error(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
