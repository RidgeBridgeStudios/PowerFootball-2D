##
## WhistleSynthesizer
##
## Pure GDScript procedural dual-tone FM audio synthesizer for realistic soccer referee
## whistles. Generates 16-bit PCM AudioStreamWAV streams with pea flutter / trill frequency
## modulation and harmonic overtones, plus visual expanding whistle shockwaves.
## Zero external .wav dependencies required.
##
## Depends on: AudioStreamPlayer2D, AudioStreamWAV.
## Exposes: play_short_blast(), play_hard_blast(), play_double_blast(),
##          play_triple_blast(), play_kickoff_blast(), emit_visual_whistle()
##

class_name WhistleSynthesizer
extends Node2D

enum WhistleType {
	SHORT_BLAST,
	HARD_BLAST,
	DOUBLE_BLAST,
	TRIPLE_BLAST,
	KICKOFF_BLAST
}

const SAMPLE_RATE: int = 22050
const CARRIER_FREQ: float = 2850.0      ## Primary whistle cavity resonance
const HARMONIC_FREQ: float = 3200.0     ## Second harmonic overtone
const TRILL_FREQ: float = 32.0          ## Pea spin flutter modulation
const TRILL_DEPTH: float = 0.18

var _player: AudioStreamPlayer2D = null
var _streams: Dictionary = {}

## Active visual whistle expanding rings
var _active_rings: Array[Dictionary] = []


func _ready() -> void:
	z_index = 5
	_player = AudioStreamPlayer2D.new()
	_player.name = "AudioPlayer"
	_player.bus = "Master"
	_player.max_distance = 2500.0
	_player.attenuation = 0.6
	add_child(_player)

	_generate_all_whistles()


func _process(delta: float) -> void:
	if _active_rings.is_empty():
		return

	var i: int = _active_rings.size() - 1
	while i >= 0:
		var ring: Dictionary = _active_rings[i]
		ring["time"] = float(ring["time"]) + delta
		var t: float = float(ring["time"]) / float(ring["duration"])
		if t >= 1.0:
			_active_rings.remove_at(i)
		else:
			ring["radius"] = lerpf(float(ring["start_radius"]), float(ring["end_radius"]), t)
			ring["alpha"] = lerpf(float(ring["start_alpha"]), 0.0, t * t)
		i -= 1

	queue_redraw()


func _draw() -> void:
	for ring: Dictionary in _active_rings:
		var center: Vector2 = ring["pos"] - global_position
		var radius: float = ring["radius"]
		var alpha: float = ring["alpha"]
		var col: Color = Color(1.0, 1.0, 0.4, alpha)
		var inner_col: Color = Color(1.0, 1.0, 1.0, alpha * 0.8)
		draw_arc(center, radius, 0.0, TAU, 24, col, 2.0, true)
		if radius > 6.0:
			draw_arc(center, radius * 0.65, 0.0, TAU, 20, inner_col, 1.5, true)


## Trigger visual acoustic shockwave puff at given world position.
func emit_visual_whistle(world_pos: Vector2, intensity: float = 1.0) -> void:
	var ring: Dictionary = {
		"pos": world_pos,
		"time": 0.0,
		"duration": 0.45 * intensity,
		"start_radius": 4.0,
		"end_radius": 42.0 * intensity,
		"start_alpha": 0.85,
		"radius": 4.0,
		"alpha": 0.85
	}
	_active_rings.append(ring)
	queue_redraw()


func play_short_blast(world_pos: Vector2 = Vector2.ZERO) -> void:
	_play_stream(WhistleType.SHORT_BLAST, world_pos, 0.9)


func play_hard_blast(world_pos: Vector2 = Vector2.ZERO) -> void:
	_play_stream(WhistleType.HARD_BLAST, world_pos, 1.3)


func play_double_blast(world_pos: Vector2 = Vector2.ZERO) -> void:
	_play_stream(WhistleType.DOUBLE_BLAST, world_pos, 1.1)


func play_triple_blast(world_pos: Vector2 = Vector2.ZERO) -> void:
	_play_stream(WhistleType.TRIPLE_BLAST, world_pos, 1.2)


func play_kickoff_blast(world_pos: Vector2 = Vector2.ZERO) -> void:
	_play_stream(WhistleType.KICKOFF_BLAST, world_pos, 1.0)


func _play_stream(type: WhistleType, world_pos: Vector2, intensity: float) -> void:
	if not _streams.has(type):
		return
	if world_pos != Vector2.ZERO:
		global_position = world_pos
		emit_visual_whistle(world_pos, intensity)
	else:
		emit_visual_whistle(global_position, intensity)

	_player.stream = _streams[type] as AudioStreamWAV
	_player.pitch_scale = randf_range(0.97, 1.03)
	_player.volume_db = 2.0 + (intensity - 1.0) * 3.0
	_player.play()


func _generate_all_whistles() -> void:
	_streams[WhistleType.SHORT_BLAST] = _synthesize_pattern([
		{"duration": 0.22, "intensity": 0.85, "attack": 0.015, "release": 0.03}
	])

	_streams[WhistleType.HARD_BLAST] = _synthesize_pattern([
		{"duration": 0.42, "intensity": 1.0, "attack": 0.01, "release": 0.05}
	])

	_streams[WhistleType.DOUBLE_BLAST] = _synthesize_pattern([
		{"duration": 0.18, "intensity": 0.9, "attack": 0.015, "release": 0.02},
		{"gap": 0.08},
		{"duration": 0.26, "intensity": 0.95, "attack": 0.015, "release": 0.04}
	])

	_streams[WhistleType.TRIPLE_BLAST] = _synthesize_pattern([
		{"duration": 0.16, "intensity": 0.85, "attack": 0.015, "release": 0.02},
		{"gap": 0.07},
		{"duration": 0.16, "intensity": 0.85, "attack": 0.015, "release": 0.02},
		{"gap": 0.07},
		{"duration": 0.45, "intensity": 1.0, "attack": 0.01, "release": 0.06}
	])

	_streams[WhistleType.KICKOFF_BLAST] = _synthesize_pattern([
		{"duration": 0.35, "intensity": 0.9, "attack": 0.02, "release": 0.04}
	])


func _synthesize_pattern(segments: Array[Dictionary]) -> AudioStreamWAV:
	var total_samples: int = 0
	for seg: Dictionary in segments:
		if seg.has("duration"):
			total_samples += int(float(seg["duration"]) * float(SAMPLE_RATE))
		elif seg.has("gap"):
			total_samples += int(float(seg["gap"]) * float(SAMPLE_RATE))

	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(total_samples * 2)

	var write_idx: int = 0
	var phase_c: float = 0.0
	var phase_h: float = 0.0
	var phase_trill: float = 0.0

	for seg: Dictionary in segments:
		if seg.has("gap"):
			var gap_samples: int = int(float(seg["gap"]) * float(SAMPLE_RATE))
			for s: int in range(gap_samples):
				buffer[write_idx] = 0
				buffer[write_idx + 1] = 0
				write_idx += 2
			continue

		var seg_dur: float = float(seg.get("duration", 0.2))
		var intensity: float = float(seg.get("intensity", 1.0))
		var attack: float = float(seg.get("attack", 0.015))
		var release: float = float(seg.get("release", 0.03))
		var seg_samples: int = int(seg_dur * float(SAMPLE_RATE))

		var attack_samples: int = int(attack * float(SAMPLE_RATE))
		var release_start: int = max(0, seg_samples - int(release * float(SAMPLE_RATE)))

		for s: int in range(seg_samples):
			# Envelope
			var env: float = 1.0
			if s < attack_samples and attack_samples > 0:
				env = float(s) / float(attack_samples)
			elif s >= release_start:
				var r_len: int = seg_samples - release_start
				env = 1.0 - (float(s - release_start) / float(max(1, r_len)))

			# Trill modulation (spinning pea turbulence)
			phase_trill += TAU * TRILL_FREQ / float(SAMPLE_RATE)
			if phase_trill > TAU:
				phase_trill -= TAU
			var trill_mod: float = 1.0 + sin(phase_trill) * TRILL_DEPTH

			# Subtle noise jitter for breath turbulence
			var noise_val: float = (randf() * 2.0 - 1.0) * 0.06

			# Frequencies
			var freq_c: float = CARRIER_FREQ * trill_mod
			var freq_h: float = HARMONIC_FREQ * trill_mod

			phase_c += TAU * freq_c / float(SAMPLE_RATE)
			if phase_c > TAU:
				phase_c -= TAU
			phase_h += TAU * freq_h / float(SAMPLE_RATE)
			if phase_h > TAU:
				phase_h -= TAU

			# Dual tone mix with slight saturation
			var tone: float = sin(phase_c) * 0.70 + sin(phase_h) * 0.30 + noise_val
			var sample_val: float = clampf(tone * env * intensity * 0.85, -1.0, 1.0)

			var sample_int: int = clampi(int(sample_val * 32767.0), -32768, 32767)
			buffer[write_idx] = sample_int & 0xFF
			buffer[write_idx + 1] = (sample_int >> 8) & 0xFF
			write_idx += 2

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = buffer
	return stream
