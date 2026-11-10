// Интерфейс: immediate-mode UI поверх canvas 640×360.
// Экран каждый кадр рисуется заново из состояния модели S; все изменения идут через go(action).

const W = 640, H = 360, SCENE_TOP = 18, PANEL_Y = 248;
let cv = null, c = null, S = null;
const ui = {
  mx: -1, my: -1, click: false, cancel: false, input: true, tip: '', t: 0, dt: 16, f: 0, scroll: 0, keys: [],
  selNode: null, target: null, trunk: false, sel: null, rot: null, dropAsk: null,
  floats: [], lockUntil: 0, shakeUntil: 0, flash: null, disp: [], driveT0: 0, muted: false,
};

// ---------- звук ----------

let AC = null;
function tone(freq, dur, type, vol, slide, delay) {
  const t = AC.currentTime + (delay || 0), o = AC.createOscillator(), g = AC.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  if (slide) o.frequency.exponentialRampToValueAtTime(slide, t + dur);
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  o.connect(g); g.connect(AC.destination);
  o.start(t); o.stop(t + dur);
}
function sfx(kind) {
  if (ui.muted) return;
  try {
    AC = AC || new (window.AudioContext || window.webkitAudioContext)();
    if (AC.state === 'suspended') AC.resume();
    if (kind === 'click') tone(740, 0.05, 'square', 0.03);
    else if (kind === 'hit') tone(240, 0.12, 'square', 0.06, 70);
    else if (kind === 'hurt') tone(150, 0.2, 'sawtooth', 0.07, 50);
    else if (kind === 'ok') tone(520, 0.08, 'square', 0.04);
    else if (kind === 'alarm') { tone(330, 0.1, 'square', 0.04); tone(440, 0.12, 'square', 0.04, 0, 0.11); }
    else if (kind === 'win') { tone(520, 0.12, 'square', 0.05); tone(660, 0.12, 'square', 0.05, 0, 0.12); tone(880, 0.25, 'square', 0.05, 0, 0.24); }
    else if (kind === 'lose') tone(220, 0.5, 'sawtooth', 0.06, 55);
  } catch (e) { /* звук необязателен */ }
}

// ---------- примитивы ----------

const rc = (x, y, w, h, i) => R(c, x, y, w, h, i);
const tx = (s, x, y, i, k) => drawText(c, s, x, y, i, k);
function txC(s, cx, y, i, k) { tx(s, Math.round(cx - textW(s, k) / 2), y, i, k); }
function txR(s, rx, y, i) { tx(s, rx - textW(s), y, i); }
function panel(x, y, w, h, fill, border) { rc(x, y, w, h, border == null ? 4 : border); rc(x + 1, y + 1, w - 2, h - 2, fill == null ? 0 : fill); }
function hover(x, y, w, h) { return ui.input && ui.mx >= x && ui.mx < x + w && ui.my >= y && ui.my < y + h; }
const key = k => ui.keys.includes(k);

// Кнопка. o: off, why (причина недоступности), tip, sub (подпись справа), left, accent, lines (вторая строка).
function btn(x, y, w, h, label, o) {
  o = o || {};
  const over = hover(x, y, w, h), hot = over && !o.off;
  if (over) ui.tip = o.off ? (o.why || '') : (o.tip || '');
  const border = o.off ? 3 : hot ? 12 : o.on ? 26 : o.accent ? 19 : 5;
  const fill = o.off ? 1 : hot ? 9 : o.on ? 9 : o.accent ? 17 : 2;
  const col = o.off ? 5 : hot ? 26 : o.accent ? 20 : 25;
  panel(x, y, w, h, fill, border);
  const ty = o.line2 ? y + (h >> 1) - 9 : y + ((h - 7) >> 1);
  if (label) { if (o.left || o.sub) tx(label, x + 6, ty, col); else txC(label, x + w / 2, ty, col); }
  if (o.sub) txR(o.sub, x + w - 6, ty, o.off ? 4 : o.subCol || 19);
  if (o.line2) tx(o.line2, x + 6, y + (h >> 1) + 2, o.off ? 4 : o.line2Col || 24);
  if (hot && ui.click) { ui.click = false; sfx('click'); return true; }
  return false;
}

function corners(x, y, w, h, i) {
  rc(x, y, 5, 1, i); rc(x, y, 1, 5, i); rc(x + w - 5, y, 5, 1, i); rc(x + w - 1, y, 1, 5, i);
  rc(x, y + h - 1, 5, 1, i); rc(x, y + h - 5, 1, 5, i); rc(x + w - 5, y + h - 1, 5, 1, i); rc(x + w - 1, y + h - 5, 1, 5, i);
}

// ---------- действия ----------

function go(a) {
  const prev = S.screen;
  if (!act(S, a)) return false;
  ui.target = null; ui.dropAsk = null;
  if (S.screen !== prev) {
    ui.selNode = null; ui.sel = null; ui.rot = null; ui.trunk = false;
    if (S.screen === 'drive') ui.driveT0 = ui.t;
    if (S.screen === 'battle') { ui.disp = []; ui.lockUntil = 0; sfx('alarm'); }
    if (S.screen === 'result') sfx(S.over ? (S.over.win ? 'win' : 'lose') : 'ok');
  }
  return true;
}

function newGame(seed) {
  S = newRun(seed == null ? ((Date.now() % 900000) + 100000) : seed);
  Object.assign(ui, { selNode: null, target: null, trunk: false, sel: null, rot: null, floats: [], lockUntil: 0, disp: [] });
}

function takeFx() {
  if (!S.fx.length) return;
  if (S.screen === 'battle') {
    let t0 = Math.max(ui.t, ui.lockUntil), hurt = false;
    for (const e of S.fx) {
      if (e.k === 'dmg') {
        const d = ui.disp[e.i];
        ui.floats.push({ x: d ? d.x + d.w / 2 : 400, y: d ? d.y - d.h - 34 : 150, text: '−' + e.n, col: 26, t0: ui.t });
        sfx('hit');
      } else if (e.k === 'hurt') {
        const col = { hull: 25, charge: 11, focus: 7, credits: 19 }[e.res];
        ui.floats.push({ x: 72, y: 178, text: RES_NAME[e.res].toUpperCase() + ' −' + e.n, col, t0, hurt: true, from: e.i });
        t0 += 450; hurt = true;
      }
    }
    if (hurt) ui.lockUntil = t0;
  }
  S.fx.length = 0;
}

function drawFloats() {
  ui.floats = ui.floats.filter(fl => ui.t - fl.t0 < 950);
  for (const fl of ui.floats) {
    const a = ui.t - fl.t0;
    if (a < 0) continue;
    if (!fl.on) { fl.on = true; if (fl.hurt) { sfx('hurt'); ui.shakeUntil = ui.t + 180; ui.flash = { i: fl.from, until: ui.t + 240 }; } }
    const x = Math.round(fl.x - textW(fl.text) / 2), y = Math.round(fl.y - a / 45);
    rc(x - 3, y - 2, textW(fl.text) + 6, 11, 0);
    tx(fl.text, x, y, fl.col);
  }
}

// ---------- общие блоки ----------

function hudBar(x, label, v, max, col) {
  const low = v <= 3 && label !== 'РОЗЫСК', hot = label === 'РОЗЫСК' && v >= 5;
  tx(label, x, 5, (low || hot) && (ui.f & 2) ? 30 : 24);
  x += textW(label) + 4;
  for (let i = 0; i < max; i++) rc(x + i * 4, 5, 3, 7, i < v ? col : 2);
  return x + max * 4 + 8;
}

function drawHUD() {
  rc(0, 0, W, 18, 0); rc(0, 17, W, 1, 3);
  const r = S.res, m = S.max;
  let x = 5;
  x = hudBar(x, 'ЗАРЯД', r.charge, m.charge, 11);
  x = hudBar(x, 'КОРПУС', r.hull, m.hull, 25);
  x = hudBar(x, 'ФОКУС', r.focus, m.focus, 6);
  x = hudBar(x, 'РОЗЫСК', r.wanted, m.wanted, 15);
  tx('КР', x, 5, 24);
  tx(String(r.credits), x + 15, 5, r.credits < 0 ? 30 : 19);
  txR(clockText(S.hour), W - 5, 5, S.hour >= DAWN ? 19 : 25);
}

// Город в полосе; возвращает y линии дороги для спрайтов.
function scene(top, h) {
  const shake = ui.t < ui.shakeUntil ? (Math.floor(ui.t / 45) & 1 ? 2 : -2) : 0;
  drawScene(c, top, h, ui.scroll + shake);
  return top + h - SCN_H + LANE_Y;
}

function crewCard(x, y, i) {
  const m = S.crew[i];
  if (!m) { panel(x, y, 108, 50, 1, 3); txC('СВОБОДНО', x + 54, y + 21, 4); return; }
  const C = CREW[m.id];
  panel(x, y, 108, 50, 0, 5);
  portrait(c, x + 3, y + 3, m.id);
  tx(C.name, x + 39, y + 5, 25);
  tx(C.role, x + 39, y + 16, 6);
  tx('«' + C.skill + '»', x + 39, y + 27, 11);
  tx('ДОВЕРИЕ', x + 3, y + 39, 5);
  for (let k = 0; k < 3; k++) rc(x + 50 + k * 7, y + 39, 5, 7, k < m.trust ? 19 : 17);
  if (hover(x, y, 108, 50)) ui.tip = C.name + ', ' + C.role.toLowerCase() + '. «' + C.skill + '»: ' + C.desc + ' Минус: ' + C.flaw;
}

function tipBar(y) {
  rc(0, y, W, H - y, 0); rc(0, y, W, 1, 3);
  if (ui.tip) tx(wrapText(ui.tip, W - 12)[0], 6, y + 4, 25);
}

function muteBtn(x, y) {
  if (btn(x, y, 76, 16, ui.muted ? 'ЗВУК: ВЫКЛ' : 'ЗВУК: ВКЛ')) ui.muted = !ui.muted;
}

function bigTitle(text, y, col, shadow) {
  const k = 5, x = Math.round(W / 2 - textW(text, k) / 2);
  tx(text, x + 3, y + 3, shadow, k);
  tx(text, x, y, col, k);
}

// ---------- экраны ----------

function scTitle() {
  rc(0, 0, W, H, 3);
  const lane = scene(60, 230);
  sprCar(c, 150, lane, ui.f, true);
  drawForeground(c, 60, 230, ui.scroll);
  drawRain(c, 0, 290, ui.t);
  bigTitle('NEON DRIFT', 14, 12, 15);
  txC('ДЕМО-ПРОТОТИП · РАЙОН «ДОКИ»', W / 2, 58, 7);
  rc(0, 290, W, 70, 0); rc(0, 290, W, 1, 4);
  txC('Довези запечатанный кейс до КПП за одну ночь.', W / 2, 297, 25);
  txC('Машина — твой дом, дистанция — твоё оружие.', W / 2, 308, 24);
  if (btn(220, 324, 200, 26, 'НАЧАТЬ РЕЙС', { accent: true }) || key('Enter')) go({ type: 'start' });
  tx('СИД ' + S.seed, 8, 334, 6);
  if (btn(8, 344, 84, 14, 'ДРУГОЙ СИД')) newGame();
  muteBtn(556, 342);
}

const NODE_COL = { start: 24, road: 15, meet: 7, hitch: 28, park: 11, shop: 19, gate: 30, hidden: 5 };
function nodeXY(n) { return [46 + n.col * 50, 74 + n.row * 54]; }

function scMap() {
  rc(0, 18, W, H - 18, 1);
  drawHUD();
  panel(6, 22, 416, 212, 0, 3);
  tx('РАЙОН «ДОКИ»', 14, 28, 7);
  const dawn = S.hour >= DAWN ? 'РАССВЕТ: каждый переезд −2 Фокус' : 'до рассвета ' + (DAWN - S.hour) + ' ч';
  txR(dawn, 414, 28, S.hour >= DAWN ? 19 : 6);
  const nodes = S.map.nodes, cur = nodes[S.at];
  nodes.forEach(n => n.next.forEach(id => {
    const [x0, y0] = nodeXY(n), [x1, y1] = nodeXY(nodes[id]);
    pxLine(c, x0, y0, x1, y1, n.id === S.at ? 10 : 3);
  }));
  nodes.forEach(n => {
    const [x, y] = nodeXY(n), type = nodeVisible(S, n) ? n.type : 'hidden';
    const reach = cur.next.includes(n.id), isCur = n.id === S.at, sel = ui.selNode === n.id;
    const hot = hover(x - 11, y - 11, 22, 22);
    let fill = 1, border = 4, ic = NODE_COL[type];
    if (n.seen && !isCur) { fill = 2; border = 3; ic = 5; }
    if (reach) { fill = sel || hot ? 9 : 8; border = sel ? 26 : hot ? 12 : 11; }
    if (isCur) { fill = 4; border = ui.f & 2 ? 26 : 7; ic = 26; }
    rc(x - 11, y - 11, 22, 22, border); rc(x - 10, y - 10, 20, 20, fill);
    drawIcon(c, type, x - 4, y - 4, ic);
    if (hot) {
      ui.tip = NODE_INFO[type].name + '. ' + NODE_INFO[type].desc + (reach ? '' : isCur ? ' Вы здесь.' : ' Отсюда не доехать.');
      if (reach && ui.click) { ui.selNode = n.id; ui.click = false; sfx('click'); }
    }
  });
  let lx = 14;
  ['road', 'meet', 'hitch', 'park', 'shop', 'gate'].forEach(t => {
    drawIcon(c, t, lx, 220, NODE_COL[t]);
    tx(NODE_INFO[t].name, lx + 12, 221, 6);
    lx += 12 + textW(NODE_INFO[t].name) + 12;
  });

  panel(426, 22, 208, 212, 0, 3);
  if (ui.selNode != null) {
    const n = nodes[ui.selNode], type = nodeVisible(S, n) ? n.type : 'hidden', I = NODE_INFO[type];
    drawIcon(c, type, 434, 30, NODE_COL[type]);
    tx(I.name.toUpperCase(), 448, 30, 19);
    wrapText(I.desc, 192).forEach((l, i) => tx(l, 434, 44 + i * LINE_H, 25));
    tx('КАК ЕХАТЬ', 434, 74, 7);
    Object.keys(MODES).forEach((m, i) => {
      const M = MODES[m], short = S.res.charge < M.charge;
      const cost = '−' + M.charge + ' Заряд · +' + M.hours + ' ч' + (M.wanted ? ' · −1 Розыск' : '');
      if (btn(434, 86 + i * 46, 192, 40, M.name.toUpperCase(), {
        line2: short ? 'заряда не хватит: буксир' : cost, line2Col: short ? 30 : 24,
        tip: M.desc + (short ? ' Заряда не хватит: приедешь на буксире за 40 кр.' : ''),
      })) go({ type: 'travel', to: n.id, mode: m });
    });
  } else {
    tx('МАРШРУТ', 434, 30, 19);
    wrapText('Выбери соседний узел на карте, затем режим езды.', 192).forEach((l, i) => tx(l, 434, 46 + i * LINE_H, 25));
    wrapText('Типы узлов видны только на шаг вперёд. До КПП нужно дожить: ноль в двух ресурсах сразу — конец рейса.', 192)
      .forEach((l, i) => tx(l, 434, 76 + i * LINE_H, 6));
    tx('ПОДСВЕЧЕНЫ ДОСТУПНЫЕ УЗЛЫ', 434, 150, 11);
  }

  const lane = scene(238, 108);
  sprCar(c, 28, lane, ui.f, false);
  drawRain(c, 238, 108, ui.t);
  for (let i = 0; i < 3; i++) crewCard(150 + i * 112, 244, i);
  if (btn(490, 244, 144, 24, 'БАГАЖНИК', { tip: 'Переложить вещи, зарядить бардачок, применить предмет.' })) openTrunk();
  muteBtn(558, 272);
  tipBar(346);
}

function scDrive() {
  drawHUD();
  const lane = scene(SCENE_TOP, 230);
  sprCar(c, 120, lane, ui.f, true);
  drawForeground(c, SCENE_TOP, 230, ui.scroll);
  drawRain(c, SCENE_TOP, 230, ui.t);
  rc(0, PANEL_Y, W, H - PANEL_Y, 0); rc(0, PANEL_Y, W, 1, 4);
  const M = MODES[S.drive.mode];
  txC('В ПУТИ · ' + M.name.toUpperCase(), W / 2, 262, 19, 2);
  txC(M.desc, W / 2, 286, 25);
  const p = Math.min(1, (ui.t - ui.driveT0) / 2400);
  rc(170, 304, 300, 6, 2); rc(170, 304, Math.round(300 * p), 6, 11);
  if (S.drive.dawn) txC('Рассвет: Фокус −2', W / 2, 318, 19);
  txC('клик — пропустить', W / 2, 340, 6);
  if (p >= 1 || ui.click || key('Enter') || key(' ')) { ui.click = false; go({ type: 'arrive' }); }
}

// ---------- бой ----------

const BAND_X = [150, 315, 480], BAND_W = 160, BAND_NAME = ['ВПЛОТНУЮ', 'СРЕДНЯЯ', 'ДАЛЬНЯЯ'];

// Метка намерения: [текст, цвет плашки]. Плашки сплошные и яркие, чтобы не путались с вывесками на фоне.
function intentLook(it) {
  if (it.k === 'stun') return ['СБОЙ', 11];
  if (it.k === 'approach') return ['СБЛИЖАЕТСЯ', 6];
  if (it.k === 'aim') return ['ЦЕЛИТСЯ', 19];
  if (it.k === 'call') return ['ЗОВЁТ ПОДМОГУ', 19];
  return [RES_NAME[it.res].toUpperCase() + ' −' + it.n, 15];
}

function layoutEnemies(lane) {
  const b = S.battle;
  for (let d = 0; d < 3; d++) {
    const inBand = b.enemies.map((e, i) => [e, i]).filter(p => p[0].hp > 0 && p[0].dist === d);
    const groundW = inBand.reduce((a, p) => a + (ENEMIES[p[0].type].air ? 0 : SPR_SIZE[p[0].type][0] + 8), 0);
    const squeeze = groundW > BAND_W - 6 ? (BAND_W - 6) / groundW : 1;
    let gx = BAND_X[d] + 6, ak = 0;
    inBand.forEach(([e, i]) => {
      const [w, h] = SPR_SIZE[e.type];
      let px, py;
      if (ENEMIES[e.type].air) { px = BAND_X[d] + 18 + (ak % 3) * 48; py = lane - 86 - (ak % 2) * 36; ak++; }
      else { px = Math.round(gx); py = lane; gx += (w + 8) * squeeze; }
      const p = ui.disp[i] || (ui.disp[i] = { x: 670, y: py, w, h });
      p.tx = px; p.ty = py; p.w = w; p.h = h;
    });
  }
}

function pressAction(a) {
  if (needsTarget(S, a)) {
    const t = battleTargets(S, a);
    if (t.length === 1) go(Object.assign({}, a, { target: t[0] })); else ui.target = a;
  } else go(a);
}

function scBattle() {
  const b = S.battle, r = S.res;
  drawHUD();
  const lane = scene(SCENE_TOP, 230);
  for (let d = 0; d < 3; d++) {
    txC(BAND_NAME[d], BAND_X[d] + BAND_W / 2, 23, 7);
    for (let y = 34; y < 212; y += 4) rc(BAND_X[d] - 3, y, 1, 2, 6);
  }
  sprCar(c, 24, lane, ui.f, true);
  if (b.shield > 0) { corners(20, lane - 40, 104, 44, ui.f & 1 ? 12 : 11); }

  layoutEnemies(lane);
  const valid = ui.target ? battleTargets(S, ui.target) : [];
  const seer = crewHas(S, 'android');
  b.enemies.forEach((e, i) => {
    if (e.hp <= 0) return;
    const p = ui.disp[i], E = ENEMIES[e.type], k = Math.min(1, ui.dt / 110);
    p.x += (p.tx - p.x) * k; p.y += (p.ty - p.y) * k;
    if (Math.abs(p.tx - p.x) < 0.6) p.x = p.tx;
    let x = Math.round(p.x), y = Math.round(p.y);
    if (E.air) y += Math.round(Math.sin(ui.t / 320 + i * 2) * 2);
    if (ui.flash && ui.flash.i === i && ui.t < ui.flash.until) x -= 6;
    sprEnemy(c, e.type, x, y, ui.f + i, e);
    const top = y - p.h, bw = Math.max(34, p.w);
    rc(x, top - 7, bw, 5, 0);
    rc(x + 1, top - 6, Math.max(1, Math.round((bw - 2) * e.hp / e.max)), 3, 30);
    tx(String(e.hp), x + bw + 3, top - 8, 25);
    const look = intentLook(intentOf(S, e)), tw = textW(look[0]) + 8;
    const ix = clamp(x + (p.w >> 1) - (tw >> 1), 2, W - tw - 2);
    const mid = x + (p.w >> 1);
    rc(ix - 1, top - 23, tw + 2, 13, 0); rc(ix, top - 22, tw, 11, look[1]); tx(look[0], ix + 4, top - 20, 0);
    rc(mid - 2, top - 11, 5, 1, look[1]); rc(mid - 1, top - 10, 3, 1, look[1]);
    if (seer) {
      const nx = 'далее: ' + intentLook(nextIntent(S, e))[0], nw = textW(nx) + 6, nxx = clamp(ix, 2, W - nw - 2);
      rc(nxx - 1, top - 35, nw, 11, 0); tx(nx, nxx + 2, top - 33, 7);
    }
    if (b.mark === i) { rc(x + (p.w >> 1) - 4, top + (p.h >> 1), 9, 1, 19); rc(x + (p.w >> 1), top + (p.h >> 1) - 4, 1, 9, 19); }
    const over = hover(Math.min(x, ix) - 3, top - 24, Math.max(bw, tw) + 6, p.h + 26);
    if (ui.target && valid.includes(i)) {
      corners(x - 3, top - 3, p.w + 6, p.h + 6, over ? 26 : ui.f & 1 ? 12 : 11);
      if (over && ui.click) { ui.click = false; go(Object.assign({}, ui.target, { target: i })); }
    }
    if (over && S.battle) ui.tip = E.name + ' · ' + e.hp + '/' + e.max + ' · ' + E.desc;
  });
  if (!S.battle) return;   // бой закончился этим кликом
  if (ui.target && (ui.cancel || (ui.click && ui.my < PANEL_Y))) { ui.target = null; ui.click = false; }

  drawRain(c, SCENE_TOP, 230, ui.t);
  tx('ХОД ' + b.turn, 6, 24, 25);
  tx('ОД', 6, 38, 19);
  for (let i = 0; i < Math.max(3, b.ap); i++) rc(22 + i * 10, 37, 8, 8, i < b.ap ? 19 : 17);
  let sy = 51;
  if (b.shield > 0) { tx('ЩИТ ' + b.shield, 6, sy, 12); sy += 11; }
  if (b.escape > 0) { tx('ОТРЫВ ' + b.escape + ' %', 6, sy, 28); sy += 11; }
  if (!b.boss) tx('патруль через ' + (6 - b.heat) + ' х.', 6, sy, 6);

  rc(0, PANEL_Y, W, H - PANEL_Y, 0); rc(0, PANEL_Y, W, 1, 4);
  const busy = ui.t < ui.lockUntil;

  for (let i = 0; i < 3; i++) {
    const x = 4 + i * 81, y = 266, m = S.crew[i];
    if (!m) { panel(x, y, 78, 90, 1, 3); txC('ПУСТО', x + 39, y + 41, 4); continue; }
    const C = CREW[m.id], a = { type: 'skill', crew: i }, why = battleWhy(S, a);
    const on = ui.target && ui.target.type === 'skill' && ui.target.crew === i;
    if (btn(x, y, 78, 90, '', { off: !!why, why: C.name + ', «' + C.skill + '»: ' + why, on, tip: C.name + ', «' + C.skill + '»: ' + C.desc })) pressAction(a);
    portrait(c, x + 23, y + 4, m.id);
    if (why) dith(c, x + 23, y + 4, 32, 32, 0, 0);
    txC(C.name, x + 39, y + 40, why ? 5 : 25);
    txC(C.skill.toUpperCase(), x + 39, y + 52, why ? 5 : 11);
    const st = m.id === 'musician' ? (m.used ? 'сыграно' : '0 ОД') : m.cd > 0 ? 'откат ' + m.cd : C.ap + ' ОД';
    txC(st, x + 39, y + 64, why ? 5 : 19);
    for (let k = 0; k < 3; k++) rc(x + 29 + k * 7, y + 78, 5, 5, k < m.trust ? 19 : 17);
  }

  tx('БАРДАЧОК', 252, 266, 7);
  for (let slot = 0; slot < 3; slot++) {
    const x = 252 + slot * 35, id = S.glove[slot], a = { type: 'item', slot }, why = id ? battleWhy(S, a) : 'Пустой слот';
    if (btn(x, 278, 32, 32, '', { off: !!why, why: id ? ITEMS[id].name + ': ' + why : why, tip: id ? ITEMS[id].name + '. ' + ITEMS[id].desc : '' })) go(a);
    if (id) { itemIcon(c, id, x + 4, 282, 2); if (why) dith(c, x + 1, 279, 30, 30, 0, 0); }
  }
  tx('0 ОД, один', 252, 316, 6); tx('предмет за ход', 252, 326, 6);

  const g = 2 + S.up.guns, hk = 2 + S.up.deck;
  const acts = [
    ['gun', 'СТВОЛЫ', '1 ОД', 'Урон ' + g + ' по цели вплотную или на средней дистанции.'],
    ['ram', 'ТАРАН', '2 ОД', 'Урон 5 по цели вплотную. Свой Корпус −1.'],
    ['hack', 'ВЗЛОМ', '1 ОД, 1 Ф', 'Урон ' + hk + ' на любой дистанции, по технике вдвое. Первый взлом за бой: +1 розыск.'],
    ['escape', 'ОТРЫВ', 'все ОД', 'Копит шкалу побега за 2 Заряда. На 100 % бой кончается без добычи.'],
    ['pull', '← ПОДТЯНУТЬ', '1 ОД, 1 З', 'Манёвр: враг на шаг ближе, чтобы достать его оружием.'],
    ['push', 'ОТТЕСНИТЬ →', '1 ОД, 1 З', 'Манёвр: враг на шаг дальше. Если оттуда он не достаёт, удар сорван.'],
  ];
  acts.forEach((d, i) => {
    const a = { type: d[0] }, why = battleWhy(S, a), on = ui.target && ui.target.type === d[0];
    if (btn(360 + (i % 2) * 140, 266 + (i >> 1) * 23, 136, 20, d[1], { sub: d[2], off: !!why, why: d[1] + ': ' + why, tip: d[3], on })) pressAction(a);
  });
  if (btn(360, 335, 276, 20, 'КОНЕЦ ХОДА', { accent: b.ap === 0, tip: 'Враги выполняют намерения, которые показаны над ними.' }) ||
      (!busy && !ui.target && (key('Enter') || key(' ')))) go({ type: 'endTurn' });

  // строка подсказки: цель, подсказка под курсором или последняя запись журнала
  const line = ui.target ? 'Выбери цель. Клик мимо или Esc — отмена.' : ui.tip || (S.battle ? S.battle.log[S.battle.log.length - 1] : '') || 'Метка над врагом показывает, что он сделает в конце хода.';
  tx(wrapText(line, W - 12)[0], 6, 254, ui.target ? 12 : ui.tip ? 25 : 24);
}

// ---------- текстовые экраны ----------

function textPanel(title) {
  rc(0, 18, W, H - 18, 1);
  drawHUD();
  const lane = scene(SCENE_TOP, 118);
  sprCar(c, 60, lane, ui.f, false);
  drawRain(c, SCENE_TOP, 118, ui.t);
  panel(6, 140, 628, 214, 0, 4);
  tx(title.toUpperCase(), 18, 150, 19, 2);
}

function scEvent() {
  const v = eventView(S), hitch = S.event.id === 'hitch';
  textPanel(v.title);
  if (hitch) { panel(576, 146, 38, 38, 0, 19); portrait(c, 579, 149, S.event.who); }
  let y = 174;
  wrapText(v.text, hitch ? 540 : 600).forEach(l => { tx(l, 18, y, 25); y += LINE_H; });
  y = Math.max(y + 8, 240);
  v.options.forEach((o, i) => {
    const label = (i + 1) + '. ' + o.label;
    if (btn(18, y, 604, 22, label, { off: !o.ok, sub: o.ok ? '' : o.why, subCol: 30, left: true, why: o.why }) || (o.ok && key(String(i + 1)))) go({ type: 'choose', i });
    y += 26;
  });
}

function scResult() {
  const r = S.result;
  textPanel(r.title);
  let y = 176;
  r.lines.forEach(line => { wrapText(line, 600).forEach(l => { tx(l, 18, y, 25); y += LINE_H; }); y += 3; });
  y += 6;
  let x = 18;
  r.deltas.forEach(d => {
    const hour = d.k === 'hour';
    const label = (hour ? 'ВРЕМЯ' : RES_NAME[d.k].toUpperCase()) + ' ' + (d.n > 0 ? '+' : '−') + Math.abs(d.n) + (hour ? ' ч' : '');
    const good = d.k === 'wanted' ? d.n < 0 : d.n > 0, col = hour ? 24 : good ? 28 : 30, w = textW(label) + 10;
    if (x + w > 622) { x = 18; y += 17; }
    panel(x, y, w, 13, 0, col); tx(label, x + 5, y + 3, col);
    x += w + 5;
  });
  if (btn(220, 324, 200, 24, 'ДАЛЬШЕ', { accent: true }) || key('Enter') || key(' ')) go({ type: 'continue' });
}

function scPark() {
  textPanel('Стоянка');
  const r = S.res, p = S.park, fee = crewHas(S, 'mechanic') ? 10 : 0;
  tx('Тихий двор под эстакадой. Колонка, кофейный автомат и никого вокруг.', 18, 174, 25);
  if (btn(18, 192, 296, 22, 'ОТДОХНУТЬ', { sub: '+5 Фокус, +3 ч' + (fee ? ', −10 кр' : ''), off: p.rested || r.credits < fee,
    why: p.rested ? 'Сегодня уже отдыхали' : 'Не хватает кредитов', tip: 'Сон в машине. Время идёт, рассвет ближе.' })) go({ type: 'rest' });
  if (btn(18, 218, 296, 22, 'ЗАРЯДКА', { sub: '+4 Заряд за 15 кр', off: r.credits < 15 || r.charge >= S.max.charge,
    why: r.charge >= S.max.charge ? 'Батарея полная' : 'Не хватает кредитов', tip: 'Можно повторять, пока есть кредиты.' })) go({ type: 'charge' });
  if (btn(18, 244, 296, 22, 'РЕМОНТ', { sub: '+4 Корпус за 20 кр', off: r.credits < 20 || r.hull >= S.max.hull,
    why: r.hull >= S.max.hull ? 'Корпус цел' : 'Не хватает кредитов', tip: 'Можно повторять, пока есть кредиты.' })) go({ type: 'repair' });
  if (!S.crew.length) tx('В салоне пусто. Попутчики дают навыки в бою.', 326, 199, 6);
  S.crew.forEach((m, i) => {
    const C = CREW[m.id], done = p.talked.includes(m.id), full = m.trust >= 3;
    if (btn(326, 192 + i * 26, 296, 22, 'ПОГОВОРИТЬ: ' + C.name.toUpperCase(), { sub: 'доверие +1', off: done || full,
      why: full ? 'Доверие уже полное' : 'Уже поговорили', tip: 'При полном доверии откат навыка короче на ход.' })) go({ type: 'talk', crew: i });
  });
  if (ui.tip) tx(wrapText(ui.tip, 600)[0], 18, 290, 7);
  if (btn(18, 322, 190, 24, 'БАГАЖНИК')) openTrunk();
  if (btn(432, 322, 190, 24, 'ЕХАТЬ ДАЛЬШЕ', { accent: true })) go({ type: 'leave' });
}

function scShop() {
  textPanel('Мастерская');
  const r = S.res;
  tx('ПРИПАСЫ', 18, 172, 7);
  SHOP_ITEMS.forEach((id, i) => {
    const D = ITEMS[id], room = findSpot(S, id) || (D.small && S.glove.includes(null));
    if (btn(18, 183 + i * 19, 196, 17, D.name, { sub: D.price + ' кр', off: r.credits < D.price || !room,
      why: room ? 'Не хватает кредитов' : 'Нет места в багажнике', tip: D.name + '. ' + D.desc })) go({ type: 'buy', item: id });
  });
  tx('АПГРЕЙДЫ', 222, 172, 7);
  Object.keys(UPGRADES).forEach((id, i) => {
    const U = UPGRADES[id], have = S.up[id];
    if (btn(222, 183 + i * 19, 196, 17, U.name, { sub: have ? 'стоит' : U.price + ' кр', off: have || r.credits < U.price,
      why: have ? 'Уже установлено. ' + U.desc : 'Не хватает кредитов. ' + U.desc, tip: U.name + '. ' + U.desc })) go({ type: 'upgrade', id });
  });
  tx('СКУПКА', 222, 264, 7);
  const loot = S.trunk.filter(t => ITEMS[t.id].sell).slice(0, 4);
  if (!loot.length) tx('Продать нечего.', 222, 277, 5);
  loot.forEach((t, i) => {
    const D = ITEMS[t.id];
    if (btn(222, 275 + i * 19, 196, 17, D.name, { sub: '+' + D.sell + ' кр', tip: 'Продать: ' + D.name })) go({ type: 'sell', uid: t.uid });
  });
  tx('ПОДСКАЗКА', 426, 172, 7);
  wrapText(ui.tip || 'Наведи на товар, чтобы прочитать описание. В бардачок помещается только мелочь.', 196)
    .slice(0, 8).forEach((l, i) => tx(l, 426, 185 + i * LINE_H, 25));
  if (btn(426, 296, 196, 22, 'БАГАЖНИК')) openTrunk();
  if (btn(426, 324, 196, 24, 'ЕХАТЬ ДАЛЬШЕ', { accent: true })) go({ type: 'leave' });
}

function scEnd() {
  const o = S.over, st = S.stats;
  rc(0, 0, W, H, 3);
  const lane = scene(60, 230);
  if (o.win) sprCar(c, 260, lane, ui.f, true);
  drawRain(c, 0, 290, ui.t);
  bigTitle(o.win ? 'ДЕМО ПРОЙДЕНО' : 'РЕЙС ОКОНЧЕН', 14, o.win ? 12 : 16, o.win ? 9 : 29);
  panel(60, 70, 520, 92, 0, o.win ? 11 : 15);
  let y = 78;
  wrapText(o.text, 500).forEach(l => { tx(l, 70, y, 25); y += LINE_H; });
  y += 6;
  tx('Узлов пройдено: ' + st.nodes + ' · Боёв: ' + st.battles + ' (побед ' + st.wins + ', отрывов ' + st.escapes + ')', 70, y, 7);
  tx('Критических событий: ' + st.crits + ' · Финиш в ' + clockText(S.hour) + ' · Кредиты: ' + S.res.credits + ' · Розыск: ' + S.res.wanted, 70, y + 12, 7);
  tx('Сид заезда: ' + S.seed, 70, y + 24, 6);
  rc(0, 290, W, 70, 0); rc(0, 290, W, 1, 4);
  if (btn(120, 312, 190, 26, 'НОВЫЙ РЕЙС', { accent: true })) newGame();
  if (btn(330, 312, 190, 26, 'ТОТ ЖЕ СИД')) newGame(S.seed);
}

// ---------- багажник ----------

function openTrunk() { ui.trunk = true; ui.sel = null; ui.rot = null; ui.dropAsk = null; }
function closeTrunk() { ui.trunk = false; ui.sel = null; ui.rot = null; ui.dropAsk = null; }

function drawTrunk() {
  dith(c, 0, 18, W, H - 18, 0, 0);
  const X = 100, Y = 50, gx = X + 16, gy = Y + 36, cs = 28;
  panel(X, Y, 440, 262, 0, 11);
  tx('БАГАЖНИК', X + 14, Y + 10, 19, 2);
  if (btn(X + 368, Y + 8, 60, 18, 'ЗАКРЫТЬ') || key('Escape')) { closeTrunk(); return; }
  for (let y = 0; y < TRUNK_H; y++) for (let x = 0; x < TRUNK_W; x++) rc(gx + x * cs, gy + y * cs, cs - 1, cs - 1, 1);

  let selIt = ui.sel && ui.sel.uid != null ? S.trunk.find(t => t.uid === ui.sel.uid) : null;
  S.trunk.forEach(t => {
    const D = ITEMS[t.id], [w, h] = itemSize(t), x = gx + t.x * cs, y = gy + t.y * cs, pw = w * cs - 1, ph = h * cs - 1;
    const sel = selIt === t, fill = D.lock ? 13 : D.sell ? 17 : D.use || D.battle ? 8 : 21;
    rc(x, y, pw, ph, sel ? (ui.f & 1 ? 26 : 12) : fill === 13 ? 14 : fill === 17 ? 18 : fill === 8 ? 10 : 23);
    rc(x + 1, y + 1, pw - 2, ph - 2, fill);
    itemIcon(c, t.id, x + ((pw - 24) >> 1), y + ((ph - 24) >> 1), 2);
    if (hover(x, y, pw, ph)) {
      ui.tip = D.name + '. ' + D.desc;
      if (ui.click && !sel) { ui.sel = { uid: t.uid }; ui.rot = null; ui.dropAsk = null; ui.click = false; sfx('click'); selIt = t; }
    }
  });

  // перенос выбранного предмета в клетку под курсором
  if (selIt && hover(gx, gy, TRUNK_W * cs, TRUNK_H * cs)) {
    const cxl = Math.floor((ui.mx - gx) / cs), cyl = Math.floor((ui.my - gy) / cs);
    const r = ui.rot == null ? selIt.r : ui.rot, D = ITEMS[selIt.id], w = r ? D.h : D.w, h = r ? D.w : D.h;
    const moved = cxl !== selIt.x || cyl !== selIt.y || r !== selIt.r;
    if (moved) {
      const ok = fits(S, selIt.id, cxl, cyl, r, selIt.uid);
      corners(gx + cxl * cs, gy + cyl * cs, w * cs - 1, h * cs - 1, ok ? 28 : 30);
      if (ui.click) { ui.click = false; if (ok) { go({ type: 'place', uid: selIt.uid, x: cxl, y: cyl, r }); ui.rot = null; sfx('click'); } }
    }
  }

  tx('БАРДАЧОК · доступен в бою', X + 200, Y + 36, 7);
  for (let slot = 0; slot < 3; slot++) {
    const x = X + 200 + slot * 36, y = Y + 48, id = S.glove[slot], sel = ui.sel && ui.sel.slot === slot;
    panel(x, y, 32, 32, sel ? 9 : 1, sel ? 26 : 5);
    if (id) itemIcon(c, id, x + 4, y + 4, 2);
    if (hover(x, y, 32, 32)) {
      ui.tip = id ? ITEMS[id].name + '. ' + ITEMS[id].desc : 'Пустой слот. Сюда помещается только мелочь 1×1.';
      if (ui.click) {
        ui.click = false; sfx('click');
        if (id) { ui.sel = { slot }; ui.rot = null; }
        else if (selIt && go({ type: 'stow', uid: selIt.uid, slot })) ui.sel = { slot };
      }
    }
  }

  const selId = selIt ? selIt.id : ui.sel && ui.sel.slot != null ? S.glove[ui.sel.slot] : null;
  if (selId) {
    const D = ITEMS[selId];
    tx(D.name.toUpperCase(), X + 200, Y + 92, 19);
    tx(D.w + '×' + D.h + (D.small ? ' · влезает в бардачок' : ''), X + 200, Y + 104, 6);
    wrapText(D.desc, 224).forEach((l, i) => tx(l, X + 200, Y + 118 + i * LINE_H, 25));
  } else {
    wrapText('Выбери предмет, затем клетку, куда его переложить. Пустой слот бардачка принимает выбранную мелочь.', 224)
      .forEach((l, i) => tx(l, X + 200, Y + 92 + i * LINE_H, 6));
  }
  if (ui.tip) wrapText(ui.tip, 408).slice(0, 2).forEach((l, i) => tx(l, X + 16, Y + 158 + i * LINE_H, 7));

  const by = Y + 232, D = selId ? ITEMS[selId] : null;
  if (btn(X + 16, by, 100, 18, 'ПОВЕРНУТЬ', { off: !selIt || D.w === D.h, why: 'Нечего поворачивать' })) {
    const r = (ui.rot == null ? selIt.r : ui.rot) ? 0 : 1;
    if (go({ type: 'place', uid: selIt.uid, x: selIt.x, y: selIt.y, r })) ui.rot = null; else ui.rot = r;
  }
  if (btn(X + 120, by, 100, 18, 'ПРИМЕНИТЬ', { off: !D || !D.use, why: D ? 'Вне боя не применяется' : 'Ничего не выбрано' })) {
    if (selIt ? go({ type: 'use', uid: selIt.uid }) : go({ type: 'useGlove', slot: ui.sel.slot })) { ui.sel = null; sfx('ok'); }
  }
  if (btn(X + 224, by, 100, 18, 'В БАГАЖНИК', { off: !(ui.sel && ui.sel.slot != null && selId), why: 'Выбери предмет в бардачке' })) {
    if (go({ type: 'unstow', slot: ui.sel.slot })) ui.sel = null;
  }
  const ask = selIt && ui.dropAsk === selIt.uid;
  if (btn(X + 328, by, 100, 18, ask ? 'ТОЧНО?' : 'ВЫБРОСИТЬ', { off: !selIt || D.lock, why: selIt ? 'Это выбросить нельзя' : 'Выбери предмет в багажнике', accent: ask })) {
    if (ask) { go({ type: 'drop', uid: selIt.uid }); ui.sel = null; } else ui.dropAsk = selIt.uid;
  }
  if (ui.rot != null && selIt) tx('Повёрнуто: укажи клетку, куда положить.', X + 16, by - 14, 19);
}

// ---------- запуск ----------

const SCREEN = { title: scTitle, map: scMap, drive: scDrive, battle: scBattle, event: scEvent, result: scResult, park: scPark, shop: scShop, end: scEnd };

function frame(now) {
  ui.dt = Math.min(100, Math.max(0, now - ui.t)); ui.t = now; ui.f = Math.floor(now / 125);
  ui.tip = '';
  ui.scroll += ({ title: 50, drive: 170, battle: 110, end: 30 }[S.screen] || 0) * ui.dt / 1000;
  takeFx();
  ui.input = !ui.trunk && now >= ui.lockUntil;
  if (key('Escape')) ui.target = null;
  SCREEN[S.screen]();
  if (ui.trunk) { ui.input = true; ui.tip = ''; drawTrunk(); }
  drawFloats();
  ui.click = false; ui.cancel = false; ui.keys.length = 0;
  requestAnimationFrame(frame);
}

// Масштаб: один игровой пиксель = целое число пикселей экрана (с учётом плотности дисплея).
// Если так картинка выходит мелкой, кнопка под экраном растягивает её на всё доступное место.
function fitCanvas() {
  const availW = cv.parentElement.clientWidth, availH = Math.max(240, window.innerHeight - 56);
  const fit = Math.min(availW / W, availH / H), dpr = window.devicePixelRatio || 1;
  const sharp = fit < 1 ? fit : Math.max(1, Math.floor(fit * dpr) / dpr);
  const k = ui.stretch ? fit : sharp;
  cv.style.width = Math.floor(W * k) + 'px';
  cv.style.height = Math.floor(H * k) + 'px';
  const b = document.getElementById('fit');
  if (b) {
    b.textContent = (ui.stretch ? 'Масштаб: во весь экран' : 'Масштаб: чёткий пиксель') + ' ×' + (Math.round(k * 100) / 100);
    b.hidden = fit < 1 || Math.abs(fit - sharp) < 0.02;
  }
}

function bindInput() {
  const pos = e => {
    const r = cv.getBoundingClientRect();
    ui.mx = Math.floor((e.clientX - r.left) * W / r.width);
    ui.my = Math.floor((e.clientY - r.top) * H / r.height);
  };
  cv.addEventListener('pointermove', pos);
  cv.addEventListener('pointerdown', e => { pos(e); if (e.button === 2) ui.cancel = true; else ui.click = true; e.preventDefault(); });
  cv.addEventListener('pointerleave', () => { ui.mx = ui.my = -1; });
  cv.addEventListener('contextmenu', e => e.preventDefault());
  window.addEventListener('keydown', e => {
    ui.keys.push(e.key);
    if (e.key === ' ' && (e.target === document.body || e.target === cv)) e.preventDefault();
  });
  window.addEventListener('resize', fitCanvas);
  const fb = document.getElementById('fit');
  if (fb) fb.addEventListener('click', () => {
    ui.stretch = !ui.stretch;
    try { localStorage.setItem('nd-stretch', ui.stretch ? '1' : ''); } catch (e) { /* без хранилища тоже работает */ }
    fitCanvas();
  });
}

function start(data) {
  cv = document.getElementById('game');
  c = cv.getContext('2d');
  c.imageSmoothingEnabled = false;
  buildScene();
  try { ui.stretch = localStorage.getItem('nd-stretch') === '1'; } catch (e) { ui.stretch = false; }
  bindInput();
  fitCanvas();
  const m = /^#s(\d{1,9})$/.exec(location.hash || '');
  if (data && data.S && data.S.map && data.S.screen) { S = data.S; S.fx = []; if (S.screen === 'drive') ui.driveT0 = -1e9; }
  else newGame(m ? Number(m[1]) : null);
  // хук для автотестов: состояние, действия и интерфейс доступны снаружи
  window.__nd = {
    get state() { return S; }, go, ui, newGame,
    // заготовки сцен для ручной проверки и скриншотов
    debug: {
      battle(types, boss) { S.screen = 'map'; S.battle = null; startBattle(S, types, !!boss); ui.disp = []; },
      crew(id) { if (!crewHas(S, id) && S.crew.length < 3) { S.crew.push({ id, trust: 2, cd: 0, used: false }); if (id === 'surgeon') addItem(S, 'tools'); } },
      item(id) { return addItem(S, id); },
    },
  };
  requestAnimationFrame(t => { ui.t = t; requestAnimationFrame(frame); });
}

const hot = window.claude && window.claude.hot;
if (hot && hot.snapshot) hot.snapshot(() => ({ S }));
if (hot && hot.ready) hot.ready(start); else start((hot && hot.data) || {});
