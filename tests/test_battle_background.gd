extends "test_runner.gd"

const BattleBackground = preload("../core/battle_background.gd")


class FakeView:
	extends RefCounted
	var early_map_scenes := []
	var mid_map_scenes := []
	var champ_map_scenes := []


func test_returns_a_view_scene() -> void:
	var view := FakeView.new()
	var early := PackedScene.new()
	view.early_map_scenes = [early]
	assert_eq(BattleBackground.scene_for(view), early)


func test_returns_a_mid_scene() -> void:
	var view := FakeView.new()
	var mid := PackedScene.new()
	view.mid_map_scenes = [mid]
	assert_eq(BattleBackground.scene_for(view), mid)


func test_returns_a_champ_scene() -> void:
	var view := FakeView.new()
	var champ := PackedScene.new()
	view.champ_map_scenes = [champ]
	assert_eq(BattleBackground.scene_for(view), champ)


func test_random_selection_returns_a_candidate() -> void:
	var view := FakeView.new()
	var a := PackedScene.new()
	var b := PackedScene.new()
	view.early_map_scenes = [a, b]
	for i in range(20):
		var result := BattleBackground.scene_for(view)
		assert_true(result == a or result == b)


func test_missing_view_returns_null() -> void:
	assert_eq(BattleBackground.scene_for(null), null)


func test_empty_view_returns_null() -> void:
	assert_eq(BattleBackground.scene_for(FakeView.new()), null)
