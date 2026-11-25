extends Node

signal floor_changed(floor_num: int)
signal word_unlocked(word: String)
signal censorship_changed(censored: bool)
signal ending_reached(ending_id: String)

var current_floor: int = 1
var unlocked_words: Array[String] = ["virdan", "noktar", "targum"]
var discovered_logs: Array[int] = []
var ui_censored: bool = false
var selected_ending: String = ""

func unlock_word(word: String) -> void:
	if word not in unlocked_words:
		unlocked_words.append(word)
		word_unlocked.emit(word)

func set_floor(floor_num: int) -> void:
	current_floor = floor_num
	floor_changed.emit(floor_num)

func set_censorship(enabled: bool) -> void:
	ui_censored = enabled
	censorship_changed.emit(enabled)

func mark_log_discovered(log_id: int) -> void:
	if log_id not in discovered_logs:
		discovered_logs.append(log_id)

func finish_chapter_one(ending_id: String) -> void:
	selected_ending = ending_id
	ending_reached.emit(ending_id)
