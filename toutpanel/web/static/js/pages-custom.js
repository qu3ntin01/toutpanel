/* Personnalisation : apparence, modèles, répertoires, liens */
(function () {
  'use strict';
  const TP = window.TP, t = TP.t;
  let tab = 'appearance';
  const SWATCHES = ['#2563eb', '#0f8f47', '#7c3aed', '#db2777', '#dc2626', '#ea580c', '#0891b2', '#0f766e', '#334155', '#111827'];

  TP.registerPage('custom', {
    async render(root) {
      const reload = () => this.render(root);
      const r = await TP.get('/api/custom'); const d = r.data, ap = d.appearance;
      root.innerHTML = TP.pageHead(t('Personnalisation'), t('Adaptez le panel à votre marque et à votre infrastructure : apparence, modèles de configuration, répertoires, liens.')) +
        '<div class="tabs">' + [['appearance', t('Apparence')], ['templates', t('Modèles de configuration')], ['dirs', t('Répertoires')], ['links', t('Liens du menu')]].map(([k, l]) => '<button class="' + (tab === k ? 'active' : '') + '" data-tab="' + k + '">' + l + '</button>').join('') + '</div><div id="pane"></div>';
      TP.qsa('.tabs button', root).forEach((b) => b.onclick = () => { tab = b.dataset.tab; reload(); });
      const pane = TP.qs('#pane', root);
      const saveAp = async (values) => { try { const rr = await TP.post('/api/custom/appearance', { values }); TP.toast(rr.msg + ' — ' + t('rechargez la page pour voir le résultat.')); } catch (e) { TP.toast(e.message, 'error'); } };

      if (tab === 'appearance') {
        const skinCard = (k, title, sub, cls) => '<button class="skin-card ' + cls + (ap.ui_skin === k ? ' on' : '') + '" data-skin="' + k + '"><span class="prev"><i class="r"></i><i class="c"></i><i class="c"></i></span><b>' + title + '</b><span class="small muted">' + sub + '</span></button>';
        pane.innerHTML = '<div class="card mb"><div class="card-h"><h3>' + t('Style de l\'interface') + '</h3><span class="muted small">' + t('S\'applique à tous les utilisateurs après rechargement.') + '</span></div><div class="card-b"><div class="skins">' +
          skinCard('aurora', t('Aurora (bleu)'), t('Rail bleu profond translucide, surfaces en verre, fond ambiant. Style par défaut.'), 'aurora') +
          skinCard('classic', t('Classique (bleu)'), t('Menu clair et plat, cartes opaques, accent bleu. Sobre et rapide.'), 'classic') + '</div></div></div>' +
          '<div class="grid g2"><div class="card"><div class="card-h"><h3>' + t('Identité') + '</h3></div><div class="card-b"><div class="form" id="f-ap">' +
          TP.field('panel_name', t('Nom du panel'), { value: ap.panel_name }) + '<div class="f2">' + TP.field('logo_letter', t('Lettre du logo'), { value: ap.logo_letter, attrs: ' maxlength="2"' }) + TP.field('logo_url', t('URL du logo (image, optionnel)'), { value: ap.logo_url, placeholder: 'https://…/logo.png' }) + '</div>' +
          '<div class="field"><label>' + t('Couleur d\'accent') + '</label><div class="row">' + SWATCHES.map((c) => '<div class="swatch ' + (ap.accent_color === c ? 'on' : '') + '" data-c="' + c + '" style="background:' + c + '"></div>').join('') + '<input class="input" name="accent_color" value="' + TP.esc(ap.accent_color) + '" style="width:110px" placeholder="#2563eb"></div></div>' +
          '<div class="f2">' + TP.field('default_theme', t('Thème par défaut'), { type: 'select', value: ap.default_theme, options: [['auto', t('Automatique (système)')], ['light', t('Clair')], ['dark', t('Sombre')]] }) + TP.field('default_contrast', t('Contraste par défaut'), { type: 'select', value: ap.default_contrast, options: [['glass', t('Effet verre (surfaces translucides)')], ['high', t('Contraste élevé (surfaces opaques)')]], hint: t('Chaque utilisateur peut ensuite changer le thème et le contraste depuis le rail.') }) + '</div>' +
          TP.field('footer_text', t('Texte de pied de menu'), { value: ap.footer_text, placeholder: '© Mon hébergeur' }) +
          '<div class="row">' + TP.field('sidebar_compact', t('Menu compact'), { type: 'checkbox', value: ap.sidebar_compact }) + TP.field('show_version', t('Afficher la version'), { type: 'checkbox', value: ap.show_version }) + '</div>' +
          '<button class="btn primary" id="save-ap">' + TP.icon('check') + t('Enregistrer') + '</button></div></div></div>' +
          '<div class="card"><div class="card-h"><h3>' + t('CSS personnalisé') + '</h3></div><div class="card-b"><p class="small muted">' + t('Injecté dans toutes les pages. Variables disponibles : --primary, --bg, --bg-elev, --text, --radius, --sidebar-w…') + '</p><textarea class="input mono" id="css" style="min-height:260px" spellcheck="false" placeholder=".sidebar { background: #0b1220; }">' + TP.esc(ap.custom_css) + '</textarea><button class="btn primary mt" id="save-css">' + TP.icon('check') + t('Enregistrer le CSS') + '</button></div></div></div>';
        TP.qsa('.skin-card', pane).forEach((b) => b.onclick = async () => { TP.qsa('.skin-card', pane).forEach((x) => x.classList.toggle('on', x === b)); document.documentElement.dataset.skin = b.dataset.skin; try { const rr = await TP.post('/api/custom/appearance', { values: { ui_skin: b.dataset.skin } }); TP.toast(rr.msg); } catch (e) { TP.toast(e.message, 'error'); } });
        TP.qsa('.swatch', pane).forEach((s) => s.onclick = () => { TP.qs('[name=accent_color]', pane).value = s.dataset.c; TP.qsa('.swatch', pane).forEach((x) => x.classList.toggle('on', x === s)); document.documentElement.style.setProperty('--primary', s.dataset.c); });
        TP.qs('#save-ap', pane).onclick = () => saveAp(TP.formData(TP.qs('#f-ap', pane)));
        TP.qs('#save-css', pane).onclick = () => saveAp({ custom_css: TP.qs('#css', pane).value });
      } else if (tab === 'templates') {
        pane.innerHTML = '<div class="alert info mb">' + TP.icon('info') + '<div>' + t('Les modèles utilisent la syntaxe Jinja2. Variables des vhosts : site (name, domains, root, php_version, site_type, proxy_target, force_https), domains, root, log_dir, ssl, cert, key, fpm, waf_include, custom_include, v6, http2_on.') + '</div></div>' +
          '<div class="card">' + TP.table([{ label: t('Modèle'), render: (x) => '<b>' + TP.esc(x.label) + '</b><div class="small muted mono">' + x.name + '</div>' }, { label: t('État'), render: (x) => x.custom ? TP.badge(t('Personnalisé'), 'violet') : TP.badge(t('Par défaut'), '') },
            { label: '', cls: 'r', render: (x) => '<div class="actions"><button class="btn xs" data-edit="' + x.name + '">' + TP.icon('edit') + t('Éditer') + '</button>' + (x.custom ? '<button class="btn xs danger" data-reset="' + x.name + '">' + TP.icon('refresh') + t('Restaurer le défaut') + '</button>' : '') + '</div>' }], d.templates) + '</div>';
        TP.qsa('[data-edit]', pane).forEach((b) => b.onclick = async () => { const rr = await TP.get('/api/custom/templates/' + b.dataset.edit); const tpl = rr.data;
          TP.modal({ title: t('Modèle') + ' · ' + tpl.label, size: 'xl', sticky: true, body: '<div class="row between mb"><span class="muted small mono">' + tpl.name + ' · ' + (tpl.custom ? t('personnalisé') : t('défaut')) + '</span><div class="btn-group"><button class="btn xs" id="tpl-preview">' + TP.icon('eye') + t('Prévisualiser le rendu') + '</button><button class="btn xs" id="tpl-default">' + TP.icon('refresh') + t('Recharger le défaut') + '</button></div></div><textarea class="input mono" id="tpl" style="min-height:55vh;white-space:pre" spellcheck="false">' + TP.esc(tpl.content) + '</textarea><pre class="pre mt" id="tpl-out" style="display:none;max-height:40vh"></pre>',
            okText: t('Enregistrer'), onOpen: (bg) => { TP.qs('#tpl-default', bg).onclick = () => { TP.qs('#tpl', bg).value = tpl.default; }; TP.qs('#tpl-preview', bg).onclick = async () => { try { const p = await TP.post('/api/custom/templates/' + tpl.name + '/preview', { content: TP.qs('#tpl', bg).value }); const out = TP.qs('#tpl-out', bg); out.style.display = ''; out.textContent = p.data.rendered; } catch (e) { TP.toast(e.message, 'error'); } }; },
            onOk: async (bg) => { const res = await TP.post('/api/custom/templates/' + tpl.name, { content: TP.qs('#tpl', bg).value }); TP.toast(res.msg, 'warn', 7000); reload(); } }); });
        TP.qsa('[data-reset]', pane).forEach((b) => b.onclick = async () => { if (await TP.confirm(t('Restaurer le défaut'), t('Votre version personnalisée sera supprimée.'), { danger: true })) { const rr = await TP.del('/api/custom/templates/' + b.dataset.reset); TP.toast(rr.msg); reload(); } });
      } else if (tab === 'dirs') {
        pane.innerHTML = '<div class="grid g2"><div class="card"><div class="card-h"><h3>' + t('Répertoires personnalisables') + '</h3></div><div class="card-b"><div class="form" id="f-dirs">' +
          TP.field('www_root', t('Racine des nouveaux sites'), { value: d.dirs.override_www_root, placeholder: d.dirs.www_root, hint: t('Vide = valeur par défaut. Les sites existants conservent leur racine.') }) +
          TP.field('backup_dir', t('Répertoire des sauvegardes'), { value: d.dirs.override_backup_dir, placeholder: d.dirs.backup_dir }) +
          '<button class="btn primary" id="save-dirs">' + TP.icon('check') + t('Enregistrer') + '</button></div></div></div>' +
          '<div class="card"><div class="card-h"><h3>' + t('Répertoires actuels') + '</h3></div><div class="card-b"><dl class="kv">' + [['home', t('Panel')], ['www_root', t('Sites')], ['backup_dir', t('Sauvegardes')], ['vhost_dir', 'Vhosts'], ['ssl_dir', 'SSL'], ['log_dir', t('Journaux')]].map(([k, l]) => '<dt>' + l + '</dt><dd class="mono"><a href="#/files?path=' + encodeURIComponent(d.dirs[k]) + '">' + TP.esc(d.dirs[k]) + '</a></dd>').join('') + '</dl></div></div></div>';
        TP.qs('#save-dirs', pane).onclick = async () => { try { const rr = await TP.post('/api/custom/dirs', TP.formData(TP.qs('#f-dirs', pane))); TP.toast(rr.msg); reload(); } catch (e) { TP.toast(e.message, 'error'); } };
      } else {
        const links = ap.custom_links.slice();
        const draw = () => { TP.qs('#links', pane).innerHTML = TP.table([{ label: t('Libellé'), render: (l) => '<b>' + TP.esc(l.label) + '</b>' }, { label: 'URL', cls: 'mono small', render: (l) => TP.esc(l.url) }, { label: '', cls: 'r', render: (l, i) => '<button class="btn xs danger" data-rm="' + links.indexOf(l) + '">' + TP.icon('trash') + '</button>' }], links, { empty: t('Aucun lien personnalisé (ex : phpMyAdmin, Roundcube, monitoring externe…)') }); TP.qsa('[data-rm]', pane).forEach((b) => b.onclick = () => { links.splice(Number(b.dataset.rm), 1); draw(); }); };
        pane.innerHTML = '<div class="card"><div class="card-h"><h3>' + t('Liens du menu') + '</h3><div class="btn-group"><button class="btn sm" id="add-link">' + TP.icon('plus') + t('Ajouter') + '</button><button class="btn sm primary" id="save-links">' + TP.icon('check') + t('Enregistrer') + '</button></div></div><div id="links"></div></div>';
        draw();
        TP.qs('#add-link', pane).onclick = () => TP.modal({ title: t('Nouveau lien'), body: '<div class="form">' + TP.field('label', t('Libellé'), { placeholder: 'phpMyAdmin' }) + TP.field('url', 'URL', { placeholder: 'https://mon-serveur/phpmyadmin' }) + '</div>', okText: t('Ajouter'), onOk: (bg) => { const f = TP.formData(bg); if (!f.label || !f.url) throw new Error(t('Libellé et URL requis')); links.push({ label: f.label, url: f.url, icon: 'external' }); draw(); } });
        TP.qs('#save-links', pane).onclick = () => saveAp({ custom_links: links });
      }
    },
  });
})();
