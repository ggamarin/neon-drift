// Сборка: склеивает src/*.js в один скрипт и вставляет в оболочку.
// Результат — один самодостаточный файл dist/index.html без внешних зависимостей (кроме веб-шрифта подписей).
const fs = require('fs');
const path = require('path');

const ORDER = ['rng', 'data', 'model', 'font', 'art', 'ui'];
const src = ORDER.map(f => fs.readFileSync(path.join(__dirname, 'src', f + '.js'), 'utf8')).join('\n');
const shell = fs.readFileSync(path.join(__dirname, 'src', 'shell.html'), 'utf8');
const out = shell.replace('/*__GAME__*/', () => "(function () {\n'use strict';\n" + src + '\n})();');

// index.html — страница без обёртки <html>: в таком виде она публикуется как артефакт Claude.
// neon-drift.html — та же страница с полной обёрткой: её можно открыть двойным кликом или положить на любой хостинг.
const cut = out.indexOf('<div class="wrap">');
const standalone = '<!doctype html>\n<html lang="ru">\n<head>\n<meta charset="utf-8">\n' +
  '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n' +
  out.slice(0, cut).replace('<style>', '<style>\n  body { margin: 0; }') + '</head>\n<body>\n' + out.slice(cut) + '</body>\n</html>\n';

fs.mkdirSync(path.join(__dirname, 'dist'), { recursive: true });
fs.writeFileSync(path.join(__dirname, 'dist', 'index.html'), out);
fs.writeFileSync(path.join(__dirname, 'dist', 'neon-drift.html'), standalone);
console.log('dist/index.html и dist/neon-drift.html: ' + (out.length / 1024).toFixed(1) + ' КБ');
