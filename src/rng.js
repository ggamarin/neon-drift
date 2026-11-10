'use strict';
// Детерминированный ГСЧ (mulberry32). Состояние лежит в s.rng,
// поэтому заезд полностью воспроизводится по сиду и логу действий.
function rngNext(s) {
  let t = (s.rng = (s.rng + 0x6d2b79f5) >>> 0);
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
function rngInt(s, n) { return Math.floor(rngNext(s) * n); }
function rngPick(s, arr) { return arr[rngInt(s, arr.length)]; }
