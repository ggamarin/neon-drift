// Сборка для публикации одним файлом. Для запуска она не нужна: index.html работает как есть.
// Берёт index.html, склеивает подключённые в нём скрипты в один и убирает обёртку <html>:
// в таком виде страница публикуется как артефакт Claude.
const fs = require('fs');
const path = require('path');

const page = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const files = [...page.matchAll(/<script src="(src\/[\w.-]+\.js)"><\/script>/g)].map(m => m[1]);
if (!files.length) throw new Error('в index.html не найдены скрипты');
const src = files.map(f => fs.readFileSync(path.join(__dirname, f), 'utf8')).join('\n');

const head = page.slice(page.indexOf('<title>'), page.indexOf('</head>'));
const body = page.slice(page.indexOf('<div class="wrap">'), page.indexOf('<!-- scripts'));
const out = head + '\n' + body + '<script>\n(function () {\n' + src + '\n})();\n</script>\n';

fs.mkdirSync(path.join(__dirname, 'dist'), { recursive: true });
fs.writeFileSync(path.join(__dirname, 'dist', 'index.html'), out);
console.log('dist/index.html: ' + files.length + ' скриптов, ' + (out.length / 1024).toFixed(1) + ' КБ');
