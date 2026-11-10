// Боты для headless-прогонов: случайный (ищет падения и зависания)
// и жадный (грубая оценка баланса).
const G = require('./load');

function mulberry(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), a | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function battleCandidates(s) {
  const out = [];
  ['gun', 'ram', 'hack', 'pull', 'push'].forEach(type => {
    G.battleTargets(s, { type }).forEach(target => out.push({ type, target }));
  });
  s.crew.forEach((c, crew) => {
    const a = { type: 'skill', crew };
    if (G.CREW[c.id].target) G.battleTargets(s, a).forEach(target => out.push({ type: 'skill', crew, target }));
    else if (!G.battleWhy(s, a)) out.push(a);
  });
  [0, 1, 2].forEach(slot => { if (!G.battleWhy(s, { type: 'item', slot })) out.push({ type: 'item', slot }); });
  if (!G.battleWhy(s, { type: 'escape' })) out.push({ type: 'escape' });
  out.push({ type: 'endTurn' });
  return out;
}

// Все действия, которые имеет смысл пробовать на текущем экране.
function candidates(s) {
  const out = [];
  const trunk = () => {
    s.trunk.forEach(t => {
      out.push({ type: 'use', uid: t.uid }, { type: 'drop', uid: t.uid }, { type: 'stow', uid: t.uid, slot: 0 },
               { type: 'place', uid: t.uid, x: 0, y: 0, r: 1 });
    });
    out.push({ type: 'unstow', slot: 0 }, { type: 'useGlove', slot: 1 });
  };
  switch (s.screen) {
    case 'title': out.push({ type: 'start' }); break;
    case 'map':
      s.map.nodes[s.at].next.forEach(to => Object.keys(G.MODES).forEach(mode => {
        for (let k = 0; k < 4; k++) out.push({ type: 'travel', to, mode });
      }));
      trunk();
      break;
    case 'drive': out.push({ type: 'arrive' }); break;
    case 'event': G.eventView(s).options.forEach((o, i) => { if (o.ok) out.push({ type: 'choose', i }); }); break;
    case 'battle': return battleCandidates(s);
    case 'park':
      out.push({ type: 'rest' }, { type: 'charge' }, { type: 'repair' }, { type: 'leave' }, { type: 'leave' });
      s.crew.forEach((c, crew) => out.push({ type: 'talk', crew }));
      break;
    case 'shop':
      G.SHOP_ITEMS.forEach(item => out.push({ type: 'buy', item }));
      Object.keys(G.UPGRADES).forEach(id => out.push({ type: 'upgrade', id }));
      s.trunk.forEach(t => out.push({ type: 'sell', uid: t.uid }));
      out.push({ type: 'leave' }, { type: 'leave' }, { type: 'leave' });
      break;
    case 'result': out.push({ type: 'continue' }); break;
  }
  return out;
}

function randomPolicy(rand) {
  return s => { const c = candidates(s); return c[Math.floor(rand() * c.length)]; };
}

// Жадный бот: не оптимален, но играет осмысленно.
function greedyPolicy(rand) {
  return s => {
    const r = s.res;
    const usable = (id, k, below) => G.ITEMS[id].use && G.ITEMS[id].use[k] && r[k] <= below;
    if (['map', 'park', 'shop'].includes(s.screen)) {
      for (const t of s.trunk) {
        if (usable(t.id, 'hull', 6) || usable(t.id, 'charge', 4) || usable(t.id, 'focus', 4)) return { type: 'use', uid: t.uid };
      }
      const free = s.glove.indexOf(null);
      const small = s.trunk.find(t => G.ITEMS[t.id].small && G.ITEMS[t.id].battle);
      if (free >= 0 && small) return { type: 'stow', uid: small.uid, slot: free };
    }
    switch (s.screen) {
      case 'title': return { type: 'start' };
      case 'map': {
        const next = s.map.nodes[s.at].next;
        const low = r.hull <= 6 || r.focus <= 4;
        const pick = next.find(id => low && ['park', 'shop', 'meet'].includes(s.map.nodes[id].type)) ?? next[Math.floor(rand() * next.length)];
        return { type: 'travel', to: pick, mode: r.wanted >= 4 && r.charge > 5 ? 'quiet' : r.charge <= 4 ? 'eco' : 'fast' };
      }
      case 'drive': return { type: 'arrive' };
      case 'event': {
        const ok = G.eventView(s).options.map((o, i) => (o.ok ? i : -1)).filter(i => i >= 0);
        return { type: 'choose', i: ok[Math.floor(rand() * ok.length)] };
      }
      case 'result': return { type: 'continue' };
      case 'park':
        if (!s.park.rested && r.focus <= 6) return { type: 'rest' };
        if (r.hull <= 8 && r.credits >= 20) return { type: 'repair' };
        if (r.charge <= 7 && r.credits >= 15) return { type: 'charge' };
        return { type: 'leave' };
      case 'shop': {
        const loot = s.trunk.find(t => G.ITEMS[t.id].sell);
        if (loot) return { type: 'sell', uid: loot.uid };
        if (!s.up.guns && r.credits >= 60) return { type: 'upgrade', id: 'guns' };
        if (!s.up.armor && r.credits >= 90) return { type: 'upgrade', id: 'armor' };
        if (s.glove.includes(null) && r.credits >= 45 && G.findSpot(s, 'patch')) return { type: 'buy', item: 'patch' };
        return { type: 'leave' };
      }
      case 'battle': {
        const b = s.battle, cs = battleCandidates(s);
        const has = f => cs.find(f);
        const danger = b.enemies.reduce((a, e) => {
          if (e.hp <= 0) return a;
          const it = G.intentOf(s, e);
          return a + (it.k === 'hit' && it.res === 'hull' ? it.n : 0);
        }, 0);
        const sk = id => has(a => a.type === 'skill' && s.crew[a.crew].id === id);
        if (sk('musician')) return sk('musician');
        if (danger >= 3 && danger > b.shield && sk('guard')) return sk('guard');
        if (r.hull <= 6 && sk('mechanic')) return sk('mechanic');
        if (r.focus <= 4 && sk('surgeon')) return sk('surgeon');
        const item = has(a => a.type === 'item' && (
          (s.glove[a.slot] === 'patch' && r.hull <= 5) || (s.glove[a.slot] === 'smoke' && danger - b.shield >= 4) ||
          (s.glove[a.slot] === 'stim' && r.focus <= 5) || (s.glove[a.slot] === 'emp' && G.living(b).length >= 2) ||
          (s.glove[a.slot] === 'cell' && r.charge <= 2)));
        if (item) return item;
        if (!b.boss && r.hull <= 3 && has(a => a.type === 'escape')) return { type: 'escape' };
        const hp = a => b.enemies[a.target].hp;
        const byHp = (x, y) => hp(x) - hp(y);
        // последнее ОД хода — на то, чтобы оттеснить самого опасного: его удар сменится сближением
        const heavyHit = a => {
          const e = b.enemies[a.target], it = G.intentOf(s, e);
          return it.k === 'hit' && it.res === 'hull' && it.n >= 4 && r.charge > (G.ENEMIES[e.type].heavy ? 2 : 1);
        };
        const dodge = cs.filter(a => a.type === 'push').find(heavyHit);
        if (dodge && b.ap === 1 && danger > b.shield) return dodge;
        const ram = cs.filter(a => a.type === 'ram').sort(byHp)[0];
        if (ram && r.hull > 4 && hp(ram) >= 3) return ram;
        const gun = cs.filter(a => a.type === 'gun').sort(byHp)[0];
        if (gun) return gun;
        const hack = cs.filter(a => a.type === 'hack' && G.ENEMIES[b.enemies[a.target].type].tech).sort(byHp)[0];
        if (hack && r.focus >= 4) return hack;
        const pull = cs.filter(a => a.type === 'pull').sort(byHp)[0];
        if (pull && !gun && r.charge >= 3 && b.ap >= 2) return pull;
        return { type: 'endTurn' };
      }
    }
    return null;
  };
}

// Гоняет заезд до конца. Возвращает состояние и лог применённых действий.
function playRun(seed, policy, opts = {}) {
  const maxSteps = opts.maxSteps || 4000;
  const s = G.newRun(seed), log = [];
  let steps = 0;
  while (s.screen !== 'end' && steps++ < maxSteps) {
    const a = policy(s);
    if (!a) throw new Error('Бот не нашёл действия на экране ' + s.screen);
    if (G.act(s, a)) { log.push(a); if (opts.onStep) opts.onStep(s, a); }
  }
  return { s, log, finished: s.screen === 'end' };
}

module.exports = { G, mulberry, candidates, randomPolicy, greedyPolicy, playRun };
