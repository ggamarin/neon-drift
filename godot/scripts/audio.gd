extends Node
# Звук демо. Всё синтезируется кодом при запуске — звуковых файлов в проекте нет.
#   эффекты  — короткие сигналы: клик, удар, урон, подбор, тревога, победа, поражение;
#   мотор    — зацикленный гул, высота и громкость зависят от скорости;
#   дождь    — зацикленный шум;
#   музыка   — петля на 4 такта (пэд, бас, арпеджио) и отдельная дорожка ударных,
#              которая звучит только в бою. Музыка строится по кусочку за кадр, чтобы не подвешивать запуск.

signal music_ready

const RATE = 22050        # эффекты и петли окружения
const MRATE = 11025       # музыка: нарочно «lo-fi», вдвое дешевле в синтезе
const BEAT = 0.6          # 100 ударов в минуту
const BARS = 4

# Аккорды петли: ля минор — фа — до — соль. [бас, три ноты пэда]
const CHORDS = [
	[110.0, 220.0, 261.63, 329.63],
	[87.31, 174.61, 220.0, 261.63],
	[130.81, 261.63, 329.63, 392.0],
	[98.0, 196.0, 246.94, 293.66],
]

var muted := false
var has_music := false

var _b := PackedFloat32Array()   # рабочий буфер синтеза
var _rate := RATE
var _streams := {}
var _pool: Array = []
var _next := 0
var _engine: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _music: AudioStreamPlayer
var _drums: AudioStreamPlayer

func _ready() -> void:
	for i in 8:
		var p = AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_build_sfx()
	_engine = _player(_make_engine(), -80.0)
	_rain = _player(_make_rain(), -80.0)
	_engine.play()
	_rain.play()
	_build_music()

# Останавливает всё, что играет. Вызывается перед выходом: звуковому серверу нужно
# пару кадров, чтобы отпустить воспроизведение, иначе движок сообщает об утечке.
func stop_all() -> void:
	for c in get_children():
		if c is AudioStreamPlayer: c.stop()

# ---------- управление ----------

func sfx(id: String, db: float = -9.0) -> void:
	if muted or not _streams.has(id): return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[id]
	p.volume_db = db
	p.play()

# Вызывается каждый кадр: подстраивает громкости и высоту мотора под происходящее.
func update(dt: float, screen: String, moving: bool, pitch: float) -> void:
	var k = minf(1.0, dt * 4.0)
	var off = -80.0
	_engine.volume_db = lerpf(_engine.volume_db, off if muted or not moving else -25.0, k)
	_engine.pitch_scale = lerpf(_engine.pitch_scale, pitch, k)
	_rain.volume_db = lerpf(_rain.volume_db, off if muted else -27.0, k)
	if has_music:
		_music.volume_db = lerpf(_music.volume_db, off if muted else (-19.0 if screen == "battle" else -16.0), k)
		_drums.volume_db = lerpf(_drums.volume_db, off if muted or screen != "battle" else -13.0, k)

# Сохраняет всё синтезированное в WAV — для проверки без звуковой карты.
func dump(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for id in _streams: _streams[id].save_to_wav(dir.path_join("sfx-" + id + ".wav"))
	_engine.stream.save_to_wav(dir.path_join("loop-engine.wav"))
	_rain.stream.save_to_wav(dir.path_join("loop-rain.wav"))
	if has_music:
		_music.stream.save_to_wav(dir.path_join("loop-music.wav"))
		_drums.stream.save_to_wav(dir.path_join("loop-drums.wav"))

# ---------- синтез ----------

func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p

func _begin(sec: float, rate: int) -> void:
	_rate = rate
	_b = PackedFloat32Array()
	_b.resize(int(sec * rate))
	_b.fill(0.0)

# Добавляет ноту в рабочий буфер.
# wave: 0 синус, 1 меандр, 2 пила, 3 шум, 4 мягкая пила, 5 мягкий меандр (суммы гармоник, без резких краёв).
# shape: 0 — щипок с затуханием, 1 — «подушка» sin² (соседние отрезки складываются в ровный звук), 2 — ровно.
# wrap: хвост, вышедший за конец буфера, заворачивается в начало — так петля получается бесшовной.
func _note(at: float, dur: float, f0: float, f1: float, wave: int, vol: float, attack: float = 0.004, shape: int = 0, wrap: bool = false) -> void:
	var n = _b.size()
	var start = int(at * _rate)
	var count = int(dur * _rate)
	var atk = maxf(1.0, attack * _rate)
	var phase = fmod(f0 * at, 1.0) if shape == 1 else 0.0
	for i in count:
		var k = float(i) / count
		phase += (f0 + (f1 - f0) * k) / _rate
		var v = 0.0
		if wave == 0: v = sin(phase * TAU)
		elif wave == 1: v = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		elif wave == 2: v = 2.0 * fmod(phase, 1.0) - 1.0
		elif wave == 3: v = randf() * 2.0 - 1.0
		elif wave == 4: v = sin(phase * TAU) + 0.45 * sin(phase * TAU * 2.0) + 0.22 * sin(phase * TAU * 3.0)
		else: v = sin(phase * TAU) + 0.33 * sin(phase * TAU * 3.0) + 0.16 * sin(phase * TAU * 5.0)
		var env = 1.0
		if shape == 1: env = pow(sin(PI * k), 2.0)
		elif shape == 2: env = minf(1.0, i / atk) * minf(1.0, (count - i) / atk)
		else: env = minf(1.0, i / atk) * (1.0 - k) * (1.0 - k)
		var j = start + i
		if j >= n:
			if not wrap: break
			j %= n
		_b[j] += v * env * vol

# Простой фильтр низких частот: сглаживает шум.
func _lowpass(alpha: float) -> void:
	var y = 0.0
	for i in _b.size():
		y += alpha * (_b[i] - y)
		_b[i] = y

# Делает петлю бесшовной: конец плавно переходит в начало, лишний хвост отрезается.
func _seam(fade_sec: float) -> void:
	var fade = int(fade_sec * _rate)
	var n = _b.size() - fade
	for i in fade:
		var k = float(i) / fade
		_b[i] = _b[i] * k + _b[n + i] * (1.0 - k)
	_b.resize(n)

func _finish(loop: bool, peak: float = 0.9) -> AudioStreamWAV:
	var top = 0.0001
	for v in _b: top = maxf(top, absf(v))
	var gain = peak / top
	var data = PackedByteArray()
	data.resize(_b.size() * 2)
	for i in _b.size(): data.encode_s16(i * 2, int(clampf(_b[i] * gain, -1.0, 1.0) * 32767.0))
	return _wav(data, loop)

func _wav(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = _rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() >> 1
	return w

func _build_sfx() -> void:
	_begin(0.06, RATE); _note(0, 0.06, 740, 740, 5, 1.0)
	_streams["click"] = _finish(false, 0.5)
	_begin(0.1, RATE); _note(0, 0.1, 300, 520, 0, 1.0)
	_streams["steer"] = _finish(false, 0.45)
	_begin(0.16, RATE); _note(0, 0.16, 240, 70, 1, 0.8); _note(0, 0.08, 0, 0, 3, 0.5)
	_streams["hit"] = _finish(false, 0.8)
	_begin(0.26, RATE); _note(0, 0.26, 150, 50, 2, 0.9); _note(0, 0.12, 0, 0, 3, 0.6)
	_streams["hurt"] = _finish(false, 0.9)
	_begin(0.2, RATE); _note(0, 0.09, 660, 660, 5, 1.0); _note(0.07, 0.13, 990, 990, 5, 1.0)
	_streams["pick"] = _finish(false, 0.6)
	_begin(0.1, RATE); _note(0, 0.1, 520, 520, 5, 1.0)
	_streams["ok"] = _finish(false, 0.5)
	_begin(0.2, RATE); _note(0, 0.2, 110, 60, 0, 1.0)
	_streams["turn"] = _finish(false, 0.8)
	_begin(0.5, RATE); _note(0, 0.16, 330, 330, 1, 1.0); _note(0.17, 0.16, 440, 440, 1, 1.0); _note(0.34, 0.16, 330, 330, 1, 1.0)
	_streams["alarm"] = _finish(false, 0.6)
	_begin(0.9, RATE); _note(0, 0.25, 523.25, 523.25, 5, 1.0); _note(0.14, 0.25, 659.25, 659.25, 5, 1.0); _note(0.28, 0.6, 783.99, 783.99, 5, 1.0)
	_streams["win"] = _finish(false, 0.7)
	_begin(0.7, RATE); _note(0, 0.7, 220, 55, 2, 1.0)
	_streams["lose"] = _finish(false, 0.8)

# Мотор: гул с гармониками и лёгкой пульсацией. Все частоты целые, поэтому секунда зацикливается без шва.
func _make_engine() -> AudioStreamWAV:
	_begin(1.0, RATE)
	for i in _b.size():
		var x = float(i) / RATE * TAU
		var v = 0.0
		for h in range(1, 6): v += sin(x * 60.0 * h) / h
		v *= 1.0 + 0.25 * sin(x * 12.0)
		v += 0.12 * sin(x * 420.0 + 2.0 * sin(x * 6.0))
		_b[i] = v
	return _finish(true, 0.8)

func _make_rain() -> AudioStreamWAV:
	_begin(3.3, RATE)
	for i in _b.size(): _b[i] = randf() * 2.0 - 1.0
	_lowpass(0.35)
	_seam(0.3)
	return _finish(true, 0.8)

# Музыка строится в фоне: после каждой ноты проверяем, не пора ли отдать кадр игре.
func _build_music() -> void:
	var length = BEAT * 4.0 * BARS
	var mark = Time.get_ticks_msec()
	# мелодическая дорожка: пэд, бас, арпеджио с эхом
	_begin(length, MRATE)
	for bar in BARS:
		var ch = CHORDS[bar]
		var t0 = bar * 4.0 * BEAT
		for seg in 8:                       # пэд: отрезки по одной доле с шагом в полдоли
			for q in 3:
				_note(t0 + seg * BEAT * 0.5, BEAT, ch[q + 1], ch[q + 1], 0, 0.16, 0.004, 1, true)
				if Time.get_ticks_msec() - mark > 5:
					await get_tree().process_frame
					mark = Time.get_ticks_msec()
		for e in 8:                         # бас: восьмые на тонике
			_note(t0 + e * BEAT * 0.5, BEAT * 0.45, ch[0], ch[0], 4, 0.3, 0.006, 0, true)
		for s in 16:                        # арпеджио: шестнадцатые по нотам аккорда октавой выше
			var f = ch[1 + [0, 1, 2, 1][s % 4]] * 2.0
			var at = t0 + s * BEAT * 0.25
			_note(at, BEAT * 0.4, f, f, 5, 0.14, 0.003, 0, true)
			_note(at + BEAT * 0.75, BEAT * 0.4, f, f, 5, 0.05, 0.003, 0, true)
			if Time.get_ticks_msec() - mark > 5:
				await get_tree().process_frame
				mark = Time.get_ticks_msec()
	var melody = await _finish_async(0.8)
	# ударные: бочка на 1 и 3, малый на 2 и 4, хэт на восьмых
	_begin(length, MRATE)
	for beat in BARS * 4:
		var at2 = beat * BEAT
		if beat % 2 == 0: _note(at2, 0.2, 130, 45, 0, 1.0, 0.002, 0, true)
		else:
			_note(at2, 0.14, 0, 0, 3, 0.5, 0.001, 0, true)
			_note(at2, 0.1, 190, 150, 0, 0.4, 0.001, 0, true)
		_note(at2, 0.035, 0, 0, 3, 0.16, 0.001, 0, true)
		_note(at2 + BEAT * 0.5, 0.035, 0, 0, 3, 0.22, 0.001, 0, true)
		if Time.get_ticks_msec() - mark > 5:
			await get_tree().process_frame
			mark = Time.get_ticks_msec()
	var drums = await _finish_async(0.85)
	_music = _player(melody, -80.0)
	_drums = _player(drums, -80.0)
	_music.play()
	_drums.play()
	has_music = true
	music_ready.emit()

# То же, что _finish для петли, но с передышками между кусками.
func _finish_async(peak: float) -> AudioStreamWAV:
	var top = 0.0001
	for v in _b: top = maxf(top, absf(v))
	await get_tree().process_frame
	var gain = peak / top
	var data = PackedByteArray()
	data.resize(_b.size() * 2)
	for i in _b.size():
		data.encode_s16(i * 2, int(clampf(_b[i] * gain, -1.0, 1.0) * 32767.0))
		if i % 20000 == 19999: await get_tree().process_frame
	return _wav(data, true)
