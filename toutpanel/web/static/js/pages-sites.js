/* Sites web, WP Toolkit, Domaines */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;
  let meta = { php_versions: [], webserver: 'nginx', www_root: '' };

  const phpOptions = () => [['', t('Statique / aucun')]].concat(meta.php_versions.map((v) => [v, 'PHP ' + v]));

  function siteForm(s) {
    s = s || {};
    return '<div class="form">' +
      (s.id ? '' : TP.field('name', t('Nom du site'), { value: s.name, placeholder: 'monsite', hint: t('Identifiant technique (dossier, vhost).') })) +
      TP.field('domains', t('Domaines'), { type: 'textarea', value: (s.domains || []).join('\n'), placeholder: 'exemple.com\nwww.exemple.com', rows: 3, hint: t('Un domaine par ligne. Le premier est le domaine principal.') }) +
      '<div class="f2">' + TP.field('site_type', t('Type'), { type: 'select', value: s.site_type || 'php', options: [['php', 'PHP'], ['static', t('Statique (HTML)')], ['proxy', t('Reverse proxy')]] }) +
      TP.field('php_version', t('Version PHP'), { type: 'select', value: s.php_version || '', options: phpOptions() }) + '</div>' +
      '<div id="proxy-box">' + TP.field('proxy_target', t('Cible du proxy'), { value: s.proxy_target, placeholder: 'http://127.0.0.1:3000', hint: t('Un seul serveur. Pour en répartir plusieurs, remplissez la liste ci-dessous : elle remplace la cible unique.') }) +
      '<div class="card" style="padding:12px 14px;margin-bottom:12px"><div class="row between mb"><b>' + t('Répartition de charge') + '</b>' + (s.id ? '<button class="btn xs" type="button" id="lb-check">' + TP.icon('activity') + t('Vérifier les serveurs') + '</button>' : '') + '</div>' +
      TP.field('upstreams_text', t('Serveurs en amont (un par ligne)'), { type: 'textarea', rows: 3, value: (s.upstreams || []).map((u) => u.url + (u.weight && u.weight !== 1 ? ' poids=' + u.weight : '') + (u.backup ? ' secours' : '') + (u.max_fails !== undefined && u.max_fails !== 3 ? ' echecs=' + u.max_fails : '') + (u.fail_timeout !== undefined && u.fail_timeout !== 10 ? ' delai=' + u.fail_timeout : '')).join('\n'), placeholder: 'http://10.0.0.2:8080 poids=2\nhttp://10.0.0.3:8080\nhttp://10.0.0.4:8080 secours', hint: t('Options par ligne : poids=N (1-100), secours (utilisé seulement si les autres sont en panne), echecs=N et delai=S (serveur écarté après N échecs pendant S secondes).') }) +
      '<div class="f2">' + TP.field('lb_method', t('Méthode'), { type: 'select', value: s.lb_method || 'round_robin', options: [['round_robin', t('Tour de rôle (round-robin)')], ['least_conn', t('Moins de connexions actives')], ['ip_hash', t('IP hash (sessions collantes)')]] }) + TP.field('lb_keepalive', t('Connexions keepalive vers les serveurs'), { type: 'number', value: s.lb_keepalive === undefined ? 32 : s.lb_keepalive, hint: t('0 = désactivé.') }) + '</div>' +
      '<div id="lb-status"></div></div></div>' +
      TP.field('root', t('Répertoire racine'), { value: s.root || '', placeholder: meta.www_root + '/…', hint: s.id ? '' : t('Laisser vide pour la valeur par défaut.') }) +
      TP.field('remark', t('Remarque'), { value: s.remark }) +
      TP.field('php_isolation', t('Isolation PHP (open_basedir) : le site ne peut lire que sa racine et /tmp'), { type: 'checkbox', value: s.id ? !!s.php_isolation : true, hint: t('Recommandé. Désactivez seulement si l\'application doit lire des fichiers hors de sa racine.') }) +
      '</div>';
  }
  const parseDomains = (v) => v.split(/[\n,;\s]+/).map((x) => x.trim()).filter(Boolean);
  const parseUpstreams = (v) => String(v || '').split('\n').map((l) => l.trim()).filter(Boolean).map((l) => { const parts = l.split(/\s+/); const u = { url: parts[0], weight: 1, backup: false, max_fails: 3, fail_timeout: 10 }; parts.slice(1).forEach((o) => { const m = o.match(/^(poids|weight)=(\d+)$/i); if (m) u.weight = Number(m[2]); else if (/^(secours|backup)$/i.test(o)) u.backup = true; else if ((m2 = o.match(/^(echecs|max_fails)=(\d+)$/i))) u.max_fails = Number(m2[2]); else if ((m3 = o.match(/^(delai|fail_timeout)=(\d+)$/i))) u.fail_timeout = Number(m3[2]); }); return u; });
  let m2, m3;
  const withLb = (d) => { d.upstreams = parseUpstreams(d.upstreams_text); delete d.upstreams_text; d.lb_keepalive = Number(d.lb_keepalive || 0); if (d.site_type !== 'proxy') { d.upstreams = []; } return d; };
  const bindLbCheck = (bg, s) => { const b = TP.qs('#lb-check', bg); if (!b) return; b.onclick = async () => { const box = TP.qs('#lb-status', bg); box.innerHTML = TP.loading(); try { const r = (await TP.get('/api/sites/' + s.id + '/upstreams/check')).data; box.innerHTML = TP.table([{ label: t('Serveur'), cls: 'mono small', render: (x) => TP.esc(x.url) + (x.backup ? ' ' + TP.badge(t('secours'), '') : '') }, { label: t('État'), render: (x) => x.ok ? TP.badge('HTTP ' + x.status, 'ok') : TP.badge(x.status ? 'HTTP ' + x.status : t('injoignable'), 'danger') + (x.error ? ' <span class="small muted">' + TP.esc(x.error) + '</span>' : '') }, { label: t('Latence'), cls: 'small', render: (x) => x.ms + ' ms' }], r.servers, { empty: t('Aucun serveur configuré') }); } catch (e) { box.innerHTML = '<div class="alert danger">' + TP.esc(e.message) + '</div>'; } }; };

  const bindTypeToggle = (bg) => { const sel = TP.qs('[name=site_type]', bg), box = TP.qs('#proxy-box', bg); if (!sel || !box) return; const sync = () => { box.style.display = sel.value === 'proxy' ? '' : 'none'; }; sel.onchange = sync; sync(); };
  function openCreate(reload) {
    TP.modal({ title: t('Nouveau site'), size: 'lg', body: siteForm(), okText: t('Créer'), onOpen: (bg) => bindTypeToggle(bg),
      onOk: async (bg) => { const d = withLb(TP.formData(bg)); d.domains = parseDomains(d.domains); if (!d.name) d.name = (d.domains[0] || '').replace(/^www\./, '');
        const lb = { upstreams: d.upstreams, lb_method: d.lb_method, lb_keepalive: d.lb_keepalive }; delete d.upstreams; delete d.lb_method; delete d.lb_keepalive;
        const r = await TP.post('/api/sites', d); if (lb.upstreams.length) { await TP.put('/api/sites/' + r.data.id, lb); } TP.toast(r.msg, r.msg.includes('échou') || r.msg.includes('installé') ? 'warn' : ''); reload(); } });
  }
  function openEdit(s, reload, tab) {
    TP.modal({ title: t('Paramètres du site') + ' · ' + s.name, size: 'lg', okText: t('Enregistrer'),
      body: '<div class="tabs"><button class="' + (tab === 'git' ? '' : 'active') + '" data-stab="gen">' + TP.icon('settings') + ' ' + t('Général') + '</button><button class="' + (tab === 'git' ? 'active' : '') + '" data-stab="git">' + TP.icon('git') + ' ' + t('Déploiement Git') + (s.git ? ' <span class="badge ok">' + TP.esc(s.git.branch) + '</span>' : '') + '</button></div>' +
        '<div data-spane="gen"' + (tab === 'git' ? ' style="display:none"' : '') + '>' + siteForm(s) + '</div><div data-spane="git"' + (tab === 'git' ? '' : ' style="display:none"') + '><div id="git-pane"></div></div>',
      onOpen: (bg) => {
        const show = (k) => { TP.qsa('[data-stab]', bg).forEach((x) => x.classList.toggle('active', x.dataset.stab === k)); TP.qsa('[data-spane]', bg).forEach((p) => p.style.display = p.dataset.spane === k ? '' : 'none'); const ok = TP.qs('[data-ok]', bg); if (ok) ok.style.display = k === 'git' ? 'none' : ''; if (k === 'git' && !bg._gitLoaded) { bg._gitLoaded = true; TP.renderGitPane(s, TP.qs('#git-pane', bg), reload); } };
        TP.qsa('[data-stab]', bg).forEach((b) => b.onclick = () => show(b.dataset.stab));
        bindLbCheck(bg, s); bindTypeToggle(bg);
        if (tab === 'git') show('git');
      },
      onOk: async (bg) => { const d = withLb(TP.formData(TP.qs('[data-spane=gen]', bg))); d.domains = parseDomains(d.domains); const r = await TP.put('/api/sites/' + s.id, d); TP.toast(r.msg); reload(); } });
  }
  async function openConfig(s) {
    const r = await TP.get('/api/sites/' + s.id + '/config');
    TP.modal({ title: t('Configuration') + ' ' + r.data.webserver + ' · ' + s.name, size: 'xl',
      body: '<div class="tabs"><button class="active" data-tab="gen">' + t('Générée') + '</button><button data-tab="custom">' + t('Personnalisée') + '</button></div>' +
        '<div data-pane="gen"><p class="muted small">' + t('Fichier généré automatiquement par ToutPanel. Ne pas modifier : utilisez l\'onglet personnalisé.') + '</p><pre class="pre" style="max-height:460px">' + TP.esc(r.data.generated) + '</pre></div>' +
        '<div data-pane="custom" style="display:none"><p class="muted small">' + t('Directives additionnelles incluses dans le bloc server / VirtualHost') + ' — <code>' + TP.esc(r.data.custom_path) + '</code></p><textarea class="input" name="content" style="min-height:400px">' + TP.esc(r.data.custom) + '</textarea></div>',
      okText: t('Enregistrer'),
      onOpen: (bg) => TP.qsa('.tabs button', bg).forEach((b) => b.onclick = () => { TP.qsa('.tabs button', bg).forEach((x) => x.classList.toggle('active', x === b)); TP.qsa('[data-pane]', bg).forEach((p) => p.style.display = p.dataset.pane === b.dataset.tab ? '' : 'none'); }),
      onOk: async (bg) => { const rr = await TP.post('/api/sites/' + s.id + '/config', { content: TP.qs('[name=content]', bg).value }); TP.toast(rr.msg); } });
  }
  async function openSsl(s, reload) {
    const r = await TP.get('/api/sites/' + s.id + '/ssl');
    const info = r.data.info;
    const body = (info && info.exists ? '<div class="alert ' + (info.days_left > 14 ? 'ok' : 'warn') + ' mb">' + TP.icon('lock') + '<div><b>' + (s.ssl_enabled ? t('SSL actif') : t('Certificat présent, SSL inactif')) + '</b> — ' + t('expire dans') + ' ' + info.days_left + ' ' + t('jours') + (info.self_signed ? ' (' + t('auto-signé') + ')' : '') + '<br><span class="small">' + TP.esc((info.domains || []).join(', ')) + '</span></div></div>' : '<div class="alert info mb">' + TP.icon('info') + '<div>' + t('Aucun certificat installé pour ce site.') + '</div></div>') +
      '<div class="tabs"><button class="active" data-tab="le">Let\'s Encrypt</button><button data-tab="self">' + t('Auto-signé') + '</button><button data-tab="manual">' + t('Manuel') + '</button></div>' +
      '<div data-pane="le"><p class="small muted">' + t('Certificat gratuit et reconnu. Le domaine doit pointer vers ce serveur et le port 80 être accessible.') + (r.data.certbot ? '' : ' <b class="badge warn">certbot ' + t('non installé') + '</b>') + '</p>' + TP.field('email', 'Email', { placeholder: 'admin@' + (s.domains[0] || 'exemple.com') }) + TP.field('force_https', t('Forcer HTTPS (redirection 301)'), { type: 'checkbox', value: true }) + '<button class="btn primary mt" id="do-le"' + (r.data.certbot ? '' : ' disabled') + '>' + TP.icon('lock') + t('Obtenir le certificat') + '</button></div>' +
      '<div data-pane="self" style="display:none"><p class="small muted">' + t('Pour les tests ou les intranets. Les navigateurs afficheront un avertissement.') + '</p>' + TP.field('force_https_s', t('Forcer HTTPS'), { type: 'checkbox' }) + '<button class="btn primary mt" id="do-self">' + TP.icon('key') + t('Générer') + '</button></div>' +
      '<div data-pane="manual" style="display:none">' + TP.field('cert', t('Certificat (PEM, fullchain)'), { type: 'textarea', rows: 6 }) + TP.field('key', t('Clé privée (PEM)'), { type: 'textarea', rows: 6 }) + TP.field('force_https_m', t('Forcer HTTPS'), { type: 'checkbox' }) + '<button class="btn primary mt" id="do-manual">' + TP.icon('upload') + t('Installer') + '</button></div>';
    TP.modal({ title: 'SSL · ' + s.name, size: 'lg', body,
      footer: (s.ssl_enabled ? '<button class="btn danger" id="do-off">' + t('Désactiver SSL') + '</button>' : '') + '<button class="btn" data-close>' + t('Fermer') + '</button>',
      onOpen: (bg, close) => {
        TP.qsa('.tabs button', bg).forEach((b) => b.onclick = () => { TP.qsa('.tabs button', bg).forEach((x) => x.classList.toggle('active', x === b)); TP.qsa('[data-pane]', bg).forEach((p) => p.style.display = p.dataset.pane === b.dataset.tab ? '' : 'none'); });
        const wrap = (fn) => async (e) => { e.target.disabled = true; try { await fn(); } catch (err) { TP.toast(err.message, 'error'); } e.target.disabled = false; };
        TP.qs('#do-le', bg).onclick = wrap(async () => { const rr = await TP.post('/api/sites/' + s.id + '/ssl/letsencrypt', { email: TP.qs('[name=email]', bg).value, force_https: TP.qs('[name=force_https]', bg).checked }); close(); TP.taskModal(rr.data.task_id, "Let's Encrypt · " + s.name, () => reload()); });
        TP.qs('#do-self', bg).onclick = wrap(async () => { const rr = await TP.post('/api/sites/' + s.id + '/ssl/self-signed', { force_https: TP.qs('[name=force_https_s]', bg).checked }); TP.toast(rr.msg); close(); reload(); });
        TP.qs('#do-manual', bg).onclick = wrap(async () => { const rr = await TP.post('/api/sites/' + s.id + '/ssl/manual', { cert: TP.qs('[name=cert]', bg).value, key: TP.qs('[name=key]', bg).value, force_https: TP.qs('[name=force_https_m]', bg).checked }); TP.toast(rr.msg); close(); reload(); });
        const off = TP.qs('#do-off', bg); if (off) off.onclick = wrap(async () => { const rr = await TP.post('/api/sites/' + s.id + '/ssl/disable'); TP.toast(rr.msg); close(); reload(); });
      } });
  }
  function openWp(s, reload) {
    TP.modal({ title: t('Installer WordPress') + ' · ' + s.name, body: '<p class="small muted">' + t('Téléchargement de la dernière version, création de la base et de wp-config.php. Vous terminerez l\'installation dans le navigateur.') + '</p><div class="form">' +
      '<div class="f2">' + TP.field('lang', t('Langue'), { type: 'select', value: 'fr', options: [['fr', 'Français'], ['en', 'English']] }) + TP.field('db_engine', t('Base de données'), { type: 'select', value: 'mysql', options: [['mysql', 'MySQL / MariaDB'], ['postgres', 'PostgreSQL (plugin requis)']] }) + '</div>' +
      '<div class="f2">' + TP.field('db_name', t('Nom de la base'), { placeholder: t('automatique') }) + TP.field('db_user', t('Utilisateur'), { placeholder: t('automatique') }) + '</div>' +
      '<div class="f2">' + TP.field('db_password', t('Mot de passe'), { placeholder: t('généré') }) + TP.field('table_prefix', t('Préfixe des tables'), { value: 'wp_' }) + '</div></div>',
      okText: t('Installer'), onOk: async (bg) => { const r = await TP.post('/api/sites/' + s.id + '/wordpress', TP.formData(bg)); TP.taskModal(r.data.task_id, 'WordPress · ' + s.name, () => reload()); } });
  }
  async function del(s, reload) {
    const bg = await TP.confirm(t('Supprimer le site'), t('Supprimer le site {name} ? Le vhost sera retiré.', { name: '<b>' + TP.esc(s.name) + '</b>' }), { danger: true, okText: t('Supprimer'), extra: '<label class="check mt"><input type="checkbox" name="df"> ' + t('Supprimer aussi les fichiers du site') + '</label>' });
    if (!bg) return;
    try { const r = await TP.del('/api/sites/' + s.id + '?delete_files=' + TP.qs('[name=df]', bg).checked); TP.toast(r.msg); reload(); } catch (e) { TP.toast(e.message, 'error'); }
  }
  TP.siteActions = { openCreate, openEdit, openConfig, openSsl, openWp, del };

  TP.registerPage('sites', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/sites'); meta = r.data;
      const sites = r.data.sites;
      root.innerHTML = TP.pageHead(t('Sites web'), (r.data.webserver_installed ? TP.badge(r.data.webserver, 'ok') : TP.badge(r.data.webserver + ' ' + t('non installé'), 'warn')) + ' ' + (meta.php_versions.length ? TP.badge('PHP ' + meta.php_versions.join(', '), 'info') : TP.badge(t('PHP non détecté'), '')),
          '<button class="btn" id="ws-test">' + TP.icon('check') + t('Tester la config') + '</button><button class="btn" id="ws-reload">' + TP.icon('refresh') + t('Recharger') + ' ' + r.data.webserver + '</button><button class="btn primary" id="add">' + TP.icon('plus') + t('Nouveau site') + '</button>') +
        (r.data.webserver_installed ? '' : '<div class="alert warn mb">' + TP.icon('alert') + '<div>' + t('Le serveur web {ws} n\'est pas installé : les vhosts sont générés mais inactifs. Installez-le depuis la page Logiciels.', { ws: r.data.webserver }) + '</div></div>') +
        '<div class="card">' + TP.table([
          { label: t('Site'), render: (s) => '<div><b>' + TP.esc(s.name) + '</b>' + (s.remark ? ' <span class="muted small">' + TP.esc(s.remark) + '</span>' : '') + '</div><div class="small">' + s.domains.map((d) => '<a href="' + (s.ssl_enabled ? 'https' : 'http') + '://' + d + '" target="_blank" class="chip">' + TP.esc(d) + '</a>').join('') + '</div>' },
          { label: t('Type'), render: (s) => s.site_type === 'proxy' ? (s.upstreams && s.upstreams.length ? TP.badge(t('répartition') + ' · ' + s.upstreams.length + ' ' + t('serveurs'), 'violet') + '<div class="small muted">' + TP.esc({ round_robin: 'round-robin', least_conn: 'least_conn', ip_hash: 'ip_hash' }[s.lb_method] || '') + '</div>' : TP.badge('proxy → ' + s.proxy_target, 'violet')) : s.site_type === 'static' ? TP.badge('HTML', '') : TP.badge('PHP ' + (s.php_version || ''), 'info') },
          { label: t('Racine'), render: (s) => '<a href="#/files?path=' + encodeURIComponent(s.root) + '" class="mono small">' + TP.esc(s.root) + '</a>' },
          { label: 'SSL', render: (s) => s.ssl_enabled ? (s.ssl_info && s.ssl_info.days_left < 15 ? TP.badge(t('expire') + ' ' + s.ssl_info.days_left + 'j', 'warn') : TP.badge('HTTPS' + (s.force_https ? ' ↺' : ''), 'ok')) : TP.badge(t('Aucun'), '') },
          { label: t('État'), render: (s) => s.enabled ? TP.badge(t('Actif'), 'ok') : TP.badge(t('Désactivé'), 'danger') },
          { label: '', cls: 'r', render: (s) => '<div class="actions">' +
            '<button class="btn xs" data-a="ssl" data-id="' + s.id + '" title="SSL">' + TP.icon('lock') + '</button>' +
            '<button class="btn xs" data-a="config" data-id="' + s.id + '" title="' + t('Configuration') + '">' + TP.icon('settings') + '</button>' +
            '<button class="btn xs' + (s.git ? ' primary' : '') + '" data-a="git" data-id="' + s.id + '" title="' + t('Déploiement Git') + (s.git ? ' · ' + TP.esc(s.git.branch) + (s.git.last_commit ? ' @ ' + s.git.last_commit : '') : '') + '">' + TP.icon('git') + '</button>' +
            (s.wordpress && s.wordpress.installed ? '<span class="badge violet" title="WordPress ' + s.wordpress.version + '">WP</span>' : '<button class="btn xs" data-a="wp" data-id="' + s.id + '" title="WordPress">' + TP.icon('wp') + '</button>') +
            '<button class="btn xs" data-a="toggle" data-id="' + s.id + '" title="' + (s.enabled ? t('Désactiver') : t('Activer')) + '">' + TP.icon(s.enabled ? 'stop' : 'play') + '</button>' +
            '<button class="btn xs" data-a="edit" data-id="' + s.id + '">' + TP.icon('edit') + '</button>' +
            '<button class="btn xs danger" data-a="del" data-id="' + s.id + '">' + TP.icon('trash') + '</button></div>' },
        ], sites, { empty: t('Aucun site. Créez votre premier site web !'), icon: 'globe' }) + '</div>';
      TP.qs('#add', root).onclick = () => openCreate(reload);
      TP.qs('#ws-test', root).onclick = async () => { try { const rr = await TP.get('/api/sites/webserver/test'); TP.modal({ title: t('Test de configuration') + ' ' + rr.data.webserver, body: '<div class="alert ' + (rr.data.ok ? 'ok' : 'danger') + ' mb">' + (rr.data.ok ? t('Configuration valide') : t('Erreurs détectées')) + '</div><pre class="pre">' + TP.esc(rr.data.output || '(vide)') + '</pre>', footer: '<button class="btn" data-close>' + t('Fermer') + '</button>' }); } catch (e) { TP.toast(e.message, 'error'); } };
      TP.qs('#ws-reload', root).onclick = async () => { try { const rr = await TP.post('/api/sites/webserver/reload'); TP.toast(rr.msg); } catch (e) { TP.toast(e.message, 'error'); } };
      TP.qsa('[data-a]', root).forEach((b) => b.onclick = async () => {
        const s = sites.find((x) => x.id === Number(b.dataset.id));
        const a = b.dataset.a;
        if (a === 'edit') openEdit(s, reload); else if (a === 'config') openConfig(s); else if (a === 'ssl') openSsl(s, reload); else if (a === 'wp') openWp(s, reload); else if (a === 'git') openEdit(s, reload, 'git'); else if (a === 'del') del(s, reload);
        else if (a === 'toggle') { try { const rr = await TP.put('/api/sites/' + s.id, { enabled: !s.enabled }); TP.toast(rr.msg); reload(); } catch (e) { TP.toast(e.message, 'error'); } }
      });
    },
  });

  TP.registerPage('wordpress', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/sites'); meta = r.data;
      const sites = r.data.sites;
      root.innerHTML = TP.pageHead('WP Toolkit', t('Installez et gérez WordPress sur vos sites en un clic.')) +
        '<div class="grid g3">' + (sites.length ? sites.map((s) => '<div class="card app-tile"><div class="icon" style="background:linear-gradient(135deg,#21759b,#0f4c75)">W</div><div class="flex1"><h4>' + TP.esc(s.name) + '</h4><p>' + TP.esc(s.domains.join(', ')) + '</p>' +
          (s.wordpress.installed ? '<div class="row">' + TP.badge('WordPress ' + (s.wordpress.version || ''), 'ok') + '<a class="btn xs" target="_blank" href="' + (s.ssl_enabled ? 'https' : 'http') + '://' + s.domains[0] + '/wp-admin/">' + TP.icon('external') + 'wp-admin</a><a class="btn xs" href="#/files?path=' + encodeURIComponent(s.root) + '">' + TP.icon('folder') + t('Fichiers') + '</a></div>' :
            '<button class="btn primary sm" data-wp="' + s.id + '">' + TP.icon('download') + t('Installer WordPress') + '</button>') + '</div></div>').join('') :
          '<div class="card" style="grid-column:1/-1">' + TP.empty(t('Créez d\'abord un site pour y installer WordPress.'), 'wp') + '</div>') + '</div>';
      TP.qsa('[data-wp]', root).forEach((b) => b.onclick = () => openWp(sites.find((x) => x.id === Number(b.dataset.wp)), reload));
    },
  });

  TP.registerPage('domains', {
    async render(root) {
      const r = await TP.get('/api/sites/domains/all');
      root.innerHTML = TP.pageHead(t('Domaines'), t('Tous les domaines rattachés à vos sites.'), '<a class="btn primary" href="#/sites">' + TP.icon('globe') + t('Gérer les sites') + '</a>') +
        '<div class="card">' + TP.table([
          { label: t('Domaine'), render: (d) => '<b>' + TP.esc(d.domain) + '</b>' },
          { label: t('Site'), render: (d) => '<a href="#/sites">' + TP.esc(d.site) + '</a>' },
          { label: 'SSL', render: (d) => d.ssl ? TP.badge('HTTPS', 'ok') : TP.badge('HTTP', '') },
          { label: t('État'), render: (d) => d.enabled ? TP.badge(t('Actif'), 'ok') : TP.badge(t('Désactivé'), 'danger') },
          { label: '', cls: 'r', render: (d) => '<a class="btn xs" target="_blank" href="' + (d.ssl ? 'https' : 'http') + '://' + d.domain + '">' + TP.icon('external') + t('Ouvrir') + '</a>' },
        ], r.data, { empty: t('Aucun domaine'), icon: 'domain' }) + '</div>';
    },
  });
})();
