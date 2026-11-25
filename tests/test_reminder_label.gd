extends "test_runner.gd"
## Headless tests for the combined day-reminder panel rendering.

const ReminderLabel = preload("../hud/reminder_label.gd")


func _label_text(panel) -> String:
	return str(panel.get_child(0).text)


func test_stacks_multiple_reminders_vertically() -> void:
	var panel = ReminderLabel.new()
	panel.set_reminders({"a": "First", "b": "Second"})
	assert_true(panel.visible)
	assert_eq(_label_text(panel), "First\nSecond")
	panel.free()


func test_deduplicates_identical_reminder_text() -> void:
	var panel = ReminderLabel.new()
	panel.set_reminders({"a": "Same", "b": "Same", "c": "Other"})
	assert_eq(_label_text(panel), "Same\nOther")
	panel.free()


func test_hides_when_no_reminders() -> void:
	var panel = ReminderLabel.new()
	panel.set_reminders({"a": "First"})
	panel.set_reminders({})
	assert_false(panel.visible)
	assert_eq(_label_text(panel), "")
	panel.free()


func test_sources_merge_and_clear_independently() -> void:
	var panel = ReminderLabel.new()
	panel.set_reminders({"a": "Advice"})
	panel.set_reminders({"strategy": "Strategy"}, "ratacomb_stoner")
	assert_eq(_label_text(panel), "Advice\nStrategy")
	# Replacing one source leaves the other visible.
	panel.set_reminders({"a": "Advice"}, ReminderLabel.SOURCE_ADVICE)
	assert_eq(_label_text(panel), "Advice\nStrategy")
	panel.clear_source("ratacomb_stoner")
	assert_true(panel.visible)
	assert_eq(_label_text(panel), "Advice")
	panel.clear_source(ReminderLabel.SOURCE_ADVICE)
	assert_false(panel.visible)
	panel.free()
