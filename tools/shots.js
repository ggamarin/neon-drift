// Дымовой прогон в настоящем браузере: node tools/shots.js [папка для скриншотов]
// Проверяет настоящими кликами и клавишами, что страница работает, и снимает ключевые экраны.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const out = process.argv[2] || path.join(__dirname, '..', 'shots');
const html = fs.readFileSync(path.join(__dirname, '..', 'dist', 'index.html'), 'utf8');
const page_ = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0}</style></head><body>${html}</body></html>`;

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1340, height: 800 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/fonts\.g|ERR_|Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
  await page.route('**/fonts.googleapis.com/**', r => r.abort());
  await page.setContent(page_, { waitUntil: 'load' });
  const ev = (fn, arg) => page.evaluate(fn, arg);
  const cv = page.locator('#game');
  const shot = async name => { await page.waitForTimeout(350); await cv.screenshot({ path: path.join(out, name + '.png') }); };
  const at = async (x, y) => { const b = await cv.boundingBox(); const k = b.width / 640; await page.mouse.click(b.x + x * k, b.y + y * k); await page.waitForTimeout(90); };
  const hover = async (x, y) => { const b = await cv.boundingBox(); const k = b.width / 640; await page.mouse.move(b.x + x * k, b.y + y * k); };
  const state = () => ev(() => { const s = window.__nd.state; return { screen: s.screen, lane: s.drive && s.drive.lane, pos: s.drive && s.drive.pos }; });
  const check = (ok, text) => { if (!ok) errors.push(text); };
  console.log('масштаб canvas: ×' + (await cv.boundingBox()).width / 640);

  // --- первый запуск: подсказки включены ---
  await ev(() => { const u = window.__nd.ui; u.muted = true; u.hintsOff = false; u.seen = {}; window.__nd.newGame(424242); });
  await shot('01-title');
  await at(320, 337);                                   // «Начать рейс»
  check((await state()).screen === 'map', 'клик по «Начать рейс» не открыл карту');
  await page.waitForTimeout(200);
  check(await ev(() => window.__nd.ui.coachOn), 'на карте не появилась первая подсказка');
  await shot('02-map-hint');
  const first = await ev(() => { const s = window.__nd.state, n = s.map.nodes[s.map.nodes[s.at].next[0]]; return { x: 46 + n.col * 50, y: 78 + n.row * 56 }; });
  await at(first.x, first.y);
  check((await ev(() => window.__nd.ui.selNode)) == null, 'пока открыта подсказка, карта не должна принимать клики');
  for (let i = 0; i < 2; i++) { await page.keyboard.press('Enter'); await page.waitForTimeout(120); }   // «Понятно» ×2: ресурсы и карта
  await at(first.x, first.y);
  check((await ev(() => window.__nd.ui.selNode)) != null, 'клик по узлу карты не выбрал его');
  await page.waitForTimeout(150);
  await page.keyboard.press('Enter');                   // подсказка про режимы
  await page.waitForTimeout(120);
  await hover(530, 150);
  await shot('03-map-modes');
  await at(530, 150);                                   // режим «Быстро»
  check((await state()).screen === 'drive', 'клик по режиму езды не начал поездку');
  await page.waitForTimeout(250);
  check((await state()).pos === 0, 'пока открыта подсказка, дорога должна стоять на паузе');
  await shot('04-drive-hint');
  await page.keyboard.press('Enter');
  await page.keyboard.press('ArrowDown');               // сразу следом: нажатие не должно потеряться
  await page.waitForTimeout(80);
  check((await state()).lane === 2, 'нажатие сразу после закрытия подсказки потерялось');
  await page.keyboard.press('ArrowUp');
  await page.waitForTimeout(60);

  // --- дорога: клавиши, клик по полосе, самоход ---
  await ev(() => { window.__nd.ui.hintsOff = true; });
  await page.keyboard.press('ArrowDown');
  await page.waitForTimeout(60);
  check((await state()).lane === 2, 'стрелка вниз не перестроила машину');
  await at(400, 18 + 196 - 4);                          // клик по верхней полосе
  check((await state()).lane === 0, 'клик по верхней полосе не перестроил машину');
  await page.keyboard.press('s');
  await page.waitForTimeout(60);
  check((await state()).lane === 1, 'клавиша S не перестроила машину');
  await page.waitForTimeout(900);
  check((await state()).pos >= 2, 'машина не едет сама');
  await ev(() => { const u = window.__nd.ui, d = window.__nd.state.drive; u.auto = false; u.acc = 100;
    d.ambushAt = -1; d.pos = 5; d.lane = 1;
    d.objs = [{ x: 6, lane: 1, k: 'debris' }, { x: 7, lane: 0, k: 'cell' }, { x: 8, lane: 2, k: 'cam' }, { x: 8, lane: 1, k: 'debris' }, { x: 10, lane: 0, k: 'chip' }, { x: 11, lane: 2, k: 'debris' }, { x: 12, lane: 1, k: 'cell' }]; });
  await shot('05-drive');

  // --- засада посреди перегона и возврат на дорогу ---
  await ev(() => { const d = window.__nd.state.drive; d.objs = []; d.ambush = ['biker']; d.ambushAt = d.pos; ['hacker', 'guard'].forEach(window.__nd.debug.crew); window.__nd.go({ type: 'tick' }); });
  check((await state()).screen === 'battle', 'засада не началась посреди перегона');
  await page.waitForTimeout(800);
  const hp0 = await ev(() => window.__nd.state.battle.enemies[0].hp);
  await at(428, 276);                                   // «Стволы»: цель одна, выстрел сразу
  check((await ev(() => window.__nd.state.battle.enemies[0].hp)) === hp0 - 2, 'клик по «Стволам» не нанёс урон');
  await at(498, 345);                                   // «Конец хода»
  check((await ev(() => window.__nd.state.battle.turn)) === 2, 'клик по «Концу хода» не передал ход');
  await page.waitForTimeout(900);
  await ev(() => { window.__nd.state.battle.enemies[0].hp = 1; });
  await at(428, 276);
  check((await state()).screen === 'result', 'после победы нет экрана итога');
  await shot('06-result-midtrip');
  await at(320, 336);                                   // «Ехать дальше»
  check((await state()).screen === 'drive', 'после боя поездка не продолжилась');

  // --- статичные сцены для скриншотов ---
  await ev(() => window.__nd.debug.battle(['biker', 'patrol', 'drone', 'swarm']));
  await page.waitForTimeout(900);
  await hover(10, 300);
  await shot('07-battle');
  await ev(() => { window.__nd.ui.target = { type: 'push' }; });
  await shot('08-battle-target');
  await ev(() => { window.__nd.ui.target = null; window.__nd.go({ type: 'endTurn' }); });
  await page.waitForTimeout(500);
  await shot('09-battle-enemy-phase');
  await ev(() => { const u = window.__nd.ui; u.hintsOff = false; u.seen = {}; window.__nd.debug.battle(['jammer', 'biker']); });
  await page.waitForTimeout(900);
  await shot('10-battle-hint');
  await ev(() => { window.__nd.ui.hintsOff = true; window.__nd.debug.crew('android'); window.__nd.debug.battle(['boss', 'drone'], true); });
  await page.waitForTimeout(900);
  await shot('11-boss');
  await ev(() => { const s = window.__nd.state; s.battle = null; s.drive = null; s.event = { id: 'courier' }; s.screen = 'event'; });
  await shot('12-event');
  await ev(() => { const s = window.__nd.state; s.event = null; s.screen = 'map'; window.__nd.debug.item('emp'); window.__nd.debug.item('scrap'); window.__nd.ui.trunk = true; window.__nd.ui.sel = { uid: 2 }; });
  await shot('13-trunk');
  await ev(() => { const s = window.__nd.state; window.__nd.ui.trunk = false; s.screen = 'shop'; });
  await hover(100, 230);
  await shot('14-shop');
  await ev(() => { const s = window.__nd.state; s.over = { win: true, text: 'Броневик дымит на обочине, шлагбаум поднят. Кейс едет дальше, в Развязку.' }; s.screen = 'end'; });
  await shot('15-end');

  // узкий экран: страница не должна скроллиться вбок
  await page.setViewportSize({ width: 400, height: 800 });
  await page.waitForTimeout(200);
  const overflow = await ev(() => document.documentElement.scrollWidth - window.innerWidth);
  check(overflow <= 0, 'горизонтальная прокрутка на 400px: ' + overflow);

  await browser.close();
  if (errors.length) { console.log('ОШИБКИ:\n' + errors.join('\n')); process.exit(1); }
  console.log('ошибок нет, скриншоты в ' + out);
})();
