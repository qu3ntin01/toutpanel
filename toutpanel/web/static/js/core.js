/* ToutPanel — noyau front : i18n, API, DOM, modales, toasts, formats, icônes */
(function () {
  'use strict';
  const TP = window.TP;
  const Pages = {};
  TP.pages = Pages;

  // ---------------------------------------------------------------- i18n
  TP.t = function (key, vars) {
    const dict = TP.i18n[TP.lang] || {};
    let s = dict[key] !== undefined ? dict[key] : (TP.lang !== 'fr' && (TP.i18n.en || {})[key] !== undefined ? TP.i18n.en[key] : key);
    if (vars) for (const k in vars) s = s.replace(new RegExp('\\{' + k + '\\}', 'g'), vars[k]);
    return s;
  };
  const t = TP.t;

  // ---------------------------------------------------------------- utils
  TP.esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  TP.fmtBytes = function (n, d) {
    n = Number(n) || 0; d = d === undefined ? 1 : d;
    const u = ['o', 'Ko', 'Mo', 'Go', 'To', 'Po']; let i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i === 0 ? n.toFixed(0) : n.toFixed(d)) + ' ' + u[i];
  };
  TP.fmtRate = (n) => TP.fmtBytes(n) + '/s';
  TP.fmtDate = function (iso) {
    if (!iso) return '—';
    const d = new Date(iso.endsWith('Z') || iso.includes('+') ? iso : iso + 'Z');
    if (isNaN(d)) return iso;
    return d.toLocaleString(TP.locale || 'fr-FR', { dateStyle: 'short', timeStyle: 'short' });
  };
  TP.fmtTs = (ts) => ts ? new Date(ts * 1000).toLocaleString(TP.locale || 'fr-FR', { dateStyle: 'short', timeStyle: 'short' }) : '—';
  TP.fmtDuration = function (s) {
    s = Math.floor(s); const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return (d ? d + t('j') + ' ' : '') + (h ? h + 'h ' : '') + m + 'min';
  };
  TP.debounce = (fn, ms) => { let to; return (...a) => { clearTimeout(to); to = setTimeout(() => fn(...a), ms); }; };
  TP.copy = async (text) => { try { await navigator.clipboard.writeText(text); TP.toast(t('Copié')); } catch (e) { TP.toast(t('Copie impossible'), 'error'); } };
  TP.qs = (sel, root) => (root || document).querySelector(sel);
  TP.qsa = (sel, root) => Array.from((root || document).querySelectorAll(sel));

  // ---------------------------------------------------------------- API
  TP.api = async function (method, url, body, opts) {
    opts = opts || {};
    const init = { method, headers: { 'X-Requested-With': 'ToutPanel' }, credentials: 'same-origin', signal: (window.AbortSignal && AbortSignal.timeout) ? AbortSignal.timeout(opts.timeout || 60000) : undefined };
    if (body instanceof FormData) init.body = body;
    else if (body !== undefined) { init.headers['Content-Type'] = 'application/json'; init.body = JSON.stringify(body); }
    let res;
    try { res = await fetch(url, init); } catch (e) { throw new Error(e && e.name === 'TimeoutError' ? t('Délai dépassé : le serveur ne répond pas') : t('Serveur injoignable')); }
    if (res.status === 401 && !opts.noAuthRedirect) { TP.showLogin(); throw new Error(t('Session expirée')); }
    let data;
    try { data = await res.json(); } catch (e) { throw new Error('HTTP ' + res.status); }
    if (!res.ok || data.ok === false) {
      if (data.need_totp) return data;
      throw new Error(data.msg || data.detail || ('HTTP ' + res.status));
    }
    return data;
  };
  TP.get = (u) => TP.api('GET', u);
  TP.post = (u, b) => TP.api('POST', u, b);
  TP.put = (u, b) => TP.api('PUT', u, b);
  TP.del = (u) => TP.api('DELETE', u);

  // ---------------------------------------------------------------- icônes (Lucide-like)
  const I = {
    home: '<path d="M3 11 12 3l9 8v10a1 1 0 0 1-1 1h-5v-7h-6v7H4a1 1 0 0 1-1-1z"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
    wp: '<circle cx="12" cy="12" r="9"/><path d="M5 9h3M9 9l3 8 2-5M13 9h4M16 9l-3 8-1-3"/>',
    ftp: '<path d="M4 7h16M4 12h16M4 17h10"/>',
    db: '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
    docker: '<path d="M3 13h18a4 4 0 0 1-4 5H8a5 5 0 0 1-5-5z"/><path d="M6 13V9h3v4M9 9h3v4M12 9h3v4M12 5h3v4M15 9h3v4"/>',
    monitor: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4M6 12l3-3 3 2 4-5"/>',
    shield: '<path d="M12 3 5 6v6c0 4 3 7 7 9 4-2 7-5 7-9V6z"/><path d="m9 12 2 2 4-4"/>',
    folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    file: '<path d="M6 3h8l5 5v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M14 3v5h5"/>',
    logs: '<path d="M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    box: '<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="M12 12 4 7.5M12 12l8-4.5M12 12v9"/>',
    backup: '<path d="M12 3v10m0 0 4-4m-4 4-4-4"/><path d="M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>',
    cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
    terminal: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="m7 9 3 3-3 3M12 15h5"/>',
    domain: '<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="1.5" fill="currentColor"/><circle cx="8" cy="12" r="1.5" fill="currentColor"/><circle cx="8" cy="18" r="1.5" fill="currentColor"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    moon: '<path d="M21 13a8 8 0 0 1-10-10 8 8 0 1 0 10 10z"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
    refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4M21 3v6h-6"/>',
    power: '<path d="M12 3v9M18.4 6.6a9 9 0 1 1-12.8 0"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    check: '<path d="m5 12 5 5L20 7"/>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
    edit: '<path d="M4 20h4l11-11-4-4L4 16z"/><path d="m13 7 4 4"/>',
    play: '<path d="m7 5 12 7-12 7z"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
    lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l2 2M14 9l2 2"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    download: '<path d="M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
    upload: '<path d="M12 15V3m0 0 4 4m-4-4-4 4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
    copy: '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>',
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    zip: '<path d="M6 3h8l5 5v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M10 3v2h2v2h-2v2h2v2h-2v2h2v2"/>',
    external: '<path d="M14 4h6v6M20 4l-9 9M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
    alert: '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17h.01"/>',
    more: '<circle cx="12" cy="5" r="1.5" fill="currentColor"/><circle cx="12" cy="12" r="1.5" fill="currentColor"/><circle cx="12" cy="19" r="1.5" fill="currentColor"/>',
    ram: '<rect x="3" y="7" width="18" height="10" rx="2"/><path d="M7 11v2M11 11v2M15 11v2M3 17v2M21 17v2"/>',
    hdd: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 13h18M7 16h.01M11 16h.01"/>',
    net: '<path d="M4 17h16M6 17V9M12 17V5M18 17v-6"/>',
    chevron: '<path d="m9 6 6 6-6 6"/>',
    eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    star: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z"/>',
    activity: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
    brush: '<path d="M14 3l7 7-9 9H5v-7z"/><path d="M5 21h4M16 5l3 3"/>',
    php: '<ellipse cx="12" cy="12" rx="10" ry="6"/><path d="M7 10v4M7 10h1.5a1.5 1.5 0 0 1 0 3H7M11 10v4M11 12h2M13 10v4M15.5 10v4M15.5 10H17a1.5 1.5 0 0 1 0 3h-1.5"/>',
    mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
    waf: '<path d="M12 3 5 6v6c0 4 3 7 7 9 4-2 7-5 7-9V6z"/><path d="M12 8v4M12 15h.01"/>',
    fire: '<path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-6 1-9z"/>',
    desktop: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
    contrast: '<circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor"/>',
    collapse: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16M15 10l-2 2 2 2"/>',
    expand: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16M13 10l2 2-2 2"/>',
    minimize: '<path d="M5 12h14"/>',
    maximize: '<path d="M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 0 2-2v-3"/>',
    git: '<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="9" r="2.5"/><path d="M6 8.5v7M18 11.5c0 3-3 4-6 4H9"/>',
    bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10 21a2 2 0 0 0 4 0"/>',
    dns: '<circle cx="12" cy="5" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><path d="M12 7v4M12 11l-6 6M12 11l6 6"/>',
    inbox: '<path d="M3 13h5l2 3h4l2-3h5"/><path d="M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"/>',
    rocket: '<path d="M5 19c0-3 1-5 3-6l7-7c2-2 4-2 5-1s1 3-1 5l-7 7c-1 2-3 3-6 3z"/><path d="m9 13-4-1 3-3M11 15l1 4 3-3"/><circle cx="15" cy="9" r="1" fill="currentColor"/>',
  };
  TP.icon = (name, cls) => '<svg class="ic ' + (cls || '') + '" viewBox="0 0 24 24">' + (I[name] || I.box) + '</svg>';

  // ---------------------------------------------------------------- toasts
  TP.toast = function (msg, type, ms) {
    const el = document.createElement('div');
    el.className = 'toast ' + (type || '');
    el.innerHTML = TP.icon(type === 'error' ? 'alert' : (type === 'warn' ? 'info' : 'check')) + '<div>' + TP.esc(msg) + '</div>';
    document.getElementById('toasts').appendChild(el);
    setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity .3s'; setTimeout(() => el.remove(), 300); }, ms || (type === 'error' ? 6000 : 3200));
  };

  // ---------------------------------------------------------------- modales
  TP.modal = function (opts) {
    const root = document.getElementById('modal-root');
    const bg = document.createElement('div');
    bg.className = 'modal-bg';
    bg.innerHTML = '<div class="modal ' + (opts.size || '') + '">' +
      '<div class="modal-h"><h3>' + TP.esc(opts.title || '') + '</h3><button class="btn ghost sm" data-close>' + TP.icon('x') + '</button></div>' +
      '<div class="modal-b">' + (opts.body || '') + '</div>' +
      (opts.footer !== false ? '<div class="modal-f">' + (opts.footer || ('<button class="btn" data-close>' + t('Annuler') + '</button>' +
        (opts.onOk ? '<button class="btn primary" data-ok>' + TP.esc(opts.okText || t('Valider')) + '</button>' : ''))) + '</div>' : '') +
      '</div>';
    root.appendChild(bg);
    const close = () => { bg.remove(); document.removeEventListener('keydown', onKey); if (opts.onClose) opts.onClose(); };
    const onKey = (e) => { if (e.key === 'Escape') close(); };
    document.addEventListener('keydown', onKey);
    bg.addEventListener('click', (e) => { if (e.target === bg && !opts.sticky) close(); });
    TP.qsa('[data-close]', bg).forEach((b) => b.addEventListener('click', close));
    const okBtn = TP.qs('[data-ok]', bg);
    if (okBtn && opts.onOk) okBtn.addEventListener('click', async () => {
      okBtn.disabled = true;
      try { const r = await opts.onOk(bg, close); if (r !== false) close(); } catch (e) { TP.toast(e.message, 'error'); }
      okBtn.disabled = false;
    });
    const first = TP.qs('input,select,textarea', bg); if (first) setTimeout(() => first.focus(), 50);
    if (opts.onOpen) opts.onOpen(bg, close);
    return { el: bg, close };
  };
  TP.confirm = (title, text, opts) => new Promise((resolve) => {
    opts = opts || {};
    TP.modal({
      title, body: '<p style="margin:0">' + text + '</p>' + (opts.extra || ''),
      footer: '<button class="btn" data-close>' + t('Annuler') + '</button><button class="btn ' + (opts.danger ? 'danger' : 'primary') + '" data-ok>' + TP.esc(opts.okText || t('Confirmer')) + '</button>',
      onOk: (bg) => { resolve(opts.extra ? bg : true); }, onClose: () => resolve(false),
    });
  });
  TP.prompt = (title, label, value, opts) => new Promise((resolve) => {
    opts = opts || {};
    TP.modal({
      title, body: '<div class="field"><label>' + TP.esc(label) + '</label>' + (opts.textarea ? '<textarea class="input" name="v">' + TP.esc(value || '') + '</textarea>' : '<input class="input" name="v" value="' + TP.esc(value || '') + '" placeholder="' + TP.esc(opts.placeholder || '') + '">') + '</div>',
      onOk: (bg) => { resolve(TP.qs('[name=v]', bg).value); }, onClose: () => resolve(null),
      onOpen: (bg, close) => { const inp = TP.qs('[name=v]', bg); if (inp.tagName === 'INPUT') inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') TP.qs('[data-ok]', bg).click(); }); },
    });
  });
  TP.formData = (root) => { const o = {}; TP.qsa('[name]', root).forEach((i) => { if (i.type === 'checkbox') o[i.name] = i.checked; else if (i.type === 'number') o[i.name] = i.value === '' ? null : Number(i.value); else o[i.name] = i.value; }); return o; };

  // ---------------------------------------------------------------- composants
  TP.field = (name, label, opts) => {
    opts = opts || {};
    let ctl;
    if (opts.type === 'select') ctl = '<select class="input" name="' + name + '">' + (opts.options || []).map((o) => '<option value="' + TP.esc(o[0]) + '"' + (String(o[0]) === String(opts.value ?? '') ? ' selected' : '') + '>' + TP.esc(o[1]) + '</option>').join('') + '</select>';
    else if (opts.type === 'textarea') ctl = '<textarea class="input" name="' + name + '" placeholder="' + TP.esc(opts.placeholder || '') + '"' + (opts.rows ? ' rows="' + opts.rows + '"' : '') + '>' + TP.esc(opts.value ?? '') + '</textarea>';
    else if (opts.type === 'checkbox') return '<label class="check"><input type="checkbox" name="' + name + '"' + (opts.value ? ' checked' : '') + '> <span>' + TP.esc(label) + '</span></label>' + (opts.hint ? '<div class="hint muted small">' + opts.hint + '</div>' : '');
    else ctl = '<input class="input" type="' + (opts.type || 'text') + '" name="' + name + '" value="' + TP.esc(opts.value ?? '') + '" placeholder="' + TP.esc(opts.placeholder || '') + '"' + (opts.attrs || '') + '>';
    return '<div class="field"><label>' + TP.esc(label) + '</label>' + ctl + (opts.hint ? '<div class="hint">' + opts.hint + '</div>' : '') + '</div>';
  };
  TP.pageHead = (title, sub, actions) => '<div class="page-head"><div><h1>' + TP.esc(title) + '</h1>' + (sub ? '<p>' + sub + '</p>' : '') + '</div><div class="actions">' + (actions || '') + '</div></div>';
  TP.empty = (msg, icon) => '<div class="empty">' + TP.icon(icon || 'box') + '<div>' + TP.esc(msg) + '</div></div>';
  TP.loading = () => '<div class="loading"><div class="spin"></div>' + t('Chargement…') + '</div>';
  TP.badge = (txt, cls) => '<span class="badge ' + (cls || '') + '"><i class="dot"></i>' + TP.esc(txt) + '</span>';
  TP.statusBadge = (st) => st === 'running' ? TP.badge(t('Actif'), 'ok') : st === 'stopped' ? TP.badge(t('Arrêté'), 'danger') : st === 'missing' ? TP.badge(t('Non installé'), '') : TP.badge(st || '?', 'warn');
  TP.table = (cols, rows, opts) => {
    opts = opts || {};
    if (!rows.length) return TP.empty(opts.empty || t('Aucun élément'), opts.icon);
    return '<div class="table-wrap"><table class="tbl"><thead><tr>' + cols.map((c) => '<th class="' + (c.cls || '') + '">' + (c.raw ? c.label : TP.esc(c.label)) + '</th>').join('') + '</tr></thead><tbody>' +
      rows.map((r) => '<tr' + (opts.rowAttr ? ' ' + opts.rowAttr(r) : '') + '>' + cols.map((c) => '<td class="' + (c.cls || '') + '">' + c.render(r) + '</td>').join('') + '</tr>').join('') + '</tbody></table></div>';
  };

  // ---------------------------------------------------------------- terminal de tâche flottant
  // Aperçu façon terminal d'une tâche de fond (installation, certificat, sauvegarde…) : fenêtre
  // flottante, journal en direct coloré, réduction / agrandissement, plusieurs tâches empilées.
  const ttOpen = {};
  function ttDock() { let d = document.getElementById('tt-dock'); if (!d) { d = document.createElement('div'); d.id = 'tt-dock'; document.body.appendChild(d); } return d; }
  function ttClass(line) {
    const l = line.trim(); if (!l) return 'dim';
    if (/^(\$|#|>|❯)\s/.test(l) || /^(\+ |Exécution|Running|Commande)/i.test(l)) return 'cmd';
    if (/^(===|---|##|\[)/.test(l) || /^(Étape|Step)\b/i.test(l)) return 'head';
    if (/(erreur|error|échec|failed|fatal|impossible|refus|denied|traceback|exception)/i.test(l)) return 'err';
    if (/(warn|attention|avertissement|deprecated|skip|ignor)/i.test(l)) return 'warn';
    if (/(✓|✔|ok\b|succès|success|terminé|done|installé|installed|démarré|started|prêt|ready|complete)/i.test(l)) return 'ok';
    if (/^(Get:|Hit:|Reading|Building|Selecting|Preparing|Unpacking|Setting up|Processing|Downloading|Téléchargement|Lecture|Dépaquetage|Paramétrage)/i.test(l)) return 'dim';
    return '';
  }
  function ttRender(html, log) {
    const lines = String(log || '').replace(/\x1b\[[0-9;]*[A-Za-z]/g, '').split('\n');
    if (lines.length && lines[lines.length - 1] === '') lines.pop();
    return lines.map((ln) => '<span class="tt-line ' + ttClass(ln) + '">' + TP.esc(ln) + '</span>').join('');
  }
  TP.taskTerminal = function (taskId, title, onDone) {
    if (ttOpen[taskId]) { ttOpen[taskId].el.classList.remove('minimized'); return ttOpen[taskId]; }
    const el = document.createElement('div'); el.className = 'tt'; el.dataset.task = taskId;
    const t0 = Date.now(); let timer, lastLen = -1, finished = false;
    el.innerHTML = '<div class="tt-h"><span class="lights"><i></i><i></i><i></i></span><span class="title">' + TP.esc(title || t('Tâche en cours')) + '</span><span class="meta" data-el>0 s</span>' +
      '<button class="ibtn" data-min title="' + t('Réduire') + '">' + TP.icon('minimize') + '</button><button class="ibtn" data-max title="' + t('Agrandir') + '">' + TP.icon('maximize') + '</button><button class="ibtn" data-close title="' + t('Fermer') + '">' + TP.icon('x') + '</button></div>' +
      '<div class="tt-prog"></div><div class="tt-body" data-body><span class="tt-line dim">' + TP.esc(t('Connexion à la tâche')) + ' #' + taskId + '…</span><span class="tt-cursor"></span></div>' +
      '<div class="tt-foot"><span class="badge info" data-st><i class="dot"></i>' + t('En cours') + '</span><span data-sum></span><span class="spacer"></span><button class="btn xs" data-copy>' + TP.icon('copy') + t('Copier') + '</button></div>';
    ttDock().appendChild(el);
    const body = TP.qs('[data-body]', el), st = TP.qs('[data-st]', el), meta = TP.qs('[data-el]', el);
    let logText = '';
    const stop = () => { clearInterval(timer); finished = true; TP.qs('.tt-cursor', el) && TP.qs('.tt-cursor', el).remove(); };
    const close = () => { stop(); el.remove(); delete ttOpen[taskId]; };
    TP.qs('[data-close]', el).onclick = close;
    TP.qs('[data-min]', el).onclick = () => { el.classList.toggle('minimized'); el.classList.remove('expanded'); };
    TP.qs('[data-max]', el).onclick = () => { el.classList.toggle('expanded'); el.classList.remove('minimized'); body.scrollTop = body.scrollHeight; };
    TP.qs('[data-copy]', el).onclick = () => TP.copy(logText);
    TP.qs('.tt-h', el).ondblclick = () => TP.qs('[data-max]', el).click();
    let inflight = false;
    const poll = async () => {
      if (inflight) return; inflight = true;
      try {
        const r = await TP.get('/api/system/tasks/' + taskId);
        logText = r.data.log || '';
        if (!finished) meta.textContent = Math.round((Date.now() - t0) / 1000) + ' s';
        if (logText.length !== lastLen) {
          lastLen = logText.length;
          const atBottom = body.scrollTop + body.clientHeight >= body.scrollHeight - 30;
          body.innerHTML = ttRender(null, logText) + (r.data.status === 'running' || r.data.status === 'pending' ? '<span class="tt-cursor"></span>' : '');
          if (atBottom) body.scrollTop = body.scrollHeight;
        }
        if (r.data.status === 'done') { el.classList.add('done'); st.className = 'badge ok'; st.innerHTML = '<i class="dot"></i>' + t('Terminé'); TP.qs('[data-sum]', el).textContent = t('Terminé en {s} s', { s: Math.round((Date.now() - t0) / 1000) }); stop(); if (onDone) onDone(true); }
        else if (r.data.status === 'error') { el.classList.add('error'); st.className = 'badge danger'; st.innerHTML = '<i class="dot"></i>' + t('Erreur'); TP.qs('[data-sum]', el).textContent = t('Voir la dernière ligne du journal'); stop(); if (onDone) onDone(false); }
      } catch (e) { st.className = 'badge warn'; st.innerHTML = '<i class="dot"></i>' + TP.esc(e.message); stop(); }
      inflight = false;
    };
    poll(); timer = setInterval(poll, 1200);
    const handle = { el, close };
    ttOpen[taskId] = handle;
    return handle;
  };
  TP.taskModal = TP.taskTerminal;  // compatibilité avec les anciens appels

  // ---------------------------------------------------------------- router
  TP.route = () => (location.hash.replace(/^#\/?/, '') || 'dashboard').split('?')[0];
  TP.query = () => { const q = location.hash.split('?')[1] || ''; return Object.fromEntries(new URLSearchParams(q)); };
  TP.go = (p, q) => { location.hash = '/' + p + (q ? '?' + new URLSearchParams(q).toString() : ''); };
  TP.registerPage = (name, def) => { Pages[name] = def; };
})();
