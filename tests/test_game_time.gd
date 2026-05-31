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
