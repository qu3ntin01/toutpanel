#!/usr/bin/env bash
# ==============================================================================
#  ToutPanel — installation complète sur Linux
#  Pris en charge : Debian 11+, Ubuntu 20.04+, Fedora 39+, AlmaLinux 9/10, Rocky Linux 9/10, RHEL 9/10
#  (fonctionne aussi sur Arch, Alpine, openSUSE avec une pile réduite)
#
#  Usage :
#    curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash
#    sudo bash install.sh [options]
#
#  Options :
#    --port 8888          port du panel (défaut : 8888 ; --random-port pour un port aléatoire)
#    --home /www/toutpanel  répertoire du panel
#    --stack full|minimal|none
#         full    (défaut) Nginx + PHP-FPM + MariaDB + Redis + Certbot + outils
#         minimal Nginx + PHP-FPM + Certbot
#         none    uniquement le panel
#    --mail               installe aussi Postfix + Dovecot + OpenDKIM
#    --waf bunkerweb|safeline   déploie un WAF externe (Docker) devant les sites, configuré automatiquement
#    --username NAME      nom du compte admin (défaut : aléatoire)
#    --password PASS      mot de passe admin (défaut : aléatoire)
#    --entrance /chemin   entrée sécurisée (défaut : aléatoire)
#    --source DIR         installer depuis des sources locales
#    --branch NAME        branche git à télécharger (défaut : main)
#    --update             met à jour une installation existante (détecté automatiquement si <home>/data existe) :
#                         sauvegarde des données, nouveau code, migration de la base, redémarrage ; comptes,
#                         réglages, sites et logiciels conservés. Ajoutez --stack / --mail / --waf pour compléter la pile.
#    --reinstall          force une installation complète même si le panel est déjà présent
#    --uninstall          désinstalle le panel (service, fichiers du panel, configurations générées) ; les sites
#                         (/www/wwwroot) et les bases de données sont conservés, les données du panel archivées
#    --yes, -y            ne pose aucune question (menu et confirmations) : pour les installations automatisées
#
#  Lancé dans un terminal sans option, le script affiche un menu : installer, mettre à jour ou désinstaller.
# ==============================================================================
set -euo pipefail
trap 'rc=$?; printf "\n\033[1;31m[ToutPanel] Échec à la ligne %s (code %s) : %s\033[0m\nRelancez le script après correction ; ajoutez --update s'"'"'il a déjà installé une partie du panel.\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2' ERR

PORT=8888
RANDOM_PORT=0
HOME_DIR="${TOUTPANEL_HOME:-/www/toutpanel}"
STACK="full"
STACK_SET=0
UPDATE=0
REINSTALL=0
UNINSTALL=0
YES=0
MAIL=0
WAF=""
ADMIN_USER=""
ADMIN_PASS=""
ENTRANCE=""
SRC=""
# Dépôt public des versions ; TOUTPANEL_REPO permet d'installer depuis un autre dépôt (développement, fork).
REPO="${TOUTPANEL_REPO:-https://github.com/qu3ntin01/toutpanel.git}"
BRANCH="${TOUTPANEL_BRANCH:-main}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --random-port) RANDOM_PORT=1; shift;;
    --home) HOME_DIR="$2"; shift 2;;
    --stack) STACK="$2"; STACK_SET=1; shift 2;;
    --update) UPDATE=1; shift;;
    --reinstall) REINSTALL=1; shift;;
    --uninstall) UNINSTALL=1; shift;;
    --yes|-y) YES=1; shift;;
    --mail) MAIL=1; shift;;
    --waf) WAF="$2"; shift 2;;
    --username) ADMIN_USER="$2"; shift 2;;
    --password) ADMIN_PASS="$2"; shift 2;;
    --entrance) ENTRANCE="$2"; shift 2;;
    --source) SRC="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    -h|--help) awk 'NR>1 && /^# =+$/ {n++; if (n==2) exit} NR>2 {print}' "$0"; exit 0;;
    *) echo "Option inconnue : $1"; exit 1;;
  esac
done

if [[ $EUID -ne 0 ]]; then echo "Ce script doit être lancé en root (sudo)."; exit 1; fi

log()  { printf '\033[1;32m[ToutPanel]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ToutPanel]\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
# Chaîne aléatoire alphanumérique. Sans « tr </dev/urandom | head » : head ferme le tube avant tr, qui meurt en
# SIGPIPE (code 141) et, avec pipefail + set -e, le script s'arrêtait net sans message.
rand() {
  local n="${1:-16}" out=""
  out=$(python3 -c 'import secrets,string,sys;a=string.ascii_letters+string.digits;print("".join(secrets.choice(a) for _ in range(int(sys.argv[1]))))' "$n" 2>/dev/null) || out=""
  if [[ ${#out} -ne $n ]]; then
    out=$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9'); out="${out:0:$n}"
  fi
  printf '%s' "$out"
}

if [[ $RANDOM_PORT -eq 1 ]]; then PORT=$(( (RANDOM % 20000) + 20000 )); fi

# ------------------------------------------------------------------------------
# Présentation, état de l'installation et menu
# ------------------------------------------------------------------------------
C0='\033[0m'; CB='\033[1;34m'; CC='\033[1;36m'; CG='\033[1;32m'; CY='\033[1;33m'; CD='\033[2m'; CW='\033[1m'
banner() {
  printf '\n'
  printf "${CB}  ████████╗ ██████╗ ██╗   ██╗████████╗██████╗  █████╗ ███╗   ██╗███████╗██╗     ${C0}\n"
  printf "${CB}  ╚══██╔══╝██╔═══██╗██║   ██║╚══██╔══╝██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     ${C0}\n"
  printf "${CB}     ██║   ██║   ██║██║   ██║   ██║   ██████╔╝███████║██╔██╗ ██║█████╗  ██║     ${C0}\n"
  printf "${CC}     ██║   ██║   ██║██║   ██║   ██║   ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     ${C0}\n"
  printf "${CC}     ██║   ╚██████╔╝╚██████╔╝   ██║   ██║     ██║  ██║██║ ╚████║███████╗███████╗${C0}\n"
  printf "${CC}     ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝${C0}\n"
  printf "${CW}  Panel d'hébergement web open source · Linux & Windows · licence MIT${C0}\n"
  printf "${CD}  https://toutpanel.com · https://github.com/qu3ntin01/toutpanel${C0}\n\n"
}
intro() {
  printf "${CW}  À quoi sert ToutPanel ?${C0}\n"
  printf "  Gérer un serveur web complet depuis le navigateur, sans ligne de commande :\n"
  printf "   ${CG}•${C0} sites Nginx / Apache, PHP 5.6 → 8.4 côte à côte, WordPress en un clic\n"
  printf "   ${CG}•${C0} bases MariaDB / PostgreSQL, FTP, serveur mail et webmail, DNS\n"
  printf "   ${CG}•${C0} SSL Let's Encrypt automatique, pare-feu applicatif (WAF), sauvegardes, Docker\n"
  printf "   ${CG}•${C0} déploiement Git, répartition de charge, alertes, terminal et fichiers\n"
  printf "  Ce script installe la pile complète (Nginx, PHP, MariaDB, certbot…) puis le panel,\n"
  printf "  crée le compte administrateur et affiche l'adresse d'accès à la fin.\n\n"
}
EXISTING=0; EXISTING_VERSION=""
if [[ -f "$HOME_DIR/data/settings.json" ]]; then
  EXISTING=1
  EXISTING_VERSION=$("$HOME_DIR/venv/bin/toutpanel" --version 2>/dev/null || true)
fi
banner
if [[ $EXISTING -eq 1 ]]; then
  printf "  ${CG}●${C0} Installation existante détectée dans ${CW}%s${C0} (version %s)\n\n" "$HOME_DIR" "${EXISTING_VERSION:-inconnue}"
else
  printf "  ${CY}○${C0} Aucune installation dans ${CW}%s${C0} : première installation\n\n" "$HOME_DIR"
fi

# Menu interactif : seulement dans un terminal, sans option de mode ni --yes (curl | bash lit le clavier via /dev/tty).
if [[ $YES -eq 0 && $UPDATE -eq 0 && $REINSTALL -eq 0 && $UNINSTALL -eq 0 ]] && [[ -r /dev/tty && -w /dev/tty ]] && exec 3</dev/tty 2>/dev/null; then
  intro
  printf "${CW}  Que voulez-vous faire ?${C0}\n"
  if [[ $EXISTING -eq 1 ]]; then
    printf "   ${CC}1${C0}) Mettre à jour ToutPanel          ${CD}(comptes, réglages, sites et logiciels conservés)${C0}\n"
    printf "   ${CC}2${C0}) Réinstaller complètement          ${CD}(repart de zéro dans %s)${C0}\n" "$HOME_DIR"
    printf "   ${CC}3${C0}) Désinstaller ToutPanel            ${CD}(les sites et bases de données restent en place)${C0}\n"
    printf "   ${CC}4${C0}) Quitter\n"
    DEFAULT_CHOICE=1
  else
    printf "   ${CC}1${C0}) Installer ToutPanel               ${CD}(pile complète : Nginx, PHP, MariaDB, certbot…)${C0}\n"
    printf "   ${CC}2${C0}) Installer le panel seul           ${CD}(sans pile : vous gérez Nginx / PHP / MariaDB)${C0}\n"
    printf "   ${CC}3${C0}) Quitter\n"
    DEFAULT_CHOICE=1
  fi
  printf "  Votre choix [%s] : " "$DEFAULT_CHOICE"
  read -r CHOICE <&3 || CHOICE=""
  exec 3<&-
  CHOICE="${CHOICE:-$DEFAULT_CHOICE}"
  echo
  if [[ $EXISTING -eq 1 ]]; then
    case "$CHOICE" in
      1) UPDATE=1;;
      2) REINSTALL=1;;
      3) UNINSTALL=1;;
      *) echo "  À bientôt."; exit 0;;
    esac
  else
    case "$CHOICE" in
      1) ;;
      2) STACK="none"; STACK_SET=1;;
      *) echo "  À bientôt."; exit 0;;
    esac
  fi
fi

# ------------------------------------------------------------------------------
# Désinstallation
# ------------------------------------------------------------------------------
if [[ $UNINSTALL -eq 1 ]]; then
  step "Désinstallation de ToutPanel"
  if [[ $EXISTING -eq 0 && ! -d "$HOME_DIR" ]]; then echo "  Rien à désinstaller dans $HOME_DIR."; exit 0; fi
  echo "  Seront supprimés : le service, $HOME_DIR (panel, environnement Python, journaux, certificats),"
  echo "  /usr/local/bin/toutpanel et les configurations Nginx / Apache générées par le panel (toutpanel_*)."
  echo "  Seront conservés : les sites dans /www/wwwroot, les bases de données, PHP, Nginx, MariaDB et les"
  echo "  autres logiciels installés. Les données du panel sont archivées avant suppression."
  if [[ $YES -eq 0 ]]; then
    if [[ -r /dev/tty ]]; then
      printf "\n  Confirmez en tapant ${CW}oui${C0} : "; read -r CONFIRM </dev/tty || CONFIRM=""
    else
      echo "  Pas de terminal : relancez avec --uninstall --yes pour confirmer."; exit 1
    fi
    [[ "$CONFIRM" == "oui" ]] || { echo "  Désinstallation annulée."; exit 0; }
  fi
  ARCHIVE="/root/toutpanel-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
  if [[ -d "$HOME_DIR/data" ]]; then
    tar -czf "$ARCHIVE" -C "$HOME_DIR" data $( [[ -d "$HOME_DIR/ssl" ]] && echo ssl ) $( [[ -d "$HOME_DIR/vhost" ]] && echo vhost ) $( [[ -d "$HOME_DIR/templates" ]] && echo templates ) 2>/dev/null && chmod 600 "$ARCHIVE" && log "Données archivées dans $ARCHIVE"
  fi
  systemctl disable --now toutpanel >/dev/null 2>&1 || true
  [[ -f "$HOME_DIR/data/panel.pid" ]] && kill "$(cat "$HOME_DIR/data/panel.pid")" 2>/dev/null || true
  rm -f /etc/systemd/system/toutpanel.service /etc/logrotate.d/toutpanel
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -f /etc/nginx/conf.d/toutpanel_*.conf /etc/apache2/sites-enabled/toutpanel_*.conf /etc/apache2/sites-available/toutpanel_*.conf /etc/httpd/conf.d/toutpanel_*.conf
  (nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1) || true
  (command -v apachectl >/dev/null && apachectl -t >/dev/null 2>&1 && apachectl graceful >/dev/null 2>&1) || true
  rm -f /usr/local/bin/toutpanel
  rm -rf "$HOME_DIR"
  echo
  printf "${CG}  ToutPanel est désinstallé.${C0}\n"
  [[ -f "$ARCHIVE" ]] && echo "  Archive des données du panel : $ARCHIVE (base, réglages, certificats, modèles)."
  echo "  Sites conservés dans /www/wwwroot ; bases de données conservées. Pour réinstaller : relancez ce script."
  echo
  exit 0
fi

# ------------------------------------------------------------------------------
# Installation existante ? → mode mise à jour (données, comptes et réglages conservés)
# ------------------------------------------------------------------------------
if [[ $REINSTALL -eq 0 && -f "$HOME_DIR/data/settings.json" ]]; then UPDATE=1; fi
if [[ $UPDATE -eq 1 ]]; then
  if [[ ! -f "$HOME_DIR/data/settings.json" ]]; then echo "Aucune installation dans $HOME_DIR : lancez sans --update."; exit 1; fi
  log "Installation existante détectée dans $HOME_DIR : mise à jour (comptes, réglages, sites et logiciels conservés)."
  [[ $STACK_SET -eq 0 ]] && STACK="none"     # la pile n'est réinstallée que sur demande explicite (--stack …)
  BK="$HOME_DIR/backup/panel-update-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$BK" && cp -a "$HOME_DIR/data" "$BK/" && chmod -R go-rwx "$BK"
  log "Données sauvegardées dans $BK (settings.json, base SQLite, clés)."
  if [[ -f "$HOME_DIR/data/settings.json" ]]; then
    PORT=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('panel_port', 8888))" "$HOME_DIR/data/settings.json" 2>/dev/null || echo "$PORT")
  fi
fi

# ------------------------------------------------------------------------------
# Détection de la distribution et du gestionnaire de paquets
# ------------------------------------------------------------------------------
FAMILY=""
DISTRO_ID=$(. /etc/os-release 2>/dev/null; echo "${ID:-}")
DISTRO_MAJOR=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-0}" | cut -d. -f1)
if command -v apt-get >/dev/null; then FAMILY="debian"
elif command -v dnf >/dev/null; then FAMILY="rhel"
elif command -v yum >/dev/null; then FAMILY="rhel-yum"
elif command -v pacman >/dev/null; then FAMILY="arch"
elif command -v apk >/dev/null; then FAMILY="alpine"
elif command -v zypper >/dev/null; then FAMILY="suse"
else echo "Gestionnaire de paquets non reconnu."; exit 1; fi

export DEBIAN_FRONTEND=noninteractive
pkg_install() {
  case "$FAMILY" in
    debian)   apt-get install -y -qq "$@";;
    rhel)     dnf install -y --allowerasing "$@";;
    rhel-yum) yum install -y --allowerasing "$@" 2>/dev/null || yum install -y "$@";;
    arch)     pacman -S --noconfirm --needed "$@";;
    alpine)   apk add --no-cache "$@";;
    suse)     zypper --non-interactive install "$@";;
  esac
}
pkg_update() {
  case "$FAMILY" in
    debian) apt-get update -qq;;
    rhel)   dnf makecache -q || true;;
    arch)   pacman -Sy --noconfirm;;
    alpine) apk update;;
    *) true;;
  esac
}
svc_enable() { for s in "$@"; do systemctl enable --now "$s" >/dev/null 2>&1 || service "$s" start >/dev/null 2>&1 || true; done; }

# Dépôts complémentaires de la famille RHEL (EPEL + CRB) ; inutile sur Fedora
rhel_prepare() {
  [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]] || return 0
  [[ "$DISTRO_ID" == "fedora" ]] && return 0
  if ! rpm -q epel-release >/dev/null 2>&1; then
    if [[ "$DISTRO_ID" == "rhel" ]]; then
      dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${DISTRO_MAJOR}.noarch.rpm" >/dev/null 2>&1 || true
      subscription-manager repos --enable "codeready-builder-for-rhel-${DISTRO_MAJOR}-$(arch)-rpms" >/dev/null 2>&1 || true
    else
      dnf install -y epel-release >/dev/null 2>&1 || true
      dnf config-manager --set-enabled crb >/dev/null 2>&1 || dnf config-manager --set-enabled powertools >/dev/null 2>&1 || true
    fi
  fi
}
# Dépôt Remi (PHP multi-versions) sur la famille RHEL
remi_prepare() {
  [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]] || return 0
  rpm -q remi-release >/dev/null 2>&1 && return 0
  if [[ "$DISTRO_ID" == "fedora" ]]; then
    dnf install -y "https://rpms.remirepo.net/fedora/remi-release-${DISTRO_MAJOR}.rpm" >/dev/null 2>&1 || true
  else
    dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-${DISTRO_MAJOR}.rpm" >/dev/null 2>&1 || true
  fi
}

# ------------------------------------------------------------------------------
step "Dépendances de base"
# ------------------------------------------------------------------------------
pkg_update
case "$FAMILY" in
  debian)   pkg_install python3 python3-venv python3-pip git curl ca-certificates unzip tar gnupg lsb-release;;
  rhel|rhel-yum) pkg_install python3 python3-pip git curl unzip tar policycoreutils-python-utils dnf-plugins-core; rhel_prepare;;
  arch)     pkg_install python python-pip git curl unzip tar;;
  alpine)   pkg_install python3 py3-pip git curl unzip tar gcc musl-dev python3-dev libffi-dev openssl-dev;;
  suse)     pkg_install python3 python3-pip git curl unzip tar;;
esac
if [[ "$(python3 -c 'import sys;print(sys.version_info>=(3,9))')" != "True" ]]; then echo "Python 3.9+ requis."; exit 1; fi

# ------------------------------------------------------------------------------
# Pile web
# ------------------------------------------------------------------------------
PHP_VER=""
if [[ "$STACK" != "none" ]]; then
  step "Serveur web Nginx"
  pkg_install nginx
  svc_enable nginx

  step "PHP-FPM"
  case "$FAMILY" in
    debian)
      PHP_VER=$(apt-cache search --names-only '^php[0-9]+\.[0-9]+-fpm$' | sed -E 's/^php([0-9.]+)-fpm.*/\1/' | sort -V | tail -1)
      if [[ -z "$PHP_VER" ]]; then pkg_install php-fpm php-cli php-mysql php-curl php-mbstring php-xml php-zip php-gd php-intl; PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;');
      else pkg_install "php${PHP_VER}-fpm" "php${PHP_VER}-cli" "php${PHP_VER}-mysql" "php${PHP_VER}-curl" "php${PHP_VER}-mbstring" "php${PHP_VER}-xml" "php${PHP_VER}-zip" "php${PHP_VER}-gd" "php${PHP_VER}-intl" "php${PHP_VER}-bcmath" "php${PHP_VER}-opcache"; fi
      svc_enable "php${PHP_VER}-fpm";;
    rhel|rhel-yum)
      # PHP 8.3 via Remi (collection php83, coexiste avec d'autres versions gérées par le panel)
      remi_prepare
      if pkg_install php83-php-fpm php83-php-cli php83-php-common php83-php-mysqlnd php83-php-mbstring php83-php-xml php83-php-gd php83-php-intl php83-php-pecl-zip php83-php-opcache php83-php-bcmath 2>/dev/null; then
        PHP_VER="8.3"
        # le pool Remi n'autorise que l'utilisateur apache sur sa socket : nginx doit y accéder
        sed -i 's/^user = apache/user = nginx/; s/^group = apache/group = nginx/; s/^listen.acl_users = .*/listen.acl_users = apache,nginx/' /etc/opt/remi/php83/php-fpm.d/www.conf
        svc_enable php83-php-fpm
        ln -sf /usr/bin/php83 /usr/local/bin/php 2>/dev/null || true
      else
        warn "Remi indisponible : installation de la version PHP du système."
        pkg_install php-fpm php-cli php-mysqlnd php-mbstring php-xml php-gd php-intl php-zip php-opcache || true
        PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "")
        svc_enable php-fpm
      fi;;
    arch)   pkg_install php php-fpm php-gd php-intl; PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'); svc_enable php-fpm;;
    alpine) pkg_install php83 php83-fpm php83-mysqli php83-pdo_mysql php83-curl php83-mbstring php83-xml php83-zip php83-gd php83-intl php83-opcache php83-session 2>/dev/null || pkg_install php82 php82-fpm; PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo ""); svc_enable "php-fpm${PHP_VER//./}" php-fpm;;
    suse)   pkg_install php8 php8-fpm php8-mysql php8-mbstring php8-gd php8-intl php8-zip; PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'); svc_enable php-fpm;;
  esac
  log "PHP ${PHP_VER:-?} installé."

  step "Certbot (Let's Encrypt) et outils"
  case "$FAMILY" in
    debian) pkg_install certbot composer 2>/dev/null || pkg_install certbot;;
    rhel|rhel-yum) pkg_install certbot composer 2>/dev/null || pkg_install certbot 2>/dev/null || true;;
    *) pkg_install certbot 2>/dev/null || true;;
  esac

  if [[ "$STACK" == "full" ]]; then
    step "MariaDB"
    case "$FAMILY" in
      debian)   pkg_install mariadb-server mariadb-client; svc_enable mariadb;;
      rhel|rhel-yum) pkg_install mariadb-server mariadb; svc_enable mariadb;;
      arch)     pkg_install mariadb; mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql >/dev/null 2>&1 || true; svc_enable mariadb;;
      alpine)   pkg_install mariadb mariadb-client; mysql_install_db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || true; svc_enable mariadb;;
      suse)     pkg_install mariadb mariadb-client; svc_enable mariadb;;
    esac
    step "Redis / Valkey"
    case "$FAMILY" in
      debian) pkg_install redis-server; svc_enable redis-server;;
      rhel|rhel-yum) (pkg_install redis 2>/dev/null && svc_enable redis) || (pkg_install valkey 2>/dev/null && svc_enable valkey) || true;;
      *) pkg_install redis 2>/dev/null && svc_enable redis || true;;
    esac
    step "Sécurité : Fail2ban"
    pkg_install fail2ban 2>/dev/null && svc_enable fail2ban || true
  fi
fi

if [[ $MAIL -eq 1 ]]; then
  step "Serveur mail : Postfix + Dovecot + OpenDKIM"
  if [[ "$FAMILY" == "debian" ]]; then
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string $(hostname -f 2>/dev/null || hostname)" | debconf-set-selections
    pkg_install postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd opendkim opendkim-tools
  elif [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]]; then
    rhel_prepare
    pkg_install postfix dovecot opendkim opendkim-tools
  else
    pkg_install postfix dovecot opendkim opendkim-tools 2>/dev/null || pkg_install postfix dovecot opendkim || true
  fi
  svc_enable postfix dovecot opendkim
fi

# ------------------------------------------------------------------------------
step "Installation du panel dans $HOME_DIR"
# ------------------------------------------------------------------------------
mkdir -p "$HOME_DIR"
if [[ -z "$SRC" && -f "$(dirname "$0")/pyproject.toml" ]]; then SRC="$(cd "$(dirname "$0")" && pwd)"; fi
if [[ -z "$SRC" ]]; then
  if [[ -d "$HOME_DIR/src/.git" ]] && git -C "$HOME_DIR/src" remote get-url origin >/dev/null 2>&1; then
    log "Mise à jour des sources (branche $BRANCH)…"
    if ! (git -C "$HOME_DIR/src" fetch --quiet --depth 1 origin "$BRANCH" && git -C "$HOME_DIR/src" checkout --quiet -B "$BRANCH" FETCH_HEAD && git -C "$HOME_DIR/src" reset --quiet --hard FETCH_HEAD); then
      warn "Dépôt local inutilisable : nouveau clone."
      rm -rf "$HOME_DIR/src"; git clone --quiet --depth 1 -b "$BRANCH" "$REPO" "$HOME_DIR/src"
    fi
  else
    log "Téléchargement des sources (branche $BRANCH)…"
    rm -rf "$HOME_DIR/src"
    git clone --quiet --depth 1 -b "$BRANCH" "$REPO" "$HOME_DIR/src"
  fi
  SRC="$HOME_DIR/src"
fi
if [[ ! -w "$SRC" ]]; then  # source en lecture seule (montage, dépôt partagé) : pip a besoin d'écrire les métadonnées
  rm -rf "$HOME_DIR/src-build"; cp -r "$SRC" "$HOME_DIR/src-build"; SRC="$HOME_DIR/src-build"
fi
rm -rf "$SRC/build" "$SRC"/*.egg-info 2>/dev/null || true   # artefacts de build obsolètes
[[ -x "$HOME_DIR/venv/bin/python" ]] || python3 -m venv "$HOME_DIR/venv"
"$HOME_DIR/venv/bin/pip" install --quiet --upgrade pip wheel setuptools
"$HOME_DIR/venv/bin/pip" install --quiet --upgrade "$SRC"
ln -sf "$HOME_DIR/venv/bin/toutpanel" /usr/local/bin/toutpanel
export TOUTPANEL_HOME="$HOME_DIR"
mkdir -p /www/wwwroot
if [[ $UPDATE -eq 1 ]]; then
  step "Migration de la base et vérification"
  "$HOME_DIR/venv/bin/toutpanel" migrate
fi

# ------------------------------------------------------------------------------
step "Compte administrateur et URL sécurisée"
# ------------------------------------------------------------------------------
if [[ $UPDATE -eq 0 ]]; then
SETUP_ARGS=(--port "$PORT")
[[ -n "$ADMIN_USER" ]] && SETUP_ARGS+=(--username "$ADMIN_USER")
[[ -n "$ADMIN_PASS" ]] && SETUP_ARGS+=(--password "$ADMIN_PASS")
[[ -n "$ENTRANCE" ]]   && SETUP_ARGS+=(--entrance "$ENTRANCE")
SETUP_JSON=$("$HOME_DIR/venv/bin/toutpanel" setup --json "${SETUP_ARGS[@]}")
ADMIN_USER=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['username'])" "$SETUP_JSON")
ADMIN_PASS=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['password'])" "$SETUP_JSON")
ENTRANCE=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['entrance'])" "$SETUP_JSON")
else
  log "Comptes et entrée sécurisée conservés."
  ENTRANCE=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('security_entrance') or '')" "$HOME_DIR/data/settings.json" 2>/dev/null || echo "")
fi

# ------------------------------------------------------------------------------
# MariaDB : mot de passe root et enregistrement dans le panel
# ------------------------------------------------------------------------------
DB_ROOT_PASS=""
if [[ $UPDATE -eq 0 && "$STACK" == "full" ]] && command -v mysql >/dev/null; then
  step "Sécurisation de MariaDB"
  DB_ROOT_PASS=$(rand 20)
  sleep 2
  if mysql -uroot -e "SELECT 1" >/dev/null 2>&1; then
    mysql -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SQL
    "$HOME_DIR/venv/bin/toutpanel" dbroot mysql --host localhost --port 3306 --user root --password "$DB_ROOT_PASS" >/dev/null
    log "Mot de passe root MariaDB défini et enregistré dans le panel."
  else
    warn "Impossible de se connecter à MariaDB en root sans mot de passe : renseignez les identifiants dans Bases de données → Identifiants root."
    DB_ROOT_PASS=""
  fi
fi

# ------------------------------------------------------------------------------
# SELinux (Alma / Rocky / RHEL / Fedora)
# ------------------------------------------------------------------------------
if command -v getenforce >/dev/null && [[ "$(getenforce 2>/dev/null)" != "Disabled" ]]; then
  # Le panel vit hors des chemins standard (/www) : sans étiquette bin_t, systemd refuse d'exécuter ses binaires (203/EXEC).
  semanage fcontext -a -t bin_t "$HOME_DIR/venv/bin(/.*)?" 2>/dev/null || semanage fcontext -m -t bin_t "$HOME_DIR/venv/bin(/.*)?" 2>/dev/null || true
  restorecon -R "$HOME_DIR/venv/bin" >/dev/null 2>&1 || true
fi
if command -v getenforce >/dev/null && [[ "$(getenforce 2>/dev/null)" != "Disabled" && ! -f "$HOME_DIR/data/.selinux-configured" ]]; then
  step "SELinux : contextes et booléens"
  semanage fcontext -a -t httpd_sys_rw_content_t "/www/wwwroot(/.*)?" 2>/dev/null || semanage fcontext -m -t httpd_sys_rw_content_t "/www/wwwroot(/.*)?" 2>/dev/null || true
  semanage fcontext -a -t httpd_log_t "$HOME_DIR/logs/sites(/.*)?" 2>/dev/null || true
  semanage fcontext -a -t cert_t "$HOME_DIR/ssl(/.*)?" 2>/dev/null || true
  semanage fcontext -a -t httpd_config_t "$HOME_DIR/vhost(/.*)?" 2>/dev/null || true
  semanage fcontext -a -t mail_spool_t "/var/vmail(/.*)?" 2>/dev/null || true
  mkdir -p "$HOME_DIR/logs/sites" "$HOME_DIR/ssl" "$HOME_DIR/vhost" /www/wwwroot
  restorecon -R /www/wwwroot "$HOME_DIR" >/dev/null 2>&1 || true
  setsebool -P httpd_can_network_connect 1 httpd_can_network_connect_db 1 httpd_can_sendmail 1 httpd_setrlimit 1 >/dev/null 2>&1 || true
  touch "$HOME_DIR/data/.selinux-configured"
  log "SELinux configuré (nginx/php-fpm peuvent servir /www/wwwroot, journaux et certificats du panel)."
fi

# ------------------------------------------------------------------------------
step "Service systemd"
# ------------------------------------------------------------------------------
if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; then
  cat > /etc/systemd/system/toutpanel.service <<UNIT
[Unit]
Description=ToutPanel - panel d'hébergement web
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Environment=TOUTPANEL_HOME=$HOME_DIR
Environment=PYTHONUNBUFFERED=1
ExecStart=$HOME_DIR/venv/bin/python3 -m toutpanel run
Restart=always
RestartSec=3
TimeoutStopSec=20
LimitNOFILE=65536
User=root
PrivateTmp=true
ProtectHostname=true
ProtectClock=true
ProtectKernelTunables=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
UNIT
  cat > /etc/logrotate.d/toutpanel <<ROTATE
$HOME_DIR/logs/sites/*.log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  sharedscripts
  postrotate
    [ -f /run/nginx.pid ] && kill -USR1 \$(cat /run/nginx.pid) 2>/dev/null || true
    [ -f /var/run/apache2/apache2.pid ] && systemctl reload apache2 2>/dev/null || true
  endscript
}
$HOME_DIR/logs/*.out {
  weekly
  rotate 4
  missingok
  notifempty
  compress
  copytruncate
}
ROTATE
  systemctl daemon-reload
  systemctl enable toutpanel >/dev/null 2>&1
  if [[ $UPDATE -eq 1 ]]; then systemctl restart toutpanel; log "Panel redémarré avec la nouvelle version."; else systemctl start toutpanel; fi
  systemctl restart toutpanel
else
  "$HOME_DIR/venv/bin/toutpanel" restart >/dev/null || "$HOME_DIR/venv/bin/toutpanel" start >/dev/null
fi
# Le service est-il vraiment joignable ? (jusqu'à 30 s : démarrage de Python, migration de la base)
PANEL_UP=0
for _ in $(seq 1 30); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/"; then PANEL_UP=1; break; fi
  sleep 1
done
if [[ $PANEL_UP -eq 1 ]]; then
  log "Service 'toutpanel' démarré et joignable sur le port $PORT."
else
  warn "Le panel ne répond pas sur le port $PORT après 30 s."
  if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; then
    # diagnostics seulement : ces commandes renvoient un code non nul quand le service est en échec
    { systemctl --no-pager -l status toutpanel 2>&1 || true; } | head -12 | sed 's/^/    /' || true
    echo "    --- journal (journalctl -u toutpanel -n 20) :"
    { journalctl -u toutpanel --no-pager -n 20 2>&1 || true; } | sed 's/^/    /' || true
  else
    { tail -n 20 "$HOME_DIR/logs/panel.out" 2>/dev/null || true; } | sed 's/^/    /' || true
  fi
  if command -v getenforce >/dev/null && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
    warn "SELinux est en mode enforcing : vérifiez les refus avec « ausearch -m avc -ts recent »."
  fi
fi

if [[ -n "$WAF" ]]; then
  step "WAF externe : $WAF (Docker)"
  case "$WAF" in bunkerweb|safeline) ;; *) echo "Valeur --waf invalide : bunkerweb ou safeline"; exit 1;; esac
  if ! command -v docker >/dev/null; then
    if [[ "$FAMILY" == "debian" ]]; then pkg_install docker.io docker-compose-v2 || true
    elif [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]]; then
      rhel_prepare
      REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"; grep -qi fedora /etc/os-release && REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"
      curl -fsSL "$REPO_URL" -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
      pkg_install docker-ce docker-ce-cli containerd.io docker-compose-plugin || pkg_install docker docker-compose || true
    else pkg_install docker docker-compose || true; fi
    svc_enable docker; systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
  fi
  "$HOME_DIR/venv/bin/toutpanel" restart >/dev/null 2>&1 || "$HOME_DIR/venv/bin/toutpanel" start >/dev/null 2>&1 || true
  if "$HOME_DIR/venv/bin/toutpanel" waf install "$WAF" --http-port 8080 --https-port 8443 && "$HOME_DIR/venv/bin/toutpanel" restart >/dev/null 2>&1; then
    log "WAF $WAF déployé : console $( [[ "$WAF" == bunkerweb ]] && echo "http://$(hostname -I 2>/dev/null | awk '{print $1}'):7000" || echo "https://$(hostname -I 2>/dev/null | awk '{print $1}'):9443" )"
  else
    warn "Le déploiement du WAF $WAF a échoué : le serveur web reste sur 80/443 (relancez depuis WAF → Moteur)."
  fi
fi

# ------------------------------------------------------------------------------
step "Pare-feu"
# ------------------------------------------------------------------------------
OPEN_PORTS=(22 80 443 "$PORT" 21)
[[ $MAIL -eq 1 ]] && OPEN_PORTS+=(25 465 587 143 993 110 995)
[[ "$WAF" == "bunkerweb" ]] && OPEN_PORTS+=(7000)
[[ "$WAF" == "safeline" ]] && OPEN_PORTS+=(9443)
if command -v ufw >/dev/null; then
  for p in "${OPEN_PORTS[@]}"; do ufw allow "$p"/tcp >/dev/null 2>&1 || true; done
  ufw allow 60000:60100/tcp >/dev/null 2>&1 || true   # ports passifs du serveur FTP intégré
  ufw --force enable >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
  for p in "${OPEN_PORTS[@]}"; do firewall-cmd --permanent --add-port="$p"/tcp >/dev/null 2>&1 || true; done
  firewall-cmd --permanent --add-port=60000-60100/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# Récapitulatif
# ------------------------------------------------------------------------------
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -z "$LOCAL_IP" ]] && LOCAL_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1)
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null | grep -E '^[0-9.]+$' || true)
IP="${PUBLIC_IP:-${LOCAL_IP:-127.0.0.1}}"
URL="http://${IP}:${PORT}${ENTRANCE}"
URL_LOCAL=""
[[ -n "$LOCAL_IP" && "$LOCAL_IP" != "$IP" ]] && URL_LOCAL="http://${LOCAL_IP}:${PORT}${ENTRANCE}"
INFO_FILE="$HOME_DIR/data/install-info.txt"
[[ $UPDATE -eq 1 ]] && INFO_FILE="$HOME_DIR/data/update-info.txt"
{
  echo "ToutPanel — informations d'installation ($(date '+%Y-%m-%d %H:%M'))"
  echo "URL du panel      : $URL"
  [[ -n "$URL_LOCAL" ]] && echo "URL locale        : $URL_LOCAL"
  echo "Utilisateur       : $ADMIN_USER"
  echo "Mot de passe      : $ADMIN_PASS"
  echo "Entrée sécurisée  : $ENTRANCE"
  [[ -n "$DB_ROOT_PASS" ]] && echo "MariaDB root      : $DB_ROOT_PASS"
  [[ -n "$PHP_VER" ]] && echo "PHP               : $PHP_VER"
  echo "Répertoire        : $HOME_DIR"
} > "$INFO_FILE"
chmod 600 "$INFO_FILE"

if [[ $UPDATE -eq 1 ]]; then
  VERSION=$("$HOME_DIR/venv/bin/toutpanel" --version 2>/dev/null || echo "")
  echo
  printf '\033[1;32m╔══════════════════════════════════════════════════════════════════╗\033[0m\n'
  printf '\033[1;32m║  ToutPanel est à jour !                                          ║\033[0m\n'
  printf '\033[1;32m╚══════════════════════════════════════════════════════════════════╝\033[0m\n'
  echo
  if [[ ${PANEL_UP:-1} -eq 0 ]]; then
    printf '\033[1;33m  Attention : le panel ne répond pas encore. Consultez « journalctl -u toutpanel -n 30 » puis « systemctl restart toutpanel ».\033[0m\n'
    echo
  fi
  echo "  Version          : ${VERSION:-inconnue}"
  echo "  URL du panel     : $URL"
  [[ -n "$URL_LOCAL" ]] && echo "  URL locale       : $URL_LOCAL"
  echo "  Comptes, réglages, sites et logiciels conservés ; sauvegarde des données : $BK"
  echo "  Commandes : toutpanel info | status | restart"
  echo
  exit 0
fi
echo
printf '\033[1;32m╔══════════════════════════════════════════════════════════════════╗\033[0m\n'
printf '\033[1;32m║  ToutPanel est installé !                                        ║\033[0m\n'
printf '\033[1;32m╚══════════════════════════════════════════════════════════════════╝\033[0m\n'
echo
if [[ ${PANEL_UP:-1} -eq 0 ]]; then
  printf '\033[1;33m  Attention : le panel ne répond pas encore. Consultez « journalctl -u toutpanel -n 30 » puis « systemctl restart toutpanel ».\033[0m\n'
  echo
fi
echo "  URL du panel     : $URL"
[[ -n "$URL_LOCAL" ]] && echo "  URL locale       : $URL_LOCAL   (depuis votre réseau)"
echo "  Utilisateur      : $ADMIN_USER"
echo "  Mot de passe     : $ADMIN_PASS"
[[ -n "$DB_ROOT_PASS" ]] && echo "  MariaDB root     : $DB_ROOT_PASS"
[[ -n "$PHP_VER" ]]      && echo "  PHP              : $PHP_VER (Nginx + PHP-FPM prêts)"
echo
echo "  Ces informations sont enregistrées dans : $INFO_FILE"
echo "  L'URL contient l'entrée sécurisée : sans elle, le panel répond 404."
echo "  Commandes : toutpanel info | passwd | entrance | port | restart | setup"
echo
