// Сквозной прогон интерфейса: бот играет заезды в настоящем браузере.
// Модель в Node и модель на странице получают одни и те же действия и обязаны прийти в одно состояние,
// а отрисовка каждого промежуточного экрана не должна бросать ошибок.
// Запуск: node tools/uirun.js [число заездов]
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { G, mulberry, randomPolicy, greedyPolicy } = require('../test/bots');

const runs = Number(process.argv[2]) || 4;
const html = fs.readFileSync(path.join(__dirname, '..', 'dist', 'index.html'), 'utf8');
const strip = s => { const c = JSON.parse(JSON.stringify(s)); c.fx = []; return JSON.stringify(c); };

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1300, height: 760 } });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.route('**/fonts.googleapis.com/**', r => r.abort());
  await page.setContent(`<!doctype html><html><head><meta charset="utf-8"></head><body>${html}</body></html>`, { waitUntil: 'load' });
  await page.evaluate(() => { window.__nd.ui.muted = true; });
  const screens = {};
  for (let run = 1; run <= runs; run++) {
    const seed = 1000 + run, s = G.newRun(seed);
    const policy = run % 2 ? greedyPolicy(mulberry(seed)) : randomPolicy(mulberry(seed));
    await page.evaluate(seed => window.__nd.newGame(seed), seed);
    let steps = 0;
    while (s.screen !== 'end' && steps < 3000) {
      const a = policy(s);
      if (!G.act(s, a)) continue;
      steps++;
      screens[s.screen] = (screens[s.screen] || 0) + 1;
      const ok = await page.evaluate(a => {
        const r = window.__nd.go(a);
        if (window.__nd.state.screen === 'map' && Math.random() < 0.2) window.__nd.ui.trunk = !window.__nd.ui.trunk;
        return new Promise(res => requestAnimationFrame(() => requestAnimationFrame(() => res(r))));
      }, a);
      if (!ok) { errors.push(`сид ${seed}, шаг ${steps}: страница отклонила действие ${JSON.stringify(a)}`); break; }
      if (errors.length) break;
    }
    const same = strip(s) === (await page.evaluate(() => { const c = JSON.parse(JSON.stringify(window.__nd.state)); c.fx = []; return JSON.stringify(c); }));
    console.log(`сид ${seed}: ${steps} действий, финал «${s.over && s.over.win ? 'победа' : 'поражение'}», состояния ${same ? 'совпали' : 'РАЗОШЛИСЬ'}`);
    if (!same) errors.push('состояние в браузере и в Node разошлось, сид ' + seed);
    if (errors.length) break;
  }
  await browser.close();
  console.log('отрисовано экранов:', screens);
  if (errors.length) { console.log('ОШИБКИ:\n' + errors.slice(0, 5).join('\n')); process.exit(1); }
  console.log('ошибок отрисовки нет');
})();
