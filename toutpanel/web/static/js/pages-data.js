/* Bases de données, FTP, Sauvegardes, Tâches planifiées */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;

  // ---------------------------------------------------------------- Bases de données
  TP.registerPage('databases', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/databases');
      const eng = r.data.engines;
      const engBadge = (name, e) => !e.available ? TP.badge(name + ' · ' + t('non installé'), '') : e.ok ? TP.badge(name + ' ' + (e.version || ''), 'ok') : TP.badge(name + ' · ' + t('connexion impossible'), 'danger');
      root.innerHTML = TP.pageHead(t('Bases de données'), engBadge('MySQL', eng.mysql) + ' ' + engBadge('PostgreSQL', eng.postgres) + ' ' + TP.badge('SQLite', 'ok'),
          '<button class="btn" id="root">' + TP.icon('key') + t('Identifiants root') + '</button><button class="btn" id="server-list">' + TP.icon('eye') + t('Bases sur le serveur') + '</button><button class="btn primary" id="add">' + TP.icon('plus') + t('Nouvelle base') + '</button>') +
        (eng.mysql.available && !eng.mysql.ok ? '<div class="alert warn mb">' + TP.icon('alert') + '<div>MySQL : ' + TP.esc(eng.mysql.error || '') + ' — ' + t('renseignez les identifiants root.') + '</div></div>' : '') +
        '<div class="card">' + TP.table([
          { label: t('Base'), render: (d) => '<b>' + TP.esc(d.name) + '</b>' + (d.remark ? ' <span class="muted small">' + TP.esc(d.remark) + '</span>' : '') },
          { label: t('Moteur'), render: (d) => TP.badge(d.engine, d.engine === 'mysql' ? 'info' : d.engine === 'postgres' ? 'violet' : '') },
          { label: t('Utilisateur'), cls: 'mono', render: (d) => TP.esc(d.username) },
          { label: t('Mot de passe'), render: (d) => '<span class="mono">••••••••</span> <button class="btn xs ghost" data-a="show" data-id="' + d.id + '">' + TP.icon('eye') + '</button><button class="btn xs ghost" data-a="copy" data-id="' + d.id + '">' + TP.icon('copy') + '</button>' },
          { label: t('Hôte'), cls: 'mono small muted', render: (d) => TP.esc(d.host) },
          { label: '', cls: 'r', render: (d) => '<div class="actions"><button class="btn xs" data-a="pwd" data-id="' + d.id + '" title="' + t('Changer le mot de passe') + '">' + TP.icon('key') + '</button><button class="btn xs" data-a="backup" data-id="' + d.id + '" title="' + t('Sauvegarder') + '">' + TP.icon('backup') + '</button>' + (d.engine === 'mysql' ? '<button class="btn xs" data-a="import" data-id="' + d.id + '" title="' + t('Importer .sql') + '">' + TP.icon('upload') + '</button>' : '') + '<button class="btn xs danger" data-a="del" data-id="' + d.id + '">' + TP.icon('trash') + '</button></div>' },
        ], r.data.databases, { empty: t('Aucune base de données'), icon: 'db' }) + '</div>';
      TP.qs('#add', root).onclick = () => TP.modal({ title: t('Nouvelle base de données'), body: '<div class="form">' +
        TP.field('engine', t('Moteur'), { type: 'select', value: eng.mysql.available ? 'mysql' : 'sqlite', options: [['mysql', 'MySQL / MariaDB'], ['postgres', 'PostgreSQL'], ['sqlite', 'SQLite (fichier)']] }) +
        TP.field('name', t('Nom de la base'), { placeholder: 'ma_base' }) + '<div class="f2">' + TP.field('username', t('Utilisateur'), { placeholder: t('= nom de la base') }) + TP.field('password', t('Mot de passe'), { placeholder: t('généré automatiquement') }) + '</div>' +
        TP.field('host', t('Accès autorisé depuis'), { type: 'select', value: 'localhost', options: [['localhost', 'localhost'], ['%', t('Tout le monde (%)')]] }) + TP.field('remark', t('Remarque')) + '</div>',
        okText: t('Créer'), onOk: async (bg) => { const rr = await TP.post('/api/databases', TP.formData(bg)); TP.toast(rr.msg); TP.modal({ title: t('Base créée'), body: '<dl class="kv"><dt>' + t('Base') + '</dt><dd>' + TP.esc(rr.data.name) + '</dd><dt>' + t('Utilisateur') + '</dt><dd>' + TP.esc(rr.data.username) + '</dd><dt>' + t('Mot de passe') + '</dt><dd class="mono">' + TP.esc(rr.data.password) + '</dd></dl>', footer: '<button class="btn primary" data-close>OK</button>', onClose: reload }); } });
      TP.qs('#root', root).onclick = async () => { const rr = await TP.get('/api/databases/root'); const m = rr.data.mysql, p = rr.data.postgres;
        TP.modal({ title: t('Identifiants administrateur'), body: '<div class="tabs"><button class="active" data-tab="mysql">MySQL</button><button data-tab="postgres">PostgreSQL</button></div>' +
          ['mysql', 'postgres'].map((e) => { const c = e === 'mysql' ? m : p; return '<div data-pane="' + e + '"' + (e === 'postgres' ? ' style="display:none"' : '') + '><div class="form"><div class="f2">' + TP.field(e + '_host', t('Hôte'), { value: c.host }) + TP.field(e + '_port', 'Port', { type: 'number', value: c.port }) + '</div><div class="f2">' + TP.field(e + '_user', t('Utilisateur'), { value: c.user }) + TP.field(e + '_password', t('Mot de passe'), { type: 'password', value: c.password }) + '</div></div></div>'; }).join(''),
          okText: t('Enregistrer'), onOpen: (bg) => TP.qsa('.tabs button', bg).forEach((b) => b.onclick = () => { TP.qsa('.tabs button', bg).forEach((x) => x.classList.toggle('active', x === b)); TP.qsa('[data-pane]', bg).forEach((pp) => pp.style.display = pp.dataset.pane === b.dataset.tab ? '' : 'none'); }),
          onOk: async (bg) => { const f = TP.formData(bg); const active = TP.qs('.tabs button.active', bg).dataset.tab; const res = await TP.post('/api/databases/root', { engine: active, host: f[active + '_host'], port: f[active + '_port'], user: f[active + '_user'], password: f[active + '_password'] }); TP.toast(res.msg, res.data.ok ? '' : 'warn'); reload(); } }); };
      TP.qs('#server-list', root).onclick = async () => { try { const rr = await TP.get('/api/databases/server/mysql'); TP.modal({ title: t('Bases présentes sur MySQL'), body: TP.table([{ label: t('Base'), render: (x) => TP.esc(x.name) }, { label: t('Tables'), render: (x) => x.tables }, { label: t('Taille'), render: (x) => TP.fmtBytes(x.size) }], rr.data), footer: '<button class="btn" data-close>' + t('Fermer') + '</button>' }); } catch (e) { TP.toast(e.message, 'error'); } };
      TP.qsa('[data-a]', root).forEach((b) => b.onclick = async () => {
        const d = r.data.databases.find((x) => x.id === Number(b.dataset.id)); const a = b.dataset.a;
        try {
          if (a === 'show') { const cell = b.parentElement.querySelector('.mono'); cell.textContent = cell.textContent.startsWith('•') ? d.password : '••••••••'; }
          else if (a === 'copy') TP.copy(d.password);
          else if (a === 'pwd') { const p = await TP.prompt(t('Nouveau mot de passe'), t('Laisser vide pour générer'), ''); if (p === null) return; const rr = await TP.post('/api/databases/' + d.id + '/password', { password: p }); TP.toast(rr.msg + ' : ' + rr.data.password, '', 8000); reload(); }
          else if (a === 'backup') { const rr = await TP.post('/api/backups', { kind: 'database', target: String(d.id) }); TP.taskModal(rr.data.task_id, t('Sauvegarde') + ' · ' + d.name); }
          else if (a === 'import') { const p = await TP.prompt(t('Importer un fichier SQL'), t('Chemin du fichier .sql sur le serveur'), ''); if (p) { const rr = await TP.post('/api/databases/' + d.id + '/import', { path: p }); TP.toast(rr.msg); } }
          else if (a === 'del') { const bg = await TP.confirm(t('Supprimer la base'), t('Supprimer {n} ?', { n: '<b>' + TP.esc(d.name) + '</b>' }), { danger: true, extra: '<label class="check mt"><input type="checkbox" name="drop" checked> ' + t('Supprimer aussi sur le serveur (irréversible)') + '</label>' }); if (bg) { const rr = await TP.del('/api/databases/' + d.id + '?drop=' + TP.qs('[name=drop]', bg).checked); TP.toast(rr.msg); reload(); } }
        } catch (e) { TP.toast(e.message, 'error'); }
      });
    },
  });

  // ---------------------------------------------------------------- FTP
  TP.registerPage('ftp', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/ftp'); const d = r.data;
      root.innerHTML = TP.pageHead(t('FTP'), t('Serveur FTP intégré (aucune installation requise).') + ' ' + (d.running ? TP.badge(t('En écoute sur le port') + ' ' + d.port, 'ok') : TP.badge(t('Arrêté'), 'danger')),
          '<button class="btn" id="srv">' + TP.icon('settings') + t('Serveur') + '</button><button class="btn primary" id="add">' + TP.icon('plus') + t('Nouvel utilisateur') + '</button>') +
        '<div class="card">' + TP.table([
          { label: t('Utilisateur'), render: (u) => '<b>' + TP.esc(u.username) + '</b>' },
          { label: t('Répertoire'), cls: 'mono small', render: (u) => '<a href="#/files?path=' + encodeURIComponent(u.home) + '">' + TP.esc(u.home) + '</a>' },
          { label: t('Droits'), render: (u) => u.perm.includes('w') ? TP.badge(t('Lecture / écriture'), 'info') : TP.badge(t('Lecture seule'), '') },
          { label: t('État'), render: (u) => u.enabled ? TP.badge(t('Actif'), 'ok') : TP.badge(t('Désactivé'), 'danger') },
          { label: '', cls: 'r', render: (u) => '<div class="actions"><button class="btn xs" data-a="pwd" data-id="' + u.id + '">' + TP.icon('key') + '</button><button class="btn xs" data-a="toggle" data-id="' + u.id + '">' + TP.icon(u.enabled ? 'stop' : 'play') + '</button><button class="btn xs" data-a="edit" data-id="' + u.id + '">' + TP.icon('edit') + '</button><button class="btn xs danger" data-a="del" data-id="' + u.id + '">' + TP.icon('trash') + '</button></div>' },
        ], d.users, { empty: t('Aucun utilisateur FTP'), icon: 'ftp' }) + '</div>';
      const userForm = (u) => '<div class="form">' + (u ? '' : TP.field('username', t('Utilisateur'))) + TP.field('password', t('Mot de passe'), { placeholder: u ? t('inchangé') : '' }) + TP.field('home', t('Répertoire racine'), { value: u ? u.home : '', placeholder: t('par défaut : wwwroot/utilisateur') }) + TP.field('perm', t('Droits'), { type: 'select', value: u ? u.perm : 'elradfmwMT', options: [['elradfmwMT', t('Lecture / écriture')], ['elr', t('Lecture seule')]] }) + '</div>';
      TP.qs('#add', root).onclick = () => TP.modal({ title: t('Nouvel utilisateur FTP'), body: userForm(), okText: t('Créer'), onOk: async (bg) => { const rr = await TP.post('/api/ftp', TP.formData(bg)); TP.toast(rr.msg); reload(); } });
      TP.qs('#srv', root).onclick = () => TP.modal({ title: t('Serveur FTP'), body: '<div class="form"><div class="f2">' + TP.field('port', 'Port', { type: 'number', value: d.port }) + TP.field('passive_ports', t('Ports passifs'), { value: d.passive_ports, hint: t('Ouvrez cette plage dans le pare-feu.') }) + '</div></div>',
        footer: '<button class="btn" data-close>' + t('Fermer') + '</button>' + (d.running ? '<button class="btn danger" data-srv="stop">' + TP.icon('stop') + t('Arrêter') + '</button><button class="btn" data-srv="restart">' + TP.icon('refresh') + t('Redémarrer') + '</button>' : '<button class="btn primary" data-srv="start">' + TP.icon('play') + t('Démarrer') + '</button>'),
        onOpen: (bg, close) => TP.qsa('[data-srv]', bg).forEach((b) => b.onclick = async () => { try { const f = TP.formData(bg); const rr = await TP.post('/api/ftp/server', { action: b.dataset.srv, port: f.port, passive_ports: f.passive_ports }); TP.toast(rr.msg); close(); reload(); } catch (e) { TP.toast(e.message, 'error'); } }) });
      TP.qsa('[data-a]', root).forEach((b) => b.onclick = async () => {
        const u = d.users.find((x) => x.id === Number(b.dataset.id)); const a = b.dataset.a;
        try {
          if (a === 'pwd') { const p = await TP.prompt(t('Nouveau mot de passe'), t('Mot de passe')); if (p) { await TP.put('/api/ftp/' + u.id, { password: p }); TP.toast(t('Mot de passe modifié')); } }
          else if (a === 'toggle') { await TP.put('/api/ftp/' + u.id, { enabled: !u.enabled }); reload(); }
          else if (a === 'edit') TP.modal({ title: t('Modifier') + ' · ' + u.username, body: userForm(u), okText: t('Enregistrer'), onOk: async (bg) => { const f = TP.formData(bg); if (!f.password) delete f.password; await TP.put('/api/ftp/' + u.id, f); TP.toast(t('Utilisateur mis à jour')); reload(); } });
          else if (a === 'del') { if (await TP.confirm(t('Supprimer'), t('Supprimer l\'utilisateur {n} ?', { n: '<b>' + TP.esc(u.username) + '</b>' }), { danger: true })) { await TP.del('/api/ftp/' + u.id); reload(); } }
        } catch (e) { TP.toast(e.message, 'error'); }
      });
    },
  });

  // ---------------------------------------------------------------- Sauvegardes
  TP.registerPage('backups', {
    async render(root) {
      const reload = () => this.render(root);
      const [r, s, d] = await Promise.all([TP.get('/api/backups'), TP.get('/api/sites'), TP.get('/api/databases')]);
      root.innerHTML = TP.pageHead(t('Sauvegardes'), t('Archives stockées dans') + ' <code>' + TP.esc(r.data.dir) + '</code> · ' + t('conservation') + ' : ' + r.data.keep + ' ' + t('par cible'),
          '<button class="btn primary" id="add">' + TP.icon('plus') + t('Nouvelle sauvegarde') + '</button>') +
        '<div class="card">' + TP.table([
          { label: t('Type'), render: (b) => TP.badge(b.kind === 'site' ? t('Site') : b.kind === 'database' ? t('Base') : t('Dossier'), b.kind === 'site' ? 'info' : b.kind === 'database' ? 'violet' : '') },
          { label: t('Cible'), render: (b) => '<b>' + TP.esc(b.target) + '</b>' },
          { label: t('Fichier'), cls: 'mono small muted', render: (b) => TP.esc(b.path.split(/[\\/]/).pop()) },
          { label: t('Taille'), render: (b) => TP.fmtBytes(b.size) },
          { label: t('Date'), cls: 'muted', render: (b) => TP.fmtDate(b.created_at) },
          { label: '', cls: 'r', render: (b) => '<div class="actions"><a class="btn xs" href="/api/backups/' + b.id + '/download">' + TP.icon('download') + '</a>' + (b.kind === 'site' ? '<button class="btn xs" data-a="restore" data-id="' + b.id + '" title="' + t('Restaurer') + '">' + TP.icon('refresh') + '</button>' : '') + '<button class="btn xs danger" data-a="del" data-id="' + b.id + '">' + TP.icon('trash') + '</button></div>' },
        ], r.data.backups, { empty: t('Aucune sauvegarde'), icon: 'backup' }) + '</div>';
      TP.qs('#add', root).onclick = () => TP.modal({ title: t('Nouvelle sauvegarde'), body: '<div class="form">' + TP.field('kind', t('Type'), { type: 'select', value: 'site', options: [['site', t('Site')], ['database', t('Base de données')], ['path', t('Dossier / fichier')]] }) +
        '<div data-k="site">' + TP.field('site', t('Site'), { type: 'select', options: s.data.sites.map((x) => [x.id, x.name]) }) + '</div><div data-k="database" style="display:none">' + TP.field('db', t('Base'), { type: 'select', options: d.data.databases.map((x) => [x.id, x.name + ' (' + x.engine + ')']) }) + '</div><div data-k="path" style="display:none">' + TP.field('path', t('Chemin'), { placeholder: '/var/www' }) + '</div></div>',
        okText: t('Lancer'), onOpen: (bg) => TP.qs('[name=kind]', bg).onchange = (e) => TP.qsa('[data-k]', bg).forEach((p) => p.style.display = p.dataset.k === e.target.value ? '' : 'none'),
        onOk: async (bg) => { const f = TP.formData(bg); const target = f.kind === 'site' ? f.site : f.kind === 'database' ? f.db : f.path; if (!target) throw new Error(t('Cible requise')); const rr = await TP.post('/api/backups', { kind: f.kind, target: String(target) }); TP.taskModal(rr.data.task_id, t('Sauvegarde'), () => reload()); } });
      TP.qsa('[data-a]', root).forEach((b) => b.onclick = async () => { const a = b.dataset.a, id = b.dataset.id; try {
        if (a === 'del') { if (await TP.confirm(t('Supprimer'), t('Supprimer cette sauvegarde ?'), { danger: true })) { await TP.del('/api/backups/' + id); reload(); } }
        else if (a === 'restore') { if (await TP.confirm(t('Restaurer'), t('Les fichiers de l\'archive écraseront ceux du site. Continuer ?'), { danger: true })) { const rr = await TP.post('/api/backups/' + id + '/restore'); TP.toast(rr.msg); } }
      } catch (e) { TP.toast(e.message, 'error'); } });
    },
  });

  // ---------------------------------------------------------------- Cron
  TP.registerPage('cron', {
    async render(root) {
      const reload = () => this.render(root);
      const [r, s, d] = await Promise.all([TP.get('/api/cron'), TP.get('/api/sites'), TP.get('/api/databases')]);
      const typeLabel = { shell: t('Commande'), url: 'URL', backup_site: t('Sauvegarde site'), backup_db: t('Sauvegarde base'), backup_path: t('Sauvegarde dossier') };
      const targetLabel = (j) => j.job_type === 'backup_site' ? (s.data.sites.find((x) => x.id === Number(j.target)) || {}).name || j.target : j.job_type === 'backup_db' ? (d.data.databases.find((x) => x.id === Number(j.target)) || {}).name || j.target : j.target;
      root.innerHTML = TP.pageHead(t('Tâches planifiées'), t('Planificateur intégré (compatible Linux et Windows).'), '<button class="btn primary" id="add">' + TP.icon('plus') + t('Nouvelle tâche') + '</button>') +
        '<div class="card">' + TP.table([
          { label: t('Tâche'), render: (j) => '<b>' + TP.esc(j.name) + '</b><div class="small muted mono">' + TP.esc(targetLabel(j)).slice(0, 80) + '</div>' },
          { label: t('Type'), render: (j) => TP.badge(typeLabel[j.job_type] || j.job_type, 'info') },
          { label: t('Planning'), cls: 'mono', render: (j) => TP.esc(j.schedule) },
          { label: t('Prochaine'), cls: 'muted', render: (j) => j.enabled ? TP.fmtDate(j.next_run) : '—' },
          { label: t('Dernière'), render: (j) => j.last_run ? '<span class="muted">' + TP.fmtDate(j.last_run) + '</span> ' + (j.last_status === 'ok' ? TP.badge('OK', 'ok') : TP.badge(t('Erreur'), 'danger')) : '<span class="muted">—</span>' },
          { label: '', cls: 'r', render: (j) => '<div class="actions"><button class="btn xs" data-a="run" data-id="' + j.id + '" title="' + t('Exécuter') + '">' + TP.icon('play') + '</button><button class="btn xs" data-a="log" data-id="' + j.id + '" title="' + t('Sortie') + '">' + TP.icon('logs') + '</button><button class="btn xs" data-a="edit" data-id="' + j.id + '">' + TP.icon('edit') + '</button><button class="btn xs danger" data-a="del" data-id="' + j.id + '">' + TP.icon('trash') + '</button></div>' },
        ], r.data, { empty: t('Aucune tâche planifiée'), icon: 'clock' }) + '</div>';
      const form = (j) => { j = j || {}; return '<div class="form">' + TP.field('name', t('Nom'), { value: j.name }) +
        '<div class="f2">' + TP.field('job_type', t('Type'), { type: 'select', value: j.job_type || 'shell', options: Object.entries(typeLabel) }) + TP.field('preset', t('Fréquence'), { type: 'select', value: '', options: [['', t('Personnalisée')], ['* * * * *', t('Chaque minute')], ['0 * * * *', t('Chaque heure')], ['0 3 * * *', t('Chaque jour à 3h')], ['0 3 * * 0', t('Chaque semaine')], ['0 3 1 * *', t('Chaque mois')]] }) + '</div>' +
        TP.field('schedule', t('Expression cron'), { value: j.schedule || '0 3 * * *', hint: 'min heure jour mois jour_semaine' }) +
        '<div data-t="shell url backup_path">' + TP.field('target', t('Commande / URL / chemin'), { type: 'textarea', value: j.target && !j.job_type?.startsWith('backup_') || j.job_type === 'backup_path' ? j.target : '', rows: 3 }) + '</div>' +
        '<div data-t="backup_site" style="display:none">' + TP.field('site', t('Site'), { type: 'select', value: j.job_type === 'backup_site' ? j.target : '', options: s.data.sites.map((x) => [x.id, x.name]) }) + '</div>' +
        '<div data-t="backup_db" style="display:none">' + TP.field('db', t('Base'), { type: 'select', value: j.job_type === 'backup_db' ? j.target : '', options: d.data.databases.map((x) => [x.id, x.name]) }) + '</div>' +
        TP.field('enabled', t('Activée'), { type: 'checkbox', value: j.enabled !== false }) + '</div>'; };
      const wire = (bg) => { const sel = TP.qs('[name=job_type]', bg); const upd = () => TP.qsa('[data-t]', bg).forEach((p) => p.style.display = p.dataset.t.split(' ').includes(sel.value) ? '' : 'none'); sel.onchange = upd; upd(); TP.qs('[name=preset]', bg).onchange = (e) => { if (e.target.value) TP.qs('[name=schedule]', bg).value = e.target.value; }; };
      const collect = (bg) => { const f = TP.formData(bg); const target = f.job_type === 'backup_site' ? f.site : f.job_type === 'backup_db' ? f.db : f.target; return { name: f.name, schedule: f.schedule, job_type: f.job_type, target: String(target || ''), enabled: f.enabled }; };
      TP.qs('#add', root).onclick = () => TP.modal({ title: t('Nouvelle tâche'), size: 'lg', body: form(), okText: t('Créer'), onOpen: wire, onOk: async (bg) => { await TP.post('/api/cron', collect(bg)); TP.toast(t('Tâche créée')); reload(); } });
      TP.qsa('[data-a]', root).forEach((b) => b.onclick = async () => { const j = r.data.find((x) => x.id === Number(b.dataset.id)); const a = b.dataset.a; try {
        if (a === 'run') { await TP.post('/api/cron/' + j.id + '/run'); TP.toast(t('Exécution lancée')); setTimeout(reload, 2500); }
        else if (a === 'log') TP.modal({ title: t('Dernière sortie') + ' · ' + j.name, size: 'lg', body: '<pre class="pre dark">' + TP.esc(j.last_output || t('(aucune exécution)')) + '</pre>', footer: '<button class="btn" data-close>' + t('Fermer') + '</button>' });
        else if (a === 'edit') TP.modal({ title: t('Modifier') + ' · ' + j.name, size: 'lg', body: form(j), okText: t('Enregistrer'), onOpen: wire, onOk: async (bg) => { await TP.put('/api/cron/' + j.id, collect(bg)); TP.toast(t('Tâche mise à jour')); reload(); } });
        else if (a === 'del') { if (await TP.confirm(t('Supprimer'), t('Supprimer la tâche {n} ?', { n: '<b>' + TP.esc(j.name) + '</b>' }), { danger: true })) { await TP.del('/api/cron/' + j.id); reload(); } }
      } catch (e) { TP.toast(e.message, 'error'); } });
    },
  });
})();
