/* ToutPanel — coquille applicative : login, rail, thème, contraste, routage */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;
  const app = document.getElementById('app');
  let currentPage = null, refreshTimer = null, routeSeq = 0;

  const NAV = [
    { group: t('Général') },
    { id: 'dashboard', icon: 'home', label: t('Accueil') },
    { id: 'sites', icon: 'globe', label: t('Sites web') },
    { id: 'wordpress', icon: 'wp', label: t('WP Toolkit') },
    { id: 'domains', icon: 'domain', label: t('Domaines') },
    { id: 'dns', icon: 'dns', label: 'DNS' },
    { id: 'ftp', icon: 'ftp', label: t('FTP') },
    { id: 'databases', icon: 'db', label: t('Bases de données') },
    { id: 'mail', icon: 'mail', label: t('Serveur mail') },
    { group: t('Système') },
    { id: 'files', icon: 'folder', label: t('Fichiers') },
    { id: 'terminal', icon: 'terminal', label: t('Terminal') },
    { id: 'docker', icon: 'docker', label: t('Docker') },
    { id: 'software', icon: 'box', label: t('Logiciels') },
    { id: 'php', icon: 'php', label: 'PHP' },
    { id: 'cron', icon: 'clock', label: t('Tâches planifiées') },
    { id: 'backups', icon: 'backup', label: t('Sauvegardes') },
    { group: t('Supervision') },
    { id: 'monitor', icon: 'monitor', label: t('Monitoring') },
    { id: 'processes', icon: 'cpu', label: t('Processus') },
    { id: 'logs', icon: 'logs', label: t('Journaux') },
    { id: 'security', icon: 'shield', label: t('Sécurité') },
    { id: 'waf', icon: 'waf', label: 'WAF' },
    { group: t('Compte') },
    { id: 'settings', icon: 'settings', label: t('Réglages') },
    { id: 'custom', icon: 'brush', label: t('Personnalisation') },
  ];

  // ---------------------------------------------------------------- thème & contraste
  const store = { get: (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } }, set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} } };
  const mq = window.matchMedia ? matchMedia('(prefers-color-scheme: dark)') : null;
  TP.themePref = function () {
    const s = store.get('tp-theme'); if (s === 'light' || s === 'dark' || s === 'system') return s;
    const d = (TP.appearance || {}).default_theme; return d === 'light' || d === 'dark' ? d : 'system';
  };
  TP.contrastPref = function () {
    const s = store.get('tp-contrast'); if (s === 'glass' || s === 'high') return s;
    return (TP.appearance || {}).default_contrast === 'high' ? 'high' : 'glass';
  };
  TP.applyTheme = function () {
    const pref = TP.themePref();
    document.documentElement.dataset.theme = pref === 'system' ? (mq && mq.matches ? 'dark' : 'light') : pref;
    document.documentElement.dataset.contrast = TP.contrastPref();
    TP.qsa('#theme-seg button').forEach((b) => b.classList.toggle('on', b.dataset.th === pref));
    const cb = document.getElementById('btn-contrast');
    if (cb) cb.innerHTML = TP.icon('contrast') + '<span>' + (TP.contrastPref() === 'high' ? t('Opaque') : t('Verre')) + '</span>';
  };
  TP.setTheme = function (pref) { store.set('tp-theme', pref); TP.applyTheme(); if (TP.user) route(); };
  TP.setContrast = function (v) { store.set('tp-contrast', v); TP.applyTheme(); };
  if (mq && mq.addEventListener) mq.addEventListener('change', () => { if (TP.themePref() === 'system') { TP.applyTheme(); if (TP.user) route(); } });
  if (store.get('tp-rail') === 'collapsed') document.documentElement.classList.add('rail-collapsed');
  TP.applyTheme();

  // ---------------------------------------------------------------- login
  TP.showLogin = function () {
    clearInterval(refreshTimer);
    const ap = TP.appearance || {};
    const logo = ap.logo_url ? '<img class="logo" src="' + TP.esc(ap.logo_url) + '" alt="">' : '<div class="logo">' + TP.esc(ap.logo_letter || 'T') + '</div>';
    app.innerHTML = '<div class="login-wrap"><div class="login">' +
      '<div class="side"><div><div class="brand">' + logo + '<div class="name">' + TP.esc(TP.panelName) + '</div></div>' +
      '<h2>' + t('Votre serveur, piloté depuis une seule interface.') + '</h2><p>' + t('Sites, PHP, bases de données, mail, WAF, sauvegardes : tout est à portée de clic, sur Linux comme sur Windows.') + '</p>' +
      '<ul><li>' + TP.icon('check') + t('Nginx, Apache ou IIS configurés automatiquement') + '</li><li>' + TP.icon('check') + t('PHP multi-versions et Let\'s Encrypt intégrés') + '</li><li>' + TP.icon('check') + t('Terminal, Docker et monitoring en temps réel') + '</li></ul></div>' +
      '<div class="foot">' + TP.esc(TP.panelName) + ' ' + TP.version + ' · ' + TP.esc(TP.os) + '</div></div>' +
      '<div class="pane"><h1>' + t('Connexion') + '</h1><p class="sub">' + t('Accédez à votre serveur') + '</p>' +
      '<form class="form" id="login-form">' +
      TP.field('username', t('Utilisateur'), { attrs: ' autocomplete="username" required' }) +
      TP.field('password', t('Mot de passe'), { type: 'password', attrs: ' autocomplete="current-password" required' }) +
      '<div id="totp-wrap" style="display:none">' + TP.field('code', t('Code 2FA'), { attrs: ' autocomplete="one-time-code"', hint: t('Code de l\'application ou code de secours (xxxxx-xxxxx).') }) + '</div>' +
      '<button class="btn primary" style="justify-content:center;padding:11px">' + t('Se connecter') + '</button>' +
      '</form><div class="row between mt"><div class="seg" id="theme-seg" style="background:var(--bg-hover);border-color:var(--border)">' + themeSeg() + '</div><span class="muted small">' + t('Connexion sécurisée') + '</span></div></div></div></div>';
    bindThemeSeg(); TP.applyTheme();
    const form = document.getElementById('login-form');
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const btn = form.querySelector('button'); btn.disabled = true;
      try {
        const r = await TP.api('POST', '/api/auth/login', TP.formData(form), { noAuthRedirect: true });
        if (r.need_totp) { document.getElementById('totp-wrap').style.display = ''; form.code.focus(); TP.toast(r.msg, 'warn'); }
        else { TP.user = r.data; renderShell(); route(); }
      } catch (err) { TP.toast(err.message, 'error'); }
      btn.disabled = false;
    });
  };
  function themeSeg() {
    return '<button data-th="light" title="' + t('Clair') + '">' + TP.icon('sun') + '</button><button data-th="dark" title="' + t('Sombre') + '">' + TP.icon('moon') + '</button><button data-th="system" title="' + t('Système') + '">' + TP.icon('desktop') + '</button>';
  }
  function bindThemeSeg() { TP.qsa('#theme-seg button').forEach((b) => b.onclick = () => TP.setTheme(b.dataset.th)); }

  // ---------------------------------------------------------------- coquille
  function renderShell() {
    const ap = TP.appearance || {};
    const logo = ap.logo_url ? '<img class="logo" src="' + TP.esc(ap.logo_url) + '" alt="">' : '<div class="logo">' + TP.esc(ap.logo_letter || 'T') + '</div>';
    const links = (ap.custom_links || []).length ? '<div class="nav-group">' + t('Liens') + '</div>' + ap.custom_links.map((l) => '<a href="' + TP.esc(l.url) + '" title="' + TP.esc(l.label) + '"' + (l.url.startsWith('http') ? ' target="_blank" rel="noopener"' : '') + '>' + TP.icon(l.icon || 'external') + '<span>' + TP.esc(l.label) + '</span></a>').join('') : '';
    if (ap.sidebar_compact) document.documentElement.classList.add('compact');
    const initials = TP.user.username.slice(0, 2).toUpperCase();
    app.innerHTML = '<aside class="sidebar" id="sidebar">' +
      '<div class="brand">' + logo + '<div class="name">' + TP.esc(TP.panelName) + '</div>' + (ap.show_version === false ? '' : '<span class="ver">v' + TP.version + '</span>') + '</div>' +
      '<nav class="nav" id="nav">' + NAV.map((n) => n.group ? '<div class="nav-group">' + TP.esc(n.group) + '</div>' : '<a href="#/' + n.id + '" data-page="' + n.id + '" title="' + TP.esc(n.label) + '">' + TP.icon(n.icon) + '<span>' + TP.esc(n.label) + '</span></a>').join('') + links + '</nav>' +
      (ap.footer_text ? '<div class="sidebar-foot">' + TP.esc(ap.footer_text) + '</div>' : '') +
      '<div class="rail-foot">' +
      '<a class="rail-user" href="#/settings" title="' + TP.esc(TP.user.username) + '"><span class="avatar">' + TP.esc(initials) + '</span><div>' + TP.esc(TP.user.username) + '<span class="sub">' + (TP.user.role === 'viewer' ? t('Lecture seule') : t('Administrateur')) + '</span></div></a>' +
      '<div class="seg" id="theme-seg">' + themeSeg() + '</div>' +
      '<div class="rail-tools"><button class="rail-btn boxed" id="btn-contrast" title="' + t('Contraste') + '"></button><button class="rail-btn boxed" id="btn-rail" title="' + t('Replier le rail') + '">' + TP.icon('collapse') + '<span>' + t('Replier') + '</span></button></div>' +
      '<button class="rail-btn" id="logout" title="' + t('Déconnexion') + '">' + TP.icon('logout') + '<span>' + t('Se déconnecter') + '</span></button>' +
      '</div></aside>' +
      '<div class="main"><header class="topbar">' +
      '<button class="ibtn hamburger" id="hamburger">' + TP.icon('menu') + '</button>' +
      '<div class="server"><span class="dot"></span><span id="top-ip">…</span><span class="muted host" id="top-host"></span></div>' +
      '<span class="badge" id="top-os"></span><div class="spacer"></div>' +
      '<div class="langmenu"><button class="ibtn" id="btn-lang" title="' + t('Langue') + '"><b style="font-size:12px">' + TP.lang.toUpperCase() + '</b></button><div class="langlist" id="langlist">' + Object.entries(TP.languages || {}).map(([k, v]) => '<button data-lang="' + k + '" class="' + (k === TP.lang ? 'on' : '') + '"><span class="code">' + k.toUpperCase() + '</span>' + TP.esc(v[0]) + '</button>').join('') + '</div></div>' +
      '<button class="ibtn" id="btn-theme" title="' + t('Thème') + '">' + TP.icon(document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon') + '</button>' +
      '<button class="ibtn" id="btn-tasks" title="' + t('Tâches en cours') + '">' + TP.icon('activity') + '</button>' +
      '<button class="ibtn" id="btn-refresh" title="' + t('Actualiser') + '">' + TP.icon('refresh') + '</button>' +
      '<button class="ibtn" id="btn-restart" title="' + t('Redémarrer le panel') + '">' + TP.icon('power') + '</button>' +
      '</header><main class="content" id="content"></main></div>';
    bindThemeSeg(); TP.applyTheme();
    document.getElementById('logout').onclick = async () => { await TP.post('/api/auth/logout'); TP.showLogin(); };
    document.getElementById('hamburger').onclick = () => document.getElementById('sidebar').classList.toggle('open');
    document.getElementById('nav').addEventListener('click', () => document.getElementById('sidebar').classList.remove('open'));
    document.getElementById('btn-contrast').onclick = () => TP.setContrast(TP.contrastPref() === 'high' ? 'glass' : 'high');
    document.getElementById('btn-rail').onclick = () => {
      const c = document.documentElement.classList.toggle('rail-collapsed'); store.set('tp-rail', c ? 'collapsed' : 'open');
      document.getElementById('btn-rail').innerHTML = TP.icon(c ? 'expand' : 'collapse') + '<span>' + t('Replier') + '</span>';
      window.dispatchEvent(new Event('resize'));
    };
    if (document.documentElement.classList.contains('rail-collapsed')) document.getElementById('btn-rail').innerHTML = TP.icon('expand') + '<span>' + t('Replier') + '</span>';
    document.getElementById('btn-theme').onclick = () => {
      TP.setTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
      document.getElementById('btn-theme').innerHTML = TP.icon(document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon');
    };
    document.getElementById('btn-tasks').onclick = () => TP.go('logs', { tab: 'tasks' });
    document.getElementById('btn-lang').onclick = (e) => { e.stopPropagation(); document.getElementById('langlist').classList.toggle('open'); };
    document.addEventListener('click', () => { const l = document.getElementById('langlist'); if (l) l.classList.remove('open'); });
    TP.qsa('#langlist button').forEach((b) => b.onclick = async () => { try { await TP.post('/api/settings', { language: b.dataset.lang }); } catch (e) {} location.reload(); });
    document.getElementById('btn-refresh').onclick = () => route();
    document.getElementById('btn-restart').onclick = async () => {
      if (!await TP.confirm(t('Redémarrer le panel'), t('Le panel sera indisponible quelques secondes.'))) return;
      try { await TP.post('/api/settings/restart'); TP.toast(t('Redémarrage…')); setTimeout(() => location.reload(), 4000); } catch (e) { TP.toast(e.message, 'error'); }
    };
    TP.get('/api/system/overview').then((r) => {
      document.getElementById('top-ip').textContent = r.data.ip;
      document.getElementById('top-host').textContent = r.data.os.hostname;
      document.getElementById('top-os').textContent = r.data.os.pretty;
      if (!r.data.panel.is_admin) TP.toast(t('Le panel ne tourne pas avec les droits administrateur : certaines actions échoueront.'), 'warn', 8000);
    }).catch(() => {});
  }

  // ---------------------------------------------------------------- routage
  async function route() {
    const name = TP.route();
    const page = TP.pages[name] || TP.pages.dashboard;
    TP.qsa('#nav a').forEach((a) => a.classList.toggle('active', a.dataset.page === name));
    const content = document.getElementById('content');
    if (!content) return;
    clearInterval(refreshTimer);
    if (currentPage && currentPage.destroy) { try { currentPage.destroy(); } catch (e) {} }
    currentPage = page;
    const seq = ++routeSeq;
    content.innerHTML = TP.loading();
    try {
      await page.render(content);
      if (seq !== routeSeq) return;
      if (page.refresh) refreshTimer = setInterval(() => { if (TP.route() === name && document.visibilityState === 'visible') { try { const p = page.refresh(content); if (p && p.catch) p.catch((e) => TP.offline(e)); } catch (e) { TP.offline(e); } } }, page.refreshMs || 5000);
    } catch (e) {
      if (seq !== routeSeq) return;
      console.error('route error', e); content.innerHTML = '<div class="alert danger">' + TP.icon('alert') + '<div>' + TP.esc(e.message) + '</div></div>';
    }
    window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', route);
  // panneau injoignable (redémarrage, réseau) : bandeau discret au lieu d'erreurs silencieuses dans la console
  let offlineEl = null, offlineSince = 0;
  TP.offline = function (e) {
    const msg = (e && e.message) || '';
    if (!/injoignable|Délai dépassé|HTTP 5/.test(msg)) return;
    if (!offlineEl) { offlineEl = document.createElement('div'); offlineEl.className = 'offline-bar'; offlineEl.textContent = t('Connexion au panel perdue, nouvelle tentative…'); document.body.appendChild(offlineEl); offlineSince = Date.now(); }
    const probe = setInterval(async () => { try { await TP.api('GET', '/api/auth/me', undefined, { noAuthRedirect: true, timeout: 5000 }); clearInterval(probe); if (offlineEl) { offlineEl.remove(); offlineEl = null; } if (Date.now() - offlineSince > 3000) route(); } catch (err) {} }, 3000);
  };
  window.addEventListener('unhandledrejection', (ev) => { if (ev.reason && ev.reason.message) { TP.offline(ev.reason); } });

  // ---------------------------------------------------------------- démarrage
  (async function boot() {
    try {
      const r = await TP.api('GET', '/api/auth/me', undefined, { noAuthRedirect: true });
      TP.user = r.data; renderShell(); route();
    } catch (e) { TP.showLogin(); }
  })();
})();
