class_name EventEffects
extends RefCounted

static func apply_option(sim: VillageSimulation, event: Dictionary, option_id: String) -> Dictionary:
	var option := _find_option(event, option_id)
	if option.is_empty():
		return {
			"ok": false,
			"error": "unknown_option",
			"event_id": event.get("id", ""),
			"option_id": option_id,
		}
	var result := {
		"ok": true,
		"event_id": event.get("id", ""),
		"event_title": event.get("title", ""),
		"option_id": option_id,
		"option_label": option.get("label", ""),
		"result_text": option.get("result_text", ""),
		"effects": [],
		"short_term_started": {},
	}
	var immediate: Array = option.get("immediate", [])
	for i in range(immediate.size()):
		var effect = immediate[i]
		if effect is Dictionary:
			result["effects"].append(apply_immediate_effect(sim, effect, event, option_id, i))
	var short_term = option.get("short_term", null)
	if short_term is Dictionary and not (short_term as Dictionary).is_empty():
		var active: Dictionary = (short_term as Dictionary).duplicate(true)
		var duration := maxi(1, int(active.get("duration_days", 1)))
		active["duration_days"] = duration
		active["remaining_days"] = duration
		active["starts_on_day"] = _current_day(sim) + 1
		active["source_event_id"] = event.get("id", "")
		active["source_option_id"] = option_id
		active["source_title"] = event.get("title", "")
		sim.active_event_effects.append(active)
		result["short_term_started"] = active.duplicate(true)
	return result

static func apply_immediate_effect(sim: VillageSimulation, effect: Dictionary, event: Dictionary, option_id: String, effect_index: int = 0) -> Dictionary:
	var effect_type: String = str(effect.get("type", ""))
	match effect_type:
		"resource_delta":
			return _apply_resource_delta(sim, effect)
		"villager_status":
			return _apply_villager_status(sim, effect, event, option_id, effect_index)
		_:
			return {
				"type": effect_type,
				"applied": false,
				"reason": "unsupported_immediate_effect",
			}

static func output_multiplier(effects: Array[Dictionary], output_type: String, day: int) -> float:
	var multiplier := 1.0
	for effect in effects:
		if str(effect.get("type", "")) != "output_multiplier":
			continue
		if not effect_is_active(effect, day):
			continue
		var target: String = str(effect.get("output_type", "all"))
		if target == "all" or target == output_type:
			multiplier *= float(effect.get("multiplier", 1.0))
	return multiplier

static func modified_risk_chance(effects: Array[Dictionary], risk_type: String, base_chance: int, day: int) -> int:
	var chance := base_chance
	for effect in effects:
		if str(effect.get("type", "")) != "risk_delta":
			continue
		if not effect_is_active(effect, day):
			continue
		if str(effect.get("risk_type", "")) == risk_type:
			chance += int(effect.get("amount", 0))
	return clampi(chance, 0, 100)

static func effect_is_active(effect: Dictionary, day: int) -> bool:
	return int(effect.get("remaining_days", 0)) > 0 and int(effect.get("starts_on_day", 1)) <= day

static func _apply_resource_delta(sim: VillageSimulation, effect: Dictionary) -> Dictionary:
	var resource: String = str(effect.get("resource", ""))
	var amount := int(effect.get("amount", 0))
	if resource == "":
		return {
			"type": "resource_delta",
			"applied": false,
			"reason": "missing_resource",
		}
	var before := sim.store.get_resource(resource)
	sim.apply_strategic_resource_delta(resource, amount)
	return {
		"type": "resource_delta",
		"applied": true,
		"resource": resource,
		"amount": amount,
		"before": before,
		"after": sim.store.get_resource(resource),
	}

static func _apply_villager_status(sim: VillageSimulation, effect: Dictionary, event: Dictionary, option_id: String, effect_index: int) -> Dictionary:
	var status_name: String = str(effect.get("status", "healthy")).to_lower()
	var status := _status_from_name(status_name)
	if status < 0:
		return {
			"type": "villager_status",
			"applied": false,
			"reason": "unknown_status",
			"status": status_name,
		}
	var villagers := _select_villagers(sim, str(effect.get("target", "random_working")), event, option_id, effect_index)
	if villagers.is_empty():
		return {
			"type": "villager_status",
			"applied": false,
			"reason": "no_target",
			"status": status_name,
		}
	var changed: Array[Dictionary] = []
	for v in villagers:
		var villager: VillagerAgent = v
		var before := villager.get_status_name()
		_set_villager_status(sim, villager, status, "event:%s" % event.get("id", ""))
		changed.append({
			"id": villager.id,
			"name": villager.name,
			"before": before,
			"after": villager.get_status_name(),
		})
	return {
		"type": "villager_status",
		"applied": true,
		"target": effect.get("target", "random_working"),
		"status": status_name,
		"villagers": changed,
	}

static func _select_villagers(sim: VillageSimulation, target: String, event: Dictionary, option_id: String, effect_index: int) -> Array:
	var candidates: Array = []
	match target:
		"all_living":
			for v in sim.villagers:
				if v.status != VillagerAgent.Status.DEAD:
					candidates.append(v)
			return candidates
		"recoverable":
			for v in sim.villagers:
				if v.status == VillagerAgent.Status.INJURED or v.status == VillagerAgent.Status.SICK:
					candidates.append(v)
		"first_healthy":
			for v in sim.villagers:
				if v.status == VillagerAgent.Status.HEALTHY:
					return [v]
		"random_living":
			for v in sim.villagers:
				if v.status != VillagerAgent.Status.DEAD:
					candidates.append(v)
		_:
			for v in sim.villagers:
				if v.can_work():
					candidates.append(v)
	if candidates.is_empty():
		return []
	var seed := sim._balance.world_seed if sim._balance != null else 0
	var day := _current_day(sim)
	var key := "event_status:%d:%d:%s:%s:%d" % [seed, day, event.get("id", ""), option_id, effect_index]
	return [candidates[absi(key.hash()) % candidates.size()]]

static func _set_villager_status(sim: VillageSimulation, villager: VillagerAgent, status: int, reason: String) -> void:
	if status == VillagerAgent.Status.DEAD:
		sim.mark_villager_dead(villager, reason)
		return
	villager.status = status
	if not villager.can_work() and villager.current_task_id != -1 and sim.board != null:
		sim.board.cancel_task(villager.current_task_id)
		villager.clear_task()

static func _status_from_name(status_name: String) -> int:
	match status_name:
		"healthy":
			return VillagerAgent.Status.HEALTHY
		"tired":
			return VillagerAgent.Status.TIRED
		"injured":
			return VillagerAgent.Status.INJURED
		"sick":
			return VillagerAgent.Status.SICK
		"dead":
			return VillagerAgent.Status.DEAD
	return -1

static func _find_option(event: Dictionary, option_id: String) -> Dictionary:
	var options: Array = event.get("options", [])
	for option in options:
		if option is Dictionary and str(option.get("id", "")) == option_id:
			return (option as Dictionary).duplicate(true)
	return {}

static func _current_day(sim: VillageSimulation) -> int:
	return sim.game_time.day if sim != null and sim.game_time != null else 1
