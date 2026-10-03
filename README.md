<div align="center">

# ToutPanel

**Le panel d'hébergement web pour Linux et Windows : sites, PHP, bases de données, mail, DNS, SSL, sécurité et sauvegardes depuis une seule interface web, en 10 langues.**

Nginx · Apache · IIS · PHP 5.6 → 8.5 · MariaDB · PostgreSQL · MongoDB · Postfix / Dovecot · BIND · Let's Encrypt · WAF · Docker · multi-tenant · multi-serveurs

![Version](https://img.shields.io/badge/version-0.3.1-2b5fd9?style=flat-square)
![Canal](https://img.shields.io/badge/canal-stable-16a34a?style=flat-square)
![Systèmes](https://img.shields.io/badge/syst%C3%A8mes-Linux%20%7C%20Windows-0f172a?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.9%20%E2%86%92%203.14-3776ab?style=flat-square)
![Langues](https://img.shields.io/badge/langues-10-8b5cf6?style=flat-square)
![Édition Personnelle](https://img.shields.io/badge/%C3%A9dition%20Personnelle-gratuite-10b981?style=flat-square)

[Installer](#installation-complète) · [Fonctionnalités](#fonctionnalités) · [CMS](#cms) · [Captures d'écran](#captures-décran) · [Thèmes](#thèmes) · [Éditions](#éditions) · [Architecture](#architecture) · [Premier démarrage](#premier-démarrage) · [Dépannage](#dépannage) · [English](README.en.md)

**Version 0.3.1** · canal **stable** · 2026-10-03

</div>

![Tableau de bord ToutPanel, thème Horizon](screenshots/dashboard.webp)

---

## C'est quoi ToutPanel ?

ToutPanel transforme un serveur fraîchement installé en **plateforme d'hébergement web complète**, pilotée depuis le navigateur. Une commande installe la pile (Nginx, PHP-FPM, MariaDB, Redis ou Valkey, Certbot, Fail2ban), le panel et son service ; vous créez ensuite vos sites, bases, boîtes mail, zones DNS et certificats en quelques clics, sans éditer un seul fichier de configuration.

Il s'adresse autant à la personne qui héberge **ses propres sites** (édition Personnelle gratuite, sans clé ni inscription) qu'aux **agences et hébergeurs** qui revendent de l'hébergement : comptes revendeurs et clients, plans et quotas, facturation, marque blanche, multi-serveurs et haute disponibilité (éditions Professionnelle et Entreprise).

Vos données restent **sur votre serveur** : aucune police ni CDN externe dans l'interface, aucun appel au serveur de licences tant qu'aucune licence n'est activée.

> **Ce dépôt ne contient aucun code source.** Il publie uniquement ce qui sert à installer le panel : les installeurs `install.sh` et `install.ps1`, le panel compilé (`dist/`, roues Python « bytecode seulement »), les notes de version, la licence et `version.json`.

| | |
|---|---|
| **Systèmes** | Debian 11 → 13, Ubuntu 20.04 → 24.04, AlmaLinux / Rocky Linux / RHEL 9 et 10, Fedora 40+, Windows 10 / 11, Windows Server 2016 → 2025 |
| **Serveurs web** | Nginx, Apache, Nginx + Apache, IIS (basique) |
| **PHP** | 5.6 à 8.5 côte à côte, 138 extensions au catalogue, une version par site |
| **Bases de données** | MariaDB / MySQL, PostgreSQL, MongoDB, SQLite, Redis / Memcached par compte |
| **CMS** | 595 CMS et applications au catalogue (582 vérifiés : 536 gratuits, 46 commerciaux), version au choix, installations suivies et mises à jour |
| **Interface** | 10 langues, 13 thèmes clair / sombre (**Horizon** par défaut), couleur d'accent libre, accessibilité WCAG AA |
| **Installeurs** | `install.sh` et `install.ps1` en 10 langues (anglais par défaut, `--lang` / `--fr`…, `TOUTPANEL_LANG`, langue du système) |
| **Automatisation** | API REST (OpenAPI), CLI de 76 commandes, webhooks signés, modules Ansible, exemples Terraform |

## Fonctionnalités

### Hébergement web
- **Sites en un clic** : multi-domaines, PHP-FPM, statique, reverse proxy, applications ; vhosts **Nginx, Apache, Nginx + Apache ou IIS** générés depuis des modèles Jinja2 et **testés avant rechargement** (`nginx -t` / `apachectl -t`, retour aux derniers vhosts valides en cas d'échec).
- **PHP multi-versions** : 5.6 → 8.5 côte à côte (Sury, PPA ondrej, Remi, windows.php.net), 138 extensions, ionCube, `php.ini` et pool FPM par site, version CLI par défaut.
- **Hébergement avancé** : redirections, hôte canonique, en-têtes, répertoires protégés, pages d'erreur, anti-hotlink, mode maintenance, cache FastCGI, préproduction (staging), statistiques GoAccess, répartition de charge (round robin, least_conn, ip_hash), compression, HTTP/2, HTTP/3, profils TLS.
- **Déploiement Git** atomique par site (HTTPS avec jeton ou SSH, branche, étiquette ou commit, actualisation automatique, retour arrière).
- **Domaines et adresses IP** : inventaire des IP, IP additionnelles persistantes, IP dédiées à un compte, adresse d'écoute par site.

### SSL / TLS
- **Let's Encrypt** (HTTP-01, DNS-01, wildcard), ZeroSSL, Buypass, autorité ACME personnalisée, CSR, import PFX, auto-signé, HSTS, **renouvellement automatique**.
- Page **Certificats** : validité, émetteur et expiration de tous les certificats ; HTTPS du panel par Let's Encrypt ; certificats SNI du serveur mail.

### DNS
- Zones **BIND**, tous les types d'enregistrements, gabarits, **DNSSEC**, serveurs secondaires (TSIG), DNS inverse, import / export BIND.
- Zones poussées chez **Cloudflare, PowerDNS, OVH, Route53** ; vérification de propagation.

### Mail et webmail
- **Postfix, Dovecot, OpenDKIM** ou rspamd ; domaines, boîtes, alias, redirections, listes (mlmmj), filtres Sieve et répondeur.
- **Webmail Roundcube ou SnappyMail** installé en un clic avec connexion directe depuis le panel.
- Rotation DKIM, antispam, ClamAV, greylisting, RBL, débit d'envoi, relais sortant, suivi des messages, file d'attente, fetchmail, CalDAV / CardDAV, MTA-STS, autoconfiguration des clients.

### Bases de données
- **MariaDB / MySQL, PostgreSQL, MongoDB, SQLite** : bases, utilisateurs et privilèges, accès distant par IP, **Adminer en SSO**, import / export, maintenance, quotas de taille.
- Serveurs supplémentaires (Docker), **Redis / Memcached par compte**, détection des versions, dépôts officiels MariaDB et PostgreSQL (PGDG), changement de version majeure avec sauvegarde préalable, réplication (Pro).

### Fichiers, FTP et accès
- **Gestionnaire de fichiers** complet : éditeur CodeMirror, archives, corbeille, permissions et propriétaire, recherche dans le contenu, occupation du disque, glisser-déposer.
- **Serveur FTP / FTPS intégré** (comptes, droits, quotas, journal), **SFTP chrooté**, shell restreint, clés SSH, **WebDAV** avec les comptes FTP.
- **Terminal web** : bash sous Linux, PowerShell sous Windows.

### CMS
- **Page CMS** : catalogue de **595 CMS et applications web**, dont **582 vérifiés** (source des versions interrogée, URL de téléchargement contrôlée) : **536 gratuits** et **46 commerciaux** ; recherche, filtres par catégorie, type (PHP, Node.js, Python, Go, Java, .NET, statique) et distribution, pastille « prêt » ou « prérequis manquants ».
- **Choix de la version** : dernière stable par défaut, toutes les versions publiées (préversions sur option) ; fiche avec prérequis vérifiés, site existant ou nouveau, sous-dossier, base créée automatiquement, compte administrateur et langue, suivi en direct.
- **Installations centralisées** : détection automatique sur tous les sites (y compris les installations faites hors du panel), version installée et dernière version, bandeau des mises à jour disponibles ; **sauvegarde** (fichiers et base), **mise à jour** avec sauvegarde préalable et retour arrière en cas d'échec, **Tout mettre à jour**, **clonage** vers un autre site ou sous-dossier, réinstallation, suppression, journal des opérations, mises à jour mineures automatiques par installation.
- **Logiciels commerciaux** : fiche avec éditeur, prix indicatif et lien d'achat ; installation à partir du **paquet fourni** par l'éditeur (envoi depuis la fiche, chemin sur le serveur ou URL privée) et de sa clé de licence ; mise à jour par paquet.
- **Recherche locale des versions** : le panel interroge lui-même les sources officielles (wordpress.org, GitHub, Packagist, npm, PyPI, sites des éditeurs), avec un cache local de 6 h, **deux fois par jour** (05:23 et 17:23, heures réglables) ou à la demande ; alerte par les canaux de notification, pastille du menu et widget d'accueil.

### Applications, WordPress et Docker
- **Installateur d'applications** : WordPress, Joomla, Drupal, Grav, PrestaShop, Nextcloud, Laravel, Symfony, Matomo, Dolibarr, Moodle, phpBB, MediaWiki, Ghost — téléchargement, base, configuration et post-installation automatiques.
- **WP Toolkit** (onglet WordPress de la page CMS) : wp-cli, mises à jour, durcissement, détection des vulnérabilités, clonage.
- Applications **Node.js, Python, Ruby, Go, Java, .NET** avec unité systemd et proxy.
- **Docker** : conteneurs, images, `docker run`, projets **Docker Compose** par compte avec site proxy.

### Sauvegardes
- Sauvegarde de site, base, dossier, boîte mail, compte ou **serveur entier** ; planifications GFS ; restauration granulaire ; sauvegardes de sécurité automatiques (avant une suppression, par exemple) ; vérification des sauvegardes.
- Moteur **restic** chiffré et dédupliqué, **destinations distantes** S3 et compatibles, SFTP, Backblaze B2, et via rclone FTP / Google Drive / OneDrive / Dropbox / WebDAV (Pro). Secrets chiffrés en base, jamais renvoyés par l'API.

### Sécurité
- **Pare-feu** nftables, firewalld, UFW, CSF ou iptables (détection automatique), protection anti-DDoS, ports en écoute.
- **Fail2ban**, **WAF intégré** (SQLi, XSS, RCE, traversée, scanners, robots, débit, bannissement automatique ; blocage par pays en Pro) et **ModSecurity + OWASP CRS** par site (Pro).
- **ToutWAF**, le WAF / reverse proxy de l'éditeur, **moteur recommandé** dans WAF › Moteur (Pro) : installation depuis le panel par l'installeur officiel (canal stable ou dev, serveur web basculé sur les ports de repli), liens secrets de la **console** (:9443), version installée et disponible, mise à jour avec retour arrière, diagnostic, **synchronisation** des sites (politique locale ou API de la console) ; aussi à l'installation avec `install.sh --waf toutwaf`. **BunkerWeb** et **SafeLine** (Docker) restent proposés.
- **Antimalware** ClamAV / maldet / YARA avec quarantaine, intégrité (rkhunter, chkrootkit, debsums, AIDE), AppArmor et **SELinux** configurés automatiquement.
- **Authentification** : 2FA TOTP et codes de secours, **clés de sécurité WebAuthn / passkeys**, entrée sécurisée secrète, liste blanche d'IP, captcha ALTCHA, verrouillage persistant, sessions révocables ; LDAP / Active Directory, OpenID Connect et SAML (Pro).
- **Journal d'audit scellé** (HMAC chaîné), carte « Recommandations » sur la page Sécurité.

### Supervision et alertes
- Accueil personnalisable : **23 widgets** (CPU, RAM, disques, I/O, réseau, services, quotas, mémo…), disposition enregistrée par utilisateur.
- **Monitoring** historique, sondes **d'uptime** HTTP(S), processus par compte, journaux en direct, services avec redémarrage automatique.
- **Alertes** par e-mail, webhook, Telegram ou SMS (service arrêté, disque plein, certificat qui expire…), export **Prometheus** `/metrics` (Pro).
- Administration de l'hôte : nom d'hôte, fuseau horaire, NTP, swap, mises à jour du système (sécurité, automatiques, redémarrage requis), file de tâches, **réparation automatique**.

### Multi-tenant, revendeurs et facturation
- Hiérarchie **administrateur → revendeurs → clients → sous-utilisateurs**, permissions par module et par action, profils d'accès.
- **Plans et quotas** (disque, inodes, trafic, sites, bases, boîtes…), limites CPU / RAM / E-S (cgroups), utilisateur système dédié, suspension automatique, connexion « en tant que », transfert, import / export CSV.
- **Facturation** (TVA, prorata, relances, PDF), Stripe, PayPal, virement, provisioning à la commande, WHMCS / Blesta / HostBill, **marque blanche**, e-mails transactionnels, tickets de support, annonces (Pro).

### Multi-serveurs et haute disponibilité
- **Panel maître et nœuds** enrôlés par jeton (web, mail, DNS, bases), ressources routées, comptes miroirs, **migration de comptes** entre serveurs (Pro).
- **Haute disponibilité** : groupes web (rsync, lsyncd, NFS), réplication MariaDB / PostgreSQL avec bascule, DNS secondaires et MX secondaire automatiques, migration à chaud (Pro).
- **Migration** depuis cPanel, Plesk, DirectAdmin, ISPConfig, un hébergement mutualisé ou des boîtes IMAP, avec rapport (Pro ; l'export reste libre).

### API, CLI et automatisation
- **API REST** complète avec jetons à portée et IP restreintes, documentation **OpenAPI / Swagger**.
- **Webhooks sortants signés**, scripts pré / post-action, **CLI** `toutpanel` (site, account, db, mail, dns, backup, cron, ftp, task… avec sortie `--json`), modules Ansible et exemples Terraform.

### Store, personnalisation et confort
- **Store** relié au catalogue toutpanel.com : applications, logiciels serveur, **modules** (manifeste validé, sha256 obligatoire, chargement à chaud), thèmes ; envoi d'un zip local, mode hors ligne.
- **Assistant de configuration** à la fin de l'installation (compte, adresse du panel, langue, mode, thème, **couleur principale** et **densité** avec aperçu immédiat), **assistant de création** (site + base + certificat + boîtes mail en une fois), **recherche globale Ctrl+K**, aide contextuelle sur chaque page, outils de diagnostic (DNS, HTTP, SSL, ping, traceroute, port, SMTP, WHOIS).
- **13 thèmes**, dont **Horizon** par défaut, couleur d'accent libre, logo, CSS, liens du menu, modèles des vhosts et des e-mails ; **10 langues** : français, English, español, Deutsch, italiano, português, Nederlands, русский, 中文, العربية (écriture de droite à gauche).

### Conformité (RGPD)
- Export et suppression des données personnelles, registre des traitements, rétention des journaux, historique des mots de passe, traçabilité des accès de l'hébergeur, ancrage externe du journal d'audit (Pro).

## Captures d'écran

| | |
|---|---|
| ![Accueil en mode sombre](screenshots/dashboard-dark.webp)<br>**Accueil, mode sombre** : jauges, compteurs, points d'attention, licence | ![Sites web](screenshots/sites.webp)<br>**Sites web** : domaines, type, racine, trafic, SSL et actions |
| ![PHP](screenshots/php.webp)<br>**PHP** : versions 5.6 → 8.5 côte à côte, état du support, pools FPM | ![Déploiement Git](screenshots/git.webp)<br>**Paramètres du site** : déploiement Git, SSL, redirections, sécurité |
| ![DNS](screenshots/dns.webp)<br>**DNS** : zones BIND ou fournisseurs, gabarits, DNSSEC, cluster | ![Certificats SSL](screenshots/certs.webp)<br>**Certificats** : validité, émetteur, renouvellement, certificat du panel |
| ![Serveur mail](screenshots/mail.webp)<br>**Serveur mail** : Postfix, Dovecot, OpenDKIM, ports et onglets | ![Webmail](screenshots/webmail.webp)<br>**Webmail** : Roundcube ou SnappyMail installé en un clic |
| ![Bases de données](screenshots/databases.webp)<br>**Bases de données** : MariaDB, PostgreSQL, MongoDB, SQLite, Redis | ![Fichiers](screenshots/files.webp)<br>**Fichiers** : éditeur, archives, corbeille, permissions, occupation |
| ![CMS](screenshots/cms.webp)<br>**CMS › Installer** : 582 CMS et applications vérifiés, recherche, filtres, pastille « prêt » | ![Fiche d'installation](screenshots/cms-app.webp)<br>**Fiche d'un CMS** : prérequis vérifiés, choix de la version, site cible, base |
| ![Installations CMS](screenshots/cms-installed.webp)<br>**CMS › Installations** : versions, mises à jour disponibles, sauvegarde, clonage | ![WAF › Moteur](screenshots/waf-engine.webp)<br>**WAF › Moteur** : ToutWAF recommandé, WAF intégré, BunkerWeb, SafeLine |
| ![Terminal](screenshots/terminal.webp)<br>**Terminal** : shell interactif bash / PowerShell dans le navigateur | ![Applications](screenshots/apps.webp)<br>**Applications** : WordPress, Joomla, Drupal, PrestaShop, Nextcloud… |
| ![Store](screenshots/software.webp)<br>**Store** : logiciels serveur, modules et thèmes en un clic | ![Sécurité](screenshots/security.webp)<br>**Sécurité** : recommandations, pare-feu, anti-DDoS, Fail2ban |
| ![WAF](screenshots/waf.webp)<br>**WAF** : protections, seuils, moteurs, GeoIP, journal des attaques | ![Monitoring](screenshots/monitor.webp)<br>**Monitoring** : CPU, mémoire, réseau, charge et disque sur 1 h → 7 j |
| ![Comptes](screenshots/accounts.webp)<br>**Comptes** : revendeurs, clients, plans, profils d'accès | ![Serveurs](screenshots/nodes.webp)<br>**Serveurs** : panel maître, nœuds, routage, migration |
| ![Mises à jour](screenshots/updates.webp)<br>**Mises à jour** : paquets du système (sécurité) et du panel | ![Réglages](screenshots/settings.webp)<br>**Réglages** : accès, port, entrée secrète, HTTPS, interface |
| ![Assistant de configuration](screenshots/setup.webp)<br>**Assistant de configuration** : thème, couleur principale, densité, aperçu immédiat | ![Horizon clair et sombre](screenshots/horizon.webp)<br>**Horizon**, thème par défaut : le même écran en clair et en sombre |

**Sur mobile**, l'interface s'adapte (menu repliable, tableaux défilants) :

<table>
<tr>
<td align="center"><img src="screenshots/dashboard-mobile.webp" width="240" alt="Accueil sur mobile"><br><b>Accueil</b></td>
<td align="center"><img src="screenshots/sites-mobile.webp" width="240" alt="Sites sur mobile"><br><b>Sites web</b></td>
</tr>
</table>

> Captures réalisées sur un serveur de démonstration (Ubuntu 24.04, adresse de documentation 192.0.2.2).

## Thèmes

### 13 thèmes, votre couleur

Une nouvelle installation utilise **Horizon** : ciel dégradé bleu-cyan, menu et barre du haut flottants translucides, pilule active en dégradé bleu-violet qui suit la couleur choisie, titres bleus très gras. **Personnalisation › Apparence** : choisissez un autre design, puis **n'importe quelle couleur d'accent** (12 préréglages, pipette ou code `#RRGGBB`). Le panel en dérive boutons, liens, menu actif, badges, dégradés et graphiques, en gardant un contraste d'au moins 4,5:1. Chaque thème existe en **clair et en sombre**, respecte le contraste élevé et les langues de droite à gauche ; l'aperçu est immédiat, rien n'est enregistré avant « Enregistrer le design ». Densité, coins, police, largeur, position du menu, icônes et animations se règlent aussi, par utilisateur ou par défaut pour tous ; le thème s'exporte et s'importe.

![Choix du thème et de la couleur](screenshots/custom.webp)

| | | |
|---|---|---|
| ![Horizon](screenshots/theme-horizon.webp)<br>**Horizon** *(par défaut)* · `#2b5fd9` | ![Classique](screenshots/theme-classique.webp)<br>**Classique** · `#2563eb` | ![Aurora](screenshots/theme-aurora.webp)<br>**Aurora** · `#2563eb` |
| ![Nuage](screenshots/theme-nuage.webp)<br>**Nuage** · `#5b5bd6` | ![Minimal](screenshots/theme-minimal.webp)<br>**Minimal** · `#18181b` | ![Nuit](screenshots/theme-nuit.webp)<br>**Nuit** · `#0369a1` |
| ![Terminal](screenshots/theme-terminal.webp)<br>**Terminal** · `#15803d` | ![Gloss](screenshots/theme-gloss.webp)<br>**Gloss** · `#7c3aed` | ![Nébuleuse](screenshots/theme-nebuleuse.webp)<br>**Nébuleuse** · `#8b5cf6` |
| ![Obsidian](screenshots/theme-obsidian.webp)<br>**Obsidian** · `#22c55e` | ![Nordic](screenshots/theme-nordic.webp)<br>**Nordic** · `#14b8a6` | ![Ember](screenshots/theme-ember.webp)<br>**Ember** · `#f97316` |
| ![Executive](screenshots/theme-executive.webp)<br>**Executive** · `#10b981` | | |

<sub>Couleur indiquée : accent par défaut du thème en mode clair, librement modifiable.</sub>

Le thème, le mode, la **couleur principale** et la **densité** se choisissent aussi dès l'**assistant de configuration** (étape Préférences), avec aperçu immédiat ; ce sont les valeurs par défaut de tous les comptes, chacun pouvant ensuite choisir les siennes.

## Éditions

Le programme est le même pour toutes les éditions : une **clé de licence** active les fonctions avancées sur un serveur donné. Une installation neuve fonctionne en édition Personnelle, sans inscription ni connexion à Internet.

| Édition | Prix | Clé | Pour qui |
|---|---|---|---|
| **Personnelle** | gratuite, sans limite de durée | aucune | usage personnel : vos propres sites, **jusqu'à 5** |
| **Professionnelle** | payante | obligatoire | hébergeurs, agences, usage professionnel : tout est inclus, sites illimités (ou selon le plan de licence) |
| **Entreprise** | payante | obligatoire | Professionnelle + multi-serveurs illimités + support prioritaire |

L'édition Personnelle est **complète** : sites, PHP multi-versions, bases de données, mail, DNS, SSL, WAF intégré, sauvegardes locales, monitoring, comptes clients et sous-utilisateurs, WebAuthn, outils RGPD, API et CLI. Sont réservés aux éditions payantes :

<details>
<summary><b>Liste exacte des fonctions Professionnelle / Entreprise</b></summary>

| Fonction | Personnelle | Professionnelle |
|---|---|---|
| Sites | 5 au maximum | illimités (ou selon la licence) |
| Sondes d'uptime | 3 | illimitées |
| Webhooks sortants | 2 | illimités |
| Choix du moteur WAF (ToutWAF, BunkerWeb, SafeLine) | WAF intégré | ✓ |
| ModSecurity + OWASP CRS | — | ✓ |
| Multi-serveurs : nœuds, haute disponibilité, migration à chaud | — | ✓ |
| Groupes web et cluster DNS | — | ✓ |
| Réplication des bases | — | ✓ |
| Facturation, passerelles, WHMCS, provisioning | — | ✓ |
| Marque blanche des revendeurs | — | ✓ |
| Domaine personnalisé du panel | — | ✓ |
| Support (tickets) | — | ✓ |
| Annonces | — | ✓ |
| Comptes revendeurs | — (clients et sous-utilisateurs : ✓) | ✓ |
| SSO LDAP / OpenID Connect / SAML | — (WebAuthn : ✓) | ✓ |
| Blocage par pays (GeoIP) | — | ✓ |
| Antimalware planifié | analyse manuelle | ✓ |
| Sauvegardes distantes (S3, SFTP, B2, rclone) | stockage local | ✓ |
| Moteur restic | — | ✓ |
| Export Prometheus `/metrics` | — | ✓ |
| Import depuis cPanel, Plesk, DirectAdmin, ISPConfig, mutualisé, IMAP | — (export : ✓) | ✓ |
| Modules premium du store | — | ✓ |
| Ancrage externe du journal d'audit | — (export et purge RGPD : ✓) | ✓ |

</details>

- Les entrées concernées portent un badge **Pro** ; les pages restent consultables, seules la création et la modification sont réservées.
- Activation : **Réglages › Licence › Activer une clé** (`TP-XXXXX-XXXXX-XXXXX-XXXXX`) ou `toutpanel licence activate <clé>`. Le jeton signé est vérifié localement : la licence fonctionne hors ligne (revalidation quotidienne, période de grâce de 15 jours).
- Si la licence expire ou n'est plus valide, le panel **repasse en édition Personnelle sans rien supprimer**.

Tarifs et achat : **[toutpanel.com/tarifs](https://toutpanel.com/tarifs)** · détails : [Éditions et licence](https://toutpanel.com/docs/guide/editions/).

## Architecture

```mermaid
flowchart TB
    U["Navigateur<br/>admin · revendeur · client"] -->|"HTTP(S) :8888 + entrée secrète"| P
    V["Visiteurs"] -->|"HTTP / HTTPS 80 · 443"| W
    subgraph S["Votre serveur"]
        P["<b>Panel ToutPanel</b><br/>FastAPI + Uvicorn · SQLite<br/>planificateur · FTP intégré · API REST"]
        subgraph PILE["Services pilotés par le panel"]
            W["Nginx / Apache / IIS"]
            F["PHP-FPM 5.6 → 8.5"]
            D[("MariaDB · PostgreSQL<br/>MongoDB · Redis")]
            M["Postfix · Dovecot · OpenDKIM"]
            B["BIND (DNS)"]
            X["systemd · pare-feu<br/>Fail2ban · Docker"]
        end
        R[("/www/wwwroot<br/>racine des sites")]
        P ==>|"configurations générées et testées"| PILE
        W --> R
        F --> R
    end
    P -. "API à jeton" .-> N["Autres serveurs ToutPanel<br/>(nœuds, multi-serveurs)"]
```

| Composant | Rôle |
|---|---|
| **Panel** | Application FastAPI servie par Uvicorn (service systemd `toutpanel` sous Linux, tâche planifiée `ToutPanel` sous Windows). Interface web sans dépendance externe, API REST, planificateur de tâches, serveur FTP intégré. |
| **Pile web** | Nginx et/ou Apache (IIS sous Windows) avec PHP-FPM ; le panel écrit les vhosts depuis ses modèles, les teste puis recharge le service. |
| **Services** | MariaDB / PostgreSQL / MongoDB, Postfix / Dovecot / OpenDKIM, BIND, Fail2ban, pare-feu, Docker : pilotés par le panel via leurs outils natifs. |
| **CLI `toutpanel`** | Administration du panel (port, entrée, mot de passe, mise à jour, licence…) et commandes métier scriptables (`--json`). |

```
<home>  (/www/toutpanel ou C:\toutpanel)
├── data/      base SQLite du panel, settings.json, clés, install-info.txt
├── logs/      panel.log et journaux des sites
├── vhost/     vhosts générés (si le dossier natif du serveur web est absent)
├── ssl/       certificats des sites et du panel
├── backup/    sauvegardes locales
├── src/       clone de ce dépôt (canaux, étiquettes, toutpanel update)
└── venv/      environnement Python du panel
/www/wwwroot   racine des sites (C:\toutpanel\wwwroot sous Windows)
```

## Installation complète

### Prérequis

| | Linux | Windows |
|---|---|---|
| **Systèmes** | Debian 11, 12, 13 · Ubuntu 20.04, 22.04, 24.04 · AlmaLinux / Rocky Linux / RHEL 9, 10 · Fedora 40+ (Arch, Alpine, openSUSE : panel fonctionnel, pile réduite, non testés) | Windows 10, 11 · Windows Server 2016, 2019, 2022, 2025 (build 14393 minimum) |
| **Droits** | `root` (ou `sudo`) et `bash` | PowerShell 5.1+ **en administrateur** (winget non nécessaire) |
| **Python** | 3.9 à 3.14 (installé par le script si la distribution le fournit) | installé par le script (3.12, python.org) si absent |
| **Mémoire** | 1 Go minimum (panel seul), 2 Go recommandés avec MariaDB et PHP | idem |
| **Disque** | 2 Go libres + vos sites | idem |
| **Réseau** | accès sortant HTTPS (GitHub, PyPI, dépôts de la distribution, Let's Encrypt) ; IP publique fixe et DNS inverse pour le mail | idem (python.org, nginx.org, windows.php.net, MariaDB) |

Installez de préférence sur un serveur **fraîchement installé**. Sur un serveur où Nginx, Apache ou MariaDB sont déjà configurés, utilisez `--stack none` : le panel les détecte et écrit ses vhosts dans leur dossier natif sans toucher au reste.

### Linux

```bash
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash
```

Pour lire le script avant de l'exécuter :

```bash
curl -sSLO https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh
less install.sh
sudo bash install.sh
```

L'installation dure de 3 à 6 minutes selon la connexion.

**Menu interactif.** Lancé dans un terminal sans option de mode, le script présente ToutPanel, détecte une installation existante et propose : **installer** (pile complète) ou **installer le panel seul**, éventuellement en **mode nœud** ; ou, si le panel est déjà là, **mettre à jour**, **réinstaller complètement** ou **désinstaller**. Sans terminal (automatisation, `--yes`), il installe, ou met à jour si le panel est présent.

**Ce que fait le script :**

1. installe Python 3.9+ si nécessaire et crée l'environnement virtuel `<home>/venv` ;
2. installe la **pile web** (Nginx, PHP-FPM, MariaDB, Redis ou Valkey, Certbot, Fail2ban), selon `--stack` ;
3. clone ce dépôt dans `<home>/src`, **vérifie la somme SHA-256** de la roue correspondant au Python du système et l'installe ;
4. crée un **compte administrateur** et une **URL d'accès secrète** aléatoires ;
5. enregistre le **service systemd** `toutpanel` ;
6. ouvre les ports nécessaires dans le pare-feu ;
7. configure **SELinux** (Alma, Rocky, RHEL, Fedora) ou **AppArmor** (Debian, Ubuntu, SUSE) ;
8. affiche un récapitulatif, enregistré dans `<home>/data/install-info.txt` (lisible par root uniquement).

#### Options de `install.sh`

| Option | Description | Défaut |
|---|---|---|
| `--stack full` | Nginx + PHP-FPM + MariaDB + Redis/Valkey + Certbot + Fail2ban | ✓ |
| `--stack minimal` | Nginx + PHP-FPM + Certbot | |
| `--stack none` | uniquement le panel (serveur déjà configuré) | |
| `--mail` | ajoute Postfix, Dovecot, OpenDKIM et ouvre les ports mail | non |
| `--postgres` | ajoute PostgreSQL (mot de passe du rôle `postgres` généré et enregistré dans le panel) | non |
| `--waf toutwaf` | déploie **ToutWAF**, le WAF de l'éditeur, devant les sites par son installeur officiel (services systemd, sans Docker ; serveur web déplacé sur 8080 / 8443, console sur 9443, récapitulatif dans `/etc/toutwaf/INSTALL-SUMMARY.txt`) | non |
| `--waf bunkerweb` / `--waf safeline` | installe Docker et déploie le WAF externe devant les sites (serveur web déplacé sur 8080 / 8443, console sur 7000 ou 9443) | non |
| `--node` | mode **nœud** multi-serveurs : HTTPS du panel activé, jeton d'enrôlement, URL de l'API et empreinte TLS affichés (à saisir sur le maître : Système › Serveurs › Ajouter) | non |
| `--master URL` | avec `--node` : URL du panel maître | — |
| `--port N` | port du panel | `8888` |
| `--random-port` | port aléatoire entre 20000 et 40000 | |
| `--username NOM` | nom du compte administrateur | `admin_xxxxxx` aléatoire |
| `--password MDP` | mot de passe administrateur | 16 caractères aléatoires |
| `--entrance /chemin` | entrée sécurisée de l'URL | `/tp_xxxxxxxxxx` aléatoire |
| `--home DIR` | répertoire du panel | `/www/toutpanel` |
| `--source DIR` | installer depuis un dossier local (copie de ce dépôt avec `dist/`) | clone de la branche |
| `--branch NOM` | branche Git à télécharger | `main` |
| `--channel stable\|dev` | canal de mise à jour, enregistré dans le panel | `stable` |
| `--update` | met à jour une installation existante (détecté automatiquement) : sauvegarde des données, nouveau code, migration de la base, redémarrage | auto |
| `--reinstall` | force une installation complète même si le panel est présent | non |
| `--uninstall` | désinstalle le panel (sites et bases conservés, données du panel archivées) | non |
| `--yes`, `-y` | aucune question (menu et confirmations) | non |
| `--lang xx` | langue de l'installeur et langue initiale du panel : `en`, `fr`, `de`, `es`, `it`, `pt`, `nl`, `ru`, `zh`, `ar` | langue du système, sinon `en` |
| `--en`, `--fr`, `--de`, `--es`, `--it`, `--pt`, `--nl`, `--ru`, `--zh`, `--ar` | raccourcis de `--lang` | |
| `-h`, `--help` | affiche l'aide du script | |

Exemples :

```bash
sudo bash install.sh --stack minimal --port 7443
sudo bash install.sh --mail --postgres
sudo bash install.sh --mail --username moi --password 'Un-Mot-De-Passe-Long' --entrance /mon-acces
sudo bash install.sh --waf toutwaf                 # WAF de l'éditeur devant les sites
sudo bash install.sh --stack minimal --node --master https://maitre.exemple.com:8888   # serveur piloté par un maître
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --yes --random-port
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --channel dev
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --fr   # installeur en français
```

#### Langue de l'installeur

Les installeurs sont **multilingues** : bannière, menu et questions, étapes, avertissements, erreurs, aide, récapitulatif et `install-info.txt` s'affichent dans l'une des **10 langues** ci-dessous, en **anglais par défaut**. La langue retenue devient aussi la **langue initiale du panel** (installation et réinstallation) ; une ligne sous la bannière indique la langue choisie et son origine.

| Langue | `--lang` | Raccourci Linux | Windows |
|---|---|---|---|
| English *(défaut)* | `en` | `--en` | `-Lang en` / `-En` |
| Français | `fr` | `--fr` | `-Lang fr` / `-Fr` |
| Deutsch | `de` | `--de` | `-Lang de` / `-De` |
| Español | `es` | `--es` | `-Lang es` / `-Es` |
| Italiano | `it` | `--it` | `-Lang it` / `-It` |
| Português | `pt` | `--pt` | `-Lang pt` / `-Pt` |
| Nederlands | `nl` | `--nl` | `-Lang nl` / `-Nl` |
| Русский | `ru` | `--ru` | `-Lang ru` / `-Ru` |
| 中文 | `zh` | `--zh` | `-Lang zh` / `-Zh` |
| العربية | `ar` | `--ar` | `-Lang ar` / `-Ar` |

Ordre de priorité, du plus fort au plus faible :

| # | Source | Linux | Windows |
|---|---|---|---|
| 1 | option de la ligne de commande | `--lang xx` ou raccourci (`--fr`…) | `-Lang xx` ou raccourci (`-Fr`…) |
| 2 | variable d'environnement | `TOUTPANEL_LANG=fr` | `$env:TOUTPANEL_LANG = "fr"` |
| 3 | valeur écrite dans le script | `INSTALLER_LANG="fr"` en tête de `install.sh` | `$InstallerLang = "fr"` en tête de `install.ps1` |
| 4 | **détection** de la langue du système, si elle fait partie des 10 | `LC_ALL`, `LC_MESSAGES`, `LANG` | `Get-Culture` |
| 5 | anglais | | |

```bash
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo env TOUTPANEL_LANG=de bash
```

Variables d'environnement reconnues : `TOUTPANEL_LANG` (langue de l'installeur), `TOUTPANEL_HOME` (répertoire), `TOUTPANEL_REPO` (dépôt Git), `TOUTPANEL_BRANCH` (branche), `TOUTPANEL_CHANNEL` (`stable` ou `dev`).

<details>
<summary><b>Paquets installés selon la distribution</b></summary>

- **Debian / Ubuntu** : `nginx`, `php8.x-fpm` (+ cli, mysql, curl, mbstring, xml, zip, gd, intl, bcmath, opcache), `certbot`, `composer`, `mariadb-server`, `redis-server`, `fail2ban`, `python3-venv`, `git`, `unzip` ; PHP multi-versions via packages.sury.org (Debian) ou le PPA ondrej (Ubuntu).
- **AlmaLinux / Rocky / RHEL / Fedora** : `epel-release` (+ CRB), `remi-release`, `nginx`, `php83-php-fpm` (+ extensions), `certbot`, `mariadb-server`, `redis` ou `valkey`, `fail2ban`, `policycoreutils-python-utils`, `dnf-plugins-core` ; contextes SELinux déclarés (`httpd_sys_rw_content_t` sur `/www/wwwroot`, `httpd_log_t`, `cert_t`, `httpd_config_t`, `mail_spool_t`) et booléens `httpd_can_network_connect`, `httpd_can_network_connect_db`, `httpd_can_sendmail`, `httpd_setrlimit` activés.
- **Modules Python facultatifs** (non installés par défaut) : `pymongo` (MongoDB), `wsgidav` (WebDAV), `geoip2` (GeoIP), `python3-saml` (SAML) — `/www/toutpanel/venv/bin/pip install "pymongo>=4.6"` puis `systemctl restart toutpanel`.

</details>

### Windows

Dans PowerShell **en tant qu'administrateur** :

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
iwr -useb https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.ps1 | iex
```

Le script vérifie la version de Windows et les droits, installe **Python 3.12** si aucun Python 3.9+ n'est présent, crée `C:\toutpanel\venv` et y installe le panel, crée le compte admin et l'URL secrète, ajoute les règles de pare-feu (port du panel, 80, 443, 21), crée la tâche planifiée **ToutPanel** (démarrage automatique en SYSTEM) et ajoute `C:\toutpanel\bin` au PATH.

Pour installer aussi la pile web (**Nginx** dans `C:\nginx`, **PHP 8.3** supervisé par le panel, **MariaDB** en service Windows) :

```powershell
iwr -useb https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.ps1 -OutFile install.ps1
.\install.ps1 -Stack
```

| Option | Description |
|---|---|
| `-Port 8888` | port du panel |
| `-Home C:\toutpanel` | répertoire du panel |
| `-Stack` | installe Nginx, PHP 8.3, MariaDB |
| `-Username`, `-Password`, `-Entrance /x` | compte admin et URL secrète choisis |
| `-PythonVersion`, `-NginxVersion`, `-MariaDBVersion`, `-PhpVersion` | versions téléchargées |
| `-Source C:\chemin` / `-Branch main` | dossier local (copie de ce dépôt) / branche téléchargée |
| `-Update` / `-Reinstall` / `-Uninstall` | mettre à jour / tout réinstaller / désinstaller |
| `-Yes` | aucune question (automatisation) |
| `-Lang xx` / `-En`, `-Fr`, `-De`, `-Es`, `-It`, `-Pt`, `-Nl`, `-Ru`, `-Zh`, `-Ar` | langue de l'installeur et langue initiale du panel (défaut : langue du système si prise en charge, sinon anglais ; voir [Langue de l'installeur](#langue-de-linstalleur)) ; avec `iwr … \| iex` : `$env:TOUTPANEL_LANG = "fr"` avant la commande |
| `-Help` | aide du script |

### Ports à ouvrir

| Port | Usage | Ouvert par l'installeur |
|---|---|---|
| **8888** (configurable) | interface du panel | oui |
| **80 / 443** | sites web | oui |
| 21 + 60000-60100 | FTP intégré (mode passif) | 21 seulement ; ouvrez la plage passive si vous activez le FTP |
| 25, 465, 587, 143, 993, 110, 995, 4190 | mail (SMTP, IMAP, POP3, ManageSieve) | avec `--mail` (4190 : à ouvrir pour Sieve à distance) |
| 53 (UDP et TCP) | DNS (BIND) si vous hébergez vos zones | non : Sécurité › Pare-feu |
| 9443 / 7000 | consoles ToutWAF et SafeLine (9443), BunkerWeb (7000) | avec `--waf` |
| 3306 / 5432 | accès distant aux bases (facultatif) | non : seulement si vous l'activez |

N'oubliez pas le **pare-feu de votre hébergeur** (groupe de sécurité) : s'il bloque le port du panel, le navigateur n'affiche rien.

## Premier démarrage

À la fin de l'installation, le script affiche un récapitulatif :

```
╔══════════════════════════════════════════════════════════════════╗
║  ToutPanel est installé !                                        ║
╚══════════════════════════════════════════════════════════════════╝

  URL du panel     : http://203.0.113.10:8888/tp_dchwp7kmkf
  Utilisateur      : admin_gbhjkv
  Mot de passe     : D9nYzTSKHbX8FTqC
  MariaDB root     : k3Jd82nLqP0sYt7wVb1c
  Assistant de configuration : http://203.0.113.10:8888/tp_dchwp7kmkf#/setup?token=npSj7xpVzJOI8weJl8R00AdQ18MHYn8YIJCbOYi43B8
  Ce lien (24 h, une seule utilisation) permet de changer l'adresse du panel, l'utilisateur et le mot de passe générés ci-dessus.
  Nouveau lien : toutpanel setup-link
  PHP              : 8.3 (Nginx + PHP-FPM prêts)

  Ces informations sont enregistrées dans : /www/toutpanel/data/install-info.txt
  L'URL contient l'entrée sécurisée : sans elle, le panel répond 404.
```

1. **Notez l'URL complète** : elle contient l'**entrée sécurisée** (`/tp_…`). Sans elle, le panel répond `404 Not Found`, ce qui le rend invisible aux balayages. `toutpanel info` la réaffiche.
2. **Ouvrez le lien « Assistant de configuration »** (`#/setup?token=…`, valable 24 h, une seule utilisation) : en cinq étapes et sans connexion, remplacez les valeurs générées par les vôtres (nom d'utilisateur, mot de passe, port, entrée sécurisée, nom d'hôte, langue, mode, thème, couleur principale et densité). Lien expiré ? `toutpanel setup-link` en génère un nouveau. L'assistant reste accessible une fois connecté (accueil › Raccourcis rapides).
3. **Sécurisez le compte** : double authentification (TOTP) et, si possible, une clé de sécurité WebAuthn ; IP autorisées si vous avez une IP fixe ; HTTPS du panel (Réglages › Accès & interface, Let's Encrypt si un domaine pointe vers le serveur, sinon `toutpanel ssl on`).
4. **Créez un premier site** : Sites web › Nouveau site (ou bouton **Assistant** pour site + base + certificat + boîtes mail), pointez le DNS vers le serveur, puis cadenas › Let's Encrypt et « Forcer HTTPS ».
5. **Activez les protections** : WAF › Appliquer (ou WAF › Moteur › Installer ToutWAF en édition Professionnelle), règles du pare-feu, sauvegarde quotidienne planifiée, alertes (Réglages › Alertes).

## Mise à jour

Toutes les méthodes conservent comptes, réglages, sites, bases et logiciels.

- **Depuis le panel** : **Mises à jour › Panel** affiche la version installée, le canal suivi, les versions disponibles et les notes de version. **Mettre à jour** sauvegarde d'abord `settings.json`, la base du panel et la version courante (`<home>/data/updates/<date>/`), installe la roue de la nouvelle version, migre la base et redémarre ; le panel vérifie ensuite sa santé et **revient seul à la version précédente** en cas d'échec. **Revenir à la version précédente** reste disponible à tout moment.
- **En ligne de commande** :

  ```bash
  toutpanel update --check              # version installée, version disponible, notes de version
  toutpanel update                      # installer la version du canal suivi
  toutpanel update --channel dev        # suivre la branche de développement
  toutpanel update --rollback           # revenir à la version précédente (--restore-data : données aussi)
  ```

- **Avec le script d'installation** : relancé sur un serveur déjà équipé, `install.sh` passe en mode mise à jour (sauvegarde de `data/` dans `<home>/backup/panel-update-<date>/`, nouvelle roue, `toutpanel migrate`, redémarrage). La pile n'est pas réinstallée sauf si vous ajoutez `--stack`, `--mail` ou `--waf`. Sous Windows : `.\install.ps1 -Update`.

## Désinstallation

```bash
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --uninstall
```

Supprime le service, `/www/toutpanel` (panel, environnement Python, journaux, certificats), `/usr/local/bin/toutpanel` et les configurations Nginx / Apache générées par le panel. Les données du panel sont d'abord archivées dans `/root/toutpanel-backup-<date>.tar.gz`. **Les sites (`/www/wwwroot`), les bases de données et les logiciels de la pile restent en place.** Ajoutez `--yes` pour ne pas confirmer.

Sous Windows : `.\install.ps1 -Uninstall` (données archivées dans `C:\toutpanel-backup-<date>.zip`, sites déplacés dans `C:\toutpanel-wwwroot-<date>`, Nginx, PHP et MariaDB conservés).

## Installation manuelle depuis une roue

Pour les environnements particuliers, sans le script. Choisissez la roue qui correspond à votre interpréteur (`cp311` pour Python 3.11, etc.) :

```bash
git clone --depth 1 https://github.com/qu3ntin01/toutpanel.git /www/toutpanel/src
python3 -m venv /www/toutpanel/venv
. /www/toutpanel/venv/bin/activate          # Windows : venv\Scripts\activate
TAG=$(python -c 'import sys;print(f"cp{sys.version_info[0]}{sys.version_info[1]}")')
(cd /www/toutpanel/src/dist && sha256sum -c --ignore-missing SHA256SUMS)
pip install /www/toutpanel/src/dist/toutpanel-*-$TAG-none-any.whl
# soit, pour Python 3.12 : pip install dist/toutpanel-0.3.1-cp312-none-any.whl
export TOUTPANEL_HOME=/www/toutpanel         # Windows : $env:TOUTPANEL_HOME="C:\toutpanel"
toutpanel setup --username admin --password 'MonMotDePasse' --entrance /mon-acces
toutpanel run
```

Garder le clone dans `<home>/src` permet ensuite `toutpanel update` (canaux et retour arrière). `toutpanel service install` crée le service systemd (ou la tâche planifiée Windows).

## Dépannage

| Symptôme | Solution |
|---|---|
| `404 Not Found` à l'ouverture du panel | l'URL ne contient pas l'entrée sécurisée : `toutpanel info` affiche l'URL complète ; `toutpanel entrance /nouveau-chemin` la change |
| le navigateur n'affiche rien sur le port du panel | pare-feu de l'hébergeur fermé, ou port modifié : ouvrez le port, vérifiez-le avec `toutpanel info` ; `toutpanel port N` pour le changer |
| mot de passe perdu ou 2FA inaccessible | `toutpanel passwd` (nouveau mot de passe généré) ou `toutpanel passwd 'Nouveau' --disable-2fa` |
| le panel ne démarre pas | `systemctl status toutpanel`, `journalctl -u toutpanel -n 50` et `<home>/logs/panel.log` ; `toutpanel check` pour le diagnostic de la machine |
| `Le panel ne répond pas sur le port … après 30 s.` | démarrage lent ou en échec : mêmes journaux, puis `systemctl restart toutpanel` |
| `[ToutPanel] Échec à la ligne N (code C) : …` | une commande de l'installeur a échoué (dépôt, paquet, service) : corrigez la cause et relancez avec `--update` |
| `Python 3.9+ requis.` ou aucune roue pour ce Python | installez `python3.11` ou `python3.12` (paquet de la distribution), puis relancez |
| site ou PHP refusé sous Alma / Rocky / RHEL / Fedora | SELinux : `toutpanel selinux` redéclare les contextes (après un changement de répertoire notamment) |
| Windows : « Lancez PowerShell en tant qu'administrateur. » | clic droit › Exécuter en tant qu'administrateur ; `Set-ExecutionPolicy Bypass -Scope Process -Force` avant le script |

### Commandes utiles

```
toutpanel info                      URL complète, utilisateur, mot de passe initial
toutpanel check                     diagnostic : OS, Python, droits, systemd, SELinux, pare-feu, serveur web, PHP, MariaDB, port
toutpanel setup-link                nouveau lien vers l'assistant de configuration (24 h, usage unique)
toutpanel passwd [MDP] [--disable-2fa]
toutpanel username NOM              renommer l'administrateur
toutpanel port N                    changer le port (redémarrage nécessaire)
toutpanel entrance [/chemin]        définir ou désactiver l'entrée sécurisée
toutpanel ssl on|off                HTTPS du panel (certificat auto-signé)
toutpanel start|stop|restart|status
toutpanel service install|uninstall
toutpanel selinux | apparmor        contextes SELinux / profils AppArmor
toutpanel php install|remove VERSION [--extensions a,b]
toutpanel waf status|install|remove|sync [toutwaf|bunkerweb|safeline]
toutpanel waf update|links|doctor toutwaf   mise à jour, liens de la console, diagnostic de ToutWAF
toutpanel update [--check] [--channel stable|dev|custom] [--rollback]
toutpanel node enroll [--master URL] | status
toutpanel licence status|activate CLÉ|deactivate|refresh
toutpanel site|account|db|mail|dns|backup|cron|ftp|task …   commandes métier (--json)
```

Référence complète : [Ligne de commande](https://toutpanel.com/docs/reference/cli/) · [API REST](https://toutpanel.com/docs/reference/api/) · [Codes d'erreur](https://toutpanel.com/docs/reference/codes-erreur/).

## Canaux

| Canal | Contenu | Installation | Ensuite |
|---|---|---|---|
| **stable** (défaut) | dernière version publiée, étiquette `vX.Y.Z` sur la branche [`main`](https://github.com/qu3ntin01/toutpanel/tree/main) | `install.sh` | Mises à jour › Panel ou `toutpanel update` |
| **dev** | branche [`dev`](https://github.com/qu3ntin01/toutpanel/tree/dev) : nouveautés non encore publiées, non garanties | `install.sh --channel dev` | `toutpanel update --channel stable` pour revenir |
| **personnalisé** | dépôt, branche ou étiquette de votre choix | `TOUTPANEL_REPO=… install.sh --branch …` | `toutpanel update --channel custom --repo URL --branch NOM` |

## Limites connues

Pour être transparent sur ce qui est moins couvert :

- **Windows** est moins éprouvé que Linux : pas de serveur mail, pas de `chmod` dans le gestionnaire de fichiers, PHP exécuté en `php-cgi` par le panel, pas d'isolation par utilisateur système ni de limites cgroups, IIS pris en charge de façon basique (préférez Nginx), terminal simplifié sans le module `pywinpty`.
- **Distributions** : l'installation complète a été validée de bout en bout sur AlmaLinux 9 et 10, et la suite de tests sur Fedora (Python 3.14) ; les autres distributions prises en charge sont gérées par l'installeur mais moins éprouvées. Arch, Alpine et openSUSE font tourner le panel avec une pile réduite, **sans avoir été testées**.
- **ARM64** : le panel compilé est portable et ses dépendances existent pour ARM64, mais aucune installation complète n'a encore été validée sur cette architecture.
- **WAF intégré** : il s'appuie sur les directives natives de Nginx / Apache et **n'analyse pas le corps des requêtes POST** ; pour une inspection complète, ajoutez ToutWAF (recommandé), ModSecurity + OWASP CRS, BunkerWeb ou SafeLine (édition Professionnelle).
- **Multi-serveurs** : la suspension d'un compte sur le maître n'est pas encore répercutée sur ses comptes miroirs des nœuds ; le WAF externe et les statistiques se configurent sur chaque nœud.
- **Modules facultatifs** : MongoDB, WebDAV, GeoIP et SAML demandent l'installation d'un module Python supplémentaire (voir [Installation complète](#installation-complète)) ; BorgBackup est installable mais n'est pas piloté par le panel.
- **Mail** : un serveur mail fiable suppose une IP publique fixe, un DNS inverse correct et des ports 25 / 465 / 587 non bloqués par l'hébergeur.

## Versions et téléchargements

**Version 0.3.1** (2026-10-03) — page **CMS** (595 CMS et applications, version au choix, installations centralisées), **ToutWAF** dans WAF › Moteur, installeurs en **10 langues**, thème **Horizon** par défaut (13 thèmes), couleur et densité dans l'assistant de configuration. Notes complètes dans [CHANGELOG.md](CHANGELOG.md), aussi affichées par le panel avant une mise à jour.

| Fichier | Contenu |
|---|---|
| `install.sh`, `install.ps1` | installeurs Linux et Windows |
| `dist/toutpanel-0.3.1-cp3XY-none-any.whl` | le panel, **une roue par version de CPython** : `cp39`, `cp310`, `cp311`, `cp312`, `cp313`, `cp314` (3 à 4,5 Mo chacune, bytecode uniquement, portables Linux / Windows) |
| `dist/manifest.json` | version, date de construction, versions de Python prises en charge, taille et SHA-256 de chaque roue |
| `dist/SHA256SUMS` | sommes de contrôle des roues (vérifiées automatiquement par l'installeur et par `toutpanel update`) |
| `version.json` | version publiée et date, Python minimum, roues disponibles : lu par la page Mises à jour |
| `CHANGELOG.md`, `LICENSE` | notes de version, licence d'utilisation |
| `screenshots/` | captures d'écran de ce README |

Vérifier les roues à la main :

```bash
cd dist && sha256sum -c SHA256SUMS
```

Les versions stables sont étiquetées `vX.Y.Z` sur `main` ; chaque publication est un commit unique.

## Licence

ToutPanel est un **logiciel propriétaire** : voir [LICENSE](LICENSE) (français, puis anglais). L'**édition Personnelle** est concédée gratuitement pour un usage personnel et non commercial, jusqu'à 5 sites par installation, sans clé. Les éditions **Professionnelle** et **Entreprise** sont soumises à une clé de licence et aux conditions publiées sur [toutpanel.com](https://toutpanel.com/tarifs). Les composants tiers utilisés par le panel (FastAPI, Starlette, SQLAlchemy, Uvicorn, httpx, Jinja2…) restent sous leurs propres licences, listées dans `LICENSE`.

---

<div align="center">

**[toutpanel.com](https://toutpanel.com)** · **[Documentation](https://toutpanel.com/docs/)** · **[Tarifs](https://toutpanel.com/tarifs)** · **[English version](README.en.md)**

</div>
