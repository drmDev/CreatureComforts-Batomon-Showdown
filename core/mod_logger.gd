extends RefCounted
## Session log file and log-line helpers for Creature Comforts.
##
## Extracted from mod_main.gd. Owns the open FileAccess handle, the startup
## banner, and the dev flags (Debug Logging / Deep Inspection) so collaborators
## can read them without mod_main passing booleans around.
##
## The log file is optional: when it cannot be opened, every log call no-ops and
## the UI still runs.

const DevConfig = preload("../dev/dev_config.gd")

const OUTPUT_DIR := "user://creature_comforts"
const LOG_FILE := "inspect.log"

var debug_logging := DevConfig.DEBUG_LOGGING
var deep_inspection := DevConfig.DEEP_INSPECTION

var _formatter = null
var _log_path := ""
var _log_file: FileAccess = null  # Kept open for the session; avoids open/close per line


func _init(formatter) -> void:
	_formatter = formatter


## Create the output directory and open the append handle, then write the
## startup banner. Returns the absolute log path on success, or "" when the log
## could not be opened.
func open(version: String) -> String:
	var dir_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_error("Creature Comforts: Failed to create directory %s: %s" % [dir_path, error_string(dir_result)])
		return ""

	_log_path = OUTPUT_DIR.path_join(LOG_FILE)
	var abs_log_path := ProjectSettings.globalize_path(_log_path)

	if not FileAccess.file_exists(_log_path):
		var file := FileAccess.open(_log_path, FileAccess.WRITE)
		if file == null:
			push_error("Creature Comforts: Cannot create log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
			return ""
		file.close()

	# Keep one append handle open for the session instead of reopening per line.
	_log_file = FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if _log_file == null:
		push_error("Creature Comforts: Cannot open log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
		return ""
	_log_file.seek_end()

	log_message("=".repeat(80))
	log_message("Creature Comforts %s " % version)
	log_message("Initialized at %s" % get_timestamp())
	log_message("Dev toggles: Debug Logging: %s | Deep Inspection: %s" % [debug_logging, deep_inspection])
	log_message("Log file: %s" % abs_log_path)
	log_message("=".repeat(80))
	return abs_log_path


func close() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null


func log_message(message: String) -> void:
	if _log_file == null:
		return
	_log_file.store_line(message)
	_log_file.flush()


func log_event(message: String) -> void:
	log_message("[%s] %s" % [get_time_short(), message])


func print_notice(message: String) -> void:
	print(message)
	log_message(message)


func log_lines(lines: Array) -> void:
	for line in lines:
		log_message(line)


## Log added/changed/removed entries between two keyed display maps (key -> log text).
func log_keyed_changes(prefix: String, previous: Dictionary, current: Dictionary) -> void:
	for key in current.keys():
		var text := str(current[key])
		if not previous.has(key):
			log_event("%s ADDED | %s" % [prefix, text])
		elif str(previous[key]) != text:
			log_event("%s UPDATED | %s" % [prefix, text])
	for key in previous.keys():
		if not current.has(key):
			log_event("%s REMOVED | %s" % [prefix, key])


func get_timestamp() -> String:
	return _formatter.get_timestamp()


func get_time_short() -> String:
	return _formatter.get_time_short()
