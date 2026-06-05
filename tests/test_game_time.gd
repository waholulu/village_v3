extends GutTest

var gt: GameTime

func before_each() -> void:
	gt = add_child_autoqfree(GameTime.new())
	gt.setup(10.0, 5.0, 5)

func test_starts_as_day() -> void:
	assert_eq(gt.phase, GameTime.Phase.DAY)

func test_starts_on_day_1() -> void:
	assert_eq(gt.day, 1)

func test_advance_day_to_night() -> void:
	gt._advance_phase()
	assert_eq(gt.phase, GameTime.Phase.NIGHT)

func test_day_does_not_increment_on_night_transition() -> void:
	gt._advance_phase()
	assert_eq(gt.day, 1)

func test_advance_night_to_next_day() -> void:
	gt._advance_phase()
	gt._advance_phase()
	assert_eq(gt.phase, GameTime.Phase.DAY)
	assert_eq(gt.day, 2)

func test_day_increments_each_full_cycle() -> void:
	for i in range(6):
		gt._advance_phase()
	assert_eq(gt.day, 4)

func test_night_started_signal_emitted() -> void:
	watch_signals(gt)
	gt._advance_phase()
	assert_signal_emitted(gt, "night_started")

func test_day_started_signal_emitted_on_second_day() -> void:
	watch_signals(gt)
	gt._advance_phase()
	gt._advance_phase()
	assert_signal_emitted(gt, "day_started")

func test_season_changed_signal_emitted_on_summer() -> void:
	watch_signals(gt)
	# 10 advances: 5 night+day pairs → day 6 → season becomes Summer
	for i in range(10):
		gt._advance_phase()
	assert_signal_emitted(gt, "season_changed")
	assert_eq(gt.current_season, GameTime.Season.SUMMER)

func test_winter_season_at_day_16() -> void:
	# days_per_season=5: Winter starts at day 16 (season index 3)
	for i in range(30):  # 15 night+day pairs → day 16
		gt._advance_phase()
	assert_eq(gt.current_season, GameTime.Season.WINTER)

func test_get_phase_name_day() -> void:
	assert_eq(gt.get_phase_name(), "Day")

func test_get_phase_name_night() -> void:
	gt._advance_phase()
	assert_eq(gt.get_phase_name(), "Night")

func test_clock_label_starts_at_six() -> void:
	assert_eq(gt.get_clock_label(), "06:00")
	assert_eq(gt.get_day_clock_label(), "Day 1 - Spring 06:00")

func test_clock_label_noon_halfway_through_day() -> void:
	gt._process(5.0)
	assert_eq(gt.get_clock_label(), "12:00")

func test_clock_label_night_starts_at_eighteen() -> void:
	gt._advance_phase()
	assert_eq(gt.get_clock_label(), "18:00")

func test_clock_label_wraps_after_midnight() -> void:
	gt._advance_phase()
	gt._process(2.5)
	assert_eq(gt.get_clock_label(), "00:00")

func test_clock_changed_signal_emitted_when_minute_changes() -> void:
	watch_signals(gt)
	gt._process(0.02)
	assert_signal_emitted(gt, "clock_changed")

func test_restore_state_preserves_clock_progress_and_derives_season() -> void:
	gt.restore_state(16, GameTime.Phase.NIGHT, 42, 2.5)
	assert_eq(gt.day, 16)
	assert_eq(gt.phase, GameTime.Phase.NIGHT)
	assert_eq(gt.tick, 42)
	assert_eq(gt.current_season, GameTime.Season.WINTER)
	assert_eq(gt.get_phase_elapsed_seconds(), 2.5)
	assert_eq(gt.get_clock_label(), "00:00")
