class_name D20Roller
extends RefCounted

static func roll_spell(confidence: float, volume: float) -> Dictionary:
	var base_d20: int = randi_range(1, 20)
	var ai_bonus: int = int(round(clampf(confidence, 0.0, 1.0) * 4.0 + clampf(volume, 0.0, 1.0) * 2.0))
	var total: int = base_d20 + ai_bonus
	var tier: String = "УСПЕХ"
	if base_d20 == 20 or total >= 21:
		tier = "КРИТИЧЕСКИЙ УСПЕХ"
	elif total < 10:
		tier = "СЛАБЫЙ КАСТ"

	return {
		"d20": base_d20,
		"bonus": ai_bonus,
		"total": total,
		"tier": tier,
	}
