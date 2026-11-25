# Run from the imported project with --script res://scripts/tests/test_keeper_chapter.gd.
extends SceneTree

var failures := 0
var player: CharacterBody3D
var manager
var boss
var voice
var game
var ai
var endings: Array[String] = []
var udp := PacketPeerUDP.new()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS ", description)
	else:
		failures += 1
		push_error(description)

func cast(word: String, die := 14, whisper := false) -> void:
	var volume := 0.2 if whisper else 0.85
	voice.spell_heard.emit(word, 1.0, volume, D20Roller.resolve_roll(die, 1.0, volume), whisper)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func wait_msec(duration: int) -> void:
	var until := Time.get_ticks_msec() + duration
	while Time.get_ticks_msec() < until:
		await process_frame

func packet(word: String, silence: float) -> void:
	var data := {"spell": word, "confidence": 0.99, "volume": 0.8, "silence_sec": silence}
	udp.put_packet(JSON.stringify(data).to_utf8_buffer())

func next_floor(gate_word: String, whisper := false) -> void:
	var floor_node: Node3D = manager._current_floor_node
	var old_index: int = manager.current_floor_index
	player.global_position = floor_node.get_node("SpellGate").global_position + Vector3(0, 1, 1)
	cast(gate_word, 14, whisper)
	await physics_frame
	player.global_position = floor_node.get_node("Exit").global_position
	for frame in range(8):
		await physics_frame
		if manager.current_floor_index != old_index:
			break
	check(manager.current_floor_index == old_index + 1, "Exit on floor %d leads to the next floor" % old_index)

func reach_summit() -> void:
	var book = manager._current_floor_node.get_node("Decor/GrimoireStand")
	player.global_position = book.global_position + Vector3.UP
	cast("noktar")
	var chest = manager._current_floor_node.get_node("Decor/SupplyChest")
	player.global_position = chest.global_position + Vector3.UP
	cast("virdan")
	await next_floor("targum")
	await next_floor("virdan")
	var ghost = manager._current_floor_node.get_node("CryptGuardian")
	player.global_position = ghost.global_position + Vector3(0, 0.8, 1.5)
	var hp: int = ghost.health
	player._melee_attack()
	check(ghost.health == hp, "The crypt ghost resists ordinary melee")
	cast("noktar")
	player._melee_attack()
	check(ghost.health == hp - 24 and ghost.exposed_for == 0, "NOCTAR opens one double-damage strike")
	player._melee_attack()
	check(ghost.health == hp - 24, "The ghost's protection returns")
	await next_floor("noktar", true)

func jury_skip() -> void:
	key(KEY_F9, true)
	key(KEY_F9, false)
	await physics_frame
	check(game.current_floor == 4 and game.selected_ending == "", "F9 starts a fresh summit encounter")
	check(player.global_position.distance_to(manager._current_floor_node.spawn_point.global_position) < 0.3, "F9 places the player at the summit spawn")
	ai.reset_for_new_run()

func ward_blocks() -> bool:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -12.5), Vector3(0, 1, -14.5))
	return not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func beam() -> void:
	boss._recovery = 0.0
	boss._physics_process(0.05)
	boss._physics_process(boss.WINDUP + 0.05)

func ritual(check_retries := false, keyboard_combo := false) -> void:
	boss = manager._current_floor_node.get_node("KeeperBoss")
	player.global_position = boss.global_position + Vector3(0, 0.8, 6)
	player.stealth_left = 0.0
	player.shield_left = 0.0
	var hp: int = player.health
	beam()
	check(player.health < hp and boss.current_phase == boss.Phase.BEAM_SHIELD, "An undefended beam deals damage without breaking the ward")
	cast("targum")
	check(ward_blocks() and boss.current_phase == boss.Phase.BEAM_SHIELD, "Casting a shield alone leaves the ward locked")
	beam()
	check(boss.current_phase == boss.Phase.ESCAPE_ROOTS, "An actual reflected beam starts the retreat")
	var old_position: Vector3 = boss.global_position
	boss._physics_process(0.1)
	check(boss.global_position.distance_to(old_position) > 0.05, "The Keeper retreats across the arena")
	if check_retries:
		var near_position := player.global_position
		player.global_position = manager._current_floor_node.spawn_point.global_position
		cast("virdan")
		check(boss.current_phase == boss.Phase.ESCAPE_ROOTS and boss.rooted_for == 0, "A distant spell cannot bind the Keeper")
		player.global_position = near_position
		cast("noktar")
	cast("virdan", 1)
	check(boss.current_phase == boss.Phase.ESCAPE_ROOTS, "A fumble cannot bind the Keeper")
	cast("virdan")
	check(boss.rooted_for > 0 and game.ui_censored and "[УДАЛЕНО]" in player.hud_spell_label.text, "Roots interrupt the retreat and censorship reaches the HUD")
	cast("noktar")
	check(boss.exposed_for > 0 and not game.ui_censored and boss.current_phase == boss.Phase.COMBO_10001, "Revealing the spirit lifts censorship")
	if check_retries:
		for word in ["targum", "noktar", "virdan", "targum"]:
			cast(word)
		check(ward_blocks() and boss._combo_step == 0, "Out-of-order words cannot unlock the exit")
		cast("virdan")
		await wait_msec(boss.COMBO_WINDOW_MSEC + 100)
		check(boss._combo_step == 0, "An incomplete combo expires")
		cast("noktar")
	cast("virdan")
	cast("noktar")
	if keyboard_combo:
		# The final key uses the receiver's normal cooldown. Retry a natural 1.
		for attempt in range(8):
			key(KEY_3, true)
			await wait_msec(50)
			key(KEY_3, false)
			if boss.current_phase == boss.Phase.FINAL_CHOICE:
				break
			await wait_msec(900)
	else:
		cast("targum")
	await physics_frame
	await physics_frame
	check(boss.current_phase == boss.Phase.FINAL_CHOICE and not ward_blocks(), "The ordered three-word combo removes the physical ward")
	check(not boss.is_physics_processing(), "The Keeper stops attacking during the decision")

func _run() -> void:
	var arena := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	manager = arena.get_node("LevelManager")
	player = arena.get_node("Player")
	game = root.get_node("GameState")
	ai = root.get_node("AdaptiveAI")
	voice = root.get_node("VoiceReceiver")
	game.ending_reached.connect(func(id: String): endings.append(id))
	udp.connect_to_host("127.0.0.1", 5055)
	await physics_frame
	check(game.current_floor == 1, "Normal startup loads the tutorial")
	await jury_skip()
	check(game.current_floor == 4, "F9 skips directly from the tutorial to the Keeper")
	manager.load_floor(1)
	await physics_frame
	await reach_summit()
	await ritual(true)
	packet("noktar", 0)
	await wait_msec(150)
	check(endings == ["translator"], "A recognized UDP spell selects Translator")
	var objective: Label = arena.get_node("CanvasLayer/HudPanel/VBox/ObjectiveLabel")
	check("Переводчик" in objective.text, "The tower displays the spoken ending")
	voice.silence_updated.emit(30.0)
	check(endings.size() == 1, "An ending is emitted only once")

	await jury_skip()
	player.health = 1
	player.shield_left = 0
	player.take_hit(14, true)
	check(player.global_position.is_equal_approx(manager._current_floor_node.spawn_point.global_position), "Death respawns the player on the summit")
	await ritual()
	key(KEY_0, true)
	await wait_msec(800)
	key(KEY_0, false)
	await wait_msec(100)
	key(KEY_0, true)
	await wait_msec(4600)
	check(game.selected_ending == "", "Releasing 0 resets the five-second hold")
	await wait_msec(550)
	key(KEY_0, false)
	check(game.selected_ending == "silence" and "Цена Тишины" in objective.text, "Five real seconds on 0 select Price of Silence")

	await jury_skip()
	await ritual()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 4800:
		packet("background", 30.0 + (Time.get_ticks_msec() - start) / 1000.0)
		await wait_msec(100)
	check(game.selected_ending == "", "Microphone silence from before the decision does not count")
	while Time.get_ticks_msec() - start < 5250:
		packet("background", 30.0 + (Time.get_ticks_msec() - start) / 1000.0)
		await wait_msec(100)
	check(game.selected_ending == "silence", "Five seconds of live UDP silence select the quiet ending")

	await jury_skip()
	await ritual(false, true)
	key(KEY_1, true)
	await wait_msec(100)
	key(KEY_1, false)
	check(endings == ["translator", "silence", "silence", "translator"], "Keyboard and microphone select both endings across clean replays")
	udp.close()
	quit(int(failures > 0))
