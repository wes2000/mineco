# Mine Co. — Round 4: Ambient Audio

**Date:** 2026-05-01
**Project:** Mine Co. (Godot 4.6 module build, Forward+, D3D12)
**Status:** Approved by user, ready for implementation

## Goal

Add three ambient/audio layers so the world has soundscape, not just visuals:

1. **Wind ambient** — global looping wind sound, present everywhere.
2. **Water lap** — 3D positional water-surface sound, audible mostly when near water.
3. **Footsteps** — biome-aware step sounds (grass / sand / water-splash) triggered as the player walks.

These three are independent — you could ship any two without the third — but together they elevate the scene from "silent diorama" to "place you're standing in."

## Non-goals

- Music / soundtrack
- Wildlife / creature sounds (birds, insects)
- 3D-positional wind variation (e.g., louder on hilltops)
- Audio buses, volume sliders, or settings UI
- Reverb (no caves yet)
- Menu / UI sounds (no menu yet)
- NPC / vehicle footsteps (no NPCs)
- Sprint-speed step rate (no sprint)

All explicitly parked. R4 is "first ambient pass."

## Architecture overview

Three components, no shared infrastructure beyond the standard Godot audio system:

1. **Wind:** one `AudioStreamPlayer` (2D global) in `main.tscn`. Autoplay, looping, fixed -20 dB.
2. **Water:** one `AudioStreamPlayer3D` at world (0, 0, 0) in `main.tscn`. Autoplay, looping, large `unit_size` and `max_distance` so spatial-attenuation provides "loud near shore, quiet on hilltop" behavior.
3. **Footsteps:** new GDScript on the Player node. Tracks horizontal distance traveled; every ~2m emits a random clip from the appropriate biome bank (decided by player Y, matching the terrain biome shader's threshold).

No new autoloads, no audio buses (master bus only), no project.godot changes.

## Project structure changes

```
res://
  assets/audio/
    wind_ambient.ogg          — NEW (Kenney Nature SoundPack or Freesound CC0)
    water_lap.ogg             — NEW
    footstep_grass1.ogg       — NEW (3 grass variants)
    footstep_grass2.ogg       — NEW
    footstep_grass3.ogg       — NEW
    footstep_sand1.ogg        — NEW (3 sand variants)
    footstep_sand2.ogg        — NEW
    footstep_sand3.ogg        — NEW
    footstep_water1.ogg       — NEW (2 water variants — sparse if rarely used)
    footstep_water2.ogg       — NEW
  scenes/
    main.tscn                 — modified: add WindAmbience + WaterAmbience child nodes
    player.tscn               — modified: add Footsteps + StepEmitter child nodes
  scripts/
    footsteps.gd              — NEW
```

10 new audio files, 1 new script, 2 scene modifications. No shaders, no shaders, no addons.

## Component: Wind ambience

A single `AudioStreamPlayer` node in `main.tscn`:

```
[node name="WindAmbience" type="AudioStreamPlayer" parent="."]
stream = ExtResource("wind_audio")
autoplay = true
volume_db = -16.0
```

`AudioStream` (the imported `.ogg`) must have **Loop = true** in its import settings: in the FileSystem dock, click the `.ogg` → Import tab in the inspector → check "Loop" → click "Reimport" at the bottom. Without that, the clip plays once and stops. Same applies to the water lap clip.

No script. Volume is taste-tuned starting point; expect adjustment.

## Component: Water ambience

A single `AudioStreamPlayer3D` node at world origin in `main.tscn`:

```
[node name="WaterAmbience" type="AudioStreamPlayer3D" parent="."]
stream = ExtResource("water_audio")
autoplay = true
volume_db = -6.0
unit_size = 50.0
max_distance = 200.0
```

Properties explained:
- `unit_size = 50.0`: distance over which the audio halves under inverse-distance attenuation. 50m means the audio falls noticeably from origin out to the island edges.
- `max_distance = 200.0`: hard-cutoff beyond which audio mutes entirely. 200m comfortably exceeds our 300m island's half-radius.
- `attenuation_model`: leave at default `0` (`ATTENUATION_INVERSE_DISTANCE`). DO NOT set to `1` — that's `INVERSE_SQUARE_DISTANCE`, which falls off ~4× faster than spec intends.
- No `transform =` line — default identity transform places the node at origin (0,0,0), which is what we want.

Like wind, the .ogg must have Loop = true in import settings.

The "single emitter at island center for water that's all around the perimeter" is a simplification. It's not realistic (real water lap would emit from the shoreline), but for v1 it gives the right *intuition*: louder in the central/lower areas (which are near water bodies) and fades on the high terrain (which is far from water). Polish path: multiple emitters around the shore, or a script that moves a single emitter to follow the nearest shoreline point. Out of scope for R4.

## Component: Footsteps

`scripts/footsteps.gd`:

```gdscript
extends Node

@export var step_distance: float = 2.0
@export var sand_threshold_y: float = 1.2  # matches biome shader sand_band
@export var capsule_half_height: float = 0.9  # subtract from body origin to get feet Y

@onready var _player: CharacterBody3D = get_parent()
@onready var _emitter: AudioStreamPlayer3D = $StepEmitter

var _last_step_pos: Vector3
var _grass: Array[AudioStream]
var _sand: Array[AudioStream]
var _water: Array[AudioStream]

func _ready() -> void:
	_last_step_pos = _player.global_position
	_grass = [
		preload("res://assets/audio/footstep_grass1.ogg"),
		preload("res://assets/audio/footstep_grass2.ogg"),
		preload("res://assets/audio/footstep_grass3.ogg"),
	]
	_sand = [
		preload("res://assets/audio/footstep_sand1.ogg"),
		preload("res://assets/audio/footstep_sand2.ogg"),
		preload("res://assets/audio/footstep_sand3.ogg"),
	]
	_water = [
		preload("res://assets/audio/footstep_water1.ogg"),
		preload("res://assets/audio/footstep_water2.ogg"),
	]

func _physics_process(_delta: float) -> void:
	if not _player.is_on_floor():
		return
	var horiz: Vector3 = Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var last_horiz: Vector3 = Vector3(_last_step_pos.x, 0.0, _last_step_pos.z)
	if horiz.distance_to(last_horiz) >= step_distance:
		_play_step()
		_last_step_pos = _player.global_position

func _play_step() -> void:
	# Feet Y, not body origin — capsule center is half-height above the feet.
	var feet_y: float = _player.global_position.y - capsule_half_height
	var bank: Array[AudioStream]
	if feet_y < 0.0:
		bank = _water
	elif feet_y < sand_threshold_y:
		bank = _sand
	else:
		bank = _grass
	if bank.is_empty():
		return
	_emitter.stream = bank.pick_random()
	_emitter.pitch_scale = randf_range(0.9, 1.1)
	_emitter.play()
```

`StepEmitter` is an `AudioStreamPlayer3D` child of the Player node, no per-property tuning needed (uses default 3D audio settings — local to the player so no spatial weirdness from other directions).

In `player.tscn`, add:

```
[node name="Footsteps" type="Node" parent="."]
script = ExtResource("footsteps_script")

[node name="StepEmitter" type="AudioStreamPlayer3D" parent="Footsteps"]
unit_size = 1.0
max_distance = 10.0
```

`StepEmitter`'s tight 1m unit_size + 10m cutoff makes footsteps a near-field sound (loud at the player, inaudible from any distance). Defaults would make footsteps audible across the whole map — fine for a single-listener game but wasteful and weird-feeling.

Wait — there's a hierarchy issue. `Footsteps`'s `_player = get_parent()` and `_emitter = $StepEmitter`. If Footsteps is a child of Player, `get_parent()` is Player ✓ and `$StepEmitter` is a child of Footsteps ✓. Good.

The footsteps node is just an organizational wrapper. Could just attach the script directly to Player, but the wrapper keeps Player's script clean.

`is_on_floor()` requires the parent be a `CharacterBody3D`, which Player is. Trips up if footsteps script were used on a generic Node3D — but it's not.

## Risks and open questions

1. **Loop seamlessness on imported .oggs.** Godot's import dialog has a Loop toggle, but it doesn't always trim a clip cleanly — sometimes there's an audible "click" at the loop point. Mitigation: pick clips designed to loop (most ambient packs are), or hand-edit in Audacity to add a short crossfade.

2. **Audio file availability from Kenney.** Kenney has multiple audio packs (Nature SoundPack, Impact Sounds, Voiceover Pack, etc.). Verify at acquisition time which pack covers wind, water, and footsteps. If a Kenney pack lacks one (e.g., no wind loop in Impact Sounds), fall back to Freesound.org (most CC0) for that file.

3. **`-20 dB wind / -10 dB water` are guesses.** Audio mixing is taste; expect 1-2 retunes by ear in playtest.

4. **Footstep step rate vs player speed.** Hardcoded 2m/step at 5 m/s player → 2.5 steps/sec. Feels brisk for walking. If too fast, raise step_distance to 2.5. If too slow, drop to 1.5.

5. **Y-threshold for biome footsteps must stay in sync with the terrain shader's `sand_band`.** R1's biome shader uses 1.2m as the sand-to-grass transition. The footsteps script uses the same value via `@export sand_threshold_y = 1.2`. If you ever change one, change both. (Could centralize in `Atmosphere` autoload, but for one constant the cost-benefit doesn't justify it. Comment in the script makes the connection visible.)

6. **Player at y < 0 (water splash).** Player can theoretically reach below water level if they fall into deep water near the seabed. With our flat 400m water plane at y=0 and terrain seabed at -5m, a player walking off a sand bank into deeper water could end up at y in [-5, 0] briefly while falling. Footstep wouldn't trigger underwater (player not `is_on_floor()`) — fine. Once they hit the seabed (y≈-5), `is_on_floor()` is true and water-bank plays. The "water splash" sample should be an underwater-style sound, not surface splashing. Worth noting at clip-selection time.

7. **3D water emitter at origin doesn't simulate sound coming from "the water all around."** If the player walks to the far end of the island (z=-150) where there's water below them, the water sound is loudest BEHIND them (toward origin) rather than below. Spatial inaccuracy is acceptable for v1 — most players don't notice unless explicitly listening. Polish path documented in Out of Scope.

## Out of scope (deferred)

- Music
- Multi-emitter water lap (one per shore quadrant or moving emitter following player)
- Wind variation by elevation or position
- Wildlife (birds, insects, ambient animals)
- Footstep audio for sprint, jump landings, falls
- Audio buses + Master/SFX/Music volume sliders
- UI sound effects (menu, button clicks)
- Reverb zones (caves, tunnels)
- 3D positional wind for spec'd-out gusts
- Footstep variation for the "edge" of biomes (ground transitions)
- Splash particles when entering water
- Footstep frequency scaling with player movement speed (relevant when sprint exists)

## Success criteria

- Wind ambient is audible everywhere, soft enough not to dominate.
- Water lap is clearly louder near the shore, quieter on the hilltop.
- Footsteps audibly differ between grass area, sand area, and (if achievable) water area.
- Same surface doesn't make the same sound twice in a row obviously (random pick + pitch variation breaks repetition).
- No looping clicks.
- No volume that makes the player want to mute the game.
