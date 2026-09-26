/* Gestionnaire de fichiers */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;
  let cur = '', selected = new Set(), clipboard = null, entries = [];

  const isArchive = (n) => /\.(zip|tar|tgz|tar\.gz|tar\.bz2|tar\.xz)$/i.test(n);
  const isText = (e) => e.type === 'file' && (e.size < 5 * 1024 * 1024) && !/\.(png|jpe?g|gif|webp|ico|pdf|zip|gz|tar|tgz|bz2|xz|7z|rar|exe|dll|so|bin|mp3|mp4|mov|avi|woff2?|ttf|eot)$/i.test(e.name);

  function crumbs(path) {
    const sep = path.includes('\\') && !path.includes('/') ? '\\' : '/';
    const parts = path.split(/[\\/]/).filter(Boolean);
    let acc = path.startsWith('/') ? '' : '';
    let html = '<a href="#" data-go="' + (path.startsWith('/') ? '/' : parts[0] + sep) + '">' + TP.icon('hdd') + '</a>';
    parts.forEach((p, i) => { acc = (i === 0 && !path.startsWith('/')) ? p + sep : (acc || '') + (acc.endsWith(sep) || acc === '' ? '' : sep) + p; if (i === 0 && path.startsWith('/')) acc = '/' + p;
      html += '<span class="sep">' + TP.icon('chevron') + '</span><a href="#" data-go="' + TP.esc(acc) + '">' + TP.esc(p) + '</a>'; });
    return html;
  }

  async function load(root, path) {
    const r = await TP.get('/api/files/list?path=' + encodeURIComponent(path || ''));
    cur = r.data.path; entries = r.data.entries; selected.clear();
    TP.qs('#crumbs', root).innerHTML = crumbs(cur);
    TP.qs('#path-input', root).value = cur;
    TP.qs('#file-list', root).innerHTML = TP.table([
      { label: '<input type="checkbox" id="sel-all">', raw: true, render: (e) => '<input type="checkbox" data-sel="' + TP.esc(e.path) + '">' },
      { label: t('Nom'), render: (e) => '<div class="file-name ' + e.type + '" data-open="' + TP.esc(e.path) + '" data-type="' + e.type + '">' + TP.icon(e.type === 'dir' ? 'folder' : isArchive(e.name) ? 'zip' : 'file') + '<span>' + TP.esc(e.name) + '</span></div>' },
      { label: t('Taille'), cls: 'muted', render: (e) => e.type === 'dir' ? '—' : TP.fmtBytes(e.size) },
      { label: t('Modifié'), cls: 'muted', render: (e) => TP.fmtTs(e.mtime) },
      { label: t('Droits'), cls: 'muted mono', render: (e) => e.mode + (e.owner ? ' ' + e.owner : '') },
      { label: '', cls: 'r', render: (e) => '<div class="actions">' +
        (e.type === 'file' && isText(e) ? '<button class="btn xs" data-act="edit" data-p="' + TP.esc(e.path) + '" title="' + t('Éditer') + '">' + TP.icon('edit') + '</button>' : '') +
        (e.type === 'file' ? '<a class="btn xs" href="/api/files/download?path=' + encodeURIComponent(e.path) + '" title="' + t('Télécharger') + '">' + TP.icon('download') + '</a>' : '') +
        (isArchive(e.name) ? '<button class="btn xs" data-act="extract" data-p="' + TP.esc(e.path) + '" title="' + t('Extraire') + '">' + TP.icon('zip') + '</button>' : '') +
        '<button class="btn xs" data-act="rename" data-p="' + TP.esc(e.path) + '" data-n="' + TP.esc(e.name) + '" title="' + t('Renommer') + '">' + TP.icon('edit') + '</button>' +
        (TP.os !== 'windows' ? '<button class="btn xs" data-act="chmod" data-p="' + TP.esc(e.path) + '" data-m="' + e.mode + '" title="chmod">' + TP.icon('key') + '</button>' : '') +
        '<button class="btn xs danger" data-act="del" data-p="' + TP.esc(e.path) + '">' + TP.icon('trash') + '</button></div>' },
    ], entries, { empty: t('Dossier vide'), icon: 'folder' });
    bind(root);
  }

  function bind(root) {
    TP.qsa('[data-go]', root).forEach((a) => a.onclick = (e) => { e.preventDefault(); load(root, a.dataset.go); });
    TP.qsa('[data-open]', root).forEach((d) => d.onclick = () => { if (d.dataset.type === 'dir') load(root, d.dataset.open); else { const e = entries.find((x) => x.path === d.dataset.open); if (e && isText(e)) openEditor(root, e.path); else window.open('/api/files/download?path=' + encodeURIComponent(d.dataset.open)); } });
    TP.qsa('[data-sel]', root).forEach((c) => c.onchange = () => { if (c.checked) selected.add(c.dataset.sel); else selected.delete(c.dataset.sel); updateBulk(root); });
    const all = TP.qs('#sel-all', root); if (all) all.onchange = () => { TP.qsa('[data-sel]', root).forEach((c) => { c.checked = all.checked; if (all.checked) selected.add(c.dataset.sel); else selected.delete(c.dataset.sel); }); updateBulk(root); };
    TP.qsa('[data-act]', root).forEach((b) => b.onclick = () => action(root, b.dataset.act, b.dataset));
  }
  function updateBulk(root) { const n = selected.size; TP.qs('#bulk', root).style.display = n ? '' : 'none'; TP.qs('#bulk-n', root).textContent = n; }

  async function action(root, act, d) {
    try {
      if (act === 'edit') openEditor(root, d.p);
      else if (act === 'rename') { const n = await TP.prompt(t('Renommer'), t('Nouveau nom'), d.n); if (n && n !== d.n) { await TP.post('/api/files/rename', { path: d.p, name: n }); load(root, cur); } }
      else if (act === 'del') { if (await TP.confirm(t('Supprimer'), t('Supprimer définitivement {n} ?', { n: '<code>' + TP.esc(d.p) + '</code>' }), { danger: true })) { await TP.post('/api/files/delete', { paths: [d.p] }); TP.toast(t('Supprimé')); load(root, cur); } }
      else if (act === 'extract') { const dest = await TP.prompt(t('Extraire'), t('Dossier de destination'), cur); if (dest) { await TP.post('/api/files/extract', { archive: d.p, dest }); TP.toast(t('Archive extraite')); load(root, cur); } }
      else if (act === 'chmod') { TP.modal({ title: 'chmod · ' + d.p.split(/[\\/]/).pop(), body: '<div class="form">' + TP.field('mode', t('Mode (octal)'), { value: d.m, placeholder: '755' }) + TP.field('recursive', t('Récursif'), { type: 'checkbox' }) + '</div>', onOk: async (bg) => { const f = TP.formData(bg); await TP.post('/api/files/chmod', { path: d.p, mode: f.mode, recursive: f.recursive }); TP.toast(t('Permissions modifiées')); load(root, cur); } }); }
    } catch (e) { TP.toast(e.message, 'error'); }
  }

  async function openEditor(root, path) {
    const r = await TP.get('/api/files/read?path=' + encodeURIComponent(path));
    const m = TP.modal({ title: t('Éditer') + ' · ' + path.split(/[\\/]/).pop(), size: 'xl', sticky: true,
      body: '<div class="row between mb"><span class="mono small muted">' + TP.esc(path) + '</span><span class="muted small">' + r.data.encoding + ' · ' + TP.fmtBytes(r.data.size) + '</span></div><textarea class="input mono" id="ed" style="min-height:62vh;white-space:pre;overflow:auto" spellcheck="false">' + TP.esc(r.data.content) + '</textarea><div class="muted small mt">Ctrl+S ' + t('pour enregistrer') + '</div>',
      okText: t('Enregistrer'), onOk: async (bg) => { await TP.post('/api/files/write', { path, content: TP.qs('#ed', bg).value, encoding: r.data.encoding }); TP.toast(t('Enregistré')); return false; } });
    const ta = TP.qs('#ed', m.el);
    ta.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); TP.qs('[data-ok]', m.el).click(); } if (e.key === 'Tab') { e.preventDefault(); const s = ta.selectionStart; ta.value = ta.value.slice(0, s) + '    ' + ta.value.slice(ta.selectionEnd); ta.selectionStart = ta.selectionEnd = s + 4; } });
  }

  async function upload(root, files) {
    for (const f of files) {
      const fd = new FormData(); fd.append('path', cur); fd.append('file', f);
      try { await TP.api('POST', '/api/files/upload', fd); TP.toast(t('Envoyé') + ' : ' + f.name); } catch (e) { TP.toast(f.name + ' : ' + e.message, 'error'); }
    }
    load(root, cur);
  }

  TP.registerPage('files', {
    async render(root) {
      const q = TP.query();
      root.innerHTML = TP.pageHead(t('Fichiers'), t('Parcourez, éditez, envoyez et archivez les fichiers du serveur.'),
        '<button class="btn" id="new-dir">' + TP.icon('folder') + t('Dossier') + '</button><button class="btn" id="new-file">' + TP.icon('file') + t('Fichier') + '</button><button class="btn" id="upload">' + TP.icon('upload') + t('Envoyer') + '</button><input type="file" id="upl" multiple style="display:none">') +
        '<div class="card mb"><div class="card-b" style="padding:12px 16px"><div class="row"><div class="breadcrumb flex1" id="crumbs"></div><div class="search" style="width:280px">' + TP.icon('search') + '<input class="input" id="path-input" placeholder="' + t('Chemin…') + '"></div><div class="search" style="width:200px">' + TP.icon('search') + '<input class="input" id="search" placeholder="' + t('Rechercher…') + '"></div></div>' +
        '<div class="row mt" id="bulk" style="display:none"><span class="badge info"><b id="bulk-n">0</b>&nbsp;' + t('sélectionné(s)') + '</span><button class="btn sm" id="b-copy">' + TP.icon('copy') + t('Copier') + '</button><button class="btn sm" id="b-cut">' + TP.icon('edit') + t('Couper') + '</button><button class="btn sm" id="b-zip">' + TP.icon('zip') + t('Compresser') + '</button><button class="btn sm danger" id="b-del">' + TP.icon('trash') + t('Supprimer') + '</button></div>' +
        '<div class="row mt" id="paste-bar" style="display:none"><span class="badge warn" id="paste-n"></span><button class="btn sm primary" id="b-paste">' + TP.icon('check') + t('Coller ici') + '</button><button class="btn sm ghost" id="b-paste-x">' + t('Annuler') + '</button></div></div></div>' +
        '<div class="card" id="drop"><div id="file-list">' + TP.loading() + '</div><div class="dropzone" style="margin:14px">' + t('Glissez-déposez des fichiers ici pour les envoyer') + '</div></div>';
      await load(root, q.path || '');
      const pi = TP.qs('#path-input', root); pi.addEventListener('keydown', (e) => { if (e.key === 'Enter') load(root, pi.value).catch((err) => TP.toast(err.message, 'error')); });
      TP.qs('#search', root).addEventListener('keydown', async (e) => { if (e.key !== 'Enter') return; const q2 = e.target.value.trim(); if (!q2) return load(root, cur);
        try { const r = await TP.get('/api/files/search?path=' + encodeURIComponent(cur) + '&q=' + encodeURIComponent(q2)); entries = r.data; selected.clear();
          TP.qs('#file-list', root).innerHTML = TP.table([{ label: t('Résultat'), render: (x) => '<div class="file-name ' + x.type + '" data-open="' + TP.esc(x.path) + '" data-type="' + x.type + '">' + TP.icon(x.type === 'dir' ? 'folder' : 'file') + '<span>' + TP.esc(x.path) + '</span></div>' }, { label: t('Taille'), render: (x) => x.type === 'dir' ? '—' : TP.fmtBytes(x.size) }], entries, { empty: t('Aucun résultat') }); bind(root); } catch (err) { TP.toast(err.message, 'error'); } });
      TP.qs('#new-dir', root).onclick = async () => { const n = await TP.prompt(t('Nouveau dossier'), t('Nom')); if (n) { try { await TP.post('/api/files/mkdir', { path: cur, name: n }); load(root, cur); } catch (e) { TP.toast(e.message, 'error'); } } };
      TP.qs('#new-file', root).onclick = async () => { const n = await TP.prompt(t('Nouveau fichier'), t('Nom')); if (n) { try { await TP.post('/api/files/touch', { path: cur, name: n }); load(root, cur); } catch (e) { TP.toast(e.message, 'error'); } } };
      const upl = TP.qs('#upl', root); TP.qs('#upload', root).onclick = () => upl.click(); upl.onchange = () => upload(root, upl.files);
      const drop = TP.qs('#drop', root), dz = TP.qs('.dropzone', root);
      drop.addEventListener('dragover', (e) => { e.preventDefault(); dz.classList.add('over'); }); drop.addEventListener('dragleave', () => dz.classList.remove('over'));
      drop.addEventListener('drop', (e) => { e.preventDefault(); dz.classList.remove('over'); upload(root, e.dataTransfer.files); });
      const showPaste = () => { const pb = TP.qs('#paste-bar', root); pb.style.display = clipboard ? '' : 'none'; if (clipboard) TP.qs('#paste-n', root).textContent = clipboard.paths.length + ' ' + (clipboard.move ? t('à déplacer') : t('à copier')); };
      TP.qs('#b-copy', root).onclick = () => { clipboard = { paths: [...selected], move: false }; showPaste(); };
      TP.qs('#b-cut', root).onclick = () => { clipboard = { paths: [...selected], move: true }; showPaste(); };
      TP.qs('#b-paste-x', root).onclick = () => { clipboard = null; showPaste(); };
      TP.qs('#b-paste', root).onclick = async () => { try { await TP.post('/api/files/copy', { paths: clipboard.paths, dest: cur, move: clipboard.move }); TP.toast(t('Terminé')); clipboard = null; showPaste(); load(root, cur); } catch (e) { TP.toast(e.message, 'error'); } };
      TP.qs('#b-del', root).onclick = async () => { if (await TP.confirm(t('Supprimer'), t('Supprimer {n} élément(s) ?', { n: selected.size }), { danger: true })) { try { await TP.post('/api/files/delete', { paths: [...selected] }); load(root, cur); } catch (e) { TP.toast(e.message, 'error'); } } };
      TP.qs('#b-zip', root).onclick = async () => { const n = await TP.prompt(t('Compresser'), t('Nom de l\'archive (.zip ou .tar.gz)'), 'archive.zip'); if (!n) return; try { await TP.post('/api/files/compress', { paths: [...selected], archive: cur.replace(/[\\/]$/, '') + (cur.includes('\\') ? '\\' : '/') + n, fmt: n.endsWith('.zip') ? 'zip' : 'tar' }); TP.toast(t('Archive créée')); load(root, cur); } catch (e) { TP.toast(e.message, 'error'); } };
    },
  });
})();
