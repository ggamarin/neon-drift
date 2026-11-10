'use strict';
// Игровая модель: чистая логика без DOM и отрисовки.
// Единственная точка входа для изменений — act(s, action). Возвращает true,
// если действие применено, и false (без изменения состояния), если оно недопустимо.

const TRUNK_W = 6, TRUNK_H = 4, DAWN = 8, DEBT_LIMIT = 100, MAX_ENEMIES = 4;

function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }

function newRun(seed) {
  const s = {
    seed: seed >>> 0, rng: seed >>> 0, screen: 'title',
    res: { charge: 10, hull: 12, focus: 8, credits: 40, wanted: 0 },
    max: { charge: 12, hull: 12, focus: 10, wanted: 10 },
    hour: 0, crew: [], trunk: [], glove: ['patch', null, null], uid: 1,
    up: { armor: 0, guns: 0, deck: 0, battery: 0 },
    map: null, at: 0, drive: null, battle: null, event: null, result: null, park: null,
    usedEvents: [], usedHitch: [], over: null, fx: [],
    stats: { nodes: 0, battles: 0, wins: 0, escapes: 0, crits: 0, hits: 0, picks: 0 },
  };
  genMap(s);
  ['case', 'kit', 'cell', 'food'].forEach(id => addItem(s, id));
  return s;
}

// ---------- карта ----------

function genMap(s) {
  const nodes = [], cols = [];
  const add = (col, row, type) => {
    const n = { id: nodes.length, col, row, type, next: [], seen: false };
    nodes.push(n); (cols[col] = cols[col] || []).push(n); return n;
  };
  add(0, 1, 'start').seen = true;
  for (let c = 1; c <= 6; c++) {
    const rows = rngNext(s) < 0.5 ? [0, 1, 2] : rngNext(s) < 0.5 ? [0, 1] : [1, 2];
    rows.forEach(r => add(c, r, rngNext(s) < 0.7 ? 'road' : 'meet'));
  }
  add(7, 1, 'gate');
  [[1, 'hitch'], [3, 'park'], [4, 'shop'], [5, 'hitch']].forEach(([c, t]) => { rngPick(s, cols[c]).type = t; });
  [2, 6].forEach(c => { if (!cols[c].some(n => n.type === 'road')) cols[c][0].type = 'road'; });
  for (let c = 0; c < 7; c++) {
    const A = cols[c], B = cols[c + 1];
    A.forEach(a => B.forEach(b => {
      if (A.length === 1 || B.length === 1 || Math.abs(a.row - b.row) <= 1) a.next.push(b.id);
    }));
  }
  s.map = { nodes };
  s.at = 0;
}

function nodeVisible(s, n) {
  const cur = s.map.nodes[s.at];
  return n.seen || n.type === 'gate' || n.col <= cur.col + 1 + (s.up.deck ? 1 : 0);
}

// ---------- экипаж и инвентарь ----------

function crewHas(s, id) { return s.crew.some(c => c.id === id); }

function itemSize(it) { const d = ITEMS[it.id]; return it.r ? [d.h, d.w] : [d.w, d.h]; }

function fits(s, id, x, y, r, skipUid) {
  const d = ITEMS[id], w = r ? d.h : d.w, h = r ? d.w : d.h;
  if (!Number.isInteger(x) || !Number.isInteger(y)) return false;
  if (x < 0 || y < 0 || x + w > TRUNK_W || y + h > TRUNK_H) return false;
  for (const o of s.trunk) {
    if (o.uid === skipUid) continue;
    const [ow, oh] = itemSize(o);
    if (x < o.x + ow && o.x < x + w && y < o.y + oh && o.y < y + h) return false;
  }
  return true;
}

function findSpot(s, id) {
  for (let r = 0; r < 2; r++) for (let y = 0; y < TRUNK_H; y++) for (let x = 0; x < TRUNK_W; x++) {
    if (fits(s, id, x, y, r)) return { x, y, r };
  }
  return null;
}

// Кладёт предмет в багажник, а если места нет — мелочь в бардачок.
function addItem(s, id) {
  const p = findSpot(s, id);
  if (p) { s.trunk.push({ uid: s.uid++, id, x: p.x, y: p.y, r: p.r }); return true; }
  if (ITEMS[id].small) {
    const g = s.glove.indexOf(null);
    if (g >= 0) { s.glove[g] = id; return true; }
  }
  return false;
}

function removeItem(s, uid) { s.trunk = s.trunk.filter(t => t.uid !== uid); }

function dropCrew(s, id, lines, text) {
  s.crew = s.crew.filter(c => c.id !== id);
  if (id === 'surgeon') s.trunk = s.trunk.filter(t => t.id !== 'tools');
  lines.push(text || CREW[id].name + ' выходит из машины.');
}

// ---------- ресурсы ----------

function gain(s, k, n) {
  const r = s.res;
  if (k === 'wanted' && n > 0 && crewHas(s, 'android')) n *= 2;
  if (k === 'credits') r.credits += n;
  else r[k] = clamp(r[k] + n, 0, s.max[k]);
}

function snap(s) {
  const r = s.res;
  return { charge: r.charge, hull: r.hull, focus: r.focus, credits: r.credits, wanted: r.wanted, hour: s.hour };
}
function diff(a, s) {
  const b = snap(s), out = [];
  for (const k in a) if (b[k] !== a[k]) out.push({ k, n: b[k] - a[k] });
  return out;
}

function applyFx(s, fx, lines) {
  if (!fx) return;
  if (fx.res) for (const k in fx.res) gain(s, k, fx.res[k]);
  if (fx.hour) s.hour += fx.hour;
  [fx.item, fx.item2].forEach(id => {
    if (id) lines.push(addItem(s, id) ? 'Получено: ' + ITEMS[id].name + '.' : ITEMS[id].name + ' не влезает: багажник полон.');
  });
  if (fx.trust && s.crew.length) {
    s.crew.forEach(c => { c.trust = clamp(c.trust + fx.trust, 0, 3); });
    lines.push(fx.trust > 0 ? 'Экипаж одобряет: доверие +1.' : 'Экипажу это не по душе: доверие −1.');
    s.crew.filter(c => c.trust <= 0).forEach(c => dropCrew(s, c.id, lines, CREW[c.id].name + ' больше тебе не верит и выходит.'));
  }
  if (fx.special === 'contra' && crewHas(s, 'guard')) dropCrew(s, 'guard', lines, 'Гранит молча выходит: с контрабандой ему не по пути.');
}

function lose(s, text) { if (!s.over) s.over = { win: false, text }; }
function win(s, text) { if (!s.over) s.over = { win: true, text }; }

// Критические состояния: один ноль — дорогая проблема, два сразу — конец рейса.
function resolveCrit(s, lines) {
  if (s.over) return false;
  const r = s.res, z = [];
  if (r.charge <= 0) z.push('charge');
  if (r.hull <= 0) z.push('hull');
  if (r.focus <= 0) z.push('focus');
  if (z.length >= 2) {
    lines.push('Сразу два ресурса в нуле. Дальше ехать не на чем и некому.');
    lose(s, 'Машина и водитель сдали одновременно. Кейс достанется тем, кто найдёт вас первым.');
    return true;
  }
  if (z[0] === 'charge') {
    r.credits -= 40; s.hour += 2; r.charge = 5;
    lines.push('Батарея в нуле. Буксир до колонки: −40 кр, +2 ч.');
  } else if (z[0] === 'hull') {
    r.credits -= 60; r.hull = 6;
    const loose = s.trunk.filter(t => !ITEMS[t.id].lock);
    let lost = '';
    if (loose.length) { const t = rngPick(s, loose); removeItem(s, t.uid); lost = ' В суматохе пропало: ' + ITEMS[t.id].name + '.'; }
    lines.push('Машина разбита. Эвакуатор и латка: −60 кр.' + lost);
  } else if (z[0] === 'focus') {
    s.hour += 3; r.hull = Math.max(1, r.hull - 3); r.focus = 4;
    lines.push('Отключка за рулём. Очнулся в отбойнике: +3 ч, Корпус −3.');
  }
  if (z.length) s.stats.crits++;
  if (r.credits < -DEBT_LIMIT) {
    lines.push('Долг вырос выше ' + DEBT_LIMIT + ' кр.');
    lose(s, 'Ростовщик забрал машину за долги. Кейс уехал вместе с ней.');
    return true;
  }
  return z.length > 0;
}

// then — куда вернуться после экрана итога; посреди перегона это всегда дорога.
function finish(s, title, lines, before, then) {
  resolveCrit(s, lines);
  s.result = { title, lines, deltas: diff(before, s), then: s.over ? 'end' : s.drive ? 'drive' : then };
  s.screen = 'result';
}

// ---------- дорога ----------

// Шанс засады по дороге в узел. Интерфейс показывает его до выезда.
function ambushChance(s, n, mode) {
  if (n.type === 'gate' || n.type === 'start') return 0;
  if (n.type === 'road') return 1;
  return MODES[mode].ambush + (s.res.wanted >= 5 ? 0.25 : 0);
}

// Раскладка перегона: в каждом столбце хотя бы одна полоса свободна,
// после столбца с двумя препятствиями идёт пустой.
function genRoad(s, mode) {
  const objs = [];
  let rest = false;
  for (let x = 3; x < TRIP_LEN - 1; x++) {
    if (rest) { rest = false; continue; }
    const lanes = [0, 1, 2];
    const pull = () => lanes.splice(rngInt(s, lanes.length), 1)[0];
    if (rngNext(s) < 0.5) {
      const two = rngNext(s) < 0.3;
      for (let k = 0; k < (two ? 2 : 1); k++) {
        objs.push({ x, lane: pull(), k: mode !== 'quiet' && rngNext(s) < 0.25 ? 'cam' : 'debris' });
      }
      rest = two;
    }
    if (rngNext(s) < 0.2) objs.push({ x, lane: pull(), k: rngNext(s) < 0.3 ? 'cell' : 'chip' });
  }
  return objs;
}

function travel(s, to, mode) {
  const cur = s.map.nodes[s.at], M = MODES[mode];
  if (!M || !cur.next.includes(to)) return false;
  const before = snap(s), n = s.map.nodes[to], chance = ambushChance(s, n, mode);
  gain(s, 'charge', -M.charge);
  s.hour += M.hours;
  if (M.wanted) gain(s, 'wanted', M.wanted);
  const dawn = s.hour > DAWN;
  if (dawn) gain(s, 'focus', -2);
  s.at = to;
  const d = s.drive = { mode, dawn, len: TRIP_LEN, pos: 0, lane: 1, objs: genRoad(s, mode), ambushAt: -1, ambush: null };
  if (chance > 0 && rngNext(s) < chance) {
    const tier = n.col <= 2 ? 0 : n.col <= 4 ? 1 : 2;
    d.ambush = rngPick(s, GROUPS[n.type === 'road' ? tier : Math.max(0, tier - 1)]).slice();
    d.ambushAt = 6 + rngInt(s, 6);
  }
  s.screen = 'drive';
  const lines = [];
  if (dawn) lines.push('Рассвет. Город просыпается, голова тяжелеет: Фокус −2.');
  if (resolveCrit(s, lines)) {
    s.result = { title: 'В пути', lines, deltas: diff(before, s), then: s.over ? 'end' : 'drive' };
    s.screen = 'result';
  }
  return true;
}

// Дорога: steer перестраивает машину, tick проезжает один отрезок.
function driveAct(s, a) {
  const d = s.drive;
  if (a.type === 'steer') {
    if (a.dir !== -1 && a.dir !== 1) return false;
    const lane = d.lane + a.dir;
    if (lane < 0 || lane > 2) return false;
    d.lane = lane;
    return true;
  }
  if (a.type !== 'tick') return false;
  if (d.pos === d.ambushAt) { d.ambushAt = -1; startBattle(s, d.ambush, false); return true; }   // враги нагнали
  if (d.pos >= d.len) { s.drive = null; enterNode(s); return true; }                              // приехали
  const before = snap(s), lines = [];
  d.pos++;
  for (let i = d.objs.length - 1; i >= 0; i--) {
    const o = d.objs[i];
    if (o.x !== d.pos || o.lane !== d.lane) continue;
    const O = ROAD_OBJ[o.k];
    gain(s, O.res, O.n);
    s.stats[O.bad ? 'hits' : 'picks']++;
    s.fx.push({ k: 'road', kind: o.k });
    d.objs.splice(i, 1);
  }
  if (resolveCrit(s, lines)) {
    s.result = { title: 'В пути', lines, deltas: diff(before, s), then: s.over ? 'end' : 'drive' };
    s.screen = 'result';
  }
  return true;
}

function enterNode(s) {
  const n = s.map.nodes[s.at];
  n.seen = true;
  s.stats.nodes++;
  switch (n.type) {
    case 'gate': startBattle(s, ['boss', 'drone'], true); break;
    case 'meet': {
      let pool = EVENTS.filter(e => !s.usedEvents.includes(e.id));
      if (!pool.length) { s.usedEvents = []; pool = EVENTS; }
      const e = rngPick(s, pool);
      s.usedEvents.push(e.id);
      s.event = { id: e.id };
      s.screen = 'event';
      break;
    }
    case 'hitch': {
      const pool = Object.keys(CREW).filter(id => !crewHas(s, id) && !s.usedHitch.includes(id));
      const who = rngPick(s, pool);
      s.usedHitch.push(who);
      s.event = { id: 'hitch', who };
      s.screen = 'event';
      break;
    }
    case 'park': s.park = { rested: false, talked: [] }; s.screen = 'park'; break;
    case 'shop': s.screen = 'shop'; break;
    default: s.screen = 'map';
  }
}

// ---------- события ----------

function needWhy(s, need) {
  if (!need) return '';
  if (need.crew && !crewHas(s, need.crew)) return 'Нужен попутчик: ' + CREW[need.crew].name;
  if (need.credits && s.res.credits < need.credits) return 'Нужно ' + need.credits + ' кр';
  if (need.space && !findSpot(s, need.space)) return 'Нет места в багажнике';
  return '';
}

// Что показывать на экране события: заголовок, текст и варианты с доступностью.
function eventView(s) {
  const ev = s.event;
  if (!ev) return null;
  if (ev.id === 'hitch') {
    const C = CREW[ev.who], full = s.crew.length >= 3;
    const noSpace = ev.who === 'surgeon' && !findSpot(s, 'tools');
    return {
      title: 'Попутчик: ' + C.name,
      text: HITCH_TEXT[ev.who] + ' ' + C.role + '. Навык «' + C.skill + '»: ' + C.desc + ' Минус: ' + C.flaw,
      options: [
        { label: 'Подвезти' + (C.fare ? ' (+' + C.fare + ' кр за проезд)' : ''), ok: !full && !noSpace,
          why: full ? 'В салоне нет мест' : noSpace ? 'Нет 4 клеток под багаж' : '' },
        { label: 'Проехать мимо', ok: true, why: '' },
      ],
    };
  }
  const E = EVENTS.find(e => e.id === ev.id);
  return {
    title: E.title, text: E.text,
    options: E.options.map(o => { const why = needWhy(s, o.need); return { label: o.label, ok: !why, why }; }),
  };
}

function chooseEvent(s, i) {
  const v = eventView(s);
  if (!v || !v.options[i] || !v.options[i].ok) return false;
  const before = snap(s), lines = [], ev = s.event;
  if (ev.id === 'hitch') {
    if (i === 0) {
      const C = CREW[ev.who];
      s.crew.push({ id: ev.who, trust: 2, cd: 0, used: false });
      if (C.fare) gain(s, 'credits', C.fare);
      if (ev.who === 'surgeon') addItem(s, 'tools');
      lines.push(C.name + ' садится в машину. В бою доступен навык «' + C.skill + '».');
    } else lines.push('Фигура у обочины остаётся в зеркале.');
  } else {
    const o = EVENTS.find(e => e.id === ev.id).options[i];
    lines.push(o.text);
    applyFx(s, o.fx, lines);
    if (o.risk && rngNext(s) < o.risk.p) { lines.push(o.risk.text); applyFx(s, o.risk.fx, lines); }
  }
  s.event = null;
  finish(s, v.title, lines, before, 'map');
  return true;
}

// ---------- бой ----------

function living(b) { return b.enemies.filter(e => e.hp > 0); }

function mkEnemy(s, type, dist) {
  const E = ENEMIES[type];
  return { type, hp: E.hp, max: E.hp, dist: dist == null ? E.start : dist, stun: 0, pi: rngInt(s, E.pattern.length), called: false };
}

function blog(s, text) { const l = s.battle.log; l.push(text); if (l.length > 6) l.shift(); }

function startBattle(s, types, boss) {
  const b = { turn: 1, ap: 3, shield: 0, escape: 0, heat: 0, boss: !!boss, enemies: [],
              usedItem: false, hacked: false, noisy: false, mark: -1, log: [], before: snap(s) };
  s.battle = b;
  types.forEach(t => b.enemies.push(mkEnemy(s, t)));
  if (boss) b.enemies[0].pi = 0;
  if (!boss && s.res.wanted >= 5) {
    b.enemies.push(mkEnemy(s, 'patrol', 2));
    b.log.push('Розыск высокий: на хвосте лишний патруль.');
  }
  s.crew.forEach(c => { c.cd = 0; c.used = false; });
  s.stats.battles++;
  s.screen = 'battle';
}

// Намерение врага — чистая функция от его состояния, поэтому интерфейс
// показывает его «вживую»: оттеснили врага — удар сменился сближением.
function intentOf(s, e) {
  const E = ENEMIES[e.type];
  if (e.stun > 0) return { k: 'stun' };
  let mv = E.pattern[e.pi % E.pattern.length];
  if (mv.k === 'call' && e.called) mv = { k: 'hit', res: 'hull', n: 2 };
  if (mv.k === 'hit' && e.dist > E.reach) return { k: 'approach' };
  if (E.swarm) return { k: 'hit', res: s.res.charge > 0 ? 'charge' : 'hull', n: Math.ceil(e.hp / 2) };
  return mv;
}

// План на следующий ход (его видит андроид).
function nextIntent(s, e) {
  const cur = intentOf(s, e);
  const sim = { type: e.type, hp: e.hp, dist: e.dist, stun: 0, pi: e.pi, called: e.called };
  if (cur.k === 'approach') sim.dist--;
  else if (cur.k !== 'stun') { sim.pi++; if (cur.k === 'call') sim.called = true; }
  return intentOf(s, sim);
}

const TARGETED = { gun: 1, ram: 1, hack: 1, pull: 1, push: 1 };
function needsTarget(s, a) {
  if (TARGETED[a.type]) return true;
  if (a.type === 'skill') { const c = s.crew[a.crew]; return !!(c && CREW[c.id].target); }
  return false;
}

// Причина, по которой действие недоступно, или '' если всё в порядке.
// Без a.target проверяет, есть ли хоть одна подходящая цель.
function battleWhy(s, a) {
  const b = s.battle, r = s.res;
  if (!b) return 'Нет боя';
  const tgt = f => {
    if (a.target == null) return b.enemies.some(e => e.hp > 0 && !f(e)) ? '' : 'Нет подходящей цели';
    const e = b.enemies[a.target];
    if (!e || e.hp <= 0) return 'Нет цели';
    return f(e);
  };
  const jam = b.enemies.some(e => e.hp > 0 && ENEMIES[e.type].jam);
  switch (a.type) {
    case 'endTurn': return '';
    case 'gun': return b.ap < 1 ? 'Нужно 1 ОД' : tgt(e => e.dist <= 1 ? '' : 'Стволы достают только до средней');
    case 'ram': return b.ap < 2 ? 'Нужно 2 ОД' : r.hull <= 1 ? 'Корпус на пределе' : tgt(e => e.dist === 0 ? '' : 'Таран только вплотную');
    case 'hack': return b.ap < 1 ? 'Нужно 1 ОД' : jam ? 'Глушилка блокирует взлом' : r.focus < 2 ? 'Нужно 2 Фокуса' : tgt(() => '');
    case 'pull': case 'push': {
      if (b.ap < 1) return 'Нужно 1 ОД';
      const d = a.type === 'pull' ? -1 : 1;
      return tgt(e => {
        const cost = ENEMIES[e.type].heavy ? 2 : 1;
        if (r.charge < cost) return 'Нужно ' + cost + ' Заряда';
        const nd = e.dist + d;
        return nd < 0 ? 'Уже вплотную' : nd > 2 ? 'Дальше некуда' : '';
      });
    }
    case 'skill': {
      const c = s.crew[a.crew];
      if (!c) return 'Нет попутчика';
      const C = CREW[c.id];
      if (c.id === 'musician') { if (c.used) return 'Уже сыграно в этом бою'; }
      else if (c.cd > 0) return 'Откат: ещё ' + c.cd + ' х.';
      if (b.ap < C.ap) return 'Нужно ' + C.ap + ' ОД';
      if (c.id === 'hacker') return jam ? 'Глушилка блокирует взлом' : tgt(e => ENEMIES[e.type].tech ? '' : 'Только по технике');
      if (c.id === 'android') return tgt(() => '');
      return '';
    }
    case 'item': {
      const id = s.glove[a.slot];
      if (!id) return 'Пусто';
      if (!ITEMS[id].battle) return 'В бою бесполезно';
      if (b.usedItem) return 'Один предмет за ход';
      return '';
    }
    case 'escape':
      if (b.boss) return 'От КПП не уйти: только прорыв';
      if (b.ap < 1) return 'Нужно хотя бы 1 ОД';
      return '';
  }
  return 'Неизвестное действие';
}

function battleTargets(s, a) {
  const out = [];
  s.battle.enemies.forEach((e, i) => { if (!battleWhy(s, Object.assign({}, a, { target: i }))) out.push(i); });
  return out;
}

function hit(s, i, n, kind) {
  const b = s.battle, e = b.enemies[i], E = ENEMIES[e.type];
  if (b.mark === i) n *= 2;
  if (E.swarm && kind !== 'ram' && kind !== 'aoe') n = Math.min(n, 1);
  n = Math.min(n, e.hp);
  e.hp -= n;
  s.fx.push({ k: 'dmg', i, n });
  blog(s, E.name + ': −' + n + (e.hp === 0 ? ', выведены из строя' : ''));
}

function battleAct(s, a) {
  const b = s.battle, r = s.res;
  if (battleWhy(s, a)) return false;
  const nt = needsTarget(s, a);
  if (nt && a.target == null) return false;
  const e = nt ? b.enemies[a.target] : null, E = e && ENEMIES[e.type];
  switch (a.type) {
    case 'endTurn': enemyPhase(s); return true;
    case 'gun': b.ap -= 1; b.noisy = true; hit(s, a.target, 2 + s.up.guns, 'gun'); break;
    case 'ram': b.ap -= 2; b.noisy = true; gain(s, 'hull', -1); hit(s, a.target, 5, 'ram'); break;
    case 'hack':
      b.ap -= 1; gain(s, 'focus', -1);
      if (!b.hacked) { b.hacked = true; gain(s, 'wanted', 1); }
      hit(s, a.target, (2 + s.up.deck) * (E.tech ? 2 : 1), 'hack');
      break;
    case 'pull': case 'push':
      b.ap -= 1; gain(s, 'charge', -(E.heavy ? 2 : 1));
      e.dist += a.type === 'pull' ? -1 : 1;
      blog(s, E.name + (a.type === 'pull' ? ': подтянули ближе' : ': оттеснили дальше'));
      break;
    case 'skill': {
      const c = s.crew[a.crew], C = CREW[c.id];
      b.ap -= C.ap;
      c.cd = Math.max(1, C.cd - (c.trust >= 3 ? 1 : 0));
      blog(s, C.name + ': «' + C.skill + '»');
      if (c.id === 'hacker') { e.stun = 1; if (!b.hacked) { b.hacked = true; gain(s, 'wanted', 1); } }
      else if (c.id === 'surgeon') gain(s, 'focus', 3);
      else if (c.id === 'guard') b.shield += 5;
      else if (c.id === 'mechanic') gain(s, 'hull', 3);
      else if (c.id === 'musician') { c.used = true; c.cd = 0; b.ap += 1; }
      else if (c.id === 'android') b.mark = a.target;
      break;
    }
    case 'item': {
      const id = s.glove[a.slot], f = ITEMS[id].battle;
      s.glove[a.slot] = null; b.usedItem = true;
      blog(s, 'Из бардачка: ' + ITEMS[id].name);
      ['charge', 'hull', 'focus'].forEach(k => { if (f[k]) gain(s, k, f[k]); });
      if (f.ap) b.ap += f.ap;
      if (f.shield) b.shield += f.shield;
      if (f.emp) b.enemies.forEach((en, i) => {
        if (en.hp <= 0) return;
        if (ENEMIES[en.type].tech) en.stun = 1;
        hit(s, i, f.emp, 'aoe');
      });
      break;
    }
    case 'escape': {
      const k = r.charge >= 2 ? 'charge' : 'hull';
      gain(s, k, -2);
      const close = living(b).filter(en => en.dist === 0).length;
      b.escape = Math.min(100, b.escape + Math.max(5, 20 * b.ap + 10 - 10 * close));
      b.ap = 0;
      blog(s, 'Отрыв: ' + b.escape + ' %' + (k === 'hull' ? ' (на износ: Корпус −2)' : ''));
      if (r.hull <= 0) { endBattle(s, 'defeat'); return true; }
      if (b.escape >= 100) { endBattle(s, 'escape'); return true; }
      break;
    }
  }
  if (s.battle && living(b).length === 0) endBattle(s, 'win');
  return true;
}

function enemyPhase(s) {
  const b = s.battle, r = s.res, count = b.enemies.length;
  for (let i = 0; i < count; i++) {
    const e = b.enemies[i];
    if (e.hp <= 0) continue;
    const E = ENEMIES[e.type], it = intentOf(s, e);
    if (it.k === 'stun') { e.stun--; blog(s, E.name + ': сбой, ход пропущен'); continue; }
    if (it.k === 'approach') { e.dist--; blog(s, E.name + ' сближается'); continue; }
    e.pi = (e.pi + 1) % E.pattern.length;
    if (it.k === 'aim') { blog(s, E.name + ' наводит орудие'); continue; }
    if (it.k === 'call') {
      e.called = true; gain(s, 'wanted', 1);
      if (living(b).length < MAX_ENEMIES) {
        const n = mkEnemy(s, 'patrol', 2); n.called = true; b.enemies.push(n);
        blog(s, E.name + ' вызывает подмогу: розыск +1');
      } else blog(s, E.name + ' сообщает о погоне: розыск +1');
      continue;
    }
    let n = it.n, ab = 0;
    if (it.res === 'hull') {
      n = Math.max(1, n - s.up.armor);
      ab = Math.min(b.shield, n); b.shield -= ab; n -= ab;
    }
    if (n > 0) gain(s, it.res, -n);
    s.fx.push({ k: 'hurt', i, res: it.res, n });
    blog(s, E.name + ': ' + RES_NAME[it.res] + ' −' + n + (ab ? ' (щит снял ' + ab + ')' : ''));
    if (r.hull <= 0 || r.focus <= 0 || r.credits < -DEBT_LIMIT) { endBattle(s, 'defeat'); return; }
  }
  b.turn++; b.ap = 3; b.shield = 0; b.mark = -1; b.usedItem = false;
  s.crew.forEach(c => { if (c.cd > 0) c.cd--; });
  if (!b.boss && ++b.heat >= 6) {
    b.heat = 0; gain(s, 'wanted', 1);
    if (living(b).length < MAX_ENEMIES) { const n = mkEnemy(s, 'patrol', 2); n.called = true; b.enemies.push(n); }
    blog(s, 'Бой затянулся: шум привлёк патруль, розыск +1');
  }
}

function endBattle(s, outcome) {
  const b = s.battle, lines = [];
  let title;
  if (outcome === 'win') {
    title = 'Победа';
    const bounty = b.enemies.reduce((a, e) => a + ENEMIES[e.type].bounty, 0);
    gain(s, 'credits', bounty);
    lines.push('Дорога свободна. С обломков снято ' + bounty + ' кр.');
    if (b.noisy) { gain(s, 'wanted', 1); lines.push('Стрельбу слышал весь квартал: розыск вырос.'); }
    if (rngNext(s) < 0.6) {
      const id = rngPick(s, LOOT);
      lines.push(addItem(s, id) ? 'Трофей: ' + ITEMS[id].name + '.' : 'Трофей «' + ITEMS[id].name + '» не влез в багажник.');
    }
    s.stats.wins++;
    if (b.boss) win(s, 'Броневик дымит на обочине, шлагбаум поднят. Кейс едет дальше, в Развязку.');
  } else if (outcome === 'escape') {
    title = 'Оторвались';
    lines.push('Погоня отстала в переулках. Добычи нет, зато все целы.');
    s.stats.escapes++;
  } else {
    title = 'Бой проигран';
    if (b.boss) {
      lines.push('Броневик прижал машину к отбойнику.');
      lose(s, 'КПП не пройден. Кейс конфискован, рейс окончен.');
    } else lines.push('Вас выбили с трассы.');
  }
  s.battle = null;
  finish(s, title, lines, b.before, 'map');
}

// ---------- стоянка, мастерская, багажник ----------

function parkAct(s, a) {
  const r = s.res, p = s.park;
  switch (a.type) {
    case 'rest': {
      const fee = crewHas(s, 'mechanic') ? 10 : 0;
      if (p.rested || r.credits < fee) return false;
      p.rested = true; s.hour += 3; gain(s, 'focus', 5); gain(s, 'credits', -fee);
      return true;
    }
    case 'charge':
      if (r.credits < 15 || r.charge >= s.max.charge) return false;
      gain(s, 'credits', -15); gain(s, 'charge', 4); return true;
    case 'repair':
      if (r.credits < 20 || r.hull >= s.max.hull) return false;
      gain(s, 'credits', -20); gain(s, 'hull', 4); return true;
    case 'talk': {
      const c = s.crew[a.crew];
      if (!c || p.talked.includes(c.id)) return false;
      p.talked.push(c.id); c.trust = clamp(c.trust + 1, 0, 3); return true;
    }
    case 'leave': s.park = null; s.screen = 'map'; return true;
  }
  return false;
}

function shopAct(s, a) {
  const r = s.res;
  switch (a.type) {
    case 'buy': {
      const d = ITEMS[a.item];
      if (!d || !SHOP_ITEMS.includes(a.item) || r.credits < d.price) return false;
      if (!addItem(s, a.item)) return false;
      gain(s, 'credits', -d.price); return true;
    }
    case 'upgrade': {
      const u = UPGRADES[a.id];
      if (!u || s.up[a.id] || r.credits < u.price) return false;
      s.up[a.id] = 1; gain(s, 'credits', -u.price);
      if (a.id === 'battery') { s.max.charge += 4; gain(s, 'charge', 4); }
      return true;
    }
    case 'sell': {
      const it = s.trunk.find(t => t.uid === a.uid);
      if (!it || !ITEMS[it.id].sell) return false;
      gain(s, 'credits', ITEMS[it.id].sell); removeItem(s, it.uid); return true;
    }
    case 'leave': s.screen = 'map'; return true;
  }
  return false;
}

function useItem(s, id) { const u = ITEMS[id].use; for (const k in u) gain(s, k, u[k]); }

function trunkAct(s, a) {
  const it = a.uid != null ? s.trunk.find(t => t.uid === a.uid) : null;
  const slotOk = a.slot === 0 || a.slot === 1 || a.slot === 2;
  switch (a.type) {
    case 'place': {
      const r = a.r ? 1 : 0;
      if (!it || !fits(s, it.id, a.x, a.y, r, it.uid)) return false;
      it.x = a.x; it.y = a.y; it.r = r; return true;
    }
    case 'stow':
      if (!it || !slotOk || !ITEMS[it.id].small || s.glove[a.slot] !== null) return false;
      s.glove[a.slot] = it.id; removeItem(s, it.uid); return true;
    case 'unstow': {
      if (!slotOk || !s.glove[a.slot]) return false;
      const id = s.glove[a.slot], p = findSpot(s, id);
      if (!p) return false;
      s.glove[a.slot] = null; s.trunk.push({ uid: s.uid++, id, x: p.x, y: p.y, r: p.r }); return true;
    }
    case 'use':
      if (!it || !ITEMS[it.id].use) return false;
      useItem(s, it.id); removeItem(s, it.uid); return true;
    case 'useGlove': {
      if (!slotOk || !s.glove[a.slot] || !ITEMS[s.glove[a.slot]].use) return false;
      useItem(s, s.glove[a.slot]); s.glove[a.slot] = null; return true;
    }
    case 'drop':
      if (!it || ITEMS[it.id].lock) return false;
      removeItem(s, it.uid); return true;
  }
  return false;
}

// ---------- диспетчер ----------

function act(s, a) {
  if (!a || typeof a.type !== 'string') return false;
  switch (s.screen) {
    case 'title': if (a.type === 'start') { s.screen = 'map'; return true; } return false;
    case 'map': return a.type === 'travel' ? travel(s, a.to, a.mode) : trunkAct(s, a);
    case 'drive': return driveAct(s, a);
    case 'event': return a.type === 'choose' ? chooseEvent(s, a.i) : false;
    case 'battle': return battleAct(s, a);
    case 'park': return parkAct(s, a) || trunkAct(s, a);
    case 'shop': return shopAct(s, a) || trunkAct(s, a);
    case 'result': {
      if (a.type !== 'continue') return false;
      const then = s.result.then;
      s.result = null;
      if (then === 'end') s.screen = 'end';
      else if (then === 'drive') s.screen = 'drive';
      else s.screen = 'map';
      return true;
    }
  }
  return false;
}

function clockText(hour) {
  const h = (22 + hour) % 24;
  return (h < 10 ? '0' : '') + h + ':00';
}
