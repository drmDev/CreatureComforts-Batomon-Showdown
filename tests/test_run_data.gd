extends "test_runner.gd"
## Unit tests for core/run_data.gd.

const RunData = preload("../core/run_data.gd")


class FakeRun:
	extends RefCounted
	var run_id := ""


class BareRun:
	extends RefCounted


func test_identity_prefers_run_id() -> void:
	var run := FakeRun.new()
	run.run_id = "run-123"
	assert_eq(RunData.identity(run), "run-123")


func test_identity_falls_back_to_instance_id_when_run_id_empty() -> void:
	var run := FakeRun.new()
	assert_eq(RunData.identity(run), str(run.get_instance_id()))


func test_identity_without_run_id_uses_instance_id() -> void:
	var run := BareRun.new()
	assert_eq(RunData.identity(run), str(run.get_instance_id()))


func test_identity_null_is_empty() -> void:
	assert_eq(RunData.identity(null), "")
