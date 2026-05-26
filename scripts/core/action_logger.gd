class_name ActionLogger
extends RefCounted

var _file: FileAccess
var _path: String
var _count: int = 0

func open(path: String) -> void:
	_path = path
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("ActionLogger: cannot open %s" % path)

func log_event(event: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(event))
	_count += 1

func close() -> void:
	if _file != null:
		_file.close()
		_file = null

func get_path() -> String:
	return _path

func get_count() -> int:
	return _count
