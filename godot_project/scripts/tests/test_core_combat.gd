# Run after project import: godot --headless --path godot_project --script res://scripts/tests/test_core_combat.gd
extends SceneTree

var failures: int = 0
var player
var keeper
var voice

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS ", description)
	else:
		failures += 1
		push_error(description)

func cast(word: String, die: int, whisper: bool = false) -> void:
	var volume := 0.2 if whisper else 0.8
	voice.spell_heard.emit(word, 1.0, volume, D20Roller.resolve_roll(die, 1.0, volume), whisper)

func click() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = Vector2(800, 380)
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await physics_frame
	await physics_frame

func _run() -> void:
	var arena := (load("res://scripts/tests/combat_trial.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	arena.get_node("CanvasLayer/TowerMenu").get_node("%Begin").pressed.emit()
	arena.get_node("LevelManager").jump_to_boss_for_jury()
	await physics_frame
	await physics_frame
	player = current_scene.get_node("Player")
	keeper = arena.get_node("ActiveFloor/Summit/KeeperBoss")
	keeper.global_position = player.global_position + Vector3(0, 0, -5)
	voice = root.get_node("VoiceReceiver")
	var door := current_scene.get_node("SealedPassage") as StaticBody3D
	var inscription := current_scene.get_node("Inscription") as Label3D
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 1), Vector3(0, 1, -1))
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	check(space.intersect_ray(query).get("collider") == door, "Closed door physically blocks the passage")

	cast("targum", 1)
	check(player.shield_left == 0 and keeper.current_phase == 0, "Natural 1 creates no shield and cannot advance the boss")
	cast("noktar", 1, true)
	check(door.visible and not inscription.visible and player.stealth_left == 0, "Fumbled whisper leaves the door and stealth unchanged")
	cast("noktar", 20, true)
	await physics_frame
	check(not door.visible and inscription.visible and space.intersect_ray(query).is_empty(), "NOCTAR reveals the glyph and opens physical passage")
	check(keeper.exposed_for > 8.0 and player.stealth_left > 5.0, "Natural 20 extends exposure and whispered stealth")
	check(D20Roller.resolve_roll(12, 1.0, 1.0)["total"] == 18, "Speech confidence and volume modify d20 total")

	keeper.global_position = player.global_position + Vector3(0, 0, -5)
	keeper._recovery = 0.0
	keeper._physics_process(0.1)
	check(keeper._windup == 0.0, "Guard cannot acquire a stealthed player")
	player.stealth_left = 0.0
	keeper._physics_process(0.1)
	check(keeper._windup > 0.0, "Guard starts casting a beam")
	cast("virdan", 12)
	var held_at: Vector3 = keeper.global_position
	keeper._physics_process(1.3)
	check(keeper._windup == 0.0 and keeper.global_position == held_at and player.health == 100, "VIRDAN interrupts the beam and immobilizes the guard")

	keeper.global_position = player.global_position + Vector3(0, 0, -1.8)
	await click()
	check(keeper.health == 36 and keeper.exposed_for == 0.0, "Actual left-click consumes exposure for double damage")
	await click()
	check(keeper.health == 36, "Melee cooldown prevents immediate repeat damage")
	player._melee_wait = 0.0
	await click()
	check(keeper.health == 24, "Ordinary melee hit deals base damage")

	var guard = load("res://scripts/combat_guard.gd").new()
	arena.add_child(guard)
	cast("targum", 12)
	for distance in [1.8, 5.0]:
		guard.global_position = player.global_position + Vector3(0, 0, -distance)
		guard.rooted_for = 0.0
		guard._recovery = 0.0
		guard._physics_process(0.1)
		guard._physics_process(1.3)
		var attack := "Удар" if distance < 3 else "Луч"
		check(player.health == 100 and (attack + " заблокирован") in player.hud_status_label.text, "TARGUM blocks the guard attack at range %.1f" % distance)
	player._physics_process(7.0)
	player.take_hit(14, true)
	check(player.health == 86 and player.shield_left == 0.0, "Damage resumes after shield expiry")
	quit(int(failures > 0))
