extends Control

# UI references
var csv_path_edit: LineEdit
var area_name_edit: LineEdit
var output_path_edit: LineEdit
var status_label: Label
var preview_edit: TextEdit

# Column index groups: [scene_col, lv_col, content_col]
const NPC_SLOT_COLS = {
	"1": [9,  10, 11],
	"2": [12, 13, 14],
	"3": [15, 16, 17],
	"4": [18, 19, 20],
	"5": [21, 22, 23],
	"6": [24, 25, 26],
}

const OBJECT_SLOT_COLS = {
	"A": [27, 28, 29],
	"B": [30, 31, 32],
	"C": [33, 34, 35],
	"D": [36, 37, 38],
	"E": [39, 40, 41],
}


func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Area Spawn Data  ·  CSV → JSON Converter"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# CSV file row
	csv_path_edit = _add_file_row(vbox, "CSV File:", "Select input .csv file...", _browse_csv)

	# Area name row
	var area_row = HBoxContainer.new()
	vbox.add_child(area_row)
	var al = Label.new()
	al.text = "Area Name:"
	al.custom_minimum_size.x = 110
	area_row.add_child(al)
	area_name_edit = LineEdit.new()
	area_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area_name_edit.placeholder_text = "e.g. izakaya_storefront"
	area_row.add_child(area_name_edit)

	# Output path row
	output_path_edit = _add_file_row(vbox, "Output JSON:", "Output .json path...", _browse_output)

	vbox.add_child(HSeparator.new())

	# Buttons + status row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var convert_btn = Button.new()
	convert_btn.text = "  Convert  "
	convert_btn.custom_minimum_size.y = 36
	convert_btn.pressed.connect(_do_convert)
	btn_row.add_child(convert_btn)

	var copy_btn = Button.new()
	copy_btn.text = "Copy JSON"
	copy_btn.custom_minimum_size.y = 36
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(preview_edit.text))
	btn_row.add_child(copy_btn)

	status_label = Label.new()
	status_label.text = "Ready."
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(status_label)

	# Preview
	vbox.add_child(HSeparator.new())
	var preview_label = Label.new()
	preview_label.text = "JSON Preview:"
	vbox.add_child(preview_label)

	preview_edit = TextEdit.new()
	preview_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_edit.editable = false
	vbox.add_child(preview_edit)


func _add_file_row(parent: VBoxContainer, label_text: String, placeholder: String, browse_cb: Callable) -> LineEdit:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 110
	row.add_child(lbl)
	var edit = LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = placeholder
	row.add_child(edit)
	var btn = Button.new()
	btn.text = "Browse"
	btn.pressed.connect(browse_cb)
	row.add_child(btn)
	return edit


# ──────────────────────────────────────────────
#  File dialogs
# ──────────────────────────────────────────────

func _browse_csv():
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.csv ; CSV Files"])
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(_on_csv_selected)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 520))


func _on_csv_selected(path: String):
	csv_path_edit.text = path
	# Auto-extract area name: strip "(TAG) " prefix and "(n)" suffix
	var raw = path.get_file().get_basename()
	var bracket_end = raw.rfind(") ")
	if bracket_end != -1:
		raw = raw.substr(bracket_end + 2)
	var trail = raw.find("(")
	if trail != -1:
		raw = raw.substr(0, trail).strip_edges()
	area_name_edit.text = raw
	# Auto-suggest output path
	if output_path_edit.text.is_empty():
		output_path_edit.text = path.get_base_dir().path_join(raw + ".json")


func _browse_output():
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.json ; JSON Files"])
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(func(p): output_path_edit.text = p)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 520))


# ──────────────────────────────────────────────
#  Conversion
# ──────────────────────────────────────────────

func _do_convert():
	var csv_path = csv_path_edit.text.strip_edges()
	var area_name = area_name_edit.text.strip_edges()
	var out_path  = output_path_edit.text.strip_edges()

	if csv_path.is_empty():
		return _set_status("ERROR: No CSV file selected.", Color.RED)
	if area_name.is_empty():
		return _set_status("ERROR: Area name is required.", Color.RED)
	if out_path.is_empty():
		return _set_status("ERROR: No output path specified.", Color.RED)

	var file = FileAccess.open(csv_path, FileAccess.READ)
	if not file:
		return _set_status("ERROR: Cannot open: " + csv_path, Color.RED)

	var lines: Array[String] = []
	while not file.eof_reached():
		var raw = file.get_line().strip_edges()
		if not raw.is_empty():
			lines.append(raw)
	file.close()

	if lines.size() < 2:
		return _set_status("ERROR: CSV appears to have no data rows.", Color.RED)

	# Skip header (index 0), parse remaining rows
	var rows = []
	var skipped = 0
	for i in range(1, lines.size()):
		var cols = _parse_csv_line(lines[i])
		# Rows where the Day column isn't a valid integer are comments / notes — skip them
		if cols.is_empty() or not cols[0].strip_edges().is_valid_int():
			skipped += 1
			continue
		rows.append(_parse_row(cols))

	# Merge into existing JSON if the file already exists
	var result: Dictionary = {}
	var merge_note := ""
	if FileAccess.file_exists(out_path):
		var existing_file = FileAccess.open(out_path, FileAccess.READ)
		if existing_file:
			var json := JSON.new()
			if json.parse(existing_file.get_as_text()) == OK:
				result = json.get_data()
				merge_note = " (merged)" if result.has(area_name) else " (added)"
			else:
				merge_note = " (existing file unreadable — overwritten)"
			existing_file.close()

	result[area_name] = rows
	var json_str = JSON.stringify(result, "\t")

	var out_file = FileAccess.open(out_path, FileAccess.WRITE)
	if not out_file:
		return _set_status("ERROR: Cannot write to: " + out_path, Color.RED)
	out_file.store_string(json_str)
	out_file.close()

	preview_edit.text = json_str
	var skip_note = (" · %d non-data rows skipped" % skipped) if skipped > 0 else ""
	_set_status("Done! %d rows%s%s  →  %s" % [rows.size(), merge_note, skip_note, out_path], Color.GREEN)


# ──────────────────────────────────────────────
#  CSV line parser  (handles quoted fields)
# ──────────────────────────────────────────────

func _parse_csv_line(line: String) -> Array:
	var result = []
	var current = ""
	var in_quotes = false
	var i = 0
	while i < line.length():
		var c = line[i]
		if c == '"':
			# "" inside a quoted field → literal quote character
			if in_quotes and i + 1 < line.length() and line[i + 1] == '"':
				current += '"'
				i += 2
				continue
			in_quotes = !in_quotes
		elif c == ',' and not in_quotes:
			result.append(current)
			current = ""
		else:
			current += c
		i += 1
	result.append(current)
	return result


# ──────────────────────────────────────────────
#  Row → Dictionary
# ──────────────────────────────────────────────

func _parse_row(cols: Array) -> Dictionary:
	# Ensure we always have enough columns to index safely
	while cols.size() < 42:
		cols.append("")

	var row = {}
	row["day"]               = int(cols[0].strip_edges())
	row["priority"]          = int(cols[1].strip_edges()) if cols[1].strip_edges().is_valid_int() else 0
	row["expired_on"]        = _str_or_null(cols[2])
	row["start_at"]          = _str_or_null(cols[3])
	row["item_requirement"]  = _parse_item_req(cols[4])
	row["no_travel"]         = cols[5].strip_edges().to_lower() == "true"
	row["no_travel_message"] = _str_or_null(cols[6])

	# auto_content  (col 7 = chapter name, col 8 = level requirement)
	var auto_ch = _str_or_null(cols[7])
	if auto_ch != null:
		var lv_s = cols[8].strip_edges()
		row["auto_content"] = {
			"chapter":        auto_ch,
			"level_required": int(lv_s) if lv_s.is_valid_int() else -1
		}
	else:
		row["auto_content"] = null

	# NPC slots  (scene / level_required / content)
	var npc_slots = {}
	for slot_key in NPC_SLOT_COLS:
		var idx     = NPC_SLOT_COLS[slot_key]
		var scene   = _str_or_null(cols[idx[0]])
		var lv_s    = cols[idx[1]].strip_edges()
		var content = _str_or_null(cols[idx[2]])
		if scene != null or content != null:
			npc_slots[slot_key] = {
				"scene":          scene,
				"level_required": int(lv_s) if lv_s.is_valid_int() else -1,
				"content":        content
			}
	row["npc_slots"] = npc_slots

	# Object slots  (scene / level_required / content)
	# scene column may be empty in the CSV (object defined by slot position in the background),
	# but we always write the key so it's never silently missing in the JSON.
	var object_slots = {}
	for slot_key in OBJECT_SLOT_COLS:
		var idx     = OBJECT_SLOT_COLS[slot_key]
		var scene   = _str_or_null(cols[idx[0]])
		var lv_s    = cols[idx[1]].strip_edges()
		var content = _str_or_null(cols[idx[2]])
		if lv_s != "" or content != null:
			object_slots[slot_key] = {
				"scene":          scene,
				"level_required": int(lv_s) if lv_s.is_valid_int() else -1,
				"content":        content
			}
	row["object_slots"] = object_slots

	return row


# ──────────────────────────────────────────────
#  Helpers
# ──────────────────────────────────────────────

func _str_or_null(s: String):
	var t = s.strip_edges()
	return t if not t.is_empty() else null


func _parse_item_req(s: String):
	var t = s.strip_edges()
	if t.is_empty():
		return null
	var parts = t.split(",")
	if parts.size() != 3:
		push_warning("item_requirement has unexpected format: " + t)
		return null
	return {
		"type": parts[0].strip_edges(),
		"id":   int(parts[1].strip_edges()),
		"qty":  int(parts[2].strip_edges())
	}


func _set_status(msg: String, color: Color = Color.WHITE):
	status_label.text = msg
	status_label.add_theme_color_override("font_color", color)
