# Графика демо: всё рисуется кодом — полигоны со сглаживанием, градиенты, мягкое свечение.
# Внешних картинок нет. Цвет несёт смысл: циан — своё, маджента — угроза, янтарь — ресурсы.
# Функции статические и принимают CanvasItem, на котором рисуют.

const INK = Color("0b0b14")
const NIGHT = Color("14132a")
const INDIGO = Color("1d1b3f")
const VIOLET = Color("2a2456")
const VIOLET2 = Color("3b2f73")
const VIOLET3 = Color("55449a")
const LAV = Color("7a68c4")
const PALE = Color("b9aef0")
const CYAN_D = Color("145066")
const CYAN_M = Color("1e8a9a")
const CYAN = Color("2fd6e0")
const CYAN_L = Color("a8f6ff")
const MAG_D = Color("8c1d6b")
const MAG = Color("e0399f")
const MAG_L = Color("ff8fd0")
const AMB_D = Color("a85a14")
const AMB = Color("f2a81d")
const AMB_L = Color("ffe08a")
const STEEL_D = Color("23262f")
const STEEL = Color("3a3f4d")
const STEEL_L = Color("5b6377")
const GREY = Color("8e97ad")
const WHITE = Color("d7dceb")
const GREEN = Color("58d37a")
const RED = Color("e0444a")

# Палитра прототипа — для портретов и значков, перенесённых из пиксельной версии.
const PAL = [
	Color("0b0b14"), Color("14132a"), Color("1d1b3f"), Color("2a2456"), Color("3b2f73"), Color("55449a"), Color("7a68c4"), Color("b9aef0"),
	Color("0f2a3a"), Color("145066"), Color("1e8a9a"), Color("2fd6e0"), Color("a8f6ff"),
	Color("4a0f3c"), Color("8c1d6b"), Color("e0399f"), Color("ff8fd0"),
	Color("4a2a10"), Color("a85a14"), Color("f2a81d"), Color("ffe08a"),
	Color("23262f"), Color("3a3f4d"), Color("5b6377"), Color("8e97ad"), Color("d7dceb"), Color("ffffff"),
	Color("2a6b3c"), Color("58d37a"), Color("7a1f24"), Color("e0444a"), Color("f5d0b5"),
]

const ROAD_TOP = 384
const ROAD_BOT = 508
const LANES = [428, 462, 496]
const TILE = 1280

# Размеры врагов для раскладки: [ширина, высота].
const SPR_SIZE = {"biker": [72, 58], "patrol": [140, 54], "drone": [52, 34], "jammer": [136, 72], "swarm": [60, 44], "boss": [196, 84]}

static var _glow: GradientTexture2D

# ---------- примитивы ----------

static func glow_tex() -> GradientTexture2D:
	if _glow == null:
		var gr = Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.4, Color(1, 1, 1, 0.32))
		_glow = GradientTexture2D.new()
		_glow.gradient = gr
		_glow.width = 128
		_glow.height = 128
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
	return _glow

# Мягкое пятно света: так делаются неон, фары и подсветка без шейдеров.
static func glow(ci: CanvasItem, x: float, y: float, rx: float, ry: float, col: Color, a: float) -> void:
	ci.draw_texture_rect(glow_tex(), Rect2(x - rx, y - ry, rx * 2, ry * 2), false, Color(col.r, col.g, col.b, a))

static func pts(a: Array, ox: float, oy: float) -> PackedVector2Array:
	var p = PackedVector2Array()
	for i in range(0, a.size(), 2):
		p.append(Vector2(ox + a[i], oy + a[i + 1]))
	return p

static func poly(ci: CanvasItem, a: Array, ox: float, oy: float, col: Color, rim = null, rw: float = 2.0) -> void:
	var p = pts(a, ox, oy)
	ci.draw_colored_polygon(p, col)
	if rim != null:
		p.append(p[0])
		ci.draw_polyline(p, rim, rw, true)

static func rr(ci: CanvasItem, x: float, y: float, w: float, h: float, fill: Color, rad: int = 6, border = null, bw: int = 2) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(rad)
	if border != null:
		sb.border_color = border
		sb.set_border_width_all(bw)
	ci.draw_style_box(sb, Rect2(x, y, w, h))

# Вертикальный градиент прямоугольником.
static func grad(ci: CanvasItem, x: float, y: float, w: float, h: float, top: Color, bot: Color) -> void:
	ci.draw_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]), PackedColorArray([top, top, bot, bot]))

static func wheel(ci: CanvasItem, cx: float, cy: float, r: float, ang: float) -> void:
	var c = Vector2(cx, cy)
	ci.draw_circle(c, r, Color("07070d"))
	ci.draw_circle(c, r * 0.58, STEEL_L)
	for k in 3:
		var a = ang + k * TAU / 3.0
		ci.draw_line(c - Vector2(cos(a), sin(a)) * r * 0.5, c + Vector2(cos(a), sin(a)) * r * 0.5, STEEL_D, 2.0, true)
	ci.draw_circle(c, r * 0.2, WHITE)
	ci.draw_arc(c, r, 0, TAU, 24, STEEL, 1.5, true)

# ---------- город: слои параллакса (каждый рисуется один раз и затем только сдвигается) ----------

static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.seed = seed_value
	return r

static func paint_sky(ci: CanvasItem) -> void:
	grad(ci, 0, -420, TILE, 500, Color("0e0d24"), Color("241f52"))
	grad(ci, 0, 80, TILE, 180, Color("241f52"), Color("4a2f7a"))
	grad(ci, 0, 260, TILE, ROAD_TOP - 260, Color("4a2f7a"), Color("8a2f78"))
	glow(ci, 640, ROAD_TOP, 900, 150, MAG, 0.45)
	glow(ci, 1010, 118, 150, 150, PALE, 0.22)
	ci.draw_circle(Vector2(1010, 118), 40, Color("d9d2ff"))
	ci.draw_circle(Vector2(996, 106), 9, Color("c4bbf2"))
	ci.draw_circle(Vector2(1026, 132), 6, Color("c4bbf2"))
	var r = _rng(5)
	for i in 110:
		var p = Vector2(r.randf_range(0, TILE), r.randf_range(-200, 200))
		ci.draw_circle(p, r.randf_range(0.6, 1.6), Color(1, 1, 1, r.randf_range(0.15, 0.7)))

static func paint_far(ci: CanvasItem) -> void:
	var r = _rng(11)
	var x = 6.0
	while x < TILE - 90:
		var w = r.randf_range(34, 84)
		var h = r.randf_range(130, 300)
		grad(ci, x, ROAD_TOP - h, w, h, Color("1f1c47"), Color("3b2a6a"))
		if r.randf() < 0.5: ci.draw_line(Vector2(x + w * 0.5, ROAD_TOP - h - r.randf_range(14, 40)), Vector2(x + w * 0.5, ROAD_TOP - h), Color("1f1c47"), 2.0)
		var wy = ROAD_TOP - h + 12
		while wy < ROAD_TOP - 14:
			var wx = x + 7
			while wx < x + w - 8:
				if r.randf() < 0.15: ci.draw_rect(Rect2(wx, wy, 3, 4), Color(0.72, 0.68, 0.94, r.randf_range(0.3, 0.8)))
				wx += 9
			wy += 11
		x += w + r.randf_range(4, 44)
	# Шпиль — цель всего рейса, виден из любого района.
	poly(ci, [0, 0, 14, -250, 20, -330, 26, -250, 40, 0], 880, ROAD_TOP, Color("1b1840"))
	poly(ci, [-22, 0, -8, -150, 48, -150, 62, 0], 880, ROAD_TOP, Color("1b1840"))
	for k in 12: ci.draw_line(Vector2(888, ROAD_TOP - 30 - k * 22), Vector2(912, ROAD_TOP - 30 - k * 22), Color(0.48, 0.41, 0.77, 0.5), 1.0)
	glow(ci, 900, ROAD_TOP - 330, 22, 22, RED, 0.9)
	ci.draw_circle(Vector2(900, ROAD_TOP - 330), 3, Color("ff8a8a"))
	# дымка у земли: дальний план уходит в туман
	grad(ci, 0, ROAD_TOP - 170, TILE, 170, Color(0.54, 0.18, 0.47, 0.0), Color(0.54, 0.18, 0.47, 0.45))

static func neon_sign(ci: CanvasItem, font: Font, x: float, y: float, word: String, col: Color, vertical: bool, size: int = 17) -> void:
	var w = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 18.0
	var h = 28.0
	if vertical:
		w = 26.0
		h = word.length() * 19.0 + 10.0
	glow(ci, x + w * 0.5, y + h * 0.5, w * 0.9 + 14, h * 0.9 + 14, col, 0.38)
	rr(ci, x, y, w, h, Color(col.r * 0.16, col.g * 0.16, col.b * 0.2, 0.96), 4, col, 2)
	var ink = col.lerp(Color.WHITE, 0.55)
	if vertical:
		for i in word.length():
			var ch = word[i]
			var cw = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			ci.draw_string(font, Vector2(x + (w - cw) * 0.5, y + 21 + i * 19), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
	else:
		ci.draw_string(font, Vector2(x + 9, y + 20), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)

static func paint_mid(ci: CanvasItem, font: Font) -> void:
	var r = _rng(22)
	var cols = [AMB_D, AMB_D, AMB_D, CYAN_M, MAG_D, AMB, CYAN]
	var x = 0.0
	while x < TILE - 150:
		var w = r.randf_range(70, 148)
		var h = r.randf_range(100, 220)
		var y = ROAD_TOP - h
		grad(ci, x, y, w, h, Color("17152f"), Color("1d1a3a"))
		ci.draw_line(Vector2(x, y), Vector2(x + w, y), Color("3b2f73"), 2.0)
		if r.randf() < 0.6:
			var tx = x + r.randf_range(8, w - 28)
			ci.draw_rect(Rect2(tx, y - 12, 18, 12), Color("17152f"))
			ci.draw_line(Vector2(tx + 9, y - 30), Vector2(tx + 9, y - 12), Color("17152f"), 2.0)
		var wy = y + 14
		while wy < ROAD_TOP - 18:
			var wx = x + 9
			while wx < x + w - 12:
				var a = r.randf()
				var c = cols[r.randi() % cols.size()]
				if a < 0.26: ci.draw_rect(Rect2(wx, wy, 6, 8), Color(c.r, c.g, c.b, 0.9))
				elif a < 0.42: ci.draw_rect(Rect2(wx, wy, 6, 8), Color("242050"))
				wx += 12
			wy += 14
		if r.randf() < 0.5 and w > 96:
			var words = ["ОТЕЛЬ", "ЧИПЫ", "ЗАЙМ", "КИБЕР", "ДОКИ"]
			neon_sign(ci, font, x + r.randf_range(8, w - 84), y + r.randf_range(20, 60), words[r.randi() % words.size()], [CYAN, MAG, AMB][r.randi() % 3], false, 15)
		x += w + r.randf_range(0, 20)

static func paint_near(ci: CanvasItem, font: Font) -> void:
	var r = _rng(33)
	var x = -12.0
	while x < TILE - 250:
		var w = r.randf_range(120, 240)
		var h = r.randf_range(64, 150)
		var y = ROAD_TOP - h
		var col = [CYAN, MAG, AMB][r.randi() % 3]
		ci.draw_rect(Rect2(x, y, w, h), Color("0c0c17"))
		ci.draw_line(Vector2(x, y), Vector2(x + w, y), Color("29264f"), 2.0)
		# витрина первого этажа со светом на тротуаре
		glow(ci, x + w * 0.5, ROAD_TOP - 14, w * 0.62, 46, col, 0.3)
		ci.draw_rect(Rect2(x + 8, ROAD_TOP - 44, w - 16, 34), Color(col.r * 0.2, col.g * 0.2, col.b * 0.24))
		ci.draw_line(Vector2(x + 8, ROAD_TOP - 45), Vector2(x + w - 8, ROAD_TOP - 45), col, 2.0)
		var wx = x + 16
		while wx < x + w - 28:
			ci.draw_rect(Rect2(wx, ROAD_TOP - 38, 20, 24), Color(col.r * 0.55, col.g * 0.55, col.b * 0.6))
			ci.draw_rect(Rect2(wx + 9, ROAD_TOP - 38, 2, 24), Color(col.r * 0.2, col.g * 0.2, col.b * 0.24))
			wx += 28
		var wy = y + 14
		while wy < ROAD_TOP - 64:
			var wxx = x + 12
			while wxx < x + w - 16:
				if r.randf() < 0.2: ci.draw_rect(Rect2(wxx, wy, 8, 10), [Color("4a2a10"), Color("0f2a3a"), Color("4a0f3c"), Color("a85a14")][r.randi() % 4])
				wxx += 18
			wy += 18
		var words = ["ЛАПША", "БАР", "РЕМОНТ", "ТИР", "ЧАЙ", "ТАКСИ"]
		var word = words[r.randi() % words.size()]
		var sx = x + r.randf_range(12, w - 44)
		var sx2 = x + r.randf_range(12, maxf(14, w - 110))
		if h >= word.length() * 19 + 78: neon_sign(ci, font, sx, y + 12, word, col, true)
		else: neon_sign(ci, font, sx2, y - 32, word, col, false)
		x += w + r.randf_range(20, 90)

# Дорога: отбойник, три полосы, мокрый асфальт с отражениями вывесок.
static func paint_road(ci: CanvasItem) -> void:
	var r = _rng(44)
	ci.draw_rect(Rect2(0, ROAD_TOP - 14, TILE, 4), GREY)
	ci.draw_rect(Rect2(0, ROAD_TOP - 10, TILE, 3), STEEL)
	var px = 0
	while px < TILE:
		ci.draw_rect(Rect2(px, ROAD_TOP - 14, 3, 14), STEEL)
		px += 32
	grad(ci, 0, ROAD_TOP, TILE, ROAD_BOT - ROAD_TOP, Color("2b2f3d"), Color("15171f"))
	ci.draw_line(Vector2(0, ROAD_TOP + 1), Vector2(TILE, ROAD_TOP + 1), STEEL_L, 2.0)
	for i in 30:
		var x = r.randf_range(0, TILE - 40)
		var w = r.randf_range(8, 30)
		var c = [MAG, CYAN, AMB, LAV][r.randi() % 4]
		grad(ci, x, ROAD_TOP + 3, w, r.randf_range(30, 90), Color(c.r, c.g, c.b, 0.2), Color(c.r, c.g, c.b, 0.0))
	for i in 30:
		ci.draw_rect(Rect2(r.randf_range(0, TILE - 20), r.randf_range(ROAD_TOP + 8, ROAD_BOT - 8), r.randf_range(6, 20), 1), Color(1, 1, 1, 0.08))
	var dx = 0
	while dx < TILE:
		ci.draw_rect(Rect2(dx, LANES[0] + 8, 36, 3), Color(0.82, 0.86, 0.95, 0.75))
		ci.draw_rect(Rect2(dx + 40, LANES[1] + 8, 36, 3), Color(0.82, 0.86, 0.95, 0.75))
		dx += 80
	ci.draw_rect(Rect2(0, ROAD_BOT - 4, TILE, 4), INK)

# ---------- транспорт ----------

# Машина игрока: старый седан с батареей на багажнике. x — левый край, y — линия полосы.
static func car(ci: CanvasItem, x: float, y: float, t: float, moving: bool) -> void:
	var by = y - (1.0 if moving and fmod(t * 6.0, 2.0) < 1.0 else 0.0)
	var ang = t * 14.0 if moving else 0.0
	glow(ci, x + 96, y - 2, 118, 12, Color.BLACK, 0.55)
	glow(ci, x + 96, y - 4, 124, 18, CYAN, 0.42)
	# свет фар и задний фонарь
	ci.draw_polygon(pts([188, -34, 188, -24, 372, 2, 372, -62], x, by), PackedColorArray([Color(1, 0.88, 0.54, 0.34), Color(1, 0.88, 0.54, 0.34), Color(1, 0.88, 0.54, 0), Color(1, 0.88, 0.54, 0)]))
	glow(ci, x + 192, by - 29, 26, 22, AMB_L, 0.7)
	glow(ci, x + 2, by - 30, 18, 14, MAG, 0.7)
	var body = [4, -14, 2, -30, 8, -40, 46, -44, 60, -60, 66, -64, 116, -64, 122, -60, 140, -42, 178, -38, 188, -32, 190, -18, 186, -12, 6, -12]
	poly(ci, body, x, by, CYAN_M)
	poly(ci, [4, -14, 4, -22, 190, -22, 190, -18, 186, -12, 6, -12], x, by, CYAN_D)
	poly(ci, [52, -44, 63, -59, 88, -59, 88, -44], x, by, Color("0d1a2c"))
	poly(ci, [92, -44, 92, -59, 114, -59, 130, -44], x, by, Color("0d1a2c"))
	ci.draw_line(Vector2(x + 58, by - 55), Vector2(x + 70, by - 55), Color(0.66, 0.96, 1, 0.5), 2.0, true)
	ci.draw_line(Vector2(x + 96, by - 55), Vector2(x + 106, by - 55), Color(0.66, 0.96, 1, 0.5), 2.0, true)
	ci.draw_line(Vector2(x + 90, by - 42), Vector2(x + 90, by - 16), CYAN_D, 2.0)
	ci.draw_line(Vector2(x + 5, by - 27), Vector2(x + 189, by - 27), CYAN_L, 2.0)
	rr(ci, x + 10, by - 54, 32, 12, STEEL, 3, STEEL_L, 1)
	for k in 3: ci.draw_circle(Vector2(x + 17 + k * 9, by - 48), 2.0, CYAN_L if (k != 2 or fmod(t * 2.0, 1.0) < 0.5) else CYAN_D)
	ci.draw_line(Vector2(x + 60, by - 67), Vector2(x + 120, by - 67), GREY, 2.0)
	rr(ci, x + 68, by - 78, 22, 10, AMB_D, 2, AMB, 1)
	rr(ci, x + 94, by - 75, 16, 7, MAG_D, 2, MAG, 1)
	ci.draw_rect(Rect2(x + 186, by - 34, 4, 8), AMB_L)
	ci.draw_rect(Rect2(x + 2, by - 34, 3, 8), MAG_L)
	var rim = pts(body, x, by)
	rim.append(rim[0])
	ci.draw_polyline(rim, CYAN_L, 2.0, true)
	wheel(ci, x + 42, y - 13, 13, ang)
	wheel(ci, x + 150, y - 13, 13, ang)

# Враг: x — левый край, y — низ спрайта. Контур мадженты — «это угроза».
static func enemy(ci: CanvasItem, font: Font, type: String, x: float, y: float, t: float, hp: int) -> void:
	var ang = t * 14.0
	match type:
		"biker":
			glow(ci, x + 36, y - 2, 44, 8, Color.BLACK, 0.55)
			glow(ci, x + 36, y - 4, 48, 12, MAG, 0.4)
			glow(ci, x + 70, y - 26, 16, 12, AMB_L, 0.6)
			poly(ci, [8, -12, 22, -28, 44, -30, 62, -14, 48, -10, 16, -10], x, y, STEEL_L, MAG_L)
			poly(ci, [24, -30, 30, -52, 44, -50, 50, -34, 60, -32, 60, -27, 44, -28], x, y, MAG, MAG_L)
			ci.draw_line(Vector2(x + 56, y - 34), Vector2(x + 62, y - 12), GREY, 3.0, true)
			ci.draw_circle(Vector2(x + 40, y - 54), 8, STEEL_D)
			ci.draw_arc(Vector2(x + 40, y - 54), 8, 0, TAU, 16, MAG_L, 2.0, true)
			ci.draw_rect(Rect2(x + 41, y - 57, 7, 4), MAG_L)
			wheel(ci, x + 12, y - 11, 11, ang)
			wheel(ci, x + 60, y - 11, 11, ang)
		"patrol":
			var flash = fmod(t * 4.0, 2.0) < 1.0
			glow(ci, x + 70, y - 2, 86, 10, Color.BLACK, 0.55)
			glow(ci, x + 70, y - 4, 90, 14, MAG, 0.35)
			glow(ci, x + 60, y - 56, 26, 18, RED if flash else CYAN, 0.75)
			poly(ci, [4, -14, 4, -30, 30, -34, 42, -50, 94, -50, 108, -34, 130, -30, 136, -22, 136, -12, 4, -12], x, y, WHITE, MAG_L)
			ci.draw_rect(Rect2(x + 5, y - 26, 130, 5), VIOLET2)
			poly(ci, [36, -36, 45, -47, 66, -47, 66, -36], x, y, Color("0d1a2c"))
			poly(ci, [70, -36, 70, -47, 92, -47, 102, -36], x, y, Color("0d1a2c"))
			ci.draw_rect(Rect2(x + 52, y - 56, 12, 6), RED if flash else Color("7a1f24"))
			ci.draw_rect(Rect2(x + 64, y - 56, 12, 6), CYAN_D if flash else CYAN)
			ci.draw_rect(Rect2(x + 132, y - 30, 4, 7), AMB_L)
			wheel(ci, x + 30, y - 12, 12, ang)
			wheel(ci, x + 108, y - 12, 12, ang)
		"drone":
			glow(ci, x + 26, y - 14, 34, 22, MAG, 0.35)
			ci.draw_line(Vector2(x + 10, y - 28), Vector2(x + 10, y - 20), GREY, 2.0)
			ci.draw_line(Vector2(x + 42, y - 28), Vector2(x + 42, y - 20), GREY, 2.0)
			var rw = 13.0 + 5.0 * sin(t * 40.0)
			ci.draw_line(Vector2(x + 10 - rw, y - 29), Vector2(x + 10 + rw, y - 29), Color(1, 1, 1, 0.7), 2.0, true)
			ci.draw_line(Vector2(x + 42 - rw, y - 29), Vector2(x + 42 + rw, y - 29), Color(1, 1, 1, 0.7), 2.0, true)
			rr(ci, x + 6, y - 22, 40, 16, GREY, 5, MAG_L, 2)
			rr(ci, x + 14, y - 18, 24, 8, INK, 3)
			var ex = x + 18 + 8.0 * (0.5 + 0.5 * sin(t * 3.0))
			glow(ci, ex + 4, y - 14, 9, 7, AMB, 0.9)
			ci.draw_rect(Rect2(ex, y - 16, 8, 4), AMB_L)
			ci.draw_line(Vector2(x + 14, y - 6), Vector2(x + 10, y), GREY, 2.0, true)
			ci.draw_line(Vector2(x + 38, y - 6), Vector2(x + 42, y), GREY, 2.0, true)
		"jammer":
			glow(ci, x + 68, y - 2, 84, 10, Color.BLACK, 0.55)
			glow(ci, x + 68, y - 4, 88, 14, MAG, 0.35)
			for k in 3:
				var ph = fmod(t * 0.8 + k / 3.0, 1.0)
				ci.draw_arc(Vector2(x + 50, y - 70), 10 + ph * 44, PI * 1.15, PI * 1.85, 20, Color(MAG.r, MAG.g, MAG.b, 0.7 * (1.0 - ph)), 3.0, true)
			poly(ci, [4, -14, 4, -58, 98, -58, 98, -44, 124, -40, 132, -26, 132, -12, 4, -12], x, y, VIOLET3, MAG_L)
			ci.draw_rect(Rect2(x + 5, y - 30, 127, 5), MAG)
			poly(ci, [102, -40, 122, -37, 128, -27, 102, -27], x, y, Color("0d1a2c"))
			rr(ci, x + 44, y - 50, 32, 16, INDIGO, 3)
			ci.draw_line(Vector2(x + 48, y - 45), Vector2(x + 72, y - 45), MAG_L, 2.0)
			ci.draw_line(Vector2(x + 48, y - 40), Vector2(x + 62, y - 40), MAG, 2.0)
			for k in 3: ci.draw_line(Vector2(x + 16 + k * 7, y - 50 + abs(k - 1) * 3), Vector2(x + 16 + k * 7, y - 36 - abs(k - 1) * 3), MAG_L, 2.0)
			ci.draw_line(Vector2(x + 50, y - 58), Vector2(x + 50, y - 68), GREY, 3.0)
			poly(ci, [34, -70, 66, -70, 58, -64, 42, -64], x, y, WHITE)
			ci.draw_rect(Rect2(x + 128, y - 28, 4, 6), AMB_L)
			wheel(ci, x + 30, y - 12, 12, ang)
			wheel(ci, x + 104, y - 12, 12, ang)
		"swarm":
			var ox = [0, 24, 44, 10, 32]
			var oy = [12, 2, 16, 30, 26]
			for k in hp:
				var px = x + ox[k] + 2.0 * sin(t * 5.0 + k * 1.7)
				var py = y - 44 + oy[k] + 2.0 * cos(t * 6.0 + k * 2.1)
				glow(ci, px + 7, py + 3, 14, 10, MAG, 0.45)
				var rw2 = 8.0 + 3.0 * sin(t * 50.0 + k)
				ci.draw_line(Vector2(px + 7 - rw2, py - 2), Vector2(px + 7 + rw2, py - 2), Color(1, 1, 1, 0.7), 2.0, true)
				rr(ci, px, py, 14, 7, GREY, 3, MAG_L, 1)
				ci.draw_circle(Vector2(px + 7, py + 3.5), 2.0, MAG)
		"boss":
			var blink = fmod(t * 2.0, 1.0) < 0.5
			glow(ci, x + 98, y - 2, 120, 12, Color.BLACK, 0.6)
			glow(ci, x + 98, y - 6, 126, 18, MAG, 0.4)
			poly(ci, [4, -16, 4, -62, 150, -62, 150, -50, 184, -46, 192, -30, 192, -14, 188, -12, 4, -12], x, y, STEEL_L, MAG_L, 2.5)
			ci.draw_rect(Rect2(x + 5, y - 34, 187, 6), MAG)
			ci.draw_line(Vector2(x + 52, y - 60), Vector2(x + 52, y - 14), STEEL, 2.0)
			ci.draw_line(Vector2(x + 100, y - 60), Vector2(x + 100, y - 14), STEEL, 2.0)
			poly(ci, [158, -46, 182, -43, 188, -36, 158, -36], x, y, Color("3a0c30"))
			ci.draw_line(Vector2(x + 160, y - 40), Vector2(x + 184, y - 40), MAG_L, 2.0)
			rr(ci, x + 62, y - 80, 44, 20, GREY, 4, MAG_L, 2)
			ci.draw_line(Vector2(x + 14, y - 70), Vector2(x + 64, y - 70), WHITE, 5.0, true)
			ci.draw_rect(Rect2(x + 8, y - 75, 8, 10), WHITE)
			glow(ci, x + 96, y - 72, 10, 8, MAG, 0.9 if blink else 0.3)
			ci.draw_circle(Vector2(x + 96, y - 72), 3, MAG_L)
			glow(ci, x + 12, y - 54, 12, 10, MAG, 0.8 if blink else 0.2)
			ci.draw_rect(Rect2(x + 8, y - 57, 8, 5), MAG_L if blink else MAG_D)
			ci.draw_string(font, Vector2(x + 106, y - 42), "КПП", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
			wheel(ci, x + 28, y - 13, 13, ang)
			wheel(ci, x + 72, y - 13, 13, ang)
			wheel(ci, x + 160, y - 13, 13, ang)

# То, что лежит на полосах. x — центр, y — линия полосы.
static func road_object(ci: CanvasItem, kind: String, x: float, y: float, t: float) -> void:
	var bob = 3.0 * sin(t * 4.0 + x * 0.01)
	match kind:
		"debris":
			glow(ci, x, y - 2, 30, 6, Color.BLACK, 0.5)
			var blink = fmod(t * 3.0, 1.0) < 0.5
			glow(ci, x, y - 34, 16, 14, MAG, 0.85 if blink else 0.25)
			ci.draw_rect(Rect2(x - 18, y - 10, 5, 10), STEEL_L)
			ci.draw_rect(Rect2(x + 13, y - 10, 5, 10), STEEL_L)
			rr(ci, x - 23, y - 28, 46, 18, INK, 3, MAG_L, 2)
			for k in 4: poly(ci, [0, 0, 7, 0, 3, 12, -4, 12], x - 17 + k * 11, y - 25, MAG)
			ci.draw_circle(Vector2(x, y - 34), 4, MAG_L if blink else MAG_D)
		"cam":
			glow(ci, x, y - 2, 30, 6, Color.BLACK, 0.5)
			var a = 0.55 + 0.35 * sin(t * 18.0)
			glow(ci, x, y - 16, 30, 12, MAG, 0.5)
			rr(ci, x - 26, y - 30, 8, 30, STEEL_L, 2, MAG_L, 1)
			rr(ci, x + 18, y - 30, 8, 30, STEEL_L, 2, MAG_L, 1)
			for k in 3: ci.draw_line(Vector2(x - 18, y - 24 + k * 8), Vector2(x + 18, y - 24 + k * 8), Color(MAG_L.r, MAG_L.g, MAG_L.b, a), 2.0, true)
			ci.draw_circle(Vector2(x - 22, y - 34), 3, RED)
			ci.draw_circle(Vector2(x + 22, y - 34), 3, RED)
		"cell":
			glow(ci, x, y - 2, 18, 5, Color.BLACK, 0.4)
			glow(ci, x, y - 20 + bob, 26, 26, CYAN, 0.55)
			rr(ci, x - 9, y - 34 + bob, 18, 28, INK, 3, CYAN_L, 2)
			ci.draw_rect(Rect2(x - 4, y - 38 + bob, 8, 4), CYAN_L)
			ci.draw_rect(Rect2(x - 5, y - 30 + bob, 10, 8), CYAN)
			ci.draw_rect(Rect2(x - 5, y - 19 + bob, 10, 8), CYAN)
		_:
			glow(ci, x, y - 2, 18, 5, Color.BLACK, 0.4)
			glow(ci, x, y - 20 + bob, 24, 24, AMB, 0.55)
			for k in 3:
				ci.draw_rect(Rect2(x - 8 + k * 6, y - 34 + bob, 2, 5), AMB)
				ci.draw_rect(Rect2(x - 8 + k * 6, y - 11 + bob, 2, 5), AMB)
			rr(ci, x - 11, y - 30 + bob, 22, 20, AMB_D, 3, AMB_L, 2)
			ci.draw_rect(Rect2(x - 5, y - 25 + bob, 10, 10), AMB_L)

# ---------- портреты и значки (перенесены из пиксельной версии, k — масштаб) ----------

static func portrait(ci: CanvasItem, x: float, y: float, id: String, k: float = 2.0) -> void:
	var p = func(dx, dy, w, h, i): ci.draw_rect(Rect2(x + dx * k, y + dy * k, w * k, h * k), PAL[i])
	var bg = {"hacker": 8, "surgeon": 2, "guard": 21, "mechanic": 17, "musician": 13, "android": 1}[id]
	var cloth = {"hacker": 4, "surgeon": 25, "guard": 22, "mechanic": 18, "musician": 14, "android": 23}[id]
	var skin = 7 if id == "android" else 31
	var shade = 6 if id == "android" else 18
	var rows = [[0, 0, 32, 32, bg], [5, 25, 22, 7, cloth], [8, 23, 16, 2, cloth], [13, 20, 6, 4, shade], [10, 8, 12, 12, skin], [11, 7, 10, 1, skin], [11, 20, 10, 1, skin],
		[12, 13, 2, 2, 0], [18, 13, 2, 2, 0], [14, 18, 4, 1, 29]]
	match id:
		"hacker": rows += [[8, 3, 16, 5, 4], [7, 6, 3, 18, 4], [22, 6, 3, 18, 4], [10, 8, 12, 2, 3], [11, 12, 10, 3, 0], [12, 13, 8, 1, 11], [18, 13, 2, 1, 12], [9, 3, 14, 1, 5]]
		"surgeon": rows += [[10, 4, 12, 4, 10], [9, 8, 14, 1, 9], [11, 16, 10, 5, 25], [11, 16, 10, 1, 24], [10, 17, 1, 1, 24], [21, 17, 1, 1, 24], [15, 26, 2, 5, 30], [13, 28, 6, 1, 30]]
		"guard": rows += [[9, 3, 14, 8, 23], [9, 3, 14, 1, 24], [10, 11, 12, 4, 17], [11, 12, 10, 2, 19], [18, 12, 2, 1, 20], [11, 19, 10, 2, 22], [3, 24, 7, 4, 23], [22, 24, 7, 4, 23], [3, 24, 7, 1, 24], [22, 24, 7, 1, 24]]
		"mechanic": rows += [[10, 5, 12, 4, 30], [22, 7, 3, 2, 30], [10, 5, 12, 1, 29], [11, 17, 10, 4, 17], [14, 18, 4, 1, 31], [10, 25, 2, 7, 17], [20, 25, 2, 7, 17], [12, 28, 8, 1, 17]]
		"musician": rows += [[9, 4, 14, 5, 15], [8, 6, 3, 9, 15], [21, 6, 3, 5, 15], [19, 2, 5, 3, 16], [9, 4, 14, 1, 16], [8, 2, 16, 1, 0], [6, 10, 3, 7, 0], [23, 10, 3, 7, 0], [6, 12, 1, 3, 11], [25, 12, 1, 3, 11], [13, 27, 6, 1, 16]]
		"android": rows += [[16, 7, 1, 14, 6], [12, 13, 3, 2, 11], [18, 13, 3, 2, 11], [13, 13, 1, 1, 12], [19, 13, 1, 1, 12], [15, 9, 2, 2, 15], [14, 18, 4, 1, 6], [13, 20, 6, 4, 22], [14, 21, 1, 3, 11], [17, 21, 1, 3, 11], [10, 19, 12, 1, 6], [5, 25, 22, 1, 24]]
	for q in rows: p.call(q[0], q[1], q[2], q[3], q[4])

const ICONS = {
	"road": ["..#####..", ".#######.", "##.###.##", "##.###.##", "#########", ".###.###.", "..#####..", "..#.#.#.."],
	"hitch": ["...###...", "...###...", "....#....", "..#####..", ".#.###.#.", "...###...", "...#.#...", "..##.##.."],
	"shop": [".##......", "#..#.....", "#.##.....", ".####....", "...###...", "....###..", ".....###.", "......##."],
	"gate": ["#########", "#.#.#.#.#", "#########", ".#.....#.", ".#.....#.", ".#.....#.", ".#.....#.", "###...###"],
	"start": ["....#....", "...###...", "..#####..", ".#######.", ".##...##.", ".##...##.", ".##...##.", ".##...##."],
	"park": [".######..", ".##...##.", ".##...##.", ".######..", ".##......", ".##......", ".##......", ".##......"],
	"meet": ["..####...", ".##..##..", ".....##..", "....##...", "...##....", "...##....", ".........", "...##...."],
	"hidden": [".........", ".........", ".........", ".#..#..#.", ".........", ".........", ".........", "........."],
}

# Значок узла карты 9×8 клеток, k — размер клетки.
static func icon(ci: CanvasItem, name: String, x: float, y: float, col: Color, k: float = 2.0) -> void:
	var rows = ICONS[name]
	for yy in rows.size():
		var row: String = rows[yy]
		for xx in row.length():
			if row[xx] == "#": ci.draw_rect(Rect2(x + xx * k, y + yy * k, k, k), col)

const ITEM_ICONS = {
	"cell": [[3, 2, 6, 9, 22], [5, 1, 2, 1, 24], [4, 4, 4, 2, 11], [4, 7, 4, 2, 11]],
	"patch": [[2, 3, 8, 6, 25], [5, 4, 2, 4, 30], [4, 5, 4, 2, 30]],
	"stim": [[5, 1, 2, 8, 25], [4, 3, 4, 4, 15], [6, 9, 1, 3, 24], [3, 1, 6, 1, 24]],
	"emp": [[3, 4, 6, 6, 22], [5, 2, 2, 2, 24], [7, 1, 2, 2, 19], [3, 6, 6, 1, 11], [4, 8, 4, 1, 11]],
	"smoke": [[4, 3, 5, 8, 23], [5, 2, 3, 1, 24], [4, 6, 5, 2, 7], [2, 0, 3, 2, 24], [6, 0, 2, 1, 24]],
	"kit": [[1, 4, 10, 6, 30], [4, 2, 4, 2, 29], [5, 6, 2, 2, 25], [1, 4, 10, 1, 16]],
	"food": [[3, 2, 6, 9, 18], [3, 4, 6, 2, 19], [4, 8, 4, 1, 20]],
	"scrap": [[2, 2, 8, 8, 23], [4, 4, 4, 4, 21], [5, 0, 2, 2, 23], [5, 10, 2, 2, 23], [0, 5, 2, 2, 23], [10, 5, 2, 2, 23]],
	"chip": [[2, 3, 8, 6, 27], [3, 1, 1, 2, 24], [6, 1, 1, 2, 24], [8, 1, 1, 2, 24], [3, 9, 1, 2, 24], [6, 9, 1, 2, 24], [8, 9, 1, 2, 24], [4, 5, 4, 2, 28]],
	"contra": [[1, 2, 10, 9, 17], [1, 2, 10, 1, 18], [1, 6, 10, 1, 18], [5, 2, 2, 9, 18]],
	"case": [[1, 3, 10, 7, 22], [1, 3, 10, 1, 24], [4, 1, 4, 2, 23], [5, 6, 2, 2, 19], [2, 8, 8, 1, 15]],
	"tools": [[1, 3, 10, 7, 25], [4, 1, 4, 2, 24], [5, 5, 2, 4, 30], [4, 6, 4, 2, 30]],
}

# Значок предмета 12×12 клеток.
static func item_icon(ci: CanvasItem, id: String, x: float, y: float, k: float = 4.0) -> void:
	for q in ITEM_ICONS[id]:
		ci.draw_rect(Rect2(x + q[0] * k, y + q[1] * k, q[2] * k, q[3] * k), PAL[q[4]])
