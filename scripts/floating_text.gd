extends Label3D
## Spawns at a world position, drifts upward, and fades out, then frees itself.

const RISE_DISTANCE: float = 1.2
const LIFETIME: float = 1.2

func setup(initial_text: String, world_pos: Vector3, color: Color = Color.WHITE) -> void:
	text = initial_text
	global_position = world_pos
	modulate = color
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", world_pos + Vector3(0, RISE_DISTANCE, 0), LIFETIME)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME).set_delay(LIFETIME * 0.35)
	tween.chain().tween_callback(queue_free)
