extends "test_runner.gd"
## Unit tests for core/shop_income.gd.

const ShopIncome = preload("../core/shop_income.gd")


func test_day_one_is_base_income() -> void:
	assert_eq(ShopIncome.compute(1), 35)


func test_income_grows_per_day() -> void:
	assert_eq(ShopIncome.compute(2), 40)
	assert_eq(ShopIncome.compute(5), 55)


func test_day_zero_clamps_to_base() -> void:
	assert_eq(ShopIncome.compute(0), 35)
	assert_eq(ShopIncome.compute(-3), 35)


func test_passive_bonuses_are_added() -> void:
	assert_eq(ShopIncome.compute(1, [5, 10]), 50)


func test_empty_passives_are_ignored() -> void:
	assert_eq(ShopIncome.compute(3, []), 45)
