extends Node
## Auto-updater. On launch, asks GitHub for the latest release of REPO,
## compares its tag against res://VERSION, and prompts the user if a newer
## build is available.
##
## Skipped entirely when running in the editor or on non-Windows platforms.

const REPO := "wes2000/mineco"
const VERSION_FILE := "res://VERSION"
const API_URL := "https://api.github.com/repos/%s/releases/latest"
const ASSET_PATTERN := "mineco-v%s-windows.zip"
const SKIP_CFG := "user://updater_skip.cfg"
const HELPER_TEMPLATE := "res://scripts/updater_helper.ps1"

const DialogScript := preload("res://autoload/update_dialog.gd")

var current_version: String = "0.0.0"
var _check_http: HTTPRequest
var _download_http: HTTPRequest
var _progress_timer: Timer
var _dialog: Window


func _ready() -> void:
	current_version = _read_version_file()
	if OS.has_feature("editor"):
		return
	if OS.get_name() != "Windows":
		return
	_check_http = HTTPRequest.new()
	add_child(_check_http)
	_check_http.request_completed.connect(_on_release_check_done)
	var err := _check_http.request(API_URL % REPO, [
		"Accept: application/vnd.github+json",
		"User-Agent: mineco-updater",
	])
	if err != OK:
		push_warning("Updater: failed to start request (err %d)" % err)


func _read_version_file() -> String:
	var f := FileAccess.open(VERSION_FILE, FileAccess.READ)
	if f == null:
		return "0.0.0"
	var v := f.get_as_text().strip_edges()
	f.close()
	return v


func _on_release_check_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var tag_raw := str(data.get("tag_name", ""))
	var latest := tag_raw.lstrip("v")
	if latest == "" or _compare_versions(latest, current_version) <= 0:
		return
	if _is_skipped(latest):
		return
	var asset_url := _find_asset_url(data.get("assets", []), latest)
	if asset_url == "":
		push_warning("Updater: release %s has no asset matching %s" % [tag_raw, ASSET_PATTERN % latest])
		return
	var notes := str(data.get("body", ""))
	_show_dialog(latest, notes, asset_url)


func _find_asset_url(assets: Variant, version: String) -> String:
	if typeof(assets) != TYPE_ARRAY:
		return ""
	var expected := ASSET_PATTERN % version
	for a in assets:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("name", "")) == expected:
			return str(a.get("browser_download_url", ""))
	return ""


# Returns 1 if a > b, -1 if a < b, 0 if equal. Inputs like "1.2.3".
func _compare_versions(a: String, b: String) -> int:
	var pa := _parse_version(a)
	var pb := _parse_version(b)
	var n: int = max(pa.size(), pb.size())
	for i in range(n):
		var ai: int = pa[i] if i < pa.size() else 0
		var bi: int = pb[i] if i < pb.size() else 0
		if ai != bi:
			return 1 if ai > bi else -1
	return 0


func _parse_version(s: String) -> Array:
	var out: Array = []
	for part in s.split("."):
		out.append(int(part))
	return out


func _is_skipped(version: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SKIP_CFG) != OK:
		return false
	return str(cfg.get_value("skip", "version", "")) == version


func _mark_skipped(version: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("skip", "version", version)
	cfg.save(SKIP_CFG)


func _show_dialog(new_version: String, notes: String, asset_url: String) -> void:
	_dialog = DialogScript.new()
	get_tree().root.add_child(_dialog)
	_dialog.configure(current_version, new_version, notes)
	_dialog.update_requested.connect(func(): _begin_download(new_version, asset_url))
	_dialog.skip_requested.connect(func(): _on_skip(new_version))
	_dialog.close_requested.connect(func(): _dismiss_dialog())
	_dialog.popup_centered()


func _on_skip(version: String) -> void:
	_mark_skipped(version)
	_dismiss_dialog()


func _dismiss_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _begin_download(_version: String, asset_url: String) -> void:
	var dl_dir := OS.get_environment("TEMP").path_join("mineco_update")
	# Clean any previous attempt.
	if DirAccess.dir_exists_absolute(dl_dir):
		_remove_dir_recursive(dl_dir)
	DirAccess.make_dir_recursive_absolute(dl_dir)
	var zip_path := dl_dir.path_join("update.zip")

	_download_http = HTTPRequest.new()
	add_child(_download_http)
	_download_http.download_file = zip_path
	_download_http.request_completed.connect(func(result, code, headers, body):
		_on_download_done(result, code, dl_dir, zip_path)
	)

	if is_instance_valid(_dialog):
		_dialog.show_progress()

	_progress_timer = Timer.new()
	_progress_timer.wait_time = 0.25
	_progress_timer.timeout.connect(func():
		if is_instance_valid(_dialog) and is_instance_valid(_download_http):
			_dialog.set_progress(_download_http.get_downloaded_bytes(), _download_http.get_body_size())
	)
	add_child(_progress_timer)
	_progress_timer.start()

	var err := _download_http.request(asset_url, ["User-Agent: mineco-updater"])
	if err != OK:
		_stop_progress_timer()
		if is_instance_valid(_dialog):
			_dialog.show_error("Failed to start download (err %d)." % err)


func _on_download_done(result: int, code: int, dl_dir: String, zip_path: String) -> void:
	_stop_progress_timer()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if is_instance_valid(_dialog):
			_dialog.show_error("Download failed (HTTP %d)." % code)
		return

	var extracted := dl_dir.path_join("extracted")
	DirAccess.make_dir_recursive_absolute(extracted)
	if not _extract_zip(zip_path, extracted):
		if is_instance_valid(_dialog):
			_dialog.show_error("Failed to extract update archive.")
		return
	_spawn_helper_and_quit(extracted)


func _stop_progress_timer() -> void:
	if is_instance_valid(_progress_timer):
		_progress_timer.stop()
		_progress_timer.queue_free()
		_progress_timer = null


func _extract_zip(zip_path: String, dest_dir: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	for entry in reader.get_files():
		var out_path := dest_dir.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(out_path)
			continue
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var data := reader.read_file(entry)
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			reader.close()
			return false
		f.store_buffer(data)
		f.close()
	reader.close()
	return true


func _remove_dir_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := path.path_join(name)
		if d.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func _spawn_helper_and_quit(extracted_dir: String) -> void:
	var install_dir := OS.get_executable_path().get_base_dir()
	var exe_path := OS.get_executable_path()

	var helper_src := FileAccess.open(HELPER_TEMPLATE, FileAccess.READ)
	if helper_src == null:
		if is_instance_valid(_dialog):
			_dialog.show_error("Helper script missing from install.")
		return
	var helper_text := helper_src.get_as_text()
	helper_src.close()

	var helper_path := OS.get_environment("TEMP").path_join("mineco_apply_update.ps1")
	var helper_out := FileAccess.open(helper_path, FileAccess.WRITE)
	if helper_out == null:
		if is_instance_valid(_dialog):
			_dialog.show_error("Could not write helper to TEMP.")
		return
	helper_out.store_string(helper_text)
	helper_out.close()

	var args := [
		"-ExecutionPolicy", "Bypass",
		"-NoProfile",
		"-WindowStyle", "Hidden",
		"-File", helper_path,
		"-WaitPid", str(OS.get_process_id()),
		"-Source", extracted_dir,
		"-Dest", install_dir,
		"-Exe", exe_path,
	]
	OS.create_process("powershell.exe", args)
	get_tree().quit()
