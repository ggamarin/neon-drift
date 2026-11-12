# Проверка точности порта логики. Запуск из папки godot:
#   godot --headless --script res://tools/replay.gd
# Эталонные заезды записаны JS-моделью (node tools/gen-godot.js): сид, лог действий,
# след состояния после каждого шага и финальное состояние. GDScript-модель обязана
# принять каждое действие и прийти в то же состояние — шаг в шаг.
extends SceneTree

const M = preload("res://scripts/model.gd")

func _init() -> void:
	var runs = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays.json"))
	var bad = 0
	var steps = 0
	for run in runs:
		var s = M.new_run(int(run.seed))
		var err = ""
		for i in range(run.actions.size()):
			var a = ints(run.actions[i])
			if not M.act(s, a):
				err = "шаг %d: действие отклонено %s (экран %s)" % [i, JSON.stringify(a), s.screen]
				break
			var mine = [s.rng, s.screen, s.res.charge, s.res.hull, s.res.focus, s.res.credits, s.res.wanted, s.hour]
			if not same(run.trace[i], mine):
				err = "шаг %d после %s: ждали %s, получили %s" % [i, JSON.stringify(a), JSON.stringify(run.trace[i]), JSON.stringify(mine)]
				break
			steps += 1
		if err == "":
			s.fx = []
			var where = diff_path(run.final, s, "state")
			if where != "": err = "финальное состояние расходится в " + where
		if err != "":
			bad += 1
			print("сид %d: %s" % [int(run.seed), err])
	print("заездов: %d, совпало шагов: %d, расхождений: %d" % [runs.size(), steps, bad])
	quit(1 if bad else 0)

# JSON отдаёт все числа как float; модель ждёт целые.
func ints(a: Dictionary) -> Dictionary:
	var out = {}
	for k in a:
		var v = a[k]
		out[k] = int(v) if typeof(v) == TYPE_FLOAT and v == floor(v) else v
	return out

func same(a, b) -> bool:
	return diff_path(a, b, "") == ""

# Путь к первому различию или "" если структуры равны (числа сравниваются по значению).
func diff_path(a, b, path: String) -> String:
	var ta = typeof(a)
	var tb = typeof(b)
	var num = [TYPE_INT, TYPE_FLOAT]
	if num.has(ta) and num.has(tb):
		return "" if float(a) == float(b) else "%s (%s ≠ %s)" % [path, str(a), str(b)]
	if ta != tb: return "%s (тип %s ≠ %s: %s / %s)" % [path, type_string(ta), type_string(tb), str(a), str(b)]
	if ta == TYPE_DICTIONARY:
		for k in a:
			if not b.has(k): return path + "." + str(k) + " (нет ключа в Godot)"
			var d = diff_path(a[k], b[k], path + "." + str(k))
			if d != "": return d
		for k in b:
			if not a.has(k): return path + "." + str(k) + " (лишний ключ в Godot)"
		return ""
	if ta == TYPE_ARRAY:
		if a.size() != b.size(): return "%s (длина %d ≠ %d)" % [path, a.size(), b.size()]
		for i in range(a.size()):
			var d = diff_path(a[i], b[i], "%s[%d]" % [path, i])
			if d != "": return d
		return ""
	return "" if a == b else "%s (%s ≠ %s)" % [path, str(a), str(b)]
