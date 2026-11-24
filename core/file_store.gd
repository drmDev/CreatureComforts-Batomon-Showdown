extends RefCounted
## Small filesystem helpers shared by the mod's persistence code.
##
## Every store in the mod (watchlist, Mod Volume, saved builds, updater state)
## needs the same two steps: create the parent directory, then write. Keeping
## them here means the error handling and the user:// globalize rule live in one
## place.

## Create the parent directory of `path`. ERR_ALREADY_EXISTS counts as success.
static func ensure_parent_dir(path: String) -> Error:
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if err == ERR_ALREADY_EXISTS:
		return OK
	return err


## Write `text` to `path`, creating the parent directory first.
static func write_text(path: String, text: String) -> Error:
	var dir_err := ensure_parent_dir(path)
	if dir_err != OK:
		return dir_err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


## Load a ConfigFile from `path`, or null when it cannot be read.
static func load_config(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return null
	return cfg


## Save `cfg` to `path`, creating the parent directory first.
static func save_config(path: String, cfg: ConfigFile) -> Error:
	var dir_err := ensure_parent_dir(path)
	if dir_err != OK:
		return dir_err
	return cfg.save(path)
