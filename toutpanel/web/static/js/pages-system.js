/* Terminal, Docker, Logiciels, Monitoring, Processus, Journaux */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;

  // ---------------------------------------------------------------- Terminal
  let term = null, ws = null, fit = null;
  function loadScript(src) { return new Promise((res, rej) => { if (document.querySelector('script[src="' + src + '"]')) return res(); const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = rej; document.head.appendChild(s); }); }
  function loadCss(href) { if (document.querySelector('link[href="' + href + '"]')) return; const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = href; document.head.appendChild(l); }
  TP.registerPage('terminal', {
    async render(root) {
      root.innerHTML = TP.pageHead(t('Terminal'), t('Shell interactif sur le serveur (bash / PowerShell).'), '<button class="btn" id="reconnect">' + TP.icon('refresh') + t('Reconnecter') + '</button>') + '<div class="card term"><div id="xterm"></div></div>';
      try {
        loadCss('/static/vendor/xterm.min.css');
        await loadScript('/static/vendor/xterm.min.js?v=' + TP.version);
        await loadScript('/static/vendor/addon-fit.min.js?v=' + TP.version);
      } catch (e) { const box = TP.qs('#xterm', root); if (box) box.innerHTML = '<div class="alert warn">' + t('Impossible de charger xterm.js.') + '</div>'; return; }
      if (!TP.qs('#xterm', root)) return;
      const connect = () => {
        if (ws) { try { ws.close(); } catch (e) {} }
        if (term) term.dispose();
        term = new window.Terminal({ cursorBlink: true, fontFamily: 'JetBrains Mono, monospace', fontSize: 13, theme: { background: '#0b1220', foreground: '#d7e0ee', cursor: '#22c55e' }, scrollback: 5000 });
        fit = new window.FitAddon.FitAddon(); term.loadAddon(fit); term.open(TP.qs('#xterm', root)); fit.fit();
        ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws/terminal');
        ws.binaryType = 'arraybuffer';
        ws.onopen = () => { ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows })); term.focus(); };
        ws.onmessage = (e) => { if (term) term.write(typeof e.data === 'string' ? e.data : new Uint8Array(e.data)); };
        ws.onclose = () => { if (term) term.write('\r\n\x1b[31m[' + t('connexion fermée') + ']\x1b[0m\r\n'); };
        term.onData((d) => { if (ws.readyState === 1) ws.send(d); });
        term.onResize(({ cols, rows }) => { if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'resize', cols, rows })); });
      };
      connect();
      this._onResize = () => { if (fit) fit.fit(); }; window.addEventListener('resize', this._onResize);
      TP.qs('#reconnect', root).onclick = connect;
    },
    destroy() { const w = ws, tm = term; ws = term = null; if (w) { w.onmessage = w.onclose = null; w.close(); } if (tm) tm.dispose(); window.removeEventListener('resize', this._onResize); },
  });

  // ---------------------------------------------------------------- Docker
  TP.registerPage('docker', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/docker'); const d = r.data;
      root.innerHTML = TP.pageHead('Docker', d.available ? TP.badge(t('Moteur disponible'), 'ok') : TP.badge(t('Docker non disponible'), 'warn'),
          d.available ? '<button class="btn" id="pull">' + TP.icon('download') + t('Télécharger une image') + '</button><button class="btn primary" id="run">' + TP.icon('plus') + t('Nouveau conteneur') + '</button>' : '<a class="btn primary" href="#/software">' + TP.icon('box') + t('Installer Docker') + '</a>');
      if (!d.available) { root.innerHTML += '<div class="card">' + TP.empty(t('Installez Docker depuis la page Logiciels puis démarrez le service.'), 'docker') + '</div>'; return; }
      const stats = {}; (d.stats || []).forEach((s) => stats[s.id] = s);
      root.innerHTML += '<div class="card mb"><div class="card-h"><h3>' + t('Conteneurs') + '</h3></div>' + TP.table([
        { label: t('Nom'), render: (c) => '<b>' + TP.esc(c.name) + '</b><div class="small muted mono">' + c.id + '</div>' },
        { label: 'Image', cls: 'mono small', render: (c) => TP.esc(c.image) },
        { label: t('État'), render: (c) => c.state === 'running' ? TP.badge(c.status, 'ok') : TP.badge(c.status, 'danger') },
        { label: 'CPU / RAM', cls: 'small', render: (c) => { const s = stats[c.id] || stats[(c.id || '').slice(0, 12)]; return s ? s.cpu + ' · ' + s.memory : '—'; } },
        { label: t('Ports'), cls: 'small mono', render: (c) => TP.esc(c.ports || '—') },
        { label: '', cls: 'r', render: (c) => '<div class="actions">' + (c.state === 'running' ? '<button class="btn xs" data-c="stop" data-id="' + c.id + '">' + TP.icon('stop') + '</button><button class="btn xs" data-c="restart" data-id="' + c.id + '">' + TP.icon('refresh') + '</button>' : '<button class="btn xs" data-c="start" data-id="' + c.id + '">' + TP.icon('play') + '</button>') + '<button class="btn xs" data-c="logs" data-id="' + c.id + '">' + TP.icon('logs') + '</button><button class="btn xs danger" data-c="rm" data-id="' + c.id + '">' + TP.icon('trash') + '</button></div>' },
      ], d.containers, { empty: t('Aucun conteneur'), icon: 'docker' }) + '</div>' +
      '<div class="card"><div class="card-h"><h3>Images</h3></div>' + TP.table([
        { label: 'Image', render: (i) => '<b>' + TP.esc(i.repository) + '</b>:' + TP.esc(i.tag) }, { label: 'ID', cls: 'mono small muted', render: (i) => i.id }, { label: t('Taille'), render: (i) => i.size }, { label: t('Créée'), cls: 'muted', render: (i) => i.created },
        { label: '', cls: 'r', render: (i) => '<button class="btn xs danger" data-i="' + i.id + '">' + TP.icon('trash') + '</button>' },
      ], d.images, { empty: t('Aucune image') }) + '</div>';
      TP.qsa('[data-c]', root).forEach((b) => b.onclick = async () => { const a = b.dataset.c, id = b.dataset.id; try {
        if (a === 'logs') { const rr = await TP.get('/api/docker/containers/' + id + '/logs'); TP.modal({ title: 'Logs · ' + id, size: 'xl', body: '<pre class="pre dark" style="max-height:60vh">' + TP.esc(rr.data.content || '(vide)') + '</pre>', footer: '<button class="btn" data-close>' + t('Fermer') + '</button>' }); return; }
        if (a === 'rm' && !await TP.confirm(t('Supprimer'), t('Supprimer ce conteneur ?'), { danger: true })) return;
        const rr = await TP.post('/api/docker/containers/' + id + '/' + a); TP.toast(rr.msg); reload();
      } catch (e) { TP.toast(e.message, 'error'); } });
      TP.qsa('[data-i]', root).forEach((b) => b.onclick = async () => { if (await TP.confirm(t('Supprimer'), t('Supprimer cette image ?'), { danger: true })) { try { await TP.del('/api/docker/images/' + b.dataset.i); reload(); } catch (e) { TP.toast(e.message, 'error'); } } });
      TP.qs('#pull', root).onclick = async () => { const img = await TP.prompt(t('Télécharger une image'), 'Image', 'nginx:latest'); if (img) { const rr = await TP.post('/api/docker/pull', { image: img }); TP.taskModal(rr.data.task_id, 'docker pull ' + img, () => reload()); } };
      TP.qs('#run', root).onclick = () => TP.modal({ title: t('Nouveau conteneur'), size: 'lg', body: '<div class="form"><div class="f2">' + TP.field('image', 'Image', { placeholder: 'nginx:latest' }) + TP.field('name', t('Nom'), { placeholder: 'mon-nginx' }) + '</div>' + TP.field('ports', t('Ports (hôte:conteneur, un par ligne)'), { type: 'textarea', rows: 2, placeholder: '8080:80' }) + TP.field('env', t('Variables d\'environnement (CLÉ=valeur, une par ligne)'), { type: 'textarea', rows: 2 }) + TP.field('volumes', t('Volumes (hôte:conteneur, un par ligne)'), { type: 'textarea', rows: 2, placeholder: '/data/site:/usr/share/nginx/html' }) + TP.field('restart', t('Redémarrage'), { type: 'select', value: 'unless-stopped', options: [['unless-stopped', 'unless-stopped'], ['always', 'always'], ['no', 'no'], ['on-failure', 'on-failure']] }) + '</div>',
        okText: t('Démarrer'), onOk: async (bg) => { const f = TP.formData(bg); const lines = (v) => v.split('\n').map((x) => x.trim()).filter(Boolean); const rr = await TP.post('/api/docker/run', { image: f.image, name: f.name, ports: lines(f.ports), env: lines(f.env), volumes: lines(f.volumes), restart: f.restart }); TP.toast(rr.msg); reload(); } });
    },
  });

  // ---------------------------------------------------------------- Logiciels
  const COLORS = { mail: 'linear-gradient(135deg,#0ea5e9,#0369a1)', web: 'linear-gradient(135deg,#3b82f6,#1d4ed8)', php: 'linear-gradient(135deg,#7377ad,#4f5b93)', database: 'linear-gradient(135deg,#f59e0b,#d97706)', tools: 'linear-gradient(135deg,#2563eb,#1e40af)', security: 'linear-gradient(135deg,#dc2626,#991b1b)' };
  TP.registerPage('software', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/software'); const items = r.data.items;
      const cats = [['web', t('Serveurs web')], ['php', 'PHP'], ['database', t('Bases de données & cache')], ['mail', t('Messagerie')], ['tools', t('Outils')], ['security', t('Sécurité')]];
      root.innerHTML = TP.pageHead(t('Logiciels'), t('Installez les composants de votre pile web en un clic.') + ' ' + TP.badge(r.data.package_manager || t('aucun gestionnaire'), r.data.package_manager ? 'info' : 'danger'), '<a class="btn" href="#/logs">' + TP.icon('logs') + t('Historique des tâches') + '</a>') +
        cats.map(([c, label]) => { const list = items.filter((i) => i.category === c); return list.length ? '<h3 class="mb" style="margin-top:8px">' + TP.esc(label) + '</h3><div class="grid g3 mb">' + list.map((i) => '<div class="card app-tile"><div class="icon" style="background:' + COLORS[c] + '">' + TP.esc(i.name.slice(0, 2)) + '</div><div class="flex1"><h4>' + TP.esc(i.name) + ' ' + (i.installed ? (i.status ? TP.statusBadge(i.status) : TP.badge(t('Installé'), 'ok')) : '') + '</h4><p>' + TP.esc(i.desc) + '</p>' +
          (!i.supported ? TP.badge(t('Non disponible sur ce système'), '') : i.installed ? '<div class="btn-group">' + (i.service ? '<button class="btn xs" data-s="restart" data-id="' + i.id + '">' + TP.icon('refresh') + t('Redémarrer') + '</button>' + (i.status === 'running' ? '<button class="btn xs" data-s="stop" data-id="' + i.id + '">' + TP.icon('stop') + t('Arrêter') + '</button>' : '<button class="btn xs" data-s="start" data-id="' + i.id + '">' + TP.icon('play') + t('Démarrer') + '</button>') : '') + '<button class="btn xs danger" data-rm="' + i.id + '">' + TP.icon('trash') + t('Désinstaller') + '</button></div>' : '<button class="btn primary sm" data-in="' + i.id + '">' + TP.icon('download') + t('Installer') + '</button>') +
          '</div></div>').join('') + '</div>' : ''; }).join('');
      TP.qsa('[data-in]', root).forEach((b) => b.onclick = async () => { try { const rr = await TP.post('/api/software/' + b.dataset.in + '/install'); TP.taskModal(rr.data.task_id, t('Installation'), () => reload()); } catch (e) { TP.toast(e.message, 'error'); } });
      TP.qsa('[data-rm]', root).forEach((b) => b.onclick = async () => { if (await TP.confirm(t('Désinstaller'), t('Désinstaller ce logiciel ?'), { danger: true })) { try { const rr = await TP.post('/api/software/' + b.dataset.rm + '/remove'); TP.taskModal(rr.data.task_id, t('Désinstallation'), () => reload()); } catch (e) { TP.toast(e.message, 'error'); } } });
      TP.qsa('[data-s]', root).forEach((b) => b.onclick = async () => { b.disabled = true; try { const rr = await TP.post('/api/software/' + b.dataset.id + '/service', { action: b.dataset.s }); TP.toast(rr.msg); reload(); } catch (e) { TP.toast(e.message, 'error'); b.disabled = false; } });
    },
  });

  // ---------------------------------------------------------------- Monitoring
  TP.registerPage('monitor', {
    refreshMs: 30000,
    async render(root) {
      const hours = Number(TP.query().h || 24);
      root.innerHTML = TP.pageHead(t('Monitoring'), t('Historique des ressources échantillonné par le panel.'), '<div class="btn-group">' + [[1, '1h'], [6, '6h'], [24, '24h'], [168, '7j']].map(([h, l]) => '<a class="btn sm ' + (h === hours ? 'primary' : '') + '" href="#/monitor?h=' + h + '">' + l + '</a>').join('') + '</div>') +
        '<div class="grid g2"><div class="card"><div class="card-h"><h3>CPU (%)</h3></div><div class="card-b"><canvas class="chart" id="m-cpu"></canvas></div></div><div class="card"><div class="card-h"><h3>' + t('Mémoire') + ' (%)</h3></div><div class="card-b"><canvas class="chart" id="m-mem"></canvas></div></div>' +
        '<div class="card"><div class="card-h"><h3>' + t('Réseau') + '</h3><div class="legend"><span><i style="background:#2563eb"></i>' + t('Entrant') + '</span><span><i style="background:#f59e0b"></i>' + t('Sortant') + '</span></div></div><div class="card-b"><canvas class="chart" id="m-net"></canvas></div></div><div class="card"><div class="card-h"><h3>' + t('Charge (1 min)') + ' & ' + t('disque') + ' (%)</h3><div class="legend"><span><i style="background:#7c3aed"></i>' + t('Charge') + '</span><span><i style="background:#dc2626"></i>' + t('Disque') + '</span></div></div><div class="card-b"><canvas class="chart" id="m-load"></canvas></div></div></div>';
      await this.refresh(root);
    },
    async refresh(root) {
      const hours = Number(TP.query().h || 24);
      const r = await TP.get('/api/system/monitor?hours=' + hours); const rows = r.data;
      if (!rows.length) { TP.qsa('canvas', root).forEach((c) => { c.parentElement.innerHTML = TP.empty(t('Pas encore de données : revenez dans quelques minutes.'), 'monitor'); }); return; }
      const labels = rows.map((x) => { const d = new Date(x.ts + 'Z'); return hours > 24 ? d.toLocaleDateString(TP.locale || 'fr-FR', { day: '2-digit', month: '2-digit' }) + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }); });
      const c = (id) => TP.qs('#' + id, root);
      if (c('m-cpu')) TP.lineChart(c('m-cpu'), [{ color: '#2563eb', data: rows.map((x) => x.cpu) }], labels, { max: 100, format: (v) => v + '%' });
      if (c('m-mem')) TP.lineChart(c('m-mem'), [{ color: '#7c3aed', data: rows.map((x) => x.mem) }], labels, { max: 100, format: (v) => v + '%' });
      if (c('m-net')) TP.lineChart(c('m-net'), [{ color: '#2563eb', data: rows.map((x) => x.net_in) }, { color: '#f59e0b', data: rows.map((x) => x.net_out) }], labels, { format: (v) => TP.fmtBytes(v, 0) });
      if (c('m-load')) TP.lineChart(c('m-load'), [{ color: '#7c3aed', data: rows.map((x) => x.load1 * 10) }, { color: '#dc2626', data: rows.map((x) => x.disk) }], labels, { max: 100, format: (v) => v });
    },
  });

  // ---------------------------------------------------------------- Processus
  TP.registerPage('processes', {
    refreshMs: 5000,
    async render(root) {
      root.innerHTML = TP.pageHead(t('Processus'), '', '<div class="btn-group">' + [['cpu', 'CPU'], ['memory', 'RAM'], ['name', t('Nom')], ['pid', 'PID']].map(([s, l]) => '<button class="btn sm ' + ((TP.query().sort || 'cpu') === s ? 'primary' : '') + '" data-sort="' + s + '">' + l + '</button>').join('') + '</div><div class="search" style="width:220px">' + TP.icon('search') + '<input class="input" id="pfilter" placeholder="' + t('Filtrer…') + '"></div>') + '<div class="card" id="plist">' + TP.loading() + '</div>';
      TP.qsa('[data-sort]', root).forEach((b) => b.onclick = () => { TP.go('processes', { sort: b.dataset.sort }); });
      TP.qs('#pfilter', root).oninput = TP.debounce(() => this.refresh(root), 200);
      await this.refresh(root);
    },
    async refresh(root) {
      const sort = TP.query().sort || 'cpu';
      const r = await TP.get('/api/system/processes?sort=' + sort);
      const q = (TP.qs('#pfilter', root) || {}).value || '';
      const rows = r.data.filter((p) => !q || (p.name + ' ' + p.cmdline + ' ' + p.user).toLowerCase().includes(q.toLowerCase())).slice(0, 150);
      const box = TP.qs('#plist', root); if (!box) return;
      box.innerHTML = TP.table([
        { label: 'PID', cls: 'mono', render: (p) => p.pid }, { label: t('Nom'), render: (p) => '<b>' + TP.esc(p.name) + '</b><div class="small muted mono" style="max-width:420px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + TP.esc(p.cmdline) + '">' + TP.esc(p.cmdline) + '</div>' },
        { label: t('Utilisateur'), cls: 'muted', render: (p) => TP.esc(p.user) }, { label: 'CPU', render: (p) => p.cpu.toFixed(1) + '%' }, { label: 'RAM', render: (p) => TP.fmtBytes(p.memory) }, { label: t('État'), render: (p) => TP.badge(p.status, p.status === 'running' ? 'ok' : '') },
        { label: '', cls: 'r', render: (p) => '<div class="actions"><button class="btn xs" data-k="' + p.pid + '" data-f="0" title="SIGTERM">' + TP.icon('stop') + '</button><button class="btn xs danger" data-k="' + p.pid + '" data-f="1" title="SIGKILL">' + TP.icon('x') + '</button></div>' },
      ], rows, { empty: t('Aucun processus') });
      TP.qsa('[data-k]', box).forEach((b) => b.onclick = async () => { if (await TP.confirm(t('Terminer le processus'), 'PID ' + b.dataset.k + (b.dataset.f === '1' ? ' (kill -9)' : ''), { danger: true })) { try { const rr = await TP.post('/api/system/processes/kill', { pid: Number(b.dataset.k), force: b.dataset.f === '1' }); TP.toast(rr.msg); this.refresh(root); } catch (e) { TP.toast(e.message, 'error'); } } });
    },
  });

  // ---------------------------------------------------------------- Journaux
  TP.registerPage('logs', {
    async render(root) {
      const [r, tk] = await Promise.all([TP.get('/api/system/logs'), TP.get('/api/system/tasks')]);
      const logs = r.data;
      root.innerHTML = TP.pageHead(t('Journaux'), t('Journaux du panel, des sites, du système et historique des tâches.')) +
        '<div class="tabs"><button class="active" data-tab="files">' + t('Fichiers journaux') + '</button><button data-tab="journal">' + t('Journal système') + '</button><button data-tab="tasks">' + t('Tâches') + ' (' + tk.data.length + ')</button></div>' +
        '<div data-pane="files"><div class="card"><div class="card-h"><div class="row"><select class="input" id="log-sel" style="width:auto;min-width:280px">' + logs.map((l) => '<option value="' + TP.esc(l.path) + '">' + TP.esc(l.label) + '</option>').join('') + '</select><select class="input" id="log-n" style="width:auto"><option value="200">200 ' + t('lignes') + '</option><option value="1000">1000</option><option value="5000">5000</option></select></div><div class="btn-group"><button class="btn sm" id="log-refresh">' + TP.icon('refresh') + t('Actualiser') + '</button><button class="btn sm danger" id="log-clear">' + TP.icon('trash') + t('Vider') + '</button></div></div><div class="card-b p0"><pre class="pre dark" id="log-out" style="border:none;border-radius:0 0 14px 14px;max-height:65vh;min-height:300px"></pre></div></div></div>' +
        '<div data-pane="journal" style="display:none"><div class="card"><div class="card-h"><div class="row"><input class="input" id="j-unit" placeholder="' + t('Unité (ex: nginx), vide = tout') + '" style="width:260px"><button class="btn sm" id="j-load">' + TP.icon('refresh') + t('Charger') + '</button></div></div><div class="card-b p0"><pre class="pre dark" id="j-out" style="border:none;border-radius:0 0 14px 14px;max-height:65vh;min-height:300px"></pre></div></div></div>' +
        '<div data-pane="tasks" style="display:none"><div class="card">' + TP.table([{ label: '#', render: (x) => x.id }, { label: t('Tâche'), render: (x) => '<b>' + TP.esc(x.name) + '</b>' }, { label: t('État'), render: (x) => x.status === 'done' ? TP.badge(t('Terminé'), 'ok') : x.status === 'error' ? TP.badge(t('Erreur'), 'danger') : TP.badge(t('En cours'), 'info') }, { label: t('Date'), cls: 'muted', render: (x) => TP.fmtDate(x.created_at) }, { label: '', cls: 'r', render: (x) => '<button class="btn xs" data-task="' + x.id + '">' + TP.icon('logs') + t('Journal') + '</button>' }], tk.data, { empty: t('Aucune tâche') }) + '</div></div>';
      TP.qsa('.tabs button', root).forEach((b) => b.onclick = () => { TP.qsa('.tabs button', root).forEach((x) => x.classList.toggle('active', x === b)); TP.qsa('[data-pane]', root).forEach((p) => p.style.display = p.dataset.pane === b.dataset.tab ? '' : 'none'); });
      const loadLog = async () => { const p = TP.qs('#log-sel', root).value; if (!p) return; try { const rr = await TP.get('/api/system/logs/read?path=' + encodeURIComponent(p) + '&lines=' + TP.qs('#log-n', root).value); const pre = TP.qs('#log-out', root); pre.textContent = rr.data.content || '(' + t('vide') + ')'; pre.scrollTop = pre.scrollHeight; } catch (e) { TP.toast(e.message, 'error'); } };
      TP.qs('#log-sel', root).onchange = loadLog; TP.qs('#log-n', root).onchange = loadLog; TP.qs('#log-refresh', root).onclick = loadLog; loadLog();
      TP.qs('#log-clear', root).onclick = async () => { if (await TP.confirm(t('Vider le journal'), t('Le contenu du fichier sera effacé.'), { danger: true })) { await TP.post('/api/system/logs/clear', { path: TP.qs('#log-sel', root).value }); loadLog(); } };
      const loadJ = async () => { try { const rr = await TP.get('/api/system/logs/journal?unit=' + encodeURIComponent(TP.qs('#j-unit', root).value)); TP.qs('#j-out', root).textContent = rr.data.content || '(' + t('vide') + ')'; } catch (e) { TP.toast(e.message, 'error'); } };
      TP.qs('#j-load', root).onclick = loadJ;
      TP.qsa('[data-task]', root).forEach((b) => b.onclick = () => TP.taskModal(Number(b.dataset.task), t('Tâche') + ' #' + b.dataset.task));
      const want = TP.query().tab; const tb = want && TP.qs('.tabs button[data-tab="' + want + '"]', root); if (tb) tb.click();
    },
  });
})();
