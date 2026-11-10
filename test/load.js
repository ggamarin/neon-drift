// Загружает модель без браузера: файлы src склеиваются в одну область видимости,
// так же, как это делает сборка в dist/index.html.
const fs = require('fs');
const path = require('path');

const files = ['rng.js', 'data.js', 'model.js'];
const src = files.map(f => fs.readFileSync(path.join(__dirname, '..', 'src', f), 'utf8')).join('\n');

module.exports = new Function(src + `
return { newRun, act, eventView, battleWhy, battleTargets, intentOf, nextIntent, fits, itemSize, living,
         nodeVisible, startBattle, resolveCrit, addItem, findSpot,
         ITEMS, CREW, ENEMIES, EVENTS, MODES, SHOP_ITEMS, UPGRADES, TRUNK_W, TRUNK_H, DAWN, DEBT_LIMIT };`)();
