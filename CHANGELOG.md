# Journal des modifications

Toutes les évolutions notables de ToutPanel sont consignées dans ce fichier. Le format s'inspire de
[Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les versions suivent le [versionnage sémantique](https://semver.org/lang/fr/)
(étiquettes Git `vX.Y.Z` sur le dépôt public). Le panel lit ce fichier pour afficher les notes de version
avant une mise à jour (page **Mises à jour → Panel**).

## [Non publié]

### Modifié

- Aucune modification depuis la 0.2.0 pour l'instant.

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
