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
