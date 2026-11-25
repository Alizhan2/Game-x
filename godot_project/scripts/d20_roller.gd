class_name D20Roller
extends RefCounted

static func roll_spell(confidence: float, volume: float) -> Dictionary:
	return resolve_roll(randi_range(1, 20), confidence, volume)

static func resolve_roll(die: int, confidence: float, volume: float) -> Dictionary:
	var bonus := roundi(clampf(confidence, 0.0, 1.0) * 4.0 + clampf(volume, 0.0, 1.0) * 2.0)
	var total := die + bonus
	var tier := "УСПЕХ"
	var strength := 1.0
	if die == 1:
		tier = "СРЫВ"
		strength = 0.0
	elif die == 20:
		tier = "КРИТИЧЕСКИЙ УСПЕХ"
		strength = 1.5
	elif total < 10:
		tier = "СЛАБЫЙ КАСТ"
		strength = 0.75
	elif total >= 21:
		tier = "СИЛЬНЫЙ КАСТ"
		strength = 1.25

	return {"d20": die, "bonus": bonus, "total": total, "tier": tier, "strength": strength}
