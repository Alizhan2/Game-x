extends "res://scenes/floors/tower_floor.gd"

enum Lesson { READ, BIND, SHIELD }

const REACH := 3.0

@onready var _book: Node3D = $Decor/GrimoireStand
@onready var _chest: Node3D = $Decor/SupplyChest
@onready var _book_sign: Label3D = $Decor/GrimoireStand/GrimoireSign
@onready var _chest_sign: Label3D = $ChestSign

var _lesson := Lesson.READ

func _on_spell_heard(spell: String, confidence: float, volume: float, roll: Dictionary, whisper: bool) -> void:
	if is_queued_for_deletion() or _gate == null:
		return
	var player := get_tree().get_first_node_in_group("tower_player") as CharacterBody3D
	if player == null:
		return
	match _lesson:
		Lesson.READ:
			if spell != "noktar" or player.global_position.distance_to(_book.global_position) > REACH:
				return
			_lesson = Lesson.BIND
			_book_sign.text = "Печать Миры спрятана в сундуке"
			var cover: Node3D = $Decor/GrimoireStand/Cover
			create_tween().tween_property(cover, "rotation:z", deg_to_rad(-72.0), 0.35)
			_chest_sign.show()
			objective_changed.emit("На странице проступил знак сундука. Подойди к нему справа и скрепи треснувшую печать словом «Вирдан» (1).")
		Lesson.BIND:
			if spell != "virdan" or player.global_position.distance_to(_chest.global_position) > REACH:
				return
			_lesson = Lesson.SHIELD
			_chest_sign.text = "Печать восстановлена"
			$ChestSeal.show()
			$SpellGate/ShieldHint.show()
			objective_changed.emit("Печать зажгла руну над аркой. Подойди к золотой завесе и отрази её свет щитом «Таргум» (3).")
		Lesson.SHIELD:
			super._on_spell_heard(spell, confidence, volume, roll, whisper)
