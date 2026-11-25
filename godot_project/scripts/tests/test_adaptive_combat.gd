# Run after project import with --script res://scripts/tests/test_adaptive_combat.gd.
extends SceneTree

var failures := 0
var ai
var voice
var player
var boss
var shield_events: Array[String] = []
var taunts: Array[String] = []
var stats: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS ", description)
	else:
		failures += 1
		push_error(description)

func cast(word: String) -> bool:
	var result := D20Roller.resolve_roll(14, 1.0, 0.85)
	voice.spell_heard.emit(word, 1.0, 0.85, result, false)
	return result.get("countered", false)

func hotkey(code: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.pressed = pressed
		Input.parse_input_event(key)
		Input.flush_buffered_events()
	await process_frame

func fire_beam(attacker) -> void:
	attacker.global_position = player.global_position + Vector3(0, 0, -5.0)
	attacker.rooted_for = 0.0
	attacker._recovery = 0.0
	attacker._physics_process(0.1)
	attacker._physics_process(1.3)

func _run() -> void:
	var arena := (load("res://scripts/tests/combat_trial.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	ai = root.get_node("AdaptiveAI")
	voice = root.get_node("VoiceReceiver")
	player = arena.get_node("Player")
	boss = arena.get_node("KeeperBoss")
	ai.counter_shield_changed.connect(func(s: String): shield_events.append(s))
	ai.taunt_triggered.connect(func(s: String): taunts.append(s))
	ai.adaptation_updated.connect(func(s: Dictionary): stats = s)
	var guard = load("res://scripts/combat_guard.gd").new()
	arena.add_child(guard)
	guard.global_position = player.global_position + Vector3.RIGHT * 2

	for mode in range(3):
		await hotkey([KEY_F1, KEY_F2, KEY_F3][mode])
		ai.reset_for_new_run()
		check(ai.current_difficulty == mode, "Difficulty hotkey %d" % (mode + 1))
		check(not cast("virdan"), "First cast reaches guards")
		if mode == 0:
			check(not cast("virdan"), "Apprentice allows a second cast")
		guard.rooted_for = 0.0
		boss.rooted_for = 0.0
		check(cast("virdan") and guard.rooted_for == 0.0 and boss.rooted_for == 0.0, "Spam threshold blocks effects on guard and boss")
		check(not cast("noktar") and guard.exposed_for > 0.0 and ai.active_counter_spell == "", "Switching school clears spam shield")
	check(shield_events.has("virdan") and taunts.size() >= 6 and stats.has("counts"), "HUD receives shield, taunt and adaptation signals")

	ai.reset_for_new_run()
	for word in ["virdan", "noktar", "virdan", "noktar"]:
		cast(word)
	check(ai.active_counter_spell == "virdan", "Archmage arms a learned transition")
	boss.current_phase = 1  # ESCAPE_ROOTS requires VIRDAN.
	boss.rooted_for = 0.0
	check(cast("virdan") and boss.rooted_for == 0.0 and boss.current_phase == 1, "Predicted cast cannot root or advance Keeper ritual")

	for mode in range(3):
		ai.set_difficulty(mode)
		ai.reset_for_new_run()
		player.health = 100
		player.shield_left = 0.0
		fire_beam(guard)
		check(player.health == 100 - [11, 14, 18][mode], "Guard beam uses difficulty multiplier %d" % mode)
	await hotkey(KEY_F2)
	ai.reset_for_new_run()
	player.health = 100
	fire_beam(boss)
	fire_beam(boss)
	check(is_equal_approx(ai.dda_modifier, 0.92), "Consecutive real hits lower DDA")
	fire_beam(boss)
	check(player.health == 59, "Next beam uses the adjusted damage")
	var before_blocks: float = ai.dda_modifier
	player.shield_left = 20.0
	for i in range(4):
		fire_beam(boss)
	check(player.health == 59 and is_equal_approx(ai.dda_modifier, before_blocks + 0.05), "Four defended attacks raise DDA without costing health")
	quit(int(failures > 0))
