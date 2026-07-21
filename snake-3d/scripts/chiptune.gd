extends Node

const MIX_RATE := 22050.0
const SFX_POOL_SIZE := 6
const MUSIC_STEP_DURATION := 0.15

# Natural minor scale (semitone offsets from root) used for all procedural melody/bass generation.
const SCALE := [0, 2, 3, 5, 7, 8, 10]
const ROOT_BASS := 110.0
const ROOT_LEAD := 440.0

# Chord progressions, expressed as scale-degree indices (0-based into SCALE, can exceed
# SCALE.size() to reach into the next octave). Each section below picks one of these.
const PROG_VERSE := [0, 5, 3, 4]
const PROG_CHORUS := [0, 3, 4, 0]
const PROG_INTERLUDE := [5, 3]

var _lead_player: AudioStreamPlayer
var _bass_player: AudioStreamPlayer
var _perc_player: AudioStreamPlayer
var _hihat_player: AudioStreamPlayer
var _sfx_players: Array = []
var _sfx_index: int = 0
var _music_timer: float = 0.0

var _song: Array = []
var _song_step: int = 0

# Held off until the splash video (which has its own audio track) finishes,
# so the two don't play over each other. GameManager flips this on once the
# splash ends or is skipped.
var music_enabled: bool = false

# Master mute -- silences both music and SFX. Persisted preference, set by
# GameManager from the title screen's mute toggle.
var master_muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lead_player = _make_player(1.0, -9.0)
	_bass_player = _make_player(1.0, -8.0)
	_perc_player = _make_player(0.5, -7.0)
	_hihat_player = _make_player(0.3, -12.0)
	for i in range(SFX_POOL_SIZE):
		_sfx_players.append(_make_player(0.6, -6.0))
	_generate_song()


func _process(delta: float) -> void:
	if not music_enabled or master_muted:
		return
	_music_timer += delta
	while _music_timer >= MUSIC_STEP_DURATION:
		_music_timer -= MUSIC_STEP_DURATION
		_advance_music_step()


func _make_player(buffer_length: float, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = buffer_length
	player.stream = gen
	player.volume_db = volume_db
	add_child(player)
	player.play()
	return player


func _advance_music_step() -> void:
	if _song.is_empty():
		return
	var ev: Dictionary = _song[_song_step % _song.size()]
	_song_step += 1

	var lead_freq: float = ev.lead
	if lead_freq > 0.0:
		var lead_wave: String = ev.lead_wave
		_push_to_player(_lead_player, _generate_tone(lead_freq, MUSIC_STEP_DURATION * 0.85, lead_wave, 0.16))

	var bass_freq: float = ev.bass
	if bass_freq > 0.0:
		_push_to_player(_bass_player, _generate_tone(bass_freq, MUSIC_STEP_DURATION * 0.95, "square", 0.16))

	var drums: Array = ev.drums
	for d in drums:
		if d == "hihat":
			_push_to_player(_hihat_player, _build_drum(d))
		else:
			_push_to_player(_perc_player, _build_drum(d))


func _generate_song() -> void:
	_song = []
	var srng := RandomNumberGenerator.new()
	srng.randomize()

	# Pop-song-ish arc: verse -> chorus -> verse -> chorus -> interlude (sparse, open,
	# different timbre) -> final chorus, then the whole thing loops.
	_song.append_array(_gen_section(PROG_VERSE, 16, 0.5, "pulse25", true, srng))
	_song.append_array(_gen_section(PROG_CHORUS, 16, 0.8, "square", true, srng))
	_song.append_array(_gen_section(PROG_VERSE, 16, 0.55, "pulse25", true, srng))
	_song.append_array(_gen_section(PROG_CHORUS, 16, 0.85, "square", true, srng))
	_song.append_array(_gen_section(PROG_INTERLUDE, 16, 0.3, "triangle", false, srng))
	_song.append_array(_gen_section(PROG_CHORUS, 24, 0.9, "square", true, srng))


func _gen_section(progression: Array, length: int, density: float, lead_wave: String, has_drums: bool, srng: RandomNumberGenerator) -> Array:
	var steps: Array = []
	var steps_per_chord := maxi(1, length / progression.size())
	var prev_degree := 0
	for i in range(length):
		var chord_idx: int = mini(progression.size() - 1, i / steps_per_chord)
		var chord_root: int = progression[chord_idx]
		var is_last_step := i == length - 1

		var lead_freq := 0.0
		if not is_last_step and srng.randf() < density:
			var degree: int
			if i % 4 == 0:
				var chord_tones := [0, 2, 4]
				var tone: int = chord_tones[srng.randi_range(0, 2)]
				degree = chord_root + tone
			else:
				degree = prev_degree + srng.randi_range(-1, 1)
				degree = clampi(degree, chord_root - 1, chord_root + 6)
			prev_degree = degree
			lead_freq = _degree_freq(ROOT_LEAD, degree)

		var bass_freq := 0.0
		var bass_on := true if has_drums else (i % 2 == 0)
		if bass_on and not is_last_step:
			bass_freq = _degree_freq(ROOT_BASS, chord_root)

		var drums: Array = []
		if has_drums and not is_last_step:
			if i % 8 == 0:
				drums.append("kick")
			if i % 8 == 4:
				drums.append("snare")
			if i % 2 == 1 and srng.randf() < 0.7:
				drums.append("hihat")

		steps.append({"lead": lead_freq, "lead_wave": lead_wave, "bass": bass_freq, "drums": drums})
	return steps


func _degree_freq(root: float, degree: int) -> float:
	var scale_size := SCALE.size()
	var octave := int(floor(float(degree) / scale_size))
	var idx := degree - octave * scale_size
	var semitone: int = SCALE[idx] + octave * 12
	return root * pow(2.0, float(semitone) / 12.0)


func _build_drum(drum_name: String) -> PackedFloat32Array:
	match drum_name:
		"kick":
			return _sweep(160.0, 45.0, 0.1, "square", 0.4)
		"snare":
			return _generate_tone(0.0, 0.08, "noise", 0.3)
		"hihat":
			return _generate_tone(0.0, 0.035, "noise", 0.13)
		_:
			return PackedFloat32Array()


func _push_to_player(player: AudioStreamPlayer, samples: PackedFloat32Array) -> void:
	if samples.is_empty():
		return
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	pb.push_buffer(_to_stereo(samples))


func play_sfx(sfx_name: String) -> void:
	if master_muted:
		return
	var samples := _build_sfx(sfx_name)
	if samples.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_index % _sfx_players.size()]
	_sfx_index += 1
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	pb.clear_buffer()
	pb.push_buffer(_to_stereo(samples))


func _build_sfx(sfx_name: String) -> PackedFloat32Array:
	match sfx_name:
		"eat":
			return _generate_tone(600.0, 0.08, "square", 0.22)
		"powerup_rainbow":
			return _mix(_arp([440.0, 554.4, 659.3, 880.0], 0.06, "pulse25", 0.2), _sweep(160.0, 55.0, 0.05, "square", 0.25))
		"powerup_yellow":
			return _mix(_arp([392.0, 493.9, 587.3, 784.0], 0.06, "pulse25", 0.2), _sweep(160.0, 55.0, 0.05, "square", 0.25))
		"powerup_red":
			return _mix(_arp([329.6, 415.3, 493.9, 659.3], 0.06, "pulse25", 0.2), _sweep(160.0, 55.0, 0.05, "square", 0.25))
		"powerup_blue":
			return _mix(_arp([349.2, 440.0, 523.3, 698.5], 0.06, "pulse25", 0.2), _sweep(160.0, 55.0, 0.05, "square", 0.25))
		"obstacle_destroy":
			return _mix(_generate_tone(0.0, 0.18, "noise", 0.22), _sweep(180.0, 40.0, 0.16, "square", 0.3))
		"turret_fire":
			return _generate_tone(900.0, 0.05, "pulse25", 0.16)
		"player_shot":
			return _sweep(1100.0, 650.0, 0.06, "pulse25", 0.18)
		"steal":
			return _sweep(700.0, 300.0, 0.1, "pulse25", 0.2)
		"enemy_down":
			return _mix(_sweep(500.0, 90.0, 0.22, "square", 0.24), _generate_tone(0.0, 0.15, "noise", 0.18))
		"hit":
			return _sweep(500.0, 120.0, 0.18, "square", 0.24)
		"death":
			return _sweep(300.0, 40.0, 0.5, "noise", 0.26)
		"high_score":
			return _arp([523.3, 659.3, 784.0, 1046.5], 0.09, "square", 0.22)
		"start":
			return _arp([392.0, 523.3, 659.3], 0.08, "pulse25", 0.22)
		"level_up":
			return _arp([392.0, 493.9, 587.3, 784.0, 987.8], 0.09, "square", 0.24)
		"powerup_neon_speed":
			return _arp([600.0, 900.0, 1200.0], 0.04, "pulse25", 0.2)
		"powerup_mirage":
			return _sweep(700.0, 250.0, 0.22, "triangle", 0.18)
		"powerup_ice_shield":
			return _mix(_generate_tone(500.0, 0.16, "triangle", 0.2), _generate_tone(750.0, 0.16, "pulse25", 0.14))
		"powerup_boulder_burst":
			return _mix(_sweep(200.0, 50.0, 0.25, "square", 0.3), _generate_tone(0.0, 0.2, "noise", 0.2))
		"powerup_crystal_growth":
			return _arp([659.3, 830.6, 1046.5, 1318.5], 0.05, "triangle", 0.2)
		"powerup_magma_trail":
			return _mix(_generate_tone(0.0, 0.22, "noise", 0.2), _sweep(150.0, 350.0, 0.22, "square", 0.22))
		"powerup_laser":
			return _mix(_arp([700.0, 1000.0, 1400.0], 0.05, "pulse25", 0.2), _sweep(1200.0, 2000.0, 0.08, "square", 0.2))
		"powerup_scatter":
			return _mix(_generate_tone(0.0, 0.1, "noise", 0.22), _arp([600.0, 750.0, 900.0], 0.04, "pulse25", 0.18))
		"powerup_nova":
			return _mix(_sweep(250.0, 60.0, 0.3, "square", 0.3), _generate_tone(0.0, 0.28, "noise", 0.24))
		_:
			return PackedFloat32Array()


func _arp(freqs: Array, note_dur: float, wave: String, volume: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		out.append_array(_generate_tone(f, note_dur, wave, volume))
	return out


func _generate_tone(freq: float, duration: float, wave: String, volume: float) -> PackedFloat32Array:
	var sample_count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var phase := 0.0
	var phase_inc := freq / MIX_RATE
	var attack := mini(sample_count / 8, int(0.01 * MIX_RATE))
	var release := sample_count / 3
	for i in range(sample_count):
		var env := 1.0
		if i < attack and attack > 0:
			env = float(i) / attack
		elif i > sample_count - release and release > 0:
			env = float(sample_count - i) / release
		samples[i] = _wave_sample(wave, phase) * volume * env
		phase += phase_inc
	return samples


func _sweep(freq_from: float, freq_to: float, duration: float, wave: String, volume: float) -> PackedFloat32Array:
	var sample_count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var phase := 0.0
	for i in range(sample_count):
		var t := float(i) / sample_count
		var freq: float = lerp(freq_from, freq_to, t)
		var env := 1.0 - t
		samples[i] = _wave_sample(wave, phase) * volume * env
		phase += freq / MIX_RATE
	return samples


func _wave_sample(wave: String, phase: float) -> float:
	var f := fmod(phase, 1.0)
	match wave:
		"square":
			return 1.0 if f < 0.5 else -1.0
		"pulse25":
			return 1.0 if f < 0.25 else -1.0
		"triangle":
			return absf(f * 4.0 - 2.0) - 1.0
		"noise":
			return randf_range(-1.0, 1.0)
		_:
			return sin(phase * TAU)


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var va: float = a[i] if i < a.size() else 0.0
		var vb: float = b[i] if i < b.size() else 0.0
		out[i] = clampf(va + vb, -1.0, 1.0)
	return out


func _to_stereo(mono: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(mono.size())
	for i in range(mono.size()):
		out[i] = Vector2(mono[i], mono[i])
	return out
