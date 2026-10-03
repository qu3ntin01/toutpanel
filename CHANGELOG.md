# Journal des modifications

Toutes les évolutions notables de ToutPanel sont consignées dans ce fichier. Le format s'inspire de
[Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les versions suivent le [versionnage sémantique](https://semver.org/lang/fr/)
(étiquettes Git `vX.Y.Z` sur le dépôt public). Le panel lit ce fichier pour afficher les notes de version
avant une mise à jour (page **Mises à jour → Panel**).

## [Non publié]

### Modifié

- Canal développeur : première version bêta **0.4.0 bêta 1** (numéro de paquet `0.4.0b1`), construite sur la base de la 0.3.1 ; les
  nouveautés de la prochaine version stable seront listées ici au fil des bêtas.

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
