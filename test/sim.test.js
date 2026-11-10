// Запуск: node --test test/
const test = require('node:test');
const assert = require('node:assert/strict');
const { G, mulberry, randomPolicy, greedyPolicy, playRun } = require('./bots');

const SCREENS = ['title', 'map', 'drive', 'event', 'battle', 'park', 'shop', 'result', 'end'];
const strip = s => { const c = JSON.parse(JSON.stringify(s)); c.fx = []; return JSON.stringify(c); };

// Инварианты, которые обязаны держаться после любого действия.
function checkInvariants(s) {
  const r = s.res;
  assert.ok(SCREENS.includes(s.screen), 'неизвестный экран ' + s.screen);
  for (const k of ['charge', 'hull', 'focus', 'wanted']) {
    assert.ok(Number.isInteger(r[k]) && r[k] >= 0 && r[k] <= s.max[k], `${k}=${r[k]} вне [0, ${s.max[k]}]`);
  }
  assert.ok(Number.isInteger(r.credits), 'кредиты не целые');
  assert.ok(Number.isInteger(s.hour) && s.hour >= 0, 'время');
  assert.ok(s.crew.length <= 3, 'в салоне больше трёх');
  assert.equal(new Set(s.crew.map(c => c.id)).size, s.crew.length, 'дубли в экипаже');
  s.crew.forEach(c => assert.ok(c.trust >= 1 && c.trust <= 3, 'доверие вне 1..3'));
  const cells = new Set();
  for (const t of s.trunk) {
    const [w, h] = G.itemSize(t);
    for (let y = t.y; y < t.y + h; y++) for (let x = t.x; x < t.x + w; x++) {
      assert.ok(x >= 0 && y >= 0 && x < G.TRUNK_W && y < G.TRUNK_H, 'предмет за пределами багажника');
      assert.ok(!cells.has(x + ',' + y), 'предметы пересекаются в ' + x + ',' + y);
      cells.add(x + ',' + y);
    }
  }
  assert.equal(s.trunk.filter(t => t.id === 'case').length, s.over && !s.over.win ? s.trunk.filter(t => t.id === 'case').length : 1, 'кейс потерян');
  s.glove.forEach(id => assert.ok(id === null || G.ITEMS[id].small, 'в бардачке крупный предмет'));
  assert.equal(s.trunk.some(t => t.id === 'tools'), s.crew.some(c => c.id === 'surgeon'), 'инструменты без хирурга или наоборот');
  if (s.screen === 'battle') {
    assert.ok(s.battle, 'экран боя без боя');
    assert.ok(G.living(s.battle).length > 0, 'бой без живых врагов');
    assert.ok(G.living(s.battle).length <= 4, 'слишком много врагов');
    s.battle.enemies.forEach(e => {
      assert.ok(e.dist >= 0 && e.dist <= 2, 'дистанция вне 0..2');
      assert.ok(e.hp >= 0 && e.hp <= e.max, 'здоровье врага');
    });
    assert.ok(s.battle.ap >= 0, 'ОД ниже нуля');
  } else assert.equal(s.battle, null, 'бой остался после выхода с экрана');
  if (s.screen === 'drive') {
    assert.ok(s.drive, 'экран дороги без перегона');
    assert.ok(s.drive.lane >= 0 && s.drive.lane <= 2 && s.drive.pos >= 0 && s.drive.pos <= s.drive.len, 'машина вне дороги');
  }
  if (s.screen === 'map' || s.screen === 'park' || s.screen === 'shop' || s.screen === 'event') assert.equal(s.drive, null, 'перегон не закрыт по прибытии');
  if (s.screen === 'event') assert.ok(G.eventView(s).options.some(o => o.ok), 'событие без доступных вариантов');
  if (s.screen === 'end') assert.ok(s.over, 'финал без результата');
}

test('заезд воспроизводится по сиду и логу действий', () => {
  for (const seed of [1, 42, 20261110]) {
    const a = playRun(seed, randomPolicy(mulberry(seed + 7)));
    const s2 = G.newRun(seed);
    a.log.forEach(act => assert.equal(G.act(s2, act), true, 'действие из лога не применилось'));
    assert.equal(strip(s2), strip(a.s));
  }
});

test('разные сиды дают разные карты', () => {
  const maps = new Set([1, 2, 3, 4, 5, 6, 7, 8].map(seed => JSON.stringify(G.newRun(seed).map.nodes.map(n => n.type + n.row))));
  assert.ok(maps.size >= 6);
});

test('случайный бот: 400 заездов без падений, зависаний и нарушений инвариантов', () => {
  for (let seed = 1; seed <= 400; seed++) {
    const run = playRun(seed, randomPolicy(mulberry(seed * 31)), { onStep: checkInvariants });
    assert.ok(run.finished, 'заезд не закончился, сид ' + seed + ', экран ' + run.s.screen);
  }
});

test('недопустимое действие не меняет состояние', () => {
  const junk = [
    null, {}, { type: 'travel', to: 99, mode: 'fast' }, { type: 'travel', to: 1, mode: 'warp' }, { type: 'arrive' },
    { type: 'choose', i: 7 }, { type: 'gun', target: 9 }, { type: 'gun' }, { type: 'skill', crew: 5 }, { type: 'item', slot: 2 },
    { type: 'buy', item: 'case' }, { type: 'upgrade', id: 'wings' }, { type: 'sell', uid: 1 }, { type: 'drop', uid: 1 },
    { type: 'place', uid: 1, x: 5, y: 3, r: 0 }, { type: 'place', uid: 2, x: 0.5, y: 0, r: 0 }, { type: 'stow', uid: 2, slot: 5 },
    { type: 'talk', crew: 3 }, { type: 'continue' }, { type: 'start' }, { type: 'rest' },
  ];
  const rand = mulberry(99);
  for (let seed = 1; seed <= 40; seed++) {
    playRun(seed, randomPolicy(mulberry(seed)), {
      onStep: s => {
        const a = junk[Math.floor(rand() * junk.length)], before = strip(s), rng = s.rng;
        if (!G.act(s, a)) { assert.equal(strip(s), before, 'состояние изменилось: ' + JSON.stringify(a)); assert.equal(s.rng, rng); }
      },
    });
  }
});

test('карта: от старта до КПП 7 переходов, все узлы достижимы', () => {
  for (let seed = 1; seed <= 100; seed++) {
    const nodes = G.newRun(seed).map.nodes, reach = new Set([0]);
    nodes.forEach(n => { if (reach.has(n.id)) n.next.forEach(id => { reach.add(id); assert.equal(nodes[id].col, n.col + 1); }); });
    assert.equal(reach.size, nodes.length, 'недостижимый узел, сид ' + seed);
    assert.ok(nodes.filter(n => n.type !== 'gate').every(n => n.next.length > 0), 'тупик');
    for (const t of ['park', 'shop', 'gate']) assert.ok(nodes.some(n => n.type === t), 'нет узла ' + t);
  }
});

test('дорога: в каждом столбце есть свободная полоса, после двойного препятствия пусто', () => {
  for (let seed = 1; seed <= 300; seed++) {
    const objs = G.genRoad({ rng: seed }, seed % 3 ? 'fast' : 'quiet');
    const bad = x => objs.filter(o => o.x === x && G.ROAD_OBJ[o.k].bad).length;
    for (let x = 0; x <= G.TRIP_LEN; x++) {
      assert.ok(bad(x) <= 2, 'все три полосы заняты');
      assert.ok(new Set(objs.filter(o => o.x === x).map(o => o.lane)).size === objs.filter(o => o.x === x).length, 'два объекта в одной клетке');
      if (bad(x) === 2) assert.equal(objs.filter(o => o.x === x + 1).length, 0, 'нет передышки после двойного препятствия');
    }
    assert.ok(objs.every(o => o.x >= 3 && o.x < G.TRIP_LEN), 'объект вне перегона');
    if (seed % 3 === 0) assert.ok(objs.every(o => o.k !== 'cam'), 'в тихом режиме сканеров нет');
  }
});

test('дорога: перестроение, наезд на препятствие и подбор', () => {
  const s = G.newRun(11);
  G.act(s, { type: 'start' });
  G.act(s, { type: 'travel', to: s.map.nodes[0].next[0], mode: 'fast' });
  const d = s.drive;
  d.ambushAt = -1;
  d.objs = [{ x: 1, lane: 1, k: 'debris' }, { x: 2, lane: 0, k: 'cell' }, { x: 3, lane: 0, k: 'cam' }];
  const r = { ...s.res };
  assert.equal(G.act(s, { type: 'steer', dir: 2 }), false);
  G.act(s, { type: 'tick' });
  assert.equal(s.res.hull, r.hull - 1, 'обломки бьют по корпусу');
  assert.equal(G.act(s, { type: 'steer', dir: -1 }), true);
  assert.equal(G.act(s, { type: 'steer', dir: -1 }), false, 'выше верхней полосы не уехать');
  G.act(s, { type: 'tick' });
  assert.equal(s.res.charge, r.charge + 1, 'батарея подобрана');
  G.act(s, { type: 'steer', dir: 1 });
  G.act(s, { type: 'tick' });
  assert.equal(s.res.wanted, r.wanted, 'сканер на соседней полосе не срабатывает');
  assert.equal(d.objs.length, 1, 'объезженное остаётся на дороге, задетое и подобранное исчезает');
});

test('дорога: бой начинается посреди перегона и после него поездка продолжается', () => {
  const s = G.newRun(12);
  G.act(s, { type: 'start' });
  G.act(s, { type: 'travel', to: s.map.nodes[0].next[0], mode: 'eco' });
  const d = s.drive;
  d.objs = []; d.ambush = ['drone']; d.ambushAt = 4;
  for (let i = 0; i < 4; i++) G.act(s, { type: 'tick' });
  assert.equal(s.screen, 'drive');
  G.act(s, { type: 'tick' });
  assert.equal(s.screen, 'battle', 'на четвёртом отрезке враги нагоняют');
  assert.equal(d.pos, 4, 'бой не съедает отрезок пути');
  G.act(s, { type: 'hack', target: 0 });
  assert.equal(s.screen, 'result');
  G.act(s, { type: 'continue' });
  assert.equal(s.screen, 'drive', 'после боя — снова дорога');
  for (let i = 0; i < G.TRIP_LEN - 4 + 1; i++) G.act(s, { type: 'tick' });
  assert.notEqual(s.screen, 'drive', 'перегон закончился прибытием');
  assert.equal(s.drive, null);
});

function battleState(types, patch) {
  const s = G.newRun(5);
  s.screen = 'map';
  G.startBattle(s, types, false);
  Object.assign(s.res, patch || {});
  return s;
}

test('бой: оттеснённый враг вместо удара сближается', () => {
  const s = battleState(['biker']);
  const e = s.battle.enemies[0];
  e.dist = 0; e.pi = 0;
  assert.deepEqual(G.intentOf(s, e), { k: 'hit', res: 'hull', n: 4 });
  assert.equal(G.act(s, { type: 'push', target: 0 }), true);
  assert.equal(G.intentOf(s, e).k, 'approach');
  const hull = s.res.hull;
  G.act(s, { type: 'endTurn' });
  assert.equal(s.res.hull, hull, 'удар не должен был пройти');
  assert.equal(e.dist, 0);
});

test('бой: дистанция ограничивает оружие', () => {
  const s = battleState(['drone']);
  assert.equal(s.battle.enemies[0].dist, 2);
  assert.ok(G.battleWhy(s, { type: 'gun', target: 0 }));
  assert.ok(G.battleWhy(s, { type: 'ram', target: 0 }));
  assert.equal(G.battleWhy(s, { type: 'hack', target: 0 }), '');
  G.act(s, { type: 'pull', target: 0 });
  assert.equal(G.battleWhy(s, { type: 'gun', target: 0 }), '');
});

test('бой: рой теряет по 1 от стволов и весь урон от тарана', () => {
  const s = battleState(['swarm', 'biker']);
  const e = s.battle.enemies[0];
  G.act(s, { type: 'gun', target: 0 });
  assert.equal(e.hp, 4);
  e.dist = 0;
  G.act(s, { type: 'ram', target: 0 });
  assert.equal(e.hp, 0);
});

test('бой: глушилка блокирует взлом, щит гасит удар по корпусу', () => {
  const s = battleState(['jammer', 'biker']);
  assert.match(G.battleWhy(s, { type: 'hack', target: 1 }), /Глушилка/);
  s.crew.push({ id: 'guard', trust: 2, cd: 0, used: false });
  const biker = s.battle.enemies[1];
  biker.dist = 0; biker.pi = 0;
  s.battle.enemies[0].hp = 0;
  G.act(s, { type: 'skill', crew: 0 });
  assert.equal(s.battle.shield, 5);
  const hull = s.res.hull;
  G.act(s, { type: 'endTurn' });
  assert.equal(s.res.hull, hull);
});

test('критические состояния: один ноль — штраф, два — конец рейса', () => {
  const a = G.newRun(3);
  a.res.charge = 0;
  const lines = [];
  G.resolveCrit(a, lines);
  assert.equal(a.over, null);
  assert.equal(a.res.charge, 5);
  assert.equal(a.res.credits, 0);
  const b = G.newRun(3);
  b.res.charge = 0; b.res.focus = 0;
  G.resolveCrit(b, []);
  assert.equal(b.over.win, false);
  const c = G.newRun(3);
  c.res.credits = -50; c.res.hull = 0;
  G.resolveCrit(c, []);
  assert.equal(c.over.win, false, 'долг выше лимита должен заканчивать рейс');
});

test('баланс: жадный бот проходит демо не всегда и не никогда', () => {
  const N = 600;
  let wins = 0, crits = 0, battles = 0, hours = 0;
  const reasons = {};
  for (let seed = 1; seed <= N; seed++) {
    const { s, finished } = playRun(seed, greedyPolicy(mulberry(seed * 17)), { onStep: checkInvariants });
    assert.ok(finished, 'жадный бот завис, сид ' + seed);
    if (s.over.win) wins++; else reasons[s.over.text.slice(0, 28)] = (reasons[s.over.text.slice(0, 28)] || 0) + 1;
    crits += s.stats.crits; battles += s.stats.battles; hours += s.hour;
  }
  let sloppy = 0;
  for (let seed = 1; seed <= N; seed++) if (playRun(seed, greedyPolicy(mulberry(seed * 17), { sloppy: true })).s.over.win) sloppy++;
  console.log(`  тот же бот, но невнимательный на дороге: побед ${(sloppy / N * 100).toFixed(1)} %`);
  const rate = wins / N;
  console.log(`  жадный бот: побед ${(rate * 100).toFixed(1)} %, боёв за заезд ${(battles / N).toFixed(1)}, ` +
              `критических событий ${(crits / N).toFixed(2)}, часов ${(hours / N).toFixed(1)}`);
  console.log('  причины поражений:', reasons);
  assert.ok(rate > 0.45 && rate < 0.85, 'доля побед ' + rate);
});
