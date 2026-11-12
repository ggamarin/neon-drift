extends Node2D
# Neon Drift — демо на Godot 4. Вся игра собирается кодом из этого сценария:
#   scripts/model.gd — логика (порт JS-прототипа, проверен эталонными заездами),
#   scripts/data.gd  — контент (генерируется из src/data.js),
#   scripts/art.gd   — графика (полигоны, градиенты, свечение),
#   scripts/audio.gd — звук (синтезируется кодом при запуске),
#   main.gd          — экраны, ввод, подсказки.
# Интерфейс — immediate-mode: каждый кадр экран рисуется заново из состояния S,
# все изменения идут через go(action).

const M = preload("res://scripts/model.gd")
const D = preload("res://scripts/data.gd")
const A = preload("res://scripts/art.gd")
const Audio = preload("res://scripts/audio.gd")

const W = 1280.0
const H = 720.0
const PANEL_Y = 508.0
const CAR_X = 48.0
const COL_W = 128.0
const BAND_X = [300.0, 630.0, 960.0]
const BAND_W = 320.0
const BAND_NAME = ["ВПЛОТНУЮ", "СРЕДНЯЯ", "ДАЛЬНЯЯ"]
const BAND_REACH = ["таран · стволы · взлом", "стволы · взлом", "только взлом"]
const CAM = {"map": 150.0, "event": -200.0, "result": -200.0, "park": -200.0, "shop": -200.0}
const SPEED = {"title": 100.0, "battle": 230.0, "end": 60.0}

# Холст: узел, который каждый кадр перерисовывается заданной функцией.
class Canvas extends Node2D:
	var painter: Callable
	func _draw() -> void:
		if painter.is_valid(): painter.call(self)

var S                         # состояние модели
var font: Font
var g: CanvasItem             # холст, на котором сейчас рисует интерфейс
var node_col: Dictionary
var res_col: Dictionary

var sky: Canvas
var layers: Array = []        # [{a, b, speed, quiet}] — пары тайлов для бесшовной прокрутки
var world: Canvas
var hud: Canvas
var rain: CPUParticles2D
var audio: Node

var t := 0.0
var dt := 0.016
var scroll := 0.0
var cam := 0.0
var dim := 0.0
var mx := -1.0
var my := -1.0
var click := false
var cancel := false
var input_on := true
var keys_live := true
var keys: Array = []
var keep = null
var tip := ""
var sel_node := -1
var target = null
var trunk_open := false
var sel = null
var rot = null
var drop_ask = null
var floats: Array = []
var lock_until := 0.0
var shake_until := 0.0
var flash = null
var disp: Dictionary = {}
var acc := 0.0
var auto := true              # false останавливает самоход на дороге (для тестов)
var car_lane := 1.0
var car_px := 462.0
var coach = null
var coach_on := false
var hints_off := false
var seen: Dictionary = {}

# ---------- запуск ----------

func _ready() -> void:
	font = ThemeDB.fallback_font
	node_col = {"start": A.GREY, "road": A.MAG, "meet": A.PALE, "hitch": A.GREEN, "park": A.CYAN, "shop": A.AMB, "gate": A.RED, "hidden": A.VIOLET3}
	res_col = {"charge": A.CYAN, "hull": A.WHITE, "focus": A.LAV, "wanted": A.MAG, "credits": A.AMB}
	sky = _canvas(func(ci): A.paint_sky(ci))
	_layer(func(ci): A.paint_far(ci), 0.06, false)
	_layer(func(ci): A.paint_mid(ci, font), 0.22, true)
	_layer(func(ci): A.paint_near(ci, font), 0.5, true)
	_layer(func(ci): A.paint_road(ci), 1.0, false)
	world = _canvas(_paint_world)
	_make_rain()
	hud = _canvas(_paint_hud)
	audio = Audio.new()
	add_child(audio)
	_load_prefs()
	get_tree().set_auto_accept_quit(false)   # выходим сами: сначала глушим звук
	new_game(-1)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tour="): _run_tour(arg.trim_prefix("--tour="))
		elif arg == "--replay": _run_replay()
		elif arg.begins_with("--audio-dump="): _run_audio_dump(arg.trim_prefix("--audio-dump="))

func _canvas(painter: Callable) -> Canvas:
	var c = Canvas.new()
	c.painter = painter
	add_child(c)
	return c

func _layer(painter: Callable, speed: float, quiet: bool) -> void:
	layers.append({"a": _canvas(painter), "b": _canvas(painter), "speed": speed, "quiet": quiet})

func _make_rain() -> void:
	var gr = Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0))
	gr.set_color(1, Color(1, 1, 1, 1))
	var tex = GradientTexture2D.new()
	tex.gradient = gr
	tex.width = 2
	tex.height = 22
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	rain = CPUParticles2D.new()
	rain.texture = tex
	rain.amount = 170
	rain.lifetime = 0.85
	rain.preprocess = 1.0
	rain.position = Vector2(760, -40)
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(820, 10)
	rain.direction = Vector2(-0.22, 1)
	rain.spread = 1.5
	rain.gravity = Vector2.ZERO
	rain.initial_velocity_min = 950
	rain.initial_velocity_max = 1200
	rain.particle_flag_align_y = true
	rain.color = Color(0.73, 0.68, 0.94, 0.3)
	add_child(rain)

func new_game(seed_value: int) -> void:
	var sd = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) % 900000 + 100000
	S = M.new_run(sd)
	sel_node = -1; target = null; trunk_open = false; sel = null; rot = null
	floats = []; lock_until = 0.0; disp = {}; acc = 0.0; car_lane = 1.0

func _load_prefs() -> void:
	var cf = ConfigFile.new()
	if cf.load("user://neon-drift.cfg") == OK:
		seen = cf.get_value("hints", "seen", {})
		hints_off = cf.get_value("hints", "off", false)
		audio.muted = cf.get_value("audio", "muted", false)

func _save_prefs() -> void:
	var cf = ConfigFile.new()
	cf.set_value("hints", "seen", seen)
	cf.set_value("hints", "off", hints_off)
	cf.set_value("audio", "muted", audio.muted)
	cf.save("user://neon-drift.cfg")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit(0)

func _quit(code: int) -> void:
	audio.stop_all()
	set_process(false)
	for i in 4: await get_tree().process_frame
	get_tree().quit(code)

# ---------- кадр ----------

func _process(delta: float) -> void:
	dt = minf(delta, 0.1)
	t += dt
	var speed = SPEED.get(S.screen, 0.0)
	if S.screen == "drive": speed = 0.0 if (coach_on or not auto) else COL_W * 1000.0 / D.MODES[S.drive.mode].tick
	scroll += speed * dt
	cam = lerpf(cam, CAM.get(S.screen, 0.0), minf(1.0, dt * 7.0))
	if absf(cam - CAM.get(S.screen, 0.0)) < 0.5: cam = CAM.get(S.screen, 0.0)
	var quiet = S.screen == "drive" or S.screen == "battle"
	dim = lerpf(dim, 1.0 if quiet else 0.0, minf(1.0, dt * 5.0))
	var shake = (3.0 if fmod(t * 22.0, 2.0) < 1.0 else -3.0) if t < shake_until else 0.0
	var cy = roundf(cam)
	sky.position = Vector2(0, cy)
	for l in layers:
		var off = -fposmod(scroll * l.speed + shake, A.TILE)
		l.a.position = Vector2(roundf(off), cy)
		l.b.position = Vector2(roundf(off) + A.TILE, cy)
		if l.quiet:
			var m = Color(1, 1, 1).lerp(Color(0.42, 0.42, 0.56), dim)
			l.a.modulate = m
			l.b.modulate = m
	# плавное перестроение машины: на дороге — к выбранной полосе, иначе — к средней
	var want = float(S.drive.lane) if S.screen == "drive" else 1.0
	car_lane += (want - car_lane) * minf(1.0, dt * 14.0)
	if absf(want - car_lane) < 0.03: car_lane = want
	var la = mini(1, int(floor(car_lane)))
	car_px = roundf(A.LANES[la] + (A.LANES[la + 1] - A.LANES[la]) * (car_lane - la)) + cy
	# мотор слышен, пока машина едет; чем быстрее режим, тем выше тон
	var rolling = S.screen == "title" or S.screen == "battle" or (S.screen == "drive" and speed > 0.0)
	var pitch = clampf(442.0 / D.MODES[S.drive.mode].tick, 0.8, 1.4) if S.screen == "drive" else (1.1 if S.screen == "battle" else 1.0)
	audio.update(dt, S.screen, rolling, pitch)
	world.queue_redraw()
	hud.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: click = true
		elif event.button_index == MOUSE_BUTTON_RIGHT: cancel = true
	elif event is InputEventKey and event.pressed and not event.echo:
		keys.append(event.physical_keycode if event.physical_keycode != 0 else event.keycode)

# ---------- мир: машины и то, что на дороге ----------

func _paint_world(ci: CanvasItem) -> void:
	var mid = A.LANES[1] + roundf(cam)
	match S.screen:
		"title": A.car(ci, 300, mid, t, true)
		"map": A.car(ci, 56, mid, t, false)
		"drive": _world_drive(ci)
		"battle": _world_battle(ci)
		"end":
			if S.over != null and S.over.win: A.car(ci, 520, mid, t, true)
		_: A.car(ci, 120, mid, t, false)

func _world_drive(ci: CanvasItem) -> void:
	var d = S.drive
	if d == null: return
	var frac = clampf(acc / (D.MODES[d.mode].tick / 1000.0), 0.0, 1.0)
	var row = int(roundf(car_lane))
	var moving = auto and not coach_on
	for lane in 3:
		for o in d.objs:
			if o.lane != lane: continue
			var x = CAR_X + 96 + (o.x - d.pos - frac) * COL_W
			if x < -60 or x > W + 60: continue
			A.road_object(ci, o.k, x, A.LANES[lane] + roundf(cam), t)
		if lane == row: A.car(ci, CAR_X, car_px, t, moving)

func _world_battle(ci: CanvasItem) -> void:
	var b = S.battle
	if b == null: return
	A.car(ci, CAR_X, car_px, t, true)
	if b.shield > 0:
		A.glow(ci, CAR_X + 96, car_px - 34, 150, 70, A.CYAN, 0.35 + 0.1 * sin(t * 8.0))
		ci.draw_arc(Vector2(CAR_X + 96, car_px - 30), 112, -PI * 0.92, -PI * 0.08, 32, A.CYAN_L, 3.0, true)
	for i in b.enemies.size():
		var e = b.enemies[i]
		if e.hp <= 0 or not disp.has(i): continue
		var p = disp[i]
		A.enemy(ci, font, e.type, p.dx, p.dy, t + i * 0.37, e.hp)

# ---------- примитивы интерфейса ----------

func rc(x: float, y: float, w: float, h: float, col: Color) -> void:
	g.draw_rect(Rect2(x, y, w, h), col)

func tw(text: String, size: int = 17) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

# Текст: y — верх заглавных букв.
func tx(text: String, x: float, y: float, col: Color, size: int = 17) -> void:
	g.draw_string(font, Vector2(x, y + roundf(size * 0.76)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func txc(text: String, cx: float, y: float, col: Color, size: int = 17) -> void:
	tx(text, roundf(cx - tw(text, size) / 2.0), y, col, size)

func txr(text: String, rx: float, y: float, col: Color, size: int = 17) -> void:
	tx(text, rx - tw(text, size), y, col, size)

# Подпись на тёмной подложке: читается поверх любого фона.
func label(text: String, cx: float, y: float, col: Color, size: int = 15) -> void:
	var w = tw(text, size)
	A.rr(g, roundf(cx - w / 2.0) - 7, y - 5, w + 14, size + 9, Color(A.INK, 0.86), 5)
	txc(text, cx, y, col, size)

func wrap_text(text: String, width: float, size: int = 17) -> Array:
	var out = []
	var line = ""
	for word in text.split(" "):
		var cand = word if line == "" else line + " " + word
		if line != "" and tw(cand, size) > width:
			out.append(line)
			line = word
		else:
			line = cand
	if line != "": out.append(line)
	return out

# Абзац с переносами; возвращает y после последней строки.
func para(text: String, x: float, y: float, width: float, col: Color, size: int = 17, lh: float = 24.0) -> float:
	for l in wrap_text(text, width, size):
		tx(l, x, y, col, size)
		y += lh
	return y

func panel(x: float, y: float, w: float, h: float, fill: Color, border: Color, rad: int = 8) -> void:
	A.rr(g, x, y, w, h, fill, rad, border, 2)

func hover(x: float, y: float, w: float, h: float) -> bool:
	return input_on and mx >= x and mx < x + w and my >= y and my < y + h

func key(k: int) -> bool:
	return keys_live and keys.has(k)

func key_ok() -> bool:
	return key(KEY_ENTER) or key(KEY_KP_ENTER) or key(KEY_SPACE)

# Кнопка. o: off, why (причина недоступности), tip, sub (подпись справа), left, accent, on, line2, line3, size.
func btn(x: float, y: float, w: float, h: float, text: String, o: Dictionary = {}) -> bool:
	var off = o.get("off", false)
	var over = hover(x, y, w, h)
	var hot = over and not off
	if over: tip = o.get("why", "") if off else o.get("tip", "")
	var accent = o.get("accent", false)
	var on = o.get("on", false)
	var border = A.VIOLET if off else (A.CYAN_L if hot else (Color.WHITE if on else (A.AMB if accent else A.VIOLET3)))
	var fill = Color(A.NIGHT, 0.85) if off else (A.CYAN_D if hot or on else (Color("4a2a10") if accent else Color(A.INDIGO, 0.95)))
	var col = A.VIOLET3 if off else (Color.WHITE if hot else (A.AMB_L if accent else A.WHITE))
	if hot: A.glow(g, x + w / 2.0, y + h / 2.0, w * 0.62, h * 1.1, A.CYAN, 0.22)
	panel(x, y, w, h, fill, border, 6)
	var size: int = o.get("size", 17)
	var multi = o.has("line2")
	var ty = y + 8 if multi else y + roundf((h - size * 0.72) / 2.0) - 1
	if text != "":
		if o.get("left", false) or o.has("sub") or multi: tx(text, x + 12, ty, col, size)
		else: txc(text, x + w / 2.0, ty, col, size)
	if o.get("sub", "") != "": txr(o.sub, x + w - 12, ty + 1, A.VIOLET2 if off else o.get("sub_col", A.AMB), 15)
	if multi: tx(o.line2, x + 12, y + 33, A.VIOLET2 if off else o.get("line2_col", A.GREY), 15)
	if o.has("line3"): tx(o.line3, x + 12, y + 56, A.VIOLET2 if off else o.get("line3_col", A.GREY), 15)
	if hot and click:
		click = false
		audio.sfx("click")
		return true
	return false

func corners(x: float, y: float, w: float, h: float, col: Color) -> void:
	var n = 14.0
	for p in [[x, y, 1, 1], [x + w, y, -1, 1], [x, y + h, 1, -1], [x + w, y + h, -1, -1]]:
		g.draw_line(Vector2(p[0], p[1]), Vector2(p[0] + n * p[2], p[1]), col, 3.0)
		g.draw_line(Vector2(p[0], p[1]), Vector2(p[0], p[1] + n * p[3]), col, 3.0)

func big(text: String, y: float, col: Color, shadow: Color) -> void:
	var size = 104
	var x = roundf(W / 2.0 - tw(text, size) / 2.0)
	A.glow(g, W / 2.0, y + 44, tw(text, size) * 0.62, 90, shadow, 0.3)
	tx(text, x + 5, y + 5, shadow, size)
	tx(text, x, y, col, size)

# ---------- обучающие подсказки ----------

# Экран во время отрисовки заявляет подсказку; показывается первая ещё не просмотренная.
# Пока подсказка на экране, остальной ввод отключён, а дорога стоит на паузе.
func hint(id: String, text: String, tg: Array, bx: float, by: float) -> void:
	if hints_off or seen.has(id) or coach != null: return
	coach = {"id": id, "text": text, "t": tg, "bx": bx, "by": by}

func _draw_coach() -> void:
	coach_on = coach != null
	if coach == null: return
	input_on = true
	keys_live = true
	var q = coach.t
	var blink = A.AMB_L if fmod(t * 2.0, 1.0) < 0.5 else A.AMB
	corners(q[0] - 4, q[1] - 4, q[2] + 8, q[3] + 8, blink)
	var lines = wrap_text(coach.text, 430, 17)
	var bh = 50 + lines.size() * 24 + 50
	var x = clampf(coach.bx, 6, W - 478)
	var y = clampf(coach.by, 42, H - bh - 6)
	A.glow(g, x + 236, y + bh / 2.0, 300, bh * 0.8, A.AMB, 0.18)
	panel(x, y, 472, bh, Color(A.NIGHT, 0.97), A.AMB, 8)
	A.rr(g, x, y, 472, 28, A.AMB, 8)
	rc(x + 2, y + 18, 468, 10, A.AMB)
	tx("ПОДСКАЗКА", x + 14, y + 7, A.INK, 16)
	for i in lines.size(): tx(lines[i], x + 18, y + 42 + i * 24, Color.WHITE, 17)
	# после закрытия ввод возвращается сразу; остальные клавиши этого кадра достанутся игре
	if btn(x + 296, y + bh - 44, 160, 32, "ПОНЯТНО", {"accent": true}) or key_ok():
		seen[coach.id] = 1
		coach_on = false
		_save_prefs()
		keep = keys.filter(func(k): return k != KEY_ENTER and k != KEY_KP_ENTER and k != KEY_SPACE)
	if btn(x + 16, y + bh - 44, 190, 32, "БЕЗ ПОДСКАЗОК"):
		hints_off = true
		coach_on = false
		_save_prefs()

# ---------- действия ----------

func go(a: Dictionary) -> bool:
	var prev = S.screen
	if not M.act(S, a): return false
	target = null
	drop_ask = null
	if S.screen != prev:
		sel_node = -1; sel = null; rot = null; trunk_open = false
		if S.screen == "drive": acc = 0.0
		if S.screen == "battle":
			disp = {}
			lock_until = 0.0
			audio.sfx("alarm")
		if S.screen == "result": audio.sfx(("win" if S.over.win else "lose") if S.over != null else "ok", -7.0)
	if a.type == "steer": audio.sfx("steer", -14.0)
	elif a.type == "endTurn": audio.sfx("turn")
	return true

func _take_fx() -> void:
	if S.fx.is_empty(): return
	var t0 = maxf(t, lock_until)
	var hurt = false
	for e in S.fx:
		if e.k == "road":
			var ob = D.ROAD_OBJ[e.kind]
			var bad = ob.get("bad", false)
			var text = D.RES_NAME[ob.res].to_upper() + (" +" if ob.n > 0 else " −") + str(abs(ob.n))
			floats.append({"x": CAR_X + 96, "y": car_px - 96, "text": text, "col": A.MAG_L if bad else (A.CYAN_L if ob.res == "charge" else A.AMB_L), "t0": t, "hurt": false, "from": -1, "on": false})
			if bad: shake_until = t + 0.16
			audio.sfx("hit" if bad else "pick")
		elif S.screen == "battle" and e.k == "dmg":
			var p = disp.get(e.i)
			floats.append({"x": p.x + p.w / 2.0 if p != null else 800.0, "y": p.y - p.h - 70 if p != null else 300.0, "text": "−" + str(e.n), "col": Color.WHITE, "t0": t, "hurt": false, "from": -1, "on": false})
			audio.sfx("hit")
		elif S.screen == "battle" and e.k == "hurt":
			floats.append({"x": CAR_X + 96, "y": car_px - 96, "text": D.RES_NAME[e.res].to_upper() + " −" + str(e.n), "col": res_col[e.res], "t0": t0, "hurt": true, "from": e.i, "on": false})
			t0 += 0.45
			hurt = true
	if hurt: lock_until = t0
	S.fx.clear()

func _draw_floats() -> void:
	floats = floats.filter(func(f): return t - f.t0 < 0.95)
	for f in floats:
		var a = t - f.t0
		if a < 0: continue
		if not f.on:
			f.on = true
			if f.hurt:
				shake_until = t + 0.18
				audio.sfx("hurt", -6.0)
				flash = {"i": f.from, "until": t + 0.24}
		label(f.text, clampf(f.x, 80, W - 80), roundf(f.y - a * 44.0), f.col, 19)

# ---------- общие блоки ----------

func _hud_bar(x: float, name: String, v: int, vmax: int, col: Color) -> float:
	var warn = ((v <= 3 and name != "РОЗЫСК") or (name == "РОЗЫСК" and v >= 5)) and fmod(t * 2.0, 1.0) < 0.5
	tx(name, x, 11, A.RED if warn else A.GREY, 15)
	x += tw(name, 15) + 8
	for i in vmax:
		A.rr(g, x + i * 8, 10, 6, 15, col if i < v else Color(A.VIOLET, 0.9), 2)
	x += vmax * 8 + 4
	tx(str(v), x, 10, A.RED if warn else Color.WHITE, 17)
	return x + 38

func _draw_hud() -> void:
	rc(0, 0, W, 36, Color(A.INK, 0.94))
	rc(0, 35, W, 1, A.VIOLET)
	var r = S.res
	var m = S.max
	var x = 12.0
	x = _hud_bar(x, "ЗАРЯД", r.charge, m.charge, A.CYAN)
	x = _hud_bar(x, "КОРПУС", r.hull, m.hull, A.WHITE)
	x = _hud_bar(x, "ФОКУС", r.focus, m.focus, A.LAV)
	x = _hud_bar(x, "РОЗЫСК", r.wanted, m.wanted, A.MAG)
	tx("КРЕДИТЫ", x, 11, A.GREY, 15)
	tx(str(r.credits), x + tw("КРЕДИТЫ", 15) + 8, 10, A.RED if r.credits < 0 else A.AMB, 17)
	txr(M.clock_text(S.hour), W - 14, 10, A.AMB if S.hour >= M.DAWN else Color.WHITE, 17)

func _crew_card(x: float, y: float, i: int) -> void:
	if i >= S.crew.size():
		panel(x, y, 216, 100, Color(A.NIGHT, 0.8), A.VIOLET, 8)
		txc("СВОБОДНО", x + 108, y + 42, A.VIOLET3, 15)
		return
	var m = S.crew[i]
	var c = D.CREW[m.id]
	panel(x, y, 216, 100, Color(A.INK, 0.92), A.VIOLET3, 8)
	A.portrait(g, x + 8, y + 8, m.id, 2.0)
	tx(c.name, x + 82, y + 10, Color.WHITE, 17)
	tx(c.role, x + 82, y + 32, A.LAV, 15)
	tx("«" + c.skill + "»", x + 82, y + 54, A.CYAN, 15)
	tx("доверие", x + 8, y + 78, A.LAV, 14)
	for k in 3: A.rr(g, x + 82 + k * 16, y + 78, 12, 12, A.AMB if k < m.trust else Color("4a2a10"), 3)
	if hover(x, y, 216, 100): tip = c.name + ", " + c.role.to_lower() + ". «" + c.skill + "»: " + c.desc + " Минус: " + c.flaw

func _tip_bar(y: float) -> void:
	rc(0, y, W, H - y, Color(A.INK, 0.96))
	rc(0, y, W, 1, A.VIOLET)
	if tip != "": tx(wrap_text(tip, W - 24, 15)[0], 12, y + 7, A.WHITE, 15)

# ---------- экраны ----------

func _sc_title() -> void:
	big("NEON DRIFT", 44, A.CYAN_L, A.MAG)
	txc("ДЕМО НА GODOT · РАЙОН «ДОКИ»", W / 2.0, 164, A.PALE, 19)
	rc(0, 576, W, 144, Color(A.INK, 0.9))
	rc(0, 576, W, 1, A.VIOLET2)
	txc("Довези запечатанный кейс до КПП за одну ночь.", W / 2.0, 592, Color.WHITE, 20)
	txc("Машина — твой дом, дистанция — твоё оружие.", W / 2.0, 620, A.GREY, 17)
	if btn(440, 652, 400, 52, "НАЧАТЬ РЕЙС", {"accent": true, "size": 21}) or key_ok(): go({"type": "start"})
	tx("Сид заезда: " + str(S.seed), 16, 660, A.LAV, 15)
	if btn(16, 684, 150, 28, "Другой сид", {"size": 15}): new_game(-1)
	if btn(874, 684, 190, 28, "Звук: выкл" if audio.muted else "Звук: вкл", {"size": 15}):
		audio.muted = not audio.muted
		_save_prefs()
	if btn(1074, 684, 190, 28, "Подсказки: выкл" if hints_off else "Подсказки: вкл", {"size": 15}):
		hints_off = not hints_off
		if not hints_off: seen = {}   # включили заново — покажем всё с начала
		_save_prefs()

func _node_xy(n) -> Vector2:
	return Vector2(92 + n.col * 100, 152 + n.row * 112)

func _sc_map() -> void:
	rc(0, 36, W, 444, Color(A.INK, 0.74))
	_draw_hud()
	panel(12, 44, 832, 428, Color(A.INK, 0.9), A.VIOLET, 10)
	tx("РАЙОН «ДОКИ»", 28, 56, A.PALE, 16)
	var dawn = "РАССВЕТ: каждый переезд −2 Фокус" if S.hour >= M.DAWN else "до рассвета " + M.plural(M.DAWN - S.hour, "час", "часа", "часов")
	txr(dawn, 828, 56, A.AMB if S.hour >= M.DAWN else A.LAV, 15)
	var nodes = S.map.nodes
	var cur = nodes[S.at]
	for n in nodes:
		for id in n.next:
			g.draw_line(_node_xy(n), _node_xy(nodes[id]), A.CYAN_M if n.id == S.at else A.VIOLET, 2.0, true)
	for n in nodes:
		var p = _node_xy(n)
		var type = n.type if M.node_visible(S, n) else "hidden"
		var reach = cur.next.has(n.id)
		var is_cur = n.id == S.at
		var is_sel = sel_node == n.id
		var hot = hover(p.x - 28, p.y - 28, 56, 56)
		var fill = Color(A.NIGHT, 0.95)
		var border = A.VIOLET2
		var ic = node_col[type]
		if n.seen and not is_cur:
			fill = A.INDIGO; border = A.VIOLET; ic = A.VIOLET3
		if reach:
			fill = A.CYAN_D if (is_sel or hot) else Color("0f2a3a")
			border = Color.WHITE if is_sel else (A.CYAN_L if hot else A.CYAN)
			A.glow(g, p.x, p.y, 46, 46, A.CYAN, 0.3 if not is_sel else 0.5)
		if is_cur:
			fill = A.VIOLET2
			border = Color.WHITE if fmod(t * 2.0, 1.0) < 0.5 else A.PALE
			ic = Color.WHITE
		A.rr(g, p.x - 28, p.y - 28, 56, 56, fill, 8, border, 3 if (is_sel or is_cur) else 2)
		A.icon(g, type, p.x - 18, p.y - 16, ic, 4.0)
		if reach: label(D.NODE_INFO[type].name, p.x, p.y + 36, Color.WHITE if is_sel else A.CYAN_L)
		if is_cur: label("ты здесь", p.x, p.y + 36, A.PALE)
		if hot:
			tip = D.NODE_INFO[type].name + ". " + D.NODE_INFO[type].desc + ("" if reach else (" Ты здесь." if is_cur else " Отсюда не доехать."))
			if reach and click:
				sel_node = n.id
				click = false
	var lx = 26.0
	for k in ["road", "meet", "hitch", "park", "shop", "gate"]:
		A.icon(g, k, lx, 444, node_col[k], 2.0)
		tx(D.NODE_INFO[k].name, lx + 24, 446, A.LAV, 15)
		lx += 24 + tw(D.NODE_INFO[k].name, 15) + 22

	panel(852, 44, 416, 428, Color(A.INK, 0.9), A.VIOLET, 10)
	if sel_node >= 0:
		var n = nodes[sel_node]
		var info = D.NODE_INFO[n.type]
		A.icon(g, n.type, 868, 58, node_col[n.type], 2.0)
		tx(info.name.to_upper(), 896, 58, A.AMB, 18)
		para(info.desc, 868, 84, 384, Color.WHITE, 16, 22)
		tx("КАК ЕХАТЬ", 868, 138, A.PALE, 15)
		var i = 0
		for mode in D.MODES:
			var md = D.MODES[mode]
			var short = S.res.charge < md.charge
			var pr = M.ambush_chance(S, n, mode)
			var cost = "−" + str(md.charge) + " Заряд · +" + str(md.hours) + " ч" + (" · −1 Розыск" if md.wanted else "")
			var risk = "засада: будет бой" if pr >= 1.0 else ("засада: нет" if pr <= 0.0 else "засада: " + str(int(round(pr * 100))) + " %")
			if btn(868, 160 + i * 100, 384, 90, md.name.to_upper(), {
				"line2": "заряда не хватит: буксир за 40 кр" if short else cost, "line2_col": A.RED if short else A.GREY,
				"line3": risk, "line3_col": A.MAG_L if pr >= 1.0 else (A.GREEN if pr <= 0.0 else A.AMB), "tip": md.desc, "size": 18,
			}): go({"type": "travel", "to": n.id, "mode": mode})
			i += 1
	else:
		tx("МАРШРУТ", 868, 58, A.AMB, 18)
		var y = para("Нажми на подсвеченный узел, затем выбери режим езды.", 868, 90, 384, Color.WHITE, 17)
		y = para("Бои случаются в пути, а не в узлах. Череп — перегон с засадой наверняка, на остальных дорогах она возможна.", 868, y + 14, 384, A.PALE, 16, 22)
		para("Типы узлов видны только на шаг вперёд.", 868, y + 14, 384, A.LAV, 16, 22)

	for i in 3: _crew_card(300 + i * 224, 548, i)
	if btn(980, 548, 288, 48, "БАГАЖНИК", {"tip": "Переложить вещи, зарядить бардачок, применить предмет."}): _open_trunk()
	_tip_bar(690)

	hint("hud", "Это ресурсы рейса. Заряд, Корпус и Фокус тратятся, Розыск копится. Ноль в одном из них — дорогой штраф, ноль в двух сразу — конец рейса.", [6, 3, 930, 30], 300, 60)
	if sel_node < 0: hint("map", "Карта района. Цель — КПП на правом краю. Нажми на подсвеченный узел: он станет пунктом назначения.", [16, 48, 824, 380], 790, 220)
	else: hint("mode", "Режим езды решает, чем платить за переезд: Зарядом, временем или Розыском. Ниже написан шанс, что по дороге нагонит засада.", [856, 154, 408, 310], 360, 180)
	if S.crew.size() > 0: hint("crew", "В машине попутчик. В бою у него есть навык, в событиях он открывает новые варианты. Доверие растёт от разговоров на стоянке.", [296, 544, 672, 108], 300, 270)
	if S.stats.nodes >= 1: hint("trunkbtn", "В бою доступны только три слота бардачка. Загляни в багажник и переложи туда мелочь заранее.", [976, 544, 296, 56], 760, 300)

# ---------- дорога ----------

func _sc_drive() -> void:
	var d = S.drive
	var md = D.MODES[d.mode]
	var type = S.map.nodes[S.at].type
	var paused = coach_on or not auto
	_draw_hud()
	if input_on:
		if key(KEY_UP) or key(KEY_W): go({"type": "steer", "dir": -1})
		if key(KEY_DOWN) or key(KEY_S): go({"type": "steer", "dir": 1})
		if click and my >= 36 and my < PANEL_Y:
			# клик по полосе — машина едет на неё; клик выше дороги — на полосу вверх
			var want = 2
			if my < A.ROAD_TOP: want = maxi(0, d.lane - 1)
			elif my < A.LANES[0] + 12: want = 0
			elif my < A.LANES[1] + 12: want = 1
			while d.lane != want and go({"type": "steer", "dir": -1 if want < d.lane else 1}): pass
			click = false
	if not paused:
		acc += dt
		var tick = md.tick / 1000.0
		if acc >= tick:
			acc = 0.0 if acc >= 2.0 * tick else acc - tick
			go({"type": "tick"})
			if S.screen != "drive": return   # бой, итог или прибытие: новый экран нарисуется следующим кадром
			d = S.drive
	var frac = clampf(acc / (md.tick / 1000.0), 0.0, 1.0)
	# предупреждение над препятствием на своей полосе
	for o in d.objs:
		var ahead = o.x - d.pos
		if D.ROAD_OBJ[o.k].get("bad", false) and o.lane == d.lane and ahead > 0 and ahead <= 3 and fmod(t * 4.0, 1.0) < 0.6:
			label("!", CAR_X + 96 + (ahead - frac) * COL_W, A.LANES[o.lane] - 74, A.MAG_L, 20)

	var head = "ОПАСНЫЙ ПЕРЕГОН" if type == "road" else "В ПУТИ: " + D.NODE_INFO[type].name.to_upper()
	label(head, 22 + tw(head, 16) / 2.0, 50, A.MAG_L if type == "road" else Color.WHITE, 16)
	A.rr(g, 458, 48, 664, 16, Color(A.INK, 0.9), 8)
	A.rr(g, 460, 50, 660, 12, A.VIOLET, 6)
	A.rr(g, 460, 50, maxf(12.0, 660.0 * minf(1.0, (d.pos + frac) / d.len)), 12, A.CYAN, 6)
	A.rr(g, 1130, 40, 40, 32, Color(A.INK, 0.9), 6)
	A.icon(g, type, 1141, 48, node_col[type], 2.0)
	if d.ambushAt >= 0 and d.ambushAt - d.pos <= 2: label("ЗАСАДА!", W / 2.0, 86, A.MAG_L if fmod(t * 4.0, 1.0) < 0.5 else Color.WHITE, 22)

	for i in 3: _crew_card(8 + i * 224, 520, i)
	tx("РЕЖИМ: " + md.name.to_upper(), 12, 632, A.AMB, 17)
	var y = para(md.desc, 12, 656, 660, A.GREY, 15, 20)
	if d.dawn: tx("Рассвет: этот переезд стоил 2 Фокуса", 12, y + 2, A.AMB, 15)
	var i = 0
	for k in D.ROAD_OBJ:
		var ob = D.ROAD_OBJ[k]
		var ry = 560.0 + i * 46
		A.road_object(g, k, 720, ry, 0.0)
		tx(ob.name, 760, ry - 26, A.MAG_L if ob.get("bad", false) else (A.CYAN_L if k == "cell" else A.AMB_L), 17)
		tx(D.RES_NAME[ob.res] + (" +" if ob.n > 0 else " −") + str(abs(ob.n)) + (" кр" if ob.res == "credits" else ""), 870, ry - 26, Color.WHITE, 17)
		i += 1
	tx("ПЕРЕСТРОЕНИЕ", 1040, 522, A.PALE, 15)
	tx("стрелки вверх и вниз", 1040, 546, Color.WHITE, 16)
	tx("клавиши W и S", 1040, 568, Color.WHITE, 16)
	tx("или клик по полосе", 1040, 590, Color.WHITE, 16)
	para("Бой может начаться прямо в пути.", 1040, 626, 220, A.LAV, 15, 20)

	hint("drive", "Машина едет сама, ты выбираешь полосу: стрелки вверх и вниз, клавиши W и S или клик по полосе. Объезжай обломки и сканеры в розовом контуре, подбирай батареи и чипы.", [4, A.ROAD_TOP - 16, W - 8, 138], 400, 140)

# ---------- бой ----------

# Плашка намерения: [текст, цвет]. Плашки сплошные и яркие, чтобы не путались с вывесками на фоне.
func _intent_look(it) -> Array:
	match it.k:
		"stun": return ["СБОЙ", A.CYAN]
		"approach": return ["СБЛИЖАЕТСЯ", A.LAV]
		"aim": return ["ЦЕЛИТСЯ", A.AMB]
		"call": return ["ЗОВЁТ ПОДМОГУ", A.AMB]
	return [D.RES_NAME[it.res].to_upper() + " −" + str(it.n), A.MAG]

func _layout_enemies(lane: float) -> void:
	var b = S.battle
	for dd in 3:
		var in_band = []
		for i in b.enemies.size():
			if b.enemies[i].hp > 0 and b.enemies[i].dist == dd: in_band.append(i)
		var ground_w = 0.0
		for i in in_band:
			if not D.ENEMIES[b.enemies[i].type].get("air", false): ground_w += A.SPR_SIZE[b.enemies[i].type][0] + 16
		var squeeze = (BAND_W - 12) / ground_w if ground_w > BAND_W - 12 else 1.0
		var gx = BAND_X[dd] + 12
		var ak = 0
		for i in in_band:
			var e = b.enemies[i]
			var sz = A.SPR_SIZE[e.type]
			var px = 0.0
			var py = lane
			if D.ENEMIES[e.type].get("air", false):
				px = BAND_X[dd] + 40 + (ak % 3) * 96
				py = lane - 170 - (ak % 2) * 84
				ak += 1
			else:
				px = roundf(gx)
				gx += (sz[0] + 16) * squeeze
			if not disp.has(i): disp[i] = {"x": W + 60, "y": py, "w": sz[0], "h": sz[1], "dx": W + 60, "dy": py, "tx": px, "ty": py}
			var p = disp[i]
			p.tx = px; p.ty = py; p.w = sz[0]; p.h = sz[1]

func _press(a: Dictionary) -> void:
	if M.needs_target(S, a):
		var ts = M.battle_targets(S, a)
		if ts.size() == 1:
			var a2 = a.duplicate()
			a2["target"] = ts[0]
			go(a2)
		else:
			target = a
	else:
		go(a)

func _sc_battle() -> void:
	var b = S.battle
	var r = S.res
	_draw_hud()
	var lane = A.LANES[1] + roundf(cam)
	for dd in 3:
		var yy = 100.0
		while yy < A.ROAD_TOP - 20:
			rc(BAND_X[dd] - 6, yy, 2, 5, Color(A.LAV, 0.55))
			yy += 10
		label(BAND_NAME[dd], BAND_X[dd] + BAND_W / 2.0, 48, Color.WHITE, 17)
		label(BAND_REACH[dd], BAND_X[dd] + BAND_W / 2.0, 76, A.PALE, 14)

	_layout_enemies(lane)
	var valid = M.battle_targets(S, target) if target != null else []
	var seer = M.crew_has(S, "android")
	for i in b.enemies.size():
		var e = b.enemies[i]
		if e.hp <= 0: continue
		var p = disp[i]
		var en = D.ENEMIES[e.type]
		var k = minf(1.0, dt * 9.0)
		p.x += (p.tx - p.x) * k
		p.y += (p.ty - p.y) * k
		if absf(p.tx - p.x) < 0.6: p.x = p.tx
		var x = roundf(p.x)
		var y = roundf(p.y)
		if en.get("air", false): y += roundf(sin(t * 3.0 + i * 2.0) * 4.0)
		if flash != null and flash.i == i and t < flash.until: x -= 12
		p.dx = x
		p.dy = y
		var top = y - p.h
		var bw = maxf(68.0, p.w)
		var mid = x + p.w / 2.0
		label(en.name, mid, y + 10, A.MAG_L, 15)
		A.rr(g, x - 2, top - 20, bw + 4, 14, A.INK, 4)
		A.rr(g, x, top - 18, maxf(4.0, bw * e.hp / e.max), 10, A.RED, 3)
		label(str(e.hp), x + bw + 20, top - 21, Color.WHITE, 15)
		var look = _intent_look(M.intent_of(S, e))
		var twd = tw(look[0], 16) + 20
		var ix = clampf(mid - twd / 2.0, 4, W - twd - 4)
		A.glow(g, ix + twd / 2.0, top - 40, twd * 0.7, 26, look[1], 0.35)
		A.rr(g, ix - 2, top - 54, twd + 4, 30, A.INK, 6)
		A.rr(g, ix, top - 52, twd, 26, look[1], 5)
		tx(look[0], ix + 10, top - 46, A.INK, 16)
		g.draw_colored_polygon(PackedVector2Array([Vector2(mid - 6, top - 27), Vector2(mid + 6, top - 27), Vector2(mid, top - 21)]), look[1])
		if seer: label("далее: " + _intent_look(M.next_intent(S, e))[0], ix + twd / 2.0, top - 78, A.PALE, 14)
		if b.mark == i:
			g.draw_arc(Vector2(mid, top + p.h / 2.0), 22, 0, TAU, 24, A.AMB_L, 2.0, true)
			g.draw_line(Vector2(mid - 30, top + p.h / 2.0), Vector2(mid + 30, top + p.h / 2.0), A.AMB_L, 2.0)
			g.draw_line(Vector2(mid, top + p.h / 2.0 - 30), Vector2(mid, top + p.h / 2.0 + 30), A.AMB_L, 2.0)
		var over = hover(minf(x, ix) - 6, top - 56, maxf(bw, twd) + 12, p.h + 86)
		if target != null and valid.has(i):
			corners(x - 8, top - 8, p.w + 16, p.h + 16, Color.WHITE if over else (A.CYAN_L if fmod(t * 4.0, 1.0) < 0.5 else A.CYAN))
			if over and click:
				click = false
				var a2 = target.duplicate()
				a2["target"] = i
				go(a2)
		if over and S.battle != null: tip = en.name + " · " + str(e.hp) + "/" + str(e.max) + " · " + en.desc
	if S.screen != "battle": return   # бой закончился этим кликом
	if target != null and (cancel or (click and my < PANEL_Y)):
		target = null
		click = false

	A.rr(g, 6, 44, 230, 26, Color(A.INK, 0.86), 5)
	tx("ХОД " + str(b.turn), 16, 50, Color.WHITE, 16)
	A.rr(g, 6, 74, 230, 30, Color(A.INK, 0.86), 5)
	tx("ОД", 16, 82, A.AMB_L, 16)
	for i in maxi(3, b.ap): A.rr(g, 52 + i * 24, 80, 18, 18, A.AMB if i < b.ap else Color("4a2a10"), 4)
	var sy = 110.0
	if b.shield > 0:
		A.rr(g, 6, sy - 4, 230, 26, Color(A.INK, 0.86), 5)
		tx("ЩИТ " + str(b.shield), 16, sy + 2, A.CYAN_L, 16)
		sy += 30
	if b.escape > 0:
		A.rr(g, 6, sy - 4, 230, 26, Color(A.INK, 0.86), 5)
		tx("ОТРЫВ " + str(b.escape) + " %", 16, sy + 2, A.GREEN, 16)
		sy += 30
	if not b.boss:
		A.rr(g, 6, sy - 4, 230, 26, Color(A.INK, 0.86), 5)
		tx("патруль через " + M.plural(6 - b.heat, "ход", "хода", "ходов"), 16, sy + 3, A.PALE, 15)

	var busy = t < lock_until
	for i in 3:
		var x = 8.0 + i * 162
		var y = 534.0
		if i >= S.crew.size():
			panel(x, y, 156, 178, Color(A.NIGHT, 0.8), A.VIOLET, 8)
			txc("ПУСТО", x + 78, y + 82, A.VIOLET3, 15)
			continue
		var m = S.crew[i]
		var c = D.CREW[m.id]
		var a = {"type": "skill", "crew": i}
		var why = M.battle_why(S, a)
		var on = target != null and target.type == "skill" and target.get("crew") == i
		if btn(x, y, 156, 178, "", {"off": why != "", "why": c.name + ", «" + c.skill + "»: " + why, "on": on, "tip": c.name + ", «" + c.skill + "»: " + c.desc}): _press(a)
		A.portrait(g, x + 46, y + 8, m.id, 2.0)
		if why != "": rc(x + 46, y + 8, 64, 64, Color(A.INK, 0.6))
		txc(c.name, x + 78, y + 80, A.VIOLET3 if why != "" else Color.WHITE, 17)
		txc(c.skill.to_upper(), x + 78, y + 104, A.VIOLET3 if why != "" else A.CYAN, 16)
		var st = str(c.ap) + " ОД"
		if m.id == "musician": st = "сыграно" if m.used else "0 ОД"
		elif m.cd > 0: st = "откат: " + M.plural(m.cd, "ход", "хода", "ходов")
		txc(st, x + 78, y + 128, A.VIOLET3 if why != "" else A.AMB, 15)
		for k in 3: A.rr(g, x + 56 + k * 16, y + 156, 12, 12, A.AMB if k < m.trust else Color("4a2a10"), 3)

	tx("БАРДАЧОК", 504, 534, A.PALE, 15)
	for slot in 3:
		var x = 504.0 + slot * 70
		var id = S.glove[slot]
		var a = {"type": "item", "slot": slot}
		var why = M.battle_why(S, a) if id != null else "Пустой слот"
		if btn(x, 558, 64, 64, "", {"off": why != "", "why": (D.ITEMS[id].name + ": " + why) if id != null else why, "tip": (D.ITEMS[id].name + ". " + D.ITEMS[id].desc) if id != null else ""}): go(a)
		if id != null:
			A.item_icon(g, id, x + 8, 566, 4.0)
			if why != "": rc(x + 2, 560, 60, 60, Color(A.INK, 0.6))
	tx("0 ОД, один предмет", 504, 634, A.LAV, 14)
	tx("за ход", 504, 652, A.LAV, 14)

	var acts = [
		["gun", "СТВОЛЫ", "1 ОД", "Урон " + str(2 + S.up.guns) + " по цели вплотную или на средней дистанции."],
		["ram", "ТАРАН", "2 ОД", "Урон 5 по цели вплотную. Свой Корпус −1."],
		["hack", "ВЗЛОМ", "1 ОД, 1 Фокус", "Урон " + str(2 + S.up.deck) + " на любой дистанции, по технике вдвое. Первый взлом за бой: +1 розыск."],
		["escape", "ОТРЫВ", "все ОД", "Копит шкалу побега за 2 Заряда. На 100 % бой кончается без добычи."],
		["pull", "ПОДТЯНУТЬ", "1 ОД, 1 Заряд", "Манёвр: враг на шаг ближе, чтобы достать его оружием."],
		["push", "ОТТЕСНИТЬ", "1 ОД, 1 Заряд", "Манёвр: враг на шаг дальше. Если оттуда он не достаёт, удар сорван."],
	]
	for i in acts.size():
		var q = acts[i]
		var a = {"type": q[0]}
		var why = M.battle_why(S, a)
		var on = target != null and target.type == q[0]
		if btn(720 + (i % 2) * 280, 534 + (i >> 1) * 46, 272, 40, q[1], {"sub": q[2], "off": why != "", "why": q[1] + ": " + why, "tip": q[3], "on": on}): _press(a)
	if btn(720, 672, 552, 40, "КОНЕЦ ХОДА", {"accent": b.ap == 0, "tip": "Враги выполняют намерения, которые показаны над ними.", "size": 18}) or (not busy and target == null and key_ok()):
		go({"type": "endTurn"})

	# строка подсказки: цель, подсказка под курсором или последняя запись журнала
	var log_line = S.battle.log.back() if S.battle != null and not S.battle.log.is_empty() else ""
	var line = "Выбери цель. Клик мимо или Esc — отмена." if target != null else (tip if tip != "" else (log_line if log_line != "" else "Плашка над врагом показывает, что он сделает в конце хода."))
	tx(wrap_text(line, W - 24, 15)[0], 12, 513, A.CYAN_L if target != null else (Color.WHITE if tip != "" else A.GREY), 15)

	if S.screen != "battle" or busy: return
	hint("battle", "Засада: бой идёт прямо на ходу. Над каждым врагом плашка — что он сделает, когда ты нажмёшь «Конец хода». У тебя 3 ОД на ход.", [300, 120, 972, 380], 8, 130)
	hint("dist", "Враги стоят на трёх дистанциях. Под названием дистанции написано, чем туда можно достать: чем ближе враг, тем больше вариантов.", [296, 40, 980, 56], 400, 140)
	hint("acts", "Действия машины. «Подтянуть» и «Оттеснить» двигают врага между дистанциями за 1 Заряд. Наведи на кнопку — над панелью появится описание.", [716, 530, 560, 186], 230, 250)
	var dodge = false
	for i in b.enemies.size():
		var e = b.enemies[i]
		if e.hp > 0 and M.intent_of(S, e).k == "hit" and e.dist == D.ENEMIES[e.type].reach and M.battle_why(S, {"type": "push", "target": i}) == "": dodge = true
	if dodge and b.turn >= 2: hint("push", "Враг готовит удар. Оттесни его туда, откуда он не достаёт: удар сорвётся, а он потратит ход на сближение.", [996, 622, 280, 48], 500, 300)
	if S.crew.size() > 0: hint("skill", "Навык попутчика — кнопка с его портретом. После применения навык уходит на откат на несколько ходов.", [4, 530, 492, 186], 120, 270)
	var usable = false
	for slot in 3:
		if S.glove[slot] != null and M.battle_why(S, {"type": "item", "slot": slot}) == "": usable = true
	if usable: hint("glove", "Предмет из бардачка не тратит ОД, но применить можно только один за ход. Сюда попадает то, что ты заранее положил через «Багажник».", [500, 530, 212, 96], 380, 270)

# ---------- текстовые экраны ----------

func _text_panel(title: String) -> void:
	_draw_hud()
	panel(12, 318, 1256, 394, Color(A.INK, 0.95), A.VIOLET2, 10)
	tx(title.to_upper(), 36, 336, A.AMB, 30)

func _sc_event() -> void:
	var v = M.event_view(S)
	var hitch = S.event.id == "hitch"
	_text_panel(v.title)
	if hitch:
		panel(1160, 330, 84, 84, A.INK, A.AMB, 6)
		A.portrait(g, 1170, 340, S.event.who, 2.0)
	var y = para(v.text, 36, 388, 1100.0 if hitch else 1200.0, Color.WHITE, 18, 26)
	y = maxf(y + 18, 500.0)
	for i in v.options.size():
		var o = v.options[i]
		if btn(36, y, 1208, 46, str(i + 1) + ". " + o.label, {"off": not o.ok, "sub": "" if o.ok else o.why, "sub_col": A.RED, "left": true, "why": o.why, "size": 18}) or (o.ok and key(KEY_1 + i)):
			go({"type": "choose", "i": i})
			return
		y += 56
	if hitch: hint("hitch", "Попутчик даёт навык в бою и новые варианты в событиях, но у каждого есть минус. Мест в салоне три.", [32, 496, 1216, 108], 760, 60)
	else: hint("event", "Событие в пути: у каждого варианта своя цена. Серые варианты откроются, если в машине нужный попутчик или хватает кредитов.", [32, 496, 1216, 164], 760, 60)

func _sc_result() -> void:
	var r = S.result
	_text_panel(r.title)
	var y = 392.0
	for line in r.lines: y = para(line, 36, y, 1200, Color.WHITE, 18, 26) + 6
	y += 10
	var x = 36.0
	for d in r.deltas:
		var hour = d.k == "hour"
		var text = ("ВРЕМЯ" if hour else D.RES_NAME[d.k].to_upper()) + (" +" if d.n > 0 else " −") + str(abs(d.n)) + (" ч" if hour else "")
		var good = d.n < 0 if d.k == "wanted" else d.n > 0
		var col = A.GREY if hour else (A.GREEN if good else A.RED)
		var w = tw(text, 16) + 24
		if x + w > 1240:
			x = 36.0
			y += 38
		panel(x, y, w, 30, A.INK, col, 6)
		tx(text, x + 12, y + 8, col, 16)
		x += w + 10
	if btn(440, 652, 400, 48, "ЕХАТЬ ДАЛЬШЕ" if r.then == "drive" else "ДАЛЬШЕ", {"accent": true, "size": 19}) or key_ok(): go({"type": "continue"})

func _sc_park() -> void:
	_text_panel("Стоянка")
	var r = S.res
	var p = S.park
	var fee = 10 if M.crew_has(S, "mechanic") else 0
	tx("Тихий двор под эстакадой. Колонка, кофейный автомат и никого вокруг.", 36, 388, Color.WHITE, 18)
	if btn(36, 428, 596, 46, "ОТДОХНУТЬ", {"sub": "+5 Фокус, +3 ч" + (", −10 кр" if fee else ""), "off": p.rested or r.credits < fee,
		"why": "Сегодня уже отдыхали" if p.rested else "Не хватает кредитов", "tip": "Сон в машине. Время идёт, рассвет ближе."}): go({"type": "rest"})
	if btn(36, 482, 596, 46, "ЗАРЯДКА", {"sub": "+4 Заряд за 15 кр", "off": r.credits < 15 or r.charge >= S.max.charge,
		"why": "Батарея полная" if r.charge >= S.max.charge else "Не хватает кредитов", "tip": "Можно повторять, пока есть кредиты."}): go({"type": "charge"})
	if btn(36, 536, 596, 46, "РЕМОНТ", {"sub": "+4 Корпус за 20 кр", "off": r.credits < 20 or r.hull >= S.max.hull,
		"why": "Корпус цел" if r.hull >= S.max.hull else "Не хватает кредитов", "tip": "Можно повторять, пока есть кредиты."}): go({"type": "repair"})
	if S.crew.is_empty(): tx("В салоне пусто. Попутчики дают навыки в бою.", 652, 442, A.LAV, 16)
	for i in S.crew.size():
		var m = S.crew[i]
		var c = D.CREW[m.id]
		var full = m.trust >= 3
		if btn(648, 428 + i * 54, 596, 46, "ПОГОВОРИТЬ: " + c.name.to_upper(), {"sub": "доверие +1", "off": p.talked.has(m.id) or full,
			"why": "Доверие уже полное" if full else "Уже поговорили", "tip": "При полном доверии откат навыка короче на ход."}): go({"type": "talk", "crew": i})
	if tip != "": tx(wrap_text(tip, 1200, 16)[0], 36, 606, A.PALE, 16)
	if btn(36, 652, 380, 48, "БАГАЖНИК"): _open_trunk()
	if btn(864, 652, 380, 48, "ЕХАТЬ ДАЛЬШЕ", {"accent": true, "size": 19}): go({"type": "leave"})
	hint("park", "Стоянка — единственное место, где ресурсы восстанавливаются. Отдых возвращает Фокус, но съедает 3 часа: после рассвета каждый переезд стоит Фокуса.", [32, 424, 604, 162], 760, 60)

func _sc_shop() -> void:
	_text_panel("Мастерская")
	var r = S.res
	tx("ПРИПАСЫ", 36, 380, A.PALE, 15)
	for i in D.SHOP_ITEMS.size():
		var id = D.SHOP_ITEMS[i]
		var d = D.ITEMS[id]
		var room = M.find_spot(S, id) != null or (d.get("small", false) and S.glove.has(null))
		if btn(36, 402 + i * 40, 396, 36, d.name, {"sub": str(d.price) + " кр", "off": r.credits < d.price or not room,
			"why": "Не хватает кредитов" if room else "Нет места в багажнике", "tip": d.name + ". " + d.desc}): go({"type": "buy", "item": id})
	tx("АПГРЕЙДЫ", 448, 380, A.PALE, 15)
	var ui = 0
	for id in D.UPGRADES:
		var u = D.UPGRADES[id]
		var have = S.up[id] > 0
		if btn(448, 402 + ui * 40, 396, 36, u.name, {"sub": "стоит" if have else str(u.price) + " кр", "off": have or r.credits < u.price,
			"why": ("Уже установлено. " if have else "Не хватает кредитов. ") + u.desc, "tip": u.name + ". " + u.desc}): go({"type": "upgrade", "id": id})
		ui += 1
	tx("СКУПКА", 448, 574, A.PALE, 15)
	var loot = S.trunk.filter(func(q): return D.ITEMS[q.id].has("sell")).slice(0, 3)
	if loot.is_empty(): tx("Продать нечего.", 448, 600, A.VIOLET3, 16)
	for i in loot.size():
		var d = D.ITEMS[loot[i].id]
		if btn(448, 594 + i * 38, 396, 34, d.name, {"sub": "+" + str(d.sell) + " кр", "tip": "Продать: " + d.name}):
			go({"type": "sell", "uid": loot[i].uid})
			break
	tx("ОПИСАНИЕ", 860, 380, A.PALE, 15)
	para(tip if tip != "" else "Наведи на товар, чтобы прочитать описание. В бардачок помещается только мелочь.", 860, 404, 384, Color.WHITE, 17, 24)
	if btn(860, 596, 384, 44, "БАГАЖНИК"): _open_trunk()
	if btn(860, 652, 384, 48, "ЕХАТЬ ДАЛЬШЕ", {"accent": true, "size": 19}): go({"type": "leave"})
	hint("shop", "Мастерская: припасы, апгрейды навсегда и скупка лута. Наведи на строку — справа появится описание. Купленная мелочь ложится в багажник.", [32, 374, 816, 330], 760, 60)

func _sc_end() -> void:
	var o = S.over
	var st = S.stats
	big("ДЕМО ПРОЙДЕНО" if o.win else "РЕЙС ОКОНЧЕН", 44, A.CYAN_L if o.win else A.MAG_L, A.CYAN_D if o.win else Color("7a1f24"))
	panel(120, 180, 1040, 176, Color(A.INK, 0.93), A.CYAN if o.win else A.MAG, 10)
	var y = para(o.text, 144, 198, 990, Color.WHITE, 19, 28) + 10
	tx("Узлов пройдено: %d · Боёв: %d (побед %d, отрывов %d)" % [st.nodes, st.battles, st.wins, st.escapes], 144, y, A.PALE, 16)
	tx("На дороге: задето %d, подобрано %d · Критических событий: %d" % [st.hits, st.picks, st.crits], 144, y + 26, A.PALE, 16)
	tx("Финиш в %s · Кредиты: %d · Розыск: %d · Сид заезда: %d" % [M.clock_text(S.hour), S.res.credits, S.res.wanted, S.seed], 144, y + 52, A.LAV, 16)
	rc(0, 580, W, 140, Color(A.INK, 0.9))
	rc(0, 580, W, 1, A.VIOLET2)
	if btn(240, 624, 380, 52, "НОВЫЙ РЕЙС", {"accent": true, "size": 20}): new_game(-1)
	if btn(660, 624, 380, 52, "ТОТ ЖЕ СИД", {"size": 20}): new_game(S.seed)

# ---------- багажник ----------

func _open_trunk() -> void:
	trunk_open = true; sel = null; rot = null; drop_ask = null

func _close_trunk() -> void:
	trunk_open = false; sel = null; rot = null; drop_ask = null

func _trunk_item(uid):
	for q in S.trunk:
		if q.uid == uid: return q
	return null

func _draw_trunk() -> void:
	rc(0, 36, W, H - 36, Color(A.INK, 0.72))
	var px = 200.0
	var py = 100.0
	var gx = px + 32
	var gy = py + 72
	var cs = 56.0
	panel(px, py, 880, 524, Color(A.INK, 0.97), A.CYAN, 10)
	tx("БАГАЖНИК", px + 30, py + 22, A.AMB, 28)
	if btn(px + 736, py + 18, 120, 36, "ЗАКРЫТЬ") or key(KEY_ESCAPE):
		_close_trunk()
		return
	for yy in M.TRUNK_H:
		for xx in M.TRUNK_W: A.rr(g, gx + xx * cs, gy + yy * cs, cs - 3, cs - 3, A.NIGHT, 4)

	var sel_it = _trunk_item(sel.uid) if sel != null and sel.has("uid") else null
	for q in S.trunk:
		var d = D.ITEMS[q.id]
		var sz = M.item_size(q)
		var x = gx + q.x * cs
		var y = gy + q.y * cs
		var pw = sz[0] * cs - 3
		var ph = sz[1] * cs - 3
		var is_sel = sel_it != null and sel_it.uid == q.uid
		var base = A.MAG if d.get("lock", false) else (A.AMB if d.has("sell") else (A.CYAN if d.has("use") or d.has("battle") else A.GREY))
		A.rr(g, x, y, pw, ph, Color(base.r * 0.22, base.g * 0.22, base.b * 0.26), 6, (Color.WHITE if fmod(t * 4.0, 1.0) < 0.5 else A.CYAN_L) if is_sel else base, 3 if is_sel else 2)
		A.item_icon(g, q.id, x + (pw - 48) / 2.0, y + (ph - 48) / 2.0, 4.0)
		if hover(x, y, pw, ph):
			tip = d.name + ". " + d.desc
			if click and not is_sel:
				sel = {"uid": q.uid}
				rot = null; drop_ask = null; click = false
				sel_it = q

	# перенос выбранного предмета в клетку под курсором
	if sel_it != null and hover(gx, gy, M.TRUNK_W * cs, M.TRUNK_H * cs):
		var cx = int(floor((mx - gx) / cs))
		var cy = int(floor((my - gy) / cs))
		var r = sel_it.r if rot == null else rot
		var d = D.ITEMS[sel_it.id]
		var w = d.h if r else d.w
		var h = d.w if r else d.h
		if cx != sel_it.x or cy != sel_it.y or r != sel_it.r:
			var ok = M.fits(S, sel_it.id, cx, cy, r, sel_it.uid)
			corners(gx + cx * cs, gy + cy * cs, w * cs - 3, h * cs - 3, A.GREEN if ok else A.RED)
			if click:
				click = false
				if ok:
					go({"type": "place", "uid": sel_it.uid, "x": cx, "y": cy, "r": r})
					rot = null

	tx("БАРДАЧОК · доступен в бою", px + 400, py + 72, A.PALE, 15)
	for slot in 3:
		var x = px + 400 + slot * 72
		var y = py + 96
		var id = S.glove[slot]
		var is_sel = sel != null and sel.get("slot", -1) == slot
		panel(x, y, 64, 64, A.CYAN_D if is_sel else A.NIGHT, Color.WHITE if is_sel else A.VIOLET3, 6)
		if id != null: A.item_icon(g, id, x + 8, y + 8, 4.0)
		if hover(x, y, 64, 64):
			tip = (D.ITEMS[id].name + ". " + D.ITEMS[id].desc) if id != null else "Пустой слот. Сюда помещается только мелочь 1×1."
			if click:
				click = false
				if id != null:
					sel = {"slot": slot}
					rot = null
				elif sel_it != null and go({"type": "stow", "uid": sel_it.uid, "slot": slot}):
					sel = {"slot": slot}
					sel_it = null

	var sel_id = null
	if sel_it != null: sel_id = sel_it.id
	elif sel != null and sel.has("slot"): sel_id = S.glove[sel.slot]
	if sel_id != null:
		var d = D.ITEMS[sel_id]
		tx(d.name.to_upper(), px + 400, py + 184, A.AMB, 18)
		tx(str(d.w) + "×" + str(d.h) + (" · влезает в бардачок" if d.get("small", false) else ""), px + 400, py + 210, A.LAV, 15)
		para(d.desc, px + 400, py + 238, 448, Color.WHITE, 17, 24)
	else:
		para("Выбери предмет, затем клетку, куда его переложить. Пустой слот бардачка принимает выбранную мелочь.", px + 400, py + 184, 448, A.PALE, 16, 22)
	if tip != "": para(tip, px + 32, py + 316, 816, A.PALE, 15, 20)

	var by = py + 464
	var d2 = D.ITEMS[sel_id] if sel_id != null else null
	if btn(px + 32, by, 196, 38, "ПОВЕРНУТЬ", {"off": sel_it == null or d2.w == d2.h, "why": "Нечего поворачивать"}):
		var nr = 0 if (sel_it.r if rot == null else rot) else 1
		if go({"type": "place", "uid": sel_it.uid, "x": sel_it.x, "y": sel_it.y, "r": nr}): rot = null
		else: rot = nr
	if btn(px + 240, by, 196, 38, "ПРИМЕНИТЬ", {"off": d2 == null or not d2.has("use"), "why": "Вне боя не применяется" if d2 != null else "Ничего не выбрано"}):
		if (go({"type": "use", "uid": sel_it.uid}) if sel_it != null else go({"type": "useGlove", "slot": sel.slot})): sel = null
	var from_glove = sel != null and sel.has("slot") and sel_id != null
	var no_room = from_glove and M.find_spot(S, sel_id) == null
	if btn(px + 448, by, 196, 38, "В БАГАЖНИК", {"off": not from_glove or no_room, "why": "В багажнике нет места" if no_room else "Выбери предмет в бардачке"}):
		if go({"type": "unstow", "slot": sel.slot}): sel = null
	var ask = sel_it != null and drop_ask == sel_it.uid
	if btn(px + 656, by, 196, 38, "ТОЧНО?" if ask else "ВЫБРОСИТЬ", {"off": sel_it == null or d2.get("lock", false), "why": "Это выбросить нельзя" if sel_it != null else "Выбери предмет в багажнике", "accent": ask}):
		if ask:
			go({"type": "drop", "uid": sel_it.uid})
			sel = null
		else:
			drop_ask = sel_it.uid
	if rot != null and sel_it != null: tx("Повёрнуто: укажи клетку, куда положить.", px + 32, by - 28, A.AMB, 15)
	hint("trunk", "Нажми на предмет, затем на клетку — он переедет. Мелочь 1×1 можно положить в слот бардачка: только оттуда она доступна в бою.", [gx - 4, gy - 4, M.TRUNK_W * cs + 4, M.TRUNK_H * cs + 4], px + 392, py + 300)

# ---------- сборка кадра интерфейса ----------

func _draw_screen(id: String) -> void:
	match id:
		"title": _sc_title()
		"map": _sc_map()
		"drive": _sc_drive()
		"battle": _sc_battle()
		"event": _sc_event()
		"result": _sc_result()
		"park": _sc_park()
		"shop": _sc_shop()
		"end": _sc_end()

func _paint_hud(ci: CanvasItem) -> void:
	g = ci
	var mp = hud.get_local_mouse_position()
	mx = mp.x
	my = mp.y
	tip = ""
	_take_fx()
	var free = not coach_on
	input_on = free and not trunk_open and t >= lock_until
	keys_live = free
	if key(KEY_ESCAPE): target = null
	coach = null
	# тёмная основа под панелями и виньетка по краям
	var base_y = A.ROAD_BOT + roundf(cam)
	if base_y < H: rc(0, base_y, W, H - base_y, A.INK)
	A.grad(g, 0, 0, W, 120, Color(0, 0, 0, 0.4), Color(0, 0, 0, 0))
	var shown = S.screen
	_draw_screen(shown)
	if S.screen != shown:
		# Экран сменился посреди отрисовки (клик закончил бой, отрезок привёл в узел).
		# Дорисовываем новый этим же кадром, уже без ввода: иначе на кадр пропала бы панель.
		input_on = false
		keys_live = false
		click = false
		_draw_screen(S.screen)
	if trunk_open:
		input_on = free
		tip = ""
		_draw_trunk()
	_draw_floats()
	_draw_coach()
	click = false
	cancel = false
	keys = keep if keep != null else []
	keep = null

# ---------- служебные режимы для проверки (аргументы после «--») ----------

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _shot(dir: String, name: String) -> void:
	await _frames(40)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))

func _crew(id: String) -> void:
	if not M.crew_has(S, id) and S.crew.size() < 3:
		S.crew.append({"id": id, "trust": 2, "cd": 0, "used": false})
		if id == "surgeon": M.add_item(S, "tools")

func _battle(types: Array, boss: bool) -> void:
	S.screen = "map"
	S.battle = null
	M.start_battle(S, types, boss)
	disp = {}

# Обход ключевых экранов со скриншотами: godot --path godot -- --tour=/папка
func _run_tour(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	auto = false
	hints_off = false
	seen = {}
	new_game(424242)
	await _shot(dir, "01-title")
	go({"type": "start"})
	await _shot(dir, "02-map-hint")
	hints_off = true
	sel_node = S.map.nodes[0].next[0]
	_crew("hacker"); _crew("guard")
	await _shot(dir, "03-map-modes")
	go({"type": "travel", "to": S.map.nodes[0].next[0], "mode": "fast"})
	var d = S.drive
	d.ambushAt = -1; d.pos = 5; d.lane = 1
	d.objs = [{"x": 6, "lane": 1, "k": "debris"}, {"x": 7, "lane": 0, "k": "cell"}, {"x": 8, "lane": 2, "k": "cam"}, {"x": 8, "lane": 1, "k": "debris"}, {"x": 10, "lane": 0, "k": "chip"}, {"x": 11, "lane": 2, "k": "debris"}, {"x": 12, "lane": 1, "k": "cell"}]
	acc = 0.1
	await _shot(dir, "04-drive")
	hints_off = false
	seen = {"hud": 1, "map": 1, "mode": 1, "crew": 1}
	await _shot(dir, "05-drive-hint")
	hints_off = true
	_battle(["biker", "patrol", "drone", "swarm"], false)
	await _shot(dir, "06-battle")
	target = {"type": "push"}
	await _shot(dir, "07-battle-target")
	target = null
	go({"type": "endTurn"})
	await _frames(20)
	await _shot(dir, "08-battle-enemy-phase")
	_crew("android")
	_battle(["boss", "drone"], true)
	await _shot(dir, "09-boss")
	_battle(["jammer", "biker"], false)
	await _shot(dir, "10-jammer")
	S.battle = null; S.drive = null
	S.event = {"id": "courier"}; S.screen = "event"
	await _shot(dir, "11-event")
	go({"type": "choose", "i": 0})
	await _shot(dir, "12-result")
	S.result = null
	S.event = {"id": "hitch", "who": "musician"}; S.screen = "event"
	await _shot(dir, "13-hitch")
	S.event = null
	S.park = {"rested": false, "talked": []}; S.screen = "park"
	await _shot(dir, "14-park")
	S.park = null; S.screen = "shop"
	await _shot(dir, "15-shop")
	S.screen = "map"
	M.add_item(S, "emp"); M.add_item(S, "scrap")
	trunk_open = true
	sel = {"uid": 2}
	await _shot(dir, "16-trunk")
	trunk_open = false
	S.over = {"win": true, "text": "Броневик дымит на обочине, шлагбаум поднят. Кейс едет дальше, в Развязку."}
	S.screen = "end"
	await _shot(dir, "17-end")
	print("tour: готово")
	_quit(0)

# Сохраняет весь синтезированный звук в WAV: godot --path godot -- --audio-dump=/папка
func _run_audio_dump(dir: String) -> void:
	var t0 = Time.get_ticks_msec()
	if not audio.has_music: await audio.music_ready
	audio.dump(dir)
	print("audio: музыка готова через ", Time.get_ticks_msec() - t0, " мс после запуска, файлы в ", dir)
	_quit(0)

# Прогон эталонных заездов через настоящий интерфейс: каждый шаг отрисовывается.
# godot --path godot -- --replay
func _run_replay() -> void:
	auto = false
	hints_off = true
	var runs = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays.json"))
	var shown = {}
	var hints_seen = {}
	var total = 0
	for ri in mini(8, runs.size()):
		var run = runs[ri]
		new_game(int(run.seed))
		# первые заезды идут с подсказками: каждая должна отрисоваться без ошибок
		hints_off = ri >= 4
		seen = {}
		for raw in run.actions:
			var a = {}
			for k in raw: a[k] = int(raw[k]) if typeof(raw[k]) == TYPE_FLOAT and raw[k] == floor(raw[k]) else raw[k]
			if S.screen == "map" and a.type == "travel" and not hints_off:
				sel_node = a.to   # как будто игрок выбрал узел: появляется подсказка про режимы
				await get_tree().process_frame
				if coach != null:
					hints_seen[coach.id] = 1
					seen[coach.id] = 1
			if not go(a):
				print("replay: действие отклонено ", a)
				_quit(1)
				return
			shown[S.screen] = shown.get(S.screen, 0) + 1
			total += 1
			if S.screen == "map" and total % 7 == 0: trunk_open = not trunk_open
			await get_tree().process_frame
			for guard in 8:   # закрываем подсказки, как это сделал бы игрок
				if coach == null: break
				hints_seen[coach.id] = 1
				seen[coach.id] = 1
				await get_tree().process_frame
		if S.screen != "end":
			print("replay: заезд не дошёл до финала, сид ", run.seed)
			_quit(1)
			return
	print("replay: готово, шагов ", total, ", экраны ", shown)
	print("replay: показано подсказок ", hints_seen.size(), ": ", ", ".join(hints_seen.keys()))
	_quit(0)
