// Мост между JS-прототипом и Godot-демо. Запуск: node tools/gen-godot.js
// 1. Контент: src/data.js → godot/scripts/data.gd (единый источник текстов и чисел).
// 2. Эталонные заезды: боты играют в JS-модели, лог действий и след состояния
//    пишутся в godot/tests/replays.json — по ним Godot проверяет, что порт логики точный.
const fs = require('fs');
const path = require('path');
const { G, mulberry, randomPolicy, greedyPolicy, playRun } = require('../test/bots');

const names = ['RES_NAME', 'MODES', 'TRIP_LEN', 'ROAD_OBJ', 'NODE_INFO', 'ITEMS', 'SHOP_ITEMS', 'LOOT', 'UPGRADES', 'CREW', 'ENEMIES', 'GROUPS', 'EVENTS', 'HITCH_TEXT'];
let gd = '# Сгенерировано из src/data.js командой: node tools/gen-godot.js\n# Руками не править: менять нужно src/data.js.\n\n';
for (const n of names) gd += 'const ' + n + ' = ' + JSON.stringify(G[n]) + '\n';
fs.writeFileSync(path.join(__dirname, '..', 'godot', 'scripts', 'data.gd'), gd);

const strip = s => { const c = JSON.parse(JSON.stringify(s)); c.fx = []; return c; };
const runs = [];
for (let i = 1; i <= 24; i++) {
  const seed = 5000 + i * 37, trace = [];
  const policy = i % 3 === 0 ? randomPolicy(mulberry(seed)) : greedyPolicy(mulberry(seed), { sloppy: i % 3 === 1 });
  const { s, log } = playRun(seed, policy, {
    onStep: st => trace.push([st.rng, st.screen, st.res.charge, st.res.hull, st.res.focus, st.res.credits, st.res.wanted, st.hour]),
  });
  runs.push({ seed, actions: log, trace, final: strip(s) });
}
fs.writeFileSync(path.join(__dirname, '..', 'godot', 'tests', 'replays.json'), JSON.stringify(runs));
console.log('data.gd: ' + names.length + ' таблиц; replays.json: ' + runs.length + ' заездов, ' + runs.reduce((a, r) => a + r.actions.length, 0) + ' действий');
