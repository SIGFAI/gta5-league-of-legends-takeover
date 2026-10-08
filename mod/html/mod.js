(function () {
  var root = document.getElementById('mod');
  root.innerHTML = "<div id=\"sr-wrap\">\n  <div id=\"sr-gray\"><\/div>\n  <div id=\"sr-top\">\n    <div class=\"nx b\"><div class=\"fill\" id=\"sr-nbf\"><\/div><div class=\"gloss\"><\/div><span><i>ORDER NEXUS<\/i><em id=\"sr-nbt\" style=\"font-style:normal\"><\/em><\/span><\/div>\n    <div id=\"sr-score\"><b id=\"sr-kb\">0<\/b><div id=\"sr-tm\">0:00<\/div><b id=\"sr-kr\">0<\/b><\/div>\n    <div class=\"nx r\"><div class=\"fill\" id=\"sr-nrf\"><\/div><div class=\"gloss\"><\/div><span><i>VOID NEXUS<\/i><em id=\"sr-nrt\" style=\"font-style:normal\"><\/em><\/span><\/div>\n  <\/div>\n  <div id=\"sr-banner\"><\/div>\n  <div id=\"sr-feed\"><\/div>\n  <div id=\"sr-resp\"><\/div>\n  <div id=\"sr-lvflash\"><\/div>\n  <div id=\"sr-lvtxt\">LEVEL UP<\/div>\n  <div id=\"sr-buff\"><div class=\"ic\"><\/div><div><div class=\"nm\" id=\"sr-bn\"><\/div><div class=\"sc\" id=\"sr-bs\"><\/div><\/div><\/div>\n  <div id=\"sr-shophint\">SHOP - press <kbd>B<\/kbd><\/div>\n  <div id=\"sr-panel\">\n    <div class=\"sr-port\">\n      <svg viewBox=\"0 0 100 100\"><circle cx=\"50\" cy=\"50\" r=\"46\" fill=\"#050a14\" stroke=\"#1a2740\" stroke-width=\"5\"/><circle id=\"sr-xpr\" cx=\"50\" cy=\"50\" r=\"46\" fill=\"none\" stroke=\"#b66bff\" stroke-width=\"5\" stroke-linecap=\"butt\" stroke-dasharray=\"289 289\" stroke-dashoffset=\"289\" style=\"transition: stroke-dashoffset .3s\"/><\/svg>\n      <div class=\"img\"><img id=\"sr-pimg\" src=\"../../img/portrait_aurelia.png\" alt=\"\"><\/div>\n      <div class=\"lv\" id=\"sr-lv\">1<\/div>\n    <\/div>\n    <div class=\"sr-mid\">\n      <div class=\"sr-nm\"><span class=\"n\" id=\"sr-cn\">AURELIA<\/span><span class=\"sr-gold\" id=\"sr-gd\"><span class=\"sr-coin\"><\/span><b style=\"font-weight:normal\" id=\"sr-gdn\">0<\/b><\/span><\/div>\n      <div class=\"sr-hp\" id=\"sr-hp\"><div class=\"trail\" id=\"sr-hpt\"><\/div><div class=\"f\" id=\"sr-hpf\"><\/div><div class=\"ticks\"><\/div><div class=\"gl\"><\/div><div class=\"t\" id=\"sr-hpx\"><\/div><\/div>\n      <div class=\"sr-xp\"><i id=\"sr-xpb\"><\/i><\/div>\n      <div class=\"sr-stats\" id=\"sr-stats\"><\/div>\n    <\/div>\n    <div class=\"sr-abil\" id=\"sr-ab\"><\/div>\n    <div class=\"sr-right\"><div class=\"sr-items\" id=\"sr-items\"><\/div><\/div>\n  <\/div>\n  <div id=\"sr-map\"><canvas id=\"sr-cv\"><\/canvas><\/div>\n  <div id=\"sr-shop\"><div class=\"hd\"><span class=\"tt\">ITEM SHOP<\/span><span class=\"sg\"><span class=\"sr-coin\"><\/span><b style=\"font-weight:normal\" id=\"sr-sg\">0<\/b><\/span><\/div><div class=\"grid\" id=\"sr-sgrid\"><\/div><div class=\"ft\">Press the key in the corner of an item to buy it.   Press B to close.<\/div><\/div>\n  <div id=\"sr-title\"><div class=\"big\" id=\"sr-tb\"><\/div><div class=\"ln\"><\/div><div class=\"small\" id=\"sr-ts\"><\/div><\/div>\n  <div id=\"sr-end\"><span id=\"sr-endt\"><\/span><\/div>\n<\/div>";
  var $ = function (id) { return document.getElementById(id); };
  (function () {
    var r = document.createElement('div');
    r.id = 'sr-roster';
    document.getElementById('sr-wrap').appendChild(r);
  })();
  (function () {
    var q = document.createElement('div');
    q.id = 'sr-quest';
    q.innerHTML = '<div class="qh" id="sr-qh"></div><div class="qt" id="sr-qt"></div><div class="qb"><i id="sr-qf"></i></div>';
    document.getElementById('sr-wrap').appendChild(q);
  })();
  var IMG = '../../img/';
  var QW = ['q', 'w', 'e', 'r'];
  var ANAME = { q: 'STARBOLT', w: 'AEGIS', e: 'PHASE', r: 'STARFALL' };
  var gold = 0;
  var lastAbil = '';
  function hueOf(c) { var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255, mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, h = 0; if (d) { if (mx === r) h = ((g - b) / d) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4; } h = Math.round(h * 60); return h < 0 ? h + 360 : h; }
  var lastItems = '';
  var shopState = null;
  var cdPrev = { q: 0, w: 0, e: 0, r: 0 };
  var timers = {};
  function later(k, fn, ms) { clearTimeout(timers[k]); timers[k] = setTimeout(fn, ms); }
  function restart(el, cls) { el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls); }
  function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
  function num(x, d) { x = Number(x); return isFinite(x) ? x : (d || 0); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  // ability slots
  var ab = $('sr-ab');
  QW.forEach(function (k) {
    var d = document.createElement('div');
    d.className = 'sr-slot ready'; d.id = 'sr-s' + k;
    d.innerHTML = '<img src="' + IMG + 'icon_' + k + '.png" alt=""><div class="sw"></div><div class="ct"></div><div class="key">' + k.toUpperCase() + '</div><div class="an">' + ANAME[k] + '</div>';
    ab.appendChild(d);
  });
  // item slots
  var itemsEl = $('sr-items');
  var itemSlots = [];
  for (var i = 0; i < 6; i++) { var s = document.createElement('div'); s.className = 'sr-it'; itemsEl.appendChild(s); itemSlots.push(s); }

  function fmtTime(t) { var s = Math.max(0, Math.floor(num(t))); return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }

  function setItems(arr) {
    var key = arr.join(',');
    var old = lastItems ? lastItems.split(',') : [];
    lastItems = key;
    for (var i = 0; i < 6; i++) {
      var id = arr[i], el = itemSlots[i];
      if (id) {
        el.className = 'sr-it has' + (old[i] !== String(id) && old.length ? ' new' : '');
        el.innerHTML = '<img src="' + IMG + 'icon_item_' + id + '.png" alt="" onerror="this.style.visibility=\'hidden\'">';
      } else { el.className = 'sr-it'; el.innerHTML = ''; }
    }
  }

  function handleHud(h) {
    if (h.gold != null) { gold = num(h.gold); $('sr-gdn').textContent = Math.floor(gold); refreshShop(); }
    if (h.lv != null) $('sr-lv').textContent = h.lv;
    if (h.xp != null) $('sr-xpr').style.strokeDashoffset = 289 * (1 - clamp01(num(h.xp)));
    if (h.xp != null) $('sr-xpb').style.width = (100 * clamp01(num(h.xp))) + '%';
    if (h.name) {
      var nm = String(h.name).toUpperCase();
      if ($('sr-cn').textContent !== nm) { $('sr-cn').textContent = nm; $('sr-pimg').src = IMG + 'portrait_' + String(h.cid || nm).toLowerCase() + '.png'; }
    }
    if (h.abil && h.abil.length === 4) {
      var sig = h.abil.join('|') + '|' + (h.col || []).join(',');
      if (sig !== lastAbil) {
        lastAbil = sig;
        var hue = h.col ? hueOf(h.col) - 210 : 0;
        QW.forEach(function (k, i) {
          var sl = $('sr-s' + k);
          sl.querySelector('.an').textContent = String(h.abil[i]).split(':')[0].toUpperCase();
          sl.querySelector('img').style.filter = 'hue-rotate(' + hue + 'deg) saturate(1.1)';
        });
      }
    }
    if (h.hp != null) {
      var mx = Math.max(1, num(h.hpmax, 1)), hp = Math.max(0, num(h.hp)), f = clamp01(hp / mx);
      $('sr-hpf').style.width = (100 * f) + '%'; $('sr-hpt').style.width = (100 * f) + '%';
      $('sr-hpx').textContent = Math.ceil(hp) + ' / ' + Math.ceil(mx);
      $('sr-hp').classList.toggle('low', f < 0.3);
    }
    if (h.keys) QW.forEach(function (k, i) { var kc = h.keys.charAt(i); if (kc) $('sr-s' + k).querySelector('.key').textContent = kc.toUpperCase(); });
    if (h.cd) QW.forEach(function (k) {
      var c = num(h.cd[k]), m = Math.max(0.1, num(h.cdm && h.cdm[k], 1));
      var sl = $('sr-s' + k), sw = sl.querySelector('.sw'), ct = sl.querySelector('.ct');
      if (c > 0.05) {
        var f = clamp01(c / m);
        sw.style.background = 'conic-gradient(from 0deg, rgba(0,0,0,0) ' + ((1 - f) * 360) + 'deg, rgba(4,8,18,.78) 0deg)';
        ct.textContent = c >= 10 ? Math.ceil(c) : c.toFixed(1);
        sl.classList.add('cd'); sl.classList.remove('ready');
      } else {
        sw.style.background = 'none'; ct.textContent = '';
        if (sl.classList.contains('cd')) restart(sl, 'rdy');
        sl.classList.remove('cd'); sl.classList.add('ready');
      }
    });
    if (h.items) setItems(h.items.slice(0, 6));
    if (h.kb != null) $('sr-kb').textContent = h.kb;
    if (h.kr != null) $('sr-kr').textContent = h.kr;
    if (h.t != null) $('sr-tm').textContent = fmtTime(h.t);
    if (h.nbm) { $('sr-nbf').style.width = (100 * clamp01(num(h.nb) / num(h.nbm, 1))) + '%'; $('sr-nbt').textContent = Math.max(0, Math.ceil(num(h.nb))); }
    if (h.nrm) { $('sr-nrf').style.width = (100 * clamp01(num(h.nr) / num(h.nrm, 1))) + '%'; $('sr-nrt').textContent = Math.max(0, Math.ceil(num(h.nr))); }
    if (h.stats) {
      var st = h.stats, lab = { dmg: 'DMG', ms: 'MS', cdr: 'CDR', ls: 'LS' }, out = '';
      ['dmg', 'ms', 'cdr', 'ls'].forEach(function (k) { if (st[k] != null) out += '<span><b>' + lab[k] + '</b>' + esc(st[k]) + '</span>'; });
      $('sr-stats').innerHTML = out;
    }
    if ('buff' in h) {
      var b = h.buff, be = $('sr-buff');
      if (b) { be.style.display = 'flex'; $('sr-bn').textContent = b.name || ''; $('sr-bs').textContent = num(b.sec).toFixed(1) + 's'; }
      else be.style.display = 'none';
    }
    if ('shopNear' in h) $('sr-shophint').style.display = h.shopNear ? 'block' : 'none';
    if (h.map) drawMap(h.map);
  }

  // ---------- minimap ----------
  var cv = $('sr-cv'), cx = cv.getContext('2d');
  var bg = null, bgKey = '';
  var MH = 480;
  function rng(seed) { return function () { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; }; }
  function lanePaths() {
    return [
      [[0.06, 0.5], [0.94, 0.5]],
      [[0.06, 0.5], [0.22, 0.14], [0.78, 0.14], [0.94, 0.5]],
      [[0.06, 0.5], [0.22, 0.86], [0.78, 0.86], [0.94, 0.5]]
    ];
  }
  function blob(c, x, y, r, rnd, fill, n) {
    n = n || 14; var ph = rnd() * 6.28, a1 = 0.18 + rnd() * 0.12;
    c.beginPath();
    for (var i = 0; i <= n; i++) {
      var a = i / n * 6.2832, rr = r * (1 + a1 * Math.sin(a * 3 + ph) + 0.12 * Math.sin(a * 5 + ph * 2) + (rnd() - 0.5) * 0.1);
      var px = x + Math.cos(a) * rr * 1.15, py = y + Math.sin(a) * rr;
      if (i) c.lineTo(px, py); else c.moveTo(px, py);
    }
    c.closePath(); c.fillStyle = fill; c.fill();
  }
  function buildBg(W, H) {
    var o = document.createElement('canvas'); o.width = W; o.height = H;
    var c = o.getContext('2d'), rnd = rng(7), S = H / 480;
    // sea / void edge
    var g = c.createLinearGradient(0, 0, W, H); g.addColorStop(0, '#16303a'); g.addColorStop(1, '#1b2740');
    c.fillStyle = g; c.fillRect(0, 0, W, H);
    // parchment-green land
    c.save();
    c.beginPath(); c.moveTo(W * .03, H * .5);
    c.bezierCurveTo(W * .05, H * .08, W * .2, H * .03, W * .5, H * .05);
    c.bezierCurveTo(W * .8, H * .03, W * .95, H * .08, W * .97, H * .5);
    c.bezierCurveTo(W * .95, H * .92, W * .8, H * .97, W * .5, H * .95);
    c.bezierCurveTo(W * .2, H * .97, W * .05, H * .92, W * .03, H * .5); c.closePath();
    c.shadowColor = '#000'; c.shadowBlur = 10 * S; c.fillStyle = '#6f7d4a'; c.fill(); c.shadowBlur = 0;
    c.clip();
    var lg = c.createLinearGradient(0, 0, 0, H); lg.addColorStop(0, '#8b9a5c'); lg.addColorStop(1, '#5c6c3e');
    c.fillStyle = lg; c.fillRect(0, 0, W, H);
    for (var i = 0; i < 260; i++) { c.fillStyle = rnd() < 0.5 ? 'rgba(255,240,170,.05)' : 'rgba(30,40,10,.07)'; c.fillRect(rnd() * W, rnd() * H, (2 + rnd() * 5) * S, (1 + rnd() * 2) * S); }
    // team tints
    var tb = c.createRadialGradient(W * .06, H * .5, 0, W * .06, H * .5, W * .3); tb.addColorStop(0, 'rgba(60,140,230,.45)'); tb.addColorStop(1, 'rgba(60,140,230,0)');
    c.fillStyle = tb; c.fillRect(0, 0, W, H);
    var tr = c.createRadialGradient(W * .94, H * .5, 0, W * .94, H * .5, W * .3); tr.addColorStop(0, 'rgba(230,70,50,.45)'); tr.addColorStop(1, 'rgba(230,70,50,0)');
    c.fillStyle = tr; c.fillRect(0, 0, W, H);
    // jungle blobs
    var J = [[.30, .33, 46], [.50, .31, 40], [.70, .33, 46], [.30, .67, 46], [.50, .69, 40], [.70, .67, 46], [.40, .5, 22], [.60, .5, 22], [.14, .32, 24], [.86, .32, 24], [.14, .68, 24], [.86, .68, 24]];
    J.forEach(function (j) {
      blob(c, j[0] * W, j[1] * H + 3 * S, j[2] * S, rnd, 'rgba(10,30,10,.35)');
      blob(c, j[0] * W, j[1] * H, j[2] * S, rnd, '#2e5a2c');
      blob(c, j[0] * W - 3 * S, j[1] * H - 3 * S, j[2] * S * 0.7, rnd, '#3f7538');
      for (var k = 0; k < 7; k++) blob(c, j[0] * W + (rnd() - .5) * j[2] * S * 1.6, j[1] * H + (rnd() - .5) * j[2] * S * 1.2, (4 + rnd() * 5) * S, rnd, '#4f8c42', 8);
    });
    // river (vertical, wavy)
    c.beginPath(); c.moveTo(W * .5, -4);
    c.bezierCurveTo(W * .44, H * .2, W * .56, H * .35, W * .49, H * .5);
    c.bezierCurveTo(W * .43, H * .65, W * .57, H * .8, W * .5, H + 4);
    c.lineCap = 'round'; c.strokeStyle = '#1b4a5c'; c.lineWidth = 16 * S; c.stroke();
    c.strokeStyle = '#3b94b0'; c.lineWidth = 11 * S; c.stroke();
    c.strokeStyle = 'rgba(190,240,255,.35)'; c.lineWidth = 3 * S; c.stroke();
    // lanes
    lanePaths().forEach(function (p) {
      function tr() { c.beginPath(); p.forEach(function (q, i) { if (i) c.lineTo(q[0] * W, q[1] * H); else c.moveTo(q[0] * W, q[1] * H); }); }
      c.lineJoin = 'round'; c.lineCap = 'round';
      tr(); c.strokeStyle = '#2b1d0e'; c.lineWidth = 14 * S; c.stroke();
      tr(); c.strokeStyle = '#8f7142'; c.lineWidth = 10 * S; c.stroke();
      tr(); c.strokeStyle = '#c5a56c'; c.lineWidth = 6 * S; c.stroke();
      tr(); c.strokeStyle = 'rgba(255,240,200,.35)'; c.lineWidth = 1.5 * S; c.setLineDash([5 * S, 6 * S]); c.stroke(); c.setLineDash([]);
    });
    // bases
    [[0.06, '#2a7fd8', '#7fcaff'], [0.94, '#d8452a', '#ff9a80']].forEach(function (b) {
      var x = b[0] * W, y = H * .5, r = 36 * S;
      var rg = c.createRadialGradient(x, y, 0, x, y, r); rg.addColorStop(0, b[2] + 'cc'); rg.addColorStop(.6, b[1] + '99'); rg.addColorStop(1, b[1] + '00');
      c.fillStyle = rg; c.beginPath(); c.arc(x, y, r, 0, 6.2832); c.fill();
      c.strokeStyle = b[2]; c.lineWidth = 2 * S; c.beginPath(); c.arc(x, y, r * .78, 0, 6.2832); c.stroke();
      c.strokeStyle = 'rgba(0,0,0,.5)'; c.lineWidth = 1 * S; c.beginPath(); c.arc(x, y, r * .78 + 2 * S, 0, 6.2832); c.stroke();
    });
    // vignette
    var vg = c.createRadialGradient(W / 2, H / 2, H * .35, W / 2, H / 2, W * .65); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.45)');
    c.fillStyle = vg; c.fillRect(0, 0, W, H);
    c.restore();
    // frame stroke
    c.strokeStyle = 'rgba(0,0,0,.6)'; c.lineWidth = 2; c.strokeRect(1, 1, W - 2, H - 2);
    return o;
  }
  var TC = ['#3aa6ff', '#ff4a36'], TD = ['#0b2f66', '#5a0c06'];
  function drawMap(m) {
    var ar = num(m.w, 1.6) / Math.max(0.1, num(m.h, 1));
    var W = Math.round(MH * ar), H = MH, S = H / 480 * 1.4;
    if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; }
    var key = W + 'x' + H;
    if (key !== bgKey) { bg = buildBg(W, H); bgKey = key; }
    cx.clearRect(0, 0, W, H); cx.drawImage(bg, 0, 0);
    var i, e, x, y;
    // structures
    (m.s || []).forEach(function (s) {
      var x = num(s[0]) * W, y = num(s[1]) * H, t = s[2] ? 1 : 0, fr = clamp01(num(s[4], 1));
      if (s[3] === 'n') {
        var r = 11 * S;
        cx.fillStyle = 'rgba(0,0,0,.55)'; cx.beginPath(); cx.arc(x, y + 2 * S, r + 2 * S, 0, 6.2832); cx.fill();
        cx.fillStyle = TD[t]; cx.beginPath(); cx.arc(x, y, r, 0, 6.2832); cx.fill();
        cx.fillStyle = TC[t]; cx.beginPath(); cx.moveTo(x, y - r * .8); cx.lineTo(x + r * .7, y); cx.lineTo(x, y + r * .8); cx.lineTo(x - r * .7, y); cx.closePath(); cx.fill();
        cx.strokeStyle = '#f0e6d2'; cx.lineWidth = 1.5 * S; cx.beginPath(); cx.arc(x, y, r, 0, 6.2832); cx.stroke();
        cx.strokeStyle = '#0008'; cx.lineWidth = 3 * S; cx.beginPath(); cx.arc(x, y, r + 4 * S, 0, 6.2832); cx.stroke();
        cx.strokeStyle = fr > .3 ? '#7dff7d' : '#ff6a50'; cx.beginPath(); cx.arc(x, y, r + 4 * S, -1.5708, -1.5708 + 6.2832 * fr); cx.stroke();
      } else {
        var q = 5 * S;
        cx.fillStyle = 'rgba(0,0,0,.55)'; cx.fillRect(x - q - S, y - q + S, 2 * q + 2 * S, 2 * q + 2 * S);
        cx.fillStyle = TD[t]; cx.fillRect(x - q, y - q, 2 * q, 2 * q);
        cx.fillStyle = TC[t]; cx.fillRect(x - q + 2 * S, y - q + 2 * S, 2 * q - 4 * S, 2 * q - 4 * S);
        cx.strokeStyle = '#f0e6d2'; cx.lineWidth = S; cx.strokeRect(x - q, y - q, 2 * q, 2 * q);
        if (fr < 0.999) {
          cx.fillStyle = '#000b'; cx.fillRect(x - 7 * S, y - q - 5 * S, 14 * S, 3 * S);
          cx.fillStyle = fr > .3 ? '#7dff7d' : '#ff6a50'; cx.fillRect(x - 7 * S, y - q - 5 * S, 14 * S * fr, 3 * S);
        }
      }
    });
    // units: minions, jungle first; champions, boss, hero on top
    var order = { m: 0, j: 1, c: 2, b: 3, h: 4 };
    var us = (m.u || []).slice().sort(function (a, b) { return (order[a[3]] || 0) - (order[b[3]] || 0); });
    us.forEach(function (u) {
      var x = num(u[0]) * W, y = num(u[1]) * H, t = u[2] ? 1 : 0, k = u[3];
      if (k === 'm') {
        cx.fillStyle = '#000a'; cx.beginPath(); cx.arc(x, y, 3.1 * S, 0, 6.2832); cx.fill();
        cx.fillStyle = TC[t]; cx.beginPath(); cx.arc(x, y, 2.2 * S, 0, 6.2832); cx.fill();
      } else if (k === 'j') {
        cx.fillStyle = '#000a'; cx.beginPath(); cx.arc(x, y, 3.8 * S, 0, 6.2832); cx.fill();
        cx.fillStyle = '#ffd83a'; cx.beginPath(); cx.arc(x, y, 2.8 * S, 0, 6.2832); cx.fill();
      } else if (k === 'b') {
        cx.fillStyle = '#d9a8ff55'; cx.beginPath(); cx.arc(x, y, 11 * S, 0, 6.2832); cx.fill();
        cx.fillStyle = '#000b'; cx.beginPath(); cx.arc(x, y, 7.5 * S, 0, 6.2832); cx.fill();
        cx.fillStyle = '#a24dff'; cx.beginPath(); cx.arc(x, y, 6 * S, 0, 6.2832); cx.fill();
        cx.strokeStyle = '#f0d8ff'; cx.lineWidth = 1.5 * S; cx.stroke();
      } else if (k === 'c') {
        cx.fillStyle = '#000b'; cx.beginPath(); cx.arc(x, y, 6.5 * S, 0, 6.2832); cx.fill();
        cx.fillStyle = TC[t]; cx.beginPath(); cx.arc(x, y, 5 * S, 0, 6.2832); cx.fill();
        cx.strokeStyle = '#f0e6d2'; cx.lineWidth = 1.5 * S; cx.stroke();
      } else if (k === 'h') {
        cx.fillStyle = 'rgba(255,255,255,.28)'; cx.beginPath(); cx.arc(x, y, 12 * S, 0, 6.2832); cx.fill();
        cx.strokeStyle = '#ffffffcc'; cx.lineWidth = 1.5 * S; cx.beginPath(); cx.arc(x, y, 9 * S, 0, 6.2832); cx.stroke();
        cx.fillStyle = '#000c'; cx.beginPath(); cx.arc(x, y, 7 * S, 0, 6.2832); cx.fill();
        // arrow-like marker: white kite pointing up-right
        cx.fillStyle = '#fff'; cx.beginPath();
        cx.moveTo(x + 6 * S, y - 6 * S); cx.lineTo(x - 2 * S, y - 2 * S); cx.lineTo(x, y); cx.lineTo(x + 2 * S, y + 2 * S); cx.lineTo(x + 6 * S, y - 6 * S); cx.closePath();
        cx.moveTo(x - 4.5 * S, y + 4.5 * S); cx.arc(x - 3 * S, y + 3 * S, 2.4 * S, 0, 6.2832);
        cx.fill();
      }
    });
  }

  // ---------- shop ----------
  function refreshShop() {
    if (!shopState) return;
    $('sr-sg').textContent = Math.floor(gold);
    var owned = shopState.owned || [];
    Array.prototype.forEach.call($('sr-sgrid').children, function (t) {
      var id = Number(t.getAttribute('data-id')), cost = Number(t.getAttribute('data-cost'));
      t.classList.toggle('dim', gold < cost);
      t.classList.toggle('own', owned.indexOf(id) >= 0);
    });
  }
  function openShop(s) {
    shopState = s;
    if (s.gold != null) gold = num(s.gold);
    var g = $('sr-sgrid'); g.innerHTML = '';
    (s.items || []).forEach(function (it) {
      var d = document.createElement('div');
      d.className = 'sr-tile'; d.setAttribute('data-id', it.id); d.setAttribute('data-cost', it.cost);
      d.innerHTML = '<img src="' + IMG + 'icon_item_' + it.id + '.png" alt="" onerror="this.style.visibility=\'hidden\'"><div class="tx"><div class="nm">' + esc(it.name) + '</div><div class="co"><span class="sr-coin"></span>' + esc(it.cost) + '</div><div class="ds">' + esc(it.desc) + '</div></div><div class="kc">' + esc(it.buy) + '</div><div class="ck"></div>';
      g.appendChild(d);
    });
    refreshShop();
    var sh = $('sr-shop'); sh.style.display = 'block'; void sh.offsetWidth; sh.classList.add('in');
    clearTimeout(timers.shopHide);
  }
  function closeShop() {
    var sh = $('sr-shop'); sh.classList.remove('in'); shopState = null;
    later('shopHide', function () { if (!sh.classList.contains('in')) sh.style.display = 'none'; }, 300);
  }

  // ---------- messages ----------
  window.addEventListener('sigfmod', function (e) {
    var m = (e && e.detail) || {};
    if (m.selChamps) selChamps = m.selChamps;
    if (m.sel && typeof m.sel === 'object') drawSel(m.sel);
    if (m.hud && typeof m.hud === 'object') handleHud(m.hud);
    if (m.cast) { var sl = $('sr-s' + String(m.cast).toLowerCase()); if (sl) restart(sl, 'pop'); }
    var rs = m.roster || (m.hud && m.hud.roster);
    if (rs && rs.length) {
      var re = $('sr-roster'), html = '';
      rs.forEach(function (c) {
        html += '<div class="rw t' + (c.team ? 1 : 0) + (c.dead ? ' dead' : '') + '"><span class="lv">' + esc(c.lv) + '</span><span class="nm">' + esc(c.name) + '</span><span class="kd">' + esc(c.k) + ' / ' + esc(c.d) + '</span></div>';
      });
      re.innerHTML = html; re.style.display = 'flex';
    }
    if ('quest' in m) {
      var qe = $('sr-quest'), qq = m.quest;
      if (qq && typeof qq === 'object') {
        qe.style.display = 'block';
        $('sr-qh').textContent = 'OBJECTIVE ' + qq.step + ' / ' + qq.total;
        $('sr-qt').textContent = qq.text + (qq.need > 1 ? '  (' + qq.n + '/' + qq.need + ')' : '');
        $('sr-qf').style.width = (100 * clamp01(num(qq.n) / Math.max(1, num(qq.need, 1)))) + '%';
        restart(qe, 'pop');
      } else qe.style.display = 'none';
    }
    if (m.banner) {
      var b = $('sr-banner'); b.textContent = m.banner; b.style.color = m.color || '#f0e6d2';
      b.classList.remove('in'); void b.offsetWidth; b.classList.add('in');
      later('banner', function () { b.classList.remove('in'); }, num(m.sec, 3) * 1000);
    }
    if (m.end) {
      var el = $('sr-end'); $('sr-endt').textContent = m.end;
      el.className = (m.end === 'VICTORY' ? 'win' : 'lose'); void el.offsetWidth; el.classList.add('in');
      later('end', function () { el.className = ''; }, num(m.sec, 8) * 1000);
    }
    if (m.feed) {
      var f = $('sr-feed'), d = document.createElement('div');
      d.className = 't' + (m.feed.team ? 1 : 0); d.textContent = m.feed.text;
      f.appendChild(d);
      while (f.children.length > 5) f.removeChild(f.firstChild);
      setTimeout(function () { d.classList.add('out'); }, 5000);
      setTimeout(function () { if (d.parentNode) d.parentNode.removeChild(d); }, 5600);
    }
    if (m.levelup != null && m.levelup !== false) {
      restart($('sr-lvflash'), 'go'); var lt = $('sr-lvtxt'); lt.textContent = 'LEVEL ' + m.levelup; restart(lt, 'go');
    }
    if (m.gold != null && typeof m.gold === 'object') {
      var n = num(m.gold.n), gd = $('sr-gd'), p = document.createElement('div');
      p.className = 'sr-float'; p.textContent = '+' + Math.round(n); gd.appendChild(p);
      setTimeout(function () { if (p.parentNode) p.parentNode.removeChild(p); }, 1500);
    }
    if (m.shop && typeof m.shop === 'object') {
      var s = m.shop;
      if (s.open === true) openShop(s);
      else if (s.open === false) closeShop();
      if (s.bought != null) {
        var t = document.querySelector('#sr-sgrid .sr-tile[data-id="' + Number(s.bought) + '"]');
        if (t) restart(t, 'flash');
      }
    }
    if (m.title && typeof m.title === 'object') {
      var tt = $('sr-title'); $('sr-tb').textContent = m.title.big || ''; $('sr-ts').textContent = m.title.small || '';
      tt.classList.remove('in'); void tt.offsetWidth; tt.classList.add('in');
      later('title', function () { tt.classList.remove('in'); }, num(m.title.sec, 4) * 1000);
    }
    if ('respawn' in m) {
      var r = $('sr-resp'), on = !!(m.respawn && m.respawn.sec != null);
      if (on) r.innerHTML = 'YOU WILL RESPAWN IN<b>' + Math.max(0, Math.ceil(num(m.respawn.sec))) + '</b>';
      r.classList.toggle('in', on); $('sr-gray').classList.toggle('in', on); $('sr-wrap').classList.toggle('dead', on);
    }
  });

  // ---------- champion select / lobby ----------
  var selEl = document.createElement('div');
  selEl.id = 'sr-sel';
  selEl.innerHTML = '<div class="sh">CHOOSE YOUR CHAMPION</div><div class="sg" id="sr-sgr"></div><div class="si" id="sr-si"></div><div class="st" id="sr-stm"></div><div class="sf" id="sr-sfo"></div>';
  document.getElementById('sr-wrap').appendChild(selEl);
  var selChamps = [];
  function rgb(c) { return 'rgb(' + (c ? c.join(',') : '200,200,200') + ')'; }
  function drawSel(m) {
    if (!m.open) { selEl.classList.remove('on'); return; }
    selEl.classList.add('on');
    var g = $('sr-sgr');
    if (g.children.length !== selChamps.length) {
      g.innerHTML = '';
      selChamps.forEach(function (c) {
        var d = document.createElement('div');
        d.className = 'cd'; d.style.setProperty('--c', rgb(c.col));
        d.innerHTML = '<img src="' + IMG + 'portrait_' + c.id + '.png" alt=""><b>' + esc(c.name) + '</b><i>' + esc(c.role) + '</i>';
        g.appendChild(d);
      });
    }
    var cur = selChamps[(m.idx || 1) - 1];
    Array.prototype.forEach.call(g.children, function (d, i) {
      d.classList.toggle('cur', i === (m.idx || 1) - 1);
      d.classList.toggle('pick', !!(m.picked && selChamps[i] && selChamps[i].id === m.picked));
    });
    if (cur) {
      var keys = ['Q', 'Z', 'X', 'C'], h = '<div class="nm" style="color:' + rgb(cur.col) + '">' + esc(cur.name) + ' <small>' + esc(cur.title) + '</small></div>';
      cur.abil.forEach(function (a, i) { var p = String(a).split(':'); h += '<div class="ab"><kbd>' + keys[i] + '</kbd><b>' + esc(p[0]) + '</b><span>' + esc(p.slice(1).join(':')) + '</span></div>'; });
      $('sr-si').innerHTML = h;
    }
    var teams = { blue: [], red: [] };
    (m.players || []).forEach(function (p) { if (teams[p.team]) teams[p.team].push(p); });
    var html = '';
    ['blue', 'red'].forEach(function (t) {
      html += '<div class="tm ' + t + '"><h4>' + (t === 'blue' ? 'ORDER' : 'VOID') + '</h4>';
      for (var i = 0; i < 5; i++) {
        var p = teams[t][i];
        html += p ? '<div class="pl' + (p.me ? ' me' : '') + '"><b>' + esc(p.name) + '</b><span>' + esc(p.champ) + '</span></div>' : '<div class="pl bot"><b>BOT</b></div>';
      }
      html += '</div>';
    });
    $('sr-stm').innerHTML = html;
    var left = num(m.left, -1);
    $('sr-sfo').innerHTML = '<kbd>LEFT</kbd> <kbd>RIGHT</kbd> choose &nbsp; <kbd>ENTER</kbd> pick (press again to start now) &nbsp; ' +
      (m.picked ? (left >= 0 ? 'MATCH STARTS IN <b>' + Math.ceil(left) + '</b>' : 'WAITING FOR THE LOBBY') : 'PICK A CHAMPION TO JOIN');
  }
  // initial empty state
  setItems([]);
  drawMap({ w: 1.6, h: 1, s: [], u: [] });
})();
