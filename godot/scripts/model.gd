# Игровая модель: чистая логика без узлов и отрисовки. Порт src/model.js один в один:
# те же поля состояния, тот же порядок обращений к ГСЧ. Точность порта проверяет
# tools/replay.gd — он прогоняет эталонные заезды из JS и сверяет состояние по шагам.
# Единственная точка входа для изменений — act(s, action).

const D = preload("res://scripts/data.gd")

const TRUNK_W = 6
const TRUNK_H = 4
const DAWN = 8
const DEBT_LIMIT = 100
const MAX_ENEMIES = 4
const TARGETED = ["gun", "ram", "hack", "pull", "push"]

# ---------- ГСЧ (mulberry32, бит в бит как в JS) ----------

static func _imul(a: int, b: int) -> int:
	return (((a & 0xFFFF) * b) + (((((a >> 16) & 0xFFFF) * b) & 0xFFFF) << 16)) & 0xFFFFFFFF

static func rng_next(s) -> float:
	s.rng = (s.rng + 0x6d2b79f5) & 0xFFFFFFFF
	var t: int = s.rng
	t = _imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

static func rng_int(s, n: int) -> int:
	return int(floor(rng_next(s) * n))

static func rng_pick(s, arr: Array):
	return arr[rng_int(s, arr.size())]

# ---------- общее ----------

# Число с правильной формой слова: plural(3, "ход", "хода", "ходов") → «3 хода».
static func plural(n: int, one: String, few: String, many: String) -> String:
	var a = abs(n) % 100
	var b = a % 10
	var w = many
	if not (a > 10 and a < 20):
		if b == 1: w = one
		elif b >= 2 and b <= 4: w = few
	return str(n) + " " + w

static func new_run(seed_value: int) -> Dictionary:
	var sd = seed_value & 0xFFFFFFFF
	var s = {
		"seed": sd, "rng": sd, "screen": "title",
		"res": {"charge": 10, "hull": 12, "focus": 8, "credits": 40, "wanted": 0},
		"max": {"charge": 12, "hull": 12, "focus": 10, "wanted": 10},
		"hour": 0, "crew": [], "trunk": [], "glove": ["patch", null, null], "uid": 1,
		"up": {"armor": 0, "guns": 0, "deck": 0, "battery": 0},
		"map": null, "at": 0, "drive": null, "battle": null, "event": null, "result": null, "park": null,
		"usedEvents": [], "usedHitch": [], "over": null, "fx": [],
		"stats": {"nodes": 0, "battles": 0, "wins": 0, "escapes": 0, "crits": 0, "hits": 0, "picks": 0},
	}
	gen_map(s)
	for id in ["case", "kit", "cell", "food"]:
		add_item(s, id)
	return s

# ---------- карта ----------

static func gen_map(s) -> void:
	var nodes = []
	var cols = {}
	var add = func(col, row, type):
		var n = {"id": nodes.size(), "col": col, "row": row, "type": type, "next": [], "seen": false}
		nodes.append(n)
		if not cols.has(col): cols[col] = []
		cols[col].append(n)
		return n
	add.call(0, 1, "start").seen = true
	for c in range(1, 7):
		var rows = [1, 2]
		if rng_next(s) < 0.5: rows = [0, 1, 2]
		elif rng_next(s) < 0.5: rows = [0, 1]
		for r in rows:
			add.call(c, r, "road" if rng_next(s) < 0.7 else "meet")
	add.call(7, 1, "gate")
	for pair in [[1, "hitch"], [3, "park"], [4, "shop"], [5, "hitch"]]:
		rng_pick(s, cols[pair[0]]).type = pair[1]
	for c in [2, 6]:
		if not cols[c].any(func(n): return n.type == "road"):
			cols[c][0].type = "road"
	for c in range(0, 7):
		var a_col = cols[c]
		var b_col = cols[c + 1]
		for a in a_col:
			for b in b_col:
				if a_col.size() == 1 or b_col.size() == 1 or abs(a.row - b.row) <= 1:
					a.next.append(b.id)
	s.map = {"nodes": nodes}
	s.at = 0

static func node_visible(s, n) -> bool:
	var cur = s.map.nodes[s.at]
	return n.seen or n.type == "gate" or n.col <= cur.col + 1 + (1 if s.up.deck else 0)

# ---------- экипаж и инвентарь ----------

static func crew_has(s, id) -> bool:
	return s.crew.any(func(c): return c.id == id)

static func item_size(it) -> Array:
	var d = D.ITEMS[it.id]
	return [d.h, d.w] if it.r else [d.w, d.h]

static func fits(s, id, x, y, r, skip_uid = null) -> bool:
	var d = D.ITEMS[id]
	var w = d.h if r else d.w
	var h = d.w if r else d.h
	if typeof(x) != TYPE_INT or typeof(y) != TYPE_INT: return false
	if x < 0 or y < 0 or x + w > TRUNK_W or y + h > TRUNK_H: return false
	for o in s.trunk:
		if skip_uid != null and o.uid == skip_uid: continue
		var sz = item_size(o)
		if x < o.x + sz[0] and o.x < x + w and y < o.y + sz[1] and o.y < y + h: return false
	return true

static func find_spot(s, id):
	for r in range(2):
		for y in range(TRUNK_H):
			for x in range(TRUNK_W):
				if fits(s, id, x, y, r): return {"x": x, "y": y, "r": r}
	return null

# Кладёт предмет в багажник, а если места нет — мелочь в бардачок.
static func add_item(s, id) -> bool:
	var p = find_spot(s, id)
	if p != null:
		s.trunk.append({"uid": s.uid, "id": id, "x": p.x, "y": p.y, "r": p.r})
		s.uid += 1
		return true
	if D.ITEMS[id].get("small", false):
		var g = s.glove.find(null)
		if g >= 0:
			s.glove[g] = id
			return true
	return false

static func remove_item(s, uid) -> void:
	s.trunk = s.trunk.filter(func(t): return t.uid != uid)

static func drop_crew(s, id, lines: Array, text = "") -> void:
	s.crew = s.crew.filter(func(c): return c.id != id)
	if id == "surgeon":
		s.trunk = s.trunk.filter(func(t): return t.id != "tools")
	lines.append(text if text != "" else D.CREW[id].name + " выходит из машины.")

# ---------- ресурсы ----------

static func gain(s, k: String, n: int) -> void:
	var r = s.res
	if k == "wanted" and n > 0 and crew_has(s, "android"): n *= 2
	if k == "credits": r.credits += n
	else: r[k] = clampi(r[k] + n, 0, s.max[k])

static func snap(s) -> Dictionary:
	var r = s.res
	return {"charge": r.charge, "hull": r.hull, "focus": r.focus, "credits": r.credits, "wanted": r.wanted, "hour": s.hour}

static func diff(a: Dictionary, s) -> Array:
	var b = snap(s)
	var out = []
	for k in a:
		if b[k] != a[k]: out.append({"k": k, "n": b[k] - a[k]})
	return out

static func apply_fx(s, fx, lines: Array) -> void:
	if fx == null or fx.is_empty(): return
	if fx.has("res"):
		for k in fx.res: gain(s, k, fx.res[k])
	if fx.get("hour", 0): s.hour += fx.hour
	for id in [fx.get("item"), fx.get("item2")]:
		if id:
			lines.append("Получено: " + D.ITEMS[id].name + "." if add_item(s, id) else D.ITEMS[id].name + " не влезает: багажник полон.")
	if fx.get("trust", 0) and s.crew.size() > 0:
		for c in s.crew: c.trust = clampi(c.trust + fx.trust, 0, 3)
		lines.append("Экипаж одобряет: доверие +1." if fx.trust > 0 else "Экипажу это не по душе: доверие −1.")
		for c in s.crew.filter(func(m): return m.trust <= 0):
			drop_crew(s, c.id, lines, D.CREW[c.id].name + " больше тебе не верит и выходит.")
	if fx.get("special", "") == "contra" and crew_has(s, "guard"):
		drop_crew(s, "guard", lines, "Гранит молча выходит: с контрабандой ему не по пути.")

static func lose(s, text: String) -> void:
	if s.over == null: s.over = {"win": false, "text": text}

static func win(s, text: String) -> void:
	if s.over == null: s.over = {"win": true, "text": text}

# Критические состояния: один ноль — дорогая проблема, два сразу — конец рейса.
static func resolve_crit(s, lines: Array) -> bool:
	if s.over != null: return false
	var r = s.res
	var z = []
	if r.charge <= 0: z.append("charge")
	if r.hull <= 0: z.append("hull")
	if r.focus <= 0: z.append("focus")
	if z.size() >= 2:
		lines.append("Сразу два ресурса в нуле. Дальше ехать не на чем и некому.")
		lose(s, "Машина и водитель сдали одновременно. Кейс достанется тем, кто найдёт тебя первым.")
		return true
	if z.size() > 0 and z[0] == "charge":
		r.credits -= 40; s.hour += 2; r.charge = 5
		lines.append("Батарея в нуле. Буксир до колонки: −40 кр, +2 ч.")
	elif z.size() > 0 and z[0] == "hull":
		r.credits -= 60; r.hull = 6
		var loose = s.trunk.filter(func(t): return not D.ITEMS[t.id].get("lock", false))
		var lost = ""
		if loose.size() > 0:
			var t = rng_pick(s, loose)
			remove_item(s, t.uid)
			lost = " В суматохе пропало: " + D.ITEMS[t.id].name + "."
		lines.append("Машина разбита. Эвакуатор и латка: −60 кр." + lost)
	elif z.size() > 0 and z[0] == "focus":
		s.hour += 3; r.hull = maxi(1, r.hull - 3); r.focus = 4
		lines.append("Отключка за рулём. Очнулся в отбойнике: +3 ч, Корпус −3.")
	if z.size() > 0: s.stats.crits += 1
	if r.credits < -DEBT_LIMIT:
		lines.append("Долг вырос выше " + str(DEBT_LIMIT) + " кр.")
		lose(s, "Ростовщик забрал машину за долги. Кейс уехал вместе с ней.")
		return true
	return z.size() > 0

# then — куда вернуться после экрана итога; посреди перегона это всегда дорога.
static func finish(s, title: String, lines: Array, before: Dictionary, then: String) -> void:
	resolve_crit(s, lines)
	var to = then
	if s.over != null: to = "end"
	elif s.drive != null: to = "drive"
	s.result = {"title": title, "lines": lines, "deltas": diff(before, s), "then": to}
	s.screen = "result"

# ---------- дорога ----------

# Шанс засады по дороге в узел. Интерфейс показывает его до выезда.
static func ambush_chance(s, n, mode: String) -> float:
	if n.type == "gate" or n.type == "start": return 0.0
	if n.type == "road": return 1.0
	return D.MODES[mode].ambush + (0.25 if s.res.wanted >= 5 else 0.0)

# Раскладка перегона: в каждом столбце хотя бы одна полоса свободна,
# после столбца с двумя препятствиями идёт пустой.
static func gen_road(s, mode: String) -> Array:
	var objs = []
	var rest = false
	for x in range(3, D.TRIP_LEN - 1):
		if rest:
			rest = false
			continue
		var lanes = [0, 1, 2]
		var pull = func():
			var i = rng_int(s, lanes.size())
			var v = lanes[i]
			lanes.remove_at(i)
			return v
		if rng_next(s) < 0.5:
			var two = rng_next(s) < 0.3
			for k in range(2 if two else 1):
				var lane = pull.call()
				var kind = "cam" if (mode != "quiet" and rng_next(s) < 0.25) else "debris"
				objs.append({"x": x, "lane": lane, "k": kind})
			rest = two
		if rng_next(s) < 0.2:
			var lane2 = pull.call()
			objs.append({"x": x, "lane": lane2, "k": "cell" if rng_next(s) < 0.3 else "chip"})
	return objs

static func travel(s, to, mode) -> bool:
	if typeof(mode) != TYPE_STRING or not D.MODES.has(mode) or typeof(to) != TYPE_INT: return false
	var cur = s.map.nodes[s.at]
	if not cur.next.has(to): return false
	var m = D.MODES[mode]
	var before = snap(s)
	var n = s.map.nodes[to]
	var chance = ambush_chance(s, n, mode)
	gain(s, "charge", -m.charge)
	s.hour += m.hours
	if m.wanted: gain(s, "wanted", m.wanted)
	var dawn = s.hour > DAWN
	if dawn: gain(s, "focus", -2)
	s.at = to
	var d = {"mode": mode, "dawn": dawn, "len": D.TRIP_LEN, "pos": 0, "lane": 1, "objs": gen_road(s, mode), "ambushAt": -1, "ambush": null}
	s.drive = d
	if chance > 0 and rng_next(s) < chance:
		var tier = 0 if n.col <= 2 else (1 if n.col <= 4 else 2)
		d.ambush = rng_pick(s, D.GROUPS[tier if n.type == "road" else maxi(0, tier - 1)]).duplicate()
		d.ambushAt = 6 + rng_int(s, 6)
	s.screen = "drive"
	var lines = []
	if dawn: lines.append("Рассвет. Город просыпается, голова тяжелеет: Фокус −2.")
	if resolve_crit(s, lines):
		s.result = {"title": "В пути", "lines": lines, "deltas": diff(before, s), "then": "end" if s.over != null else "drive"}
		s.screen = "result"
	return true

# Дорога: steer перестраивает машину, tick проезжает один отрезок.
static func drive_act(s, a) -> bool:
	var d = s.drive
	if a.type == "steer":
		var dir = a.get("dir")
		if typeof(dir) != TYPE_INT or (dir != -1 and dir != 1): return false
		var lane = d.lane + dir
		if lane < 0 or lane > 2: return false
		d.lane = lane
		return true
	if a.type != "tick": return false
	if d.pos == d.ambushAt:   # враги нагнали
		d.ambushAt = -1
		start_battle(s, d.ambush, false)
		return true
	if d.pos >= d.len:        # приехали
		s.drive = null
		enter_node(s)
		return true
	var before = snap(s)
	var lines = []
	d.pos += 1
	for i in range(d.objs.size() - 1, -1, -1):
		var o = d.objs[i]
		if o.x != d.pos or o.lane != d.lane: continue
		var ob = D.ROAD_OBJ[o.k]
		gain(s, ob.res, ob.n)
		s.stats["hits" if ob.get("bad", false) else "picks"] += 1
		s.fx.append({"k": "road", "kind": o.k})
		d.objs.remove_at(i)
	if resolve_crit(s, lines):
		s.result = {"title": "В пути", "lines": lines, "deltas": diff(before, s), "then": "end" if s.over != null else "drive"}
		s.screen = "result"
	return true

static func enter_node(s) -> void:
	var n = s.map.nodes[s.at]
	n.seen = true
	s.stats.nodes += 1
	match n.type:
		"gate":
			start_battle(s, ["boss", "drone"], true)
		"meet":
			var pool = D.EVENTS.filter(func(e): return not s.usedEvents.has(e.id))
			if pool.is_empty():
				s.usedEvents = []
				pool = D.EVENTS
			var e = rng_pick(s, pool)
			s.usedEvents.append(e.id)
			s.event = {"id": e.id}
			s.screen = "event"
		"hitch":
			var pool2 = D.CREW.keys().filter(func(id): return not crew_has(s, id) and not s.usedHitch.has(id))
			var who = rng_pick(s, pool2)
			s.usedHitch.append(who)
			s.event = {"id": "hitch", "who": who}
			s.screen = "event"
		"park":
			s.park = {"rested": false, "talked": []}
			s.screen = "park"
		"shop":
			s.screen = "shop"
		_:
			s.screen = "map"

# ---------- события ----------

static func need_why(s, need) -> String:
	if need == null: return ""
	if need.has("crew") and not crew_has(s, need.crew): return "Нужен попутчик: " + D.CREW[need.crew].name
	if need.has("credits") and s.res.credits < need.credits: return "Нужно " + str(need.credits) + " кр"
	if need.has("space") and find_spot(s, need.space) == null: return "Нет места в багажнике"
	return ""

static func find_event(id):
	for e in D.EVENTS:
		if e.id == id: return e
	return null

# Что показывать на экране события: заголовок, текст и варианты с доступностью.
static func event_view(s):
	var ev = s.event
	if ev == null: return null
	if ev.id == "hitch":
		var c = D.CREW[ev.who]
		var full = s.crew.size() >= 3
		var no_space = ev.who == "surgeon" and find_spot(s, "tools") == null
		var why = "В салоне нет мест" if full else ("Нет 4 клеток под багаж" if no_space else "")
		return {
			"title": "Попутчик: " + c.name,
			"text": D.HITCH_TEXT[ev.who] + " " + c.role + ". Навык «" + c.skill + "»: " + c.desc + " Минус: " + c.flaw,
			"options": [
				{"label": "Подвезти" + (" (+" + str(c.fare) + " кр за проезд)" if c.fare else ""), "ok": not full and not no_space, "why": why},
				{"label": "Проехать мимо", "ok": true, "why": ""},
			],
		}
	var e = find_event(ev.id)
	var opts = []
	for o in e.options:
		var w = need_why(s, o.get("need"))
		opts.append({"label": o.label, "ok": w == "", "why": w})
	return {"title": e.title, "text": e.text, "options": opts}

static func choose_event(s, i) -> bool:
	var v = event_view(s)
	if v == null or typeof(i) != TYPE_INT or i < 0 or i >= v.options.size() or not v.options[i].ok: return false
	var before = snap(s)
	var lines = []
	var ev = s.event
	if ev.id == "hitch":
		if i == 0:
			var c = D.CREW[ev.who]
			s.crew.append({"id": ev.who, "trust": 2, "cd": 0, "used": false})
			if c.fare: gain(s, "credits", c.fare)
			if ev.who == "surgeon": add_item(s, "tools")
			lines.append(c.name + " садится в машину. В бою доступен навык «" + c.skill + "».")
		else:
			lines.append("Фигура у обочины остаётся в зеркале.")
	else:
		var o = find_event(ev.id).options[i]
		lines.append(o.text)
		apply_fx(s, o.get("fx"), lines)
		if o.has("risk") and rng_next(s) < o.risk.p:
			lines.append(o.risk.text)
			apply_fx(s, o.risk.fx, lines)
	s.event = null
	finish(s, v.title, lines, before, "map")
	return true

# ---------- бой ----------

static func living(b) -> Array:
	return b.enemies.filter(func(e): return e.hp > 0)

static func mk_enemy(s, type: String, dist = null) -> Dictionary:
	var e = D.ENEMIES[type]
	return {"type": type, "hp": e.hp, "max": e.hp, "dist": e.start if dist == null else dist, "stun": 0, "pi": rng_int(s, e.pattern.size()), "called": false}

static func blog(s, text: String) -> void:
	var l = s.battle.log
	l.append(text)
	if l.size() > 6: l.pop_front()

static func start_battle(s, types: Array, boss: bool) -> void:
	var b = {"turn": 1, "ap": 3, "shield": 0, "escape": 0, "heat": 0, "boss": boss, "enemies": [],
		"usedItem": false, "hacked": false, "noisy": false, "mark": -1, "log": [], "before": snap(s)}
	s.battle = b
	for t in types: b.enemies.append(mk_enemy(s, t))
	if boss: b.enemies[0].pi = 0
	if not boss and s.res.wanted >= 5:
		b.enemies.append(mk_enemy(s, "patrol", 2))
		b.log.append("Розыск высокий: на хвосте лишний патруль.")
	for c in s.crew:
		c.cd = 0
		c.used = false
	s.stats.battles += 1
	s.screen = "battle"

# Намерение врага — чистая функция от его состояния, поэтому интерфейс
# показывает его «вживую»: оттеснили врага — удар сменился сближением.
static func intent_of(s, e) -> Dictionary:
	var en = D.ENEMIES[e.type]
	if e.stun > 0: return {"k": "stun"}
	var mv = en.pattern[e.pi % en.pattern.size()]
	if mv.k == "call" and e.called: mv = {"k": "hit", "res": "hull", "n": 2}
	if mv.k == "hit" and e.dist > en.reach: return {"k": "approach"}
	if en.get("swarm", false):
		return {"k": "hit", "res": "charge" if s.res.charge > 0 else "hull", "n": int(ceil(e.hp / 2.0))}
	return mv

# План на следующий ход (его видит андроид).
static func next_intent(s, e) -> Dictionary:
	var cur = intent_of(s, e)
	var sim = {"type": e.type, "hp": e.hp, "dist": e.dist, "stun": 0, "pi": e.pi, "called": e.called}
	if cur.k == "approach": sim.dist -= 1
	elif cur.k != "stun":
		sim.pi += 1
		if cur.k == "call": sim.called = true
	return intent_of(s, sim)

static func needs_target(s, a) -> bool:
	if TARGETED.has(a.type): return true
	if a.type == "skill":
		var ci = a.get("crew")
		if typeof(ci) == TYPE_INT and ci >= 0 and ci < s.crew.size():
			return D.CREW[s.crew[ci].id].has("target")
	return false

# Проверка цели: без a.target — есть ли хоть одна подходящая; f(e) возвращает причину отказа или "".
static func _tgt(s, a, f: Callable) -> String:
	var b = s.battle
	var t = a.get("target")
	if t == null:
		return "" if b.enemies.any(func(e): return e.hp > 0 and f.call(e) == "") else "Нет подходящей цели"
	if typeof(t) != TYPE_INT or t < 0 or t >= b.enemies.size() or b.enemies[t].hp <= 0: return "Нет цели"
	return f.call(b.enemies[t])

# Причина, по которой действие недоступно, или "" если всё в порядке.
static func battle_why(s, a) -> String:
	var b = s.battle
	var r = s.res
	if b == null: return "Нет боя"
	var jam = b.enemies.any(func(e): return e.hp > 0 and D.ENEMIES[e.type].get("jam", false))
	match a.type:
		"endTurn":
			return ""
		"gun":
			if b.ap < 1: return "Нужно 1 ОД"
			return _tgt(s, a, func(e): return "" if e.dist <= 1 else "Стволы достают только до средней")
		"ram":
			if b.ap < 2: return "Нужно 2 ОД"
			if r.hull <= 1: return "Корпус на пределе"
			return _tgt(s, a, func(e): return "" if e.dist == 0 else "Таран только вплотную")
		"hack":
			if b.ap < 1: return "Нужно 1 ОД"
			if jam: return "Глушилка блокирует взлом"
			if r.focus < 2: return "Нужно 2 Фокуса"
			return _tgt(s, a, func(_e): return "")
		"pull", "push":
			if b.ap < 1: return "Нужно 1 ОД"
			var dd = -1 if a.type == "pull" else 1
			var can_move = func(e):
				var cost = 2 if D.ENEMIES[e.type].get("heavy", false) else 1
				if r.charge < cost: return "Нужно " + str(cost) + " Заряда"
				var nd = e.dist + dd
				return "Уже вплотную" if nd < 0 else ("Дальше некуда" if nd > 2 else "")
			return _tgt(s, a, can_move)
		"skill":
			var ci = a.get("crew")
			if typeof(ci) != TYPE_INT or ci < 0 or ci >= s.crew.size(): return "Нет попутчика"
			var c = s.crew[ci]
			var cd = D.CREW[c.id]
			if c.id == "musician":
				if c.used: return "Уже сыграно в этом бою"
			elif c.cd > 0: return "Откат: ещё " + plural(c.cd, "ход", "хода", "ходов")
			if b.ap < cd.ap: return "Нужно " + str(cd.ap) + " ОД"
			if c.id == "hacker":
				if jam: return "Глушилка блокирует взлом"
				return _tgt(s, a, func(e): return "" if D.ENEMIES[e.type].get("tech", false) else "Только по технике")
			if c.id == "android": return _tgt(s, a, func(_e): return "")
			return ""
		"item":
			var slot = a.get("slot")
			if typeof(slot) != TYPE_INT or slot < 0 or slot > 2 or s.glove[slot] == null: return "Пусто"
			var id = s.glove[slot]
			if not D.ITEMS[id].has("battle"): return "В бою бесполезно"
			if b.usedItem: return "Один предмет за ход"
			return ""
		"escape":
			if b.boss: return "От КПП не уйти: только прорыв"
			if b.ap < 1: return "Нужно хотя бы 1 ОД"
			return ""
	return "Неизвестное действие"

static func battle_targets(s, a) -> Array:
	var out = []
	for i in range(s.battle.enemies.size()):
		var a2 = a.duplicate()
		a2["target"] = i
		if battle_why(s, a2) == "": out.append(i)
	return out

static func hit(s, i: int, n: int, kind: String) -> void:
	var b = s.battle
	var e = b.enemies[i]
	var en = D.ENEMIES[e.type]
	if b.mark == i: n *= 2
	if en.get("swarm", false) and kind != "ram" and kind != "aoe": n = mini(n, 1)
	n = mini(n, e.hp)
	e.hp -= n
	s.fx.append({"k": "dmg", "i": i, "n": n})
	blog(s, en.name + ": −" + str(n) + (", цель выведена из строя" if e.hp == 0 else ""))

static func battle_act(s, a) -> bool:
	var b = s.battle
	var r = s.res
	if battle_why(s, a) != "": return false
	var nt = needs_target(s, a)
	if nt and a.get("target") == null: return false
	var e = b.enemies[a.target] if nt else null
	var en = D.ENEMIES[e.type] if e != null else null
	match a.type:
		"endTurn":
			enemy_phase(s)
			return true
		"gun":
			b.ap -= 1; b.noisy = true
			hit(s, a.target, 2 + s.up.guns, "gun")
		"ram":
			b.ap -= 2; b.noisy = true
			gain(s, "hull", -1)
			hit(s, a.target, 5, "ram")
		"hack":
			b.ap -= 1
			gain(s, "focus", -1)
			if not b.hacked:
				b.hacked = true
				gain(s, "wanted", 1)
			hit(s, a.target, (2 + s.up.deck) * (2 if en.get("tech", false) else 1), "hack")
		"pull", "push":
			b.ap -= 1
			gain(s, "charge", -(2 if en.get("heavy", false) else 1))
			e.dist += -1 if a.type == "pull" else 1
			blog(s, en.name + (": подтянули ближе" if a.type == "pull" else ": оттеснили дальше"))
		"skill":
			var c = s.crew[a.crew]
			var cd = D.CREW[c.id]
			b.ap -= cd.ap
			c.cd = maxi(1, cd.cd - (1 if c.trust >= 3 else 0))
			blog(s, cd.name + ": «" + cd.skill + "»")
			match c.id:
				"hacker":
					e.stun = 1
					if not b.hacked:
						b.hacked = true
						gain(s, "wanted", 1)
				"surgeon": gain(s, "focus", 3)
				"guard": b.shield += 5
				"mechanic": gain(s, "hull", 3)
				"musician":
					c.used = true
					c.cd = 0
					b.ap += 1
				"android": b.mark = a.target
		"item":
			var id = s.glove[a.slot]
			var f = D.ITEMS[id].battle
			s.glove[a.slot] = null
			b.usedItem = true
			blog(s, "Из бардачка: " + D.ITEMS[id].name)
			for k in ["charge", "hull", "focus"]:
				if f.get(k, 0): gain(s, k, f[k])
			if f.get("ap", 0): b.ap += f.ap
			if f.get("shield", 0): b.shield += f.shield
			if f.get("emp", 0):
				for i in range(b.enemies.size()):
					var x = b.enemies[i]
					if x.hp <= 0: continue
					if D.ENEMIES[x.type].get("tech", false): x.stun = 1
					hit(s, i, f.emp, "aoe")
		"escape":
			var k2 = "charge" if r.charge >= 2 else "hull"
			gain(s, k2, -2)
			var close = living(b).filter(func(x): return x.dist == 0).size()
			b.escape = mini(100, b.escape + maxi(5, 20 * b.ap + 10 - 10 * close))
			b.ap = 0
			blog(s, "Отрыв: " + str(b.escape) + " %" + (" (на износ: Корпус −2)" if k2 == "hull" else ""))
			if r.hull <= 0:
				end_battle(s, "defeat")
				return true
			if b.escape >= 100:
				end_battle(s, "escape")
				return true
	if s.battle != null and living(b).is_empty(): end_battle(s, "win")
	return true

static func enemy_phase(s) -> void:
	var b = s.battle
	var r = s.res
	var count = b.enemies.size()
	for i in range(count):
		var e = b.enemies[i]
		if e.hp <= 0: continue
		var en = D.ENEMIES[e.type]
		var it = intent_of(s, e)
		if it.k == "stun":
			e.stun -= 1
			blog(s, en.name + ": сбой, ход пропущен")
			continue
		if it.k == "approach":
			e.dist -= 1
			blog(s, en.name + " сближается")
			continue
		e.pi = (e.pi + 1) % en.pattern.size()
		if it.k == "aim":
			blog(s, en.name + " наводит орудие")
			continue
		if it.k == "call":
			e.called = true
			gain(s, "wanted", 1)
			if living(b).size() < MAX_ENEMIES:
				var n2 = mk_enemy(s, "patrol", 2)
				n2.called = true
				b.enemies.append(n2)
				blog(s, en.name + " вызывает подмогу: розыск +1")
			else:
				blog(s, en.name + " сообщает о погоне: розыск +1")
			continue
		var n: int = it.n
		var ab = 0
		if it.res == "hull":
			n = maxi(1, n - s.up.armor)
			ab = mini(b.shield, n)
			b.shield -= ab
			n -= ab
		if n > 0: gain(s, it.res, -n)
		s.fx.append({"k": "hurt", "i": i, "res": it.res, "n": n})
		blog(s, en.name + ": " + D.RES_NAME[it.res] + " −" + str(n) + (" (щит снял " + str(ab) + ")" if ab else ""))
		if r.hull <= 0 or r.focus <= 0 or r.credits < -DEBT_LIMIT:
			end_battle(s, "defeat")
			return
	b.turn += 1; b.ap = 3; b.shield = 0; b.mark = -1; b.usedItem = false
	for c in s.crew:
		if c.cd > 0: c.cd -= 1
	if not b.boss:
		b.heat += 1
		if b.heat >= 6:
			b.heat = 0
			gain(s, "wanted", 1)
			if living(b).size() < MAX_ENEMIES:
				var n3 = mk_enemy(s, "patrol", 2)
				n3.called = true
				b.enemies.append(n3)
			blog(s, "Бой затянулся: шум привлёк патруль, розыск +1")

static func end_battle(s, outcome: String) -> void:
	var b = s.battle
	var lines = []
	var title = ""
	if outcome == "win":
		title = "Победа"
		var bounty = 0
		for e in b.enemies: bounty += D.ENEMIES[e.type].bounty
		gain(s, "credits", bounty)
		lines.append("Дорога свободна. С обломков снято " + str(bounty) + " кр.")
		if b.noisy:
			gain(s, "wanted", 1)
			lines.append("Стрельбу слышал весь квартал: розыск вырос.")
		if rng_next(s) < 0.6:
			var id = rng_pick(s, D.LOOT)
			lines.append("Трофей: " + D.ITEMS[id].name + "." if add_item(s, id) else "Трофей «" + D.ITEMS[id].name + "» не влез в багажник.")
		s.stats.wins += 1
		if b.boss: win(s, "Броневик дымит на обочине, шлагбаум поднят. Кейс едет дальше, в Развязку.")
	elif outcome == "escape":
		title = "Оторвались"
		lines.append("Погоня отстала в переулках. Добычи нет, зато все целы.")
		s.stats.escapes += 1
	else:
		title = "Бой проигран"
		if b.boss:
			lines.append("Броневик прижал машину к отбойнику.")
			lose(s, "КПП не пройден. Кейс конфискован, рейс окончен.")
		else:
			lines.append("Тебя выбили с трассы.")
	s.battle = null
	finish(s, title, lines, b.before, "map")

# ---------- стоянка, мастерская, багажник ----------

static func park_act(s, a) -> bool:
	var r = s.res
	var p = s.park
	match a.type:
		"rest":
			var fee = 10 if crew_has(s, "mechanic") else 0
			if p.rested or r.credits < fee: return false
			p.rested = true
			s.hour += 3
			gain(s, "focus", 5)
			gain(s, "credits", -fee)
			return true
		"charge":
			if r.credits < 15 or r.charge >= s.max.charge: return false
			gain(s, "credits", -15); gain(s, "charge", 4)
			return true
		"repair":
			if r.credits < 20 or r.hull >= s.max.hull: return false
			gain(s, "credits", -20); gain(s, "hull", 4)
			return true
		"talk":
			var ci = a.get("crew")
			if typeof(ci) != TYPE_INT or ci < 0 or ci >= s.crew.size(): return false
			var c = s.crew[ci]
			if p.talked.has(c.id): return false
			p.talked.append(c.id)
			c.trust = clampi(c.trust + 1, 0, 3)
			return true
		"leave":
			s.park = null
			s.screen = "map"
			return true
	return false

static func shop_act(s, a) -> bool:
	var r = s.res
	match a.type:
		"buy":
			var item = a.get("item")
			if typeof(item) != TYPE_STRING or not D.SHOP_ITEMS.has(item): return false
			var d = D.ITEMS[item]
			if r.credits < d.price: return false
			if not add_item(s, item): return false
			gain(s, "credits", -d.price)
			return true
		"upgrade":
			var id = a.get("id")
			if typeof(id) != TYPE_STRING or not D.UPGRADES.has(id): return false
			var u = D.UPGRADES[id]
			if s.up[id] or r.credits < u.price: return false
			s.up[id] = 1
			gain(s, "credits", -u.price)
			if id == "battery":
				s.max.charge += 4
				gain(s, "charge", 4)
			return true
		"sell":
			var it = _trunk_item(s, a.get("uid"))
			if it == null or not D.ITEMS[it.id].has("sell"): return false
			gain(s, "credits", D.ITEMS[it.id].sell)
			remove_item(s, it.uid)
			return true
		"leave":
			s.screen = "map"
			return true
	return false

static func use_item(s, id) -> void:
	var u = D.ITEMS[id].use
	for k in u: gain(s, k, u[k])

static func _trunk_item(s, uid):
	if uid == null: return null
	for t in s.trunk:
		if t.uid == uid: return t
	return null

static func trunk_act(s, a) -> bool:
	var it = _trunk_item(s, a.get("uid"))
	var slot = a.get("slot")
	var slot_ok = typeof(slot) == TYPE_INT and slot >= 0 and slot <= 2
	match a.type:
		"place":
			var r = 1 if a.get("r") else 0
			if it == null or not fits(s, it.id, a.get("x"), a.get("y"), r, it.uid): return false
			it.x = a.x; it.y = a.y; it.r = r
			return true
		"stow":
			if it == null or not slot_ok or not D.ITEMS[it.id].get("small", false) or s.glove[slot] != null: return false
			s.glove[slot] = it.id
			remove_item(s, it.uid)
			return true
		"unstow":
			if not slot_ok or s.glove[slot] == null: return false
			var id = s.glove[slot]
			var p = find_spot(s, id)
			if p == null: return false
			s.glove[slot] = null
			s.trunk.append({"uid": s.uid, "id": id, "x": p.x, "y": p.y, "r": p.r})
			s.uid += 1
			return true
		"use":
			if it == null or not D.ITEMS[it.id].has("use"): return false
			use_item(s, it.id)
			remove_item(s, it.uid)
			return true
		"useGlove":
			if not slot_ok or s.glove[slot] == null or not D.ITEMS[s.glove[slot]].has("use"): return false
			use_item(s, s.glove[slot])
			s.glove[slot] = null
			return true
		"drop":
			if it == null or D.ITEMS[it.id].get("lock", false): return false
			remove_item(s, it.uid)
			return true
	return false

# ---------- диспетчер ----------

static func act(s, a) -> bool:
	if typeof(a) != TYPE_DICTIONARY or typeof(a.get("type")) != TYPE_STRING: return false
	match s.screen:
		"title":
			if a.type == "start":
				s.screen = "map"
				return true
			return false
		"map":
			return travel(s, a.get("to"), a.get("mode")) if a.type == "travel" else trunk_act(s, a)
		"drive":
			return drive_act(s, a)
		"event":
			return choose_event(s, a.get("i")) if a.type == "choose" else false
		"battle":
			return battle_act(s, a)
		"park":
			return park_act(s, a) or trunk_act(s, a)
		"shop":
			return shop_act(s, a) or trunk_act(s, a)
		"result":
			if a.type != "continue": return false
			var then = s.result.then
			s.result = null
			if then == "end": s.screen = "end"
			elif then == "drive": s.screen = "drive"
			else: s.screen = "map"
			return true
	return false

static func clock_text(hour: int) -> String:
	return "%02d:00" % ((22 + hour) % 24)
