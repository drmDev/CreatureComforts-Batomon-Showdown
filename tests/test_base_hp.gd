extends "test_runner.gd"
## Unit tests for core/base_hp.gd.

const BaseHp = preload("../core/base_hp.gd")

const EXPECTED := [
	300, 500, 800, 1400, 2400, 3800, 5700, 8300, 11600,
	17300, 24900, 34700, 47300, 63000, 82400, 106000, 134300,
]


func test_day_one_is_base_hp() -> void:
	assert_eq(BaseHp.for_day(1), 300)


func test_day_zero_and_negative_clamp_to_base() -> void:
	assert_eq(BaseHp.for_day(0), 300)
	assert_eq(BaseHp.for_day(-5), 300)


func test_provided_values_match() -> void:
	for i in range(EXPECTED.size()):
		assert_eq(BaseHp.for_day(i + 1), EXPECTED[i], "day %d" % (i + 1))


func test_late_multiplier_starts_on_day_ten() -> void:
	assert_eq(BaseHp.for_day(9), 11600)
	assert_eq(BaseHp.for_day(10), 17300)


func test_values_round_to_nearest_hundred() -> void:
	for day in range(1, BaseHp.MAX_DAY + 1):
		assert_eq(BaseHp.for_day(day) % 100, 0, "day %d" % day)


func test_bonus_is_total_minus_base() -> void:
	assert_eq(BaseHp.bonus(2000, 1), 1700)
	assert_eq(BaseHp.bonus(250, 1), 0, "never negative")


func test_with_bonus_adds_flat_bonus() -> void:
	assert_eq(BaseHp.with_bonus(1, 1700), 2000)
	assert_eq(BaseHp.with_bonus(2, 1700), 2200)
	assert_eq(BaseHp.with_bonus(2, -50), 500, "negative bonus ignored")
