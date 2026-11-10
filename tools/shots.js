// Дымовой прогон в настоящем браузере: node tools/shots.js [папка для скриншотов]
// Проверяет, что страница грузится без ошибок, и снимает ключевые экраны.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const out = process.argv[2] || path.join(__dirname, '..', 'shots');
const html = fs.readFileSync(path.join(__dirname, '..', 'dist', 'index.html'), 'utf8');
const page_ = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0}</style></head><body>${html}</body></html>`;

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1300, height: 760 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/fonts\.g|ERR_|Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
  await page.route('**/fonts.googleapis.com/**', r => r.abort());
  await page.setContent(page_, { waitUntil: 'load' });
  await page.evaluate(() => { window.__nd.ui.muted = true; window.__nd.newGame(424242); });
  const cv = page.locator('#game');
  const shot = async name => { await page.waitForTimeout(350); await cv.screenshot({ path: path.join(out, name + '.png') }); };
  const go = a => page.evaluate(a => window.__nd.go(a), a);
  const at = async (x, y) => { const b = await cv.boundingBox(); const k = b.width / 640; await page.mouse.click(b.x + x * k, b.y + y * k); };
  const box = await cv.boundingBox();
  console.log('масштаб canvas: ×' + box.width / 640);

  await shot('01-title');
  await at(320, 337);                                   // «Начать рейс»
  await page.waitForTimeout(100);
  if ((await page.evaluate(() => window.__nd.state.screen)) !== 'map') errors.push('клик по «Начать рейс» не открыл карту');
  await page.evaluate(() => { const s = window.__nd.state; window.__nd.ui.selNode = s.map.nodes[s.at].next[0]; ['hacker', 'guard'].forEach(window.__nd.debug.crew); });
  await page.mouse.move(box.x + 500 * box.width / 640, box.y + 110 * box.width / 640);
  await shot('02-map');
  await page.evaluate(() => { window.__nd.debug.item('emp'); window.__nd.debug.item('scrap'); window.__nd.ui.trunk = true; window.__nd.ui.sel = { uid: 2 }; });
  await shot('03-trunk');
  await page.evaluate(() => { window.__nd.ui.trunk = false; });
  await page.evaluate(() => window.__nd.debug.battle(['biker', 'patrol', 'drone', 'swarm']));
  await page.waitForTimeout(900);
  await shot('04-battle');
  await page.evaluate(() => { window.__nd.ui.target = { type: 'push' }; });
  await shot('05-battle-target');
  await page.evaluate(() => { window.__nd.ui.target = null; window.__nd.go({ type: 'endTurn' }); });
  await page.waitForTimeout(500);
  await shot('06-battle-enemy-phase');
  await page.evaluate(() => { window.__nd.debug.crew('android'); window.__nd.debug.battle(['boss', 'drone'], true); });
  await page.waitForTimeout(900);
  await shot('07-boss');
  await page.evaluate(() => { const s = window.__nd.state; s.battle = null; s.event = { id: 'courier' }; s.screen = 'event'; });
  await shot('08-event');
  await go({ type: 'choose', i: 0 });
  await shot('09-result');
  await page.evaluate(() => { const s = window.__nd.state; s.result = null; s.event = { id: 'hitch', who: 'musician' }; s.screen = 'event'; });
  await shot('10-hitch');
  await page.evaluate(() => { const s = window.__nd.state; s.event = null; s.park = { rested: false, talked: [] }; s.screen = 'park'; });
  await shot('11-park');
  await page.evaluate(() => { const s = window.__nd.state; s.park = null; s.screen = 'shop'; });
  await page.mouse.move(box.x + 100 * box.width / 640, box.y + 230 * box.width / 640);
  await shot('12-shop');
  await page.evaluate(() => { const s = window.__nd.state; s.over = { win: true, text: 'Броневик дымит на обочине, шлагбаум поднят. Кейс едет дальше, в Развязку.' }; s.screen = 'end'; });
  await shot('13-end');

  // настоящие клики: узел → режим → дорога → прибытие, затем кнопка боя
  await page.evaluate(() => window.__nd.newGame(7));
  await at(320, 337);
  const first = await page.evaluate(() => { const s = window.__nd.state, n = s.map.nodes[s.map.nodes[s.at].next[0]]; return { x: 46 + n.col * 50, y: 74 + n.row * 54 }; });
  await at(first.x, first.y);
  await page.waitForTimeout(80);
  if ((await page.evaluate(() => window.__nd.ui.selNode)) == null) errors.push('клик по узлу карты не выбрал его');
  await at(530, 152);                                   // режим «Быстро»
  await page.waitForTimeout(80);
  if ((await page.evaluate(() => window.__nd.state.screen)) !== 'drive') errors.push('клик по режиму езды не начал поездку');
  await page.waitForTimeout(2700);
  const after = await page.evaluate(() => window.__nd.state.screen);
  if (after === 'drive' || after === 'map') errors.push('поездка не закончилась прибытием: ' + after);
  await page.evaluate(() => window.__nd.debug.battle(['biker']));
  await page.waitForTimeout(700);
  const hp0 = await page.evaluate(() => window.__nd.state.battle.enemies[0].hp);
  await at(428, 276);                                   // «Стволы»: цель одна, выстрел сразу
  await page.waitForTimeout(80);
  const hp1 = await page.evaluate(() => window.__nd.state.battle.enemies[0].hp);
  if (hp1 !== hp0 - 2) errors.push('клик по «Стволам» не нанёс урон: ' + hp0 + ' → ' + hp1);
  await at(498, 345);                                   // «Конец хода»
  await page.waitForTimeout(80);
  if ((await page.evaluate(() => window.__nd.state.battle.turn)) !== 2) errors.push('клик по «Концу хода» не передал ход');
  await page.waitForTimeout(1200);

  // шрифт целиком — для проверки глифов глазами
  await page.evaluate(() => {
    const cv = document.getElementById('game'), s = window.__nd.state;
    s.over = null; s.screen = 'result';
    s.result = { title: 'Шрифт', then: 'map', deltas: [], lines: [
      'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ', 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789',
      '.,:;!?-–—−+×/()%«»"\'·…→←↑↓[]=<>#*_|', 'Съешь ещё этих мягких французских булок, да выпей чаю. Эй, жлоб! Где туз? Прячь юных съёмщиц в шкаф.' ] };
  });
  await shot('14-font');

  // узкий экран: страница не должна скроллиться вбок
  await page.setViewportSize({ width: 400, height: 800 });
  await page.waitForTimeout(200);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  if (overflow > 0) errors.push('горизонтальная прокрутка на 400px: ' + overflow);
  await page.screenshot({ path: path.join(out, '15-phone.png') });

  await browser.close();
  if (errors.length) { console.log('ОШИБКИ:\n' + errors.join('\n')); process.exit(1); }
  console.log('ошибок нет, скриншоты в ' + out);
})();
