/* Graphiques légers en canvas (jauge circulaire, courbes) — sans dépendance */
(function () {
  'use strict';
  const TP = window.TP;

  TP.gauge = function (pct, size) {
    size = size || 96; const r = (size - 10) / 2, c = 2 * Math.PI * r;
    pct = Math.max(0, Math.min(100, Number(pct) || 0));
    const cls = pct >= 90 ? 'danger' : pct >= 70 ? 'warn' : '';
    return '<div class="gauge ' + cls + '" style="width:' + size + 'px;height:' + size + 'px"><svg width="' + size + '" height="' + size + '">' +
      '<circle class="track" cx="' + size / 2 + '" cy="' + size / 2 + '" r="' + r + '"/>' +
      '<circle class="bar" cx="' + size / 2 + '" cy="' + size / 2 + '" r="' + r + '" stroke-dasharray="' + c + '" stroke-dashoffset="' + (c * (1 - pct / 100)) + '"/>' +
      '</svg><div class="pct">' + Math.round(pct) + '%</div></div>';
  };

  function cssVar(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

  /**
   * Courbes lissées avec zone. series: [{label, color, data:[num]}], labels:[string]
   */
  TP.lineChart = function (canvas, series, labels, opts) {
    opts = opts || {};
    const dpr = window.devicePixelRatio || 1;
    const W = canvas.clientWidth || 600, H = canvas.clientHeight || 240;
    canvas.width = W * dpr; canvas.height = H * dpr;
    const ctx = canvas.getContext('2d'); ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, W, H);
    const padL = 46, padR = 12, padT = 12, padB = 26;
    const w = W - padL - padR, h = H - padT - padB;
    const text3 = cssVar('--text-3'), border = cssVar('--border');
    let max = opts.max;
    if (max === undefined) { max = 0; series.forEach((s) => s.data.forEach((v) => { if (v > max) max = v; })); max = max <= 0 ? 1 : max * 1.15; }
    const n = Math.max(...series.map((s) => s.data.length), 2);
    const fmt = opts.format || ((v) => Math.round(v));
    // grille
    ctx.font = '11px ' + cssVar('--font'); ctx.fillStyle = text3; ctx.strokeStyle = border; ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const y = padT + h - (h * i / 4);
      ctx.setLineDash([3, 4]); ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(W - padR, y); ctx.stroke(); ctx.setLineDash([]);
      ctx.textAlign = 'right'; ctx.fillText(fmt(max * i / 4), padL - 8, y + 4);
    }
    if (labels && labels.length) {
      ctx.textAlign = 'center'; const step = Math.ceil(labels.length / Math.max(2, Math.floor(w / 70)));
      labels.forEach((l, i) => { if (i % step === 0) ctx.fillText(l, padL + (w * i / (n - 1)), H - 8); });
    }
    const X = (i) => padL + w * i / (n - 1), Y = (v) => padT + h - h * Math.min(v, max) / max;
    series.forEach((s) => {
      const pts = s.data.map((v, i) => [X(i), Y(v || 0)]);
      if (pts.length < 2) return;
      const path = () => { ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]);
        for (let i = 1; i < pts.length; i++) { const p0 = pts[i - 1], p1 = pts[i]; const cx = (p0[0] + p1[0]) / 2; ctx.bezierCurveTo(cx, p0[1], cx, p1[1], p1[0], p1[1]); } };
      // zone
      path(); ctx.lineTo(pts[pts.length - 1][0], padT + h); ctx.lineTo(pts[0][0], padT + h); ctx.closePath();
      const g = ctx.createLinearGradient(0, padT, 0, padT + h); g.addColorStop(0, s.color + '55'); g.addColorStop(1, s.color + '00');
      ctx.fillStyle = g; ctx.fill();
      // ligne
      path(); ctx.strokeStyle = s.color; ctx.lineWidth = 2; ctx.lineJoin = 'round'; ctx.stroke();
      // dernier point
      const last = pts[pts.length - 1]; ctx.fillStyle = s.color; ctx.beginPath(); ctx.arc(last[0], last[1], 3, 0, Math.PI * 2); ctx.fill();
    });
  };

  TP.barsInline = (pct, cls) => '<div class="progress ' + (cls || (pct >= 90 ? 'danger' : pct >= 70 ? 'warn' : '')) + '"><i style="width:' + Math.min(100, pct) + '%"></i></div>';
})();
