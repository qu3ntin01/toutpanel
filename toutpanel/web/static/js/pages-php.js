/* Gestionnaire PHP multi-versions */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;

  const tabsModal = (bg) => TP.qsa('.tabs button', bg).forEach((b) => b.onclick = () => { TP.qsa('.tabs button', bg).forEach((x) => x.classList.toggle('active', x === b)); TP.qsa('[data-pane]', bg).forEach((p) => p.style.display = p.dataset.pane === b.dataset.tab ? '' : 'none'); });

  function openInstall(v, d, reload) {
    TP.modal({ title: t('Installer PHP') + ' ' + v.version, size: 'lg', body: '<p class="small muted">' + t('Le dépôt multi-versions de votre distribution est ajouté automatiquement (Sury / PPA ondrej, Remi, community). Choisissez les extensions à installer avec PHP-FPM.') + '</p><div class="grid g3">' +
      d.extensions.map((e) => '<label class="check"><input type="checkbox" name="ext" value="' + e.id + '"' + (d.default_extensions.includes(e.id) ? ' checked' : '') + '> <span>' + TP.esc(e.label) + '</span></label>').join('') + '</div>',
      okText: t('Installer'), onOk: async (bg) => { const exts = TP.qsa('[name=ext]:checked', bg).map((x) => x.value); const r = await TP.post('/api/php/' + v.version + '/install', { extensions: exts }); TP.taskModal(r.data.task_id, 'PHP ' + v.version, () => reload()); } });
  }
  async function openIni(v) {
    const r = await TP.get('/api/php/' + v.version + '/ini'); const vals = r.data.values;
    const hints = { memory_limit: '256M', upload_max_filesize: '64M', post_max_size: '64M', max_execution_time: '120', 'date.timezone': 'Europe/Paris', display_errors: 'Off', disable_functions: 'exec,passthru,shell_exec,system' };
    TP.modal({ title: 'php.ini · PHP ' + v.version, size: 'xl', body: '<div class="tabs"><button class="active" data-tab="form">' + t('Réglages courants') + '</button><button data-tab="raw">' + t('Fichier complet') + '</button></div>' +
      '<div data-pane="form"><p class="small muted mono">' + TP.esc(r.data.path) + '</p><div class="grid g2" id="ini-form">' + r.data.keys.map((k) => TP.field(k, k, { value: vals[k], placeholder: hints[k] || '' })).join('') + '</div></div>' +
      '<div data-pane="raw" style="display:none"><textarea class="input mono" name="raw" style="min-height:55vh;white-space:pre" spellcheck="false">' + TP.esc(r.data.raw) + '</textarea></div>',
      okText: t('Enregistrer et redémarrer'), onOpen: tabsModal,
      onOk: async (bg) => { const rawPane = TP.qs('[data-pane=raw]', bg).style.display !== 'none'; const body = rawPane ? { raw: TP.qs('[name=raw]', bg).value } : { values: TP.formData(TP.qs('#ini-form', bg)) }; const rr = await TP.post('/api/php/' + v.version + '/ini', body); TP.toast(rr.msg); } });
  }
  async function openPool(v) {
    const r = await TP.get('/api/php/' + v.version + '/pool'); const vals = r.data.values;
    TP.modal({ title: 'Pool FPM · PHP ' + v.version, size: 'xl', body: '<div class="tabs"><button class="active" data-tab="form">' + t('Réglages') + '</button><button data-tab="raw">' + t('Fichier complet') + '</button></div>' +
      '<div data-pane="form"><p class="small muted mono">' + TP.esc(r.data.path) + '</p><div class="grid g2" id="pool-form">' + r.data.keys.map((k) => TP.field(k, k, { value: vals[k], attrs: ['listen', 'user', 'group'].includes(k) ? ' readonly' : '' })).join('') + '</div><p class="small muted mt">' + t('pm = dynamic : max_children ≈ RAM disponible / mémoire moyenne d\'un processus PHP (30–60 Mo).') + '</p></div>' +
      '<div data-pane="raw" style="display:none"><textarea class="input mono" name="raw" style="min-height:55vh;white-space:pre" spellcheck="false">' + TP.esc(r.data.raw) + '</textarea></div>',
      okText: t('Enregistrer et redémarrer'), onOpen: tabsModal,
      onOk: async (bg) => { const rawPane = TP.qs('[data-pane=raw]', bg).style.display !== 'none'; const body = rawPane ? { raw: TP.qs('[name=raw]', bg).value } : { values: TP.formData(TP.qs('#pool-form', bg)) }; const rr = await TP.post('/api/php/' + v.version + '/pool', body); TP.toast(rr.msg); } });
  }
  async function openExts(v, d, reload) {
    const r = await TP.get('/api/php/' + v.version + '/modules'); const mods = new Set(r.data.modules);
    const has = (e) => ({ mysql: ['mysqli', 'pdo_mysql'], sqlite3: ['sqlite3'], opcache: ['zend opcache'], xml: ['xml', 'simplexml'] }[e.id] || [e.id]).some((m) => mods.has(m));
    TP.modal({ title: t('Extensions') + ' · PHP ' + v.version, size: 'lg', body: '<p class="small muted">' + mods.size + ' ' + t('modules chargés') + '</p><div class="grid g3">' +
      d.extensions.map((e) => '<label class="check"><input type="checkbox" name="ext" value="' + e.id + '"' + (has(e) ? ' checked disabled' : '') + '> <span>' + TP.esc(e.label) + (has(e) ? ' ' + TP.badge('OK', 'ok') : '') + '</span></label>').join('') + '</div><details class="mt"><summary class="small muted">' + t('Tous les modules chargés') + '</summary><div class="small mono mt">' + TP.esc([...mods].join(', ')) + '</div></details>',
      okText: t('Installer la sélection'), onOk: async (bg) => { const exts = TP.qsa('[name=ext]:checked:not(:disabled)', bg).map((x) => x.value); if (!exts.length) throw new Error(t('Aucune extension sélectionnée')); const rr = await TP.post('/api/php/' + v.version + '/extensions', { extensions: exts }); TP.taskModal(rr.data.task_id, t('Extensions') + ' PHP ' + v.version, () => reload()); } });
  }

  TP.registerPage('php', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/php'); const d = r.data;
      const inst = d.versions.filter((v) => v.installed), avail = d.versions.filter((v) => !v.installed);
      root.innerHTML = TP.pageHead('PHP', t('Installez plusieurs versions de PHP côte à côte et affectez-les site par site.') + ' ' + TP.badge(d.family || TP.os, d.supported ? 'info' : 'warn'),
          '<a class="btn" href="#/sites">' + TP.icon('globe') + t('Affecter aux sites') + '</a>') +
        (!d.supported ? '<div class="alert warn mb">' + TP.icon('alert') + '<div>' + t('Installation multi-versions non prise en charge sur cette distribution (Arch/openSUSE) : utilisez la page Logiciels pour la version du système.') + '</div></div>' : '') +
        '<div class="card mb"><div class="card-h"><h3>' + t('Versions installées') + ' (' + inst.length + ')</h3></div>' + TP.table([
          { label: t('Version'), render: (v) => '<b>PHP ' + v.version + '</b>' + (v.full_version ? ' <span class="muted small mono">' + v.full_version + '</span>' : '') + (v.is_default_cli ? ' ' + TP.badge('CLI ' + t('par défaut'), 'violet') : '') },
          { label: 'FPM', render: (v) => TP.statusBadge(v.status) },
          { label: 'FastCGI', cls: 'mono small muted', render: (v) => TP.esc(v.paths.fpm_pass) },
          { label: '', cls: 'r', render: (v) => '<div class="actions">' +
            '<button class="btn xs" data-a="ini" data-v="' + v.version + '" title="php.ini">' + TP.icon('settings') + ' ini</button>' +
            '<button class="btn xs" data-a="pool" data-v="' + v.version + '" title="Pool FPM">' + TP.icon('cpu') + ' pool</button>' +
            '<button class="btn xs" data-a="ext" data-v="' + v.version + '" title="' + t('Extensions') + '">' + TP.icon('box') + '</button>' +
            '<button class="btn xs" data-a="info" data-v="' + v.version + '" title="phpinfo">' + TP.icon('info') + '</button>' +
            (v.status === 'running' ? '<button class="btn xs" data-a="restart" data-v="' + v.version + '">' + TP.icon('refresh') + '</button><button class="btn xs" data-a="stop" data-v="' + v.version + '">' + TP.icon('stop') + '</button>' : '<button class="btn xs" data-a="start" data-v="' + v.version + '">' + TP.icon('play') + '</button>') +
            (v.is_default_cli ? '' : '<button class="btn xs" data-a="default" data-v="' + v.version + '" title="' + t('Version CLI par défaut') + '">' + TP.icon('star') + '</button>') +
            '<button class="btn xs danger" data-a="remove" data-v="' + v.version + '">' + TP.icon('trash') + '</button></div>' },
        ], inst, { empty: t('Aucune version de PHP installée. Installez-en une ci-dessous.'), icon: 'php' }) + '</div>' +
        '<h3 class="mb">' + t('Versions disponibles') + '</h3><div class="grid g4">' + avail.map((v) => '<div class="card app-tile"><div class="icon" style="background:linear-gradient(135deg,#7377ad,#4f5b93)">' + v.version + '</div><div class="flex1"><h4>PHP ' + v.version + '</h4><p>' + (parseFloat(v.version) >= 8.1 ? t('Version maintenue') : t('Fin de vie : usage legacy uniquement')) + '</p><button class="btn primary sm" data-install="' + v.version + '"' + (d.supported ? '' : ' disabled') + '>' + TP.icon('download') + t('Installer') + '</button></div></div>').join('') + '</div>';
      TP.qsa('[data-install]', root).forEach((b) => b.onclick = () => openInstall(d.versions.find((v) => v.version === b.dataset.install), d, reload));
      TP.qsa('[data-a]', root).forEach((b) => b.onclick = async () => { const v = d.versions.find((x) => x.version === b.dataset.v); const a = b.dataset.a; try {
        if (a === 'ini') openIni(v); else if (a === 'pool') openPool(v); else if (a === 'ext') openExts(v, d, reload);
        else if (a === 'info') { const rr = await TP.get('/api/php/' + v.version + '/info'); TP.modal({ title: 'phpinfo · PHP ' + v.version, size: 'xl', body: '<div class="alert info mb">' + TP.esc(rr.data.test) + '</div><pre class="pre" style="max-height:60vh">' + TP.esc(rr.data.info) + '</pre>', footer: '<button class="btn" data-close>' + t('Fermer') + '</button>' }); }
        else if (a === 'default') { const rr = await TP.post('/api/php/' + v.version + '/default'); TP.toast(rr.msg); reload(); }
        else if (a === 'remove') { if (await TP.confirm(t('Supprimer PHP') + ' ' + v.version, t('Les sites utilisant cette version cesseront de fonctionner.'), { danger: true })) { const rr = await TP.post('/api/php/' + v.version + '/remove'); TP.taskModal(rr.data.task_id, t('Suppression') + ' PHP ' + v.version, () => reload()); } }
        else { b.disabled = true; const rr = await TP.post('/api/php/' + v.version + '/service', { action: a }); TP.toast(rr.msg); reload(); }
      } catch (e) { TP.toast(e.message, 'error'); b.disabled = false; } });
    },
  });
})();
