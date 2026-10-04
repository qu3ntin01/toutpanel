# Journal des modifications

Toutes les évolutions notables de ToutPanel sont consignées dans ce fichier. Le format s'inspire de
[Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les versions suivent le [versionnage sémantique](https://semver.org/lang/fr/)
(étiquettes Git `vX.Y.Z` sur le dépôt public). Le panel lit ce fichier pour afficher les notes de version
avant une mise à jour (page **Mises à jour → Panel**).

## [Non publié]

### Ajouté

- **Installeurs : mot de passe administrateur fourni sans passer par la ligne de commande** (sur le modèle du jeton d'API ToutWAF). `install.sh` : variable `TOUTPANEL_PASSWORD`
  (à conserver avec `sudo -E`), `--password-file FICHIER` (1re ligne ; refusé si le fichier est accessible au groupe ou aux autres, ou n'appartient ni à root ni à l'utilisateur),
  `--password-stdin` (1re ligne de l'entrée standard ; **refusé avec `curl … | sudo bash -s -- --password-stdin`**, où l'entrée standard est le script lui-même : message conseillant la
  variable ou le fichier, détecté avant toute lecture). `install.ps1` : `$env:TOUTPANEL_PASSWORD`, `-PasswordFile`, `-PasswordStdin`, `-PasswordSecure` (SecureString). **Priorité** :
  l'option donnée (une seule à la fois, deux options sont refusées) > `TOUTPANEL_PASSWORD` > question dans un terminal (« générer automatiquement (recommandé) » ou « saisir » sans écho, avec
  confirmation) > mot de passe aléatoire sans terminal ou avec `--yes` (comportement inchangé). `--password VALEUR` reste accepté, avec un avertissement traduit (visible dans `ps` et
  l'historique), jamais refusé. Un mot de passe fourni n'apparaît ni dans la sortie, ni dans le récapitulatif, ni dans `install-info.txt` (« celui que vous avez fourni, non affiché »), ni dans
  une trace `bash -x` (coupée dès qu'un secret est en jeu), ni dans l'environnement des autres processus (variable retirée dès le départ) ; il est transmis à `toutpanel setup` par
  l'**environnement de ce seul processus** (`TOUTPANEL_SETUP_PASSWORD`), jamais en argument. Force minimale contrôlée avant toute modification (8 caractères, une lettre, un chiffre,
  différent du nom d'utilisateur, pas dans la liste des mots de passe courants) avec message traduit ; une mise à jour ne modifie jamais le mot de passe existant (avertissement si un mot de
  passe est fourni). `toutpanel setup` : nouvelles sources `--password-stdin` et variable `TOUTPANEL_SETUP_PASSWORD` (un mot de passe reçu ainsi n'est ni écrit dans
  `data/initial_password.txt` ni renvoyé dans le JSON ; champ `password_generated`), et un mot de passe fourni est désormais contrôlé par la politique du panel (code de sortie 3) ; si le panel
  refuse un mot de passe que l'installeur avait accepté, l'installation n'est pas perdue : mot de passe aléatoire et avertissement. Aide `--help` (10 langues), `--dry-run` (source du mot de
  passe, jamais sa valeur : `ADMIN_PASSWORD_SOURCE`), `scripts/installer_options.json` (option `--password` avec `env`, `secret_alternatives` et `warning_key`, options `--password-file`,
  `--password-stdin`, `-PasswordSecure`) et documentation Linux / Windows (section « Mot de passe administrateur »). **Testé** : `tests/test_installer_password.py` (bash réel, PowerShell réel
  avec `pwsh`, pseudo-terminal pour les questions, vraie commande `toutpanel setup`) ; le faux `toutpanel` des tests d'installeur est simulé, aucune installation complète n'a été exécutée.

- **Serveur DNS au choix (BIND, PowerDNS, Knot DNS) et serveur de courrier au choix (Postfix, Exim)** : composants modulaires, un seul serveur autoritaire local à la fois (port 53)
  et un seul agent de transfert (port 25). Nouveaux modules `toutpanel/services/dns_engines.py` et `mail_engines.py`, `cli_engines.py` (`toutpanel dns engine [NOM]`,
  `toutpanel mail engine [NOM]`, `--json`, `--yes`, `--dry-run`, `--rollback`, `--install`), routes `/api/dns/engines`, `/api/dns/engine` (+ `install`, `rollback`, `pdns-backend`) et
  `/api/mail/engines`, `/api/mail/engine` (+ `install`, `rollback`) réservées à l'administrateur, onglet **Moteur** des pages DNS et Serveur mail (`engines.js` / `engines.css` : cartes avec
  état, version, capacités et limites, tableau comparatif, bascule confirmée après contrôles, retour arrière), réglages `dns_engine` (défaut `bind`), `dns_pdns_backend`, `mail_engine` (défaut
  `postfix`) et leurs journaux, valeurs d'installeur `--dns bind|powerdns|knot|external|none` et `--mail postfix|postfix-clamav|postfix-light|exim|relay|none`. **DNS** : PowerDNS
  Authoritative (base SQLite `gsqlite3` ou fichiers de zone, API locale 127.0.0.1 à clé aléatoire, DNSSEC par `pdnsutil`, TSIG, `primary` / `secondary`) et Knot DNS (`knot.conf` généré,
  KASP automatique, `keymgr`, un `knot.conf` étranger n'est jamais écrasé) servent les zones du panel (même fichier de zone que BIND) ; écoute sur adresses explicites quand
  `systemd-resolved` occupe le port 53 ; zones secondaires et AXFR / NOTIFY / TSIG pour les trois moteurs. **Bascule A → B** : contrôles préalables, sauvegarde, préparation pendant que
  l'ancien moteur sert, vérification de chaque zone sur 127.0.0.1, retour arrière automatique ; **clés DNSSEC reprises** (BIND ↔ PowerDNS ↔ Knot, même DS chez le registrar : BIND n'adopte
  une clé importée qu'avec un fichier d'état créé par `dnssec-settime`) ; bascule refusée quand des clés ne peuvent pas suivre. **Courrier** : Exim 4 + Dovecot, **expérimental**, configuration
  générée depuis le modèle du panel (domaines virtuels, boîtes par LMTP et SASL Dovecot, alias / fourre-tout, DKIM natif avec les clés existantes, TLS et SNI, relais, débit, RBL, listes d'accès,
  Rspamd par protocole spamd, ClamAV) ; **tableau des limites** déclaré et grisé dans l'interface : pas de listes de diffusion, de suivi de message, de MX de secours ni de jail fail2ban du
  panel, Rspamd / ClamAV / débit / greylisting partiels ; bascule Postfix ↔ Exim sans toucher aux Maildir, file d'attente vide exigée, conflit de paquets Debian simulé (`apt-get -s`) et réinstallation
  de l'ancien agent en cas d'échec. Composeur de pile : PowerDNS et Knot **stables**, Exim **expérimental** (ils n'étaient plus « bientôt »), nouvelles étapes `dns_engine` / `mail_engine`,
  conflits (un seul DNS autoritaire, un seul agent de transfert), `dns-external` / `mail-relay` enregistrent leur réglage ; le pare-feu ouvre les ports du moteur actif. **Testé pour de vrai**
  (Ubuntu 24.04) : `pdns_server` 4.8, `knotd` 3.3, `named` 9.18 et `dig` avec la configuration générée (zones, DNSSEC, cycle PowerDNS → BIND → Knot → PowerDNS → BIND avec le même DS) ; Exim 4.97
  (routage `-bt`, ACL `-bh`, SNI, démon SMTP) avec un Dovecot 2.3 réel (LMTP vers Maildir, IMAP, SASL après STARTTLS). **Non exécuté** : secondaires DNS réels, Rspamd et ClamAV avec Exim,
  bascule Postfix → Exim avec les vrais paquets, familles RHEL (noms de paquets `pdns`, `knot`, `exim` non vérifiés). Voir les guides `docs/content/guide/dns.md`
  (Moteurs DNS) et `docs/content/guide/mail.md` (Moteurs de courrier).
- **OpenLiteSpeed, serveur web du panel avec LSPHP et LSCache** (aux côtés de Nginx, Apache et « les deux » ; **expérimental**). Nouveau module `toutpanel/services/openlitespeed.py`
  (`api/openlitespeed.py`, `cli_ols.py`, `pages-openlitespeed.js`, `distro.ols_repo`). **Installation** depuis le dépôt officiel LiteSpeed Tech : apt (Debian 10 à 13, Ubuntu 18.04 à 26.04,
  clés GPG `signed-by`) et dnf (RHEL, Alma, Rocky, CentOS Stream, Oracle, CloudLinux 8 à 10) ; **refus propre** (« non disponible », raison, aucune commande) sur SUSE, Arch, Alpine, Fedora,
  Amazon Linux, EL 7, nom de code inconnu ou architecture non publiée. Branches **1.9** (index signé), **1.8** et **1.7** (`.deb` de l'archive du dépôt, SHA-256 journalisé, `apt-mark hold` /
  `dnf versionlock` ; **limite : l'archive n'est pas couverte par l'index signé**, changer de branche est refusé sans retrait préalable). **LSPHP 7.4 à 8.5** (paquets `lsphpNN` et extensions
  traduites depuis le catalogue PHP, absents signalés). **WebAdmin 7080** désactivée ou limitée à 127.0.0.1, mot de passe aléatoire bcrypt, copie **chiffrée**, jamais journalisé.
  **Configuration générée** : `httpd_config.conf` dérivé des vhosts présents (écouteurs 80 / 443 ou ports de repli d'un WAF externe, IPv6 détectée, QUIC, gzip / Brotli, `.htaccess`) et un
  `vhconf.conf` par site (domaines, redirections et domaines redirigés, canonique, HTTPS forcé, SSL / SNI / OCSP / HTTP/2 / HTTP/3, HSTS et en-têtes par contexte, pages d'erreur,
  répertoires protégés bcrypt + IP, anti-hotlink, maintenance 503, compte suspendu, fichiers cachés, proxy / WebSocket / socket Unix / répartition, `open_basedir` et réglages PHP du site,
  processeur LSPHP dédié par compte limité, journaux au format *combined*), directives personnalisées `<site>.ols.conf`. **Validation avant application** (lint maison puis `openlitespeed -t`
  dont la sortie est analysée, car son code retour est trompeur), rechargement gracieux, instantané `.last-good` et retour arrière. **Bascule** Nginx / Apache / les deux ↔ OpenLiteSpeed
  (`toutpanel ols switch`, `POST /api/openlitespeed/switch`, bouton « Basculer ») : vhosts de tous les sites réécrits et testés avant de toucher aux services, retour arrière si le nouveau
  serveur ne démarre pas. **LSCache** par site (module `cache`, purge par le bouton existant, `X-LiteSpeed-Cache`), application pilotée par défaut ; option `lscache_public` (toutes les pages
  publiques, déconseillée avec des comptes). Intégrations : pare-feu (UDP 443 avec HTTP/3), journaux et GoAccess, Fail2ban, sauvegarde / restauration et réparation automatique, plans
  limités, résumé des services. **Composeur de pile** : OpenLiteSpeed et LSCache passent de « bientôt » à **expérimental** (`--web openlitespeed[:1.9|1.8|1.7]`, étape `ols_install`, conflits
  du résolveur : un seul serveur web, LSPHP et non mod_php, PHP ≥ 7.4, avertissement `ols_limits`), variante **OpenLiteSpeed + LSCache** des profils Mono-site léger et Haute performance
  (`--variant openlitespeed`). **Non pris en charge, listé partout (documentation, interface, API, `toutpanel ols unsupported`)** : WAF intégré, ModSecurity par site, filtrage par pays,
  connexions par site, détails de la répartition de charge et du proxy, cache FastCGI nginx, directives nginx / Apache personnalisées, réseaux IPv6 de la maintenance, Varnish. **Testé pour
  de vrai** (Ubuntu 24.04, sans systemd) : installation par le code du panel d'OpenLiteSpeed **1.7.19, 1.8.5 et 1.9.3**, et, sur chacune, démarrage et requêtes HTTP réelles (PHP LSPHP,
  `open_basedir`, statique, redirection, `.htaccess`, 403, 404 personnalisée, en-têtes, Basic bcrypt, LSCache miss / hit, maintenance, rechargement gracieux) ; vérifiés à la main : SNI, HTTP/2,
  proxy HTTP et socket Unix, WebSocket, répartition, anti-hotlink, LSPHP sous un autre utilisateur. **Simulé** (plateforme factice) : bascule Nginx → OLS → Nginx, commandes par distribution.
  **Non exécuté** : famille RHEL (`dnf`), `aarch64`, systemd, HTTP/3 avec un client QUIC, IPv6, SELinux / AppArmor (aucune politique livrée). Voir [OpenLiteSpeed](docs/content/guide/openlitespeed.md).
- **Accélérateurs gérés par le panel : Varnish, Memcached, JIT de PHP, Zstandard, HTTP/3, et bases MySQL Oracle / Percona / Redis par versions** (page **Accélérateurs**, `toutpanel accel`,
  `/api/accelerators`, composeur de pile `--accel …` / `--db …`). Nouveaux modules `toutpanel/services/accelerators.py` (logique), `stack_accel.py` (étapes et état du composeur),
  `toutpanel/platform/vendor_repos.py` (dépôts officiels MySQL Oracle, Percona, Redis, Varnish : disponibilité par famille de distribution, nom de code et architecture, refus expliqués),
  `api/accelerators.py`, `cli_accel.py`, `pages-accel.js` / `accel.css`. **Varnish** : paquet de la distribution ou séries 6.0 / 7.7 / 8.0 du dépôt officiel ; VCL générée (PURGE et BAN
  limités à 127.0.0.1 / ::1, défis ACME, chemins et cookies WordPress / WooCommerce exclus, cookies de suivi retirés, durée par défaut, grâce, `X-Forwarded-For` réécrit, `X-Cache`), compilée
  à blanc (`varnishd -C`) avant installation ; Varnish sur le port 80 et serveur web sur un port de repli (HTTP seulement : **le HTTPS reste servi par le serveur web sans cache Varnish**,
  Hitch non géré), extension d'unité systemd, contrôle d'une vraie requête puis retour arrière complet si elle échoue, mémoire proportionnelle à la RAM, « Vider le cache » d'un site
  qui bannit aussi ses pages dans Varnish ; refus propres (OpenRC, IIS, WAF externe, OpenLiteSpeed). **Memcached** : service réglé (mémoire, 127.0.0.1 ou socket Unix, connexions) sur Debian
  et RHEL, extension PHP `memcached` par version, statistiques, `flush_all` (SASL non géré, avertissement). **JIT** : `opcache.jit` et tampon par version de PHP 8.0+ dans `toutpanel-jit.ini`,
  chargé en priorité 99 (le paquet Sury règle `opcache.jit=off` dans `10-opcache.ini` : en priorité 00 le JIT restait éteint, constaté avec PHP 8.4), désactivé avant PHP 8.0, sous 1 Go
  et avec Xdebug ; le fichier de réglages d'OPcache passe aussi en priorité 99. **Zstandard** : directives Nginx seulement si le module est présent, sinon refus expliqué (étape « à terminer à la
  main » dans la pile). **HTTP/3** : vérification de `nginx -V` (1.25+ avec `--with-http_v3_module`), `listen 443 quic reuseport` + `Alt-Svc` (déjà générés), **UDP 443 ajouté à
  `firewall.required_ports`**, règle déclarée, retour arrière si `nginx -t` refuse ; refus propre sinon. **Bases** : MySQL Oracle 8.4 LTS / 9.7 LTS / innovation (clé `RPM-GPG-KEY-mysql-2025`, l'ancienne est
  expirée), Percona Server 8.0 / 8.4 (`percona-release`, télémétrie désactivée), Redis 7.2 à 8.x (dépôt officiel) ou Valkey, par `dbversions.plan()` / `status()` / `install()` ; **un seul
  moteur de la famille MySQL**, sauvegarde préalable **obligatoire** (dump Redis copié), rétrogradation, 8.0 → 9.x et Redis ↔ Valkey refusés, contrôle de la version obtenue. Composeur de
  pile : JIT et Memcached **stables**, Varnish, Zstandard, HTTP/3, MySQL Oracle et Percona **expérimentaux** avec explication (Percona et Zstandard ne sont plus « bientôt ») ; Caddy et Apache + mod_php
  restent « bientôt » et refusés proprement ; conflits du résolveur (Varnish ↔ port 80 / WAF / systemd, HTTP/3 ↔ version de Nginx, un seul moteur MySQL, installé ou choisi). **Testé pour de vrai**
  (Ubuntu 24.04) : `varnishd` 7.1 compile la VCL et sert un vrai backend, `memcached` 1.6 en TCP et en socket Unix, PHP 8.4 active le JIT, résolution `apt` des paquets MySQL / Percona / Redis ;
  **non exécuté** : Varnish devant Nginx sous systemd, HTTP/3 avec un Nginx QUIC en service, module Zstandard, installation d'un serveur MySQL Oracle / Percona. Voir
  [Accélérateurs](docs/content/guide/accelerateurs.md) et [Bases de données](docs/content/guide/bases-de-donnees.md#mysql-oracle-percona-et-redis-par-versions).
- **Moteurs FTP au choix : serveur intégré, Pure-FTPd, ProFTPD, vsftpd, SFTP seul ou aucun** (FTP → Moteur, `toutpanel ftp engine`, `--ftp` de l'installeur et du composeur de pile).
  Nouveau module `toutpanel/services/ftp_engines.py` : une interface commune (installation par famille de distribution, état et version, démarrage / arrêt / rechargement, génération de la
  configuration depuis les réglages FTP du panel — ports passifs, adresse annoncée, FTPS explicite avec le certificat du panel ou d'un site, FTPS implicite avec ProFTPD, anonymes toujours
  refusés, connexions maximales, débit, umask, bannière, journaux —, synchronisation des comptes, journal natif converti au format `ftp.log`) et, par moteur, des **capacités déclarées**
  (`oui` / `partiel` / `non` : quota, droits fins, IP autorisées, connexions par compte, uid par compte, chroot, débit, TLS explicite / implicite, IPv6…) que l'interface utilise pour
  **griser** ce qui n'est pas géré. Les comptes FTP du panel restent la source de vérité : chaque moteur est généré depuis la base (le mot de passe n'est jamais copié, seul le hachage bcrypt,
  écrit en `$2y$…`) avec l'uid / gid du compte propriétaire et le chroot dans la racine du site ; Pure-FTPd (PureDB, `pure-pw`), ProFTPD (`AuthUserFile`, `mod_wrap2`, `mod_tls`), vsftpd
  (`pam_userdb`, un fichier par compte), SFTP seul (utilisateurs système `useradd -o`, `Match Group`, montage « bind » du site dans un chroot root:root). **Bascule** (`ftp_engine`, défaut
  `builtin` : une installation existante ne change pas) : résumé de migration (comptes migrés, ignorés, fonctions non appliquées, ports), **garde-fou** si des comptes perdent une restriction de
  sécurité (`accept_degraded`), configuration du nouveau moteur générée et validée avant d'arrêter l'ancien, vérification de l'écoute, **retour arrière automatique** puis `previous`.
  Un seul moteur actif à la fois ; sshd n'est jamais arrêté. `firewall.required_ports()` suit le moteur (21 + passifs, 990 en FTPS implicite, port SSH seul pour SFTP, rien pour « Aucun »).
  Routes `GET /api/ftp/engines`, `GET /api/ftp/engine/plan`, `POST /api/ftp/engine`, `POST /api/ftp/engine/sync` (administrateur) ; `POST /api/ftp/server` agit sur le moteur actif ;
  commande `toutpanel ftp engine [NOM] [--yes] [--dry-run] [--accept-degraded] [--json]` ; réglages `ftp_engine`, `ftp_engine_previous`, `ftp_tls_implicit`, `ftp_tls_site`, `ftp_umask`. Composeur de
  pile : Pure-FTPd, ProFTPD, vsftpd et SFTP seul passent de « bientôt » / noop à **expérimentaux** réels (installation, état, retrait, un seul serveur FTP) ; la plage passive du FTP intégré
  affichée par le catalogue est corrigée (60000-60100). **Exécuté pour de vrai sous Ubuntu 24.04** (démons installés, connexions `ftplib` et `paramiko`, bascules A → B → A, retour arrière) ;
  chemins RHEL, IPv6 et SELinux non éprouvés. Voir [FTP](docs/content/guide/ftp.md#moteurs-ftp).
- **Composeur de pile logicielle** (assistant de configuration, Réglages → Pile logicielle, `toutpanel stack`). Un moteur unique (`toutpanel/services/stack.py`, catalogue déclaratif
  `toutpanel/data/stack_catalog.json`) choisit, valide et installe serveur web (Nginx, Apache + PHP-FPM, Nginx + Apache), PHP 5.6 à 8.5 côte à côte, accélérateurs (OPcache, APCu, Redis / Valkey,
  Brotli, cache FastCGI, HTTP/3, ionCube, Varnish, Memcached, JIT, Zstandard ; voir l'entrée « Accélérateurs »), MariaDB / PostgreSQL / MySQL / Percona à la version voulue, FTP intégré, Postfix + Dovecot + Rspamd
  (avec ou sans ClamAV), BIND ou DNS externe, Fail2ban, ModSecurity, ClamAV, ToutWAF et runtimes (Node.js, Python, Go, Ruby, Java, Docker). Onze profils (mono-site, multi-sites, hébergeur, haute
  performance, application, mail seul, DNS seul, nœud minimal, LAMP, pile standard de l'installeur, personnalisé) et quatre types d'installation (mono-serveur, mono-site, multi-sites, multi-serveurs
  par rôles). Résolveur pur `resolve(selection, faits) -> Plan` : conflits (deux serveurs web, mod_php et pool par site…), dépendances ajoutées automatiquement, disponibilité par famille et version de
  distribution (`platform/distro.py`), estimation RAM / disque / durée, ports à ouvrir, étapes ordonnées ; réglages proportionnels à la mémoire `tuning(ram_mb, profil)` (PHP-FPM, OPcache, MariaDB,
  Redis). Application reprenable (journal `stack-progress.json`) et idempotente, journalisée, par tâche de fond ; **les composants « à venir » (Caddy, Apache + mod_php,
  Exim, Knot DNS, PowerDNS serveur, Percona, MySQL Oracle, Zstandard ; OpenLiteSpeed et LSCache le sont devenus : voir l'entrée OpenLiteSpeed) sont refusés avec un message, jamais simulés**. Routes `/api/stack` (catalogue, état, plan,
  application, progression, retrait) et `/api/setup/stack/*` (jeton de l'assistant) ; commande `toutpanel stack catalog|profiles|plan|apply|status` (`--profile`, `--web`, `--php`, `--db`, `--ftp`,
  `--mail`, `--dns`, `--accel`, `--mode` / `--install-mode`, `--from` / `--stack-file`, `--yes`, `--dry-run`, `--json` ; codes de sortie 0 à 3) appelable par l'installeur. Interface : cartes de
  profils recommandées selon le serveur, composition par sections pliables, **schéma d'architecture SVG animé** exportable (SVG, PNG, impression), récapitulatif, progression avec reprise, page
  d'état réel (versions installées, ajout, changement de version, retrait). Trois étapes ajoutées à l'assistant avant le pare-feu, avec « Passer : décider plus tard ». Réglages `stack_profile`,
  `stack_mode`, `stack_components`, `stack_roles`, `stack_applied_at`. Voir [Pile logicielle](docs/content/guide/pile-logicielle.md).
- **Pare-feu : mode de gestion, garde-fou anti-verrouillage et nouvelle interface** (Sécurité → Pare-feu, assistant de configuration, `toutpanel firewall`).
  Nouveau réglage `firewall_mode` : `panel` (ToutPanel gère le pare-feu du serveur), `external` (pare-feu en amont : cloud, matériel, hébergeur — **aucune règle système n'est touchée**,
  les règles restent « déclarées, non appliquées » et la liste des ports à ouvrir chez l'hébergeur est affichée, copiable et exportable) ou vide (à choisir ; comportement historique).
  Migration : installation existante avec pare-feu actif → `panel`. Tout ce qui modifie le pare-feu système (règles, activation, protection réseau, bannissements du WAF, accès distant aux bases,
  restriction d'origine ToutWAF, reprise au démarrage) devient un no-op explicite en mode `external` ; fail2ban reste indépendant. Étape **Pare-feu** de l'assistant (3 cartes : gérer avec ToutPanel avec
  choix du moteur et activation immédiate, pare-feu en amont, décider plus tard) ; `toutpanel setup --firewall panel|external|later [--firewall-engine …]` et
  `toutpanel firewall status|enable|disable|mode|ports` (`--json`, codes de sortie 0 à 3). **Garde-fou anti-verrouillage** : essai de 60 s avec compte à rebours, annulation automatique côté serveur
  (reprise après redémarrage), SSH (port réel de sshd), ports du panel, services actifs et IP de l'administrateur autorisés d'office. Interface refondue : bandeau d'état, cartes de synthèse,
  onglets Règles (recherche, filtres, tri, actions groupées, tiroir d'édition avec validation et commande équivalente), Ports ouverts / exposition, Listes d'IP (CIDR, expiration, import / export),
  Services prédéfinis, Journal et Avancé ; règles « tous protocoles » et temporaires, désactivables. Réglages `firewall_mode`, `fw_mode_migrated`, `fw_guard_seconds`, `fw_last_change`.
  Voir [Pare-feu](docs/content/guide/pare-feu.md).
- **Compatibilité étendue avec les distributions Linux** : détection centralisée (`toutpanel/platform/distro.py`, depuis `/etc/os-release` et l'architecture) de la famille
  (debian, rhel, rhel-yum, amzn, suse, arch, alpine), du gestionnaire de paquets, de l'init et d'un **niveau de support** (complet / réduit / non pris en charge) avec sa raison.
  Debian 10 à 14 et testing, Ubuntu 18.04 à 26.04 et suivantes (LTS et intermédiaires), dérivés (Linux Mint, LMDE, Pop!_OS, Zorin, elementary, Raspberry Pi OS, Armbian,
  Proxmox VE, Devuan, Kali), RHEL / AlmaLinux / Rocky / CentOS Stream / Oracle Linux / CloudLinux 8 à 10 et suivantes, CentOS 7, Amazon Linux 2 / 2023, Fedora 39 et suivantes,
  openSUSE / SLES, Arch et dérivés, Alpine 3.18+. Plancher de version par distribution, **jamais de plafond** : une version future d'une famille connue reste prise en charge.
  Dépôts PHP (Sury, PPA ondrej avec le codename Ubuntu de la base pour Mint / Pop!_OS, Remi, paquets Amazon Linux), MariaDB et PostgreSQL (codenames récents ou inconnus, repli sur le
  dernier publié, erreur claire sans dépôt), EPEL Oracle, `yum` / `yum-cron` (CentOS 7), OpenRC (`rc-service`), dossiers Apache SUSE / Alpine, vérification d'intégrité `pacman` / `apk`.
  `toutpanel check` affiche distribution, version, famille, niveau, architecture et init ; nouvelle commande `toutpanel compat [--json] [--arch]` ; `GET /api/system/overview` expose `distro`,
  `GET /api/system/compat` la matrice ; bandeau d'avertissement sur l'accueil quand le niveau est « réduit » ou « non pris en charge ». Voir [Installation › Linux](docs/content/installation/linux.md).
- **ToutWAF distant : relier le panel à une autre installation de ToutWAF** (WAF › Moteur › ToutWAF › Mode « Distant », et `toutpanel waf connect toutwaf`).
  Aucune installation locale : le serveur web garde 80 / 443 ; les sites sont déclarés par l'API REST de ToutWAF (`<console>/api/v1`, chemin secret compris),
  une application par site avec ses domaines et alias, origine `scheme://IP:port` (adresse d'origine détectée : privée si réseau commun, sinon publique),
  en-tête `Host` conservé, certificats envoyés (`import`) ou obtenus par ToutWAF (`acme`), politique publiée ; idempotent, aucun domaine d'une autre
  application n'est écrasé, un site supprimé retire son application. Nouveaux réglages `toutwaf_mode` (`local` par défaut), `toutwaf_remote_host`, `toutwaf_remote_path`,
  `toutwaf_remote_fingerprint` (épinglage TLS vérifié avant l'envoi du jeton), `toutwaf_remote_insecure`, `toutwaf_remote_token` (chiffré), `toutwaf_origin_ip`,
  `toutwaf_origin_http_port` / `toutwaf_origin_https_port` / `toutwaf_origin_scheme`, `toutwaf_cert_mode`, `toutwaf_restrict_origin` (pare-feu : 80 / 443 depuis le seul ToutWAF,
  avec confirmation et retour arrière), `toutwaf_remote_server_id` (heartbeat 60 s). CLI : `waf connect | disconnect | status toutwaf` (jeton par `TOUTPANEL_WAF_TOKEN` ou entrée standard, jamais en argument ;
  `--json` ; codes de sortie 2 à 8 documentés), API `POST /api/waf/engines/toutwaf/connect|disconnect|test`, `GET …/status`. Surveillance toutes les 5 minutes avec alerte (événement `waf`)
  quand ToutWAF devient injoignable, refuse le jeton ou n'a plus de data plane ; journal des 20 dernières synchronisations. Voir [WAF](docs/content/guide/waf.md).
- **Installer une version précise** : `install.sh --version X.Y.Z` (aussi `vX.Y.Z`, `0.4.0b1` ou `0.4.0-beta.1`, variable `TOUTPANEL_VERSION`)
  et `install.ps1 -Version X.Y.Z` ; `--list-versions` / `-ListVersions` liste les versions publiées (la plus récente d'abord, canal stable ou dev)
  sans rien modifier. Le dépôt public n'ayant pas d'étiquettes obligatoires, la version est retrouvée par l'étiquette `vX.Y.Z` si elle existe,
  sinon par le commit de publication dont le sujet est exactement « ToutPanel X.Y.Z » (clone partiel sous Linux, API GitHub publique sous
  Windows, sans Git). Version introuvable ou sans roue pour le Python du système : arrêt avant toute modification, avec la liste des
  versions disponibles. Une préversion implique le canal `dev`. Mise à jour ou **descente** d'une installation existante permises, avec
  avertissement traduit et confirmation (sauf `--yes`) en cas de descente. Messages dans les 10 langues.
- **Le panel écoute en HTTP et en HTTPS en même temps**, dans un seul processus : HTTP sur `panel_port` (8888, inchangé) et HTTPS sur le
  nouveau `panel_https_port` (8443). Nouveaux réglages `panel_http_enabled` (vrai), `panel_https_enabled` (vrai), `panel_https_port` (8443)
  et `panel_redirect_https` (faux : redirection `308` HTTP vers HTTPS, avec l'hôte demandé, l'entrée sécurisée et le chemin conservés, jamais
  pour `127.0.0.1` / `::1` ni pour les routes internes de vérification SSO). Deux serveurs uvicorn dans la même boucle avec la même
  application ; le cycle de vie (services de fond, planificateurs, message « démarré ») ne s'exécute qu'une fois ; SIGTERM / SIGINT arrêtent
  proprement les deux écoutes (uvicorn 0.27 et suivants) ; un port occupé ou un certificat inutilisable désactive seulement l'écoute concernée
  (erreur claire dans `panel.log`), code de sortie 1 si aucune écoute ne démarre. Certificat auto-signé généré au premier démarrage avec les
  noms et adresses locales du serveur, régénéré s'il en manque ; rechargé comme avant au renouvellement.
- **Migration automatique** de l'ancien réglage `panel_ssl` au premier démarrage (rejouable) : `true` reste HTTPS seul sur `panel_port` (mode
  nœud et installations en HTTPS existantes inchangés), `false` garde le HTTP et ajoute l'HTTPS sur 8443 (ou le premier port libre ; le
  pare-feu n'est pas ouvert par la migration). Fonction unique `config.panel_listeners()` pour tous les usages.
- Adresses, cookies et en-têtes selon l'écoute : `toutpanel info`, assistant, e-mails (HTTPS préféré), clients internes (HTTP local, sinon
  HTTPS sans vérification), drapeau `Secure` des cookies et adresses de retour SSO selon le **schéma de la requête**, HSTS seulement en HTTPS
  et jamais sur une adresse IP, fail2ban sur les deux ports, ports de repli du WAF décalés s'ils sont ceux du panel.
- Réglages › Accès & interface : « Écouter en HTTP », « Écouter en HTTPS », ports, « Rediriger HTTP vers HTTPS », état du certificat, liens
  vers les deux adresses ; refus (sauf confirmation explicite `confirm_listener_loss`) de désactiver l'écoute par laquelle on est connecté ;
  validation (ports 1 à 65535, ports différents, au moins une écoute active). L'assistant de configuration gagne le champ « Port HTTPS », la
  case de redirection et affiche l'adresse finale en HTTPS et en HTTP.
- CLI : `toutpanel https-port N`, `toutpanel http on|off`, `toutpanel ssl on|off` (écoute HTTPS), `toutpanel info` (deux URL),
  `toutpanel setup --https-port N` (le JSON renvoie aussi `https_port`, `http_enabled`, `https_enabled`).
- Installeurs : ouverture du port HTTP **et** du port HTTPS du panel dans le pare-feu, option `--https-port` / `-HttpsPort`, récapitulatif
  et `install-info.txt` avec « URL du panel (HTTP) » et « (HTTPS) » (public et local, mention du certificat auto-signé), liens de
  l'assistant en HTTPS quand il est actif ; messages dans les 10 langues.
- **phpMyAdmin installable depuis le panel**, à côté d'Adminer (Bases de données → onglet **Outils d'administration**) : même site « dbadmin »
  (Adminer garde l'adresse `/`, phpMyAdmin est servi sous `/phpmyadmin/`), installation depuis l'archive officielle
  `files.phpmyadmin.net` avec **vérification SHA-256 obligatoire**, extraction sûre (anti zip-slip), dossier `setup/` supprimé,
  `blowfish_secret` aléatoire de 32 octets, `AllowNoPassword = false`, `TempDir` hors de la racine web, accès aux fichiers de
  configuration interdit (nginx et Apache) et droits restrictifs.
- **Connexion unique à phpMyAdmin** (`auth_type = 'signon'`, script `tp-signon.php` : jeton à usage unique de 60 s, mot de passe jamais
  dans le navigateur) ; le bouton « Ouvrir » des bases propose un menu **Ouvrir avec** quand les deux outils sont installés, avec un
  outil par défaut réglable (`dbadmin_default_tool`) ; PostgreSQL reste sur Adminer.
- **Choix de toutes les versions** d'Adminer et de phpMyAdmin à l'installation et ensuite (changement de version avec conservation de
  la configuration, sauvegarde de la version précédente et retour arrière automatique en cas d'échec), dernière stable compatible par
  défaut, préversions sur option, **compatibilité avec la version de PHP** (badge par version, version incompatible refusée avec les
  versions compatibles proposées, choix de la version de PHP du site) et avec le serveur de bases détecté (MySQL 8 / 9, MariaDB 10.x / 11.x).
- **Mises à jour** : badge « mise à jour disponible », bouton « Mettre à jour », « Rechercher les nouvelles versions » (cache de 6 h, recherche
  planifiée des CMS étendue aux outils installés).
- API : `GET /api/databases/dbadmin` (les deux outils), `GET /api/databases/dbadmin/{tool}/versions`, `POST /api/databases/dbadmin/install`
  (`tool`, `version`, `domain`, `php_version`), `POST /api/databases/dbadmin/{tool}/update`, `PUT /api/databases/dbadmin/default-tool`,
  `DELETE /api/databases/dbadmin/{tool}` et `POST /api/databases/{id}/open` avec `tool` ; les appels existants restent valables.
- Logiciels : le paquet système phpMyAdmin renvoie vers l'installation du panel (connexion unique, version au choix).

- **Installeur Linux : répertoire `/var/toutpanel`, pare-feu au choix, pile du composeur, distributions étendues, Python 3.9+ fourni** (`install.sh`, 10 langues, `scripts/installer_options.json`) :
  - **Répertoire par défaut `/var/toutpanel`** (Windows : `C:\toutpanel`, inchangé). Une installation existante dans l'ancien défaut `/www/toutpanel` (ou ailleurs : unité systemd, lien `/usr/local/bin/toutpanel`) est **détectée et conservée sans déplacement**, avec un message clair, en installation, mise à jour, réinstallation et désinstallation ; `--home DIR` reste possible (refus des dossiers système). Les sites restent dans `/www/wwwroot` (`TOUTPANEL_WWW`). Contextes SELinux, AppArmor, logrotate, unité systemd et sauvegardes suivent le répertoire retenu.
  - **Pare-feu** `--firewall on|off|ask` (`--firewall-engine`) : `on` → `toutpanel setup --firewall panel` puis `toutpanel firewall enable --port …` (à la place des commandes `ufw` / `firewalld` de l'installeur) ; `off` → `--firewall external`, **aucune commande système de pare-feu** et ports à ouvrir chez l'hébergeur (`toutpanel firewall ports`) affichés en fin d'installation ; `ask` ou aucune option dans un terminal → question à trois choix (ToutPanel / en amont / plus tard) ; sans terminal ou avec `--yes` : « plus tard » (rien n'est touché, ufw n'est jamais activé sans demande). Une mise à jour ne modifie **jamais** le pare-feu. ToutWAF distant : raccordement avant le pare-feu, `firewall enable --no-web` quand 80 / 443 sont restreints. Ligne « Pare-feu » dans le récapitulatif et `install-info.txt`.
  - **Pile du composeur** : `--profile`, `--web`, `--php`, `--php-default`, `--php-ext`, `--db`, `--redis`, `--accel`, `--ftp`, `--mail MOTEUR`, `--dns`, `--security`, `--runtime`, `--tools`, `--install-mode`, `--roles`, `--stack-file`, `--no-tuning` transmises telles quelles à `toutpanel stack apply … --yes` après l'installation du panel (validation de syntaxe traduite côté installeur) ; un échec (codes 1, 2, 3) ne fait pas échouer l'installation du panel (avertissement et commande de reprise) ; question du profil (liste de `toutpanel stack profiles`) dans un terminal ; `--stack full|minimal|none` conservé (obsolète) ; lignes Profil de pile, Composants et Compatibilité dans le récapitulatif. `--mail` seul garde son sens historique.
  - **Distributions** : détection depuis `/etc/os-release` (`ID`, `ID_LIKE`, `VERSION_ID`, codenames, `VARIANT_ID`) avec les mêmes familles et planchers que `toutpanel/platform/distro.py` (debian, rhel, rhel-yum, amzn, suse, arch, alpine ; dérivés Mint / Pop!_OS / Zorin / Raspberry Pi OS / Kali, Oracle `ID_LIKE=fedora`, numérotation Fedora ≥ 25), `dnf` / `yum` (sans `--allowerasing`) / `apt` / `zypper` / `pacman` / `apk`, noms de paquets et de services par famille, OpenRC / sysvinit (scripts d'init), Amazon Linux, **refus propres** traduits (Gentoo, NixOS, Void, Photon, systèmes immuables…), avertissement **non bloquant** pour le niveau « réduit », jamais de plafond de version ; niveau relevé ensuite par `toutpanel compat --json`.
  - **Python 3.9+ sur les systèmes anciens** (Debian 10, Ubuntu 18.04 / 20.04, RHEL / Alma / Rocky / CentOS 7-8, Amazon Linux 2, SLES / Leap 15) : paquet récent de la distribution (AppStream, `python311`, deadsnakes), sinon Python autonome (`uv` + python-build-standalone) dans `<home>/python` après **vérification SHA-256**, uniquement si l'utilisateur l'accepte (`--yes` ou question) ; compilateur installé hors x86_64 / aarch64.
  - `--dry-run` (sans root, sans rien modifier) affiche la détection, le plan et les commandes `toutpanel` prévues.
  - **Aide `--help` en sections** (Compte et accès, Réseau et ports, Dossiers, Version, Pile logicielle, Pare-feu, Moteur WAF, Divers) et nouveaux messages traduits en 10 langues (`h_*`, `hs_*`, `dr_*`, `fw_*`, `stack_*`, `python_*`, `lbl_*`…).
  - **Windows** (`install.ps1`) : les options propres à Linux (`-Firewall`, `-Profile`, `-Web`, `-Php`, `-Db`, `-Mail`, `-Node`, `-Channel`, `-DryRun`…) sont **refusées avec un message clair** ; `-Home` garde `C:\toutpanel`.
  - **`scripts/installer_options.json`** : source unique de toutes les options des installeurs (noms, alias, variables d'environnement, types, valeurs, défauts, dépendances, conflits, plateformes, section d'aide, clé de message, options sensibles), **vérifiée contre `install.sh` et `install.ps1`** par `scripts/check_installer_options.py` et `tests/test_installer_options.py` ; destinée au générateur de ligne d'installation du site.
  - Tests : `tests/test_installer_distro.py` (100+ fichiers os-release factices, parité avec `distro.py`, Python autonome avec SHA-256 contre un faux dépôt `file://`), `tests/test_installer_stack.py` (répertoire, pare-feu, pile, questions interactives par pseudo-terminal, faux `toutpanel` enregistrant arguments et environnement, jeton jamais en argument), `tests/test_installer_options.py`.

### Corrigé

- Installeur Linux : les paquets PHP optionnels `phpX.Y-bcmath` et `phpX.Y-opcache` ne bloquent plus l'installation (PHP 8.5+ intègre OpenCache : plus de paquet séparé) ; sans effet ailleurs.
- OpenLiteSpeed : les réglages `php.ini` enregistrés depuis la page **PHP** sont maintenant **réellement reportés** dans le `php.ini` de LSPHP de la même version (`php.set_ini` appelle `openlitespeed.sync_lsphp_ini` quand OpenLiteSpeed est le serveur web actif ; sans effet sinon), comme l'annonçait le guide.
- Adminer en connexion unique : le jeton consommé ne suit plus la redirection d'Adminer (la page d'accueil de la base répondait « Jeton
  invalide ou expiré »), connexion automatique compatible Adminer 6 ; les règles de sécurité du vhost sont aussi écrites pour Apache
  (`dbadmin.apache.conf`). Les installations existantes sont corrigées au prochain « Ouvrir ».

### Modifié

- Canal développeur : **0.4.0 bêta 2** (numéro de paquet `0.4.0b2`), construite sur la base de la 0.3.1 (la bêta 1 était `0.4.0b1`) ; les
  nouveautés de la prochaine version stable sont listées ici au fil des bêtas. La bêta 2 apporte notamment la pile logicielle modulaire
  (profils, versions, schéma d'architecture), le pare-feu géré par le panel ou en amont, OpenLiteSpeed, les moteurs FTP / DNS / mail au choix
  (plusieurs sont **expérimentaux**), les accélérateurs, la compatibilité de distributions étendue, l'écoute HTTP + HTTPS, le raccordement
  à un ToutWAF distant et un installeur enrichi (`--version`, `--firewall`, options de pile, mot de passe hors ligne de commande).
- Installeurs (Linux et Windows) : le récapitulatif final et `install-info.txt` donnent maintenant, en plus de l'adresse publique, le **lien de
  connexion local** et le **lien direct de l'assistant de configuration pour l'adresse locale** (réseau privé) ; l'assistant met à jour
  les deux adresses dans `install-info.txt` après son passage.

## [0.3.1] - 2026-10-03

### Modifié

- Design de l'interface (tous les thèmes) : échelle typographique unique, en-têtes de page avec fil d'Ariane discret (groupe du
  menu), aide près du titre et actions alignées, cartes, boutons, badges et formulaires harmonisés (états désactivé, lecture
  seule et erreur), onglets à icônes alignées et fondu quand ils débordent, tableaux plus aérés (en-tête collant au-delà de 12
  lignes, chiffres tabulaires, actions de ligne discrètes au repos), états vides illustrés avec bouton d'action (Sites, Bases de
  données, Sauvegardes, Tâches planifiées), squelette de page pendant le chargement, recherche en pastille avec raccourci clavier,
  graphiques avec infobulle au survol ou au toucher et palette dérivée de la couleur d'accent, mode sombre avec champs en
  retrait et filet de lumière sur les cartes.
- Mobile : menu avec fond assombri (fermeture au clic extérieur ou à Échap), cibles tactiles de 44 px, compteurs et jauges sur
  deux colonnes, fenêtres en feuille basse, assistant de configuration sans rognage ; plus aucun défilement horizontal en
  390 px (Sécurité, CMS › Installations).
- Contrastes : pastilles « Pro » et compteur du menu, logos du catalogue CMS et des applications, lettre du logo en mode sombre,
  page de connexion avec une couleur d'accent très claire : tous les textes testés atteignent 4,5:1.
- Thème Horizon : nouvelle police d'affichage **Plus Jakarta Sans** (licence SIL OFL, fichiers hébergés avec le panel, aucune
  ressource distante), avec Inter en repli pour le cyrillique ; léger espacement des mots pour la lisibilité.
- Menu latéral : le bouton « Verre / Opaque » est retiré (le contraste élevé reste réglable dans Personnalisation et par
  utilisateur).
- Catalogue CMS : 595 applications dont 582 vérifiées (536 gratuites, 46 commerciales) ; une entrée est retirée du catalogue.

## [0.3.0] - 2026-10-03


### Ajouté

- CMS : catalogue porté à 595 entrées (582 vérifiées : 536 gratuites, 46 commerciales), nouvelles familles
  PyPI (environnement virtuel), Java, .NET, dépôts Composer privés (Mage-OS, Adobe Commerce), distributions Drupal, frameworks
  Node.js et Python. Type de distribution **commercial** : fiche avec éditeur, prix indicatif, lien d'achat et licence
  requise, installation à partir d'un **paquet fourni** (envoi depuis la fiche, chemin sur le serveur ou URL privée), **clé de
  licence** transmise à la configuration, extensions ajoutées à un CMS parent existant (WordPress, PrestaShop, Joomla,
  Dolibarr), version lue dans le paquet et mise à jour par paquet. Recherche des nouvelles versions faite par le panel
  lui-même auprès des sources officielles (cache local de 6 h) : bouton **Rechercher les nouvelles mises à jour** en tête
  de l'onglet Installations (date, heure et résultat), recherche des versions du catalogue depuis l'onglet Installer,
  recherche automatique **deux fois par jour** (05:23 et 17:23, heures réglables `cms_check_times`) et historique des
  recherches. Routes `/api/cms/packages`, `/api/cms/checks`, `/api/cms/catalog/refresh`.
- Installeurs multilingues (`install.sh`, `install.ps1`) : 10 langues (anglais par défaut, français, allemand, espagnol,
  italien, portugais, néerlandais, russe, chinois, arabe) pour tous les textes affichés (bannière, menu et questions, étapes,
  avertissements, erreurs, aide, récapitulatif, `install-info.txt`). Choix : `--lang xx` ou `--fr`, `--de`… (`-Lang xx`,
  `-Fr`… sous Windows), puis `TOUTPANEL_LANG`, puis `INSTALLER_LANG` / `$InstallerLang` écrit dans le script, puis la langue
  du système (`LC_ALL` / `LC_MESSAGES` / `LANG`, `Get-Culture`), sinon l'anglais ; une ligne sous la bannière indique la
  langue retenue et son origine. La langue choisie devient la langue initiale du panel (réglage `language`, installation et
  réinstallation seulement). Catalogue unique `scripts/installer_messages.json`, embarqué dans les deux scripts par
  `scripts/installer_i18n.py` (vérification de parité des clés et des `%s`, `--check`) ; `install.ps1` gagne `-Help` et
  reste en ASCII pur hors commentaires (lisible par PowerShell 5.1 sans BOM). Tests : `tests/test_installer_i18n.py`.
- CMS : nouvelle page **CMS** qui remplace l'entrée « WP Toolkit » (devenue l'onglet **WordPress**, `#/wordpress` reste un
  alias). Onglet **Installer** : catalogue de 375 CMS et applications web (364 vérifiés : source des versions interrogée et URL
  de téléchargement contrôlée par `scripts/cms_catalog.py`, catalogue `toutpanel/data/cms/*.json`), recherche, filtres par
  catégorie et par type, pastille « prêt » / « prérequis manquants », fiche avec prérequis vérifiés et propositions
  d'installation (Logiciels, extensions PHP), **choix de la version** (dernière stable par défaut, préversions sur option),
  site existant ou nouveau, sous-dossier, base créée automatiquement, compte administrateur, langue, suivi en direct.
  Familles d'installation : archive officielle, dépôt git à une étiquette, `composer create-project`, paquet npm / npx,
  binaire Go, WordPress + extension (WooCommerce, bbPress, BuddyPress, LearnPress, GiveWP…). Onglet **Installations** :
  détection automatique sur tous les sites (y compris les installations faites hors du panel), version installée et
  dernière version, sauvegarde (fichiers + base), mise à jour en place (wp-cli, CLI du CMS ou remplacement des fichiers
  en conservant configuration et données, migrations, retour arrière en cas d'échec) avec sauvegarde avant, **Tout mettre
  à jour** (file une par une), clonage vers un autre site / sous-dossier (base copiée, configuration et adresses
  adaptées), réinstallation, suppression, journal des opérations. Vérification quotidienne des versions (05:23), alerte
  par les canaux de notification (option), mises à jour mineures automatiques par installation, pastille du menu et
  widget d'accueil « Mises à jour CMS ». Routes `/api/cms/…`.
- WAF : **ToutWAF**, le WAF / reverse proxy de l'éditeur, devient un moteur au choix (et le moteur recommandé) dans WAF › Moteur
  (édition Pro) : installation par l'installeur officiel (canal stable ou dev, hôte public, ouverture du pare-feu) avec bascule
  du serveur web sur les ports de repli, liens secrets de la console et lien d'installation à usage unique affichés, version
  installée / disponible (`channel.json`, cache 6 h) avec badge « Mise à jour disponible », mise à jour avec retour arrière,
  désinstallation (option purge), démarrage / arrêt, diagnostic (`toutwafctl doctor` ou contrôles locaux), synchronisation
  idempotente des sites (politique locale `policy.yaml` + certificats, ou API REST de la console avec jeton) et raccordement du
  data plane à la console. Routes `/api/waf/engines/toutwaf/{update,channel,doctor,links,setup-link,enroll}`, commandes
  `toutpanel waf install|update|links|doctor toutwaf`, option `install.sh --waf toutwaf`.
- Thèmes : nouveau thème **Horizon** (ciel dégradé bleu-cyan-lavande, menu et barre du haut flottants translucides, pilule
  active et boutons en dégradé bleu-violet qui suit la couleur choisie, titres bleus très gras), **thème par défaut** d'une
  nouvelle installation ; 13 thèmes au total. Mode clair par défaut.
- Assistant de configuration : choix de la couleur principale (préréglages, pipette, hexadécimal) et de la densité, avec
  aperçu immédiat ; `install-info.txt` mis à jour quelle que soit la langue de l'installeur.

### Modifié

- Édition : l'installation de BunkerWeb ou SafeLine depuis la page Logiciels applique désormais le même contrôle d'édition
  que WAF › Moteur (choix du moteur réservé à l'édition Professionnelle).
- Store : les routes d'un module chargé à chaud sont enregistrées sur toutes les instances de l'application.

## [0.2.0] - 2026-10-03

### Ajouté

- Éditions : édition Personnelle gratuite sans clé (usage personnel, 5 sites) et édition Professionnelle / Entreprise activée par
  une clé de licence `TP-XXXXX-XXXXX-XXXXX-XXXXX` (jeton signé, fonctionnement hors ligne avec période de grâce, revalidation
  quotidienne, page Réglages › Licence, carte Licence sur l'accueil, badges « Pro » et réponses 402 explicites, commande
  `toutpanel licence`).
- Accueil personnalisable : grille de 23 widgets (tailles, glisser-déposer, ajout/retrait, réinitialisation), disposition
  enregistrée par utilisateur.
- Thèmes : 12 thèmes en clair et en sombre (Classique, Aurora, Nuage, Minimal, Nuit, Terminal, Gloss, Nébuleuse, Obsidian,
  Nordic, Ember, Executive) avec couleur d'accent par défaut puis libre (préréglages, pipette, hex), densité, coins, police,
  largeur, position du menu, icônes, animations, surcharges de couleurs par mode avec contraste affiché, aperçu en direct,
  export / import du thème ; préférence par utilisateur et valeur par défaut globale.
- Store d'applications : page Store à onglets (Applications, Logiciels serveur, Modules, Thèmes, Installés) reliée au
  catalogue toutpanel.com, installation de modules (manifest validé, sha256 obligatoire, extraction sûre), modules Python
  chargés à chaud, pages et thèmes de modules, envoi d'un zip local, mode hors ligne, modules payants réservés à l'édition
  Professionnelle.
- Assistant de configuration : lien direct affiché à la fin de l'installation (jeton à usage unique, 24 h) pour changer
  l'utilisateur, le mot de passe, le port, l'entrée sécurisée, le nom d'hôte, la langue et le thème sans passer par les
  réglages ; aussi accessible connecté (menu et accueil) ; commande `toutpanel setup-link`.
- Documentation complète : référence de toutes les routes de l'API, de tous les réglages, de tous les messages d'erreur,
  de la CLI et des modèles de données ; guides pour chaque page ; 10 langues d'interface mises à jour.

### Ajouté

- Distribution : le dépôt public ne contient plus de code source. Chaque version y est publiée sous forme de roues Python
  « bytecode seulement » (`dist/toutpanel-<version>-cp3XY-none-any.whl`, une par version de CPython 3.9 à 3.14, JS et CSS
  minifiés) avec `dist/manifest.json`, `dist/SHA256SUMS` et `version.json`. `install.sh`, `install.ps1` et `toutpanel update`
  installent la roue correspondant au Python du système (message explicite et liste des versions prises en charge sinon) ;
  le mode source reste disponible pour le dépôt de développement. Licence propriétaire ToutPanel (édition Personnelle
  gratuite) à la place de la licence MIT.
- Administration du serveur : services avec activation au démarrage, mise à jour du panel par canal (stable, développeur,
  personnalisé) avec sauvegarde préalable, vérification de santé après redémarrage et retour à la version précédente,
  historique des mises à jour, commande `toutpanel update`, option `--channel dev` de `install.sh`.
- Gestion des adresses IP : inventaire, IP additionnelles persistantes (netplan, NetworkManager, ifupdown), IP dédiées à un
  compte, adresse d'écoute par site.
- Hôte : nom d'hôte, fuseau horaire, synchronisation NTP, fichier d'échange (swap) et `vm.swappiness`.
- Versions des SGBD : détection, dépôts officiels MariaDB et PostgreSQL (PGDG), changement de version majeure avec
  sauvegarde complète préalable.
- File de tâches : concurrence réglable, priorité, annulation, relance et purge des tâches terminées.
- Réparation automatique : conservation des derniers vhosts valides, restauration si `nginx -t` / `apachectl -t` échoue,
  diagnostic et corrections (vhosts orphelins, sites sans vhost, pools PHP orphelins, permissions, services, certificats).
- Multi-tenant (comptes, revendeurs, plans, quotas, permissions), hébergement avancé, authentification avancée, DNS et SSL
  avancés, messagerie avancée, bases de données et fichiers avancés, applications, tâches planifiées, sauvegardes et
  sécurité du serveur.

## [0.1.1] - 2026-09-26

### Ajouté

- Répartition de charge (load balancing) nginx / Apache pour les sites proxy : groupes de serveurs, poids, secours,
  méthodes round robin, least_conn et ip_hash.
- Déploiement Git dans les paramètres du site, rôles des utilisateurs, mise à jour du panel et des scripts, alertes.
- Gestion DNS, webmail Roundcube, 10 langues et habillage Classique.
- Installateurs : menu installer / mettre à jour / désinstaller, adresses publique et locale affichées.

### Corrigé

- `install.sh` : arrêt silencieux après « Sécurisation de MariaDB » ; service lancé via l'interpréteur du venv
  (SELinux) et vérification que le panel répond.
- Validation de SafeLine et du DNS sous Windows.

## [0.1.0] - 2026-09-19

### Ajouté

- Première version publique : backend FastAPI, interface web, installeurs Linux (`install.sh`) et Windows (`install.ps1`).
- Sites web Nginx / Apache / IIS, SSL Let's Encrypt, WP Toolkit, bases de données, fichiers, terminal, Docker.
- Serveur mail (Postfix, Dovecot, OpenDKIM) et pare-feu applicatif (WAF) avec moteurs BunkerWeb et SafeLine.
- PHP multi-versions et personnalisation avancée (modèles Jinja2, apparence, menus).
- Support de Debian, Ubuntu, Fedora, AlmaLinux, Rocky Linux, RHEL et de Windows 10+ / Server 2016+.

### Corrigé

- 12 corrections issues de la campagne de test de bout en bout ; suppression de `datetime.utcnow()` déprécié.
