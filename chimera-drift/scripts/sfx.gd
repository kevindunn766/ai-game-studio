extends Node

# ============================================================================
# Sfx — Chimera Drift sound-effects synthesizer (autoload `Sfx`).
# Every effect is SYNTHESIZED procedurally at boot (no audio files) and baked to a
# small AudioStreamWAV, then played through a round-robin AudioStreamPlayer pool.
# Style: RETRO but PlayStation-era, not raw chiptune -- richer timbres via FM zaps,
# detuned oscillator stacks, filtered-noise impacts, and short feedback-delay REVERB
# tails (the PS1 SPU signature). Call Sfx.play("name") from anywhere.
# ============================================================================

const MIX_RATE := 32000.0
const POOL_SIZE := 10

var muted: bool = false
var _bank: Dictionary = {}          # name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _idx: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.volume_db = -5.0
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_bake_bank()

# Play a baked effect. `pitch` sets base speed; `pitch_var` adds +/- random spread
# so repeated sounds (shots, hits) don't feel machine-gun identical.
func play(name: String, pitch: float = 1.0, pitch_var: float = 0.06) -> void:
	if muted:
		return
	var wav: AudioStreamWAV = _bank.get(name)
	if wav == null:
		return
	var p: AudioStreamPlayer = _players[_idx % _players.size()]
	_idx += 1
	p.stream = wav
	p.pitch_scale = maxf(0.2, pitch + randf_range(-pitch_var, pitch_var))
	p.play()

# ---------------------------------------------------------------------------
# The catalog. Each entry composes the primitives below into a PS1-flavoured hit.
# ---------------------------------------------------------------------------
func _bake_bank() -> void:
	# --- combat ---
	_bank["shoot"] = _bake(_verb(_mix([
		_fm(900.0, 320.0, 0.10, 2.0, 3.2, 0.34),
		_noise(0.02, 0.18, 7000.0, 2200.0, 1.6)]), 0.14, 0.30, 40.0))
	_bank["enemy_hit"] = _bake(_mix([
		_synth(1250.0, 720.0, 0.05, "square", 0.22, 0.0, 0.5, 0.004, 0.4),
		_noise(0.035, 0.20, 8000.0, 3000.0, 1.4)]))
	_bank["enemy_down"] = _bake(_verb(_mix([
		_synth(520.0, 80.0, 0.24, "saw", 0.30, 0.012, 0.5, 0.004, 0.7),
		_noise(0.24, 0.34, 5200.0, 400.0, 1.2)]), 0.26, 0.42, 60.0))
	_bank["weak_pop"] = _bake(_verb(_mix([
		_synth(920.0, 200.0, 0.12, "square", 0.30, 0.0, 0.5, 0.003, 0.6),
		_noise(0.13, 0.30, 9000.0, 1500.0, 1.2)]), 0.24, 0.40, 50.0))
	# --- player state ---
	_bank["hurt"] = _bake(_verb(_mix([
		_synth(270.0, 120.0, 0.18, "saw", 0.34, 0.016, 0.5, 0.003, 0.7),
		_noise(0.05, 0.24, 3000.0, 600.0, 1.5)]), 0.15, 0.30, 45.0))
	_bank["shield"] = _bake(_verb(_mix([
		_synth(1400.0, 1400.0, 0.15, "sine", 0.22, 0.010, 0.5, 0.004, 0.8),
		_synth(2100.0, 2100.0, 0.15, "sine", 0.13, 0.008, 0.5, 0.004, 0.8)]), 0.32, 0.45, 55.0))
	_bank["death"] = _bake(_verb(_mix([
		_synth(300.0, 42.0, 0.72, "saw", 0.34, 0.02, 0.5, 0.004, 1.0),
		_noise(0.72, 0.30, 4200.0, 180.0, 1.3)]), 0.36, 0.55, 85.0))
	_bank["boost"] = _bake(_verb(_mix([
		_noise(0.5, 0.32, 320.0, 4200.0, 0.7),
		_synth(120.0, 420.0, 0.42, "saw", 0.20, 0.02, 0.5, 0.01, 0.8)]), 0.22, 0.4, 60.0))
	# --- pickups ---
	_bank["pickup"] = _bake(_verb(_seq([
		_synth(660.0, 660.0, 0.05, "tri", 0.26, 0.0, 0.5, 0.003, 0.5),
		_synth(880.0, 880.0, 0.05, "tri", 0.26, 0.0, 0.5, 0.003, 0.5),
		_synth(1320.0, 1320.0, 0.09, "tri", 0.28, 0.0, 0.5, 0.003, 0.7)]), 0.3, 0.42, 45.0))
	_bank["part"] = _bake(_verb(_mix([
		_noise(0.04, 0.28, 2000.0, 300.0, 1.4),
		_seq([_synth(440.0, 440.0, 0.05, "square", 0.22, 0.0, 0.5, 0.003, 0.4),
			_synth(880.0, 1180.0, 0.13, "tri", 0.28, 0.0, 0.5, 0.003, 0.8)])]), 0.26, 0.42, 55.0))
	# --- boss ---
	_bank["boss_warn"] = _bake(_verb(_mix([
		_seq([_synth(220.0, 175.0, 0.26, "pulse", 0.30, 0.012, 0.28, 0.01, 0.7),
			_synth(200.0, 160.0, 0.26, "pulse", 0.30, 0.012, 0.28, 0.01, 0.7)]),
		_synth(70.0, 60.0, 0.52, "sine", 0.22, 0.0, 0.5, 0.02, 1.0)]), 0.4, 0.55, 95.0))
	_bank["boss_die"] = _bake(_verb(_verb(_mix([
		_synth(210.0, 30.0, 0.95, "saw", 0.40, 0.03, 0.5, 0.006, 1.1),
		_noise(0.95, 0.40, 6500.0, 150.0, 1.4)]), 0.35, 0.55, 70.0), 0.3, 0.5, 130.0))
	# --- menu / flow ---
	_bank["ui_move"] = _bake(_synth(720.0, 720.0, 0.035, "pulse", 0.18, 0.0, 0.30, 0.002, 0.4))
	_bank["ui_confirm"] = _bake(_verb(_seq([
		_synth(660.0, 660.0, 0.05, "tri", 0.22, 0.0, 0.5, 0.003, 0.4),
		_synth(990.0, 990.0, 0.09, "tri", 0.24, 0.0, 0.5, 0.003, 0.7)]), 0.22, 0.35, 40.0))
	_bank["ui_back"] = _bake(_synth(520.0, 300.0, 0.09, "tri", 0.20, 0.0, 0.5, 0.003, 0.6))
	_bank["reroll"] = _bake(_verb(_seq([
		_synth(500.0, 500.0, 0.03, "pulse", 0.17, 0.0, 0.3, 0.002, 0.4),
		_synth(650.0, 650.0, 0.03, "pulse", 0.17, 0.0, 0.3, 0.002, 0.4),
		_synth(820.0, 820.0, 0.03, "pulse", 0.18, 0.0, 0.3, 0.002, 0.4),
		_synth(1040.0, 1040.0, 0.05, "pulse", 0.20, 0.0, 0.3, 0.002, 0.6)]), 0.2, 0.35, 40.0))
	_bank["win"] = _bake(_verb(_seq([
		_synth(523.3, 523.3, 0.10, "tri", 0.26, 0.006, 0.5, 0.004, 0.5),
		_synth(659.3, 659.3, 0.10, "tri", 0.26, 0.006, 0.5, 0.004, 0.5),
		_synth(784.0, 784.0, 0.10, "tri", 0.26, 0.006, 0.5, 0.004, 0.5),
		_synth(1046.5, 1046.5, 0.24, "tri", 0.30, 0.006, 0.5, 0.004, 0.9)]), 0.35, 0.5, 60.0))

# ---------------------------------------------------------------------------
# Synthesis primitives (all return PackedFloat32Array of mono float samples).
# ---------------------------------------------------------------------------

# Detuned oscillator stack with an exponential pitch sweep + short attack / power
# release. `detune` spreads two extra voices for a fuller, less "beepy" tone.
func _synth(f0: float, f1: float, dur: float, wave: String, vol: float,
		detune: float = 0.006, pw: float = 0.5, atk: float = 0.004, rel: float = 0.6) -> PackedFloat32Array:
	var n: int = int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a: float = maxf(f0, 1.0)
	var b: float = maxf(f1, 1.0)
	var ph1: float = 0.0
	var ph2: float = 0.0
	var ph3: float = 0.0
	var atk_n: int = maxi(1, int(atk * MIX_RATE))
	for i in range(n):
		var t: float = float(i) / float(n)
		var f: float = a * pow(b / a, t)
		var env: float
		if i < atk_n:
			env = float(i) / float(atk_n)
		else:
			env = pow(1.0 - float(i - atk_n) / float(maxi(1, n - atk_n)), 1.0 + rel * 2.0)
		var s: float = _wave(wave, ph1, pw)
		if detune > 0.0:
			s = (s + _wave(wave, ph2, pw) * 0.8 + _wave(wave, ph3, pw) * 0.6) / 2.4
		out[i] = s * vol * env
		ph1 += f / MIX_RATE
		ph2 += f * (1.0 + detune) / MIX_RATE
		ph3 += f * (1.0 - detune) / MIX_RATE
	return out

# 2-operator FM (carrier modulated by a sine) -- great for zaps/lasers.
func _fm(f0: float, f1: float, dur: float, ratio: float, amt: float, vol: float, rel: float = 0.7) -> PackedFloat32Array:
	var n: int = int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a: float = maxf(f0, 1.0)
	var b: float = maxf(f1, 1.0)
	var cph: float = 0.0
	var mph: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var f: float = a * pow(b / a, t)
		var env: float = pow(1.0 - t, 1.0 + rel * 2.0)
		var m: float = sin(TAU * mph) * amt
		out[i] = sin(TAU * (cph + m)) * vol * env
		cph += f / MIX_RATE
		mph += f * ratio / MIX_RATE
	return out

# Noise with a swept one-pole low-pass (bright -> dark = the classic impact tail).
func _noise(dur: float, vol: float, cut0: float, cut1: float, rel: float = 1.0) -> PackedFloat32Array:
	var n: int = int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var cut: float = maxf(cut0, 1.0) * pow(maxf(cut1, 1.0) / maxf(cut0, 1.0), t)
		var coef: float = clampf(cut / (MIX_RATE * 0.5), 0.02, 0.99)
		var raw: float = randf() * 2.0 - 1.0
		lp += coef * (raw - lp)
		out[i] = lp * vol * pow(1.0 - t, rel)
	return out

func _wave(kind: String, phase: float, pw: float) -> float:
	var f: float = fposmod(phase, 1.0)
	match kind:
		"sine":
			return sin(TAU * f)
		"saw":
			return 2.0 * f - 1.0
		"square":
			return 1.0 if f < 0.5 else -1.0
		"pulse":
			return 1.0 if f < pw else -1.0
		"tri":
			return 4.0 * absf(f - 0.5) - 1.0
		_:
			return randf() * 2.0 - 1.0

# Feedback-delay "reverb": a decaying echo tail added after the dry signal. Cheap
# stand-in for the PS1 SPU reverb that gives the effects their spacey body.
func _verb(dry: PackedFloat32Array, mix: float, decay: float, delay_ms: float) -> PackedFloat32Array:
	var d: int = maxi(1, int(delay_ms * 0.001 * MIX_RATE))
	var tail: int = int(0.35 * MIX_RATE)
	var n: int = dry.size() + tail
	var out := PackedFloat32Array()
	out.resize(n)
	var wet := PackedFloat32Array()
	wet.resize(n)
	for i in range(n):
		out[i] = dry[i] if i < dry.size() else 0.0
	for i in range(n):
		var inp: float = out[i - d] if i >= d else 0.0
		var fb: float = wet[i - d] * decay if i >= d else 0.0
		wet[i] = inp + fb
	for i in range(n):
		out[i] += wet[i] * mix
	return out

# Sum several buffers (aligned at the start; padded to the longest).
func _mix(parts: Array) -> PackedFloat32Array:
	var n: int = 0
	for p in parts:
		n = maxi(n, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var arr: PackedFloat32Array = p
		for i in range(arr.size()):
			out[i] += arr[i]
	return out

# Concatenate buffers end-to-end (for arpeggios / jingles).
func _seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out

# Normalize to a target peak, then convert to a 16-bit mono AudioStreamWAV.
func _bake(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak: float = 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var g: float = minf(1.0, 0.85 / peak)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: int = int(clampf(samples[i] * g, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = bytes
	return wav
