class_name AlertRules
extends RefCounted

const MAX_ALERTS := 4

static func build(
		snapshot: Dictionary,
		monitor_anomalies: Array[Dictionary] = [],
		activity_alerts: Array[Dictionary] = []) -> Array[Dictionary]:
	var alerts: Array[Dictionary] = []
	if snapshot.is_empty():
		return alerts
	alerts.append_array(activity_alerts)
	_add_population_alert(snapshot, alerts)
	_add_zero_resource_alerts(snapshot, alerts)
	_add_campfire_alert(snapshot, alerts)
	_add_shortfall_alerts(snapshot, alerts)
	_add_wolf_warning(snapshot, alerts)
	_add_monitor_alerts(monitor_anomalies, alerts)
	alerts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a := _severity_rank(String(a.get("severity", "warning")))
		var rank_b := _severity_rank(String(b.get("severity", "warning")))
		if rank_a == rank_b:
			return String(a.get("id", "")) < String(b.get("id", ""))
		return rank_a > rank_b
	)
	if alerts.size() > MAX_ALERTS:
		alerts.resize(MAX_ALERTS)
	return alerts

static func _add_population_alert(snapshot: Dictionary, alerts: Array[Dictionary]) -> void:
	var population := int(snapshot.get("population", 0))
	if population <= 1:
		alerts.append(_alert(
			"population_low",
			"critical",
			"Population critical",
			"%d villager(s) remain" % population
		))

static func _add_zero_resource_alerts(snapshot: Dictionary, alerts: Array[Dictionary]) -> void:
	var zero_streaks: Dictionary = snapshot.get("zero_streaks", {})
	var limit := int(snapshot.get("zero_resource_loss_days", 3))
	for resource_name in ["food", "morale", "security"]:
		var value_key: String = "strategic_food" if resource_name == "food" else resource_name
		if int(snapshot.get(value_key, 0)) > 0:
			continue
		var streak := int(zero_streaks.get(resource_name, 0))
		var days_left := maxi(1, limit - streak)
		var severity := "critical" if streak >= limit - 1 else "warning"
		alerts.append(_alert(
			"%s_zero" % resource_name,
			severity,
			"%s depleted" % resource_name.capitalize(),
			"Loss in %d daily resolution(s)" % days_left
		))

static func _add_campfire_alert(snapshot: Dictionary, alerts: Array[Dictionary]) -> void:
	var campfire_out := int(snapshot.get("campfire_out", 0))
	if campfire_out <= 0:
		return
	var limit := int(snapshot.get("max_campfire_out_nights", 5))
	var severity := "critical" if campfire_out >= limit - 1 else "warning"
	alerts.append(_alert(
		"campfire_out",
		severity,
		"Campfire out",
		"%d/%d consecutive night(s)" % [campfire_out, limit]
	))

static func _add_shortfall_alerts(snapshot: Dictionary, alerts: Array[Dictionary]) -> void:
	var risk: Dictionary = snapshot.get("risk", {})
	var food_shortfall := int(risk.get("food_shortfall", 0))
	if food_shortfall > 0 and int(snapshot.get("strategic_food", 0)) > 0:
		alerts.append(_alert(
			"food_shortfall",
			"critical",
			"Food shortfall",
			"%d missing for tonight" % food_shortfall
		))
	var wood_shortfall := int(risk.get("wood_shortfall", 0))
	if wood_shortfall > 0:
		alerts.append(_alert(
			"wood_shortfall",
			"warning",
			"Wood shortfall",
			"%d missing for tonight" % wood_shortfall
		))

static func _add_wolf_warning(snapshot: Dictionary, alerts: Array[Dictionary]) -> void:
	var nature: Dictionary = snapshot.get("nature", {})
	if int(snapshot.get("campfire_out", 0)) <= 0:
		return
	if int(nature.get("wolf_count", 0)) <= 0:
		return
	alerts.append(_alert(
		"wolf_near_cold_fire",
		"warning",
		"Wolves circling",
		"Cold fire increases threat"
	))

static func _add_monitor_alerts(monitor_anomalies: Array[Dictionary], alerts: Array[Dictionary]) -> void:
	for anomaly in monitor_anomalies:
		var severity := String(anomaly.get("severity", "warning"))
		alerts.append(_alert(
			"monitor_%s" % anomaly.get("code", "unknown"),
			"critical" if severity == "error" else "warning",
			"Simulation warning",
			String(anomaly.get("message", "Check debug overlay"))
		))

static func _alert(id: String, severity: String, title: String, message: String) -> Dictionary:
	return {
		"id": id,
		"severity": severity,
		"title": title,
		"message": message,
	}

static func _severity_rank(severity: String) -> int:
	match severity:
		"critical":
			return 3
		"warning":
			return 2
	return 1
