/* Tableau de bord */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;
  let netHist = { in: [], out: [], labels: [] }, cpuHist = { cpu: [], mem: [], labels: [] };

  function gaugeCard(label, pct, val, sub) {
    return '<div class="card gauge-card"><div><div class="lbl">' + TP.esc(label) + '</div><div class="val">' + val + '</div>' + (sub ? '<div class="sub">' + sub + '</div>' : '') + '</div>' + TP.gauge(pct) + '</div>';
  }

  function overviewCard(icon, title, body, link) {
    return '<a class="card stat" href="#/' + link + '" style="color:inherit"><div class="k">' + TP.esc(title) + '<span class="ico">' + TP.icon(icon) + '</span></div><div>' + body + '</div></a>';
  }

  async function loadCounts() {
    const [s, f, d, fw] = await Promise.all([TP.get('/api/sites'), TP.get('/api/ftp'), TP.get('/api/databases'), TP.get('/api/firewall/login-logs?limit=1')]);
    const sites = s.data.sites, fails = fw.data;
    return { sites: sites.length, sitesOn: sites.filter((x) => x.enabled).length, ssl: sites.filter((x) => x.ssl_enabled).length,
      ftp: f.data.users.length, ftpRunning: f.data.running, dbs: d.data.databases.length, lastLogin: fails[0] };
  }

  function drawCharts(root) {
    const c1 = TP.qs('#chart-net', root), c2 = TP.qs('#chart-cpu', root);
    if (c1) TP.lineChart(c1, [{ color: '#2563eb', data: netHist.in }, { color: '#f59e0b', data: netHist.out }], netHist.labels, { format: (v) => TP.fmtBytes(v, 0) });
    if (c2) TP.lineChart(c2, [{ color: '#2563eb', data: cpuHist.cpu }, { color: '#7c3aed', data: cpuHist.mem }], cpuHist.labels, { max: 100, format: (v) => v + '%' });
  }

  function pushHist(o) {
    const lbl = new Date().toLocaleTimeString(TP.locale || 'fr-FR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    netHist.in.push(o.network.in); netHist.out.push(o.network.out); netHist.labels.push(lbl);
    cpuHist.cpu.push(o.cpu.percent); cpuHist.mem.push(o.memory.percent); cpuHist.labels.push(lbl);
    [netHist.in, netHist.out, netHist.labels, cpuHist.cpu, cpuHist.mem, cpuHist.labels].forEach((a) => { while (a.length > 60) a.shift(); });
  }

  function renderGauges(o) {
    const loadPct = Math.min(100, (o.load['1'] / Math.max(1, o.cpu.threads)) * 100);
    let html = gaugeCard(t('Charge'), loadPct, o.load['1'] + ' / ' + o.load['5'] + ' / ' + o.load['15'], loadPct < 70 ? t('Normale') : t('Élevée'));
    html += gaugeCard(t('CPU'), o.cpu.percent, o.cpu.cores + ' ' + t('cœurs') + ' · ' + o.cpu.threads + ' ' + t('threads'), o.cpu.freq_mhz ? Math.round(o.cpu.freq_mhz) + ' MHz' : '');
    html += gaugeCard(t('RAM'), o.memory.percent, '<b>' + TP.fmtBytes(o.memory.used, 1) + '</b> / ' + TP.fmtBytes(o.memory.total, 0), o.swap.total ? 'Swap ' + TP.fmtBytes(o.swap.used) + ' / ' + TP.fmtBytes(o.swap.total) : '');
    const disks = o.disks.slice().sort((a, b) => b.total - a.total).slice(0, window.innerWidth < 1500 ? 1 : 2);
    disks.forEach((d) => { html += gaugeCard(d.mountpoint, d.percent, '<b>' + TP.fmtBytes(d.used, 1) + '</b> / ' + TP.fmtBytes(d.total, 1), d.fstype + ' · ' + TP.esc(d.device)); });
    return html;
  }

  TP.registerPage('dashboard', {
    refreshMs: 3000,
    async render(root) {
      const [ov, svc, settings] = await Promise.all([TP.get('/api/system/overview'), TP.get('/api/system/services'), TP.get('/api/settings')]);
      const o = ov.data; pushHist(o);
      const counts = await loadCounts().catch(() => null);
      root.innerHTML =
        TP.pageHead(t('Accueil'), TP.esc(o.os.pretty) + ' · ' + t('démarré depuis') + ' ' + TP.fmtDuration(o.uptime),
          '<span class="badge ok"><i class="dot"></i>' + TP.esc(o.panel.webserver) + '</span><span class="badge info">Python ' + o.panel.python + '</span>' + (o.panel.is_admin ? '' : '<span class="badge warn">' + t('droits limités') + '</span>')) +
        '<div class="gauges" id="gauges">' + renderGauges(o) + '</div>' +
        '<div class="grid g5 mb" id="overview">' +
        overviewCard('globe', t('Sites'), counts ? '<div class="v">' + counts.sitesOn + '<small>/ ' + counts.sites + ' ' + t('actifs') + '</small></div><div class="small muted">' + counts.ssl + ' ' + t('avec SSL') + '</div>' : '—', 'sites') +
        overviewCard('ftp', t('FTP'), counts ? '<div class="v">' + counts.ftp + '<small>' + t('comptes') + '</small></div><div class="small">' + (counts.ftpRunning ? TP.badge(t('Serveur actif'), 'ok') : TP.badge(t('Serveur arrêté'), '')) + '</div>' : '—', 'ftp') +
        overviewCard('db', t('Bases de données'), counts ? '<div class="v">' + counts.dbs + '<small>' + t('bases') + '</small></div>' : '—', 'databases') +
        overviewCard('shield', t('Sécurité'), counts ? '<div class="v" style="font-size:15px">' + (settings.data.totp_enabled ? TP.badge('2FA ' + t('activée'), 'ok') : TP.badge('2FA ' + t('inactive'), 'warn')) + '</div><div class="small muted">' + (counts.lastLogin ? t('Dernière connexion') + ' : ' + TP.fmtDate(counts.lastLogin.created_at) + ' (' + counts.lastLogin.ip + ')' : '') + '</div>' : '—', 'security') +
        '<div class="card stat memo"><div class="k">' + t('Mémo') + '<span class="ico">' + TP.icon('edit') + '</span></div><textarea class="input" id="memo" placeholder="' + t('Notes rapides…') + '">' + TP.esc(settings.data.memo || '') + '</textarea></div>' +
        '</div>' +
        renderWatch(o, svc.data, counts, settings.data) +
        '<div class="card mb"><div class="card-h"><h3>' + t('Actions rapides') + '</h3><span class="muted small">' + t('Les modules les plus utilisés, à un clic.') + '</span></div><div class="card-b"><div class="tiles">' +
        tile('sites', 'globe', '', t('Nouveau site'), t('Nginx / Apache, PHP au choix, SSL')) +
        tile('wordpress', 'wp', 'violet', t('Installer WordPress'), t('En un clic, base créée automatiquement')) +
        tile('php', 'php', 'green', t('Versions PHP'), t('Installer 5.6 à 8.4 côte à côte')) +
        tile('databases', 'db', 'warn', t('Base de données'), t('MySQL, PostgreSQL, import SQL')) +
        tile('mail', 'mail', '', t('Serveur mail'), t('Domaines, boîtes, DKIM, DNS')) +
        tile('waf', 'waf', 'violet', t('Pare-feu applicatif'), t('Règles, bannissements, journal')) +
        tile('backups', 'backup', 'green', t('Sauvegarde'), t('Sites, bases, dossiers, restauration')) +
        tile('software', 'box', 'warn', t('Logiciels'), t('Installer la pile en un clic')) +
        '</div></div></div>' +
        '<div class="grid g2 mb">' +
        '<div class="card"><div class="card-h"><h3>' + t('Trafic réseau') + '</h3><div class="legend"><span><i style="background:#2563eb"></i>' + t('Entrant') + ' <b id="net-in"></b></span><span><i style="background:#f59e0b"></i>' + t('Sortant') + ' <b id="net-out"></b></span></div></div><div class="card-b"><canvas class="chart" id="chart-net"></canvas><div class="row between small muted mt"><span>' + t('Total reçu') + ' : ' + TP.fmtBytes(o.network.total.bytes_recv) + '</span><span>' + t('Total envoyé') + ' : ' + TP.fmtBytes(o.network.total.bytes_sent) + '</span></div></div></div>' +
        '<div class="card"><div class="card-h"><h3>' + t('CPU & mémoire') + '</h3><div class="legend"><span><i style="background:#2563eb"></i>CPU</span><span><i style="background:#7c3aed"></i>RAM</span></div></div><div class="card-b"><canvas class="chart" id="chart-cpu"></canvas></div></div>' +
        '</div>' +
        '<div class="grid g2">' +
        '<div class="card"><div class="card-h"><h3>' + t('Services') + '</h3><a class="btn sm" href="#/software">' + TP.icon('box') + t('Logiciels') + '</a></div><div class="card-b p0" id="services">' + renderServices(svc.data) + '</div></div>' +
        '<div class="card"><div class="card-h"><h3>' + t('Informations système') + '</h3></div><div class="card-b"><dl class="kv">' +
        '<dt>' + t('Hôte') + '</dt><dd>' + TP.esc(o.os.hostname) + '</dd><dt>IP</dt><dd>' + o.ip + '</dd><dt>' + t('Système') + '</dt><dd>' + TP.esc(o.os.pretty) + '</dd><dt>' + t('Noyau') + '</dt><dd>' + TP.esc(o.os.release) + '</dd>' +
        '<dt>' + t('Architecture') + '</dt><dd>' + o.os.machine + '</dd><dt>' + t('Processus') + '</dt><dd>' + o.processes + '</dd><dt>' + t('Répertoire panel') + '</dt><dd class="mono">' + TP.esc(o.panel.home) + '</dd><dt>' + t('Serveur web') + '</dt><dd>' + o.panel.webserver + '</dd>' +
        '</dl></div></div></div>';
      drawCharts(root);
      TP.qs('#memo', root).addEventListener('input', TP.debounce(async (e) => { try { await TP.post('/api/settings', { memo: e.target.value }); } catch (err) {} }, 800));
      TP.qsa('[data-svc-action]', root).forEach(bindSvc);
    },
    async refresh(root) {
      const ov = await TP.get('/api/system/overview'); const o = ov.data; pushHist(o);
      const g = TP.qs('#gauges', root); if (g) g.innerHTML = renderGauges(o);
      const ni = TP.qs('#net-in', root), no = TP.qs('#net-out', root);
      if (ni) { ni.textContent = TP.fmtRate(o.network.in); no.textContent = TP.fmtRate(o.network.out); }
      drawCharts(root);
    },
  });

  function tile(page, icon, cls, title, sub) {
    return '<a class="tile ' + cls + '" href="#/' + page + '"><span class="tico">' + TP.icon(icon) + '</span><div><b>' + TP.esc(title) + '</b><span>' + TP.esc(sub) + '</span></div></a>';
  }
  // « À regarder » : ce qui mérite l'attention, sinon rien
  function renderWatch(o, services, counts, settings) {
    const items = [];
    const disk = (o.disks || []).find((d) => d.percent >= 85); if (disk) items.push(['danger', t('Disque {m} rempli à {p} %', { m: disk.mountpoint, p: disk.percent }), t('Libérez de l\'espace ou agrandissez le volume.'), 'files']);
    if (o.memory.percent >= 90) items.push(['warn', t('Mémoire utilisée à {p} %', { p: o.memory.percent }), t('Vérifiez les processus gourmands.'), 'processes']);
    const optional = ['postgresql', 'docker', 'memcached', 'redis'];
    services.filter((s) => s.status === 'stopped' && !s.builtin && !optional.includes(s.name || s.label)).forEach((s) => items.push(['warn', t('Service {s} arrêté', { s: s.label }), t('Redémarrez-le ou vérifiez ses journaux.'), 'logs']));
    if (!settings.totp_enabled) items.push(['info', t('Double authentification inactive'), t('Activez la 2FA pour protéger l\'accès au panel.'), 'settings']);
    if (counts && counts.sites && counts.ssl < counts.sites) items.push(['info', t('{n} site(s) sans certificat SSL', { n: counts.sites - counts.ssl }), t('Let\'s Encrypt est gratuit et automatique.'), 'sites']);
    if (!o.panel.is_admin) items.push(['danger', t('Droits administrateur absents'), t('Lancez le panel en root / administrateur.'), 'settings']);
    if (!items.length) return '';
    return '<div class="card mb"><div class="card-h"><h3>' + t('À regarder') + '</h3><span class="badge">' + items.length + '</span></div><div class="card-b watch">' +
      items.slice(0, 6).map((i) => '<a class="alert ' + i[0] + '" href="#/' + i[3] + '"><span><b>' + TP.esc(i[1]) + '</b><span class="small muted">' + TP.esc(i[2]) + '</span></span>' + TP.icon('chevron') + '</a>').join('') + '</div></div>';
  }
  function renderServices(list) {
    return '<table class="tbl"><tbody>' + list.map((s) => '<tr><td><b>' + TP.esc(s.label) + '</b>' + (s.service ? ' <span class="muted small mono">' + TP.esc(s.service) + '</span>' : '') + '</td><td>' + TP.statusBadge(s.status) + '</td><td class="actions">' +
      (s.status === 'missing' ? '<a class="btn xs" href="#/software">' + t('Installer') + '</a>' :
        (s.builtin ? '<a class="btn xs" href="#/ftp">' + t('Gérer') + '</a>' :
          '<button class="btn xs" data-svc-action="restart" data-svc="' + TP.esc(s.service) + '">' + TP.icon('refresh') + '</button>' +
          (s.status === 'running' ? '<button class="btn xs" data-svc-action="stop" data-svc="' + TP.esc(s.service) + '">' + TP.icon('stop') + '</button>' : '<button class="btn xs" data-svc-action="start" data-svc="' + TP.esc(s.service) + '">' + TP.icon('play') + '</button>'))) +
      '</td></tr>').join('') + '</tbody></table>';
  }
  function bindSvc(btn) {
    btn.onclick = async () => {
      btn.disabled = true;
      try { const r = await TP.post('/api/system/services/action', { name: btn.dataset.svc, action: btn.dataset.svcAction }); TP.toast(r.msg);
        const svc = await TP.get('/api/system/services'); const box = TP.qs('#services'); box.innerHTML = renderServices(svc.data); TP.qsa('[data-svc-action]', box).forEach(bindSvc); }
      catch (e) { TP.toast(e.message, 'error'); btn.disabled = false; }
    };
  }
})();
