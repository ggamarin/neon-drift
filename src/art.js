'use strict';
// Пиксель-арт прототипа: палитра 32 цвета и процедурные спрайты из прямоугольников.
// Никаких внешних картинок, поворотов и сглаживания — всё рисуется по целым пикселям.
// Цвет несёт смысл: циан — своё, маджента — угроза, янтарь — ресурсы. Контур спрайта красится так же.

const PAL = [
  '#0b0b14', '#14132a', '#1d1b3f', '#2a2456', '#3b2f73', '#55449a', '#7a68c4', '#b9aef0',   // 0–7  тёмная база
  '#0f2a3a', '#145066', '#1e8a9a', '#2fd6e0', '#a8f6ff',                                     // 8–12 циан: своё
  '#4a0f3c', '#8c1d6b', '#e0399f', '#ff8fd0',                                                // 13–16 маджента: угроза
  '#4a2a10', '#a85a14', '#f2a81d', '#ffe08a',                                                // 17–20 янтарь: ресурсы
  '#23262f', '#3a3f4d', '#5b6377', '#8e97ad', '#d7dceb', '#ffffff',                          // 21–26 сталь
  '#2a6b3c', '#58d37a', '#7a1f24', '#e0444a', '#f5d0b5',                                     // 27–31 зелёный, красный, кожа
];

function R(c, x, y, w, h, i) { c.fillStyle = PAL[i]; c.fillRect(x, y, w, h); }
// Шахматный дизеринг: так рисуются свечение и переходы, без полупрозрачности.
function dith(c, x, y, w, h, i, ph) {
  c.fillStyle = PAL[i];
  for (let yy = 0; yy < h; yy++) for (let xx = (yy + (ph || 0)) & 1; xx < w; xx += 2) c.fillRect(x + xx, y + yy, 1, 1);
}
function outline(c, x, y, w, h, i) { R(c, x, y, w, 1, i); R(c, x, y + h - 1, w, 1, i); R(c, x, y, 1, h, i); R(c, x + w - 1, y, 1, h, i); }
function pxLine(c, x0, y0, x1, y1, i) {
  c.fillStyle = PAL[i];
  const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  let e = dx + dy;
  for (;;) {
    c.fillRect(x0, y0, 1, 1);
    if (x0 === x1 && y0 === y1) break;
    const e2 = 2 * e;
    if (e2 >= dy) { e += dy; x0 += sx; }
    if (e2 <= dx) { e += dx; y0 += sy; }
  }
}

// ---------- город: слои параллакса ----------

// Дорога в три полосы: LANES — линии, на которых стоят колёса (верхняя, средняя, нижняя).
const SCN_H = 230, ROAD_Y = 178, LANES = [196, 210, 224], LANE_Y = LANES[1];
let SCN = null;

function visRand(seed) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), a | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeLayer(w, h, draw) {
  const cv = document.createElement('canvas');
  cv.width = w; cv.height = h;
  draw(cv.getContext('2d'));
  return cv;
}

const DARK = { 11: 8, 15: 13, 19: 17 }, MID = { 11: 9, 15: 14, 19: 18 }, LITE = { 11: 12, 15: 16, 19: 20 };
const DIM = { 18: 17, 19: 17, 10: 8, 11: 8, 14: 13, 17: 2, 8: 2, 13: 2 };

// quiet — приглушённый вариант для экранов, где фон не должен спорить с игрой.
function neonSign(c, x, y, word, col, vertical, quiet) {
  const w = vertical ? 11 : textW(word) + 8, h = vertical ? word.length * 9 + 5 : 13;
  if (!quiet) dith(c, x - 2, y - 2, w + 4, h + 4, MID[col], 0);
  R(c, x, y, w, h, quiet ? 1 : DARK[col]);
  outline(c, x, y, w, h, quiet ? DARK[col] : col);
  const ink = quiet ? MID[col] : LITE[col];
  if (vertical) [...word].forEach((ch, i) => drawText(c, ch, x + 3, y + 3 + i * 9, ink));
  else drawText(c, word, x + 4, y + 3, ink);
}

function buildScene() {
  const tools = seed => {
    const rnd = visRand(seed);
    return { rnd, ri: (a, b) => a + Math.floor(rnd() * (b - a + 1)), pick: arr => arr[Math.floor(rnd() * arr.length)] };
  };

  const sky = makeLayer(640, SCN_H, c => {
    const { ri } = tools(5);
    R(c, 0, 0, 640, 64, 3); dith(c, 0, 52, 640, 12, 4, 0);
    R(c, 0, 64, 640, 56, 4); dith(c, 0, 110, 640, 10, 5, 1);
    R(c, 0, 120, 640, 58, 5); dith(c, 0, 144, 640, 14, 14, 0);
    R(c, 0, 158, 640, 20, 14); dith(c, 0, 168, 640, 10, 15, 1);
    for (let i = 0; i < 40; i++) R(c, ri(0, 639), ri(0, 56), 1, 1, 6);
  });

  const far = makeLayer(640, SCN_H, c => {
    const { rnd, ri } = tools(11);
    for (let x = 4; x < 600;) {
      const w = ri(16, 40), h = ri(64, 140), y = ROAD_Y - h;
      R(c, x, y, w, h, 2);
      if (rnd() < 0.5) R(c, x + (w >> 1), y - ri(6, 18), 1, 18, 2);
      if (rnd() < 0.4) R(c, x + 3, y - 4, w - 6, 4, 2);
      for (let wy = y + 5; wy < ROAD_Y - 6; wy += 5) for (let wx = x + 3; wx < x + w - 3; wx += 4) {
        if (rnd() < 0.16) R(c, wx, wy, 2, 2, rnd() < 0.25 ? 6 : 4);
      }
      x += w + ri(2, 22);
    }
    // Шпиль — цель всего рейса, виден из любого района.
    const sx = 452;
    R(c, sx, 26, 14, 152, 2); R(c, sx + 3, 12, 8, 14, 2); R(c, sx + 6, 0, 2, 12, 2);
    R(c, sx - 6, 88, 26, 90, 2); R(c, sx - 12, 136, 38, 42, 2);
    for (let y = 32; y < 172; y += 9) R(c, sx + 2, y, 10, 1, 4);
    R(c, sx + 6, 2, 2, 2, 30); R(c, sx + 3, 24, 1, 1, 15); R(c, sx + 10, 24, 1, 1, 15);
  });

  const mid = quiet => makeLayer(640, SCN_H, c => {
    const { rnd, ri, pick } = tools(22);
    for (let x = 0; x < 610;) {
      const w = ri(34, 72), h = ri(48, 108), y = ROAD_Y - h;
      R(c, x, y, w, h, 1);
      R(c, x, y, w, 1, 3);
      const tank = rnd() < 0.6, tx = x + ri(4, w - 14);
      if (tank) { R(c, tx, y - 6, 9, 6, 1); R(c, tx + 4, y - 14, 1, 8, 1); }
      for (let wy = y + 6; wy < ROAD_Y - 8; wy += 7) for (let wx = x + 4; wx < x + w - 5; wx += 6) {
        const a = rnd(), b = rnd(), col = pick([18, 18, 18, 10, 14, 19, 11]);
        if (a < 0.3) { if (!quiet || ((wx + wy) & 1)) R(c, wx, wy, 3, 4, quiet ? DIM[col] : col); }
        else if (b < 0.2) R(c, wx, wy, 3, 4, 2);
      }
      const sign = rnd() < 0.5, sgx = x + ri(4, Math.max(5, w - 40)), sgy = y + ri(10, 30);
      const word = pick(['ОТЕЛЬ', 'ЧИПЫ', 'ЗАЙМ', 'КИБЕР', 'ДОКИ']), col = pick([11, 15, 19]);
      if (sign && w > 44) neonSign(c, sgx, sgy, word, col, false, quiet);
      x += w + ri(0, 10);
    }
  });

  const near = quiet => makeLayer(640, SCN_H, c => {
    const { rnd, ri, pick } = tools(33);
    for (let x = -6; x < 600;) {
      const w = ri(60, 120), h = ri(30, 76), y = ROAD_Y - h;
      R(c, x, y, w, h, 0);
      R(c, x, y, w, 1, 2);
      const col = pick([11, 15, 19]);
      // витрина первого этажа
      R(c, x + 4, ROAD_Y - 22, w - 8, 16, quiet ? 1 : DARK[col]);
      R(c, x + 4, ROAD_Y - 23, w - 8, 1, quiet ? DARK[col] : col);
      for (let wx = x + 8; wx < x + w - 12; wx += 14) {
        R(c, wx, ROAD_Y - 19, 9, 11, quiet ? DARK[col] : MID[col]);
        R(c, wx + 4, ROAD_Y - 19, 1, 11, quiet ? 1 : DARK[col]);
      }
      for (let wy = y + 7; wy < ROAD_Y - 32; wy += 9) for (let wx = x + 6; wx < x + w - 8; wx += 9) {
        const a = rnd(), wc = pick([17, 17, 8, 13, 18]);
        if (a < 0.22) R(c, wx, wy, 4, 5, quiet ? DIM[wc] : wc);
      }
      // вертикальная вывеска — только если целиком помещается над витриной, иначе горизонтальная над крышей
      const word = pick(['ЛАПША', 'БАР', 'РЕМОНТ', 'ТИР', 'ЧАЙ', 'ТАКСИ']), sx = x + ri(6, w - 20), sx2 = x + ri(6, Math.max(7, w - 52));
      if (h >= word.length * 9 + 39) neonSign(c, sx, y + 6, word, col, true, quiet);
      else neonSign(c, sx2, y - 15, word, col, false, quiet);
      x += w + ri(10, 46);
    }
  });

  // Дорога: отбойник, три полосы с пунктирной разметкой, тусклые отражения вывесок.
  const road = makeLayer(640, SCN_H - ROAD_Y + 6, c => {
    const { ri, pick } = tools(44);
    R(c, 0, 2, 640, 1, 24); R(c, 0, 3, 640, 1, 22);
    for (let x = 0; x < 640; x += 16) R(c, x, 2, 1, 5, 22);
    R(c, 0, 6, 640, 52, 21); R(c, 0, 6, 640, 1, 23); R(c, 0, 56, 640, 2, 0);
    for (let i = 0; i < 26; i++) { const x = ri(0, 630); dith(c, x, 8, ri(2, 6), ri(5, 14), pick([13, 8, 17, 2]), x & 1); }
    for (let i = 0; i < 22; i++) R(c, ri(0, 630), ri(10, 54), ri(3, 9), 1, 22);
    for (let x = 0; x < 640; x += 40) { R(c, x, 29, 16, 1, 24); R(c, x + 20, 43, 16, 1, 24); }
  });

  const fg = makeLayer(640, SCN_H, c => {
    [90, 410].forEach(x => {
      R(c, x, 60, 3, 170, 0); R(c, x - 16, 60, 18, 2, 0); R(c, x - 18, 62, 6, 2, 20);
      dith(c, x - 22, 64, 14, 6, 19, 0); dith(c, x - 24, 70, 18, 8, 18, 1);
    });
  });

  SCN = { sky, far, road, fg, mid: mid(false), near: near(false), midQ: mid(true), nearQ: near(true) };
}

function tileLayer(c, img, sx, y) {
  const x = -(((Math.floor(sx) % 640) + 640) % 640);
  c.drawImage(img, x, y);
  c.drawImage(img, x + 640, y);
}

// Рисует город в полосе [top, top+h): низ сцены прижат к низу полосы.
function drawScene(c, top, h, scroll, quiet) {
  const off = top + h - SCN_H;
  c.save();
  c.beginPath(); c.rect(0, top, 640, h); c.clip();
  if (off > top) R(c, 0, top, 640, off - top, 3);
  c.drawImage(SCN.sky, 0, off);
  tileLayer(c, SCN.far, scroll * 0.06, off);
  tileLayer(c, quiet ? SCN.midQ : SCN.mid, scroll * 0.22, off);
  tileLayer(c, quiet ? SCN.nearQ : SCN.near, scroll * 0.5, off);
  tileLayer(c, SCN.road, scroll, off + ROAD_Y - 6);
  c.restore();
  return off;
}

function drawForeground(c, top, h, scroll) {
  c.save();
  c.beginPath(); c.rect(0, top, 640, h); c.clip();
  tileLayer(c, SCN.fg, scroll * 1.5, top + h - SCN_H);
  c.restore();
}

function drawRain(c, top, h, t, thin) {
  const f = Math.floor(t / 40);
  for (let i = 0; i < 70; i += thin ? 3 : 1) {
    const x = (i * 97 + f * (3 + (i % 3))) % 660 - 10, y = (i * 53 + f * (9 + (i % 5))) % h;
    R(c, 640 - x, top + y, 1, 3, 6);
    if (y + 5 < h) R(c, 639 - x, top + y + 3, 1, 2, 5);
  }
}

// ---------- спрайты с цветным контуром ----------

// Спрайт рисуется один раз во внеэкранный холст, обводится контуром в 1 пиксель и кешируется.
const SPR_CACHE = {};
function rimmed(key, w, h, pad, rim, draw) {
  let s = SPR_CACHE[key];
  if (s) return s;
  s = document.createElement('canvas');
  s.width = w + 2; s.height = h + pad + 2;
  const g = s.getContext('2d');
  draw(g, 1, h + pad + 1);
  const d = g.getImageData(0, 0, s.width, s.height).data, W2 = s.width, H2 = s.height;
  const on = (x, y) => x >= 0 && y >= 0 && x < W2 && y < H2 && d[(y * W2 + x) * 4 + 3] > 0;
  g.fillStyle = PAL[rim];
  for (let y = 0; y < H2; y++) for (let x = 0; x < W2; x++) {
    if (!on(x, y) && (on(x - 1, y) || on(x + 1, y) || on(x, y - 1) || on(x, y + 1))) g.fillRect(x, y, 1, 1);
  }
  SPR_CACHE[key] = s;
  return s;
}

function wheel(c, x, y, f, d) {
  const e = d - 3;
  R(c, x + 3, y, d - 6, d, 0); R(c, x, y + 3, d, d - 6, 0); R(c, x + 1, y + 1, d - 2, d - 2, 0);
  R(c, x + (d >> 1) - 2, y + (d >> 1) - 2, 4, 4, 23);
  if (f & 1) R(c, x + (d >> 1) - 1, y + 2, 2, e - 1, 22); else R(c, x + 2, y + (d >> 1) - 1, e - 1, 2, 22);
  R(c, x + (d >> 1) - 1, y + (d >> 1) - 1, 2, 2, 25);
}

function rawCar(c, x, y, f, moving) {
  const o = y - 32 - (moving && (f & 2) ? 1 : 0), P = (dx, dy, w, h, i) => R(c, x + dx, o + dy, w, h, i);
  P(3, 15, 90, 11, 10); P(3, 23, 90, 3, 9); P(4, 15, 88, 1, 11);
  P(1, 21, 3, 3, 24); P(92, 21, 3, 3, 24);
  P(26, 6, 34, 9, 10); P(27, 6, 32, 1, 11);
  P(23, 9, 3, 6, 10); P(21, 12, 2, 3, 10);
  P(60, 8, 2, 7, 10); P(62, 10, 2, 5, 10); P(64, 12, 2, 3, 10);
  P(62, 14, 31, 1, 11);
  P(28, 8, 14, 6, 1); P(44, 8, 14, 6, 1); P(30, 9, 4, 1, 9); P(46, 9, 4, 1, 9);
  P(59, 9, 2, 5, 8); P(61, 11, 2, 3, 8);
  P(43, 15, 1, 9, 9); P(47, 17, 4, 1, 9);
  P(3, 19, 90, 1, 12);
  P(92, 16, 2, 3, 20); P(2, 16, 2, 3, 15);
  P(12, 19, 16, 7, 8); P(66, 19, 16, 7, 8);
  P(6, 10, 15, 5, 22); P(6, 10, 15, 1, 24);
  P(8, 12, 1, 1, 11); P(11, 12, 1, 1, 11); P(14, 12, 1, 1, f & 2 ? 12 : 9); P(17, 12, 1, 1, 15);
  P(21, 13, 3, 1, 0);
  P(30, 4, 26, 1, 24); P(31, 5, 1, 1, 23); P(54, 5, 1, 1, 23);
  P(34, 1, 9, 3, 18); P(34, 1, 9, 1, 19); P(45, 2, 7, 2, 14); P(45, 2, 7, 1, 15);
  wheel(c, x + 14, y - 12, moving ? f : 0, 12); wheel(c, x + 68, y - 12, moving ? f : 0, 12);
}

// Машина игрока: старый седан с батареей на багажнике. x — левый край, y — линия полосы.
function sprCar(c, x, y, f, moving) {
  const ph = f & 3;
  c.drawImage(rimmed('car' + ph + (moving ? 'm' : 's'), 96, 33, 0, 12, (g, ox, oy) => rawCar(g, ox, oy, ph, moving)), x - 1, y - 34);
  // свет фар дизерингом
  c.fillStyle = PAL[19];
  for (let dx = 0; dx < 38; dx++) {
    const hh = 1 + (dx >> 3);
    for (let dy = -hh; dy <= hh; dy++) if ((dx + dy) & 1 && dx % 3 !== 0) c.fillRect(x + 96 + dx, y - 15 + dy, 1, 1);
  }
}

// Размеры спрайтов врагов: [ширина, высота].
const SPR_SIZE = { biker: [34, 26], patrol: [68, 26], drone: [24, 16], jammer: [66, 34], swarm: [28, 20], boss: [92, 40] };

function rawEnemy(c, type, x, y, f, hp) {
  const h = SPR_SIZE[type][1], o = y - h, P = (dx, dy, pw, ph, i) => R(c, x + dx, o + dy, pw, ph, i);
  switch (type) {
    case 'biker':
      wheel(c, x + 1, y - 10, f, 10); wheel(c, x + 23, y - 10, f, 10);
      P(8, 17, 16, 2, 24); P(11, 14, 8, 6, 23); P(13, 11, 9, 3, 15); P(6, 12, 8, 2, 22);
      P(25, 9, 2, 10, 24); P(23, 8, 4, 1, 25); P(27, 11, 2, 2, 20); P(4, 13, 2, 1, 30);
      P(12, 4, 6, 8, 15); P(12, 4, 6, 1, 16); P(17, 6, 7, 2, 15); P(23, 7, 2, 2, 31);
      P(13, 0, 6, 5, 22); P(16, 2, 3, 2, 16); P(10, 11, 4, 6, 14); P(12, 17, 4, 2, 22);
      break;
    case 'patrol':
      P(2, 10, 64, 10, 25); P(2, 17, 64, 3, 23); P(2, 14, 64, 2, 4);
      P(18, 3, 28, 8, 25); P(15, 6, 3, 5, 25); P(46, 6, 3, 5, 25); P(49, 8, 2, 3, 25);
      P(20, 5, 11, 5, 1); P(33, 5, 11, 5, 1); P(46, 6, 2, 4, 8);
      P(26, 0, 12, 3, 21); P(26, 0, 6, 2, f & 1 ? 30 : 29); P(32, 0, 6, 2, f & 1 ? 9 : 11);
      P(64, 11, 2, 3, 20); P(2, 11, 2, 3, 30); P(0, 16, 2, 3, 23); P(66, 16, 2, 3, 23);
      P(8, 12, 16, 8, 23); P(46, 12, 16, 8, 23);
      wheel(c, x + 10, y - 12, f, 12); wheel(c, x + 48, y - 12, f, 12);
      break;
    case 'drone':
      P(f & 1 ? 0 : 2, 1, f & 1 ? 8 : 4, 1, 25); P(f & 1 ? 16 : 18, 1, f & 1 ? 8 : 4, 1, 25);
      P(3, 2, 2, 3, 23); P(19, 2, 2, 3, 23);
      P(4, 5, 16, 7, 24); P(5, 4, 14, 1, 25); P(4, 11, 16, 1, 23);
      P(8, 7, 8, 3, 0); P(9 + f, 8, 3, 1, 19);
      P(6, 12, 2, 3, 24); P(16, 12, 2, 3, 24); P(5, 15, 2, 1, 24); P(17, 15, 2, 1, 24);
      break;
    case 'jammer':
      P(2, 6, 46, 22, 5); P(2, 6, 46, 1, 7); P(2, 27, 62, 1, 3);
      P(48, 12, 16, 16, 5); P(48, 12, 16, 1, 7); P(54, 14, 9, 6, 8); P(56, 15, 4, 1, 10);
      P(64, 24, 2, 3, 24); P(62, 21, 2, 2, 20); P(2, 20, 62, 2, 15);
      P(10, 10, 1, 6, 16); P(13, 9, 1, 8, 16); P(16, 10, 1, 6, 16); P(24, 10, 14, 7, 2); P(26, 12, 10, 1, 15); P(26, 14, 6, 1, 14);
      P(18, 2, 14, 2, 25); P(22, 4, 6, 1, 24); P(24, 5, 2, 1, 23); P(24, 0, 2, 2, 25);
      if (f & 2) { dith(c, x + 12, o - 4, 26, 2, 15, 0); dith(c, x + 16, o - 8, 18, 2, 14, 1); }
      P(7, 21, 16, 7, 1); P(44, 21, 16, 7, 1);
      wheel(c, x + 9, y - 12, f, 12); wheel(c, x + 46, y - 12, f, 12);
      break;
    case 'swarm': {
      const ox = [0, 12, 22, 5, 16], oy = [5, 0, 7, 14, 12];
      for (let k = 0; k < hp; k++) {
        const px = x + ox[k], py = o + oy[k] + ((f + k) & 1);
        R(c, px - 1, py - 1, 7, 1, (f + k) & 1 ? 25 : 24); R(c, px, py, 5, 3, 24); R(c, px + 2, py + 1, 1, 1, 15);
      }
      break;
    }
    case 'boss':
      P(2, 10, 70, 20, 23); P(2, 10, 70, 1, 25); P(2, 29, 88, 1, 0);
      P(24, 11, 1, 18, 21); P(48, 11, 1, 18, 21); P(6, 14, 1, 1, 25); P(20, 14, 1, 1, 25); P(28, 14, 1, 1, 25); P(44, 14, 1, 1, 25);
      P(72, 16, 18, 14, 23); P(72, 16, 18, 1, 25); P(78, 18, 10, 3, 13); P(79, 19, 8, 1, 15);
      P(88, 24, 4, 6, 24); P(2, 24, 88, 2, 15); P(4, 12, 3, 2, f & 1 ? 16 : 14);
      P(30, 2, 20, 8, 24); P(30, 2, 20, 1, 26); P(10, 5, 20, 2, 24); P(8, 4, 3, 4, 25); P(44, 4, 3, 2, 15);
      drawText(c, 'КПП', x + 52, o + 14, 0);
      P(5, 26, 16, 4, 0); P(27, 26, 16, 4, 0); P(67, 26, 16, 4, 0);
      wheel(c, x + 7, y - 12, f, 12); wheel(c, x + 29, y - 12, f, 12); wheel(c, x + 69, y - 12, f, 12);
      break;
  }
}

// Враг: x — левый край, y — низ спрайта. Контур мадженты — «это угроза».
function sprEnemy(c, type, x, y, f, e) {
  const [w, h] = SPR_SIZE[type], ph = f & 3, hp = e ? e.hp : 5, pad = type === 'jammer' ? 8 : 0;
  const key = type + ph + (type === 'swarm' ? 'x' + hp : '');
  c.drawImage(rimmed(key, w, h, pad, 15, (g, ox, oy) => rawEnemy(g, type, ox, oy, ph, hp)), x - 1, y - h - pad - 1);
  return [w, h];
}

// То, что лежит на полосах. x — центр, y — линия полосы. Плохое — маджента, полезное — циан и янтарь.
function sprObject(c, kind, x, y, f) {
  const key = kind + (f & 1);
  const s = rimmed(key, 24, 20, 0, kind === 'cell' ? 12 : kind === 'chip' ? 20 : 16, (g, ox, oy) => {
    const P = (dx, dy, w, h, i) => R(g, ox + dx, oy - 20 + dy, w, h, i);
    if (kind === 'debris') {
      P(1, 7, 22, 9, 0); P(2, 8, 20, 7, 15);
      for (let k = 0; k < 4; k++) P(3 + k * 5, 8, 2, 7, 0);
      P(3, 16, 3, 4, 22); P(18, 16, 3, 4, 22); P(10, 3, 4, 4, f & 1 ? 16 : 14); P(11, 2, 2, 1, 25);
    } else if (kind === 'cam') {
      P(1, 6, 4, 14, 22); P(2, 7, 2, 12, 24); P(19, 6, 4, 14, 22); P(20, 7, 2, 12, 24);
      P(0, 3, 6, 4, 0); P(18, 3, 6, 4, 0); P(2, 4, 2, 2, 30); P(20, 4, 2, 2, 30);
      dith(g, ox + 5, oy - 12, 14, 7, 15, f & 1); R(g, ox + 5, oy - 9, 14, 1, 16);
    } else if (kind === 'cell') {
      const b = f & 1;
      P(7, 5 - b, 10, 13, 22); P(8, 6 - b, 8, 11, 0); P(10, 3 - b, 4, 2, 24);
      P(9, 7 - b, 6, 4, 11); P(9, 12 - b, 6, 4, 11); P(10, 8 - b, 2, 1, 12);
    } else {
      const b = f & 1;
      P(7, 7 - b, 10, 10, 19); P(8, 8 - b, 8, 8, 17); P(10, 10 - b, 4, 4, 20);
      P(9, 5 - b, 1, 2, 19); P(12, 5 - b, 1, 2, 19); P(15, 5 - b, 1, 2, 19);
      P(9, 17 - b, 1, 2, 19); P(12, 17 - b, 1, 2, 19); P(15, 17 - b, 1, 2, 19);
    }
  });
  c.drawImage(s, x - 13, y - 21);
}

// ---------- портреты 32×32 ----------

function portrait(c, x, y, id) {
  const P = (dx, dy, w, h, i) => R(c, x + dx, y + dy, w, h, i);
  const bg = { hacker: 8, surgeon: 2, guard: 21, mechanic: 17, musician: 13, android: 1 }[id];
  const cloth = { hacker: 4, surgeon: 25, guard: 22, mechanic: 18, musician: 14, android: 23 }[id];
  const skin = id === 'android' ? 7 : 31, shade = id === 'android' ? 6 : 18;
  P(0, 0, 32, 32, bg);
  P(5, 25, 22, 7, cloth); P(8, 23, 16, 2, cloth);
  P(13, 20, 6, 4, shade);
  P(10, 8, 12, 12, skin); P(11, 7, 10, 1, skin); P(11, 20, 10, 1, skin);
  P(12, 13, 2, 2, 0); P(18, 13, 2, 2, 0); P(14, 18, 4, 1, 29);
  switch (id) {
    case 'hacker':
      P(8, 3, 16, 5, 4); P(7, 6, 3, 18, 4); P(22, 6, 3, 18, 4); P(10, 8, 12, 2, 3);
      P(11, 12, 10, 3, 0); P(12, 13, 8, 1, 11); P(18, 13, 2, 1, 12); P(9, 3, 14, 1, 5);
      break;
    case 'surgeon':
      P(10, 4, 12, 4, 10); P(9, 8, 14, 1, 9); P(11, 16, 10, 5, 25); P(11, 16, 10, 1, 24);
      P(10, 17, 1, 1, 24); P(21, 17, 1, 1, 24); P(15, 26, 2, 5, 30); P(13, 28, 6, 1, 30);
      break;
    case 'guard':
      P(9, 3, 14, 8, 23); P(9, 3, 14, 1, 24); P(10, 11, 12, 4, 17); P(11, 12, 10, 2, 19); P(18, 12, 2, 1, 20);
      P(11, 19, 10, 2, 22); P(3, 24, 7, 4, 23); P(22, 24, 7, 4, 23); P(3, 24, 7, 1, 24); P(22, 24, 7, 1, 24);
      break;
    case 'mechanic':
      P(10, 5, 12, 4, 30); P(22, 7, 3, 2, 30); P(10, 5, 12, 1, 29);
      P(11, 17, 10, 4, 17); P(14, 18, 4, 1, 31); P(10, 25, 2, 7, 17); P(20, 25, 2, 7, 17); P(12, 28, 8, 1, 17);
      break;
    case 'musician':
      P(9, 4, 14, 5, 15); P(8, 6, 3, 9, 15); P(21, 6, 3, 5, 15); P(19, 2, 5, 3, 16); P(9, 4, 14, 1, 16);
      P(8, 2, 16, 1, 0); P(6, 10, 3, 7, 0); P(23, 10, 3, 7, 0); P(6, 12, 1, 3, 11); P(25, 12, 1, 3, 11);
      P(13, 27, 6, 1, 16);
      break;
    case 'android':
      P(16, 7, 1, 14, 6); P(12, 13, 3, 2, 11); P(18, 13, 3, 2, 11); P(13, 13, 1, 1, 12); P(19, 13, 1, 1, 12);
      P(15, 9, 2, 2, 15); P(14, 18, 4, 1, 6); P(13, 20, 6, 4, 22); P(14, 21, 1, 3, 11); P(17, 21, 1, 3, 11);
      P(10, 19, 12, 1, 6); P(5, 25, 22, 1, 24);
      break;
  }
}

// ---------- значки ----------

const ICONS = {
  road:  ['..#####..', '.#######.', '##.###.##', '##.###.##', '#########', '.###.###.', '..#####..', '..#.#.#..'],
  hitch: ['...###...', '...###...', '....#....', '..#####..', '.#.###.#.', '...###...', '...#.#...', '..##.##..'],
  shop:  ['.##......', '#..#.....', '#.##.....', '.####....', '...###...', '....###..', '.....###.', '......##.'],
  gate:  ['#########', '#.#.#.#.#', '#########', '.#.....#.', '.#.....#.', '.#.....#.', '.#.....#.', '###...###'],
  start: ['....#....', '...###...', '..#####..', '.#######.', '.##...##.', '.##...##.', '.##...##.', '.##...##.'],
  park:  ['.######..', '.##...##.', '.##...##.', '.######..', '.##......', '.##......', '.##......', '.##......'],
  meet:  ['..####...', '.##..##..', '.....##..', '....##...', '...##....', '...##....', '.........', '...##....'],
  hidden:['.........', '.........', '.........', '.#..#..#.', '.........', '.........', '.........', '.........'],
};

// Значок 9×8, k — целочисленный масштаб.
function drawIcon(c, name, x, y, color, k) {
  k = k || 1;
  c.fillStyle = PAL[color];
  ICONS[name].forEach((row, yy) => { for (let xx = 0; xx < row.length; xx++) if (row[xx] === '#') c.fillRect(x + xx * k, y + yy * k, k, k); });
}

// Значок предмета 12×12, k — целочисленный масштаб.
function itemIcon(c, id, x, y, k) {
  const P = (dx, dy, w, h, i) => R(c, x + dx * k, y + dy * k, w * k, h * k, i);
  switch (id) {
    case 'cell':   P(3, 2, 6, 9, 22); P(5, 1, 2, 1, 24); P(4, 4, 4, 2, 11); P(4, 7, 4, 2, 11); break;
    case 'patch':  P(2, 3, 8, 6, 25); P(5, 4, 2, 4, 30); P(4, 5, 4, 2, 30); break;
    case 'stim':   P(5, 1, 2, 8, 25); P(4, 3, 4, 4, 15); P(6, 9, 1, 3, 24); P(3, 1, 6, 1, 24); break;
    case 'emp':    P(3, 4, 6, 6, 22); P(5, 2, 2, 2, 24); P(7, 1, 2, 2, 19); P(3, 6, 6, 1, 11); P(4, 8, 4, 1, 11); break;
    case 'smoke':  P(4, 3, 5, 8, 23); P(5, 2, 3, 1, 24); P(4, 6, 5, 2, 7); P(2, 0, 3, 2, 24); P(6, 0, 2, 1, 24); break;
    case 'kit':    P(1, 4, 10, 6, 30); P(4, 2, 4, 2, 29); P(5, 6, 2, 2, 25); P(1, 4, 10, 1, 16); break;
    case 'food':   P(3, 2, 6, 9, 18); P(3, 4, 6, 2, 19); P(4, 8, 4, 1, 20); break;
    case 'scrap':  P(2, 2, 8, 8, 23); P(4, 4, 4, 4, 21); P(5, 0, 2, 2, 23); P(5, 10, 2, 2, 23); P(0, 5, 2, 2, 23); P(10, 5, 2, 2, 23); break;
    case 'chip':   P(2, 3, 8, 6, 27); P(3, 1, 1, 2, 24); P(6, 1, 1, 2, 24); P(8, 1, 1, 2, 24); P(3, 9, 1, 2, 24); P(6, 9, 1, 2, 24); P(8, 9, 1, 2, 24); P(4, 5, 4, 2, 28); break;
    case 'contra': P(1, 2, 10, 9, 17); P(1, 2, 10, 1, 18); P(1, 6, 10, 1, 18); P(5, 2, 2, 9, 18); break;
    case 'case':   P(1, 3, 10, 7, 22); P(1, 3, 10, 1, 24); P(4, 1, 4, 2, 23); P(5, 6, 2, 2, 19); P(2, 8, 8, 1, 15); break;
    case 'tools':  P(1, 3, 10, 7, 25); P(4, 1, 4, 2, 24); P(5, 5, 2, 4, 30); P(4, 6, 4, 2, 30); break;
  }
}
