#!/usr/bin/env bash
# ==============================================================================
#  ToutPanel — installation complète sur Linux (installeur multilingue : en fr de es it pt nl ru zh ar)
#  Distributions : détection depuis /etc/os-release (ID, ID_LIKE, VERSION_ID, codenames), mêmes familles et mêmes niveaux que « toutpanel compat » :
#    complet : Debian 11+, Ubuntu 20.04+ (et dérivés), Fedora 39+, AlmaLinux / Rocky / RHEL / CentOS Stream / Oracle / CloudLinux 8+ ;
#    réduit  : Debian 10, Ubuntu 18.04, RHEL / CentOS 7, Amazon Linux, openSUSE / SLES, Arch, Alpine, Devuan, architectures 32 bits… (avertissement non bloquant) ;
#    refusées : Gentoo, NixOS, Void, Photon, systèmes immuables… (message traduit). Aucun plafond de version.
#  Python 3.9+ requis : sur un système plus ancien, paquet récent de la distribution, sinon Python autonome (uv, SHA-256 vérifié) dans <home>/python.
#
#  Usage :
#    curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash
#    curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --fr
#    sudo bash install.sh [options]          liste des options : sudo bash install.sh --help ; simulation sans rien modifier : --dry-run
#    ... | sudo bash -s -- --version 0.3.1   installer une version publiée précise ; --list-versions : lister les versions publiées
#
#  Répertoire du panel : /var/toutpanel par défaut. Une installation existante dans l'ancien défaut /www/toutpanel (ou ailleurs : unité systemd,
#  lien /usr/local/bin/toutpanel) est détectée et conservée sans déplacement ; --home DIR impose un répertoire. Les sites restent dans /www/wwwroot.
#
#  Pare-feu : --firewall on|off|ask (+ --firewall-engine). on = ToutPanel le gère (« toutpanel firewall enable »), off = pare-feu en amont (aucune
#  commande système, liste des ports à ouvrir), ask / sans option dans un terminal = question ; sans terminal ou avec --yes : « plus tard »
#  (rien n'est touché). Une mise à jour ne modifie JAMAIS le pare-feu existant.
#
#  Pile logicielle : sans option, la pile par défaut (Nginx, PHP-FPM, MariaDB, Redis, Certbot, outils) ; avec --profile / --web / --php / --db / --accel /
#  --ftp / --mail MOTEUR / --dns / --security / --runtime / --tools / --install-mode / --roles / --stack-file / --redis / --no-tuning / --accept-litespeed-license, les options sont
#  transmises telles quelles à « toutpanel stack apply … --yes » une fois le panel démarré (un échec de la pile ne fait jamais échouer l'installation
#  du panel : commande de reprise affichée). --web litespeed[:6.3] (LiteSpeed Enterprise, produit commercial EXPÉRIMENTAL : essai officiel de durée limitée,
#  puis licence payante) exige --accept-litespeed-license (contrat de licence de LiteSpeed Technologies), sinon l'installeur s'arrête avant toute modification.
#  --stack full|minimal|none est conservé (obsolète : full = --profile standard, minimal = --profile node).
#
#  ToutWAF distant (panel relié à un ToutWAF installé sur un AUTRE serveur ; la commande est générée par ToutWAF) :
#    export TOUTPANEL_WAF_TOKEN='tw_…' TOUTPANEL_WAF_URL='https://<IP_WAF>:9443/<chemin_secret>' TOUTPANEL_WAF_PIN='sha256:…'
#    curl -fsSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo -E bash -s -- --yes --waf toutwaf --waf-console "$TOUTPANEL_WAF_URL" --waf-origin-ip <IP_WAF>
#    (le jeton n'est jamais un argument : variable TOUTPANEL_WAF_TOKEN conservée par sudo -E, ou --waf-token-file FICHIER ; voir --help)
#
#  Mot de passe administrateur choisi sans le mettre dans la ligne de commande (historique du shell, « ps ») : variable TOUTPANEL_PASSWORD (sudo -E),
#    --password-file FICHIER (1re ligne, chmod 600) ou --password-stdin (inutilisable avec « curl | bash »). Une seule source à la fois ; l'option l'emporte sur la variable ;
#    sans source : question dans un terminal, sinon mot de passe aléatoire affiché à la fin. --password VALEUR reste accepté (avertissement). Voir --help.
#    export TOUTPANEL_PASSWORD='…'; curl -fsSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo -E bash -s -- --yes
#
#  Langue (affichage de l'installeur et langue initiale du panel), par ordre de priorité :
#    1. option --lang xx ou raccourci --en --fr --de --es --it --pt --nl --ru --zh --ar
#    2. variable d'environnement TOUTPANEL_LANG
#    3. variable INSTALLER_LANG ci-dessous (code langue écrit dans ce fichier)
#    4. langue du système (LC_ALL, LC_MESSAGES, LANG) si c'est l'une des 10 langues
#    5. anglais
#  Les textes viennent de scripts/installer_messages.json : « python3 scripts/installer_i18n.py » régénère le catalogue
#  embarqué plus bas (entre « # BEGIN CATALOG » et « # END CATALOG », ne pas le modifier à la main).
#
#  Le dépôt public (https://github.com/qu3ntin01/toutpanel) ne contient pas de code source : le panel y est publié sous forme
#  de roues Python « bytecode seulement » dans dist/, une par version de CPython (toutpanel-<version>-cp3XY-none-any.whl,
#  Python 3.9 à 3.14). Le script clone le dépôt dans <home>/src (c'est ce qui permet les canaux, les étiquettes et
#  « toutpanel update ») puis installe la roue correspondant au Python du système ; un dépôt contenant pyproject.toml
#  (dépôt de développement) est installé depuis ses sources comme auparavant.
# ==============================================================================
set -euo pipefail

# Mot de passe administrateur : jamais dans la trace d'exécution (bash -x) ni dans l'environnement des processus lancés par l'installeur.
# TOUTPANEL_PASSWORD est copiée dans une variable shell non exportée (PASS_ENV) puis retirée de l'environnement ; la trace est coupée dès que
# l'une des options --password* est donnée ou que la variable est définie (sinon « + ADMIN_PASS=… » afficherait la valeur).
if [[ $- == *x* ]]; then
  { set +x; } 2>/dev/null
  _xt_keep=1
  if [[ -n "${TOUTPANEL_PASSWORD:-}" ]]; then _xt_keep=0; fi
  for _xa in "$@"; do case "$_xa" in --password|--password=*|--password-file|--password-file=*|--password-stdin) _xt_keep=0;; esac; done
  if [[ $_xt_keep -eq 1 ]]; then set -x; fi
fi
PASS_ENV="${TOUTPANEL_PASSWORD:-}"; PASS_ENV_SET=0; if [[ -n "$PASS_ENV" ]]; then PASS_ENV_SET=1; fi
unset TOUTPANEL_PASSWORD TOUTPANEL_SETUP_PASSWORD _xa _xt_keep

# Langue de l'installeur écrite dans ce fichier (ex. INSTALLER_LANG="fr") ; vide = choix automatique (voir plus haut).
INSTALLER_LANG=""
SUPPORTED_LANGS="en fr de es it pt nl ru zh ar"

# ------------------------------------------------------------------------------
# Catalogue de messages (10 langues) et fonction msg CLÉ [arguments…] (format printf, %s)
# ------------------------------------------------------------------------------
declare -A _MSG=()
UI_LANG="en"
# Charge l'anglais puis la langue retenue par-dessus : une clé absente d'une langue retombe sur l'anglais.
_load_catalog() {
  local line l rest k
  _MSG=()
  while IFS= read -r line; do
    case "$line" in "#"*|"") continue;; esac
    l="${line%%|*}"; rest="${line#*|}"; k="${rest%%|*}"
    if [[ "$l" == "$UI_LANG" ]]; then _MSG[$k]="${rest#*|}"
    elif [[ "$l" == "en" && -z "${_MSG[$k]+x}" ]]; then _MSG[$k]="${rest#*|}"; fi
  done <<'TP_CATALOG'
# BEGIN CATALOG (generated by scripts/installer_i18n.py from scripts/installer_messages.json: do not edit)
en|lang_name|English
fr|lang_name|français
de|lang_name|Deutsch
es|lang_name|español
it|lang_name|italiano
pt|lang_name|português
nl|lang_name|Nederlands
ru|lang_name|русский
zh|lang_name|中文
ar|lang_name|العربية
en|lang_line|Language: %s (%s; use %s to change)
fr|lang_line|Langue : %s (%s ; %s pour changer)
de|lang_line|Sprache: %s (%s; ändern mit %s)
es|lang_line|Idioma: %s (%s; use %s para cambiarlo)
it|lang_line|Lingua: %s (%s; usare %s per cambiarla)
pt|lang_line|Idioma: %s (%s; use %s para alterar)
nl|lang_line|Taal: %s (%s; wijzigen met %s)
ru|lang_line|Язык: %s (%s; для смены используйте %s)
zh|lang_line|语言：%s（%s；使用 %s 更改）
ar|lang_line|اللغة: %s (%s؛ استخدم %s للتغيير)
en|lang_src_option|chosen with an option
fr|lang_src_option|choisie par option
de|lang_src_option|per Option gewählt
es|lang_src_option|elegido con una opción
it|lang_src_option|scelta tramite opzione
pt|lang_src_option|escolhido por opção
nl|lang_src_option|gekozen via optie
ru|lang_src_option|задан параметром
zh|lang_src_option|由选项指定
ar|lang_src_option|محددة بخيار
en|lang_src_env|from TOUTPANEL_LANG
fr|lang_src_env|variable TOUTPANEL_LANG
de|lang_src_env|aus TOUTPANEL_LANG
es|lang_src_env|desde TOUTPANEL_LANG
it|lang_src_env|da TOUTPANEL_LANG
pt|lang_src_env|de TOUTPANEL_LANG
nl|lang_src_env|uit TOUTPANEL_LANG
ru|lang_src_env|из TOUTPANEL_LANG
zh|lang_src_env|来自 TOUTPANEL_LANG
ar|lang_src_env|من TOUTPANEL_LANG
en|lang_src_file|set in the installer file
fr|lang_src_file|définie dans le fichier d'installation
de|lang_src_file|in der Installationsdatei festgelegt
es|lang_src_file|definido en el archivo de instalación
it|lang_src_file|impostata nel file di installazione
pt|lang_src_file|definido no ficheiro de instalação
nl|lang_src_file|ingesteld in het installatiebestand
ru|lang_src_file|задан в файле установщика
zh|lang_src_file|在安装脚本中设置
ar|lang_src_file|محددة في ملف التثبيت
en|lang_src_system|detected from the system
fr|lang_src_system|détectée depuis le système
de|lang_src_system|vom System erkannt
es|lang_src_system|detectado en el sistema
it|lang_src_system|rilevata dal sistema
pt|lang_src_system|detetado no sistema
nl|lang_src_system|gedetecteerd uit het systeem
ru|lang_src_system|определён по системе
zh|lang_src_system|根据系统检测
ar|lang_src_system|مكتشفة من النظام
en|lang_src_default|default
fr|lang_src_default|par défaut
de|lang_src_default|Standard
es|lang_src_default|predeterminado
it|lang_src_default|predefinita
pt|lang_src_default|predefinido
nl|lang_src_default|standaard
ru|lang_src_default|по умолчанию
zh|lang_src_default|默认
ar|lang_src_default|افتراضية
en|lang_unknown|Unsupported language "%s": using English (available: %s).
fr|lang_unknown|Langue « %s » non prise en charge : anglais utilisé (disponibles : %s).
de|lang_unknown|Nicht unterstützte Sprache „%s“: Englisch wird verwendet (verfügbar: %s).
es|lang_unknown|Idioma «%s» no admitido: se usa el inglés (disponibles: %s).
it|lang_unknown|Lingua «%s» non supportata: viene usato l'inglese (disponibili: %s).
pt|lang_unknown|Idioma «%s» não suportado: será usado o inglês (disponíveis: %s).
nl|lang_unknown|Taal "%s" wordt niet ondersteund: Engels wordt gebruikt (beschikbaar: %s).
ru|lang_unknown|Язык «%s» не поддерживается: используется английский (доступны: %s).
zh|lang_unknown|不支持语言“%s”：将使用英语（可用：%s）。
ar|lang_unknown|اللغة "%s" غير مدعومة: سيتم استخدام الإنجليزية (المتاحة: %s).
en|err_failed|Failed at line %s (exit code %s): %s
fr|err_failed|Échec à la ligne %s (code %s) : %s
de|err_failed|Fehler in Zeile %s (Code %s): %s
es|err_failed|Error en la línea %s (código %s): %s
it|err_failed|Errore alla riga %s (codice %s): %s
pt|err_failed|Falha na linha %s (código %s): %s
nl|err_failed|Fout op regel %s (code %s): %s
ru|err_failed|Ошибка в строке %s (код %s): %s
zh|err_failed|第 %s 行失败（代码 %s）：%s
ar|err_failed|فشل في السطر %s (الرمز %s): %s
en|err_retry|Run the script again once the problem is fixed; add --update if it already installed part of the panel.
fr|err_retry|Relancez le script après correction ; ajoutez --update s'il a déjà installé une partie du panel.
de|err_retry|Starten Sie das Skript nach der Behebung erneut; fügen Sie --update hinzu, falls bereits ein Teil des Panels installiert wurde.
es|err_retry|Vuelva a ejecutar el script tras corregir el problema; añada --update si ya instaló parte del panel.
it|err_retry|Rilanciare lo script dopo la correzione; aggiungere --update se ha già installato una parte del pannello.
pt|err_retry|Execute novamente o script após a correção; adicione --update se já instalou parte do painel.
nl|err_retry|Start het script opnieuw na de correctie; voeg --update toe als een deel van het paneel al is geïnstalleerd.
ru|err_retry|Запустите скрипт снова после исправления; добавьте --update, если часть панели уже установлена.
zh|err_retry|问题修复后请重新运行脚本；如果已安装部分面板，请添加 --update。
ar|err_retry|أعد تشغيل السكربت بعد الإصلاح؛ أضف --update إذا كان قد ثبّت جزءًا من اللوحة.
en|unknown_option|Unknown option: %s (see --help)
fr|unknown_option|Option inconnue : %s (voir --help)
de|unknown_option|Unbekannte Option: %s (siehe --help)
es|unknown_option|Opción desconocida: %s (véase --help)
it|unknown_option|Opzione sconosciuta: %s (vedere --help)
pt|unknown_option|Opção desconhecida: %s (consulte --help)
nl|unknown_option|Onbekende optie: %s (zie --help)
ru|unknown_option|Неизвестный параметр: %s (см. --help)
zh|unknown_option|未知选项：%s（参见 --help）
ar|unknown_option|خيار غير معروف: %s (راجع --help)
en|bad_channel|Unknown channel: %s (stable or dev)
fr|bad_channel|Canal inconnu : %s (stable ou dev)
de|bad_channel|Unbekannter Kanal: %s (stable oder dev)
es|bad_channel|Canal desconocido: %s (stable o dev)
it|bad_channel|Canale sconosciuto: %s (stable o dev)
pt|bad_channel|Canal desconhecido: %s (stable ou dev)
nl|bad_channel|Onbekend kanaal: %s (stable of dev)
ru|bad_channel|Неизвестный канал: %s (stable или dev)
zh|bad_channel|未知通道：%s（stable 或 dev）
ar|bad_channel|قناة غير معروفة: %s (stable أو dev)
en|bad_waf|Invalid --waf value: %s (toutwaf, bunkerweb, safeline or none)
fr|bad_waf|Valeur --waf invalide : %s (toutwaf, bunkerweb, safeline ou none)
de|bad_waf|Ungültiger Wert für --waf: %s (toutwaf, bunkerweb, safeline oder none)
es|bad_waf|Valor de --waf no válido: %s (toutwaf, bunkerweb, safeline o none)
it|bad_waf|Valore --waf non valido: %s (toutwaf, bunkerweb, safeline o none)
pt|bad_waf|Valor de --waf inválido: %s (toutwaf, bunkerweb, safeline ou none)
nl|bad_waf|Ongeldige waarde voor --waf: %s (toutwaf, bunkerweb, safeline of none)
ru|bad_waf|Недопустимое значение --waf: %s (toutwaf, bunkerweb, safeline или none)
zh|bad_waf|无效的 --waf 值：%s（toutwaf、bunkerweb、safeline 或 none）
ar|bad_waf|قيمة --waf غير صالحة: %s (toutwaf أو bunkerweb أو safeline أو none)
en|need_root|This script must be run as root (sudo).
fr|need_root|Ce script doit être lancé en root (sudo).
de|need_root|Dieses Skript muss als root ausgeführt werden (sudo).
es|need_root|Este script debe ejecutarse como root (sudo).
it|need_root|Questo script deve essere eseguito come root (sudo).
pt|need_root|Este script deve ser executado como root (sudo).
nl|need_root|Dit script moet als root worden uitgevoerd (sudo).
ru|need_root|Этот скрипт нужно запускать от root (sudo).
zh|need_root|此脚本必须以 root 身份运行（sudo）。
ar|need_root|يجب تشغيل هذا السكربت بصلاحيات root (sudo).
en|need_admin|Run PowerShell as administrator.
fr|need_admin|Lancez PowerShell en tant qu'administrateur.
de|need_admin|Starten Sie PowerShell als Administrator.
es|need_admin|Ejecute PowerShell como administrador.
it|need_admin|Avviare PowerShell come amministratore.
pt|need_admin|Execute o PowerShell como administrador.
nl|need_admin|Start PowerShell als administrator.
ru|need_admin|Запустите PowerShell от имени администратора.
zh|need_admin|请以管理员身份运行 PowerShell。
ar|need_admin|شغّل PowerShell بصلاحيات المسؤول.
en|win_build|Windows 10 / Windows Server 2016 (build 14393) or later required (current build: %s).
fr|win_build|Windows 10 / Windows Server 2016 (build 14393) minimum requis (build actuel : %s).
de|win_build|Windows 10 / Windows Server 2016 (Build 14393) oder neuer erforderlich (aktueller Build: %s).
es|win_build|Se requiere Windows 10 / Windows Server 2016 (compilación 14393) o posterior (compilación actual: %s).
it|win_build|È richiesto Windows 10 / Windows Server 2016 (build 14393) o successivo (build attuale: %s).
pt|win_build|É necessário Windows 10 / Windows Server 2016 (build 14393) ou posterior (build atual: %s).
nl|win_build|Windows 10 / Windows Server 2016 (build 14393) of nieuwer vereist (huidige build: %s).
ru|win_build|Требуется Windows 10 / Windows Server 2016 (сборка 14393) или новее (текущая сборка: %s).
zh|win_build|需要 Windows 10 / Windows Server 2016（内部版本 14393）或更高版本（当前版本：%s）。
ar|win_build|يتطلب Windows 10 / Windows Server 2016 (الإصدار 14393) أو أحدث (الإصدار الحالي: %s).
en|usage_title|Usage:
fr|usage_title|Usage :
de|usage_title|Verwendung:
es|usage_title|Uso:
it|usage_title|Utilizzo:
pt|usage_title|Utilização:
nl|usage_title|Gebruik:
ru|usage_title|Использование:
zh|usage_title|用法：
ar|usage_title|الاستخدام:
en|options_title|Options:
fr|options_title|Options :
de|options_title|Optionen:
es|options_title|Opciones:
it|options_title|Opzioni:
pt|options_title|Opções:
nl|options_title|Opties:
ru|options_title|Параметры:
zh|options_title|选项：
ar|options_title|الخيارات:
en|h_port|panel HTTP port (default: 8888)
fr|h_port|port HTTP du panel (défaut : 8888)
de|h_port|HTTP-Port des Panels (Standard: 8888)
es|h_port|puerto HTTP del panel (predeterminado: 8888)
it|h_port|porta HTTP del pannello (predefinita: 8888)
pt|h_port|porta HTTP do painel (predefinição: 8888)
nl|h_port|HTTP-poort van het paneel (standaard: 8888)
ru|h_port|порт HTTP панели (по умолчанию: 8888)
zh|h_port|面板 HTTP 端口（默认：8888）
ar|h_port|منفذ HTTP للوحة (الافتراضي: 8888)
en|h_https_port|panel HTTPS port (default: 8443; node mode: HTTPS only on --port)
fr|h_https_port|port HTTPS du panel (défaut : 8443 ; mode nœud : HTTPS seul sur --port)
de|h_https_port|HTTPS-Port des Panels (Standard: 8443; Node-Modus: nur HTTPS auf --port)
es|h_https_port|puerto HTTPS del panel (predeterminado: 8443; modo nodo: solo HTTPS en --port)
it|h_https_port|porta HTTPS del pannello (predefinita: 8443; modalità nodo: solo HTTPS su --port)
pt|h_https_port|porta HTTPS do painel (predefinição: 8443; modo nó: apenas HTTPS em --port)
nl|h_https_port|HTTPS-poort van het paneel (standaard: 8443; node-modus: alleen HTTPS op --port)
ru|h_https_port|порт HTTPS панели (по умолчанию: 8443; режим узла: только HTTPS на --port)
zh|h_https_port|面板 HTTPS 端口（默认：8443；节点模式：仅在 --port 上提供 HTTPS）
ar|h_https_port|منفذ HTTPS للوحة (الافتراضي: 8443؛ وضع العقدة: HTTPS فقط على --port)
en|h_version|install a specific published version (e.g. 0.3.1 or 0.4.0b1; also TOUTPANEL_VERSION)
fr|h_version|installer une version précise publiée (ex. 0.3.1 ou 0.4.0b1 ; aussi TOUTPANEL_VERSION)
de|h_version|eine bestimmte veröffentlichte Version installieren (z. B. 0.3.1 oder 0.4.0b1; auch TOUTPANEL_VERSION)
es|h_version|instalar una versión publicada concreta (p. ej. 0.3.1 o 0.4.0b1; también TOUTPANEL_VERSION)
it|h_version|installare una versione pubblicata precisa (es. 0.3.1 o 0.4.0b1; anche TOUTPANEL_VERSION)
pt|h_version|instalar uma versão publicada concreta (ex. 0.3.1 ou 0.4.0b1; também TOUTPANEL_VERSION)
nl|h_version|een bepaalde gepubliceerde versie installeren (bijv. 0.3.1 of 0.4.0b1; ook TOUTPANEL_VERSION)
ru|h_version|установить конкретную опубликованную версию (например, 0.3.1 или 0.4.0b1; также TOUTPANEL_VERSION)
zh|h_version|安装指定的已发布版本（如 0.3.1 或 0.4.0b1；也可用 TOUTPANEL_VERSION）
ar|h_version|تثبيت إصدار منشور محدد (مثل 0.3.1 أو 0.4.0b1؛ ويمكن أيضًا TOUTPANEL_VERSION)
en|h_list_versions|list the published versions, then exit
fr|h_list_versions|lister les versions publiées puis quitter
de|h_list_versions|veröffentlichte Versionen auflisten und beenden
es|h_list_versions|listar las versiones publicadas y salir
it|h_list_versions|elencare le versioni pubblicate ed uscire
pt|h_list_versions|listar as versões publicadas e sair
nl|h_list_versions|gepubliceerde versies tonen en afsluiten
ru|h_list_versions|вывести список опубликованных версий и выйти
zh|h_list_versions|列出已发布的版本后退出
ar|h_list_versions|عرض الإصدارات المنشورة ثم الخروج
en|h_random_port|random panel port (20000-39999)
fr|h_random_port|port du panel aléatoire (20000-39999)
de|h_random_port|zufälliger Panel-Port (20000-39999)
es|h_random_port|puerto del panel aleatorio (20000-39999)
it|h_random_port|porta del pannello casuale (20000-39999)
pt|h_random_port|porta do painel aleatória (20000-39999)
nl|h_random_port|willekeurige paneelpoort (20000-39999)
ru|h_random_port|случайный порт панели (20000-39999)
zh|h_random_port|随机面板端口（20000-39999）
ar|h_random_port|منفذ عشوائي للوحة (20000-39999)
en|h_home|panel directory (default: %s)
fr|h_home|répertoire du panel (défaut : %s)
de|h_home|Verzeichnis des Panels (Standard: %s)
es|h_home|directorio del panel (predeterminado: %s)
it|h_home|directory del pannello (predefinita: %s)
pt|h_home|diretório do painel (predefinição: %s)
nl|h_home|map van het paneel (standaard: %s)
ru|h_home|каталог панели (по умолчанию: %s)
zh|h_home|面板目录（默认：%s）
ar|h_home|مجلد اللوحة (الافتراضي: %s)
en|h_stack|software stack installed with the panel:
fr|h_stack|pile logicielle installée avec le panel :
de|h_stack|mit dem Panel installierter Software-Stack:
es|h_stack|pila de software instalada con el panel:
it|h_stack|stack software installato con il pannello:
pt|h_stack|pilha de software instalada com o painel:
nl|h_stack|softwarestack die met het paneel wordt geïnstalleerd:
ru|h_stack|программный стек, устанавливаемый вместе с панелью:
zh|h_stack|随面板安装的软件栈：
ar|h_stack|حزمة البرامج المثبتة مع اللوحة:
en|h_stack_full|(default) Nginx + PHP-FPM + MariaDB + Redis + Certbot + tools
fr|h_stack_full|(défaut) Nginx + PHP-FPM + MariaDB + Redis + Certbot + outils
de|h_stack_full|(Standard) Nginx + PHP-FPM + MariaDB + Redis + Certbot + Werkzeuge
es|h_stack_full|(predeterminado) Nginx + PHP-FPM + MariaDB + Redis + Certbot + herramientas
it|h_stack_full|(predefinito) Nginx + PHP-FPM + MariaDB + Redis + Certbot + strumenti
pt|h_stack_full|(predefinição) Nginx + PHP-FPM + MariaDB + Redis + Certbot + ferramentas
nl|h_stack_full|(standaard) Nginx + PHP-FPM + MariaDB + Redis + Certbot + hulpmiddelen
ru|h_stack_full|(по умолчанию) Nginx + PHP-FPM + MariaDB + Redis + Certbot + утилиты
zh|h_stack_full|（默认）Nginx + PHP-FPM + MariaDB + Redis + Certbot + 工具
ar|h_stack_full|(افتراضي) Nginx + PHP-FPM + MariaDB + Redis + Certbot + أدوات
en|h_stack_none|the panel only
fr|h_stack_none|uniquement le panel
de|h_stack_none|nur das Panel
es|h_stack_none|solo el panel
it|h_stack_none|solo il pannello
pt|h_stack_none|apenas o painel
nl|h_stack_none|alleen het paneel
ru|h_stack_none|только панель
zh|h_stack_none|仅面板
ar|h_stack_none|اللوحة فقط
en|h_mail|also install Postfix + Dovecot + OpenDKIM
fr|h_mail|installe aussi Postfix + Dovecot + OpenDKIM
de|h_mail|installiert zusätzlich Postfix + Dovecot + OpenDKIM
es|h_mail|instala también Postfix + Dovecot + OpenDKIM
it|h_mail|installa anche Postfix + Dovecot + OpenDKIM
pt|h_mail|instala também Postfix + Dovecot + OpenDKIM
nl|h_mail|installeert ook Postfix + Dovecot + OpenDKIM
ru|h_mail|также устанавливает Postfix + Dovecot + OpenDKIM
zh|h_mail|同时安装 Postfix + Dovecot + OpenDKIM
ar|h_mail|يثبت أيضًا Postfix + Dovecot + OpenDKIM
en|h_postgres|also install PostgreSQL (postgres role password generated and saved in the panel)
fr|h_postgres|installe aussi PostgreSQL (mot de passe du rôle postgres généré et enregistré dans le panel)
de|h_postgres|installiert zusätzlich PostgreSQL (Passwort der Rolle postgres wird erzeugt und im Panel gespeichert)
es|h_postgres|instala también PostgreSQL (contraseña del rol postgres generada y guardada en el panel)
it|h_postgres|installa anche PostgreSQL (password del ruolo postgres generata e salvata nel pannello)
pt|h_postgres|instala também PostgreSQL (senha da função postgres gerada e guardada no painel)
nl|h_postgres|installeert ook PostgreSQL (wachtwoord van de rol postgres wordt gegenereerd en in het paneel opgeslagen)
ru|h_postgres|также устанавливает PostgreSQL (пароль роли postgres создаётся и сохраняется в панели)
zh|h_postgres|同时安装 PostgreSQL（自动生成 postgres 角色密码并保存到面板）
ar|h_postgres|يثبت أيضًا PostgreSQL (تُنشأ كلمة مرور الدور postgres وتُحفظ في اللوحة)
en|h_waf|deploy an external WAF in front of the sites, configured automatically:
fr|h_waf|déploie un WAF externe devant les sites, configuré automatiquement :
de|h_waf|stellt eine externe WAF vor den Websites bereit, automatisch konfiguriert:
es|h_waf|despliega un WAF externo delante de los sitios, configurado automáticamente:
it|h_waf|distribuisce un WAF esterno davanti ai siti, configurato automaticamente:
pt|h_waf|implementa um WAF externo à frente dos sites, configurado automaticamente:
nl|h_waf|plaatst een externe WAF vóór de sites, automatisch geconfigureerd:
ru|h_waf|развёртывает внешний WAF перед сайтами с автоматической настройкой:
zh|h_waf|在站点前部署外部 WAF，并自动配置：
ar|h_waf|ينشر جدار حماية تطبيقات (WAF) خارجيًا أمام المواقع مع إعداد تلقائي:
en|h_waf2|toutwaf = the vendor's WAF (official installer, systemd services, console :9443); bunkerweb / safeline = Docker containers
fr|h_waf2|toutwaf = WAF de l'éditeur (installeur officiel, services systemd, console :9443) ; bunkerweb / safeline = conteneurs Docker
de|h_waf2|toutwaf = WAF des Herstellers (offizieller Installer, systemd-Dienste, Konsole :9443); bunkerweb / safeline = Docker-Container
es|h_waf2|toutwaf = WAF del editor (instalador oficial, servicios systemd, consola :9443); bunkerweb / safeline = contenedores Docker
it|h_waf2|toutwaf = WAF dell'editore (installer ufficiale, servizi systemd, console :9443); bunkerweb / safeline = container Docker
pt|h_waf2|toutwaf = WAF do editor (instalador oficial, serviços systemd, consola :9443); bunkerweb / safeline = contentores Docker
nl|h_waf2|toutwaf = WAF van de uitgever (officieel installatieprogramma, systemd-services, console :9443); bunkerweb / safeline = Docker-containers
ru|h_waf2|toutwaf = WAF разработчика (официальный установщик, службы systemd, консоль :9443); bunkerweb / safeline = контейнеры Docker
zh|h_waf2|toutwaf = 发行方的 WAF（官方安装程序、systemd 服务、控制台 :9443）；bunkerweb / safeline = Docker 容器
ar|h_waf2|toutwaf = WAF الناشر (المثبت الرسمي، خدمات systemd، الواجهة :9443)؛ bunkerweb / safeline = حاويات Docker
en|h_node|node mode (multi-server): panel HTTPS enabled, enrolment token created and displayed (enter it on the master panel: System → Servers → Add)
fr|h_node|mode nœud (multi-serveurs) : HTTPS du panel activé, jeton d'enrôlement créé et affiché (à saisir sur le panel maître : Système → Serveurs → Ajouter)
de|h_node|Node-Modus (Multi-Server): HTTPS des Panels aktiviert, Registrierungstoken erstellt und angezeigt (auf dem Master-Panel eingeben: System → Server → Hinzufügen)
es|h_node|modo nodo (multiservidor): HTTPS del panel activado, token de registro creado y mostrado (introdúzcalo en el panel maestro: Sistema → Servidores → Añadir)
it|h_node|modalità nodo (multi-server): HTTPS del pannello attivato, token di registrazione creato e mostrato (da inserire nel pannello master: Sistema → Server → Aggiungi)
pt|h_node|modo nó (multi-servidor): HTTPS do painel ativado, token de registo criado e apresentado (introduza-o no painel principal: Sistema → Servidores → Adicionar)
nl|h_node|node-modus (multi-server): HTTPS van het paneel ingeschakeld, registratietoken aangemaakt en getoond (in te voeren op het hoofdpaneel: Systeem → Servers → Toevoegen)
ru|h_node|режим узла (несколько серверов): включён HTTPS панели, создаётся и выводится токен регистрации (введите его на главной панели: Система → Серверы → Добавить)
zh|h_node|节点模式（多服务器）：启用面板 HTTPS，创建并显示注册令牌（在主面板中输入：系统 → 服务器 → 添加）
ar|h_node|وضع العقدة (خوادم متعددة): تفعيل HTTPS للوحة وإنشاء رمز تسجيل وعرضه (يُدخل في اللوحة الرئيسية: النظام → الخوادم → إضافة)
en|h_master|with --node: URL of the master panel (shown to the accounts managed by the master)
fr|h_master|avec --node : URL du panel maître (affichée aux comptes gérés par le maître)
de|h_master|mit --node: URL des Master-Panels (wird den vom Master verwalteten Konten angezeigt)
es|h_master|con --node: URL del panel maestro (mostrada a las cuentas gestionadas por el maestro)
it|h_master|con --node: URL del pannello master (mostrato agli account gestiti dal master)
pt|h_master|com --node: URL do painel principal (mostrado às contas geridas pelo principal)
nl|h_master|met --node: URL van het hoofdpaneel (getoond aan de accounts die door het hoofdpaneel worden beheerd)
ru|h_master|с --node: URL главной панели (показывается учётным записям, которыми управляет главная панель)
zh|h_master|与 --node 一起使用：主面板的 URL（显示给由主面板管理的账户）
ar|h_master|مع --node: عنوان URL للوحة الرئيسية (يُعرض للحسابات التي تديرها)
en|h_username|admin account name (default: random)
fr|h_username|nom du compte admin (défaut : aléatoire)
de|h_username|Name des Admin-Kontos (Standard: zufällig)
es|h_username|nombre de la cuenta de administrador (predeterminado: aleatorio)
it|h_username|nome dell'account amministratore (predefinito: casuale)
pt|h_username|nome da conta de administrador (predefinição: aleatório)
nl|h_username|naam van het beheerdersaccount (standaard: willekeurig)
ru|h_username|имя учётной записи администратора (по умолчанию: случайное)
zh|h_username|管理员账户名（默认：随机）
ar|h_username|اسم حساب المسؤول (الافتراضي: عشوائي)
en|h_password|admin password (default: random; visible in the process list and the history: prefer the variable, a file or standard input below)
fr|h_password|mot de passe admin (défaut : aléatoire ; visible dans la liste des processus et l'historique : préférez la variable, un fichier ou l'entrée standard ci-dessous)
de|h_password|Admin-Passwort (Standard: zufällig; in der Prozessliste und im Verlauf sichtbar: besser die Variable, eine Datei oder die Standardeingabe unten)
es|h_password|contraseña del administrador (predeterminado: aleatoria; visible en la lista de procesos y en el historial: es preferible la variable, un archivo o la entrada estándar de abajo)
it|h_password|password dell'amministratore (predefinita: casuale; visibile nell'elenco dei processi e nella cronologia: meglio la variabile, un file o lo standard input qui sotto)
pt|h_password|senha do administrador (predefinição: aleatória; visível na lista de processos e no histórico: prefira a variável, um ficheiro ou a entrada padrão abaixo)
nl|h_password|beheerderswachtwoord (standaard: willekeurig; zichtbaar in de proceslijst en de geschiedenis: gebruik liever de variabele, een bestand of de standaardinvoer hieronder)
ru|h_password|пароль администратора (по умолчанию: случайный; виден в списке процессов и истории: лучше использовать переменную, файл или стандартный ввод ниже)
zh|h_password|管理员密码（默认：随机；会出现在进程列表和历史记录中：建议改用下面的环境变量、文件或标准输入）
ar|h_password|كلمة مرور المسؤول (الافتراضي: عشوائية؛ تظهر في قائمة العمليات والسجل: يُفضَّل المتغير أو ملف أو الإدخال القياسي أدناه)
en|h_entrance|secure entrance path (default: random)
fr|h_entrance|entrée sécurisée (défaut : aléatoire)
de|h_entrance|gesicherter Zugang (Standard: zufällig)
es|h_entrance|entrada segura (predeterminado: aleatoria)
it|h_entrance|ingresso sicuro (predefinito: casuale)
pt|h_entrance|entrada segura (predefinição: aleatória)
nl|h_entrance|beveiligde toegang (standaard: willekeurig)
ru|h_entrance|защищённый вход (по умолчанию: случайный)
zh|h_entrance|安全入口（默认：随机）
ar|h_entrance|المدخل الآمن (الافتراضي: عشوائي)
en|h_source|install from a local repository: sources (pyproject.toml, development repository) or prebuilt wheels (dist folder, copy of the public repository)
fr|h_source|installer depuis un dépôt local : sources (pyproject.toml, dépôt de développement) ou roues précompilées (dossier dist, copie du dépôt public)
de|h_source|aus einem lokalen Repository installieren: Quellen (pyproject.toml, Entwicklungs-Repository) oder vorkompilierte Wheels (Ordner dist, Kopie des öffentlichen Repositorys)
es|h_source|instalar desde un repositorio local: fuentes (pyproject.toml, repositorio de desarrollo) o wheels precompilados (carpeta dist, copia del repositorio público)
it|h_source|installare da un repository locale: sorgenti (pyproject.toml, repository di sviluppo) o wheel precompilate (cartella dist, copia del repository pubblico)
pt|h_source|instalar a partir de um repositório local: código-fonte (pyproject.toml, repositório de desenvolvimento) ou wheels pré-compiladas (pasta dist, cópia do repositório público)
nl|h_source|installeren vanuit een lokale repository: broncode (pyproject.toml, ontwikkelrepository) of vooraf gebouwde wheels (map dist, kopie van de publieke repository)
ru|h_source|установка из локального репозитория: исходники (pyproject.toml, репозиторий разработки) или готовые колёса (папка dist, копия публичного репозитория)
zh|h_source|从本地仓库安装：源码（pyproject.toml，开发仓库）或预编译 wheel（dist 文件夹，公共仓库的副本）
ar|h_source|التثبيت من مستودع محلي: الشيفرة المصدرية (pyproject.toml، مستودع التطوير) أو حزم wheel مُجمّعة مسبقًا (مجلد dist، نسخة من المستودع العام)
en|h_branch|git branch to download (default: main)
fr|h_branch|branche git à télécharger (défaut : main)
de|h_branch|herunterzuladender Git-Branch (Standard: main)
es|h_branch|rama git que se descarga (predeterminada: main)
it|h_branch|branch git da scaricare (predefinito: main)
pt|h_branch|ramo git a transferir (predefinição: main)
nl|h_branch|te downloaden git-branch (standaard: main)
ru|h_branch|ветка git для загрузки (по умолчанию: main)
zh|h_branch|要下载的 git 分支（默认：main）
ar|h_branch|فرع git المراد تنزيله (الافتراضي: main)
en|h_channel|update channel: stable (default, branch main / tagged releases) or dev (branch dev, development builds); saved in the panel (Updates → Panel)
fr|h_channel|canal de mise à jour : stable (défaut, branche main / versions étiquetées) ou dev (branche dev, versions de développement) ; enregistré dans le panel (Mises à jour → Panel)
de|h_channel|Update-Kanal: stable (Standard, Branch main / getaggte Versionen) oder dev (Branch dev, Entwicklungsversionen); im Panel gespeichert (Updates → Panel)
es|h_channel|canal de actualización: stable (predeterminado, rama main / versiones etiquetadas) o dev (rama dev, versiones de desarrollo); guardado en el panel (Actualizaciones → Panel)
it|h_channel|canale di aggiornamento: stable (predefinito, branch main / versioni con tag) o dev (branch dev, versioni di sviluppo); salvato nel pannello (Aggiornamenti → Pannello)
pt|h_channel|canal de atualização: stable (predefinição, ramo main / versões etiquetadas) ou dev (ramo dev, versões de desenvolvimento); guardado no painel (Atualizações → Painel)
nl|h_channel|updatekanaal: stable (standaard, branch main / getagde versies) of dev (branch dev, ontwikkelversies); opgeslagen in het paneel (Updates → Paneel)
ru|h_channel|канал обновлений: stable (по умолчанию, ветка main / версии с тегами) или dev (ветка dev, версии для разработки); сохраняется в панели (Обновления → Панель)
zh|h_channel|更新通道：stable（默认，main 分支 / 带标签的版本）或 dev（dev 分支，开发版本）；保存在面板中（更新 → 面板）
ar|h_channel|قناة التحديث: stable (افتراضي، الفرع main / الإصدارات الموسومة) أو dev (الفرع dev، إصدارات التطوير)؛ تُحفظ في اللوحة (التحديثات → لوحة التحكم)
en|h_update|update an existing installation (detected automatically): data backup, new code, database migration, restart; accounts, settings, sites and software kept. Add --stack / --mail / --waf to complete the stack.
fr|h_update|met à jour une installation existante (détectée automatiquement) : sauvegarde des données, nouveau code, migration de la base, redémarrage ; comptes, réglages, sites et logiciels conservés. Ajoutez --stack / --mail / --waf pour compléter la pile.
de|h_update|aktualisiert eine bestehende Installation (automatisch erkannt): Datensicherung, neuer Code, Datenbankmigration, Neustart; Konten, Einstellungen, Websites und Software bleiben erhalten. Mit --stack / --mail / --waf den Stack ergänzen.
es|h_update|actualiza una instalación existente (detectada automáticamente): copia de seguridad de los datos, código nuevo, migración de la base, reinicio; se conservan cuentas, ajustes, sitios y software. Añada --stack / --mail / --waf para completar la pila.
it|h_update|aggiorna un'installazione esistente (rilevata automaticamente): backup dei dati, nuovo codice, migrazione del database, riavvio; account, impostazioni, siti e software conservati. Aggiungere --stack / --mail / --waf per completare lo stack.
pt|h_update|atualiza uma instalação existente (detetada automaticamente): cópia de segurança dos dados, novo código, migração da base de dados, reinício; contas, definições, sites e software mantidos. Adicione --stack / --mail / --waf para completar a pilha.
nl|h_update|werkt een bestaande installatie bij (automatisch gedetecteerd): back-up van de gegevens, nieuwe code, databasemigratie, herstart; accounts, instellingen, sites en software blijven behouden. Voeg --stack / --mail / --waf toe om de stack aan te vullen.
ru|h_update|обновляет существующую установку (определяется автоматически): резервная копия данных, новый код, миграция базы, перезапуск; учётные записи, настройки, сайты и программы сохраняются. Добавьте --stack / --mail / --waf, чтобы дополнить стек.
zh|h_update|更新现有安装（自动检测）：备份数据、更新代码、迁移数据库、重启；保留账户、设置、站点和软件。添加 --stack / --mail / --waf 可补全软件栈。
ar|h_update|يحدّث تثبيتًا موجودًا (يُكتشف تلقائيًا): نسخ احتياطي للبيانات، شيفرة جديدة، ترحيل قاعدة البيانات، إعادة تشغيل؛ مع الاحتفاظ بالحسابات والإعدادات والمواقع والبرامج. أضف --stack / --mail / --waf لإكمال الحزمة.
en|h_update_win|update an existing installation (detected automatically): data backup, new code, database migration, task restart; accounts and settings kept
fr|h_update_win|met à jour une installation existante (détectée automatiquement) : sauvegarde des données, nouveau code, migration de la base, redémarrage de la tâche ; comptes et réglages conservés
de|h_update_win|aktualisiert eine bestehende Installation (automatisch erkannt): Datensicherung, neuer Code, Datenbankmigration, Neustart der Aufgabe; Konten und Einstellungen bleiben erhalten
es|h_update_win|actualiza una instalación existente (detectada automáticamente): copia de seguridad de los datos, código nuevo, migración de la base, reinicio de la tarea; se conservan cuentas y ajustes
it|h_update_win|aggiorna un'installazione esistente (rilevata automaticamente): backup dei dati, nuovo codice, migrazione del database, riavvio dell'attività; account e impostazioni conservati
pt|h_update_win|atualiza uma instalação existente (detetada automaticamente): cópia de segurança dos dados, novo código, migração da base de dados, reinício da tarefa; contas e definições mantidas
nl|h_update_win|werkt een bestaande installatie bij (automatisch gedetecteerd): back-up van de gegevens, nieuwe code, databasemigratie, herstart van de taak; accounts en instellingen blijven behouden
ru|h_update_win|обновляет существующую установку (определяется автоматически): резервная копия данных, новый код, миграция базы, перезапуск задачи; учётные записи и настройки сохраняются
zh|h_update_win|更新现有安装（自动检测）：备份数据、更新代码、迁移数据库、重启计划任务；保留账户和设置
ar|h_update_win|يحدّث تثبيتًا موجودًا (يُكتشف تلقائيًا): نسخ احتياطي للبيانات، شيفرة جديدة، ترحيل قاعدة البيانات، إعادة تشغيل المهمة؛ مع الاحتفاظ بالحسابات والإعدادات
en|h_reinstall|force a full installation even if the panel is already present
fr|h_reinstall|force une installation complète même si le panel est déjà présent
de|h_reinstall|erzwingt eine vollständige Installation, auch wenn das Panel bereits vorhanden ist
es|h_reinstall|fuerza una instalación completa aunque el panel ya esté presente
it|h_reinstall|forza un'installazione completa anche se il pannello è già presente
pt|h_reinstall|força uma instalação completa mesmo que o painel já esteja presente
nl|h_reinstall|dwingt een volledige installatie af, ook als het paneel al aanwezig is
ru|h_reinstall|принудительная полная установка, даже если панель уже установлена
zh|h_reinstall|即使面板已存在也强制完整安装
ar|h_reinstall|يفرض تثبيتًا كاملًا حتى لو كانت اللوحة موجودة
en|h_uninstall|uninstall the panel (service, panel files, generated configurations); sites (/www/wwwroot) and databases are kept, panel data archived
fr|h_uninstall|désinstalle le panel (service, fichiers du panel, configurations générées) ; les sites (/www/wwwroot) et les bases de données sont conservés, les données du panel archivées
de|h_uninstall|deinstalliert das Panel (Dienst, Panel-Dateien, erzeugte Konfigurationen); Websites (/www/wwwroot) und Datenbanken bleiben erhalten, Panel-Daten werden archiviert
es|h_uninstall|desinstala el panel (servicio, archivos del panel, configuraciones generadas); se conservan los sitios (/www/wwwroot) y las bases de datos, los datos del panel se archivan
it|h_uninstall|disinstalla il pannello (servizio, file del pannello, configurazioni generate); siti (/www/wwwroot) e database conservati, dati del pannello archiviati
pt|h_uninstall|desinstala o painel (serviço, ficheiros do painel, configurações geradas); os sites (/www/wwwroot) e as bases de dados são mantidos, os dados do painel arquivados
nl|h_uninstall|verwijdert het paneel (service, paneelbestanden, gegenereerde configuraties); sites (/www/wwwroot) en databases blijven behouden, paneelgegevens worden gearchiveerd
ru|h_uninstall|удаляет панель (служба, файлы панели, созданные конфигурации); сайты (/www/wwwroot) и базы данных сохраняются, данные панели архивируются
zh|h_uninstall|卸载面板（服务、面板文件、生成的配置）；保留站点（/www/wwwroot）和数据库，面板数据会被归档
ar|h_uninstall|يزيل اللوحة (الخدمة، ملفات اللوحة، الإعدادات المُنشأة)؛ مع الاحتفاظ بالمواقع (/www/wwwroot) وقواعد البيانات وأرشفة بيانات اللوحة
en|h_uninstall_win|uninstall the panel (scheduled tasks, panel folder); sites and databases stay in place, panel data archived in a zip
fr|h_uninstall_win|désinstalle le panel (tâches planifiées, dossier du panel) ; les sites et bases de données restent en place, les données du panel sont archivées dans un zip
de|h_uninstall_win|deinstalliert das Panel (geplante Aufgaben, Panel-Ordner); Websites und Datenbanken bleiben erhalten, Panel-Daten werden in einem ZIP archiviert
es|h_uninstall_win|desinstala el panel (tareas programadas, carpeta del panel); los sitios y las bases de datos se mantienen, los datos del panel se archivan en un zip
it|h_uninstall_win|disinstalla il pannello (attività pianificate, cartella del pannello); siti e database restano al loro posto, dati del pannello archiviati in uno zip
pt|h_uninstall_win|desinstala o painel (tarefas agendadas, pasta do painel); os sites e as bases de dados mantêm-se, os dados do painel são arquivados num zip
nl|h_uninstall_win|verwijdert het paneel (geplande taken, paneelmap); sites en databases blijven staan, paneelgegevens worden in een zip gearchiveerd
ru|h_uninstall_win|удаляет панель (запланированные задачи, папка панели); сайты и базы данных остаются на месте, данные панели архивируются в zip
zh|h_uninstall_win|卸载面板（计划任务、面板文件夹）；站点和数据库保持不变，面板数据归档为 zip
ar|h_uninstall_win|يزيل اللوحة (المهام المجدولة، مجلد اللوحة)؛ تبقى المواقع وقواعد البيانات كما هي وتُؤرشف بيانات اللوحة في ملف zip
en|h_yes|ask no questions (menu and confirmations): for automated installations
fr|h_yes|ne pose aucune question (menu et confirmations) : pour les installations automatisées
de|h_yes|stellt keine Fragen (Menü und Bestätigungen): für automatisierte Installationen
es|h_yes|no hace ninguna pregunta (menú y confirmaciones): para instalaciones automatizadas
it|h_yes|non pone domande (menu e conferme): per le installazioni automatizzate
pt|h_yes|não faz perguntas (menu e confirmações): para instalações automatizadas
nl|h_yes|stelt geen vragen (menu en bevestigingen): voor geautomatiseerde installaties
ru|h_yes|не задаёт вопросов (меню и подтверждения): для автоматической установки
zh|h_yes|不提出任何问题（菜单和确认）：用于自动化安装
ar|h_yes|لا يطرح أي سؤال (القائمة والتأكيدات): للتثبيت الآلي
en|h_stack_win|also install Nginx (nginx.org), PHP 8.5 (windows.php.net, managed by the panel) and MariaDB (official MSI, Windows service)
fr|h_stack_win|installe aussi Nginx (nginx.org), PHP 8.5 (windows.php.net, géré par le panel) et MariaDB (MSI officiel, service Windows)
de|h_stack_win|installiert zusätzlich Nginx (nginx.org), PHP 8.5 (windows.php.net, vom Panel verwaltet) und MariaDB (offizielles MSI, Windows-Dienst)
es|h_stack_win|instala también Nginx (nginx.org), PHP 8.5 (windows.php.net, gestionado por el panel) y MariaDB (MSI oficial, servicio de Windows)
it|h_stack_win|installa anche Nginx (nginx.org), PHP 8.5 (windows.php.net, gestito dal pannello) e MariaDB (MSI ufficiale, servizio Windows)
pt|h_stack_win|instala também Nginx (nginx.org), PHP 8.5 (windows.php.net, gerido pelo painel) e MariaDB (MSI oficial, serviço Windows)
nl|h_stack_win|installeert ook Nginx (nginx.org), PHP 8.5 (windows.php.net, beheerd door het paneel) en MariaDB (officiële MSI, Windows-service)
ru|h_stack_win|также устанавливает Nginx (nginx.org), PHP 8.5 (windows.php.net, управляется панелью) и MariaDB (официальный MSI, служба Windows)
zh|h_stack_win|同时安装 Nginx（nginx.org）、PHP 8.5（windows.php.net，由面板管理）和 MariaDB（官方 MSI，Windows 服务）
ar|h_stack_win|يثبت أيضًا Nginx (nginx.org) وPHP 8.5 (windows.php.net، تديره اللوحة) وMariaDB (حزمة MSI الرسمية، خدمة Windows)
en|h_lang|installer language and initial panel language: en fr de es it pt nl ru zh ar
fr|h_lang|langue de l'installeur et langue initiale du panel : en fr de es it pt nl ru zh ar
de|h_lang|Sprache des Installers und anfängliche Panel-Sprache: en fr de es it pt nl ru zh ar
es|h_lang|idioma del instalador e idioma inicial del panel: en fr de es it pt nl ru zh ar
it|h_lang|lingua dell'installer e lingua iniziale del pannello: en fr de es it pt nl ru zh ar
pt|h_lang|idioma do instalador e idioma inicial do painel: en fr de es it pt nl ru zh ar
nl|h_lang|taal van het installatieprogramma en begintaal van het paneel: en fr de es it pt nl ru zh ar
ru|h_lang|язык установщика и начальный язык панели: en fr de es it pt nl ru zh ar
zh|h_lang|安装程序语言及面板初始语言：en fr de es it pt nl ru zh ar
ar|h_lang|لغة المثبت واللغة الأولية للوحة: en fr de es it pt nl ru zh ar
en|h_lang_short|shortcuts for the language option
fr|h_lang_short|raccourcis de l'option de langue
de|h_lang_short|Kurzformen der Sprachoption
es|h_lang_short|atajos de la opción de idioma
it|h_lang_short|scorciatoie dell'opzione della lingua
pt|h_lang_short|atalhos da opção de idioma
nl|h_lang_short|snelkoppelingen voor de taaloptie
ru|h_lang_short|краткие формы параметра языка
zh|h_lang_short|语言选项的快捷方式
ar|h_lang_short|اختصارات خيار اللغة
en|h_help|show this help
fr|h_help|affiche cette aide
de|h_help|zeigt diese Hilfe an
es|h_help|muestra esta ayuda
it|h_help|mostra questo aiuto
pt|h_help|mostra esta ajuda
nl|h_help|toont deze hulp
ru|h_help|показывает эту справку
zh|h_help|显示此帮助
ar|h_help|يعرض هذه المساعدة
en|help_menu|Run in a terminal without any option, the script shows a menu: install, update or uninstall.
fr|help_menu|Lancé dans un terminal sans option, le script affiche un menu : installer, mettre à jour ou désinstaller.
de|help_menu|Ohne Optionen in einem Terminal gestartet, zeigt das Skript ein Menü: installieren, aktualisieren oder deinstallieren.
es|help_menu|Ejecutado en un terminal sin opciones, el script muestra un menú: instalar, actualizar o desinstalar.
it|help_menu|Avviato in un terminale senza opzioni, lo script mostra un menu: installare, aggiornare o disinstallare.
pt|help_menu|Executado num terminal sem opções, o script mostra um menu: instalar, atualizar ou desinstalar.
nl|help_menu|Zonder opties in een terminal gestart, toont het script een menu: installeren, bijwerken of verwijderen.
ru|help_menu|При запуске в терминале без параметров скрипт показывает меню: установить, обновить или удалить.
zh|help_menu|在终端中不带任何选项运行时，脚本会显示菜单：安装、更新或卸载。
ar|help_menu|عند تشغيله في طرفية دون خيارات، يعرض السكربت قائمة: تثبيت أو تحديث أو إزالة.
en|help_lang|Language: option, then the TOUTPANEL_LANG variable, then the system language (%s) if supported, otherwise English.
fr|help_lang|Langue : option, puis variable TOUTPANEL_LANG, puis langue du système (%s) si elle est prise en charge, sinon anglais.
de|help_lang|Sprache: Option, dann die Variable TOUTPANEL_LANG, dann die Systemsprache (%s), falls unterstützt, sonst Englisch.
es|help_lang|Idioma: opción, luego la variable TOUTPANEL_LANG, luego el idioma del sistema (%s) si está admitido; si no, inglés.
it|help_lang|Lingua: opzione, poi la variabile TOUTPANEL_LANG, poi la lingua del sistema (%s) se supportata, altrimenti inglese.
pt|help_lang|Idioma: opção, depois a variável TOUTPANEL_LANG, depois o idioma do sistema (%s) se for suportado; caso contrário, inglês.
nl|help_lang|Taal: optie, dan de variabele TOUTPANEL_LANG, dan de systeemtaal (%s) indien ondersteund, anders Engels.
ru|help_lang|Язык: параметр, затем переменная TOUTPANEL_LANG, затем язык системы (%s), если он поддерживается, иначе английский.
zh|help_lang|语言：先看选项，然后是 TOUTPANEL_LANG 变量，再是系统语言（%s，若受支持），否则使用英语。
ar|help_lang|اللغة: الخيار، ثم المتغير TOUTPANEL_LANG، ثم لغة النظام (%s) إن كانت مدعومة، وإلا فالإنجليزية.
en|help_env|Environment variables: %s
fr|help_env|Variables d'environnement : %s
de|help_env|Umgebungsvariablen: %s
es|help_env|Variables de entorno: %s
it|help_env|Variabili d'ambiente: %s
pt|help_env|Variáveis de ambiente: %s
nl|help_env|Omgevingsvariabelen: %s
ru|help_env|Переменные окружения: %s
zh|help_env|环境变量：%s
ar|help_env|متغيرات البيئة: %s
en|help_wheels|The public repository ships the panel as bytecode-only Python wheels in dist/ (one per CPython version, 3.9 to 3.14); the script installs the wheel that matches the system's Python.
fr|help_wheels|Le dépôt public publie le panel sous forme de roues Python « bytecode seulement » dans dist/ (une par version de CPython, 3.9 à 3.14) ; le script installe la roue correspondant au Python du système.
de|help_wheels|Das öffentliche Repository liefert das Panel als reine Bytecode-Python-Wheels in dist/ (eines pro CPython-Version, 3.9 bis 3.14); das Skript installiert das Wheel, das zum Python des Systems passt.
es|help_wheels|El repositorio público distribuye el panel como wheels de Python solo con bytecode en dist/ (uno por versión de CPython, de 3.9 a 3.14); el script instala el que corresponde al Python del sistema.
it|help_wheels|Il repository pubblico distribuisce il pannello come wheel Python solo bytecode in dist/ (una per versione di CPython, da 3.9 a 3.14); lo script installa quella corrispondente al Python del sistema.
pt|help_wheels|O repositório público disponibiliza o painel como wheels Python apenas com bytecode em dist/ (uma por versão de CPython, 3.9 a 3.14); o script instala a que corresponde ao Python do sistema.
nl|help_wheels|De publieke repository levert het paneel als Python-wheels met alleen bytecode in dist/ (één per CPython-versie, 3.9 tot 3.14); het script installeert de wheel die bij de Python van het systeem past.
ru|help_wheels|Публичный репозиторий распространяет панель в виде колёс Python только с байт-кодом в dist/ (по одному на версию CPython, 3.9–3.14); скрипт устанавливает колесо, соответствующее Python системы.
zh|help_wheels|公共仓库以仅含字节码的 Python wheel 形式在 dist/ 中发布面板（每个 CPython 版本一个，3.9 至 3.14）；脚本会安装与系统 Python 匹配的 wheel。
ar|help_wheels|ينشر المستودع العام اللوحة على شكل حزم wheel لبايثون تحتوي على bytecode فقط في dist/ (واحدة لكل إصدار CPython، من 3.9 إلى 3.14)؛ ويثبت السكربت الحزمة المطابقة لإصدار بايثون في النظام.
en|tagline|Web hosting control panel · Linux & Windows · proprietary licence, free Personal edition
fr|tagline|Panel d'hébergement web · Linux & Windows · licence propriétaire, édition Personnelle gratuite
de|tagline|Webhosting-Panel · Linux & Windows · proprietäre Lizenz, kostenlose Personal-Edition
es|tagline|Panel de alojamiento web · Linux y Windows · licencia propietaria, edición Personal gratuita
it|tagline|Pannello di web hosting · Linux e Windows · licenza proprietaria, edizione Personale gratuita
pt|tagline|Painel de alojamento web · Linux e Windows · licença proprietária, edição Pessoal gratuita
nl|tagline|Webhostingpaneel · Linux & Windows · propriëtaire licentie, gratis Personal-editie
ru|tagline|Панель веб-хостинга · Linux и Windows · проприетарная лицензия, бесплатная редакция Personal
zh|tagline|网站托管面板 · Linux 和 Windows · 专有许可，个人版免费
ar|tagline|لوحة استضافة مواقع الويب · Linux وWindows · ترخيص احتكاري، الإصدار الشخصي مجاني
en|intro_title|What is ToutPanel for?
fr|intro_title|À quoi sert ToutPanel ?
de|intro_title|Wofür ist ToutPanel gedacht?
es|intro_title|¿Para qué sirve ToutPanel?
it|intro_title|A cosa serve ToutPanel?
pt|intro_title|Para que serve o ToutPanel?
nl|intro_title|Waarvoor dient ToutPanel?
ru|intro_title|Для чего нужен ToutPanel?
zh|intro_title|ToutPanel 有什么用？
ar|intro_title|ما فائدة ToutPanel؟
en|intro_lead|Manage a complete web server from your browser, without the command line:
fr|intro_lead|Gérer un serveur web complet depuis le navigateur, sans ligne de commande :
de|intro_lead|Einen kompletten Webserver im Browser verwalten, ohne Kommandozeile:
es|intro_lead|Gestionar un servidor web completo desde el navegador, sin línea de comandos:
it|intro_lead|Gestire un server web completo dal browser, senza riga di comando:
pt|intro_lead|Gerir um servidor web completo a partir do navegador, sem linha de comandos:
nl|intro_lead|Een volledige webserver beheren vanuit de browser, zonder opdrachtregel:
ru|intro_lead|Управление полноценным веб-сервером из браузера, без командной строки:
zh|intro_lead|在浏览器中管理完整的 Web 服务器，无需命令行：
ar|intro_lead|إدارة خادم ويب كامل من المتصفح دون سطر الأوامر:
en|intro_b1|%s sites, PHP 5.6 → 8.5 side by side, one-click WordPress
fr|intro_b1|sites %s, PHP 5.6 → 8.5 côte à côte, WordPress en un clic
de|intro_b1|%s-Websites, PHP 5.6 → 8.5 parallel, WordPress mit einem Klick
es|intro_b1|sitios %s, PHP 5.6 → 8.5 en paralelo, WordPress en un clic
it|intro_b1|siti %s, PHP 5.6 → 8.5 in parallelo, WordPress con un clic
pt|intro_b1|sites %s, PHP 5.6 → 8.5 lado a lado, WordPress num clique
nl|intro_b1|%s-sites, PHP 5.6 → 8.5 naast elkaar, WordPress met één klik
ru|intro_b1|сайты %s, PHP 5.6 → 8.5 параллельно, WordPress в один клик
zh|intro_b1|%s 站点，PHP 5.6 → 8.5 并存，一键安装 WordPress
ar|intro_b1|مواقع %s، وPHP 5.6 → 8.5 جنبًا إلى جنب، وWordPress بنقرة واحدة
en|intro_b2|MariaDB / PostgreSQL databases, FTP, mail server and webmail, DNS
fr|intro_b2|bases MariaDB / PostgreSQL, FTP, serveur mail et webmail, DNS
de|intro_b2|MariaDB-/PostgreSQL-Datenbanken, FTP, Mailserver und Webmail, DNS
es|intro_b2|bases de datos MariaDB / PostgreSQL, FTP, servidor de correo y webmail, DNS
it|intro_b2|database MariaDB / PostgreSQL, FTP, server di posta e webmail, DNS
pt|intro_b2|bases de dados MariaDB / PostgreSQL, FTP, servidor de correio e webmail, DNS
nl|intro_b2|MariaDB-/PostgreSQL-databases, FTP, mailserver en webmail, DNS
ru|intro_b2|базы MariaDB / PostgreSQL, FTP, почтовый сервер и веб-почта, DNS
zh|intro_b2|MariaDB / PostgreSQL 数据库、FTP、邮件服务器与 Webmail、DNS
ar|intro_b2|قواعد بيانات MariaDB / PostgreSQL، وFTP، وخادم بريد وبريد ويب، وDNS
en|intro_b3|automatic Let's Encrypt SSL, web application firewall (WAF), backups, Docker
fr|intro_b3|SSL Let's Encrypt automatique, pare-feu applicatif (WAF), sauvegardes, Docker
de|intro_b3|automatisches Let's-Encrypt-SSL, Web Application Firewall (WAF), Backups, Docker
es|intro_b3|SSL Let's Encrypt automático, cortafuegos de aplicaciones (WAF), copias de seguridad, Docker
it|intro_b3|SSL Let's Encrypt automatico, firewall applicativo (WAF), backup, Docker
pt|intro_b3|SSL Let's Encrypt automático, firewall aplicacional (WAF), cópias de segurança, Docker
nl|intro_b3|automatische Let's Encrypt-SSL, webapplicatiefirewall (WAF), back-ups, Docker
ru|intro_b3|автоматический SSL Let's Encrypt, межсетевой экран приложений (WAF), резервные копии, Docker
zh|intro_b3|自动 Let's Encrypt SSL、Web 应用防火墙（WAF）、备份、Docker
ar|intro_b3|شهادات SSL تلقائية من Let's Encrypt، وجدار حماية التطبيقات (WAF)، ونسخ احتياطي، وDocker
en|intro_b4|Git deployment, load balancing, alerts, terminal and file manager
fr|intro_b4|déploiement Git, répartition de charge, alertes, terminal et fichiers
de|intro_b4|Git-Deployment, Lastverteilung, Warnmeldungen, Terminal und Dateimanager
es|intro_b4|despliegue Git, balanceo de carga, alertas, terminal y gestor de archivos
it|intro_b4|deploy Git, bilanciamento del carico, avvisi, terminale e file manager
pt|intro_b4|implementação Git, balanceamento de carga, alertas, terminal e gestor de ficheiros
nl|intro_b4|Git-deployment, load balancing, waarschuwingen, terminal en bestandsbeheer
ru|intro_b4|развёртывание из Git, балансировка нагрузки, оповещения, терминал и файлы
zh|intro_b4|Git 部署、负载均衡、告警、终端与文件管理
ar|intro_b4|النشر عبر Git، وموازنة الحمل، والتنبيهات، والطرفية، وإدارة الملفات
en|intro_end|This script installs %s then the panel, creates the administrator account and shows the access address at the end.
fr|intro_end|Ce script installe %s puis le panel, crée le compte administrateur et affiche l'adresse d'accès à la fin.
de|intro_end|Dieses Skript installiert %s und danach das Panel, legt das Administratorkonto an und zeigt am Ende die Zugangsadresse an.
es|intro_end|Este script instala %s y luego el panel, crea la cuenta de administrador y muestra la dirección de acceso al final.
it|intro_end|Questo script installa %s e poi il pannello, crea l'account amministratore e alla fine mostra l'indirizzo di accesso.
pt|intro_end|Este script instala %s e depois o painel, cria a conta de administrador e mostra o endereço de acesso no fim.
nl|intro_end|Dit script installeert %s en daarna het paneel, maakt het beheerdersaccount aan en toont aan het eind het toegangsadres.
ru|intro_end|Этот скрипт устанавливает %s, затем панель, создаёт учётную запись администратора и в конце показывает адрес доступа.
zh|intro_end|此脚本先安装%s，再安装面板，创建管理员账户，并在最后显示访问地址。
ar|intro_end|يثبت هذا السكربت %s ثم اللوحة، وينشئ حساب المسؤول ويعرض عنوان الوصول في النهاية.
en|intro_stack_linux|the full stack (Nginx, PHP, MariaDB, certbot…)
fr|intro_stack_linux|la pile complète (Nginx, PHP, MariaDB, certbot…)
de|intro_stack_linux|den kompletten Stack (Nginx, PHP, MariaDB, certbot…)
es|intro_stack_linux|la pila completa (Nginx, PHP, MariaDB, certbot…)
it|intro_stack_linux|lo stack completo (Nginx, PHP, MariaDB, certbot…)
pt|intro_stack_linux|a pilha completa (Nginx, PHP, MariaDB, certbot…)
nl|intro_stack_linux|de volledige stack (Nginx, PHP, MariaDB, certbot…)
ru|intro_stack_linux|полный стек (Nginx, PHP, MariaDB, certbot…)
zh|intro_stack_linux|完整软件栈（Nginx、PHP、MariaDB、certbot…）
ar|intro_stack_linux|الحزمة الكاملة (Nginx وPHP وMariaDB وcertbot…)
en|intro_stack_win|Python, the stack (-Stack: Nginx, PHP, MariaDB)
fr|intro_stack_win|Python, la pile (-Stack : Nginx, PHP, MariaDB)
de|intro_stack_win|Python, den Stack (-Stack: Nginx, PHP, MariaDB)
es|intro_stack_win|Python, la pila (-Stack: Nginx, PHP, MariaDB)
it|intro_stack_win|Python, lo stack (-Stack: Nginx, PHP, MariaDB)
pt|intro_stack_win|o Python, a pilha (-Stack: Nginx, PHP, MariaDB)
nl|intro_stack_win|Python, de stack (-Stack: Nginx, PHP, MariaDB)
ru|intro_stack_win|Python, стек (-Stack: Nginx, PHP, MariaDB)
zh|intro_stack_win|Python、软件栈（-Stack：Nginx、PHP、MariaDB）
ar|intro_stack_win|بايثون والحزمة (-Stack: Nginx وPHP وMariaDB)
en|state_existing|Existing installation detected in %s (version %s)
fr|state_existing|Installation existante détectée dans %s (version %s)
de|state_existing|Bestehende Installation in %s erkannt (Version %s)
es|state_existing|Instalación existente detectada en %s (versión %s)
it|state_existing|Installazione esistente rilevata in %s (versione %s)
pt|state_existing|Instalação existente detetada em %s (versão %s)
nl|state_existing|Bestaande installatie gevonden in %s (versie %s)
ru|state_existing|Обнаружена существующая установка в %s (версия %s)
zh|state_existing|在 %s 中检测到现有安装（版本 %s）
ar|state_existing|تم اكتشاف تثبيت موجود في %s (الإصدار %s)
en|state_none|No installation in %s: first installation
fr|state_none|Aucune installation dans %s : première installation
de|state_none|Keine Installation in %s: Erstinstallation
es|state_none|Ninguna instalación en %s: primera instalación
it|state_none|Nessuna installazione in %s: prima installazione
pt|state_none|Nenhuma instalação em %s: primeira instalação
nl|state_none|Geen installatie in %s: eerste installatie
ru|state_none|В %s нет установки: первая установка
zh|state_none|%s 中没有安装：首次安装
ar|state_none|لا يوجد تثبيت في %s: تثبيت أول
en|unknown|unknown
fr|unknown|inconnue
de|unknown|unbekannt
es|unknown|desconocida
it|unknown|sconosciuta
pt|unknown|desconhecida
nl|unknown|onbekend
ru|unknown|неизвестна
zh|unknown|未知
ar|unknown|غير معروف
en|none|none
fr|none|aucune
de|none|keine
es|none|ninguna
it|none|nessuna
pt|none|nenhuma
nl|none|geen
ru|none|нет
zh|none|无
ar|none|لا شيء
en|menu_title|What would you like to do?
fr|menu_title|Que voulez-vous faire ?
de|menu_title|Was möchten Sie tun?
es|menu_title|¿Qué desea hacer?
it|menu_title|Cosa desidera fare?
pt|menu_title|O que pretende fazer?
nl|menu_title|Wat wilt u doen?
ru|menu_title|Что вы хотите сделать?
zh|menu_title|您想做什么？
ar|menu_title|ماذا تريد أن تفعل؟
en|m_update|Update ToutPanel
fr|m_update|Mettre à jour ToutPanel
de|m_update|ToutPanel aktualisieren
es|m_update|Actualizar ToutPanel
it|m_update|Aggiornare ToutPanel
pt|m_update|Atualizar o ToutPanel
nl|m_update|ToutPanel bijwerken
ru|m_update|Обновить ToutPanel
zh|m_update|更新 ToutPanel
ar|m_update|تحديث ToutPanel
en|m_update_d|accounts, settings, sites and software kept
fr|m_update_d|comptes, réglages, sites et logiciels conservés
de|m_update_d|Konten, Einstellungen, Websites und Software bleiben erhalten
es|m_update_d|se conservan cuentas, ajustes, sitios y software
it|m_update_d|account, impostazioni, siti e software conservati
pt|m_update_d|contas, definições, sites e software mantidos
nl|m_update_d|accounts, instellingen, sites en software blijven behouden
ru|m_update_d|учётные записи, настройки, сайты и программы сохраняются
zh|m_update_d|保留账户、设置、站点和软件
ar|m_update_d|مع الاحتفاظ بالحسابات والإعدادات والمواقع والبرامج
en|m_reinstall|Reinstall from scratch
fr|m_reinstall|Réinstaller complètement
de|m_reinstall|Komplett neu installieren
es|m_reinstall|Reinstalar desde cero
it|m_reinstall|Reinstallare da zero
pt|m_reinstall|Reinstalar de raiz
nl|m_reinstall|Volledig opnieuw installeren
ru|m_reinstall|Переустановить с нуля
zh|m_reinstall|完全重新安装
ar|m_reinstall|إعادة التثبيت بالكامل
en|m_reinstall_d|starts over in %s
fr|m_reinstall_d|repart de zéro dans %s
de|m_reinstall_d|beginnt in %s von vorn
es|m_reinstall_d|empieza de cero en %s
it|m_reinstall_d|riparte da zero in %s
pt|m_reinstall_d|recomeça do zero em %s
nl|m_reinstall_d|begint opnieuw in %s
ru|m_reinstall_d|начинает заново в %s
zh|m_reinstall_d|在 %s 中从头开始
ar|m_reinstall_d|يبدأ من الصفر في %s
en|m_uninstall|Uninstall ToutPanel
fr|m_uninstall|Désinstaller ToutPanel
de|m_uninstall|ToutPanel deinstallieren
es|m_uninstall|Desinstalar ToutPanel
it|m_uninstall|Disinstallare ToutPanel
pt|m_uninstall|Desinstalar o ToutPanel
nl|m_uninstall|ToutPanel verwijderen
ru|m_uninstall|Удалить ToutPanel
zh|m_uninstall|卸载 ToutPanel
ar|m_uninstall|إزالة ToutPanel
en|m_uninstall_d|sites and databases stay in place
fr|m_uninstall_d|les sites et bases de données restent en place
de|m_uninstall_d|Websites und Datenbanken bleiben erhalten
es|m_uninstall_d|los sitios y las bases de datos se mantienen
it|m_uninstall_d|siti e database restano al loro posto
pt|m_uninstall_d|os sites e as bases de dados mantêm-se
nl|m_uninstall_d|sites en databases blijven staan
ru|m_uninstall_d|сайты и базы данных остаются на месте
zh|m_uninstall_d|站点和数据库保持不变
ar|m_uninstall_d|تبقى المواقع وقواعد البيانات كما هي
en|m_quit|Quit
fr|m_quit|Quitter
de|m_quit|Beenden
es|m_quit|Salir
it|m_quit|Esci
pt|m_quit|Sair
nl|m_quit|Afsluiten
ru|m_quit|Выйти
zh|m_quit|退出
ar|m_quit|خروج
en|m_install|Install ToutPanel
fr|m_install|Installer ToutPanel
de|m_install|ToutPanel installieren
es|m_install|Instalar ToutPanel
it|m_install|Installare ToutPanel
pt|m_install|Instalar o ToutPanel
nl|m_install|ToutPanel installeren
ru|m_install|Установить ToutPanel
zh|m_install|安装 ToutPanel
ar|m_install|تثبيت ToutPanel
en|m_install_d_linux|full stack: Nginx, PHP, MariaDB, certbot…
fr|m_install_d_linux|pile complète : Nginx, PHP, MariaDB, certbot…
de|m_install_d_linux|kompletter Stack: Nginx, PHP, MariaDB, certbot…
es|m_install_d_linux|pila completa: Nginx, PHP, MariaDB, certbot…
it|m_install_d_linux|stack completo: Nginx, PHP, MariaDB, certbot…
pt|m_install_d_linux|pilha completa: Nginx, PHP, MariaDB, certbot…
nl|m_install_d_linux|volledige stack: Nginx, PHP, MariaDB, certbot…
ru|m_install_d_linux|полный стек: Nginx, PHP, MariaDB, certbot…
zh|m_install_d_linux|完整软件栈：Nginx、PHP、MariaDB、certbot…
ar|m_install_d_linux|الحزمة الكاملة: Nginx وPHP وMariaDB وcertbot…
en|m_install_d_win|with the stack: Nginx, PHP, MariaDB
fr|m_install_d_win|avec la pile : Nginx, PHP, MariaDB
de|m_install_d_win|mit dem Stack: Nginx, PHP, MariaDB
es|m_install_d_win|con la pila: Nginx, PHP, MariaDB
it|m_install_d_win|con lo stack: Nginx, PHP, MariaDB
pt|m_install_d_win|com a pilha: Nginx, PHP, MariaDB
nl|m_install_d_win|met de stack: Nginx, PHP, MariaDB
ru|m_install_d_win|со стеком: Nginx, PHP, MariaDB
zh|m_install_d_win|包含软件栈：Nginx、PHP、MariaDB
ar|m_install_d_win|مع الحزمة: Nginx وPHP وMariaDB
en|m_panel_only|Install the panel only
fr|m_panel_only|Installer le panel seul
de|m_panel_only|Nur das Panel installieren
es|m_panel_only|Instalar solo el panel
it|m_panel_only|Installare solo il pannello
pt|m_panel_only|Instalar apenas o painel
nl|m_panel_only|Alleen het paneel installeren
ru|m_panel_only|Установить только панель
zh|m_panel_only|仅安装面板
ar|m_panel_only|تثبيت اللوحة فقط
en|m_panel_only_d|no stack: you manage Nginx / PHP / MariaDB
fr|m_panel_only_d|sans pile : vous gérez Nginx / PHP / MariaDB
de|m_panel_only_d|ohne Stack: Sie verwalten Nginx / PHP / MariaDB selbst
es|m_panel_only_d|sin pila: usted gestiona Nginx / PHP / MariaDB
it|m_panel_only_d|senza stack: gestite voi Nginx / PHP / MariaDB
pt|m_panel_only_d|sem pilha: gere o Nginx / PHP / MariaDB por si
nl|m_panel_only_d|zonder stack: u beheert zelf Nginx / PHP / MariaDB
ru|m_panel_only_d|без стека: Nginx / PHP / MariaDB вы настраиваете сами
zh|m_panel_only_d|不含软件栈：由您自行管理 Nginx / PHP / MariaDB
ar|m_panel_only_d|بدون الحزمة: تتولى أنت إدارة Nginx / PHP / MariaDB
en|menu_choice|Your choice [%s]:
fr|menu_choice|Votre choix [%s] :
de|menu_choice|Ihre Wahl [%s]:
es|menu_choice|Su elección [%s]:
it|menu_choice|La sua scelta [%s]:
pt|menu_choice|A sua escolha [%s]:
nl|menu_choice|Uw keuze [%s]:
ru|menu_choice|Ваш выбор [%s]:
zh|menu_choice|您的选择 [%s]：
ar|menu_choice|اختيارك [%s]:
en|menu_choice_win|Your choice [%s]
fr|menu_choice_win|Votre choix [%s]
de|menu_choice_win|Ihre Wahl [%s]
es|menu_choice_win|Su elección [%s]
it|menu_choice_win|La sua scelta [%s]
pt|menu_choice_win|A sua escolha [%s]
nl|menu_choice_win|Uw keuze [%s]
ru|menu_choice_win|Ваш выбор [%s]
zh|menu_choice_win|您的选择 [%s]
ar|menu_choice_win|اختيارك [%s]
en|yn_hint|[y/N]
fr|yn_hint|[o/N]
de|yn_hint|[j/N]
es|yn_hint|[s/N]
it|yn_hint|[s/N]
pt|yn_hint|[s/N]
nl|yn_hint|[j/N]
ru|yn_hint|[д/N]
zh|yn_hint|[y/N]
ar|yn_hint|[y/N]
en|yes_chars|yY
fr|yes_chars|oOyY
de|yes_chars|jJyY
es|yes_chars|sSyY
it|yes_chars|sSyY
pt|yes_chars|sSyY
nl|yes_chars|jJyY
ru|yes_chars|дДyY
zh|yes_chars|yY
ar|yes_chars|yYن
en|ask_postgres|Also install PostgreSQL (in addition to MariaDB)? %s:
fr|ask_postgres|Installer aussi PostgreSQL (en plus de MariaDB) ? %s :
de|ask_postgres|PostgreSQL zusätzlich installieren (neben MariaDB)? %s:
es|ask_postgres|¿Instalar también PostgreSQL (además de MariaDB)? %s:
it|ask_postgres|Installare anche PostgreSQL (oltre a MariaDB)? %s:
pt|ask_postgres|Instalar também o PostgreSQL (além do MariaDB)? %s:
nl|ask_postgres|Ook PostgreSQL installeren (naast MariaDB)? %s:
ru|ask_postgres|Установить также PostgreSQL (в дополнение к MariaDB)? %s:
zh|ask_postgres|是否同时安装 PostgreSQL（MariaDB 之外）？%s：
ar|ask_postgres|هل تريد تثبيت PostgreSQL أيضًا (إضافة إلى MariaDB)؟ %s:
en|ask_node|Install in node mode (server managed by another ToutPanel panel)? %s:
fr|ask_node|Installer en mode nœud (serveur piloté par un autre panel ToutPanel) ? %s :
de|ask_node|Im Node-Modus installieren (Server wird von einem anderen ToutPanel-Panel verwaltet)? %s:
es|ask_node|¿Instalar en modo nodo (servidor gestionado por otro panel ToutPanel)? %s:
it|ask_node|Installare in modalità nodo (server gestito da un altro pannello ToutPanel)? %s:
pt|ask_node|Instalar em modo nó (servidor gerido por outro painel ToutPanel)? %s:
nl|ask_node|Installeren in node-modus (server beheerd door een ander ToutPanel-paneel)? %s:
ru|ask_node|Установить в режиме узла (сервер управляется другой панелью ToutPanel)? %s:
zh|ask_node|是否以节点模式安装（由另一个 ToutPanel 面板管理此服务器）？%s：
ar|ask_node|هل تريد التثبيت في وضع العقدة (خادم تديره لوحة ToutPanel أخرى)؟ %s:
en|goodbye|Goodbye.
fr|goodbye|À bientôt.
de|goodbye|Auf Wiedersehen.
es|goodbye|Hasta pronto.
it|goodbye|A presto.
pt|goodbye|Até breve.
nl|goodbye|Tot ziens.
ru|goodbye|До свидания.
zh|goodbye|再见。
ar|goodbye|إلى اللقاء.
en|st_uninstall|Uninstalling ToutPanel
fr|st_uninstall|Désinstallation de ToutPanel
de|st_uninstall|Deinstallation von ToutPanel
es|st_uninstall|Desinstalación de ToutPanel
it|st_uninstall|Disinstallazione di ToutPanel
pt|st_uninstall|Desinstalação do ToutPanel
nl|st_uninstall|ToutPanel wordt verwijderd
ru|st_uninstall|Удаление ToutPanel
zh|st_uninstall|正在卸载 ToutPanel
ar|st_uninstall|إزالة ToutPanel
en|un_nothing|Nothing to uninstall in %s.
fr|un_nothing|Rien à désinstaller dans %s.
de|un_nothing|In %s gibt es nichts zu deinstallieren.
es|un_nothing|Nada que desinstalar en %s.
it|un_nothing|Niente da disinstallare in %s.
pt|un_nothing|Nada a desinstalar em %s.
nl|un_nothing|Niets te verwijderen in %s.
ru|un_nothing|В %s нечего удалять.
zh|un_nothing|%s 中没有可卸载的内容。
ar|un_nothing|لا يوجد ما يُزال في %s.
en|un_remove|Will be removed: the service, %s (panel, Python environment, logs, certificates), /usr/local/bin/toutpanel and the Nginx / Apache configurations generated by the panel (toutpanel_*).
fr|un_remove|Seront supprimés : le service, %s (panel, environnement Python, journaux, certificats), /usr/local/bin/toutpanel et les configurations Nginx / Apache générées par le panel (toutpanel_*).
de|un_remove|Entfernt werden: der Dienst, %s (Panel, Python-Umgebung, Protokolle, Zertifikate), /usr/local/bin/toutpanel und die vom Panel erzeugten Nginx-/Apache-Konfigurationen (toutpanel_*).
es|un_remove|Se eliminarán: el servicio, %s (panel, entorno Python, registros, certificados), /usr/local/bin/toutpanel y las configuraciones Nginx / Apache generadas por el panel (toutpanel_*).
it|un_remove|Verranno rimossi: il servizio, %s (pannello, ambiente Python, log, certificati), /usr/local/bin/toutpanel e le configurazioni Nginx / Apache generate dal pannello (toutpanel_*).
pt|un_remove|Serão removidos: o serviço, %s (painel, ambiente Python, registos, certificados), /usr/local/bin/toutpanel e as configurações Nginx / Apache geradas pelo painel (toutpanel_*).
nl|un_remove|Worden verwijderd: de service, %s (paneel, Python-omgeving, logboeken, certificaten), /usr/local/bin/toutpanel en de door het paneel gegenereerde Nginx-/Apache-configuraties (toutpanel_*).
ru|un_remove|Будут удалены: служба, %s (панель, окружение Python, журналы, сертификаты), /usr/local/bin/toutpanel и конфигурации Nginx / Apache, созданные панелью (toutpanel_*).
zh|un_remove|将被删除：服务、%s（面板、Python 环境、日志、证书）、/usr/local/bin/toutpanel 以及面板生成的 Nginx / Apache 配置（toutpanel_*）。
ar|un_remove|سيُحذف: الخدمة، و%s (اللوحة، وبيئة بايثون، والسجلات، والشهادات)، و/usr/local/bin/toutpanel، وإعدادات Nginx / Apache التي أنشأتها اللوحة (toutpanel_*).
en|un_keep|Will be kept: the sites in /www/wwwroot, the databases, PHP, Nginx, MariaDB and the other installed software. The panel data is archived before removal.
fr|un_keep|Seront conservés : les sites dans /www/wwwroot, les bases de données, PHP, Nginx, MariaDB et les autres logiciels installés. Les données du panel sont archivées avant suppression.
de|un_keep|Erhalten bleiben: die Websites in /www/wwwroot, die Datenbanken, PHP, Nginx, MariaDB und die übrige installierte Software. Die Panel-Daten werden vor dem Entfernen archiviert.
es|un_keep|Se conservarán: los sitios en /www/wwwroot, las bases de datos, PHP, Nginx, MariaDB y el resto del software instalado. Los datos del panel se archivan antes de eliminarlos.
it|un_keep|Verranno conservati: i siti in /www/wwwroot, i database, PHP, Nginx, MariaDB e gli altri software installati. I dati del pannello vengono archiviati prima della rimozione.
pt|un_keep|Serão mantidos: os sites em /www/wwwroot, as bases de dados, PHP, Nginx, MariaDB e o restante software instalado. Os dados do painel são arquivados antes da remoção.
nl|un_keep|Blijven behouden: de sites in /www/wwwroot, de databases, PHP, Nginx, MariaDB en de overige geïnstalleerde software. De paneelgegevens worden vóór het verwijderen gearchiveerd.
ru|un_keep|Будут сохранены: сайты в /www/wwwroot, базы данных, PHP, Nginx, MariaDB и другие установленные программы. Данные панели архивируются перед удалением.
zh|un_keep|将被保留：/www/wwwroot 中的站点、数据库、PHP、Nginx、MariaDB 及其他已安装软件。面板数据会在删除前归档。
ar|un_keep|سيُحتفظ بـ: المواقع في /www/wwwroot، وقواعد البيانات، وPHP، وNginx، وMariaDB، وبقية البرامج المثبتة. تُؤرشف بيانات اللوحة قبل الحذف.
en|un_remove_win|Will be removed: the ToutPanel and ToutPanel-Nginx scheduled tasks, the folder %s (panel, Python, logs, certificates).
fr|un_remove_win|Seront supprimés : les tâches planifiées ToutPanel et ToutPanel-Nginx, le dossier %s (panel, Python, journaux, certificats).
de|un_remove_win|Entfernt werden: die geplanten Aufgaben ToutPanel und ToutPanel-Nginx, der Ordner %s (Panel, Python, Protokolle, Zertifikate).
es|un_remove_win|Se eliminarán: las tareas programadas ToutPanel y ToutPanel-Nginx, la carpeta %s (panel, Python, registros, certificados).
it|un_remove_win|Verranno rimossi: le attività pianificate ToutPanel e ToutPanel-Nginx, la cartella %s (pannello, Python, log, certificati).
pt|un_remove_win|Serão removidos: as tarefas agendadas ToutPanel e ToutPanel-Nginx, a pasta %s (painel, Python, registos, certificados).
nl|un_remove_win|Worden verwijderd: de geplande taken ToutPanel en ToutPanel-Nginx, de map %s (paneel, Python, logboeken, certificaten).
ru|un_remove_win|Будут удалены: запланированные задачи ToutPanel и ToutPanel-Nginx, папка %s (панель, Python, журналы, сертификаты).
zh|un_remove_win|将被删除：计划任务 ToutPanel 和 ToutPanel-Nginx、文件夹 %s（面板、Python、日志、证书）。
ar|un_remove_win|سيُحذف: المهمتان المجدولتان ToutPanel وToutPanel-Nginx، والمجلد %s (اللوحة، وبايثون، والسجلات، والشهادات).
en|un_keep_win|Will be kept: the sites in %s (moved alongside), the databases, Nginx, PHP, MariaDB.
fr|un_keep_win|Seront conservés : les sites dans %s (déplacés à côté), les bases de données, Nginx, PHP, MariaDB.
de|un_keep_win|Erhalten bleiben: die Websites in %s (werden daneben verschoben), die Datenbanken, Nginx, PHP, MariaDB.
es|un_keep_win|Se conservarán: los sitios en %s (movidos al lado), las bases de datos, Nginx, PHP, MariaDB.
it|un_keep_win|Verranno conservati: i siti in %s (spostati accanto), i database, Nginx, PHP, MariaDB.
pt|un_keep_win|Serão mantidos: os sites em %s (movidos para o lado), as bases de dados, Nginx, PHP, MariaDB.
nl|un_keep_win|Blijven behouden: de sites in %s (ernaast verplaatst), de databases, Nginx, PHP, MariaDB.
ru|un_keep_win|Будут сохранены: сайты в %s (перемещаются рядом), базы данных, Nginx, PHP, MariaDB.
zh|un_keep_win|将被保留：%s 中的站点（移到旁边）、数据库、Nginx、PHP、MariaDB。
ar|un_keep_win|سيُحتفظ بـ: المواقع في %s (تُنقل بجانبه)، وقواعد البيانات، وNginx، وPHP، وMariaDB.
en|un_confirm|Confirm by typing %s:
fr|un_confirm|Confirmez en tapant %s :
de|un_confirm|Zur Bestätigung %s eingeben:
es|un_confirm|Confirme escribiendo %s:
it|un_confirm|Confermare digitando %s:
pt|un_confirm|Confirme escrevendo %s:
nl|un_confirm|Bevestig door %s te typen:
ru|un_confirm|Подтвердите, введя %s:
zh|un_confirm|输入 %s 以确认：
ar|un_confirm|أكّد بكتابة %s:
en|un_confirm_win|Confirm by typing %s
fr|un_confirm_win|Confirmez en tapant %s
de|un_confirm_win|Zur Bestätigung %s eingeben
es|un_confirm_win|Confirme escribiendo %s
it|un_confirm_win|Confermare digitando %s
pt|un_confirm_win|Confirme escrevendo %s
nl|un_confirm_win|Bevestig door %s te typen
ru|un_confirm_win|Подтвердите, введя %s
zh|un_confirm_win|输入 %s 以确认
ar|un_confirm_win|أكّد بكتابة %s
en|confirm_word|yes
fr|confirm_word|oui
de|confirm_word|ja
es|confirm_word|si
it|confirm_word|si
pt|confirm_word|sim
nl|confirm_word|ja
ru|confirm_word|да
zh|confirm_word|yes
ar|confirm_word|نعم
en|un_no_tty|No terminal: run again with --uninstall --yes to confirm.
fr|un_no_tty|Pas de terminal : relancez avec --uninstall --yes pour confirmer.
de|un_no_tty|Kein Terminal: zur Bestätigung erneut mit --uninstall --yes starten.
es|un_no_tty|Sin terminal: vuelva a ejecutar con --uninstall --yes para confirmar.
it|un_no_tty|Nessun terminale: rilanciare con --uninstall --yes per confermare.
pt|un_no_tty|Sem terminal: execute novamente com --uninstall --yes para confirmar.
nl|un_no_tty|Geen terminal: start opnieuw met --uninstall --yes om te bevestigen.
ru|un_no_tty|Нет терминала: для подтверждения запустите снова с --uninstall --yes.
zh|un_no_tty|没有终端：请使用 --uninstall --yes 重新运行以确认。
ar|un_no_tty|لا توجد طرفية: أعد التشغيل مع --uninstall --yes للتأكيد.
en|un_cancelled|Uninstall cancelled.
fr|un_cancelled|Désinstallation annulée.
de|un_cancelled|Deinstallation abgebrochen.
es|un_cancelled|Desinstalación cancelada.
it|un_cancelled|Disinstallazione annullata.
pt|un_cancelled|Desinstalação cancelada.
nl|un_cancelled|Verwijderen geannuleerd.
ru|un_cancelled|Удаление отменено.
zh|un_cancelled|已取消卸载。
ar|un_cancelled|تم إلغاء الإزالة.
en|un_archived|Data archived in %s
fr|un_archived|Données archivées dans %s
de|un_archived|Daten archiviert in %s
es|un_archived|Datos archivados en %s
it|un_archived|Dati archiviati in %s
pt|un_archived|Dados arquivados em %s
nl|un_archived|Gegevens gearchiveerd in %s
ru|un_archived|Данные заархивированы в %s
zh|un_archived|数据已归档到 %s
ar|un_archived|أُرشفت البيانات في %s
en|un_archive_failed|Could not archive the panel data to %s: uninstall stopped, nothing was removed (free some space in /root and try again).
fr|un_archive_failed|Impossible d'archiver les données du panel dans %s : désinstallation arrêtée, rien n'a été supprimé (libérez de la place dans /root puis relancez).
de|un_archive_failed|Die Panel-Daten konnten nicht nach %s archiviert werden: Deinstallation abgebrochen, nichts wurde entfernt (geben Sie Speicherplatz in /root frei und versuchen Sie es erneut).
es|un_archive_failed|No se pudieron archivar los datos del panel en %s: desinstalación detenida, no se ha eliminado nada (libere espacio en /root y vuelva a intentarlo).
it|un_archive_failed|Impossibile archiviare i dati del pannello in %s: disinstallazione interrotta, nulla è stato rimosso (liberare spazio in /root e riprovare).
pt|un_archive_failed|Não foi possível arquivar os dados do painel em %s: desinstalação interrompida, nada foi removido (liberte espaço em /root e tente novamente).
nl|un_archive_failed|De paneelgegevens konden niet in %s worden gearchiveerd: verwijdering gestopt, er is niets verwijderd (maak ruimte vrij in /root en probeer het opnieuw).
ru|un_archive_failed|Не удалось архивировать данные панели в %s: удаление остановлено, ничего не удалено (освободите место в /root и повторите попытку).
zh|un_archive_failed|无法将面板数据归档到 %s：卸载已停止，未删除任何内容（请释放 /root 中的空间后重试）。
ar|un_archive_failed|تعذّرت أرشفة بيانات اللوحة في %s: أُوقف إلغاء التثبيت ولم يُحذف أي شيء (حرّر مساحة في /root ثم أعد المحاولة).
en|un_sites_moved|Sites moved to %s
fr|un_sites_moved|Sites déplacés dans %s
de|un_sites_moved|Websites verschoben nach %s
es|un_sites_moved|Sitios movidos a %s
it|un_sites_moved|Siti spostati in %s
pt|un_sites_moved|Sites movidos para %s
nl|un_sites_moved|Sites verplaatst naar %s
ru|un_sites_moved|Сайты перемещены в %s
zh|un_sites_moved|站点已移至 %s
ar|un_sites_moved|نُقلت المواقع إلى %s
en|un_done|ToutPanel has been uninstalled.
fr|un_done|ToutPanel est désinstallé.
de|un_done|ToutPanel wurde deinstalliert.
es|un_done|ToutPanel se ha desinstalado.
it|un_done|ToutPanel è stato disinstallato.
pt|un_done|O ToutPanel foi desinstalado.
nl|un_done|ToutPanel is verwijderd.
ru|un_done|ToutPanel удалён.
zh|un_done|ToutPanel 已卸载。
ar|un_done|تمت إزالة ToutPanel.
en|un_archive_info|Panel data archive: %s (database, settings, certificates, templates).
fr|un_archive_info|Archive des données du panel : %s (base, réglages, certificats, modèles).
de|un_archive_info|Archiv der Panel-Daten: %s (Datenbank, Einstellungen, Zertifikate, Vorlagen).
es|un_archive_info|Archivo de los datos del panel: %s (base de datos, ajustes, certificados, plantillas).
it|un_archive_info|Archivio dei dati del pannello: %s (database, impostazioni, certificati, modelli).
pt|un_archive_info|Arquivo dos dados do painel: %s (base de dados, definições, certificados, modelos).
nl|un_archive_info|Archief van de paneelgegevens: %s (database, instellingen, certificaten, sjablonen).
ru|un_archive_info|Архив данных панели: %s (база, настройки, сертификаты, шаблоны).
zh|un_archive_info|面板数据归档：%s（数据库、设置、证书、模板）。
ar|un_archive_info|أرشيف بيانات اللوحة: %s (قاعدة البيانات، والإعدادات، والشهادات، والقوالب).
en|un_kept|Sites kept in /www/wwwroot; databases kept. To reinstall: run this script again.
fr|un_kept|Sites conservés dans /www/wwwroot ; bases de données conservées. Pour réinstaller : relancez ce script.
de|un_kept|Websites in /www/wwwroot und Datenbanken bleiben erhalten. Zum Neuinstallieren: dieses Skript erneut starten.
es|un_kept|Sitios conservados en /www/wwwroot; bases de datos conservadas. Para reinstalar: vuelva a ejecutar este script.
it|un_kept|Siti conservati in /www/wwwroot; database conservati. Per reinstallare: rilanciare questo script.
pt|un_kept|Sites mantidos em /www/wwwroot; bases de dados mantidas. Para reinstalar: execute novamente este script.
nl|un_kept|Sites behouden in /www/wwwroot; databases behouden. Opnieuw installeren: start dit script opnieuw.
ru|un_kept|Сайты сохранены в /www/wwwroot; базы данных сохранены. Для переустановки запустите этот скрипт снова.
zh|un_kept|站点保留在 /www/wwwroot；数据库已保留。如需重新安装：请再次运行此脚本。
ar|un_kept|المواقع محفوظة في /www/wwwroot؛ وقواعد البيانات محفوظة. لإعادة التثبيت: أعد تشغيل هذا السكربت.
en|un_archive_win|Panel data archive: %s
fr|un_archive_win|Archive des données du panel : %s
de|un_archive_win|Archiv der Panel-Daten: %s
es|un_archive_win|Archivo de los datos del panel: %s
it|un_archive_win|Archivio dei dati del pannello: %s
pt|un_archive_win|Arquivo dos dados do painel: %s
nl|un_archive_win|Archief van de paneelgegevens: %s
ru|un_archive_win|Архив данных панели: %s
zh|un_archive_win|面板数据归档：%s
ar|un_archive_win|أرشيف بيانات اللوحة: %s
en|un_reinstall_win|To reinstall: run this script again.
fr|un_reinstall_win|Pour réinstaller : relancez ce script.
de|un_reinstall_win|Zum Neuinstallieren: dieses Skript erneut starten.
es|un_reinstall_win|Para reinstalar: vuelva a ejecutar este script.
it|un_reinstall_win|Per reinstallare: rilanciare questo script.
pt|un_reinstall_win|Para reinstalar: execute novamente este script.
nl|un_reinstall_win|Opnieuw installeren: start dit script opnieuw.
ru|un_reinstall_win|Для переустановки запустите этот скрипт снова.
zh|un_reinstall_win|如需重新安装：请再次运行此脚本。
ar|un_reinstall_win|لإعادة التثبيت: أعد تشغيل هذا السكربت.
en|no_install_update|No installation in %s: run without %s.
fr|no_install_update|Aucune installation dans %s : lancez sans %s.
de|no_install_update|Keine Installation in %s: ohne %s starten.
es|no_install_update|Ninguna instalación en %s: ejecute sin %s.
it|no_install_update|Nessuna installazione in %s: avviare senza %s.
pt|no_install_update|Nenhuma instalação em %s: execute sem %s.
nl|no_install_update|Geen installatie in %s: start zonder %s.
ru|no_install_update|В %s нет установки: запустите без %s.
zh|no_install_update|%s 中没有安装：请不带 %s 运行。
ar|no_install_update|لا يوجد تثبيت في %s: شغّل دون %s.
en|update_detected|Existing installation detected in %s: updating (accounts, settings, sites and software kept).
fr|update_detected|Installation existante détectée dans %s : mise à jour (comptes, réglages, sites et logiciels conservés).
de|update_detected|Bestehende Installation in %s erkannt: Aktualisierung (Konten, Einstellungen, Websites und Software bleiben erhalten).
es|update_detected|Instalación existente detectada en %s: actualización (se conservan cuentas, ajustes, sitios y software).
it|update_detected|Installazione esistente rilevata in %s: aggiornamento (account, impostazioni, siti e software conservati).
pt|update_detected|Instalação existente detetada em %s: atualização (contas, definições, sites e software mantidos).
nl|update_detected|Bestaande installatie gevonden in %s: bijwerken (accounts, instellingen, sites en software blijven behouden).
ru|update_detected|Обнаружена существующая установка в %s: обновление (учётные записи, настройки, сайты и программы сохраняются).
zh|update_detected|在 %s 中检测到现有安装：执行更新（保留账户、设置、站点和软件）。
ar|update_detected|تم اكتشاف تثبيت موجود في %s: تحديث (مع الاحتفاظ بالحسابات والإعدادات والمواقع والبرامج).
en|data_backed_up|Data backed up to %s (settings.json, SQLite database, keys).
fr|data_backed_up|Données sauvegardées dans %s (settings.json, base SQLite, clés).
de|data_backed_up|Daten gesichert in %s (settings.json, SQLite-Datenbank, Schlüssel).
es|data_backed_up|Datos guardados en %s (settings.json, base SQLite, claves).
it|data_backed_up|Dati salvati in %s (settings.json, database SQLite, chiavi).
pt|data_backed_up|Dados guardados em %s (settings.json, base de dados SQLite, chaves).
nl|data_backed_up|Gegevens geback-upt in %s (settings.json, SQLite-database, sleutels).
ru|data_backed_up|Данные сохранены в %s (settings.json, база SQLite, ключи).
zh|data_backed_up|数据已备份到 %s（settings.json、SQLite 数据库、密钥）。
ar|data_backed_up|نُسخت البيانات احتياطيًا في %s (settings.json، وقاعدة SQLite، والمفاتيح).
en|pkg_unknown|Unrecognised package manager.
fr|pkg_unknown|Gestionnaire de paquets non reconnu.
de|pkg_unknown|Paketmanager nicht erkannt.
es|pkg_unknown|Gestor de paquetes no reconocido.
it|pkg_unknown|Gestore di pacchetti non riconosciuto.
pt|pkg_unknown|Gestor de pacotes não reconhecido.
nl|pkg_unknown|Pakketbeheerder niet herkend.
ru|pkg_unknown|Менеджер пакетов не распознан.
zh|pkg_unknown|无法识别的软件包管理器。
ar|pkg_unknown|مدير الحزم غير معروف.
en|st_deps|Base dependencies
fr|st_deps|Dépendances de base
de|st_deps|Grundlegende Abhängigkeiten
es|st_deps|Dependencias básicas
it|st_deps|Dipendenze di base
pt|st_deps|Dependências de base
nl|st_deps|Basisafhankelijkheden
ru|st_deps|Базовые зависимости
zh|st_deps|基础依赖
ar|st_deps|الاعتماديات الأساسية
en|python_required|Python 3.9+ required.
fr|python_required|Python 3.9+ requis.
de|python_required|Python 3.9+ erforderlich.
es|python_required|Se requiere Python 3.9+.
it|python_required|È richiesto Python 3.9+.
pt|python_required|É necessário Python 3.9+.
nl|python_required|Python 3.9+ vereist.
ru|python_required|Требуется Python 3.9+.
zh|python_required|需要 Python 3.9+。
ar|python_required|يلزم Python 3.9 أو أحدث.
en|st_nginx|Nginx web server
fr|st_nginx|Serveur web Nginx
de|st_nginx|Webserver Nginx
es|st_nginx|Servidor web Nginx
it|st_nginx|Server web Nginx
pt|st_nginx|Servidor web Nginx
nl|st_nginx|Webserver Nginx
ru|st_nginx|Веб-сервер Nginx
zh|st_nginx|Nginx Web 服务器
ar|st_nginx|خادم الويب Nginx
en|st_phpfpm|PHP-FPM
fr|st_phpfpm|PHP-FPM
de|st_phpfpm|PHP-FPM
es|st_phpfpm|PHP-FPM
it|st_phpfpm|PHP-FPM
pt|st_phpfpm|PHP-FPM
nl|st_phpfpm|PHP-FPM
ru|st_phpfpm|PHP-FPM
zh|st_phpfpm|PHP-FPM
ar|st_phpfpm|PHP-FPM
en|remi_unavailable|Remi unavailable: installing the system's PHP version.
fr|remi_unavailable|Remi indisponible : installation de la version PHP du système.
de|remi_unavailable|Remi nicht verfügbar: Die PHP-Version des Systems wird installiert.
es|remi_unavailable|Remi no disponible: se instala la versión de PHP del sistema.
it|remi_unavailable|Remi non disponibile: installazione della versione PHP del sistema.
pt|remi_unavailable|Remi indisponível: a instalar a versão de PHP do sistema.
nl|remi_unavailable|Remi niet beschikbaar: de PHP-versie van het systeem wordt geïnstalleerd.
ru|remi_unavailable|Remi недоступен: устанавливается версия PHP из системы.
zh|remi_unavailable|Remi 不可用：安装系统自带的 PHP 版本。
ar|remi_unavailable|مستودع Remi غير متاح: يُثبَّت إصدار PHP الخاص بالنظام.
en|php_installed|PHP %s installed.
fr|php_installed|PHP %s installé.
de|php_installed|PHP %s installiert.
es|php_installed|PHP %s instalado.
it|php_installed|PHP %s installato.
pt|php_installed|PHP %s instalado.
nl|php_installed|PHP %s geïnstalleerd.
ru|php_installed|PHP %s установлен.
zh|php_installed|PHP %s 已安装。
ar|php_installed|تم تثبيت PHP %s.
en|php_default_fallback|PHP %s is not available for this system: PHP %s installed instead (most recent available).
fr|php_default_fallback|PHP %s n'est pas disponible pour ce système : PHP %s installé à la place (la plus récente disponible).
de|php_default_fallback|PHP %s ist für dieses System nicht verfügbar: stattdessen PHP %s installiert (neueste verfügbare Version).
es|php_default_fallback|PHP %s no está disponible para este sistema: se instala PHP %s en su lugar (la más reciente disponible).
it|php_default_fallback|PHP %s non è disponibile per questo sistema: installato PHP %s al suo posto (la più recente disponibile).
pt|php_default_fallback|O PHP %s não está disponível para este sistema: instalado o PHP %s em seu lugar (a mais recente disponível).
nl|php_default_fallback|PHP %s is niet beschikbaar voor dit systeem: in plaats daarvan PHP %s geïnstalleerd (nieuwste beschikbare versie).
ru|php_default_fallback|PHP %s недоступен для этой системы: вместо него установлен PHP %s (самая новая из доступных версий).
zh|php_default_fallback|此系统无法使用 PHP %s：已改为安装 PHP %s（可用的最新版本）。
ar|php_default_fallback|PHP %s غير متاح لهذا النظام: ثُبّت PHP %s بدلًا منه (أحدث إصدار متاح).
en|st_certbot|Certbot (Let's Encrypt) and tools
fr|st_certbot|Certbot (Let's Encrypt) et outils
de|st_certbot|Certbot (Let's Encrypt) und Werkzeuge
es|st_certbot|Certbot (Let's Encrypt) y herramientas
it|st_certbot|Certbot (Let's Encrypt) e strumenti
pt|st_certbot|Certbot (Let's Encrypt) e ferramentas
nl|st_certbot|Certbot (Let's Encrypt) en hulpmiddelen
ru|st_certbot|Certbot (Let's Encrypt) и утилиты
zh|st_certbot|Certbot（Let's Encrypt）及工具
ar|st_certbot|Certbot (Let's Encrypt) والأدوات
en|st_mariadb|MariaDB
fr|st_mariadb|MariaDB
de|st_mariadb|MariaDB
es|st_mariadb|MariaDB
it|st_mariadb|MariaDB
pt|st_mariadb|MariaDB
nl|st_mariadb|MariaDB
ru|st_mariadb|MariaDB
zh|st_mariadb|MariaDB
ar|st_mariadb|MariaDB
en|st_redis|Redis / Valkey
fr|st_redis|Redis / Valkey
de|st_redis|Redis / Valkey
es|st_redis|Redis / Valkey
it|st_redis|Redis / Valkey
pt|st_redis|Redis / Valkey
nl|st_redis|Redis / Valkey
ru|st_redis|Redis / Valkey
zh|st_redis|Redis / Valkey
ar|st_redis|Redis / Valkey
en|st_fail2ban|Security: Fail2ban
fr|st_fail2ban|Sécurité : Fail2ban
de|st_fail2ban|Sicherheit: Fail2ban
es|st_fail2ban|Seguridad: Fail2ban
it|st_fail2ban|Sicurezza: Fail2ban
pt|st_fail2ban|Segurança: Fail2ban
nl|st_fail2ban|Beveiliging: Fail2ban
ru|st_fail2ban|Безопасность: Fail2ban
zh|st_fail2ban|安全：Fail2ban
ar|st_fail2ban|الأمان: Fail2ban
en|st_mail|Mail server: Postfix + Dovecot + OpenDKIM
fr|st_mail|Serveur mail : Postfix + Dovecot + OpenDKIM
de|st_mail|Mailserver: Postfix + Dovecot + OpenDKIM
es|st_mail|Servidor de correo: Postfix + Dovecot + OpenDKIM
it|st_mail|Server di posta: Postfix + Dovecot + OpenDKIM
pt|st_mail|Servidor de correio: Postfix + Dovecot + OpenDKIM
nl|st_mail|Mailserver: Postfix + Dovecot + OpenDKIM
ru|st_mail|Почтовый сервер: Postfix + Dovecot + OpenDKIM
zh|st_mail|邮件服务器：Postfix + Dovecot + OpenDKIM
ar|st_mail|خادم البريد: Postfix + Dovecot + OpenDKIM
en|st_postgres|PostgreSQL
fr|st_postgres|PostgreSQL
de|st_postgres|PostgreSQL
es|st_postgres|PostgreSQL
it|st_postgres|PostgreSQL
pt|st_postgres|PostgreSQL
nl|st_postgres|PostgreSQL
ru|st_postgres|PostgreSQL
zh|st_postgres|PostgreSQL
ar|st_postgres|PostgreSQL
en|st_install_panel|Installing the panel in %s
fr|st_install_panel|Installation du panel dans %s
de|st_install_panel|Installation des Panels in %s
es|st_install_panel|Instalación del panel en %s
it|st_install_panel|Installazione del pannello in %s
pt|st_install_panel|Instalação do painel em %s
nl|st_install_panel|Installatie van het paneel in %s
ru|st_install_panel|Установка панели в %s
zh|st_install_panel|正在将面板安装到 %s
ar|st_install_panel|تثبيت اللوحة في %s
en|st_update_panel|Updating the panel in %s
fr|st_update_panel|Mise à jour du panel dans %s
de|st_update_panel|Aktualisierung des Panels in %s
es|st_update_panel|Actualización del panel en %s
it|st_update_panel|Aggiornamento del pannello in %s
pt|st_update_panel|Atualização do painel em %s
nl|st_update_panel|Bijwerken van het paneel in %s
ru|st_update_panel|Обновление панели в %s
zh|st_update_panel|正在更新 %s 中的面板
ar|st_update_panel|تحديث اللوحة في %s
en|src_updating|Updating the sources (branch %s)…
fr|src_updating|Mise à jour des sources (branche %s)…
de|src_updating|Quellen werden aktualisiert (Branch %s)…
es|src_updating|Actualizando las fuentes (rama %s)…
it|src_updating|Aggiornamento dei sorgenti (branch %s)…
pt|src_updating|A atualizar o código-fonte (ramo %s)…
nl|src_updating|Broncode wordt bijgewerkt (branch %s)…
ru|src_updating|Обновление исходников (ветка %s)…
zh|src_updating|正在更新源码（分支 %s）…
ar|src_updating|تحديث الشيفرة المصدرية (الفرع %s)…
en|src_reclone|Local repository unusable: cloning again.
fr|src_reclone|Dépôt local inutilisable : nouveau clone.
de|src_reclone|Lokales Repository unbrauchbar: neuer Klon.
es|src_reclone|Repositorio local inutilizable: se clona de nuevo.
it|src_reclone|Repository locale inutilizzabile: nuovo clone.
pt|src_reclone|Repositório local inutilizável: novo clone.
nl|src_reclone|Lokale repository onbruikbaar: opnieuw klonen.
ru|src_reclone|Локальный репозиторий непригоден: повторное клонирование.
zh|src_reclone|本地仓库不可用：重新克隆。
ar|src_reclone|المستودع المحلي غير صالح: استنساخ جديد.
en|src_download|Downloading the sources (branch %s)…
fr|src_download|Téléchargement des sources (branche %s)…
de|src_download|Quellen werden heruntergeladen (Branch %s)…
es|src_download|Descargando las fuentes (rama %s)…
it|src_download|Download dei sorgenti (branch %s)…
pt|src_download|A transferir o código-fonte (ramo %s)…
nl|src_download|Broncode wordt gedownload (branch %s)…
ru|src_download|Загрузка исходников (ветка %s)…
zh|src_download|正在下载源码（分支 %s）…
ar|src_download|تنزيل الشيفرة المصدرية (الفرع %s)…
en|repo_incomplete|Incomplete panel repository in %s: neither pyproject.toml (sources) nor %s (prebuilt wheels).
fr|repo_incomplete|Dépôt du panel incomplet dans %s : ni pyproject.toml (sources) ni %s (roues précompilées).
de|repo_incomplete|Unvollständiges Panel-Repository in %s: weder pyproject.toml (Quellen) noch %s (vorkompilierte Wheels).
es|repo_incomplete|Repositorio del panel incompleto en %s: no hay pyproject.toml (fuentes) ni %s (wheels precompilados).
it|repo_incomplete|Repository del pannello incompleto in %s: né pyproject.toml (sorgenti) né %s (wheel precompilate).
pt|repo_incomplete|Repositório do painel incompleto em %s: sem pyproject.toml (código-fonte) nem %s (wheels pré-compiladas).
nl|repo_incomplete|Onvolledige paneelrepository in %s: geen pyproject.toml (broncode) en geen %s (vooraf gebouwde wheels).
ru|repo_incomplete|Неполный репозиторий панели в %s: нет ни pyproject.toml (исходники), ни %s (готовые колёса).
zh|repo_incomplete|%s 中的面板仓库不完整：既没有 pyproject.toml（源码）也没有 %s（预编译 wheel）。
ar|repo_incomplete|مستودع اللوحة غير مكتمل في %s: لا يوجد pyproject.toml (الشيفرة المصدرية) ولا %s (حزم wheel مُجمّعة مسبقًا).
en|no_wheel|No panel build for Python %s in %s.
fr|no_wheel|Aucune version du panel pour Python %s dans %s.
de|no_wheel|Keine Panel-Version für Python %s in %s.
es|no_wheel|Ninguna versión del panel para Python %s en %s.
it|no_wheel|Nessuna versione del pannello per Python %s in %s.
pt|no_wheel|Nenhuma versão do painel para Python %s em %s.
nl|no_wheel|Geen paneelversie voor Python %s in %s.
ru|no_wheel|Нет сборки панели для Python %s в %s.
zh|no_wheel|没有适用于 Python %s 的面板版本（位于 %s）。
ar|no_wheel|لا توجد نسخة من اللوحة لبايثون %s في %s.
en|wheel_supported|Python versions supported by this ToutPanel release: %s.
fr|wheel_supported|Versions de Python prises en charge par cette version de ToutPanel : %s.
de|wheel_supported|Von dieser ToutPanel-Version unterstützte Python-Versionen: %s.
es|wheel_supported|Versiones de Python admitidas por esta versión de ToutPanel: %s.
it|wheel_supported|Versioni di Python supportate da questa versione di ToutPanel: %s.
pt|wheel_supported|Versões de Python suportadas por esta versão do ToutPanel: %s.
nl|wheel_supported|Python-versies die deze ToutPanel-versie ondersteunt: %s.
ru|wheel_supported|Версии Python, поддерживаемые этой версией ToutPanel: %s.
zh|wheel_supported|此 ToutPanel 版本支持的 Python 版本：%s。
ar|wheel_supported|إصدارات بايثون التي يدعمها هذا الإصدار من ToutPanel: %s.
en|no_wheel_hint|Install one of these versions (the distribution's python3.X package) and run the script again, or delete %s if the environment was created with a different Python version than the system's.
fr|no_wheel_hint|Installez l'une de ces versions (paquet python3.X de la distribution) et relancez le script, ou supprimez %s si l'environnement a été créé avec une autre version de Python que celle du système.
de|no_wheel_hint|Installieren Sie eine dieser Versionen (Paket python3.X der Distribution) und starten Sie das Skript erneut, oder löschen Sie %s, falls die Umgebung mit einer anderen Python-Version als der des Systems erstellt wurde.
es|no_wheel_hint|Instale una de estas versiones (paquete python3.X de la distribución) y vuelva a ejecutar el script, o elimine %s si el entorno se creó con una versión de Python distinta de la del sistema.
it|no_wheel_hint|Installare una di queste versioni (pacchetto python3.X della distribuzione) e rilanciare lo script, oppure eliminare %s se l'ambiente è stato creato con una versione di Python diversa da quella del sistema.
pt|no_wheel_hint|Instale uma destas versões (pacote python3.X da distribuição) e execute novamente o script, ou elimine %s se o ambiente foi criado com uma versão de Python diferente da do sistema.
nl|no_wheel_hint|Installeer een van deze versies (pakket python3.X van de distributie) en start het script opnieuw, of verwijder %s als de omgeving met een andere Python-versie dan die van het systeem is gemaakt.
ru|no_wheel_hint|Установите одну из этих версий (пакет python3.X дистрибутива) и запустите скрипт снова, либо удалите %s, если окружение создано другой версией Python, чем системная.
zh|no_wheel_hint|请安装其中一个版本（发行版的 python3.X 软件包）后重新运行脚本；如果该环境是用与系统不同的 Python 版本创建的，请删除 %s。
ar|no_wheel_hint|ثبّت أحد هذه الإصدارات (حزمة python3.X من التوزيعة) وأعد تشغيل السكربت، أو احذف %s إذا أُنشئت البيئة بإصدار بايثون مختلف عن إصدار النظام.
en|no_wheel_hint_win|Install one of them (python.org) and run the script again; if %s was created with another Python version, delete it first.
fr|no_wheel_hint_win|Installez l'une d'elles (python.org) puis relancez le script ; si %s a été créé avec une autre version de Python, supprimez-le d'abord.
de|no_wheel_hint_win|Installieren Sie eine davon (python.org) und starten Sie das Skript erneut; wurde %s mit einer anderen Python-Version erstellt, löschen Sie es zuerst.
es|no_wheel_hint_win|Instale una de ellas (python.org) y vuelva a ejecutar el script; si %s se creó con otra versión de Python, elimínelo antes.
it|no_wheel_hint_win|Installarne una (python.org) e rilanciare lo script; se %s è stato creato con un'altra versione di Python, eliminarlo prima.
pt|no_wheel_hint_win|Instale uma delas (python.org) e execute novamente o script; se %s foi criado com outra versão de Python, elimine-o primeiro.
nl|no_wheel_hint_win|Installeer er een (python.org) en start het script opnieuw; als %s met een andere Python-versie is gemaakt, verwijder het dan eerst.
ru|no_wheel_hint_win|Установите одну из них (python.org) и запустите скрипт снова; если %s создан другой версией Python, сначала удалите его.
zh|no_wheel_hint_win|请安装其中一个版本（python.org）后重新运行脚本；如果 %s 是用其他 Python 版本创建的，请先将其删除。
ar|no_wheel_hint_win|ثبّت أحدها (python.org) ثم أعد تشغيل السكربت؛ وإذا أُنشئ %s بإصدار بايثون آخر فاحذفه أولًا.
en|checksum_bad|Checksum mismatch for %s: tampered repository or incomplete download.
fr|checksum_bad|Somme de contrôle incorrecte pour %s : dépôt altéré ou téléchargement incomplet.
de|checksum_bad|Falsche Prüfsumme für %s: manipuliertes Repository oder unvollständiger Download.
es|checksum_bad|Suma de comprobación incorrecta para %s: repositorio alterado o descarga incompleta.
it|checksum_bad|Checksum errato per %s: repository alterato o download incompleto.
pt|checksum_bad|Soma de verificação incorreta para %s: repositório alterado ou transferência incompleta.
nl|checksum_bad|Onjuiste controlesom voor %s: gewijzigde repository of onvolledige download.
ru|checksum_bad|Неверная контрольная сумма для %s: репозиторий изменён или загрузка не завершена.
zh|checksum_bad|%s 的校验和不正确：仓库被篡改或下载不完整。
ar|checksum_bad|مجموع التحقق غير صحيح لـ %s: مستودع معدّل أو تنزيل غير مكتمل.
en|installing_wheel|Installing %s (Python %s)…
fr|installing_wheel|Installation de %s (Python %s)…
de|installing_wheel|Installation von %s (Python %s)…
es|installing_wheel|Instalando %s (Python %s)…
it|installing_wheel|Installazione di %s (Python %s)…
pt|installing_wheel|A instalar %s (Python %s)…
nl|installing_wheel|%s wordt geïnstalleerd (Python %s)…
ru|installing_wheel|Установка %s (Python %s)…
zh|installing_wheel|正在安装 %s（Python %s）…
ar|installing_wheel|تثبيت %s (بايثون %s)…
en|installing_source|Installing from the sources (%s)…
fr|installing_source|Installation depuis les sources (%s)…
de|installing_source|Installation aus den Quellen (%s)…
es|installing_source|Instalando desde las fuentes (%s)…
it|installing_source|Installazione dai sorgenti (%s)…
pt|installing_source|A instalar a partir do código-fonte (%s)…
nl|installing_source|Installatie vanuit de broncode (%s)…
ru|installing_source|Установка из исходников (%s)…
zh|installing_source|正在从源码安装（%s）…
ar|installing_source|التثبيت من الشيفرة المصدرية (%s)…
en|docs_not_built|Embedded documentation not built: the online help will be used.
fr|docs_not_built|Documentation embarquée non construite : aide en ligne utilisée.
de|docs_not_built|Eingebettete Dokumentation nicht erstellt: Die Online-Hilfe wird verwendet.
es|docs_not_built|Documentación integrada no generada: se usará la ayuda en línea.
it|docs_not_built|Documentazione integrata non generata: verrà usata la guida online.
pt|docs_not_built|Documentação integrada não gerada: será usada a ajuda online.
nl|docs_not_built|Ingebouwde documentatie niet gebouwd: de online hulp wordt gebruikt.
ru|docs_not_built|Встроенная документация не собрана: будет использоваться онлайн-справка.
zh|docs_not_built|未构建内置文档：将使用在线帮助。
ar|docs_not_built|لم تُبنَ الوثائق المضمّنة: ستُستخدم المساعدة عبر الإنترنت.
en|st_migrate|Database migration and check
fr|st_migrate|Migration de la base et vérification
de|st_migrate|Datenbankmigration und Prüfung
es|st_migrate|Migración de la base de datos y verificación
it|st_migrate|Migrazione del database e verifica
pt|st_migrate|Migração da base de dados e verificação
nl|st_migrate|Databasemigratie en controle
ru|st_migrate|Миграция базы и проверка
zh|st_migrate|数据库迁移与检查
ar|st_migrate|ترحيل قاعدة البيانات والتحقق
en|st_admin|Administrator account and secure URL
fr|st_admin|Compte administrateur et URL sécurisée
de|st_admin|Administratorkonto und gesicherte URL
es|st_admin|Cuenta de administrador y URL segura
it|st_admin|Account amministratore e URL sicuro
pt|st_admin|Conta de administrador e URL segura
nl|st_admin|Beheerdersaccount en beveiligde URL
ru|st_admin|Учётная запись администратора и защищённый URL
zh|st_admin|管理员账户与安全 URL
ar|st_admin|حساب المسؤول وعنوان URL الآمن
en|accounts_kept|Accounts and secure entrance kept.
fr|accounts_kept|Comptes et entrée sécurisée conservés.
de|accounts_kept|Konten und gesicherter Zugang bleiben erhalten.
es|accounts_kept|Se conservan las cuentas y la entrada segura.
it|accounts_kept|Account e ingresso sicuro conservati.
pt|accounts_kept|Contas e entrada segura mantidas.
nl|accounts_kept|Accounts en beveiligde toegang blijven behouden.
ru|accounts_kept|Учётные записи и защищённый вход сохранены.
zh|accounts_kept|已保留账户和安全入口。
ar|accounts_kept|تم الاحتفاظ بالحسابات والمدخل الآمن.
en|st_secure_mariadb|Securing MariaDB
fr|st_secure_mariadb|Sécurisation de MariaDB
de|st_secure_mariadb|Absicherung von MariaDB
es|st_secure_mariadb|Protección de MariaDB
it|st_secure_mariadb|Messa in sicurezza di MariaDB
pt|st_secure_mariadb|Proteção do MariaDB
nl|st_secure_mariadb|MariaDB beveiligen
ru|st_secure_mariadb|Защита MariaDB
zh|st_secure_mariadb|加固 MariaDB
ar|st_secure_mariadb|تأمين MariaDB
en|mariadb_ok|MariaDB root password set and saved in the panel.
fr|mariadb_ok|Mot de passe root MariaDB défini et enregistré dans le panel.
de|mariadb_ok|MariaDB-Root-Passwort festgelegt und im Panel gespeichert.
es|mariadb_ok|Contraseña root de MariaDB definida y guardada en el panel.
it|mariadb_ok|Password root di MariaDB impostata e salvata nel pannello.
pt|mariadb_ok|Senha root do MariaDB definida e guardada no painel.
nl|mariadb_ok|MariaDB-rootwachtwoord ingesteld en in het paneel opgeslagen.
ru|mariadb_ok|Пароль root MariaDB задан и сохранён в панели.
zh|mariadb_ok|已设置 MariaDB root 密码并保存到面板。
ar|mariadb_ok|تم تعيين كلمة مرور root لـ MariaDB وحفظها في اللوحة.
en|mariadb_fail|Cannot connect to MariaDB as root without a password: enter the credentials in Databases → Root credentials.
fr|mariadb_fail|Impossible de se connecter à MariaDB en root sans mot de passe : renseignez les identifiants dans Bases de données → Identifiants root.
de|mariadb_fail|Verbindung zu MariaDB als root ohne Passwort nicht möglich: Zugangsdaten unter Datenbanken → Root-Zugangsdaten eintragen.
es|mariadb_fail|No se puede conectar a MariaDB como root sin contraseña: introduzca las credenciales en Bases de datos → Credenciales root.
it|mariadb_fail|Impossibile connettersi a MariaDB come root senza password: inserire le credenziali in Database → Credenziali root.
pt|mariadb_fail|Não é possível ligar ao MariaDB como root sem senha: introduza as credenciais em Bases de dados → Credenciais root.
nl|mariadb_fail|Kan geen verbinding maken met MariaDB als root zonder wachtwoord: vul de gegevens in bij Databases → Root-inloggegevens.
ru|mariadb_fail|Не удаётся подключиться к MariaDB как root без пароля: укажите данные в разделе Базы данных → Учётные данные root.
zh|mariadb_fail|无法以 root 身份无密码连接 MariaDB：请在 数据库 → root 凭据 中填写凭据。
ar|mariadb_fail|تعذّر الاتصال بـ MariaDB بصفة root دون كلمة مرور: أدخل بيانات الاعتماد في قواعد البيانات → بيانات اعتماد root.
en|st_secure_pg|Securing PostgreSQL
fr|st_secure_pg|Sécurisation de PostgreSQL
de|st_secure_pg|Absicherung von PostgreSQL
es|st_secure_pg|Protección de PostgreSQL
it|st_secure_pg|Messa in sicurezza di PostgreSQL
pt|st_secure_pg|Proteção do PostgreSQL
nl|st_secure_pg|PostgreSQL beveiligen
ru|st_secure_pg|Защита PostgreSQL
zh|st_secure_pg|加固 PostgreSQL
ar|st_secure_pg|تأمين PostgreSQL
en|pg_ok|postgres role password set and saved in the panel.
fr|pg_ok|Mot de passe du rôle postgres défini et enregistré dans le panel.
de|pg_ok|Passwort der Rolle postgres festgelegt und im Panel gespeichert.
es|pg_ok|Contraseña del rol postgres definida y guardada en el panel.
it|pg_ok|Password del ruolo postgres impostata e salvata nel pannello.
pt|pg_ok|Senha da função postgres definida e guardada no painel.
nl|pg_ok|Wachtwoord van de rol postgres ingesteld en in het paneel opgeslagen.
ru|pg_ok|Пароль роли postgres задан и сохранён в панели.
zh|pg_ok|已设置 postgres 角色密码并保存到面板。
ar|pg_ok|تم تعيين كلمة مرور الدور postgres وحفظها في اللوحة.
en|pg_fail|postgres role unreachable: enter the credentials in Databases → Root credentials.
fr|pg_fail|Rôle postgres inaccessible : renseignez les identifiants dans Bases de données → Identifiants root.
de|pg_fail|Rolle postgres nicht erreichbar: Zugangsdaten unter Datenbanken → Root-Zugangsdaten eintragen.
es|pg_fail|Rol postgres inaccesible: introduzca las credenciales en Bases de datos → Credenciales root.
it|pg_fail|Ruolo postgres non raggiungibile: inserire le credenziali in Database → Credenziali root.
pt|pg_fail|Função postgres inacessível: introduza as credenciais em Bases de dados → Credenciais root.
nl|pg_fail|Rol postgres niet bereikbaar: vul de gegevens in bij Databases → Root-inloggegevens.
ru|pg_fail|Роль postgres недоступна: укажите данные в разделе Базы данных → Учётные данные root.
zh|pg_fail|无法访问 postgres 角色：请在 数据库 → root 凭据 中填写凭据。
ar|pg_fail|تعذّر الوصول إلى الدور postgres: أدخل بيانات الاعتماد في قواعد البيانات → بيانات اعتماد root.
en|st_selinux|SELinux: contexts and booleans
fr|st_selinux|SELinux : contextes et booléens
de|st_selinux|SELinux: Kontexte und Booleans
es|st_selinux|SELinux: contextos y booleanos
it|st_selinux|SELinux: contesti e booleani
pt|st_selinux|SELinux: contextos e booleanos
nl|st_selinux|SELinux: contexten en booleans
ru|st_selinux|SELinux: контексты и переключатели
zh|st_selinux|SELinux：上下文与布尔值
ar|st_selinux|SELinux: السياقات والقيم المنطقية
en|selinux_ok|SELinux configured (nginx/php-fpm can serve /www/wwwroot and the panel's logs and certificates).
fr|selinux_ok|SELinux configuré (nginx/php-fpm peuvent servir /www/wwwroot, journaux et certificats du panel).
de|selinux_ok|SELinux konfiguriert (nginx/php-fpm dürfen /www/wwwroot sowie Protokolle und Zertifikate des Panels bereitstellen).
es|selinux_ok|SELinux configurado (nginx/php-fpm pueden servir /www/wwwroot y los registros y certificados del panel).
it|selinux_ok|SELinux configurato (nginx/php-fpm possono servire /www/wwwroot, i log e i certificati del pannello).
pt|selinux_ok|SELinux configurado (nginx/php-fpm podem servir /www/wwwroot e os registos e certificados do painel).
nl|selinux_ok|SELinux geconfigureerd (nginx/php-fpm mogen /www/wwwroot en de logboeken en certificaten van het paneel serveren).
ru|selinux_ok|SELinux настроен (nginx/php-fpm могут обслуживать /www/wwwroot, журналы и сертификаты панели).
zh|selinux_ok|SELinux 已配置（nginx/php-fpm 可访问 /www/wwwroot 及面板的日志和证书）。
ar|selinux_ok|تم إعداد SELinux (يمكن لـ nginx/php-fpm تقديم /www/wwwroot وسجلات اللوحة وشهاداتها).
en|st_apparmor|AppArmor: local profiles
fr|st_apparmor|AppArmor : profils locaux
de|st_apparmor|AppArmor: lokale Profile
es|st_apparmor|AppArmor: perfiles locales
it|st_apparmor|AppArmor: profili locali
pt|st_apparmor|AppArmor: perfis locais
nl|st_apparmor|AppArmor: lokale profielen
ru|st_apparmor|AppArmor: локальные профили
zh|st_apparmor|AppArmor：本地配置文件
ar|st_apparmor|AppArmor: الملفات الشخصية المحلية
en|apparmor_fail|AppArmor: configuration to redo with "toutpanel apparmor"
fr|apparmor_fail|AppArmor : configuration à refaire avec « toutpanel apparmor »
de|apparmor_fail|AppArmor: Konfiguration mit „toutpanel apparmor“ wiederholen
es|apparmor_fail|AppArmor: configuración que debe repetirse con «toutpanel apparmor»
it|apparmor_fail|AppArmor: configurazione da ripetere con «toutpanel apparmor»
pt|apparmor_fail|AppArmor: configuração a repetir com «toutpanel apparmor»
nl|apparmor_fail|AppArmor: configuratie opnieuw uitvoeren met "toutpanel apparmor"
ru|apparmor_fail|AppArmor: повторите настройку командой «toutpanel apparmor»
zh|apparmor_fail|AppArmor：请使用“toutpanel apparmor”重新配置
ar|apparmor_fail|AppArmor: أعد الإعداد باستخدام "toutpanel apparmor"
en|st_service|Panel service
fr|st_service|Service du panel
de|st_service|Panel-Dienst
es|st_service|Servicio del panel
it|st_service|Servizio del pannello
pt|st_service|Serviço do painel
nl|st_service|Paneelservice
ru|st_service|Служба панели
zh|st_service|面板服务
ar|st_service|خدمة اللوحة
en|panel_restarted|Panel restarted with the new version.
fr|panel_restarted|Panel redémarré avec la nouvelle version.
de|panel_restarted|Panel mit der neuen Version neu gestartet.
es|panel_restarted|Panel reiniciado con la nueva versión.
it|panel_restarted|Pannello riavviato con la nuova versione.
pt|panel_restarted|Painel reiniciado com a nova versão.
nl|panel_restarted|Paneel herstart met de nieuwe versie.
ru|panel_restarted|Панель перезапущена с новой версией.
zh|panel_restarted|面板已使用新版本重启。
ar|panel_restarted|أُعيد تشغيل اللوحة بالإصدار الجديد.
en|panel_up|Service 'toutpanel' started and reachable on port %s.
fr|panel_up|Service 'toutpanel' démarré et joignable sur le port %s.
de|panel_up|Dienst 'toutpanel' gestartet und auf Port %s erreichbar.
es|panel_up|Servicio 'toutpanel' iniciado y accesible en el puerto %s.
it|panel_up|Servizio 'toutpanel' avviato e raggiungibile sulla porta %s.
pt|panel_up|Serviço 'toutpanel' iniciado e acessível na porta %s.
nl|panel_up|Service 'toutpanel' gestart en bereikbaar op poort %s.
ru|panel_up|Служба 'toutpanel' запущена и доступна на порту %s.
zh|panel_up|服务“toutpanel”已启动，可通过端口 %s 访问。
ar|panel_up|الخدمة 'toutpanel' تعمل ويمكن الوصول إليها على المنفذ %s.
en|panel_down|The panel is not responding on port %s after 30 s.
fr|panel_down|Le panel ne répond pas sur le port %s après 30 s.
de|panel_down|Das Panel antwortet nach 30 s nicht auf Port %s.
es|panel_down|El panel no responde en el puerto %s tras 30 s.
it|panel_down|Il pannello non risponde sulla porta %s dopo 30 s.
pt|panel_down|O painel não responde na porta %s após 30 s.
nl|panel_down|Het paneel reageert na 30 s niet op poort %s.
ru|panel_down|Панель не отвечает на порту %s спустя 30 с.
zh|panel_down|30 秒后面板仍未在端口 %s 上响应。
ar|panel_down|لا تستجيب اللوحة على المنفذ %s بعد 30 ثانية.
en|journal_header|--- log (journalctl -u toutpanel -n 20):
fr|journal_header|--- journal (journalctl -u toutpanel -n 20) :
de|journal_header|--- Protokoll (journalctl -u toutpanel -n 20):
es|journal_header|--- registro (journalctl -u toutpanel -n 20):
it|journal_header|--- log (journalctl -u toutpanel -n 20):
pt|journal_header|--- registo (journalctl -u toutpanel -n 20):
nl|journal_header|--- logboek (journalctl -u toutpanel -n 20):
ru|journal_header|--- журнал (journalctl -u toutpanel -n 20):
zh|journal_header|--- 日志（journalctl -u toutpanel -n 20）：
ar|journal_header|--- السجل (journalctl -u toutpanel -n 20):
en|selinux_enforcing|SELinux is in enforcing mode: check the denials with "ausearch -m avc -ts recent".
fr|selinux_enforcing|SELinux est en mode enforcing : vérifiez les refus avec « ausearch -m avc -ts recent ».
de|selinux_enforcing|SELinux ist im Modus enforcing: Ablehnungen mit „ausearch -m avc -ts recent“ prüfen.
es|selinux_enforcing|SELinux está en modo enforcing: revise los rechazos con «ausearch -m avc -ts recent».
it|selinux_enforcing|SELinux è in modalità enforcing: verificare i rifiuti con «ausearch -m avc -ts recent».
pt|selinux_enforcing|O SELinux está em modo enforcing: verifique as recusas com «ausearch -m avc -ts recent».
nl|selinux_enforcing|SELinux staat in enforcing-modus: controleer de weigeringen met "ausearch -m avc -ts recent".
ru|selinux_enforcing|SELinux в режиме enforcing: проверьте отказы командой «ausearch -m avc -ts recent».
zh|selinux_enforcing|SELinux 处于 enforcing 模式：请用“ausearch -m avc -ts recent”检查拒绝记录。
ar|selinux_enforcing|SELinux في وضع enforcing: تحقق من حالات الرفض باستخدام "ausearch -m avc -ts recent".
en|st_waf_toutwaf|Vendor WAF: ToutWAF (official installer)
fr|st_waf_toutwaf|WAF de l'éditeur : ToutWAF (installeur officiel)
de|st_waf_toutwaf|WAF des Herstellers: ToutWAF (offizieller Installer)
es|st_waf_toutwaf|WAF del editor: ToutWAF (instalador oficial)
it|st_waf_toutwaf|WAF dell'editore: ToutWAF (installer ufficiale)
pt|st_waf_toutwaf|WAF do editor: ToutWAF (instalador oficial)
nl|st_waf_toutwaf|WAF van de uitgever: ToutWAF (officieel installatieprogramma)
ru|st_waf_toutwaf|WAF разработчика: ToutWAF (официальный установщик)
zh|st_waf_toutwaf|发行方 WAF：ToutWAF（官方安装程序）
ar|st_waf_toutwaf|WAF الناشر: ToutWAF (المثبت الرسمي)
en|waf_deployed|WAF %s deployed: console %s
fr|waf_deployed|WAF %s déployé : console %s
de|waf_deployed|WAF %s bereitgestellt: Konsole %s
es|waf_deployed|WAF %s desplegado: consola %s
it|waf_deployed|WAF %s distribuito: console %s
pt|waf_deployed|WAF %s implementado: consola %s
nl|waf_deployed|WAF %s geïmplementeerd: console %s
ru|waf_deployed|WAF %s развёрнут: консоль %s
zh|waf_deployed|WAF %s 已部署：控制台 %s
ar|waf_deployed|تم نشر WAF %s: الواجهة %s
en|toutwaf_failed|ToutWAF deployment failed: the web server stays on 80/443 (log: /var/log/toutwaf-install.log; retry from WAF → Engine).
fr|toutwaf_failed|Le déploiement de ToutWAF a échoué : le serveur web reste sur 80/443 (journal : /var/log/toutwaf-install.log ; relancez depuis WAF → Moteur).
de|toutwaf_failed|Bereitstellung von ToutWAF fehlgeschlagen: Der Webserver bleibt auf 80/443 (Protokoll: /var/log/toutwaf-install.log; erneut unter WAF → Engine starten).
es|toutwaf_failed|El despliegue de ToutWAF ha fallado: el servidor web sigue en 80/443 (registro: /var/log/toutwaf-install.log; reintente desde WAF → Motor).
it|toutwaf_failed|Distribuzione di ToutWAF non riuscita: il server web resta su 80/443 (log: /var/log/toutwaf-install.log; riprovare da WAF → Motore).
pt|toutwaf_failed|A implementação do ToutWAF falhou: o servidor web mantém-se em 80/443 (registo: /var/log/toutwaf-install.log; tente novamente em WAF → Motor).
nl|toutwaf_failed|Implementatie van ToutWAF mislukt: de webserver blijft op 80/443 (logboek: /var/log/toutwaf-install.log; opnieuw starten via WAF → Engine).
ru|toutwaf_failed|Развёртывание ToutWAF не удалось: веб-сервер остаётся на 80/443 (журнал: /var/log/toutwaf-install.log; повторите в WAF → Движок).
zh|toutwaf_failed|ToutWAF 部署失败：Web 服务器仍使用 80/443（日志：/var/log/toutwaf-install.log；请在 WAF → 引擎 中重试）。
ar|toutwaf_failed|فشل نشر ToutWAF: يبقى خادم الويب على 80/443 (السجل: /var/log/toutwaf-install.log؛ أعد المحاولة من WAF → المحرك).
en|st_waf_docker|External WAF: %s (Docker)
fr|st_waf_docker|WAF externe : %s (Docker)
de|st_waf_docker|Externe WAF: %s (Docker)
es|st_waf_docker|WAF externo: %s (Docker)
it|st_waf_docker|WAF esterno: %s (Docker)
pt|st_waf_docker|WAF externo: %s (Docker)
nl|st_waf_docker|Externe WAF: %s (Docker)
ru|st_waf_docker|Внешний WAF: %s (Docker)
zh|st_waf_docker|外部 WAF：%s（Docker）
ar|st_waf_docker|WAF خارجي: %s (Docker)
en|waf_failed|Deployment of WAF %s failed: the web server stays on 80/443 (retry from WAF → Engine).
fr|waf_failed|Le déploiement du WAF %s a échoué : le serveur web reste sur 80/443 (relancez depuis WAF → Moteur).
de|waf_failed|Bereitstellung der WAF %s fehlgeschlagen: Der Webserver bleibt auf 80/443 (erneut unter WAF → Engine starten).
es|waf_failed|El despliegue del WAF %s ha fallado: el servidor web sigue en 80/443 (reintente desde WAF → Motor).
it|waf_failed|Distribuzione del WAF %s non riuscita: il server web resta su 80/443 (riprovare da WAF → Motore).
pt|waf_failed|A implementação do WAF %s falhou: o servidor web mantém-se em 80/443 (tente novamente em WAF → Motor).
nl|waf_failed|Implementatie van WAF %s mislukt: de webserver blijft op 80/443 (opnieuw starten via WAF → Engine).
ru|waf_failed|Развёртывание WAF %s не удалось: веб-сервер остаётся на 80/443 (повторите в WAF → Движок).
zh|waf_failed|WAF %s 部署失败：Web 服务器仍使用 80/443（请在 WAF → 引擎 中重试）。
ar|waf_failed|فشل نشر WAF %s: يبقى خادم الويب على 80/443 (أعد المحاولة من WAF → المحرك).
en|st_firewall|Firewall
fr|st_firewall|Pare-feu
de|st_firewall|Firewall
es|st_firewall|Cortafuegos
it|st_firewall|Firewall
pt|st_firewall|Firewall
nl|st_firewall|Firewall
ru|st_firewall|Межсетевой экран
zh|st_firewall|防火墙
ar|st_firewall|جدار الحماية
en|st_node|Node mode (multi-server)
fr|st_node|Mode nœud (multi-serveurs)
de|st_node|Node-Modus (Multi-Server)
es|st_node|Modo nodo (multiservidor)
it|st_node|Modalità nodo (multi-server)
pt|st_node|Modo nó (multi-servidor)
nl|st_node|Node-modus (multi-server)
ru|st_node|Режим узла (несколько серверов)
zh|st_node|节点模式（多服务器）
ar|st_node|وضع العقدة (خوادم متعددة)
en|node_ok|Node mode enabled: enter the URL and the token, and check the TLS fingerprint on the master panel (System → Servers).
fr|node_ok|Mode nœud activé : saisissez l'URL, le jeton et vérifiez l'empreinte TLS sur le panel maître (Système → Serveurs).
de|node_ok|Node-Modus aktiviert: URL und Token auf dem Master-Panel eingeben und den TLS-Fingerabdruck prüfen (System → Server).
es|node_ok|Modo nodo activado: introduzca la URL y el token, y compruebe la huella TLS en el panel maestro (Sistema → Servidores).
it|node_ok|Modalità nodo attivata: inserire URL e token e verificare l'impronta TLS nel pannello master (Sistema → Server).
pt|node_ok|Modo nó ativado: introduza o URL e o token e verifique a impressão digital TLS no painel principal (Sistema → Servidores).
nl|node_ok|Node-modus ingeschakeld: voer de URL en het token in en controleer de TLS-vingerafdruk op het hoofdpaneel (Systeem → Servers).
ru|node_ok|Режим узла включён: введите URL и токен и проверьте отпечаток TLS на главной панели (Система → Серверы).
zh|node_ok|节点模式已启用：请在主面板中输入 URL 和令牌，并核对 TLS 指纹（系统 → 服务器）。
ar|node_ok|تم تفعيل وضع العقدة: أدخل عنوان URL والرمز وتحقق من بصمة TLS في اللوحة الرئيسية (النظام → الخوادم).
en|node_fail|Enrolment token not created: run "toutpanel node enroll --master <url>" again.
fr|node_fail|Jeton d'enrôlement non créé : relancez « toutpanel node enroll --master <url> ».
de|node_fail|Registrierungstoken nicht erstellt: „toutpanel node enroll --master <url>“ erneut ausführen.
es|node_fail|Token de registro no creado: vuelva a ejecutar «toutpanel node enroll --master <url>».
it|node_fail|Token di registrazione non creato: rieseguire «toutpanel node enroll --master <url>».
pt|node_fail|Token de registo não criado: execute novamente «toutpanel node enroll --master <url>».
nl|node_fail|Registratietoken niet aangemaakt: voer "toutpanel node enroll --master <url>" opnieuw uit.
ru|node_fail|Токен регистрации не создан: выполните снова «toutpanel node enroll --master <url>».
zh|node_fail|未创建注册令牌：请重新运行“toutpanel node enroll --master <url>”。
ar|node_fail|لم يُنشأ رمز التسجيل: أعد تشغيل "toutpanel node enroll --master <url>".
en|info_title|ToutPanel — installation details (%s)
fr|info_title|ToutPanel — informations d'installation (%s)
de|info_title|ToutPanel — Installationsinformationen (%s)
es|info_title|ToutPanel — información de la instalación (%s)
it|info_title|ToutPanel — informazioni sull'installazione (%s)
pt|info_title|ToutPanel — informações da instalação (%s)
nl|info_title|ToutPanel — installatiegegevens (%s)
ru|info_title|ToutPanel — сведения об установке (%s)
zh|info_title|ToutPanel — 安装信息（%s）
ar|info_title|ToutPanel — معلومات التثبيت (%s)
en|lbl_url|Panel URL
fr|lbl_url|URL du panel
de|lbl_url|Panel-URL
es|lbl_url|URL del panel
it|lbl_url|URL del pannello
pt|lbl_url|URL do painel
nl|lbl_url|Paneel-URL
ru|lbl_url|URL панели
zh|lbl_url|面板 URL
ar|lbl_url|عنوان URL للوحة
en|lbl_url_local|Local URL
fr|lbl_url_local|URL locale
de|lbl_url_local|Lokale URL
es|lbl_url_local|URL local
it|lbl_url_local|URL locale
pt|lbl_url_local|URL local
nl|lbl_url_local|Lokale URL
ru|lbl_url_local|Локальный URL
zh|lbl_url_local|本地 URL
ar|lbl_url_local|عنوان URL المحلي
en|lbl_url_http|Panel URL (HTTP)
fr|lbl_url_http|URL du panel (HTTP)
de|lbl_url_http|Panel-URL (HTTP)
es|lbl_url_http|URL del panel (HTTP)
it|lbl_url_http|URL del pannello (HTTP)
pt|lbl_url_http|URL do painel (HTTP)
nl|lbl_url_http|Paneel-URL (HTTP)
ru|lbl_url_http|URL панели (HTTP)
zh|lbl_url_http|面板 URL（HTTP）
ar|lbl_url_http|عنوان URL للوحة (HTTP)
en|lbl_url_https|Panel URL (HTTPS)
fr|lbl_url_https|URL du panel (HTTPS)
de|lbl_url_https|Panel-URL (HTTPS)
es|lbl_url_https|URL del panel (HTTPS)
it|lbl_url_https|URL del pannello (HTTPS)
pt|lbl_url_https|URL do painel (HTTPS)
nl|lbl_url_https|Paneel-URL (HTTPS)
ru|lbl_url_https|URL панели (HTTPS)
zh|lbl_url_https|面板 URL（HTTPS）
ar|lbl_url_https|عنوان URL للوحة (HTTPS)
en|lbl_url_local_http|Local URL (HTTP)
fr|lbl_url_local_http|URL locale (HTTP)
de|lbl_url_local_http|Lokale URL (HTTP)
es|lbl_url_local_http|URL local (HTTP)
it|lbl_url_local_http|URL locale (HTTP)
pt|lbl_url_local_http|URL local (HTTP)
nl|lbl_url_local_http|Lokale URL (HTTP)
ru|lbl_url_local_http|Локальный URL (HTTP)
zh|lbl_url_local_http|本地 URL（HTTP）
ar|lbl_url_local_http|عنوان URL المحلي (HTTP)
en|lbl_url_local_https|Local URL (HTTPS)
fr|lbl_url_local_https|URL locale (HTTPS)
de|lbl_url_local_https|Lokale URL (HTTPS)
es|lbl_url_local_https|URL local (HTTPS)
it|lbl_url_local_https|URL locale (HTTPS)
pt|lbl_url_local_https|URL local (HTTPS)
nl|lbl_url_local_https|Lokale URL (HTTPS)
ru|lbl_url_local_https|Локальный URL (HTTPS)
zh|lbl_url_local_https|本地 URL（HTTPS）
ar|lbl_url_local_https|عنوان URL المحلي (HTTPS)
en|self_signed_note|self-signed certificate: the browser warning is normal
fr|self_signed_note|certificat auto-signé : avertissement du navigateur normal
de|self_signed_note|selbstsigniertes Zertifikat: Browserwarnung ist normal
es|self_signed_note|certificado autofirmado: la advertencia del navegador es normal
it|self_signed_note|certificato autofirmato: l'avviso del browser è normale
pt|self_signed_note|certificado autoassinado: o aviso do navegador é normal
nl|self_signed_note|zelfondertekend certificaat: de browserwaarschuwing is normaal
ru|self_signed_note|самоподписанный сертификат: предупреждение браузера — это нормально
zh|self_signed_note|自签名证书：浏览器出现警告属正常现象
ar|self_signed_note|شهادة موقّعة ذاتيًا: تحذير المتصفح أمر طبيعي
en|lbl_user|Username
fr|lbl_user|Utilisateur
de|lbl_user|Benutzername
es|lbl_user|Usuario
it|lbl_user|Nome utente
pt|lbl_user|Utilizador
nl|lbl_user|Gebruikersnaam
ru|lbl_user|Пользователь
zh|lbl_user|用户名
ar|lbl_user|اسم المستخدم
en|lbl_pass|Password
fr|lbl_pass|Mot de passe
de|lbl_pass|Passwort
es|lbl_pass|Contraseña
it|lbl_pass|Password
pt|lbl_pass|Senha
nl|lbl_pass|Wachtwoord
ru|lbl_pass|Пароль
zh|lbl_pass|密码
ar|lbl_pass|كلمة المرور
en|lbl_entrance|Secure entrance
fr|lbl_entrance|Entrée sécurisée
de|lbl_entrance|Gesicherter Zugang
es|lbl_entrance|Entrada segura
it|lbl_entrance|Ingresso sicuro
pt|lbl_entrance|Entrada segura
nl|lbl_entrance|Beveiligde toegang
ru|lbl_entrance|Защищённый вход
zh|lbl_entrance|安全入口
ar|lbl_entrance|المدخل الآمن
en|lbl_setup|Setup wizard
fr|lbl_setup|Assistant de configuration
de|lbl_setup|Einrichtungsassistent
es|lbl_setup|Asistente de configuración
it|lbl_setup|Procedura guidata di configurazione
pt|lbl_setup|Assistente de configuração
nl|lbl_setup|Configuratieassistent
ru|lbl_setup|Мастер настройки
zh|lbl_setup|配置向导
ar|lbl_setup|معالج الإعداد
en|lbl_setup_local|Setup wizard (local)
fr|lbl_setup_local|Assistant de configuration (local)
de|lbl_setup_local|Einrichtungsassistent (lokal)
es|lbl_setup_local|Asistente de configuración (local)
it|lbl_setup_local|Procedura guidata di configurazione (locale)
pt|lbl_setup_local|Assistente de configuração (local)
nl|lbl_setup_local|Configuratieassistent (lokaal)
ru|lbl_setup_local|Мастер настройки (локально)
zh|lbl_setup_local|配置向导（本地）
ar|lbl_setup_local|معالج الإعداد (محلي)
en|lbl_dir|Directory
fr|lbl_dir|Répertoire
de|lbl_dir|Verzeichnis
es|lbl_dir|Directorio
it|lbl_dir|Directory
pt|lbl_dir|Diretório
nl|lbl_dir|Map
ru|lbl_dir|Каталог
zh|lbl_dir|目录
ar|lbl_dir|المجلد
en|lbl_version|Version
fr|lbl_version|Version
de|lbl_version|Version
es|lbl_version|Versión
it|lbl_version|Versione
pt|lbl_version|Versão
nl|lbl_version|Versie
ru|lbl_version|Версия
zh|lbl_version|版本
ar|lbl_version|الإصدار
en|lbl_mariadb|MariaDB root
fr|lbl_mariadb|MariaDB root
de|lbl_mariadb|MariaDB root
es|lbl_mariadb|MariaDB root
it|lbl_mariadb|MariaDB root
pt|lbl_mariadb|MariaDB root
nl|lbl_mariadb|MariaDB root
ru|lbl_mariadb|MariaDB root
zh|lbl_mariadb|MariaDB root
ar|lbl_mariadb|MariaDB root
en|lbl_pg|PostgreSQL
fr|lbl_pg|PostgreSQL
de|lbl_pg|PostgreSQL
es|lbl_pg|PostgreSQL
it|lbl_pg|PostgreSQL
pt|lbl_pg|PostgreSQL
nl|lbl_pg|PostgreSQL
ru|lbl_pg|PostgreSQL
zh|lbl_pg|PostgreSQL
ar|lbl_pg|PostgreSQL
en|lbl_php|PHP
fr|lbl_php|PHP
de|lbl_php|PHP
es|lbl_php|PHP
it|lbl_php|PHP
pt|lbl_php|PHP
nl|lbl_php|PHP
ru|lbl_php|PHP
zh|lbl_php|PHP
ar|lbl_php|PHP
en|lbl_commands|Commands
fr|lbl_commands|Commandes
de|lbl_commands|Befehle
es|lbl_commands|Comandos
it|lbl_commands|Comandi
pt|lbl_commands|Comandos
nl|lbl_commands|Opdrachten
ru|lbl_commands|Команды
zh|lbl_commands|命令
ar|lbl_commands|الأوامر
en|setup_note_file|(24 h, single use: change the address, the username and the password; new link: toutpanel setup-link)
fr|setup_note_file|(24 h, usage unique : changer l'adresse, l'utilisateur et le mot de passe ; nouveau lien : toutpanel setup-link)
de|setup_note_file|(24 h, einmalig: Adresse, Benutzername und Passwort ändern; neuer Link: toutpanel setup-link)
es|setup_note_file|(24 h, un solo uso: cambiar la dirección, el usuario y la contraseña; nuevo enlace: toutpanel setup-link)
it|setup_note_file|(24 h, uso singolo: modificare indirizzo, nome utente e password; nuovo link: toutpanel setup-link)
pt|setup_note_file|(24 h, utilização única: alterar o endereço, o utilizador e a senha; nova ligação: toutpanel setup-link)
nl|setup_note_file|(24 u, eenmalig: adres, gebruikersnaam en wachtwoord wijzigen; nieuwe link: toutpanel setup-link)
ru|setup_note_file|(24 ч, однократно: смена адреса, имени пользователя и пароля; новая ссылка: toutpanel setup-link)
zh|setup_note_file|（24 小时内一次性有效：修改地址、用户名和密码；新链接：toutpanel setup-link）
ar|setup_note_file|(24 ساعة، استخدام واحد: تغيير العنوان واسم المستخدم وكلمة المرور؛ رابط جديد: toutpanel setup-link)
en|info_node|Multi-server (node mode):
fr|info_node|Multi-serveurs (mode nœud) :
de|info_node|Multi-Server (Node-Modus):
es|info_node|Multiservidor (modo nodo):
it|info_node|Multi-server (modalità nodo):
pt|info_node|Multi-servidor (modo nó):
nl|info_node|Multi-server (node-modus):
ru|info_node|Несколько серверов (режим узла):
zh|info_node|多服务器（节点模式）：
ar|info_node|خوادم متعددة (وضع العقدة):
en|info_waf|ToutWAF (vendor WAF, full summary: /etc/toutwaf/INSTALL-SUMMARY.txt):
fr|info_waf|ToutWAF (WAF de l'éditeur, récapitulatif complet : /etc/toutwaf/INSTALL-SUMMARY.txt) :
de|info_waf|ToutWAF (WAF des Herstellers, vollständige Übersicht: /etc/toutwaf/INSTALL-SUMMARY.txt):
es|info_waf|ToutWAF (WAF del editor, resumen completo: /etc/toutwaf/INSTALL-SUMMARY.txt):
it|info_waf|ToutWAF (WAF dell'editore, riepilogo completo: /etc/toutwaf/INSTALL-SUMMARY.txt):
pt|info_waf|ToutWAF (WAF do editor, resumo completo: /etc/toutwaf/INSTALL-SUMMARY.txt):
nl|info_waf|ToutWAF (WAF van de uitgever, volledig overzicht: /etc/toutwaf/INSTALL-SUMMARY.txt):
ru|info_waf|ToutWAF (WAF разработчика, полная сводка: /etc/toutwaf/INSTALL-SUMMARY.txt):
zh|info_waf|ToutWAF（发行方 WAF，完整摘要：/etc/toutwaf/INSTALL-SUMMARY.txt）：
ar|info_waf|ToutWAF (WAF الناشر، الملخص الكامل: /etc/toutwaf/INSTALL-SUMMARY.txt):
en|done_update|ToutPanel is up to date!
fr|done_update|ToutPanel est à jour !
de|done_update|ToutPanel ist auf dem neuesten Stand!
es|done_update|¡ToutPanel está actualizado!
it|done_update|ToutPanel è aggiornato!
pt|done_update|O ToutPanel está atualizado!
nl|done_update|ToutPanel is bijgewerkt!
ru|done_update|ToutPanel обновлён!
zh|done_update|ToutPanel 已是最新版本！
ar|done_update|ToutPanel محدّث!
en|done_install|ToutPanel is installed!
fr|done_install|ToutPanel est installé !
de|done_install|ToutPanel ist installiert!
es|done_install|¡ToutPanel está instalado!
it|done_install|ToutPanel è installato!
pt|done_install|O ToutPanel está instalado!
nl|done_install|ToutPanel is geïnstalleerd!
ru|done_install|ToutPanel установлен!
zh|done_install|ToutPanel 已安装！
ar|done_install|تم تثبيت ToutPanel!
en|panel_not_up_yet|Warning: the panel is not responding yet. Check "journalctl -u toutpanel -n 30" then run "systemctl restart toutpanel".
fr|panel_not_up_yet|Attention : le panel ne répond pas encore. Consultez « journalctl -u toutpanel -n 30 » puis « systemctl restart toutpanel ».
de|panel_not_up_yet|Achtung: Das Panel antwortet noch nicht. Prüfen Sie „journalctl -u toutpanel -n 30“ und führen Sie dann „systemctl restart toutpanel“ aus.
es|panel_not_up_yet|Atención: el panel aún no responde. Consulte «journalctl -u toutpanel -n 30» y luego ejecute «systemctl restart toutpanel».
it|panel_not_up_yet|Attenzione: il pannello non risponde ancora. Consultare «journalctl -u toutpanel -n 30» e poi eseguire «systemctl restart toutpanel».
pt|panel_not_up_yet|Atenção: o painel ainda não responde. Consulte «journalctl -u toutpanel -n 30» e depois execute «systemctl restart toutpanel».
nl|panel_not_up_yet|Let op: het paneel reageert nog niet. Bekijk "journalctl -u toutpanel -n 30" en voer daarna "systemctl restart toutpanel" uit.
ru|panel_not_up_yet|Внимание: панель пока не отвечает. Проверьте «journalctl -u toutpanel -n 30», затем выполните «systemctl restart toutpanel».
zh|panel_not_up_yet|注意：面板尚未响应。请查看“journalctl -u toutpanel -n 30”，然后运行“systemctl restart toutpanel”。
ar|panel_not_up_yet|تنبيه: لا تستجيب اللوحة بعد. راجع "journalctl -u toutpanel -n 30" ثم شغّل "systemctl restart toutpanel".
en|update_kept|Accounts, settings, sites and software kept; data backup: %s
fr|update_kept|Comptes, réglages, sites et logiciels conservés ; sauvegarde des données : %s
de|update_kept|Konten, Einstellungen, Websites und Software bleiben erhalten; Datensicherung: %s
es|update_kept|Se conservan cuentas, ajustes, sitios y software; copia de seguridad de los datos: %s
it|update_kept|Account, impostazioni, siti e software conservati; backup dei dati: %s
pt|update_kept|Contas, definições, sites e software mantidos; cópia de segurança dos dados: %s
nl|update_kept|Accounts, instellingen, sites en software behouden; back-up van de gegevens: %s
ru|update_kept|Учётные записи, настройки, сайты и программы сохранены; резервная копия данных: %s
zh|update_kept|已保留账户、设置、站点和软件；数据备份：%s
ar|update_kept|تم الاحتفاظ بالحسابات والإعدادات والمواقع والبرامج؛ النسخة الاحتياطية للبيانات: %s
en|from_network|(from your network)
fr|from_network|(depuis votre réseau)
de|from_network|(aus Ihrem Netzwerk)
es|from_network|(desde su red)
it|from_network|(dalla vostra rete)
pt|from_network|(a partir da sua rede)
nl|from_network|(vanuit uw netwerk)
ru|from_network|(из вашей сети)
zh|from_network|（在您的网络内）
ar|from_network|(من شبكتك)
en|php_ready|(Nginx + PHP-FPM ready)
fr|php_ready|(Nginx + PHP-FPM prêts)
de|php_ready|(Nginx + PHP-FPM bereit)
es|php_ready|(Nginx + PHP-FPM listos)
it|php_ready|(Nginx + PHP-FPM pronti)
pt|php_ready|(Nginx + PHP-FPM prontos)
nl|php_ready|(Nginx + PHP-FPM gereed)
ru|php_ready|(Nginx + PHP-FPM готовы)
zh|php_ready|（Nginx + PHP-FPM 已就绪）
ar|php_ready|(Nginx + PHP-FPM جاهزان)
en|setup_note|This link (24 h, single use) lets you change the panel address, the username and the password generated above.
fr|setup_note|Ce lien (24 h, une seule utilisation) permet de changer l'adresse du panel, l'utilisateur et le mot de passe générés ci-dessus.
de|setup_note|Mit diesem Link (24 h, einmalig) können Sie die Adresse des Panels sowie den oben erzeugten Benutzernamen und das Passwort ändern.
es|setup_note|Este enlace (24 h, un solo uso) permite cambiar la dirección del panel, el usuario y la contraseña generados arriba.
it|setup_note|Questo link (24 h, uso singolo) consente di modificare l'indirizzo del pannello, il nome utente e la password generati sopra.
pt|setup_note|Esta ligação (24 h, utilização única) permite alterar o endereço do painel, o utilizador e a senha gerados acima.
nl|setup_note|Met deze link (24 u, eenmalig) kunt u het adres van het paneel en de hierboven gegenereerde gebruikersnaam en het wachtwoord wijzigen.
ru|setup_note|По этой ссылке (24 ч, однократно) можно изменить адрес панели, а также созданные выше имя пользователя и пароль.
zh|setup_note|此链接（24 小时内一次性有效）可用于修改面板地址以及上面生成的用户名和密码。
ar|setup_note|يتيح هذا الرابط (24 ساعة، استخدام واحد) تغيير عنوان اللوحة واسم المستخدم وكلمة المرور المُنشأين أعلاه.
en|setup_new_link|New link: toutpanel setup-link
fr|setup_new_link|Nouveau lien : toutpanel setup-link
de|setup_new_link|Neuer Link: toutpanel setup-link
es|setup_new_link|Nuevo enlace: toutpanel setup-link
it|setup_new_link|Nuovo link: toutpanel setup-link
pt|setup_new_link|Nova ligação: toutpanel setup-link
nl|setup_new_link|Nieuwe link: toutpanel setup-link
ru|setup_new_link|Новая ссылка: toutpanel setup-link
zh|setup_new_link|新链接：toutpanel setup-link
ar|setup_new_link|رابط جديد: toutpanel setup-link
en|node_summary|Multi-server — to enter on the master panel (System → Servers → Add):
fr|node_summary|Multi-serveurs — à saisir sur le panel maître (Système → Serveurs → Ajouter) :
de|node_summary|Multi-Server — auf dem Master-Panel einzugeben (System → Server → Hinzufügen):
es|node_summary|Multiservidor — para introducir en el panel maestro (Sistema → Servidores → Añadir):
it|node_summary|Multi-server — da inserire nel pannello master (Sistema → Server → Aggiungi):
pt|node_summary|Multi-servidor — a introduzir no painel principal (Sistema → Servidores → Adicionar):
nl|node_summary|Multi-server — in te voeren op het hoofdpaneel (Systeem → Servers → Toevoegen):
ru|node_summary|Несколько серверов — ввести на главной панели (Система → Серверы → Добавить):
zh|node_summary|多服务器 — 在主面板中输入（系统 → 服务器 → 添加）：
ar|node_summary|خوادم متعددة — تُدخل في اللوحة الرئيسية (النظام → الخوادم → إضافة):
en|waf_summary|ToutWAF (vendor WAF) — secret console links, credentials in /etc/toutwaf/INSTALL-SUMMARY.txt:
fr|waf_summary|ToutWAF (WAF de l'éditeur) — liens secrets de la console, identifiants dans /etc/toutwaf/INSTALL-SUMMARY.txt :
de|waf_summary|ToutWAF (WAF des Herstellers) — geheime Konsolen-Links, Zugangsdaten in /etc/toutwaf/INSTALL-SUMMARY.txt:
es|waf_summary|ToutWAF (WAF del editor) — enlaces secretos de la consola, credenciales en /etc/toutwaf/INSTALL-SUMMARY.txt:
it|waf_summary|ToutWAF (WAF dell'editore) — link segreti della console, credenziali in /etc/toutwaf/INSTALL-SUMMARY.txt:
pt|waf_summary|ToutWAF (WAF do editor) — ligações secretas da consola, credenciais em /etc/toutwaf/INSTALL-SUMMARY.txt:
nl|waf_summary|ToutWAF (WAF van de uitgever) — geheime consolelinks, inloggegevens in /etc/toutwaf/INSTALL-SUMMARY.txt:
ru|waf_summary|ToutWAF (WAF разработчика) — секретные ссылки на консоль, учётные данные в /etc/toutwaf/INSTALL-SUMMARY.txt:
zh|waf_summary|ToutWAF（发行方 WAF）— 控制台秘密链接，凭据见 /etc/toutwaf/INSTALL-SUMMARY.txt：
ar|waf_summary|ToutWAF (WAF الناشر) — روابط سرية للواجهة، وبيانات الاعتماد في /etc/toutwaf/INSTALL-SUMMARY.txt:
en|saved_in|This information is saved in: %s
fr|saved_in|Ces informations sont enregistrées dans : %s
de|saved_in|Diese Informationen sind gespeichert in: %s
es|saved_in|Esta información se guarda en: %s
it|saved_in|Queste informazioni sono salvate in: %s
pt|saved_in|Estas informações estão guardadas em: %s
nl|saved_in|Deze gegevens zijn opgeslagen in: %s
ru|saved_in|Эти сведения сохранены в: %s
zh|saved_in|这些信息已保存在：%s
ar|saved_in|حُفظت هذه المعلومات في: %s
en|entrance_note|The URL contains the secure entrance: without it, the panel answers 404.
fr|entrance_note|L'URL contient l'entrée sécurisée : sans elle, le panel répond 404.
de|entrance_note|Die URL enthält den gesicherten Zugang: Ohne ihn antwortet das Panel mit 404.
es|entrance_note|La URL contiene la entrada segura: sin ella, el panel responde 404.
it|entrance_note|L'URL contiene l'ingresso sicuro: senza di esso, il pannello risponde 404.
pt|entrance_note|O URL contém a entrada segura: sem ela, o painel responde 404.
nl|entrance_note|De URL bevat de beveiligde toegang: zonder deze antwoordt het paneel met 404.
ru|entrance_note|URL содержит защищённый вход: без него панель отвечает 404.
zh|entrance_note|URL 中包含安全入口：缺少它时面板返回 404。
ar|entrance_note|يحتوي عنوان URL على المدخل الآمن: بدونه تُرجع اللوحة الخطأ 404.
en|kept_value|(kept)
fr|kept_value|(conservé)
de|kept_value|(unverändert)
es|kept_value|(conservado)
it|kept_value|(invariato)
pt|kept_value|(mantido)
nl|kept_value|(behouden)
ru|kept_value|(без изменений)
zh|kept_value|（保持不变）
ar|kept_value|(دون تغيير)
en|downloading|Downloading %s
fr|downloading|Téléchargement %s
de|downloading|Herunterladen von %s
es|downloading|Descargando %s
it|downloading|Download di %s
pt|downloading|A transferir %s
nl|downloading|%s wordt gedownload
ru|downloading|Загрузка %s
zh|downloading|正在下载 %s
ar|downloading|تنزيل %s
en|python_installing|Installing Python %s from python.org…
fr|python_installing|Installation de Python %s depuis python.org…
de|python_installing|Installation von Python %s von python.org…
es|python_installing|Instalando Python %s desde python.org…
it|python_installing|Installazione di Python %s da python.org…
pt|python_installing|A instalar o Python %s a partir de python.org…
nl|python_installing|Python %s wordt geïnstalleerd vanaf python.org…
ru|python_installing|Установка Python %s с python.org…
zh|python_installing|正在从 python.org 安装 Python %s…
ar|python_installing|تثبيت بايثون %s من python.org…
en|python_missing|Python not found after installation. Install Python 3.9+ manually then run again.
fr|python_missing|Python introuvable après installation. Installez Python 3.9+ manuellement puis relancez.
de|python_missing|Python nach der Installation nicht gefunden. Installieren Sie Python 3.9+ manuell und starten Sie erneut.
es|python_missing|Python no encontrado tras la instalación. Instale Python 3.9+ manualmente y vuelva a ejecutar.
it|python_missing|Python non trovato dopo l'installazione. Installare Python 3.9+ manualmente e rilanciare.
pt|python_missing|Python não encontrado após a instalação. Instale o Python 3.9+ manualmente e execute novamente.
nl|python_missing|Python niet gevonden na de installatie. Installeer Python 3.9+ handmatig en start opnieuw.
ru|python_missing|Python не найден после установки. Установите Python 3.9+ вручную и запустите снова.
zh|python_missing|安装后仍未找到 Python。请手动安装 Python 3.9+ 后重新运行。
ar|python_missing|لم يُعثر على بايثون بعد التثبيت. ثبّت Python 3.9 أو أحدث يدويًا ثم أعد التشغيل.
en|python_found|Python: %s
fr|python_found|Python : %s
de|python_found|Python: %s
es|python_found|Python: %s
it|python_found|Python: %s
pt|python_found|Python: %s
nl|python_found|Python: %s
ru|python_found|Python: %s
zh|python_found|Python：%s
ar|python_found|بايثون: %s
en|st_python|Python
fr|st_python|Python
de|st_python|Python
es|st_python|Python
it|st_python|Python
pt|st_python|Python
nl|st_python|Python
ru|st_python|Python
zh|st_python|Python
ar|st_python|Python
en|archive_empty|Source archive empty or unreadable.
fr|archive_empty|Archive des sources vide ou illisible.
de|archive_empty|Quellarchiv leer oder nicht lesbar.
es|archive_empty|Archivo de fuentes vacío o ilegible.
it|archive_empty|Archivio dei sorgenti vuoto o illeggibile.
pt|archive_empty|Arquivo do código-fonte vazio ou ilegível.
nl|archive_empty|Bronarchief leeg of onleesbaar.
ru|archive_empty|Архив исходников пуст или не читается.
zh|archive_empty|源码归档为空或无法读取。
ar|archive_empty|أرشيف الشيفرة المصدرية فارغ أو غير قابل للقراءة.
en|pip_failed|Cannot install the panel and its Python dependencies (pip, code %s): check access to pypi.org then run again.
fr|pip_failed|Installation du panel et de ses dépendances Python impossible (pip, code %s) : vérifiez l'accès à pypi.org puis relancez.
de|pip_failed|Installation des Panels und seiner Python-Abhängigkeiten nicht möglich (pip, Code %s): Zugriff auf pypi.org prüfen und erneut starten.
es|pip_failed|No se puede instalar el panel ni sus dependencias de Python (pip, código %s): compruebe el acceso a pypi.org y vuelva a ejecutar.
it|pip_failed|Impossibile installare il pannello e le sue dipendenze Python (pip, codice %s): verificare l'accesso a pypi.org e rilanciare.
pt|pip_failed|Não é possível instalar o painel e as suas dependências Python (pip, código %s): verifique o acesso a pypi.org e execute novamente.
nl|pip_failed|Kan het paneel en de Python-afhankelijkheden niet installeren (pip, code %s): controleer de toegang tot pypi.org en start opnieuw.
ru|pip_failed|Не удаётся установить панель и её зависимости Python (pip, код %s): проверьте доступ к pypi.org и запустите снова.
zh|pip_failed|无法安装面板及其 Python 依赖（pip，代码 %s）：请检查对 pypi.org 的访问后重新运行。
ar|pip_failed|تعذّر تثبيت اللوحة واعتمادياتها في بايثون (pip، الرمز %s): تحقق من الوصول إلى pypi.org ثم أعد التشغيل.
en|pip_reinstall_failed|Cannot reinstall the panel package (pip, code %s).
fr|pip_reinstall_failed|Réinstallation du paquet du panel impossible (pip, code %s).
de|pip_reinstall_failed|Neuinstallation des Panel-Pakets nicht möglich (pip, Code %s).
es|pip_reinstall_failed|No se puede reinstalar el paquete del panel (pip, código %s).
it|pip_reinstall_failed|Impossibile reinstallare il pacchetto del pannello (pip, codice %s).
pt|pip_reinstall_failed|Não é possível reinstalar o pacote do painel (pip, código %s).
nl|pip_reinstall_failed|Kan het paneelpakket niet opnieuw installeren (pip, code %s).
ru|pip_reinstall_failed|Не удаётся переустановить пакет панели (pip, код %s).
zh|pip_reinstall_failed|无法重新安装面板软件包（pip，代码 %s）。
ar|pip_reinstall_failed|تعذّرت إعادة تثبيت حزمة اللوحة (pip، الرمز %s).
en|st_nginx_win|Nginx %s
fr|st_nginx_win|Nginx %s
de|st_nginx_win|Nginx %s
es|st_nginx_win|Nginx %s
it|st_nginx_win|Nginx %s
pt|st_nginx_win|Nginx %s
nl|st_nginx_win|Nginx %s
ru|st_nginx_win|Nginx %s
zh|st_nginx_win|Nginx %s
ar|st_nginx_win|Nginx %s
en|nginx_installed|Nginx installed in %s (automatic start).
fr|nginx_installed|Nginx installé dans %s (démarrage automatique).
de|nginx_installed|Nginx in %s installiert (automatischer Start).
es|nginx_installed|Nginx instalado en %s (inicio automático).
it|nginx_installed|Nginx installato in %s (avvio automatico).
pt|nginx_installed|Nginx instalado em %s (arranque automático).
nl|nginx_installed|Nginx geïnstalleerd in %s (automatisch starten).
ru|nginx_installed|Nginx установлен в %s (автозапуск).
zh|nginx_installed|Nginx 已安装到 %s（自动启动）。
ar|nginx_installed|تم تثبيت Nginx في %s (تشغيل تلقائي).
en|st_php_win|PHP %s (windows.php.net, php-cgi managed by the panel)
fr|st_php_win|PHP %s (windows.php.net, php-cgi géré par le panel)
de|st_php_win|PHP %s (windows.php.net, php-cgi vom Panel verwaltet)
es|st_php_win|PHP %s (windows.php.net, php-cgi gestionado por el panel)
it|st_php_win|PHP %s (windows.php.net, php-cgi gestito dal pannello)
pt|st_php_win|PHP %s (windows.php.net, php-cgi gerido pelo painel)
nl|st_php_win|PHP %s (windows.php.net, php-cgi beheerd door het paneel)
ru|st_php_win|PHP %s (windows.php.net, php-cgi управляется панелью)
zh|st_php_win|PHP %s（windows.php.net，php-cgi 由面板管理）
ar|st_php_win|PHP %s (windows.php.net، تدير اللوحة php-cgi)
en|php_failed_win|PHP %s not installed: retry from the panel's PHP page.
fr|php_failed_win|PHP %s non installé : réessayez depuis la page PHP du panel.
de|php_failed_win|PHP %s nicht installiert: erneut über die PHP-Seite des Panels versuchen.
es|php_failed_win|PHP %s no instalado: reintente desde la página PHP del panel.
it|php_failed_win|PHP %s non installato: riprovare dalla pagina PHP del pannello.
pt|php_failed_win|PHP %s não instalado: tente novamente na página PHP do painel.
nl|php_failed_win|PHP %s niet geïnstalleerd: probeer opnieuw via de PHP-pagina van het paneel.
ru|php_failed_win|PHP %s не установлен: повторите на странице PHP панели.
zh|php_failed_win|PHP %s 未安装：请在面板的 PHP 页面重试。
ar|php_failed_win|لم يُثبَّت PHP %s: أعد المحاولة من صفحة PHP في اللوحة.
en|st_mariadb_win|MariaDB %s
fr|st_mariadb_win|MariaDB %s
de|st_mariadb_win|MariaDB %s
es|st_mariadb_win|MariaDB %s
it|st_mariadb_win|MariaDB %s
pt|st_mariadb_win|MariaDB %s
nl|st_mariadb_win|MariaDB %s
ru|st_mariadb_win|MariaDB %s
zh|st_mariadb_win|MariaDB %s
ar|st_mariadb_win|MariaDB %s
en|mariadb_installed_win|MariaDB installed (MariaDB service), root password saved in the panel.
fr|mariadb_installed_win|MariaDB installée (service MariaDB), mot de passe root enregistré dans le panel.
de|mariadb_installed_win|MariaDB installiert (Dienst MariaDB), Root-Passwort im Panel gespeichert.
es|mariadb_installed_win|MariaDB instalada (servicio MariaDB), contraseña root guardada en el panel.
it|mariadb_installed_win|MariaDB installato (servizio MariaDB), password root salvata nel pannello.
pt|mariadb_installed_win|MariaDB instalado (serviço MariaDB), senha root guardada no painel.
nl|mariadb_installed_win|MariaDB geïnstalleerd (service MariaDB), rootwachtwoord opgeslagen in het paneel.
ru|mariadb_installed_win|MariaDB установлена (служба MariaDB), пароль root сохранён в панели.
zh|mariadb_installed_win|MariaDB 已安装（MariaDB 服务），root 密码已保存到面板。
ar|mariadb_installed_win|تم تثبيت MariaDB (خدمة MariaDB) وحُفظت كلمة مرور root في اللوحة.
en|mariadb_present|MariaDB service already present.
fr|mariadb_present|Service MariaDB déjà présent.
de|mariadb_present|Dienst MariaDB bereits vorhanden.
es|mariadb_present|Servicio MariaDB ya presente.
it|mariadb_present|Servizio MariaDB già presente.
pt|mariadb_present|Serviço MariaDB já presente.
nl|mariadb_present|Service MariaDB al aanwezig.
ru|mariadb_present|Служба MariaDB уже установлена.
zh|mariadb_present|MariaDB 服务已存在。
ar|mariadb_present|خدمة MariaDB موجودة مسبقًا.
en|st_migrate_win|Database migration
fr|st_migrate_win|Migration de la base
de|st_migrate_win|Datenbankmigration
es|st_migrate_win|Migración de la base de datos
it|st_migrate_win|Migrazione del database
pt|st_migrate_win|Migração da base de dados
nl|st_migrate_win|Databasemigratie
ru|st_migrate_win|Миграция базы
zh|st_migrate_win|数据库迁移
ar|st_migrate_win|ترحيل قاعدة البيانات
en|st_task|Service (scheduled task)
fr|st_task|Service (tâche planifiée)
de|st_task|Dienst (geplante Aufgabe)
es|st_task|Servicio (tarea programada)
it|st_task|Servizio (attività pianificata)
pt|st_task|Serviço (tarefa agendada)
nl|st_task|Service (geplande taak)
ru|st_task|Служба (запланированная задача)
zh|st_task|服务（计划任务）
ar|st_task|الخدمة (مهمة مجدولة)
en|task_created|Scheduled task 'ToutPanel' created and started (automatic start).
fr|task_created|Tâche planifiée 'ToutPanel' créée et lancée (démarrage automatique).
de|task_created|Geplante Aufgabe 'ToutPanel' erstellt und gestartet (automatischer Start).
es|task_created|Tarea programada 'ToutPanel' creada e iniciada (inicio automático).
it|task_created|Attività pianificata 'ToutPanel' creata e avviata (avvio automatico).
pt|task_created|Tarefa agendada 'ToutPanel' criada e iniciada (arranque automático).
nl|task_created|Geplande taak 'ToutPanel' aangemaakt en gestart (automatisch starten).
ru|task_created|Запланированная задача 'ToutPanel' создана и запущена (автозапуск).
zh|task_created|计划任务“ToutPanel”已创建并启动（自动启动）。
ar|task_created|تم إنشاء المهمة المجدولة 'ToutPanel' وتشغيلها (تشغيل تلقائي).
en|bad_version|Invalid version: %s (expected X.Y.Z, vX.Y.Z or a pre-release such as 0.4.0b1 or 0.4.0-beta.1)
fr|bad_version|Version invalide : %s (attendu : X.Y.Z, vX.Y.Z ou une préversion comme 0.4.0b1 ou 0.4.0-beta.1)
de|bad_version|Ungültige Version: %s (erwartet: X.Y.Z, vX.Y.Z oder eine Vorabversion wie 0.4.0b1 oder 0.4.0-beta.1)
es|bad_version|Versión no válida: %s (se espera X.Y.Z, vX.Y.Z o una preversión como 0.4.0b1 o 0.4.0-beta.1)
it|bad_version|Versione non valida: %s (atteso: X.Y.Z, vX.Y.Z o una pre-release come 0.4.0b1 o 0.4.0-beta.1)
pt|bad_version|Versão inválida: %s (esperado: X.Y.Z, vX.Y.Z ou uma pré-versão como 0.4.0b1 ou 0.4.0-beta.1)
nl|bad_version|Ongeldige versie: %s (verwacht: X.Y.Z, vX.Y.Z of een voorversie zoals 0.4.0b1 of 0.4.0-beta.1)
ru|bad_version|Недопустимая версия: %s (ожидается X.Y.Z, vX.Y.Z или предварительная версия, например 0.4.0b1 или 0.4.0-beta.1)
zh|bad_version|版本无效：%s（应为 X.Y.Z、vX.Y.Z 或预发布版本，如 0.4.0b1 或 0.4.0-beta.1）
ar|bad_version|إصدار غير صالح: %s (المتوقع X.Y.Z أو vX.Y.Z أو إصدار تجريبي مثل 0.4.0b1 أو 0.4.0-beta.1)
en|versions_title|Published versions (most recent first):
fr|versions_title|Versions publiées (la plus récente d'abord) :
de|versions_title|Veröffentlichte Versionen (neueste zuerst):
es|versions_title|Versiones publicadas (la más reciente primero):
it|versions_title|Versioni pubblicate (la più recente per prima):
pt|versions_title|Versões publicadas (a mais recente primeiro):
nl|versions_title|Gepubliceerde versies (nieuwste eerst):
ru|versions_title|Опубликованные версии (сначала новые):
zh|versions_title|已发布的版本（最新的在前）：
ar|versions_title|الإصدارات المنشورة (الأحدث أولًا):
en|versions_none|No published version found in %s
fr|versions_none|Aucune version publiée trouvée dans %s
de|versions_none|Keine veröffentlichte Version in %s gefunden
es|versions_none|No se encontró ninguna versión publicada en %s
it|versions_none|Nessuna versione pubblicata trovata in %s
pt|versions_none|Nenhuma versão publicada encontrada em %s
nl|versions_none|Geen gepubliceerde versie gevonden in %s
ru|versions_none|В %s не найдено опубликованных версий
zh|versions_none|在 %s 中未找到已发布的版本
ar|versions_none|لم يُعثر على أي إصدار منشور في %s
en|ver_stable|stable
fr|ver_stable|stable
de|ver_stable|stabil
es|ver_stable|estable
it|ver_stable|stabile
pt|ver_stable|estável
nl|ver_stable|stabiel
ru|ver_stable|стабильная
zh|ver_stable|稳定版
ar|ver_stable|مستقر
en|ver_dev|dev
fr|ver_dev|dev
de|ver_dev|dev
es|ver_dev|dev
it|ver_dev|dev
pt|ver_dev|dev
nl|ver_dev|dev
ru|ver_dev|dev
zh|ver_dev|开发版
ar|ver_dev|تطوير
en|version_need_git|git is required to look up versions: install it first.
fr|version_need_git|git est requis pour chercher les versions : installez-le d'abord.
de|version_need_git|git wird zur Versionssuche benötigt: bitte zuerst installieren.
es|version_need_git|git es necesario para buscar versiones: instálelo primero.
it|version_need_git|git è necessario per cercare le versioni: installatelo prima.
pt|version_need_git|o git é necessário para procurar versões: instale-o primeiro.
nl|version_need_git|git is nodig om versies op te zoeken: installeer het eerst.
ru|version_need_git|для поиска версий нужен git: сначала установите его.
zh|version_need_git|查找版本需要 git：请先安装。
ar|version_need_git|يلزم git للبحث عن الإصدارات: ثبّته أولًا.
en|version_git_install|Installing git to look up versions…
fr|version_git_install|Installation de git pour chercher les versions…
de|version_git_install|git wird für die Versionssuche installiert…
es|version_git_install|Instalando git para buscar versiones…
it|version_git_install|Installazione di git per cercare le versioni…
pt|version_git_install|A instalar o git para procurar versões…
nl|version_git_install|git wordt geïnstalleerd om versies op te zoeken…
ru|version_git_install|Установка git для поиска версий…
zh|version_git_install|正在安装 git 以查找版本…
ar|version_git_install|جارٍ تثبيت git للبحث عن الإصدارات…
en|version_net_fail|Cannot read the version history of %s (network or repository error).
fr|version_net_fail|Impossible de lire l'historique des versions de %s (erreur réseau ou de dépôt).
de|version_net_fail|Der Versionsverlauf von %s kann nicht gelesen werden (Netzwerk- oder Repository-Fehler).
es|version_net_fail|No se puede leer el historial de versiones de %s (error de red o de repositorio).
it|version_net_fail|Impossibile leggere la cronologia delle versioni di %s (errore di rete o di repository).
pt|version_net_fail|Não é possível ler o histórico de versões de %s (erro de rede ou de repositório).
nl|version_net_fail|De versiegeschiedenis van %s kan niet worden gelezen (netwerk- of repositoryfout).
ru|version_net_fail|Не удалось прочитать историю версий %s (ошибка сети или репозитория).
zh|version_net_fail|无法读取 %s 的版本历史（网络或仓库错误）。
ar|version_net_fail|تعذّرت قراءة سجل إصدارات %s (خطأ في الشبكة أو المستودع).
en|version_not_found|Version %s not found in %s. Available versions:
fr|version_not_found|Version %s introuvable dans %s. Versions disponibles :
de|version_not_found|Version %s in %s nicht gefunden. Verfügbare Versionen:
es|version_not_found|Versión %s no encontrada en %s. Versiones disponibles:
it|version_not_found|Versione %s non trovata in %s. Versioni disponibili:
pt|version_not_found|Versão %s não encontrada em %s. Versões disponíveis:
nl|version_not_found|Versie %s niet gevonden in %s. Beschikbare versies:
ru|version_not_found|Версия %s не найдена в %s. Доступные версии:
zh|version_not_found|在 %s 中未找到版本 %s。可用版本：
ar|version_not_found|الإصدار %s غير موجود في %s. الإصدارات المتاحة:
en|version_resolved|Version %s found (commit %s, %s)
fr|version_resolved|Version %s trouvée (commit %s, %s)
de|version_resolved|Version %s gefunden (Commit %s, %s)
es|version_resolved|Versión %s encontrada (commit %s, %s)
it|version_resolved|Versione %s trovata (commit %s, %s)
pt|version_resolved|Versão %s encontrada (commit %s, %s)
nl|version_resolved|Versie %s gevonden (commit %s, %s)
ru|version_resolved|Версия %s найдена (коммит %s, %s)
zh|version_resolved|已找到版本 %s（提交 %s，%s）
ar|version_resolved|تم العثور على الإصدار %s (الإيداع %s، %s)
en|version_no_wheel|Version %s has no package for Python %s. Python versions supported by this release: %s
fr|version_no_wheel|La version %s n'a pas de paquet pour Python %s. Python pris en charge par cette version : %s
de|version_no_wheel|Version %s enthält kein Paket für Python %s. Von dieser Version unterstützte Python-Versionen: %s
es|version_no_wheel|La versión %s no tiene paquete para Python %s. Python admitido por esta versión: %s
it|version_no_wheel|La versione %s non ha un pacchetto per Python %s. Python supportato da questa versione: %s
pt|version_no_wheel|A versão %s não tem pacote para Python %s. Python suportado por esta versão: %s
nl|version_no_wheel|Versie %s heeft geen pakket voor Python %s. Door deze versie ondersteunde Python-versies: %s
ru|version_no_wheel|У версии %s нет пакета для Python %s. Поддерживаемые этой версией Python: %s
zh|version_no_wheel|版本 %s 没有适用于 Python %s 的安装包。该版本支持的 Python：%s
ar|version_no_wheel|الإصدار %s لا يحتوي على حزمة لـ Python %s. إصدارات Python المدعومة: %s
en|version_ignored|--version is ignored with --source or when the script runs from a local repository.
fr|version_ignored|--version est ignoré avec --source ou quand le script est lancé depuis un dépôt local.
de|version_ignored|--version wird mit --source oder bei Start aus einem lokalen Repository ignoriert.
es|version_ignored|--version se ignora con --source o cuando el script se ejecuta desde un repositorio local.
it|version_ignored|--version viene ignorata con --source o quando lo script è avviato da un repository locale.
pt|version_ignored|--version é ignorado com --source ou quando o script é executado a partir de um repositório local.
nl|version_ignored|--version wordt genegeerd met --source of wanneer het script vanuit een lokale repository draait.
ru|version_ignored|--version игнорируется с --source или при запуске скрипта из локального репозитория.
zh|version_ignored|使用 --source 或从本地仓库运行脚本时，将忽略 --version。
ar|version_ignored|يتم تجاهل --version مع --source أو عند تشغيل البرنامج النصي من مستودع محلي.
en|version_downgrade|Warning: downgrading from %s to %s. In update mode your data is backed up first, but the database schema only migrates forward: recent data may be unreadable by the older version.
fr|version_downgrade|Attention : retour de la version %s à la version %s. En mode mise à jour, vos données sont d'abord sauvegardées, mais le schéma de la base ne migre que vers l'avant : des données récentes peuvent être illisibles par l'ancienne version.
de|version_downgrade|Achtung: Downgrade von %s auf %s. Im Update-Modus werden Ihre Daten zuvor gesichert, das Datenbankschema wird aber nur vorwärts migriert: neuere Daten sind für die ältere Version eventuell nicht lesbar.
es|version_downgrade|Atención: se pasa de la versión %s a la %s. En modo actualización sus datos se copian antes, pero el esquema de la base solo migra hacia delante: datos recientes pueden ser ilegibles para la versión anterior.
it|version_downgrade|Attenzione: ritorno dalla versione %s alla %s. In modalità aggiornamento i dati vengono prima salvati, ma lo schema del database migra solo in avanti: dati recenti potrebbero non essere leggibili dalla versione precedente.
pt|version_downgrade|Atenção: regresso da versão %s para a %s. No modo de atualização os dados são copiados antes, mas o esquema da base só migra para a frente: dados recentes podem ficar ilegíveis para a versão anterior.
nl|version_downgrade|Let op: terug van versie %s naar %s. In updatemodus worden uw gegevens eerst geback-upt, maar het databaseschema migreert alleen vooruit: recente gegevens zijn mogelijk onleesbaar voor de oudere versie.
ru|version_downgrade|Внимание: возврат с версии %s на %s. В режиме обновления данные сначала копируются, но схема базы переносится только вперёд: свежие данные могут быть нечитаемы для старой версии.
zh|version_downgrade|警告：将从版本 %s 降级到 %s。更新模式会先备份数据，但数据库结构只会向前迁移：较新的数据可能无法被旧版本读取。
ar|version_downgrade|تحذير: الرجوع من الإصدار %s إلى %s. في وضع التحديث تُنسخ بياناتك احتياطيًا أولًا، لكن مخطط قاعدة البيانات يُرحَّل للأمام فقط: قد تتعذر قراءة البيانات الحديثة في الإصدار الأقدم.
en|ask_downgrade|Continue with the downgrade? %s
fr|ask_downgrade|Continuer le retour en arrière ? %s
de|ask_downgrade|Downgrade fortsetzen? %s
es|ask_downgrade|¿Continuar con la reversión? %s
it|ask_downgrade|Continuare con il ritorno alla versione precedente? %s
pt|ask_downgrade|Continuar com a reversão? %s
nl|ask_downgrade|Doorgaan met het terugzetten? %s
ru|ask_downgrade|Продолжить откат? %s
zh|ask_downgrade|继续降级吗？%s
ar|ask_downgrade|متابعة الرجوع إلى الإصدار الأقدم؟ %s
en|downgrade_cancelled|Downgrade cancelled.
fr|downgrade_cancelled|Retour en arrière annulé.
de|downgrade_cancelled|Downgrade abgebrochen.
es|downgrade_cancelled|Reversión cancelada.
it|downgrade_cancelled|Ritorno alla versione precedente annullato.
pt|downgrade_cancelled|Reversão cancelada.
nl|downgrade_cancelled|Terugzetten geannuleerd.
ru|downgrade_cancelled|Откат отменён.
zh|downgrade_cancelled|已取消降级。
ar|downgrade_cancelled|تم إلغاء الرجوع.
en|downgrade_no_tty|No terminal available to confirm the downgrade: re-run with --yes.
fr|downgrade_no_tty|Aucun terminal pour confirmer le retour en arrière : relancez avec --yes.
de|downgrade_no_tty|Kein Terminal zur Bestätigung des Downgrades: mit --yes erneut starten.
es|downgrade_no_tty|No hay terminal para confirmar la reversión: ejecute de nuevo con --yes.
it|downgrade_no_tty|Nessun terminale per confermare il ritorno: rilanciare con --yes.
pt|downgrade_no_tty|Sem terminal para confirmar a reversão: execute de novo com --yes.
nl|downgrade_no_tty|Geen terminal om het terugzetten te bevestigen: start opnieuw met --yes.
ru|downgrade_no_tty|Нет терминала для подтверждения отката: запустите снова с --yes.
zh|downgrade_no_tty|没有可用于确认降级的终端：请加 --yes 重新运行。
ar|downgrade_no_tty|لا توجد طرفية لتأكيد الرجوع: أعد التشغيل مع --yes.
en|version_installed_note|Installed version: %s. 'toutpanel update' offers newer versions.
fr|version_installed_note|Version installée : %s. « toutpanel update » proposera les versions plus récentes.
de|version_installed_note|Installierte Version: %s. 'toutpanel update' bietet neuere Versionen an.
es|version_installed_note|Versión instalada: %s. 'toutpanel update' ofrecerá versiones más recientes.
it|version_installed_note|Versione installata: %s. 'toutpanel update' proporrà le versioni più recenti.
pt|version_installed_note|Versão instalada: %s. 'toutpanel update' oferecerá versões mais recentes.
nl|version_installed_note|Geïnstalleerde versie: %s. 'toutpanel update' biedt nieuwere versies aan.
ru|version_installed_note|Установлена версия: %s. 'toutpanel update' предложит более новые версии.
zh|version_installed_note|已安装版本：%s。'toutpanel update' 会提供更新的版本。
ar|version_installed_note|الإصدار المثبّت: %s. سيعرض 'toutpanel update' الإصدارات الأحدث.
en|src_version|Downloading version %s (commit %s)…
fr|src_version|Téléchargement de la version %s (commit %s)…
de|src_version|Version %s wird heruntergeladen (Commit %s)…
es|src_version|Descargando la versión %s (commit %s)…
it|src_version|Download della versione %s (commit %s)…
pt|src_version|A transferir a versão %s (commit %s)…
nl|src_version|Versie %s wordt gedownload (commit %s)…
ru|src_version|Загрузка версии %s (коммит %s)…
zh|src_version|正在下载版本 %s（提交 %s）…
ar|src_version|جارٍ تنزيل الإصدار %s (الإيداع %s)…
en|version_api_limit|GitHub API rate limit reached: retry later (or set GITHUB_TOKEN).
fr|version_api_limit|Limite de débit de l'API GitHub atteinte : réessayez plus tard (ou définissez GITHUB_TOKEN).
de|version_api_limit|GitHub-API-Limit erreicht: später erneut versuchen (oder GITHUB_TOKEN setzen).
es|version_api_limit|Límite de la API de GitHub alcanzado: reintente más tarde (o defina GITHUB_TOKEN).
it|version_api_limit|Limite dell'API GitHub raggiunto: riprovare più tardi (o impostare GITHUB_TOKEN).
pt|version_api_limit|Limite da API do GitHub atingido: tente mais tarde (ou defina GITHUB_TOKEN).
nl|version_api_limit|Limiet van de GitHub-API bereikt: probeer het later opnieuw (of stel GITHUB_TOKEN in).
ru|version_api_limit|Достигнут лимит GitHub API: повторите позже (или задайте GITHUB_TOKEN).
zh|version_api_limit|已达到 GitHub API 速率限制：请稍后重试（或设置 GITHUB_TOKEN）。
ar|version_api_limit|تم بلوغ حد معدل واجهة GitHub: أعد المحاولة لاحقًا (أو عيّن GITHUB_TOKEN).
en|h_waf_section|WAF engine, remote mode: link this server to a ToutWAF installed on ANOTHER server (no local WAF is installed):
fr|h_waf_section|Moteur WAF, mode distant : relie ce serveur à un ToutWAF installé sur un AUTRE serveur (aucun WAF local n'est installé) :
de|h_waf_section|WAF-Engine, Remote-Modus: verbindet diesen Server mit einem ToutWAF auf einem ANDEREN Server (es wird keine lokale WAF installiert):
es|h_waf_section|Motor WAF, modo remoto: enlaza este servidor con un ToutWAF instalado en OTRO servidor (no se instala ningún WAF local):
it|h_waf_section|Motore WAF, modalità remota: collega questo server a un ToutWAF installato su un ALTRO server (nessun WAF locale viene installato):
pt|h_waf_section|Motor WAF, modo remoto: liga este servidor a um ToutWAF instalado noutro servidor (nenhum WAF local é instalado):
nl|h_waf_section|WAF-engine, externe modus: koppelt deze server aan een ToutWAF op een ANDERE server (er wordt geen lokale WAF geïnstalleerd):
ru|h_waf_section|Движок WAF, удалённый режим: подключает этот сервер к ToutWAF, установленному на ДРУГОМ сервере (локальный WAF не устанавливается):
zh|h_waf_section|WAF 引擎，远程模式：将此服务器连接到安装在另一台服务器上的 ToutWAF（不安装本地 WAF）：
ar|h_waf_section|محرك WAF، الوضع البعيد: يربط هذا الخادم بـ ToutWAF مثبّت على خادم آخر (لا يُثبَّت أي WAF محلي):
en|h_waf_none|none = no external WAF (default); toutwaf with --waf-console = remote ToutWAF (below)
fr|h_waf_none|none = aucun WAF externe (défaut) ; toutwaf avec --waf-console = ToutWAF distant (ci-dessous)
de|h_waf_none|none = keine externe WAF (Standard); toutwaf mit --waf-console = entferntes ToutWAF (unten)
es|h_waf_none|none = sin WAF externo (predeterminado); toutwaf con --waf-console = ToutWAF remoto (abajo)
it|h_waf_none|none = nessun WAF esterno (predefinito); toutwaf con --waf-console = ToutWAF remoto (sotto)
pt|h_waf_none|none = sem WAF externo (predefinição); toutwaf com --waf-console = ToutWAF remoto (abaixo)
nl|h_waf_none|none = geen externe WAF (standaard); toutwaf met --waf-console = externe ToutWAF (hieronder)
ru|h_waf_none|none = без внешнего WAF (по умолчанию); toutwaf с --waf-console = удалённый ToutWAF (ниже)
zh|h_waf_none|none = 不使用外部 WAF（默认）；toutwaf 加 --waf-console = 远程 ToutWAF（见下）
ar|h_waf_none|none = بلا WAF خارجي (الافتراضي)؛ toutwaf مع --waf-console = ToutWAF بعيد (أدناه)
en|h_waf_console|console of the remote ToutWAF with its secret path, e.g. https://IP:9443/<path> (also TOUTPANEL_WAF_URL); without it, --waf toutwaf installs ToutWAF locally
fr|h_waf_console|console du ToutWAF distant avec son chemin secret, ex. https://IP:9443/<chemin> (aussi TOUTPANEL_WAF_URL) ; sans elle, --waf toutwaf installe ToutWAF en local
de|h_waf_console|Konsole des entfernten ToutWAF mit geheimem Pfad, z. B. https://IP:9443/<Pfad> (auch TOUTPANEL_WAF_URL); ohne sie installiert --waf toutwaf ToutWAF lokal
es|h_waf_console|consola del ToutWAF remoto con su ruta secreta, p. ej. https://IP:9443/<ruta> (también TOUTPANEL_WAF_URL); sin ella, --waf toutwaf instala ToutWAF en local
it|h_waf_console|console del ToutWAF remoto con il suo percorso segreto, es. https://IP:9443/<percorso> (anche TOUTPANEL_WAF_URL); senza, --waf toutwaf installa ToutWAF in locale
pt|h_waf_console|consola do ToutWAF remoto com o seu caminho secreto, ex. https://IP:9443/<caminho> (também TOUTPANEL_WAF_URL); sem ela, --waf toutwaf instala o ToutWAF localmente
nl|h_waf_console|console van de externe ToutWAF met geheim pad, bijv. https://IP:9443/<pad> (ook TOUTPANEL_WAF_URL); zonder installeert --waf toutwaf ToutWAF lokaal
ru|h_waf_console|консоль удалённого ToutWAF с секретным путём, например https://IP:9443/<путь> (также TOUTPANEL_WAF_URL); без неё --waf toutwaf устанавливает ToutWAF локально
zh|h_waf_console|远程 ToutWAF 的控制台及其秘密路径，如 https://IP:9443/<路径>（也可用 TOUTPANEL_WAF_URL）；未提供时，--waf toutwaf 在本机安装 ToutWAF
ar|h_waf_console|واجهة ToutWAF البعيد مع مسارها السري، مثل https://IP:9443/<المسار> (ويمكن أيضًا TOUTPANEL_WAF_URL)؛ بدونها يثبّت --waf toutwaf ‏ToutWAF محليًا
en|h_waf_origin_ip|address of the ToutWAF as seen from this server (firewall, real visitor IP; default: resolved from the console)
fr|h_waf_origin_ip|adresse du ToutWAF vue depuis ce serveur (pare-feu, IP réelle des visiteurs ; défaut : résolue depuis la console)
de|h_waf_origin_ip|Adresse des ToutWAF, von diesem Server aus gesehen (Firewall, echte Besucher-IP; Standard: aus der Konsole aufgelöst)
es|h_waf_origin_ip|dirección del ToutWAF vista desde este servidor (cortafuegos, IP real de los visitantes; por defecto: resuelta desde la consola)
it|h_waf_origin_ip|indirizzo del ToutWAF visto da questo server (firewall, IP reale dei visitatori; predefinito: risolto dalla console)
pt|h_waf_origin_ip|endereço do ToutWAF visto a partir deste servidor (firewall, IP real dos visitantes; predefinição: resolvido a partir da consola)
nl|h_waf_origin_ip|adres van de ToutWAF gezien vanaf deze server (firewall, echt bezoeker-IP; standaard: afgeleid van de console)
ru|h_waf_origin_ip|адрес ToutWAF с точки зрения этого сервера (брандмауэр, реальный IP посетителей; по умолчанию определяется по консоли)
zh|h_waf_origin_ip|此服务器所见的 ToutWAF 地址（防火墙、访客真实 IP；默认从控制台地址解析）
ar|h_waf_origin_ip|عنوان ToutWAF كما يراه هذا الخادم (الجدار الناري، عنوان IP الحقيقي للزوار؛ الافتراضي: يُستنتج من الواجهة)
en|h_waf_origin_addr|address of this server as seen by the ToutWAF (default: detected)
fr|h_waf_origin_addr|adresse de ce serveur vue par le ToutWAF (défaut : détectée)
de|h_waf_origin_addr|Adresse dieses Servers, vom ToutWAF aus gesehen (Standard: erkannt)
es|h_waf_origin_addr|dirección de este servidor vista por el ToutWAF (por defecto: detectada)
it|h_waf_origin_addr|indirizzo di questo server visto dal ToutWAF (predefinito: rilevato)
pt|h_waf_origin_addr|endereço deste servidor visto pelo ToutWAF (predefinição: detetado)
nl|h_waf_origin_addr|adres van deze server gezien door de ToutWAF (standaard: gedetecteerd)
ru|h_waf_origin_addr|адрес этого сервера с точки зрения ToutWAF (по умолчанию определяется автоматически)
zh|h_waf_origin_addr|ToutWAF 所见的此服务器地址（默认自动检测）
ar|h_waf_origin_addr|عنوان هذا الخادم كما يراه ToutWAF (الافتراضي: يُكتشف تلقائيًا)
en|h_waf_restrict|limit ports 80/443 to the ToutWAF only (direct access is cut; asks for confirmation unless --yes)
fr|h_waf_restrict|limite les ports 80/443 au seul ToutWAF (l'accès direct est coupé ; demande confirmation sauf avec --yes)
de|h_waf_restrict|Ports 80/443 nur für das ToutWAF freigeben (direkter Zugriff wird unterbunden; fragt nach, außer mit --yes)
es|h_waf_restrict|limita los puertos 80/443 al ToutWAF (se corta el acceso directo; pide confirmación salvo con --yes)
it|h_waf_restrict|limita le porte 80/443 al solo ToutWAF (l'accesso diretto viene interrotto; chiede conferma salvo con --yes)
pt|h_waf_restrict|limita as portas 80/443 ao ToutWAF (o acesso direto é cortado; pede confirmação, exceto com --yes)
nl|h_waf_restrict|beperkt poort 80/443 tot de ToutWAF (directe toegang vervalt; vraagt bevestiging, behalve met --yes)
ru|h_waf_restrict|ограничивает порты 80/443 только для ToutWAF (прямой доступ закрывается; запрашивает подтверждение, кроме --yes)
zh|h_waf_restrict|将 80/443 端口仅限 ToutWAF 访问（切断直接访问；除非使用 --yes，否则会请求确认）
ar|h_waf_restrict|يحصر المنفذين 80/443 في ToutWAF فقط (يُقطع الوصول المباشر؛ يطلب التأكيد ما لم يُستخدم --yes)
en|h_waf_cert_mode|certificates: import (sent by the panel, default) or acme (obtained by ToutWAF)
fr|h_waf_cert_mode|certificats : import (envoyés par le panel, défaut) ou acme (obtenus par ToutWAF)
de|h_waf_cert_mode|Zertifikate: import (vom Panel gesendet, Standard) oder acme (von ToutWAF bezogen)
es|h_waf_cert_mode|certificados: import (enviados por el panel, predeterminado) o acme (obtenidos por ToutWAF)
it|h_waf_cert_mode|certificati: import (inviati dal pannello, predefinito) o acme (ottenuti da ToutWAF)
pt|h_waf_cert_mode|certificados: import (enviados pelo painel, predefinição) ou acme (obtidos pelo ToutWAF)
nl|h_waf_cert_mode|certificaten: import (door het paneel verzonden, standaard) of acme (door ToutWAF verkregen)
ru|h_waf_cert_mode|сертификаты: import (передаются панелью, по умолчанию) или acme (получает ToutWAF)
zh|h_waf_cert_mode|证书：import（由面板发送，默认）或 acme（由 ToutWAF 申请）
ar|h_waf_cert_mode|الشهادات: import (ترسلها اللوحة، الافتراضي) أو acme (يحصل عليها ToutWAF)
en|h_waf_ssl|SSL mode expected before the first heartbeat: toutwaf (default for a new link) or panel; writes nothing to ToutWAF, the heartbeat value always prevails
fr|h_waf_ssl|mode SSL attendu avant le premier heartbeat : toutwaf (défaut d'un nouveau lien) ou panel ; n'écrit rien dans ToutWAF, la valeur du heartbeat fait toujours foi
de|h_waf_ssl|vor dem ersten Heartbeat erwarteter SSL-Modus: toutwaf (Standard bei neuer Verbindung) oder panel; schreibt nichts in ToutWAF, der Wert des Heartbeats gilt immer
es|h_waf_ssl|modo SSL esperado antes del primer heartbeat: toutwaf (predeterminado en un enlace nuevo) o panel; no escribe nada en ToutWAF, el valor del heartbeat siempre prevalece
it|h_waf_ssl|modalità SSL attesa prima del primo heartbeat: toutwaf (predefinita per un nuovo collegamento) o panel; non scrive nulla in ToutWAF, prevale sempre il valore del heartbeat
pt|h_waf_ssl|modo SSL esperado antes do primeiro heartbeat: toutwaf (predefinição de uma nova ligação) ou panel; não escreve nada no ToutWAF, o valor do heartbeat prevalece sempre
nl|h_waf_ssl|SSL-modus die vóór de eerste heartbeat wordt verwacht: toutwaf (standaard bij een nieuwe koppeling) of panel; schrijft niets naar ToutWAF, de waarde van de heartbeat geldt altijd
ru|h_waf_ssl|режим SSL, ожидаемый до первого heartbeat: toutwaf (по умолчанию для новой связи) или panel; ничего не записывает в ToutWAF, значение из heartbeat всегда главнее
zh|h_waf_ssl|首次心跳之前预期的 SSL 模式：toutwaf（新连接的默认值）或 panel；不会向 ToutWAF 写入任何内容，始终以心跳返回的值为准
ar|h_waf_ssl|وضع SSL المتوقع قبل أول heartbeat: toutwaf (الافتراضي لربط جديد) أو panel؛ لا يكتب شيئًا في ToutWAF، والقيمة القادمة من heartbeat هي المعتمدة دائمًا
en|h_waf_server_id|identifier of this server in ToutWAF, for the status heartbeat (also TOUTPANEL_WAF_SERVER_ID)
fr|h_waf_server_id|identifiant de ce serveur dans ToutWAF, pour le signal d'état (aussi TOUTPANEL_WAF_SERVER_ID)
de|h_waf_server_id|Kennung dieses Servers in ToutWAF für das Statussignal (auch TOUTPANEL_WAF_SERVER_ID)
es|h_waf_server_id|identificador de este servidor en ToutWAF, para la señal de estado (también TOUTPANEL_WAF_SERVER_ID)
it|h_waf_server_id|identificativo di questo server in ToutWAF, per il segnale di stato (anche TOUTPANEL_WAF_SERVER_ID)
pt|h_waf_server_id|identificador deste servidor no ToutWAF, para o sinal de estado (também TOUTPANEL_WAF_SERVER_ID)
nl|h_waf_server_id|id van deze server in ToutWAF, voor het statussignaal (ook TOUTPANEL_WAF_SERVER_ID)
ru|h_waf_server_id|идентификатор этого сервера в ToutWAF для сигнала состояния (также TOUTPANEL_WAF_SERVER_ID)
zh|h_waf_server_id|此服务器在 ToutWAF 中的标识，用于状态心跳（也可用 TOUTPANEL_WAF_SERVER_ID）
ar|h_waf_server_id|معرّف هذا الخادم في ToutWAF لإشارة الحالة (ويمكن أيضًا TOUTPANEL_WAF_SERVER_ID)
en|h_waf_fingerprint|SHA-256 fingerprint of the console certificate, sha256:... (also TOUTPANEL_WAF_PIN); not a secret
fr|h_waf_fingerprint|empreinte SHA-256 du certificat de la console, sha256:... (aussi TOUTPANEL_WAF_PIN) ; n'est pas un secret
de|h_waf_fingerprint|SHA-256-Fingerabdruck des Konsolenzertifikats, sha256:... (auch TOUTPANEL_WAF_PIN); kein Geheimnis
es|h_waf_fingerprint|huella SHA-256 del certificado de la consola, sha256:... (también TOUTPANEL_WAF_PIN); no es un secreto
it|h_waf_fingerprint|impronta SHA-256 del certificato della console, sha256:... (anche TOUTPANEL_WAF_PIN); non è un segreto
pt|h_waf_fingerprint|impressão digital SHA-256 do certificado da consola, sha256:... (também TOUTPANEL_WAF_PIN); não é um segredo
nl|h_waf_fingerprint|SHA-256-vingerafdruk van het consolecertificaat, sha256:... (ook TOUTPANEL_WAF_PIN); geen geheim
ru|h_waf_fingerprint|отпечаток SHA-256 сертификата консоли, sha256:... (также TOUTPANEL_WAF_PIN); не секрет
zh|h_waf_fingerprint|控制台证书的 SHA-256 指纹，sha256:...（也可用 TOUTPANEL_WAF_PIN）；不属于机密
ar|h_waf_fingerprint|بصمة SHA-256 لشهادة الواجهة، sha256:... (ويمكن أيضًا TOUTPANEL_WAF_PIN)؛ ليست سرًّا
en|h_waf_trust|accept and pin the fingerprint seen at the first connection (not verified: prefer --waf-fingerprint)
fr|h_waf_trust|accepte et épingle l'empreinte vue à la première connexion (non vérifiée : préférez --waf-fingerprint)
de|h_waf_trust|Fingerabdruck der ersten Verbindung akzeptieren und festschreiben (ungeprüft: besser --waf-fingerprint)
es|h_waf_trust|acepta y fija la huella vista en la primera conexión (sin verificar: prefiera --waf-fingerprint)
it|h_waf_trust|accetta e fissa l'impronta vista alla prima connessione (non verificata: preferire --waf-fingerprint)
pt|h_waf_trust|aceita e fixa a impressão digital vista na primeira ligação (não verificada: prefira --waf-fingerprint)
nl|h_waf_trust|accepteert en pint de vingerafdruk van de eerste verbinding (niet gecontroleerd: liever --waf-fingerprint)
ru|h_waf_trust|принимает и закрепляет отпечаток, увиденный при первом подключении (без проверки: лучше --waf-fingerprint)
zh|h_waf_trust|接受并固定首次连接时看到的指纹（未经核对：建议改用 --waf-fingerprint）
ar|h_waf_trust|يقبل البصمة المشاهدة عند أول اتصال ويثبّتها (دون تحقق: يُفضَّل --waf-fingerprint)
en|h_waf_strict|exit with an error (code 3) if the link to ToutWAF fails (state partial or unlinked) instead of code 0; the panel stays installed
fr|h_waf_strict|sortie en erreur (code 3) si la liaison à ToutWAF échoue (état partial ou unlinked) au lieu du code 0 ; le panel reste installé
de|h_waf_strict|mit einem Fehler (Code 3) statt mit Code 0 beenden, wenn die Verbindung zu ToutWAF fehlschlägt (Status partial oder unlinked); das Panel bleibt installiert
es|h_waf_strict|termina con error (código 3) en lugar del código 0 si el enlace con ToutWAF falla (estado partial o unlinked); el panel sigue instalado
it|h_waf_strict|termina con un errore (codice 3) invece del codice 0 se il collegamento a ToutWAF non riesce (stato partial o unlinked); il pannello resta installato
pt|h_waf_strict|termina com erro (código 3) em vez do código 0 se a ligação ao ToutWAF falhar (estado partial ou unlinked); o painel continua instalado
nl|h_waf_strict|stopt met een fout (code 3) in plaats van code 0 als de koppeling met ToutWAF mislukt (status partial of unlinked); het paneel blijft geïnstalleerd
ru|h_waf_strict|завершается с ошибкой (код 3) вместо кода 0, если подключение к ToutWAF не удалось (состояние partial или unlinked); панель остаётся установленной
zh|h_waf_strict|如果与 ToutWAF 的连接失败（状态为 partial 或 unlinked），以错误退出（代码 3）而不是代码 0；面板仍保持安装
ar|h_waf_strict|ينهي التنفيذ بخطأ (الرمز 3) بدل الرمز 0 إذا فشل الربط بـ ToutWAF (الحالة partial أو unlinked)؛ تبقى اللوحة مثبّتة
en|h_waf_token_env|API token: variable TOUTPANEL_WAF_TOKEN (keep it with sudo -E); never an argument (--waf-token is refused)
fr|h_waf_token_env|jeton d'API : variable TOUTPANEL_WAF_TOKEN (à conserver avec sudo -E) ; jamais en argument (--waf-token est refusé)
de|h_waf_token_env|API-Token: Variable TOUTPANEL_WAF_TOKEN (mit sudo -E beibehalten); nie als Argument (--waf-token wird abgelehnt)
es|h_waf_token_env|token de API: variable TOUTPANEL_WAF_TOKEN (conservarla con sudo -E); nunca como argumento (--waf-token se rechaza)
it|h_waf_token_env|token API: variabile TOUTPANEL_WAF_TOKEN (da mantenere con sudo -E); mai come argomento (--waf-token viene rifiutato)
pt|h_waf_token_env|token da API: variável TOUTPANEL_WAF_TOKEN (preservar com sudo -E); nunca como argumento (--waf-token é recusado)
nl|h_waf_token_env|API-token: variabele TOUTPANEL_WAF_TOKEN (behouden met sudo -E); nooit als argument (--waf-token wordt geweigerd)
ru|h_waf_token_env|токен API: переменная TOUTPANEL_WAF_TOKEN (сохраняйте через sudo -E); никогда не аргументом (--waf-token отклоняется)
zh|h_waf_token_env|API 令牌：环境变量 TOUTPANEL_WAF_TOKEN（用 sudo -E 保留）；绝不作为参数（--waf-token 会被拒绝）
ar|h_waf_token_env|رمز API: المتغير TOUTPANEL_WAF_TOKEN (احتفظ به باستخدام sudo -E)؛ لا يُمرَّر أبدًا كوسيط (يُرفض --waf-token)
en|h_waf_token_file|read the API token from this file (instead of the variable)
fr|h_waf_token_file|lit le jeton d'API dans ce fichier (au lieu de la variable)
de|h_waf_token_file|API-Token aus dieser Datei lesen (statt der Variablen)
es|h_waf_token_file|lee el token de API de este archivo (en lugar de la variable)
it|h_waf_token_file|legge il token API da questo file (invece della variabile)
pt|h_waf_token_file|lê o token da API deste ficheiro (em vez da variável)
nl|h_waf_token_file|leest het API-token uit dit bestand (in plaats van de variabele)
ru|h_waf_token_file|читает токен API из этого файла (вместо переменной)
zh|h_waf_token_file|从该文件读取 API 令牌（代替环境变量）
ar|h_waf_token_file|يقرأ رمز API من هذا الملف (بدل المتغير)
en|h_waf_token_stdin|read the API token on standard input (not usable with curl | bash)
fr|h_waf_token_stdin|lit le jeton d'API sur l'entrée standard (inutilisable avec curl | bash)
de|h_waf_token_stdin|API-Token von der Standardeingabe lesen (nicht mit curl | bash nutzbar)
es|h_waf_token_stdin|lee el token de API de la entrada estándar (no utilizable con curl | bash)
it|h_waf_token_stdin|legge il token API dallo standard input (non utilizzabile con curl | bash)
pt|h_waf_token_stdin|lê o token da API da entrada padrão (não utilizável com curl | bash)
nl|h_waf_token_stdin|leest het API-token van de standaardinvoer (niet bruikbaar met curl | bash)
ru|h_waf_token_stdin|читает токен API со стандартного ввода (непригодно при curl | bash)
zh|h_waf_token_stdin|从标准输入读取 API 令牌（不能与 curl | bash 同用）
ar|h_waf_token_stdin|يقرأ رمز API من الإدخال القياسي (لا يصلح مع curl | bash)
en|help_env_waf|Remote ToutWAF variables (kept by sudo -E): %s
fr|help_env_waf|Variables du ToutWAF distant (conservées par sudo -E) : %s
de|help_env_waf|Variablen für entferntes ToutWAF (von sudo -E beibehalten): %s
es|help_env_waf|Variables del ToutWAF remoto (conservadas por sudo -E): %s
it|help_env_waf|Variabili del ToutWAF remoto (mantenute da sudo -E): %s
pt|help_env_waf|Variáveis do ToutWAF remoto (preservadas por sudo -E): %s
nl|help_env_waf|Variabelen voor externe ToutWAF (behouden met sudo -E): %s
ru|help_env_waf|Переменные удалённого ToutWAF (сохраняются sudo -E): %s
zh|help_env_waf|远程 ToutWAF 变量（由 sudo -E 保留）：%s
ar|help_env_waf|متغيرات ToutWAF البعيد (يحتفظ بها sudo -E): %s
en|waf_token_arg_refused|The ToutWAF API token must never be passed as an argument (it would show in the process list and the shell history). Export TOUTPANEL_WAF_TOKEN (keep it with sudo -E), or use --waf-token-file FILE or --waf-token-stdin.
fr|waf_token_arg_refused|Le jeton d'API ToutWAF ne doit jamais être passé en argument (il serait visible dans la liste des processus et l'historique du shell). Exportez TOUTPANEL_WAF_TOKEN (à conserver avec sudo -E), ou utilisez --waf-token-file FICHIER ou --waf-token-stdin.
de|waf_token_arg_refused|Das ToutWAF-API-Token darf nie als Argument übergeben werden (es wäre in der Prozessliste und im Shell-Verlauf sichtbar). Exportieren Sie TOUTPANEL_WAF_TOKEN (mit sudo -E beibehalten) oder verwenden Sie --waf-token-file DATEI oder --waf-token-stdin.
es|waf_token_arg_refused|El token de API de ToutWAF nunca debe pasarse como argumento (sería visible en la lista de procesos y en el historial del shell). Exporte TOUTPANEL_WAF_TOKEN (consérvela con sudo -E) o use --waf-token-file ARCHIVO o --waf-token-stdin.
it|waf_token_arg_refused|Il token API di ToutWAF non deve mai essere passato come argomento (sarebbe visibile nell'elenco dei processi e nella cronologia della shell). Esportare TOUTPANEL_WAF_TOKEN (mantenerla con sudo -E) oppure usare --waf-token-file FILE o --waf-token-stdin.
pt|waf_token_arg_refused|O token da API do ToutWAF nunca deve ser passado como argumento (ficaria visível na lista de processos e no histórico da shell). Exporte TOUTPANEL_WAF_TOKEN (preserve-a com sudo -E) ou use --waf-token-file FICHEIRO ou --waf-token-stdin.
nl|waf_token_arg_refused|Het ToutWAF-API-token mag nooit als argument worden doorgegeven (het zou zichtbaar zijn in de proceslijst en de shellgeschiedenis). Exporteer TOUTPANEL_WAF_TOKEN (behouden met sudo -E) of gebruik --waf-token-file BESTAND of --waf-token-stdin.
ru|waf_token_arg_refused|Токен API ToutWAF нельзя передавать аргументом (он будет виден в списке процессов и истории оболочки). Экспортируйте TOUTPANEL_WAF_TOKEN (сохраняйте через sudo -E) или используйте --waf-token-file ФАЙЛ либо --waf-token-stdin.
zh|waf_token_arg_refused|ToutWAF 的 API 令牌绝不能作为参数传递（会出现在进程列表和 shell 历史中）。请导出 TOUTPANEL_WAF_TOKEN（用 sudo -E 保留），或使用 --waf-token-file 文件 或 --waf-token-stdin。
ar|waf_token_arg_refused|يجب ألا يُمرَّر رمز API الخاص بـ ToutWAF كوسيط أبدًا (سيظهر في قائمة العمليات وسجل الصدفة). صدّر TOUTPANEL_WAF_TOKEN (واحتفظ به باستخدام sudo -E) أو استخدم --waf-token-file ملف أو --waf-token-stdin.
en|waf_token_missing|ToutWAF API token missing: export TOUTPANEL_WAF_TOKEN (keep it with sudo -E), or use --waf-token-file FILE / --waf-token-stdin.
fr|waf_token_missing|Jeton d'API ToutWAF absent : exportez TOUTPANEL_WAF_TOKEN (à conserver avec sudo -E), ou utilisez --waf-token-file FICHIER / --waf-token-stdin.
de|waf_token_missing|ToutWAF-API-Token fehlt: Exportieren Sie TOUTPANEL_WAF_TOKEN (mit sudo -E beibehalten) oder verwenden Sie --waf-token-file DATEI / --waf-token-stdin.
es|waf_token_missing|Falta el token de API de ToutWAF: exporte TOUTPANEL_WAF_TOKEN (consérvela con sudo -E) o use --waf-token-file ARCHIVO / --waf-token-stdin.
it|waf_token_missing|Token API di ToutWAF mancante: esportare TOUTPANEL_WAF_TOKEN (mantenerla con sudo -E) oppure usare --waf-token-file FILE / --waf-token-stdin.
pt|waf_token_missing|Falta o token da API do ToutWAF: exporte TOUTPANEL_WAF_TOKEN (preserve-a com sudo -E) ou use --waf-token-file FICHEIRO / --waf-token-stdin.
nl|waf_token_missing|ToutWAF-API-token ontbreekt: exporteer TOUTPANEL_WAF_TOKEN (behouden met sudo -E) of gebruik --waf-token-file BESTAND / --waf-token-stdin.
ru|waf_token_missing|Не задан токен API ToutWAF: экспортируйте TOUTPANEL_WAF_TOKEN (сохраняйте через sudo -E) или используйте --waf-token-file ФАЙЛ / --waf-token-stdin.
zh|waf_token_missing|缺少 ToutWAF 的 API 令牌：请导出 TOUTPANEL_WAF_TOKEN（用 sudo -E 保留），或使用 --waf-token-file 文件 / --waf-token-stdin。
ar|waf_token_missing|رمز API الخاص بـ ToutWAF مفقود: صدّر TOUTPANEL_WAF_TOKEN (واحتفظ به باستخدام sudo -E) أو استخدم --waf-token-file ملف / --waf-token-stdin.
en|waf_token_prompt|ToutWAF API token (input hidden): 
fr|waf_token_prompt|Jeton d'API ToutWAF (saisie masquée) : 
de|waf_token_prompt|ToutWAF-API-Token (Eingabe verborgen): 
es|waf_token_prompt|Token de API de ToutWAF (entrada oculta): 
it|waf_token_prompt|Token API di ToutWAF (input nascosto): 
pt|waf_token_prompt|Token da API do ToutWAF (entrada oculta): 
nl|waf_token_prompt|ToutWAF-API-token (invoer verborgen): 
ru|waf_token_prompt|Токен API ToutWAF (ввод скрыт): 
zh|waf_token_prompt|ToutWAF API 令牌（输入不回显）：
ar|waf_token_prompt|رمز API لـ ToutWAF (الإدخال مخفي): 
en|waf_token_stdin_pipe|--waf-token-stdin cannot be used when this script itself is read from standard input (curl | bash): use TOUTPANEL_WAF_TOKEN or --waf-token-file FILE.
fr|waf_token_stdin_pipe|--waf-token-stdin est inutilisable quand le script lui-même arrive sur l'entrée standard (curl | bash) : utilisez TOUTPANEL_WAF_TOKEN ou --waf-token-file FICHIER.
de|waf_token_stdin_pipe|--waf-token-stdin ist nicht nutzbar, wenn das Skript selbst über die Standardeingabe kommt (curl | bash): verwenden Sie TOUTPANEL_WAF_TOKEN oder --waf-token-file DATEI.
es|waf_token_stdin_pipe|--waf-token-stdin no es utilizable cuando el propio script llega por la entrada estándar (curl | bash): use TOUTPANEL_WAF_TOKEN o --waf-token-file ARCHIVO.
it|waf_token_stdin_pipe|--waf-token-stdin non è utilizzabile quando lo script stesso arriva dallo standard input (curl | bash): usare TOUTPANEL_WAF_TOKEN o --waf-token-file FILE.
pt|waf_token_stdin_pipe|--waf-token-stdin não é utilizável quando o próprio script chega pela entrada padrão (curl | bash): use TOUTPANEL_WAF_TOKEN ou --waf-token-file FICHEIRO.
nl|waf_token_stdin_pipe|--waf-token-stdin kan niet worden gebruikt als het script zelf via de standaardinvoer binnenkomt (curl | bash): gebruik TOUTPANEL_WAF_TOKEN of --waf-token-file BESTAND.
ru|waf_token_stdin_pipe|--waf-token-stdin нельзя использовать, когда сам скрипт поступает через стандартный ввод (curl | bash): используйте TOUTPANEL_WAF_TOKEN или --waf-token-file ФАЙЛ.
zh|waf_token_stdin_pipe|当脚本本身通过标准输入传入（curl | bash）时，不能使用 --waf-token-stdin：请使用 TOUTPANEL_WAF_TOKEN 或 --waf-token-file 文件。
ar|waf_token_stdin_pipe|لا يمكن استخدام --waf-token-stdin عندما يصل السكربت نفسه عبر الإدخال القياسي (curl | bash): استخدم TOUTPANEL_WAF_TOKEN أو --waf-token-file ملف.
en|waf_token_file_bad|ToutWAF token file unreadable or empty: %s
fr|waf_token_file_bad|Fichier du jeton ToutWAF illisible ou vide : %s
de|waf_token_file_bad|ToutWAF-Token-Datei nicht lesbar oder leer: %s
es|waf_token_file_bad|Archivo del token de ToutWAF ilegible o vacío: %s
it|waf_token_file_bad|File del token ToutWAF illeggibile o vuoto: %s
pt|waf_token_file_bad|Ficheiro do token do ToutWAF ilegível ou vazio: %s
nl|waf_token_file_bad|ToutWAF-tokenbestand onleesbaar of leeg: %s
ru|waf_token_file_bad|Файл токена ToutWAF нечитаем или пуст: %s
zh|waf_token_file_bad|ToutWAF 令牌文件无法读取或为空：%s
ar|waf_token_file_bad|ملف رمز ToutWAF غير قابل للقراءة أو فارغ: %s
en|waf_console_empty|The ToutWAF console is empty: is TOUTPANEL_WAF_URL exported (and kept by sudo -E)?
fr|waf_console_empty|La console ToutWAF est vide : TOUTPANEL_WAF_URL est-elle exportée (et conservée par sudo -E) ?
de|waf_console_empty|Die ToutWAF-Konsole ist leer: ist TOUTPANEL_WAF_URL exportiert (und von sudo -E beibehalten)?
es|waf_console_empty|La consola de ToutWAF está vacía: ¿está exportada TOUTPANEL_WAF_URL (y conservada por sudo -E)?
it|waf_console_empty|La console ToutWAF è vuota: TOUTPANEL_WAF_URL è esportata (e mantenuta da sudo -E)?
pt|waf_console_empty|A consola do ToutWAF está vazia: TOUTPANEL_WAF_URL está exportada (e preservada por sudo -E)?
nl|waf_console_empty|De ToutWAF-console is leeg: is TOUTPANEL_WAF_URL geëxporteerd (en behouden met sudo -E)?
ru|waf_console_empty|Консоль ToutWAF не задана: экспортирована ли TOUTPANEL_WAF_URL (и сохранена ли через sudo -E)?
zh|waf_console_empty|ToutWAF 控制台地址为空：是否已导出 TOUTPANEL_WAF_URL（并用 sudo -E 保留）？
ar|waf_console_empty|واجهة ToutWAF فارغة: هل صُدِّر TOUTPANEL_WAF_URL (واحتُفظ به باستخدام sudo -E)؟
en|waf_bad_console|Invalid ToutWAF console: %s (expected https://HOST:9443/<secret-path>)
fr|waf_bad_console|Console ToutWAF invalide : %s (attendu : https://HÔTE:9443/<chemin-secret>)
de|waf_bad_console|Ungültige ToutWAF-Konsole: %s (erwartet: https://HOST:9443/<geheimer-Pfad>)
es|waf_bad_console|Consola de ToutWAF no válida: %s (se espera https://HOST:9443/<ruta-secreta>)
it|waf_bad_console|Console ToutWAF non valida: %s (atteso: https://HOST:9443/<percorso-segreto>)
pt|waf_bad_console|Consola do ToutWAF inválida: %s (esperado: https://HOST:9443/<caminho-secreto>)
nl|waf_bad_console|Ongeldige ToutWAF-console: %s (verwacht: https://HOST:9443/<geheim-pad>)
ru|waf_bad_console|Недопустимая консоль ToutWAF: %s (ожидается https://ХОСТ:9443/<секретный-путь>)
zh|waf_bad_console|无效的 ToutWAF 控制台：%s（应为 https://主机:9443/<秘密路径>）
ar|waf_bad_console|واجهة ToutWAF غير صالحة: %s (المتوقع https://HOST:9443/<المسار-السري>)
en|waf_bad_ip|Invalid IP address for %s: %s
fr|waf_bad_ip|Adresse IP invalide pour %s : %s
de|waf_bad_ip|Ungültige IP-Adresse für %s: %s
es|waf_bad_ip|Dirección IP no válida para %s: %s
it|waf_bad_ip|Indirizzo IP non valido per %s: %s
pt|waf_bad_ip|Endereço IP inválido para %s: %s
nl|waf_bad_ip|Ongeldig IP-adres voor %s: %s
ru|waf_bad_ip|Недопустимый IP-адрес для %s: %s
zh|waf_bad_ip|%s 的 IP 地址无效：%s
ar|waf_bad_ip|عنوان IP غير صالح لـ %s: %s
en|waf_bad_fp|Invalid fingerprint: expected sha256: followed by 64 hexadecimal characters.
fr|waf_bad_fp|Empreinte invalide : attendu sha256: suivi de 64 caractères hexadécimaux.
de|waf_bad_fp|Ungültiger Fingerabdruck: erwartet wird sha256: gefolgt von 64 Hexadezimalzeichen.
es|waf_bad_fp|Huella no válida: se espera sha256: seguido de 64 caracteres hexadecimales.
it|waf_bad_fp|Impronta non valida: atteso sha256: seguito da 64 caratteri esadecimali.
pt|waf_bad_fp|Impressão digital inválida: esperado sha256: seguido de 64 caracteres hexadecimais.
nl|waf_bad_fp|Ongeldige vingerafdruk: verwacht sha256: gevolgd door 64 hexadecimale tekens.
ru|waf_bad_fp|Недопустимый отпечаток: ожидается sha256: и 64 шестнадцатеричных символа.
zh|waf_bad_fp|指纹无效：应为 sha256: 后跟 64 个十六进制字符。
ar|waf_bad_fp|بصمة غير صالحة: المتوقع sha256: متبوعًا بـ 64 رمزًا سداسيًا عشريًا.
en|waf_bad_cert_mode|Invalid --waf-cert-mode: %s (import or acme)
fr|waf_bad_cert_mode|Valeur --waf-cert-mode invalide : %s (import ou acme)
de|waf_bad_cert_mode|Ungültiger Wert für --waf-cert-mode: %s (import oder acme)
es|waf_bad_cert_mode|Valor de --waf-cert-mode no válido: %s (import o acme)
it|waf_bad_cert_mode|Valore --waf-cert-mode non valido: %s (import o acme)
pt|waf_bad_cert_mode|Valor de --waf-cert-mode inválido: %s (import ou acme)
nl|waf_bad_cert_mode|Ongeldige waarde voor --waf-cert-mode: %s (import of acme)
ru|waf_bad_cert_mode|Недопустимое значение --waf-cert-mode: %s (import или acme)
zh|waf_bad_cert_mode|无效的 --waf-cert-mode 值：%s（import 或 acme）
ar|waf_bad_cert_mode|قيمة --waf-cert-mode غير صالحة: %s (import أو acme)
en|waf_bad_ssl|Invalid --waf-ssl: %s (toutwaf or panel)
fr|waf_bad_ssl|Valeur --waf-ssl invalide : %s (toutwaf ou panel)
de|waf_bad_ssl|Ungültiger Wert für --waf-ssl: %s (toutwaf oder panel)
es|waf_bad_ssl|Valor de --waf-ssl no válido: %s (toutwaf o panel)
it|waf_bad_ssl|Valore --waf-ssl non valido: %s (toutwaf o panel)
pt|waf_bad_ssl|Valor de --waf-ssl inválido: %s (toutwaf ou panel)
nl|waf_bad_ssl|Ongeldige waarde voor --waf-ssl: %s (toutwaf of panel)
ru|waf_bad_ssl|Недопустимое значение --waf-ssl: %s (toutwaf или panel)
zh|waf_bad_ssl|无效的 --waf-ssl 值：%s（toutwaf 或 panel）
ar|waf_bad_ssl|قيمة --waf-ssl غير صالحة: %s (toutwaf أو panel)
en|waf_bad_server_id|Invalid --waf-server-id: letters, digits and . _ : - only (80 characters at most).
fr|waf_bad_server_id|Valeur --waf-server-id invalide : lettres, chiffres et . _ : - uniquement (80 caractères au plus).
de|waf_bad_server_id|Ungültiger Wert für --waf-server-id: nur Buchstaben, Ziffern und . _ : - (höchstens 80 Zeichen).
es|waf_bad_server_id|Valor de --waf-server-id no válido: solo letras, cifras y . _ : - (80 caracteres como máximo).
it|waf_bad_server_id|Valore --waf-server-id non valido: solo lettere, cifre e . _ : - (al massimo 80 caratteri).
pt|waf_bad_server_id|Valor de --waf-server-id inválido: apenas letras, dígitos e . _ : - (no máximo 80 caracteres).
nl|waf_bad_server_id|Ongeldige waarde voor --waf-server-id: alleen letters, cijfers en . _ : - (maximaal 80 tekens).
ru|waf_bad_server_id|Недопустимое значение --waf-server-id: только буквы, цифры и . _ : - (не более 80 символов).
zh|waf_bad_server_id|无效的 --waf-server-id 值：仅限字母、数字和 . _ : -（最多 80 个字符）。
ar|waf_bad_server_id|قيمة --waf-server-id غير صالحة: أحرف وأرقام و . _ : - فقط (80 رمزًا كحد أقصى).
en|waf_server_id_missing|WARNING: no ToutWAF server identifier (--waf-server-id or TOUTPANEL_WAF_SERVER_ID). The panel will send no status heartbeat and ToutWAF will not receive the panel API token. Copy the full command generated by ToutWAF, or run later: toutpanel waf connect toutwaf --server-id ID
fr|waf_server_id_missing|ATTENTION : aucun identifiant de serveur ToutWAF (--waf-server-id ou TOUTPANEL_WAF_SERVER_ID). Le panel n'enverra pas de signal d'état et ToutWAF ne recevra pas le jeton d'API du panel. Copiez la commande complète générée par ToutWAF, ou lancez plus tard : toutpanel waf connect toutwaf --server-id ID
de|waf_server_id_missing|ACHTUNG: keine ToutWAF-Serverkennung (--waf-server-id oder TOUTPANEL_WAF_SERVER_ID). Das Panel sendet kein Statussignal und ToutWAF erhält das API-Token des Panels nicht. Kopieren Sie den vollständigen von ToutWAF erzeugten Befehl oder führen Sie später aus: toutpanel waf connect toutwaf --server-id ID
es|waf_server_id_missing|ATENCIÓN: no hay identificador de servidor ToutWAF (--waf-server-id o TOUTPANEL_WAF_SERVER_ID). El panel no enviará la señal de estado y ToutWAF no recibirá el token de API del panel. Copie el comando completo generado por ToutWAF o ejecute más tarde: toutpanel waf connect toutwaf --server-id ID
it|waf_server_id_missing|ATTENZIONE: nessun identificativo di server ToutWAF (--waf-server-id o TOUTPANEL_WAF_SERVER_ID). Il pannello non invierà il segnale di stato e ToutWAF non riceverà il token API del pannello. Copiare il comando completo generato da ToutWAF, oppure eseguire in seguito: toutpanel waf connect toutwaf --server-id ID
pt|waf_server_id_missing|ATENÇÃO: nenhum identificador de servidor ToutWAF (--waf-server-id ou TOUTPANEL_WAF_SERVER_ID). O painel não enviará o sinal de estado e o ToutWAF não receberá o token de API do painel. Copie o comando completo gerado pelo ToutWAF ou execute mais tarde: toutpanel waf connect toutwaf --server-id ID
nl|waf_server_id_missing|LET OP: geen ToutWAF-server-id (--waf-server-id of TOUTPANEL_WAF_SERVER_ID). Het paneel stuurt geen statussignaal en ToutWAF ontvangt het API-token van het paneel niet. Kopieer de volledige opdracht die ToutWAF genereert, of voer later uit: toutpanel waf connect toutwaf --server-id ID
ru|waf_server_id_missing|ВНИМАНИЕ: не указан идентификатор сервера ToutWAF (--waf-server-id или TOUTPANEL_WAF_SERVER_ID). Панель не будет отправлять сигнал состояния, и ToutWAF не получит API-токен панели. Скопируйте полную команду, созданную ToutWAF, или выполните позже: toutpanel waf connect toutwaf --server-id ID
zh|waf_server_id_missing|警告：未提供 ToutWAF 服务器标识（--waf-server-id 或 TOUTPANEL_WAF_SERVER_ID）。面板不会发送状态心跳，ToutWAF 也不会收到面板的 API 令牌。请复制 ToutWAF 生成的完整命令，或稍后运行：toutpanel waf connect toutwaf --server-id ID
ar|waf_server_id_missing|تنبيه: لا يوجد معرّف خادم ToutWAF (--waf-server-id أو TOUTPANEL_WAF_SERVER_ID). لن ترسل اللوحة إشارة الحالة ولن يتلقى ToutWAF رمز API الخاص باللوحة. انسخ الأمر الكامل الذي يولّده ToutWAF، أو نفّذ لاحقًا: toutpanel waf connect toutwaf --server-id ID
en|waf_opts_need_waf|The --waf-* options require --waf toutwaf.
fr|waf_opts_need_waf|Les options --waf-* exigent --waf toutwaf.
de|waf_opts_need_waf|Die --waf-*-Optionen erfordern --waf toutwaf.
es|waf_opts_need_waf|Las opciones --waf-* requieren --waf toutwaf.
it|waf_opts_need_waf|Le opzioni --waf-* richiedono --waf toutwaf.
pt|waf_opts_need_waf|As opções --waf-* exigem --waf toutwaf.
nl|waf_opts_need_waf|De --waf-*-opties vereisen --waf toutwaf.
ru|waf_opts_need_waf|Параметры --waf-* требуют --waf toutwaf.
zh|waf_opts_need_waf|--waf-* 选项需要配合 --waf toutwaf 使用。
ar|waf_opts_need_waf|تتطلب خيارات --waf-* وجود --waf toutwaf.
en|waf_opts_need_console|%s only applies to a remote ToutWAF: add --waf-console URL (or export TOUTPANEL_WAF_URL).
fr|waf_opts_need_console|%s ne s'applique qu'à un ToutWAF distant : ajoutez --waf-console URL (ou exportez TOUTPANEL_WAF_URL).
de|waf_opts_need_console|%s gilt nur für ein entferntes ToutWAF: fügen Sie --waf-console URL hinzu (oder exportieren Sie TOUTPANEL_WAF_URL).
es|waf_opts_need_console|%s solo se aplica a un ToutWAF remoto: añada --waf-console URL (o exporte TOUTPANEL_WAF_URL).
it|waf_opts_need_console|%s si applica solo a un ToutWAF remoto: aggiungere --waf-console URL (o esportare TOUTPANEL_WAF_URL).
pt|waf_opts_need_console|%s só se aplica a um ToutWAF remoto: adicione --waf-console URL (ou exporte TOUTPANEL_WAF_URL).
nl|waf_opts_need_console|%s geldt alleen voor een externe ToutWAF: voeg --waf-console URL toe (of exporteer TOUTPANEL_WAF_URL).
ru|waf_opts_need_console|%s применимо только к удалённому ToutWAF: добавьте --waf-console URL (или экспортируйте TOUTPANEL_WAF_URL).
zh|waf_opts_need_console|%s 仅适用于远程 ToutWAF：请添加 --waf-console URL（或导出 TOUTPANEL_WAF_URL）。
ar|waf_opts_need_console|لا ينطبق %s إلا على ToutWAF بعيد: أضف --waf-console URL (أو صدّر TOUTPANEL_WAF_URL).
en|waf_tls_conflict|Choose one: a fingerprint (--waf-fingerprint or TOUTPANEL_WAF_PIN) or --waf-trust-first-use.
fr|waf_tls_conflict|Choisissez l'un ou l'autre : une empreinte (--waf-fingerprint ou TOUTPANEL_WAF_PIN) ou --waf-trust-first-use.
de|waf_tls_conflict|Wählen Sie eines: einen Fingerabdruck (--waf-fingerprint oder TOUTPANEL_WAF_PIN) oder --waf-trust-first-use.
es|waf_tls_conflict|Elija una: una huella (--waf-fingerprint o TOUTPANEL_WAF_PIN) o --waf-trust-first-use.
it|waf_tls_conflict|Scegliere una sola: un'impronta (--waf-fingerprint o TOUTPANEL_WAF_PIN) oppure --waf-trust-first-use.
pt|waf_tls_conflict|Escolha uma: uma impressão digital (--waf-fingerprint ou TOUTPANEL_WAF_PIN) ou --waf-trust-first-use.
nl|waf_tls_conflict|Kies één: een vingerafdruk (--waf-fingerprint of TOUTPANEL_WAF_PIN) of --waf-trust-first-use.
ru|waf_tls_conflict|Выберите одно: отпечаток (--waf-fingerprint или TOUTPANEL_WAF_PIN) либо --waf-trust-first-use.
zh|waf_tls_conflict|请二选一：指纹（--waf-fingerprint 或 TOUTPANEL_WAF_PIN）或 --waf-trust-first-use。
ar|waf_tls_conflict|اختر أحدهما: بصمة (--waf-fingerprint أو TOUTPANEL_WAF_PIN) أو --waf-trust-first-use.
en|waf_restrict_needs_yes|--waf-restrict cuts direct access to ports 80/443 (only the ToutWAF will get through): confirm with --yes.
fr|waf_restrict_needs_yes|--waf-restrict coupe l'accès direct aux ports 80/443 (seul ToutWAF passera) : confirmez avec --yes.
de|waf_restrict_needs_yes|--waf-restrict unterbindet den direkten Zugriff auf die Ports 80/443 (nur ToutWAF kommt durch): mit --yes bestätigen.
es|waf_restrict_needs_yes|--waf-restrict corta el acceso directo a los puertos 80/443 (solo pasará ToutWAF): confirme con --yes.
it|waf_restrict_needs_yes|--waf-restrict interrompe l'accesso diretto alle porte 80/443 (passerà solo ToutWAF): confermare con --yes.
pt|waf_restrict_needs_yes|--waf-restrict corta o acesso direto às portas 80/443 (só o ToutWAF passará): confirme com --yes.
nl|waf_restrict_needs_yes|--waf-restrict sluit directe toegang tot poort 80/443 af (alleen ToutWAF komt erdoor): bevestig met --yes.
ru|waf_restrict_needs_yes|--waf-restrict закрывает прямой доступ к портам 80/443 (пройдёт только ToutWAF): подтвердите с помощью --yes.
zh|waf_restrict_needs_yes|--waf-restrict 会切断对 80/443 端口的直接访问（只有 ToutWAF 能通过）：请用 --yes 确认。
ar|waf_restrict_needs_yes|يقطع --waf-restrict الوصول المباشر إلى المنفذين 80/443 (لن يمرّ سوى ToutWAF): أكّد باستخدام --yes.
en|waf_ask_restrict|Limit ports 80/443 to the ToutWAF? Direct access to this server will be cut. %s
fr|waf_ask_restrict|Limiter les ports 80/443 au seul ToutWAF ? L'accès direct à ce serveur sera coupé. %s
de|waf_ask_restrict|Ports 80/443 nur für das ToutWAF freigeben? Der direkte Zugriff auf diesen Server wird unterbunden. %s
es|waf_ask_restrict|¿Limitar los puertos 80/443 al ToutWAF? Se cortará el acceso directo a este servidor. %s
it|waf_ask_restrict|Limitare le porte 80/443 al solo ToutWAF? L'accesso diretto a questo server verrà interrotto. %s
pt|waf_ask_restrict|Limitar as portas 80/443 ao ToutWAF? O acesso direto a este servidor será cortado. %s
nl|waf_ask_restrict|Poort 80/443 beperken tot de ToutWAF? Directe toegang tot deze server vervalt. %s
ru|waf_ask_restrict|Ограничить порты 80/443 только для ToutWAF? Прямой доступ к этому серверу будет закрыт. %s
zh|waf_ask_restrict|是否将 80/443 端口仅限 ToutWAF 访问？将切断对此服务器的直接访问。%s
ar|waf_ask_restrict|هل تريد حصر المنفذين 80/443 في ToutWAF؟ سيُقطع الوصول المباشر إلى هذا الخادم. %s
en|waf_restrict_declined|Firewall restriction declined: ports 80/443 stay open.
fr|waf_restrict_declined|Restriction du pare-feu refusée : les ports 80/443 restent ouverts.
de|waf_restrict_declined|Firewall-Einschränkung abgelehnt: die Ports 80/443 bleiben offen.
es|waf_restrict_declined|Restricción del cortafuegos rechazada: los puertos 80/443 siguen abiertos.
it|waf_restrict_declined|Restrizione del firewall rifiutata: le porte 80/443 restano aperte.
pt|waf_restrict_declined|Restrição da firewall recusada: as portas 80/443 permanecem abertas.
nl|waf_restrict_declined|Firewallbeperking geweigerd: poort 80/443 blijft open.
ru|waf_restrict_declined|Ограничение брандмауэра отклонено: порты 80/443 остаются открытыми.
zh|waf_restrict_declined|已拒绝防火墙限制：80/443 端口保持开放。
ar|waf_restrict_declined|رُفض تقييد الجدار الناري: يبقى المنفذان 80/443 مفتوحين.
en|st_waf_remote|Linking the panel to the remote ToutWAF
fr|st_waf_remote|Raccordement du panel au ToutWAF distant
de|st_waf_remote|Panel mit dem entfernten ToutWAF verbinden
es|st_waf_remote|Enlazando el panel con el ToutWAF remoto
it|st_waf_remote|Collegamento del pannello al ToutWAF remoto
pt|st_waf_remote|A ligar o painel ao ToutWAF remoto
nl|st_waf_remote|Paneel koppelen aan de externe ToutWAF
ru|st_waf_remote|Подключение панели к удалённому ToutWAF
zh|st_waf_remote|正在将面板连接到远程 ToutWAF
ar|st_waf_remote|ربط اللوحة بـ ToutWAF البعيد
en|waf_connecting|Connecting to ToutWAF %s (the token goes through the environment and is never displayed)...
fr|waf_connecting|Connexion à ToutWAF %s (le jeton passe par l'environnement et n'est jamais affiché)...
de|waf_connecting|Verbindung zu ToutWAF %s (das Token läuft über die Umgebung und wird nie angezeigt)...
es|waf_connecting|Conectando con ToutWAF %s (el token pasa por el entorno y nunca se muestra)...
it|waf_connecting|Connessione a ToutWAF %s (il token passa dall'ambiente e non viene mai mostrato)...
pt|waf_connecting|A ligar ao ToutWAF %s (o token passa pelo ambiente e nunca é apresentado)...
nl|waf_connecting|Verbinden met ToutWAF %s (het token loopt via de omgeving en wordt nooit getoond)...
ru|waf_connecting|Подключение к ToutWAF %s (токен передаётся через окружение и никогда не выводится)...
zh|waf_connecting|正在连接 ToutWAF %s（令牌通过环境变量传递，绝不显示）...
ar|waf_connecting|جارٍ الاتصال بـ ToutWAF %s (يُمرَّر الرمز عبر البيئة ولا يُعرض أبدًا)...
en|waf_linked|Panel linked to the remote ToutWAF %s: sites declared, ToutWAF is now the WAF engine.
fr|waf_linked|Panel relié au ToutWAF distant %s : sites déclarés, ToutWAF est maintenant le moteur WAF.
de|waf_linked|Panel mit dem entfernten ToutWAF %s verbunden: Websites gemeldet, ToutWAF ist jetzt die WAF-Engine.
es|waf_linked|Panel enlazado con el ToutWAF remoto %s: sitios declarados, ToutWAF es ahora el motor WAF.
it|waf_linked|Pannello collegato al ToutWAF remoto %s: siti dichiarati, ToutWAF è ora il motore WAF.
pt|waf_linked|Painel ligado ao ToutWAF remoto %s: sites declarados, o ToutWAF é agora o motor WAF.
nl|waf_linked|Paneel gekoppeld aan de externe ToutWAF %s: sites aangemeld, ToutWAF is nu de WAF-engine.
ru|waf_linked|Панель подключена к удалённому ToutWAF %s: сайты объявлены, ToutWAF теперь движок WAF.
zh|waf_linked|面板已连接到远程 ToutWAF %s：站点已登记，ToutWAF 现为 WAF 引擎。
ar|waf_linked|تم ربط اللوحة بـ ToutWAF البعيد %s: أُعلنت المواقع وأصبح ToutWAF محرك WAF.
en|waf_pinned|TLS fingerprint pinned: %s
fr|waf_pinned|Empreinte TLS épinglée : %s
de|waf_pinned|TLS-Fingerabdruck festgeschrieben: %s
es|waf_pinned|Huella TLS fijada: %s
it|waf_pinned|Impronta TLS fissata: %s
pt|waf_pinned|Impressão digital TLS fixada: %s
nl|waf_pinned|TLS-vingerafdruk vastgepind: %s
ru|waf_pinned|Отпечаток TLS закреплён: %s
zh|waf_pinned|已固定 TLS 指纹：%s
ar|waf_pinned|تم تثبيت بصمة TLS: %s
en|waf_unpinned|Warning: the console certificate is not pinned, so the link is not verified by fingerprint. Re-run with --waf-fingerprint sha256:... (shown by ToutWAF).
fr|waf_unpinned|Attention : le certificat de la console n'est pas épinglé, la liaison n'est donc pas vérifiée par empreinte. Relancez avec --waf-fingerprint sha256:... (affichée par ToutWAF).
de|waf_unpinned|Achtung: Das Konsolenzertifikat ist nicht festgeschrieben, die Verbindung wird daher nicht per Fingerabdruck geprüft. Erneut mit --waf-fingerprint sha256:... starten (von ToutWAF angezeigt).
es|waf_unpinned|Atención: el certificado de la consola no está fijado, por lo que el enlace no se verifica por huella. Vuelva a ejecutar con --waf-fingerprint sha256:... (la muestra ToutWAF).
it|waf_unpinned|Attenzione: il certificato della console non è fissato, quindi il collegamento non è verificato tramite impronta. Rilanciare con --waf-fingerprint sha256:... (mostrata da ToutWAF).
pt|waf_unpinned|Atenção: o certificado da consola não está fixado, pelo que a ligação não é verificada por impressão digital. Execute novamente com --waf-fingerprint sha256:... (indicada pelo ToutWAF).
nl|waf_unpinned|Let op: het consolecertificaat is niet vastgepind, dus de koppeling wordt niet met een vingerafdruk gecontroleerd. Start opnieuw met --waf-fingerprint sha256:... (getoond door ToutWAF).
ru|waf_unpinned|Внимание: сертификат консоли не закреплён, поэтому соединение не проверяется по отпечатку. Повторите с --waf-fingerprint sha256:... (его показывает ToutWAF).
zh|waf_unpinned|注意：未固定控制台证书，因此连接没有经过指纹验证。请使用 --waf-fingerprint sha256:... 重新运行（由 ToutWAF 显示）。
ar|waf_unpinned|تنبيه: شهادة الواجهة غير مثبّتة، لذا لا يُتحقق من الاتصال بالبصمة. أعد التشغيل مع --waf-fingerprint sha256:... (يعرضها ToutWAF).
en|waf_not_linked|The panel is NOT linked to ToutWAF. The panel itself is installed and working; link it by hand once the cause is fixed:
fr|waf_not_linked|Le panel n'est PAS relié à ToutWAF. Le panel lui-même est installé et fonctionne ; reliez-le à la main une fois la cause corrigée :
de|waf_not_linked|Das Panel ist NICHT mit ToutWAF verbunden. Das Panel selbst ist installiert und funktioniert; verbinden Sie es nach Behebung der Ursache von Hand:
es|waf_not_linked|El panel NO está enlazado con ToutWAF. El panel está instalado y funciona; enlácelo a mano una vez corregida la causa:
it|waf_not_linked|Il pannello NON è collegato a ToutWAF. Il pannello è installato e funziona; collegarlo a mano dopo aver risolto la causa:
pt|waf_not_linked|O painel NÃO está ligado ao ToutWAF. O painel está instalado e a funcionar; ligue-o manualmente depois de corrigir a causa:
nl|waf_not_linked|Het paneel is NIET gekoppeld aan ToutWAF. Het paneel zelf is geïnstalleerd en werkt; koppel het handmatig nadat de oorzaak is verholpen:
ru|waf_not_linked|Панель НЕ подключена к ToutWAF. Сама панель установлена и работает; подключите её вручную после устранения причины:
zh|waf_not_linked|面板尚未连接到 ToutWAF。面板本身已安装并可正常使用；排除原因后请手动连接：
ar|waf_not_linked|اللوحة غير مرتبطة بـ ToutWAF. اللوحة نفسها مثبّتة وتعمل؛ اربطها يدويًا بعد معالجة السبب:
en|waf_strict_failed|--waf-strict: the panel is installed but its link to ToutWAF is not complete (state: %s). Exit code 3.
fr|waf_strict_failed|--waf-strict : le panel est installé mais sa liaison à ToutWAF n'est pas complète (état : %s). Code de sortie 3.
de|waf_strict_failed|--waf-strict: Das Panel ist installiert, aber seine Verbindung zu ToutWAF ist nicht vollständig (Status: %s). Exit-Code 3.
es|waf_strict_failed|--waf-strict: el panel está instalado pero su enlace con ToutWAF no está completo (estado: %s). Código de salida 3.
it|waf_strict_failed|--waf-strict: il pannello è installato ma il suo collegamento a ToutWAF non è completo (stato: %s). Codice di uscita 3.
pt|waf_strict_failed|--waf-strict: o painel está instalado mas a ligação ao ToutWAF não está completa (estado: %s). Código de saída 3.
nl|waf_strict_failed|--waf-strict: het paneel is geïnstalleerd, maar de koppeling met ToutWAF is niet volledig (status: %s). Exitcode 3.
ru|waf_strict_failed|--waf-strict: панель установлена, но её подключение к ToutWAF не завершено (состояние: %s). Код выхода 3.
zh|waf_strict_failed|--waf-strict：面板已安装，但与 ToutWAF 的连接未完成（状态：%s）。退出代码 3。
ar|waf_strict_failed|--waf-strict: اللوحة مثبّتة لكن ربطها بـ ToutWAF غير مكتمل (الحالة: %s). رمز الخروج 3.
en|waf_retry|The token is read from the environment, never from an argument:
fr|waf_retry|Le jeton est lu dans l'environnement, jamais en argument :
de|waf_retry|Das Token wird aus der Umgebung gelesen, nie aus einem Argument:
es|waf_retry|El token se lee del entorno, nunca de un argumento:
it|waf_retry|Il token viene letto dall'ambiente, mai da un argomento:
pt|waf_retry|O token é lido do ambiente, nunca de um argumento:
nl|waf_retry|Het token wordt uit de omgeving gelezen, nooit uit een argument:
ru|waf_retry|Токен читается из окружения, а не из аргумента:
zh|waf_retry|令牌从环境变量读取，绝不从参数读取：
ar|waf_retry|يُقرأ الرمز من البيئة وليس من وسيط أبدًا:
en|waf_fp_seen|TLS certificate not trusted. Fingerprint seen on the console: %s. Compare it with the one shown by ToutWAF, then re-run with --waf-fingerprint %s (or --waf-trust-first-use to accept it unchecked).
fr|waf_fp_seen|Certificat TLS non approuvé. Empreinte vue sur la console : %s. Comparez-la à celle qu'affiche ToutWAF, puis relancez avec --waf-fingerprint %s (ou --waf-trust-first-use pour l'accepter sans vérifier).
de|waf_fp_seen|TLS-Zertifikat nicht vertrauenswürdig. Auf der Konsole gesehener Fingerabdruck: %s. Vergleichen Sie ihn mit dem von ToutWAF angezeigten und starten Sie dann erneut mit --waf-fingerprint %s (oder --waf-trust-first-use, um ihn ungeprüft zu akzeptieren).
es|waf_fp_seen|Certificado TLS no confiable. Huella vista en la consola: %s. Compárela con la que muestra ToutWAF y vuelva a ejecutar con --waf-fingerprint %s (o --waf-trust-first-use para aceptarla sin comprobar).
it|waf_fp_seen|Certificato TLS non attendibile. Impronta vista sulla console: %s. Confrontarla con quella mostrata da ToutWAF, poi rilanciare con --waf-fingerprint %s (o --waf-trust-first-use per accettarla senza verifica).
pt|waf_fp_seen|Certificado TLS não fiável. Impressão digital vista na consola: %s. Compare-a com a apresentada pelo ToutWAF e execute novamente com --waf-fingerprint %s (ou --waf-trust-first-use para a aceitar sem verificar).
nl|waf_fp_seen|TLS-certificaat niet vertrouwd. Op de console gezien vingerafdruk: %s. Vergelijk die met de vingerafdruk van ToutWAF en start opnieuw met --waf-fingerprint %s (of --waf-trust-first-use om ongecontroleerd te accepteren).
ru|waf_fp_seen|Сертификат TLS не принят. Отпечаток, увиденный на консоли: %s. Сравните его с показанным в ToutWAF и повторите с --waf-fingerprint %s (или --waf-trust-first-use, чтобы принять без проверки).
zh|waf_fp_seen|TLS 证书不受信任。在控制台看到的指纹：%s。请与 ToutWAF 显示的指纹核对，然后使用 --waf-fingerprint %s 重新运行（或用 --waf-trust-first-use 不经核对直接接受）。
ar|waf_fp_seen|شهادة TLS غير موثوقة. البصمة المشاهدة على الواجهة: %s. قارنها بالبصمة التي يعرضها ToutWAF ثم أعد التشغيل مع --waf-fingerprint %s (أو --waf-trust-first-use لقبولها دون تحقق).
en|waf_tls_other|TLS certificate of the console not trusted, or different from the pinned fingerprint. Check it in ToutWAF, then use --waf-fingerprint sha256:...
fr|waf_tls_other|Certificat TLS de la console non approuvé ou différent de l'empreinte épinglée. Vérifiez-le dans ToutWAF, puis utilisez --waf-fingerprint sha256:...
de|waf_tls_other|TLS-Zertifikat der Konsole nicht vertrauenswürdig oder abweichend vom festgeschriebenen Fingerabdruck. Prüfen Sie es in ToutWAF und verwenden Sie dann --waf-fingerprint sha256:...
es|waf_tls_other|Certificado TLS de la consola no confiable o distinto de la huella fijada. Compruébelo en ToutWAF y use --waf-fingerprint sha256:...
it|waf_tls_other|Certificato TLS della console non attendibile o diverso dall'impronta fissata. Verificarlo in ToutWAF, poi usare --waf-fingerprint sha256:...
pt|waf_tls_other|Certificado TLS da consola não fiável ou diferente da impressão digital fixada. Verifique-o no ToutWAF e use --waf-fingerprint sha256:...
nl|waf_tls_other|TLS-certificaat van de console niet vertrouwd of anders dan de vastgepinde vingerafdruk. Controleer het in ToutWAF en gebruik --waf-fingerprint sha256:...
ru|waf_tls_other|Сертификат TLS консоли не принят или отличается от закреплённого отпечатка. Проверьте его в ToutWAF и используйте --waf-fingerprint sha256:...
zh|waf_tls_other|控制台的 TLS 证书不受信任，或与已固定的指纹不同。请在 ToutWAF 中核对，然后使用 --waf-fingerprint sha256:...
ar|waf_tls_other|شهادة TLS للواجهة غير موثوقة أو تختلف عن البصمة المثبتة. تحقق منها في ToutWAF ثم استخدم --waf-fingerprint sha256:...
en|waf_unreachable|ToutWAF unreachable. Check the address, that port 9443 of the ToutWAF is open to this server (firewall, security group) and that its console service is running.
fr|waf_unreachable|ToutWAF injoignable. Vérifiez l'adresse, que le port 9443 du ToutWAF est ouvert pour ce serveur (pare-feu, groupe de sécurité) et que son service de console tourne.
de|waf_unreachable|ToutWAF nicht erreichbar. Prüfen Sie die Adresse, ob Port 9443 des ToutWAF für diesen Server offen ist (Firewall, Sicherheitsgruppe) und ob sein Konsolendienst läuft.
es|waf_unreachable|ToutWAF inaccesible. Compruebe la dirección, que el puerto 9443 del ToutWAF esté abierto para este servidor (cortafuegos, grupo de seguridad) y que su servicio de consola esté en marcha.
it|waf_unreachable|ToutWAF non raggiungibile. Verificare l'indirizzo, che la porta 9443 del ToutWAF sia aperta per questo server (firewall, gruppo di sicurezza) e che il suo servizio console sia in esecuzione.
pt|waf_unreachable|ToutWAF inacessível. Verifique o endereço, se a porta 9443 do ToutWAF está aberta para este servidor (firewall, grupo de segurança) e se o serviço da consola está em execução.
nl|waf_unreachable|ToutWAF onbereikbaar. Controleer het adres, of poort 9443 van de ToutWAF openstaat voor deze server (firewall, beveiligingsgroep) en of de consoleservice draait.
ru|waf_unreachable|ToutWAF недоступен. Проверьте адрес, открыт ли порт 9443 ToutWAF для этого сервера (брандмауэр, группа безопасности) и запущена ли служба консоли.
zh|waf_unreachable|无法连接 ToutWAF。请检查地址、ToutWAF 的 9443 端口是否对此服务器开放（防火墙、安全组），以及其控制台服务是否在运行。
ar|waf_unreachable|تعذّر الوصول إلى ToutWAF. تحقق من العنوان ومن أن المنفذ 9443 في ToutWAF مفتوح لهذا الخادم (الجدار الناري، مجموعة الأمان) ومن أن خدمة الواجهة تعمل.
en|waf_denied|API token refused by ToutWAF (invalid, expired, revoked or missing rights). Create a new token in the ToutWAF console with the rights listed in the documentation.
fr|waf_denied|Jeton d'API refusé par ToutWAF (invalide, expiré, révoqué ou droits manquants). Créez un nouveau jeton dans la console ToutWAF avec les droits indiqués dans la documentation.
de|waf_denied|API-Token von ToutWAF abgelehnt (ungültig, abgelaufen, widerrufen oder fehlende Rechte). Erstellen Sie in der ToutWAF-Konsole ein neues Token mit den in der Dokumentation genannten Rechten.
es|waf_denied|Token de API rechazado por ToutWAF (no válido, caducado, revocado o sin los derechos necesarios). Cree un token nuevo en la consola de ToutWAF con los derechos indicados en la documentación.
it|waf_denied|Token API rifiutato da ToutWAF (non valido, scaduto, revocato o privo dei diritti necessari). Creare un nuovo token nella console ToutWAF con i diritti indicati nella documentazione.
pt|waf_denied|Token da API recusado pelo ToutWAF (inválido, expirado, revogado ou sem os direitos necessários). Crie um novo token na consola do ToutWAF com os direitos indicados na documentação.
nl|waf_denied|API-token door ToutWAF geweigerd (ongeldig, verlopen, ingetrokken of ontbrekende rechten). Maak in de ToutWAF-console een nieuw token met de rechten uit de documentatie.
ru|waf_denied|Токен API отклонён ToutWAF (недействителен, истёк, отозван или не хватает прав). Создайте в консоли ToutWAF новый токен с правами, указанными в документации.
zh|waf_denied|ToutWAF 拒绝了 API 令牌（无效、已过期、已吊销或权限不足）。请在 ToutWAF 控制台中按文档所列权限创建新令牌。
ar|waf_denied|رفض ToutWAF رمز API (غير صالح أو منتهي أو مُلغى أو ينقصه بعض الصلاحيات). أنشئ رمزًا جديدًا في واجهة ToutWAF بالصلاحيات المذكورة في التوثيق.
en|waf_incompat|Wrong console URL or incompatible ToutWAF (too old, or not a ToutWAF). Check the secret path in https://IP:9443/<secret-path> and update ToutWAF if needed.
fr|waf_incompat|URL de console incorrecte ou ToutWAF incompatible (trop ancien, ou pas un ToutWAF). Vérifiez le chemin secret dans https://IP:9443/<chemin-secret> et mettez ToutWAF à jour au besoin.
de|waf_incompat|Falsche Konsolen-URL oder inkompatibles ToutWAF (zu alt oder kein ToutWAF). Prüfen Sie den geheimen Pfad in https://IP:9443/<geheimer-Pfad> und aktualisieren Sie ToutWAF bei Bedarf.
es|waf_incompat|URL de consola incorrecta o ToutWAF incompatible (demasiado antiguo o no es un ToutWAF). Compruebe la ruta secreta en https://IP:9443/<ruta-secreta> y actualice ToutWAF si es necesario.
it|waf_incompat|URL della console errato o ToutWAF incompatibile (troppo vecchio o non è un ToutWAF). Verificare il percorso segreto in https://IP:9443/<percorso-segreto> e aggiornare ToutWAF se necessario.
pt|waf_incompat|URL da consola incorreto ou ToutWAF incompatível (demasiado antigo ou não é um ToutWAF). Verifique o caminho secreto em https://IP:9443/<caminho-secreto> e atualize o ToutWAF se necessário.
nl|waf_incompat|Onjuiste console-URL of incompatibele ToutWAF (te oud, of geen ToutWAF). Controleer het geheime pad in https://IP:9443/<geheim-pad> en werk ToutWAF zo nodig bij.
ru|waf_incompat|Неверный URL консоли или несовместимый ToutWAF (слишком старый или не ToutWAF). Проверьте секретный путь в https://IP:9443/<секретный-путь> и при необходимости обновите ToutWAF.
zh|waf_incompat|控制台 URL 有误或 ToutWAF 不兼容（版本过旧，或并非 ToutWAF）。请检查 https://IP:9443/<秘密路径> 中的秘密路径，必要时更新 ToutWAF。
ar|waf_incompat|عنوان الواجهة خاطئ أو ToutWAF غير متوافق (قديم جدًا أو ليس ToutWAF). تحقق من المسار السري في https://IP:9443/<المسار-السري> وحدّث ToutWAF عند الحاجة.
en|waf_partial|Panel linked, but the site synchronisation is incomplete: it is retried automatically (see: toutpanel waf status toutwaf).
fr|waf_partial|Panel relié, mais la synchronisation des sites est incomplète : elle est retentée automatiquement (voir : toutpanel waf status toutwaf).
de|waf_partial|Panel verbunden, aber die Synchronisierung der Websites ist unvollständig: sie wird automatisch wiederholt (siehe: toutpanel waf status toutwaf).
es|waf_partial|Panel enlazado, pero la sincronización de los sitios está incompleta: se reintenta automáticamente (véase: toutpanel waf status toutwaf).
it|waf_partial|Pannello collegato, ma la sincronizzazione dei siti è incompleta: viene ritentata automaticamente (vedere: toutpanel waf status toutwaf).
pt|waf_partial|Painel ligado, mas a sincronização dos sites está incompleta: é repetida automaticamente (ver: toutpanel waf status toutwaf).
nl|waf_partial|Paneel gekoppeld, maar de synchronisatie van de sites is onvolledig: ze wordt automatisch herhaald (zie: toutpanel waf status toutwaf).
ru|waf_partial|Панель подключена, но синхронизация сайтов неполная: она повторяется автоматически (см.: toutpanel waf status toutwaf).
zh|waf_partial|面板已连接，但站点同步不完整：将自动重试（参见：toutpanel waf status toutwaf）。
ar|waf_partial|اللوحة مرتبطة لكن مزامنة المواقع غير مكتملة: ستُعاد المحاولة تلقائيًا (انظر: toutpanel waf status toutwaf).
en|waf_firewall|Panel linked, but the firewall restriction was NOT applied: ports 80/443 stay open to everyone.
fr|waf_firewall|Panel relié, mais la restriction du pare-feu n'a PAS été appliquée : les ports 80/443 restent ouverts à tous.
de|waf_firewall|Panel verbunden, aber die Firewall-Einschränkung wurde NICHT angewendet: die Ports 80/443 bleiben für alle offen.
es|waf_firewall|Panel enlazado, pero la restricción del cortafuegos NO se aplicó: los puertos 80/443 siguen abiertos para todos.
it|waf_firewall|Pannello collegato, ma la restrizione del firewall NON è stata applicata: le porte 80/443 restano aperte a tutti.
pt|waf_firewall|Painel ligado, mas a restrição da firewall NÃO foi aplicada: as portas 80/443 permanecem abertas a todos.
nl|waf_firewall|Paneel gekoppeld, maar de firewallbeperking is NIET toegepast: poort 80/443 blijft voor iedereen open.
ru|waf_firewall|Панель подключена, но ограничение брандмауэра НЕ применено: порты 80/443 остаются открытыми для всех.
zh|waf_firewall|面板已连接，但未应用防火墙限制：80/443 端口仍对所有人开放。
ar|waf_firewall|اللوحة مرتبطة لكن تقييد الجدار الناري لم يُطبَّق: يبقى المنفذان 80/443 مفتوحين للجميع.
en|waf_fw_closed|Ports 80/443 are now limited to the ToutWAF (%s).
fr|waf_fw_closed|Les ports 80/443 sont désormais limités au ToutWAF (%s).
de|waf_fw_closed|Die Ports 80/443 sind jetzt auf das ToutWAF beschränkt (%s).
es|waf_fw_closed|Los puertos 80/443 quedan limitados al ToutWAF (%s).
it|waf_fw_closed|Le porte 80/443 sono ora limitate al ToutWAF (%s).
pt|waf_fw_closed|As portas 80/443 ficam agora limitadas ao ToutWAF (%s).
nl|waf_fw_closed|Poort 80/443 is nu beperkt tot de ToutWAF (%s).
ru|waf_fw_closed|Порты 80/443 теперь ограничены только ToutWAF (%s).
zh|waf_fw_closed|80/443 端口现仅限 ToutWAF 访问（%s）。
ar|waf_fw_closed|أصبح المنفذان 80/443 محصورين في ToutWAF (%s).
en|waf_args|Linking refused: invalid arguments or missing confirmation.
fr|waf_args|Raccordement refusé : arguments invalides ou confirmation manquante.
de|waf_args|Verbindung abgelehnt: ungültige Argumente oder fehlende Bestätigung.
es|waf_args|Enlace rechazado: argumentos no válidos o falta de confirmación.
it|waf_args|Collegamento rifiutato: argomenti non validi o conferma mancante.
pt|waf_args|Ligação recusada: argumentos inválidos ou confirmação em falta.
nl|waf_args|Koppeling geweigerd: ongeldige argumenten of ontbrekende bevestiging.
ru|waf_args|Подключение отклонено: недопустимые аргументы или нет подтверждения.
zh|waf_args|连接被拒绝：参数无效或缺少确认。
ar|waf_args|رُفض الربط: وسائط غير صالحة أو تأكيد مفقود.
en|waf_error|Unexpected error while linking to ToutWAF (exit code %s).
fr|waf_error|Erreur inattendue lors du raccordement à ToutWAF (code de sortie %s).
de|waf_error|Unerwarteter Fehler bei der Verbindung mit ToutWAF (Exit-Code %s).
es|waf_error|Error inesperado al enlazar con ToutWAF (código de salida %s).
it|waf_error|Errore imprevisto durante il collegamento a ToutWAF (codice di uscita %s).
pt|waf_error|Erro inesperado ao ligar ao ToutWAF (código de saída %s).
nl|waf_error|Onverwachte fout bij het koppelen aan ToutWAF (afsluitcode %s).
ru|waf_error|Непредвиденная ошибка при подключении к ToutWAF (код выхода %s).
zh|waf_error|连接 ToutWAF 时出现意外错误（退出码 %s）。
ar|waf_error|خطأ غير متوقع أثناء الربط بـ ToutWAF (رمز الخروج %s).
en|waf_detail|Panel detail: %s
fr|waf_detail|Détail renvoyé par le panel : %s
de|waf_detail|Meldung des Panels: %s
es|waf_detail|Detalle devuelto por el panel: %s
it|waf_detail|Dettaglio restituito dal pannello: %s
pt|waf_detail|Detalhe devolvido pelo painel: %s
nl|waf_detail|Melding van het paneel: %s
ru|waf_detail|Сообщение панели: %s
zh|waf_detail|面板返回的详情：%s
ar|waf_detail|التفاصيل الواردة من اللوحة: %s
en|waf_win_local|On Windows, only a remote ToutWAF is supported: use -Waf toutwaf -WafConsole URL (no local WAF is installed).
fr|waf_win_local|Sous Windows, seul un ToutWAF distant est pris en charge : utilisez -Waf toutwaf -WafConsole URL (aucun WAF local n'est installé).
de|waf_win_local|Unter Windows wird nur ein entferntes ToutWAF unterstützt: verwenden Sie -Waf toutwaf -WafConsole URL (es wird keine lokale WAF installiert).
es|waf_win_local|En Windows solo se admite un ToutWAF remoto: use -Waf toutwaf -WafConsole URL (no se instala ningún WAF local).
it|waf_win_local|Su Windows è supportato solo un ToutWAF remoto: usare -Waf toutwaf -WafConsole URL (nessun WAF locale viene installato).
pt|waf_win_local|No Windows, apenas um ToutWAF remoto é suportado: use -Waf toutwaf -WafConsole URL (nenhum WAF local é instalado).
nl|waf_win_local|Onder Windows wordt alleen een externe ToutWAF ondersteund: gebruik -Waf toutwaf -WafConsole URL (er wordt geen lokale WAF geïnstalleerd).
ru|waf_win_local|В Windows поддерживается только удалённый ToutWAF: используйте -Waf toutwaf -WafConsole URL (локальный WAF не устанавливается).
zh|waf_win_local|Windows 上仅支持远程 ToutWAF：请使用 -Waf toutwaf -WafConsole URL（不安装本地 WAF）。
ar|waf_win_local|يُدعَم في Windows ToutWAF بعيد فقط: استخدم -Waf toutwaf -WafConsole URL (لا يُثبَّت أي WAF محلي).
en|lbl_waf|WAF engine
fr|lbl_waf|Moteur WAF
de|lbl_waf|WAF-Engine
es|lbl_waf|Motor WAF
it|lbl_waf|Motore WAF
pt|lbl_waf|Motor WAF
nl|lbl_waf|WAF-engine
ru|lbl_waf|Движок WAF
zh|lbl_waf|WAF 引擎
ar|lbl_waf|محرك WAF
en|lbl_waf_link|WAF link
fr|lbl_waf_link|Liaison WAF
de|lbl_waf_link|WAF-Verbindung
es|lbl_waf_link|Enlace WAF
it|lbl_waf_link|Collegamento WAF
pt|lbl_waf_link|Ligação WAF
nl|lbl_waf_link|WAF-koppeling
ru|lbl_waf_link|Связь с WAF
zh|lbl_waf_link|WAF 连接
ar|lbl_waf_link|ارتباط WAF
en|lbl_waf_pin|Pinned fingerprint
fr|lbl_waf_pin|Empreinte épinglée
de|lbl_waf_pin|Festgeschriebener Fingerabdruck
es|lbl_waf_pin|Huella fijada
it|lbl_waf_pin|Impronta fissata
pt|lbl_waf_pin|Impressão digital fixada
nl|lbl_waf_pin|Vastgepinde vingerafdruk
ru|lbl_waf_pin|Закреплённый отпечаток
zh|lbl_waf_pin|已固定的指纹
ar|lbl_waf_pin|البصمة المثبتة
en|lbl_waf_fw|WAF firewall
fr|lbl_waf_fw|Pare-feu WAF
de|lbl_waf_fw|WAF-Firewall
es|lbl_waf_fw|Cortafuegos WAF
it|lbl_waf_fw|Firewall WAF
pt|lbl_waf_fw|Firewall WAF
nl|lbl_waf_fw|WAF-firewall
ru|lbl_waf_fw|Брандмауэр WAF
zh|lbl_waf_fw|WAF 防火墙
ar|lbl_waf_fw|جدار WAF الناري
en|waf_info_remote|remote ToutWAF %s (token not displayed)
fr|waf_info_remote|ToutWAF distant %s (jeton non affiché)
de|waf_info_remote|entferntes ToutWAF %s (Token nicht angezeigt)
es|waf_info_remote|ToutWAF remoto %s (token no mostrado)
it|waf_info_remote|ToutWAF remoto %s (token non mostrato)
pt|waf_info_remote|ToutWAF remoto %s (token não apresentado)
nl|waf_info_remote|externe ToutWAF %s (token niet getoond)
ru|waf_info_remote|удалённый ToutWAF %s (токен не показывается)
zh|waf_info_remote|远程 ToutWAF %s（不显示令牌）
ar|waf_info_remote|ToutWAF بعيد %s (الرمز غير معروض)
en|waf_st_linked|linked
fr|waf_st_linked|relié
de|waf_st_linked|verbunden
es|waf_st_linked|enlazado
it|waf_st_linked|collegato
pt|waf_st_linked|ligado
nl|waf_st_linked|gekoppeld
ru|waf_st_linked|подключено
zh|waf_st_linked|已连接
ar|waf_st_linked|مرتبط
en|waf_st_partial|linked, site synchronisation incomplete
fr|waf_st_partial|relié, synchronisation des sites incomplète
de|waf_st_partial|verbunden, Synchronisierung der Websites unvollständig
es|waf_st_partial|enlazado, sincronización de sitios incompleta
it|waf_st_partial|collegato, sincronizzazione dei siti incompleta
pt|waf_st_partial|ligado, sincronização dos sites incompleta
nl|waf_st_partial|gekoppeld, synchronisatie van sites onvolledig
ru|waf_st_partial|подключено, синхронизация сайтов неполная
zh|waf_st_partial|已连接，站点同步不完整
ar|waf_st_partial|مرتبط، مزامنة المواقع غير مكتملة
en|waf_st_unlinked|NOT LINKED (the panel stays installed; see the message above)
fr|waf_st_unlinked|NON RELIÉ (le panel reste installé ; voir le message ci-dessus)
de|waf_st_unlinked|NICHT VERBUNDEN (das Panel bleibt installiert; siehe Meldung oben)
es|waf_st_unlinked|NO ENLAZADO (el panel sigue instalado; véase el mensaje anterior)
it|waf_st_unlinked|NON COLLEGATO (il pannello resta installato; vedere il messaggio sopra)
pt|waf_st_unlinked|NÃO LIGADO (o painel permanece instalado; ver a mensagem acima)
nl|waf_st_unlinked|NIET GEKOPPELD (het paneel blijft geïnstalleerd; zie de melding hierboven)
ru|waf_st_unlinked|НЕ ПОДКЛЮЧЕНО (панель остаётся установленной; см. сообщение выше)
zh|waf_st_unlinked|未连接（面板仍已安装；见上方消息）
ar|waf_st_unlinked|غير مرتبط (تبقى اللوحة مثبّتة؛ انظر الرسالة أعلاه)
en|waf_pin_none|none (link not verified by fingerprint)
fr|waf_pin_none|aucune (liaison non vérifiée par empreinte)
de|waf_pin_none|keiner (Verbindung nicht per Fingerabdruck geprüft)
es|waf_pin_none|ninguna (enlace no verificado por huella)
it|waf_pin_none|nessuna (collegamento non verificato tramite impronta)
pt|waf_pin_none|nenhuma (ligação não verificada por impressão digital)
nl|waf_pin_none|geen (koppeling niet met vingerafdruk gecontroleerd)
ru|waf_pin_none|нет (соединение не проверено по отпечатку)
zh|waf_pin_none|无（连接未经指纹验证）
ar|waf_pin_none|لا شيء (الاتصال غير متحقق منه بالبصمة)
en|waf_fw_on|ports 80/443 limited to %s
fr|waf_fw_on|ports 80/443 limités à %s
de|waf_fw_on|Ports 80/443 beschränkt auf %s
es|waf_fw_on|puertos 80/443 limitados a %s
it|waf_fw_on|porte 80/443 limitate a %s
pt|waf_fw_on|portas 80/443 limitadas a %s
nl|waf_fw_on|poort 80/443 beperkt tot %s
ru|waf_fw_on|порты 80/443 ограничены: %s
zh|waf_fw_on|80/443 端口仅限 %s
ar|waf_fw_on|المنفذان 80/443 محصوران في %s
en|waf_fw_off|no restriction (80/443 open)
fr|waf_fw_off|aucune restriction (80/443 ouverts)
de|waf_fw_off|keine Einschränkung (80/443 offen)
es|waf_fw_off|sin restricción (80/443 abiertos)
it|waf_fw_off|nessuna restrizione (80/443 aperte)
pt|waf_fw_off|sem restrição (80/443 abertas)
nl|waf_fw_off|geen beperking (80/443 open)
ru|waf_fw_off|без ограничений (80/443 открыты)
zh|waf_fw_off|无限制（80/443 开放）
ar|waf_fw_off|بلا تقييد (80/443 مفتوحان)
en|waf_token_arg_refused_win|The ToutWAF API token must never be passed as an argument (it would show in the process list and the command history). Set $env:TOUTPANEL_WAF_TOKEN, or use -WafTokenFile FILE or -WafTokenStdin.
fr|waf_token_arg_refused_win|Le jeton d'API ToutWAF ne doit jamais être passé en argument (il serait visible dans la liste des processus et l'historique des commandes). Définissez $env:TOUTPANEL_WAF_TOKEN, ou utilisez -WafTokenFile FICHIER ou -WafTokenStdin.
de|waf_token_arg_refused_win|Das ToutWAF-API-Token darf nie als Argument übergeben werden (es wäre in der Prozessliste und im Befehlsverlauf sichtbar). Setzen Sie $env:TOUTPANEL_WAF_TOKEN oder verwenden Sie -WafTokenFile DATEI oder -WafTokenStdin.
es|waf_token_arg_refused_win|El token de API de ToutWAF nunca debe pasarse como argumento (sería visible en la lista de procesos y en el historial de comandos). Defina $env:TOUTPANEL_WAF_TOKEN o use -WafTokenFile ARCHIVO o -WafTokenStdin.
it|waf_token_arg_refused_win|Il token API di ToutWAF non deve mai essere passato come argomento (sarebbe visibile nell'elenco dei processi e nella cronologia dei comandi). Impostare $env:TOUTPANEL_WAF_TOKEN oppure usare -WafTokenFile FILE o -WafTokenStdin.
pt|waf_token_arg_refused_win|O token da API do ToutWAF nunca deve ser passado como argumento (ficaria visível na lista de processos e no histórico de comandos). Defina $env:TOUTPANEL_WAF_TOKEN ou use -WafTokenFile FICHEIRO ou -WafTokenStdin.
nl|waf_token_arg_refused_win|Het ToutWAF-API-token mag nooit als argument worden doorgegeven (het zou zichtbaar zijn in de proceslijst en de opdrachtgeschiedenis). Stel $env:TOUTPANEL_WAF_TOKEN in of gebruik -WafTokenFile BESTAND of -WafTokenStdin.
ru|waf_token_arg_refused_win|Токен API ToutWAF нельзя передавать аргументом (он будет виден в списке процессов и истории команд). Задайте $env:TOUTPANEL_WAF_TOKEN или используйте -WafTokenFile ФАЙЛ либо -WafTokenStdin.
zh|waf_token_arg_refused_win|ToutWAF 的 API 令牌绝不能作为参数传递（会出现在进程列表和命令历史中）。请设置 $env:TOUTPANEL_WAF_TOKEN，或使用 -WafTokenFile 文件 或 -WafTokenStdin。
ar|waf_token_arg_refused_win|يجب ألا يُمرَّر رمز API الخاص بـ ToutWAF كوسيط أبدًا (سيظهر في قائمة العمليات وسجل الأوامر). عيّن $env:TOUTPANEL_WAF_TOKEN أو استخدم -WafTokenFile ملف أو -WafTokenStdin.
en|waf_token_missing_win|ToutWAF API token missing: set $env:TOUTPANEL_WAF_TOKEN, or use -WafTokenFile FILE / -WafTokenStdin.
fr|waf_token_missing_win|Jeton d'API ToutWAF absent : définissez $env:TOUTPANEL_WAF_TOKEN, ou utilisez -WafTokenFile FICHIER / -WafTokenStdin.
de|waf_token_missing_win|ToutWAF-API-Token fehlt: Setzen Sie $env:TOUTPANEL_WAF_TOKEN oder verwenden Sie -WafTokenFile DATEI / -WafTokenStdin.
es|waf_token_missing_win|Falta el token de API de ToutWAF: defina $env:TOUTPANEL_WAF_TOKEN o use -WafTokenFile ARCHIVO / -WafTokenStdin.
it|waf_token_missing_win|Token API di ToutWAF mancante: impostare $env:TOUTPANEL_WAF_TOKEN oppure usare -WafTokenFile FILE / -WafTokenStdin.
pt|waf_token_missing_win|Falta o token da API do ToutWAF: defina $env:TOUTPANEL_WAF_TOKEN ou use -WafTokenFile FICHEIRO / -WafTokenStdin.
nl|waf_token_missing_win|ToutWAF-API-token ontbreekt: stel $env:TOUTPANEL_WAF_TOKEN in of gebruik -WafTokenFile BESTAND / -WafTokenStdin.
ru|waf_token_missing_win|Не задан токен API ToutWAF: задайте $env:TOUTPANEL_WAF_TOKEN или используйте -WafTokenFile ФАЙЛ / -WafTokenStdin.
zh|waf_token_missing_win|缺少 ToutWAF 的 API 令牌：请设置 $env:TOUTPANEL_WAF_TOKEN，或使用 -WafTokenFile 文件 / -WafTokenStdin。
ar|waf_token_missing_win|رمز API الخاص بـ ToutWAF مفقود: عيّن $env:TOUTPANEL_WAF_TOKEN أو استخدم -WafTokenFile ملف / -WafTokenStdin.
en|waf_console_empty_win|The ToutWAF console is empty: is $env:TOUTPANEL_WAF_URL set?
fr|waf_console_empty_win|La console ToutWAF est vide : $env:TOUTPANEL_WAF_URL est-elle définie ?
de|waf_console_empty_win|Die ToutWAF-Konsole ist leer: ist $env:TOUTPANEL_WAF_URL gesetzt?
es|waf_console_empty_win|La consola de ToutWAF está vacía: ¿está definida $env:TOUTPANEL_WAF_URL?
it|waf_console_empty_win|La console ToutWAF è vuota: $env:TOUTPANEL_WAF_URL è impostata?
pt|waf_console_empty_win|A consola do ToutWAF está vazia: $env:TOUTPANEL_WAF_URL está definida?
nl|waf_console_empty_win|De ToutWAF-console is leeg: is $env:TOUTPANEL_WAF_URL ingesteld?
ru|waf_console_empty_win|Консоль ToutWAF не задана: задана ли $env:TOUTPANEL_WAF_URL?
zh|waf_console_empty_win|ToutWAF 控制台地址为空：是否已设置 $env:TOUTPANEL_WAF_URL？
ar|waf_console_empty_win|واجهة ToutWAF فارغة: هل عُيّن $env:TOUTPANEL_WAF_URL؟
en|h_waf_console_win|console of the remote ToutWAF with its secret path, e.g. https://IP:9443/<path> (also $env:TOUTPANEL_WAF_URL)
fr|h_waf_console_win|console du ToutWAF distant avec son chemin secret, ex. https://IP:9443/<chemin> (aussi $env:TOUTPANEL_WAF_URL)
de|h_waf_console_win|Konsole des entfernten ToutWAF mit geheimem Pfad, z. B. https://IP:9443/<Pfad> (auch $env:TOUTPANEL_WAF_URL)
es|h_waf_console_win|consola del ToutWAF remoto con su ruta secreta, p. ej. https://IP:9443/<ruta> (también $env:TOUTPANEL_WAF_URL)
it|h_waf_console_win|console del ToutWAF remoto con il suo percorso segreto, es. https://IP:9443/<percorso> (anche $env:TOUTPANEL_WAF_URL)
pt|h_waf_console_win|consola do ToutWAF remoto com o seu caminho secreto, ex. https://IP:9443/<caminho> (também $env:TOUTPANEL_WAF_URL)
nl|h_waf_console_win|console van de externe ToutWAF met geheim pad, bijv. https://IP:9443/<pad> (ook $env:TOUTPANEL_WAF_URL)
ru|h_waf_console_win|консоль удалённого ToutWAF с секретным путём, например https://IP:9443/<путь> (также $env:TOUTPANEL_WAF_URL)
zh|h_waf_console_win|远程 ToutWAF 的控制台及其秘密路径，如 https://IP:9443/<路径>（也可用 $env:TOUTPANEL_WAF_URL）
ar|h_waf_console_win|واجهة ToutWAF البعيد مع مسارها السري، مثل https://IP:9443/<المسار> (ويمكن أيضًا $env:TOUTPANEL_WAF_URL)
en|h_waf_token_env_win|API token: variable $env:TOUTPANEL_WAF_TOKEN; never an argument (-WafToken is refused)
fr|h_waf_token_env_win|jeton d'API : variable $env:TOUTPANEL_WAF_TOKEN ; jamais en argument (-WafToken est refusé)
de|h_waf_token_env_win|API-Token: Variable $env:TOUTPANEL_WAF_TOKEN; nie als Argument (-WafToken wird abgelehnt)
es|h_waf_token_env_win|token de API: variable $env:TOUTPANEL_WAF_TOKEN; nunca como argumento (-WafToken se rechaza)
it|h_waf_token_env_win|token API: variabile $env:TOUTPANEL_WAF_TOKEN; mai come argomento (-WafToken viene rifiutato)
pt|h_waf_token_env_win|token da API: variável $env:TOUTPANEL_WAF_TOKEN; nunca como argumento (-WafToken é recusado)
nl|h_waf_token_env_win|API-token: variabele $env:TOUTPANEL_WAF_TOKEN; nooit als argument (-WafToken wordt geweigerd)
ru|h_waf_token_env_win|токен API: переменная $env:TOUTPANEL_WAF_TOKEN; никогда не аргументом (-WafToken отклоняется)
zh|h_waf_token_env_win|API 令牌：变量 $env:TOUTPANEL_WAF_TOKEN；绝不作为参数（-WafToken 会被拒绝）
ar|h_waf_token_env_win|رمز API: المتغير $env:TOUTPANEL_WAF_TOKEN؛ لا يُمرَّر أبدًا كوسيط (يُرفض -WafToken)
en|hs_account|Account and access:
fr|hs_account|Compte et accès :
de|hs_account|Konto und Zugang:
es|hs_account|Cuenta y acceso:
it|hs_account|Account e accesso:
pt|hs_account|Conta e acesso:
nl|hs_account|Account en toegang:
ru|hs_account|Учётная запись и доступ:
zh|hs_account|账户与访问：
ar|hs_account|الحساب والوصول:
en|hs_network|Network and ports:
fr|hs_network|Réseau et ports :
de|hs_network|Netzwerk und Ports:
es|hs_network|Red y puertos:
it|hs_network|Rete e porte:
pt|hs_network|Rede e portas:
nl|hs_network|Netwerk en poorten:
ru|hs_network|Сеть и порты:
zh|hs_network|网络与端口：
ar|hs_network|الشبكة والمنافذ:
en|hs_dirs|Directories and source:
fr|hs_dirs|Dossiers et source :
de|hs_dirs|Verzeichnisse und Quelle:
es|hs_dirs|Directorios y origen:
it|hs_dirs|Directory e sorgente:
pt|hs_dirs|Diretórios e origem:
nl|hs_dirs|Mappen en bron:
ru|hs_dirs|Каталоги и источник:
zh|hs_dirs|目录与来源：
ar|hs_dirs|المجلدات والمصدر:
en|hs_version|Version and mode (install, update, uninstall):
fr|hs_version|Version et mode (installation, mise à jour, désinstallation) :
de|hs_version|Version und Modus (Installation, Update, Deinstallation):
es|hs_version|Versión y modo (instalación, actualización, desinstalación):
it|hs_version|Versione e modalità (installazione, aggiornamento, disinstallazione):
pt|hs_version|Versão e modo (instalação, atualização, desinstalação):
nl|hs_version|Versie en modus (installatie, update, verwijdering):
ru|hs_version|Версия и режим (установка, обновление, удаление):
zh|hs_version|版本与模式（安装、更新、卸载）：
ar|hs_version|الإصدار والوضع (التثبيت، التحديث، الإزالة):
en|hs_stack|Software stack:
fr|hs_stack|Pile logicielle :
de|hs_stack|Software-Stack:
es|hs_stack|Pila de software:
it|hs_stack|Stack software:
pt|hs_stack|Pilha de software:
nl|hs_stack|Softwarestack:
ru|hs_stack|Программный стек:
zh|hs_stack|软件栈：
ar|hs_stack|حزمة البرامج:
en|hs_firewall|Firewall:
fr|hs_firewall|Pare-feu :
de|hs_firewall|Firewall:
es|hs_firewall|Cortafuegos:
it|hs_firewall|Firewall:
pt|hs_firewall|Firewall:
nl|hs_firewall|Firewall:
ru|hs_firewall|Брандмауэр:
zh|hs_firewall|防火墙：
ar|hs_firewall|جدار الحماية:
en|hs_waf|WAF engine:
fr|hs_waf|Moteur WAF :
de|hs_waf|WAF-Engine:
es|hs_waf|Motor WAF:
it|hs_waf|Motore WAF:
pt|hs_waf|Motor WAF:
nl|hs_waf|WAF-engine:
ru|hs_waf|Движок WAF:
zh|hs_waf|WAF 引擎：
ar|hs_waf|محرك WAF:
en|hs_misc|Miscellaneous:
fr|hs_misc|Divers :
de|hs_misc|Sonstiges:
es|hs_misc|Varios:
it|hs_misc|Varie:
pt|hs_misc|Diversos:
nl|hs_misc|Overig:
ru|hs_misc|Прочее:
zh|hs_misc|其他：
ar|hs_misc|متفرقات:
en|h_home_linux|panel directory (default: %s; an existing installation in %s is detected and kept as is, never moved)
fr|h_home_linux|répertoire du panel (défaut : %s ; une installation existante dans %s est détectée et conservée telle quelle, jamais déplacée)
de|h_home_linux|Verzeichnis des Panels (Standard: %s; eine bestehende Installation in %s wird erkannt und unverändert beibehalten, nie verschoben)
es|h_home_linux|directorio del panel (predeterminado: %s; una instalación existente en %s se detecta y se conserva tal cual, nunca se mueve)
it|h_home_linux|directory del pannello (predefinita: %s; un'installazione esistente in %s viene rilevata e conservata così com'è, mai spostata)
pt|h_home_linux|diretório do painel (predefinição: %s; uma instalação existente em %s é detetada e mantida como está, nunca movida)
nl|h_home_linux|map van het paneel (standaard: %s; een bestaande installatie in %s wordt herkend en ongewijzigd behouden, nooit verplaatst)
ru|h_home_linux|каталог панели (по умолчанию: %s; существующая установка в %s обнаруживается и остаётся как есть, без переноса)
zh|h_home_linux|面板目录（默认：%s；检测到 %s 中的现有安装时原样保留，绝不移动）
ar|h_home_linux|مجلد اللوحة (الافتراضي: %s؛ يُكتشف أي تثبيت موجود في %s ويُبقى كما هو دون نقل)
en|h_stack_note|stack options are passed as they are to toutpanel stack apply --yes once the panel is installed and started; without --profile the selection starts empty (custom). Without any stack option: the default stack, or a profile question in a terminal.
fr|h_stack_note|les options de pile sont transmises telles quelles à toutpanel stack apply --yes une fois le panel installé et démarré ; sans --profile la sélection part de zéro (custom). Sans option de pile : la pile par défaut, ou une question sur le profil dans un terminal.
de|h_stack_note|Stack-Optionen werden unverändert an toutpanel stack apply --yes übergeben, sobald das Panel installiert und gestartet ist; ohne --profile beginnt die Auswahl leer (custom). Ohne Stack-Option: der Standard-Stack oder eine Profilfrage im Terminal.
es|h_stack_note|las opciones de pila se pasan tal cual a toutpanel stack apply --yes cuando el panel está instalado y en marcha; sin --profile la selección parte de cero (custom). Sin opción de pila: la pila predeterminada, o una pregunta de perfil en un terminal.
it|h_stack_note|le opzioni dello stack vengono passate invariate a toutpanel stack apply --yes una volta installato e avviato il pannello; senza --profile la selezione parte da zero (custom). Senza opzioni dello stack: lo stack predefinito, oppure una domanda sul profilo in un terminale.
pt|h_stack_note|as opções da pilha são passadas tal como estão a toutpanel stack apply --yes depois de o painel estar instalado e iniciado; sem --profile a seleção começa vazia (custom). Sem opção de pilha: a pilha predefinida, ou uma pergunta sobre o perfil num terminal.
nl|h_stack_note|stackopties worden ongewijzigd doorgegeven aan toutpanel stack apply --yes zodra het paneel is geïnstalleerd en gestart; zonder --profile begint de selectie leeg (custom). Zonder stackoptie: de standaardstack, of een profielvraag in een terminal.
ru|h_stack_note|параметры стека передаются без изменений в toutpanel stack apply --yes после установки и запуска панели; без --profile выбор начинается с пустого (custom). Без параметров стека: стек по умолчанию или вопрос о профиле в терминале.
zh|h_stack_note|面板安装并启动后，软件栈选项会原样传给 toutpanel stack apply --yes；未指定 --profile 时从空白选择（custom）开始。未给出任何软件栈选项：使用默认软件栈，或在终端中询问配置方案。
ar|h_stack_note|تُمرَّر خيارات الحزمة كما هي إلى toutpanel stack apply --yes بعد تثبيت اللوحة وتشغيلها؛ ودون --profile يبدأ الاختيار فارغًا (custom). ودون أي خيار للحزمة: الحزمة الافتراضية، أو سؤال عن الملف في الطرفية.
en|h_profile|starting profile: single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (list: toutpanel stack profiles)
fr|h_profile|profil de départ : single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (liste : toutpanel stack profiles)
de|h_profile|Startprofil: single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (Liste: toutpanel stack profiles)
es|h_profile|perfil de partida: single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (lista: toutpanel stack profiles)
it|h_profile|profilo di partenza: single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (elenco: toutpanel stack profiles)
pt|h_profile|perfil de partida: single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (lista: toutpanel stack profiles)
nl|h_profile|startprofiel: single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (lijst: toutpanel stack profiles)
ru|h_profile|начальный профиль: single-site, multi-site, hosting, performance, application, mail-only, dns-only, node, lamp, standard, custom (список: toutpanel stack profiles)
zh|h_profile|起始配置方案：single-site、multi-site、hosting、performance、application、mail-only、dns-only、node、lamp、standard、custom（列表：toutpanel stack profiles）
ar|h_profile|الملف الابتدائي: single-site، multi-site، hosting، performance، application، mail-only، dns-only، node، lamp، standard، custom (القائمة: toutpanel stack profiles)
en|h_web|web server: nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (commercial, experimental: --accept-litespeed-license) or none
fr|h_web|serveur web : nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (commercial, expérimental : --accept-litespeed-license) ou none
de|h_web|Webserver: nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (kommerziell, experimentell: --accept-litespeed-license) oder none
es|h_web|servidor web: nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (comercial, experimental: --accept-litespeed-license) o none
it|h_web|server web: nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (commerciale, sperimentale: --accept-litespeed-license) o none
pt|h_web|servidor web: nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (comercial, experimental: --accept-litespeed-license) ou none
nl|h_web|webserver: nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (commercieel, experimenteel: --accept-litespeed-license) of none
ru|h_web|веб-сервер: nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3] (коммерческий, экспериментальный: --accept-litespeed-license) или none
zh|h_web|Web 服务器：nginx、apache、nginx-apache、openlitespeed[:1.9], litespeed[:6.3] (商业产品，实验性：--accept-litespeed-license) 或 none
ar|h_web|خادم الويب: nginx أو apache أو nginx-apache أو openlitespeed[:1.9], litespeed[:6.3] (تجاري وتجريبي: --accept-litespeed-license) أو none
en|h_php|PHP versions separated by commas (e.g. 8.4,8.5) or none
fr|h_php|versions de PHP séparées par des virgules (ex. 8.4,8.5) ou none
de|h_php|PHP-Versionen, durch Kommas getrennt (z. B. 8.4,8.5), oder none
es|h_php|versiones de PHP separadas por comas (p. ej. 8.4,8.5) o none
it|h_php|versioni di PHP separate da virgole (es. 8.4,8.5) o none
pt|h_php|versões do PHP separadas por vírgulas (ex. 8.4,8.5) ou none
nl|h_php|PHP-versies gescheiden door komma's (bijv. 8.4,8.5) of none
ru|h_php|версии PHP через запятую (например, 8.4,8.5) или none
zh|h_php|PHP 版本，以逗号分隔（如 8.4,8.5），或 none
ar|h_php|إصدارات PHP مفصولة بفواصل (مثل 8.4,8.5) أو none
en|h_php_default|PHP version used by default on the command line (e.g. 8.5)
fr|h_php_default|version de PHP par défaut en ligne de commande (ex. 8.5)
de|h_php_default|standardmäßige PHP-Version auf der Kommandozeile (z. B. 8.5)
es|h_php_default|versión de PHP predeterminada en la línea de comandos (p. ej. 8.5)
it|h_php_default|versione di PHP predefinita da riga di comando (es. 8.5)
pt|h_php_default|versão do PHP predefinida na linha de comandos (ex. 8.5)
nl|h_php_default|standaard PHP-versie op de opdrachtregel (bijv. 8.5)
ru|h_php_default|версия PHP по умолчанию в командной строке (например, 8.5)
zh|h_php_default|命令行默认使用的 PHP 版本（如 8.5）
ar|h_php_default|إصدار PHP الافتراضي في سطر الأوامر (مثل 8.5)
en|h_php_ext|PHP extension set: minimal, standard or full
fr|h_php_ext|jeu d'extensions PHP : minimal, standard ou full
de|h_php_ext|PHP-Erweiterungssatz: minimal, standard oder full
es|h_php_ext|conjunto de extensiones de PHP: minimal, standard o full
it|h_php_ext|set di estensioni PHP: minimal, standard o full
pt|h_php_ext|conjunto de extensões do PHP: minimal, standard ou full
nl|h_php_ext|PHP-extensieset: minimal, standard of full
ru|h_php_ext|набор расширений PHP: minimal, standard или full
zh|h_php_ext|PHP 扩展集：minimal、standard 或 full
ar|h_php_ext|مجموعة امتدادات PHP: minimal أو standard أو full
en|h_db|database engine(s): mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] or none (a list is allowed: mariadb:11.4,postgresql:17)
fr|h_db|moteur(s) de base de données : mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] ou none (liste possible : mariadb:11.4,postgresql:17)
de|h_db|Datenbank-Engine(s): mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] oder none (Liste möglich: mariadb:11.4,postgresql:17)
es|h_db|motor(es) de base de datos: mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] o none (se admite una lista: mariadb:11.4,postgresql:17)
it|h_db|motore/i di database: mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] o none (elenco possibile: mariadb:11.4,postgresql:17)
pt|h_db|motor(es) de base de dados: mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] ou none (lista possível: mariadb:11.4,postgresql:17)
nl|h_db|databaseengine(s): mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] of none (lijst mogelijk: mariadb:11.4,postgresql:17)
ru|h_db|СУБД: mariadb[:11.4], mysql[:8.4], percona, postgresql[:17] или none (можно списком: mariadb:11.4,postgresql:17)
zh|h_db|数据库引擎：mariadb[:11.4]、mysql[:8.4]、percona、postgresql[:17] 或 none（可用列表：mariadb:11.4,postgresql:17）
ar|h_db|محرك (محركات) قواعد البيانات: mariadb[:11.4] أو mysql[:8.4] أو percona أو postgresql[:17] أو none (يمكن استخدام قائمة: mariadb:11.4,postgresql:17)
en|h_redis|add Redis (or Valkey)
fr|h_redis|ajoute Redis (ou Valkey)
de|h_redis|fügt Redis (oder Valkey) hinzu
es|h_redis|añade Redis (o Valkey)
it|h_redis|aggiunge Redis (o Valkey)
pt|h_redis|adiciona Redis (ou Valkey)
nl|h_redis|voegt Redis (of Valkey) toe
ru|h_redis|добавляет Redis (или Valkey)
zh|h_redis|添加 Redis（或 Valkey）
ar|h_redis|يضيف Redis (أو Valkey)
en|h_accel|accelerators, comma-separated: opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
fr|h_accel|accélérateurs séparés par des virgules : opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
de|h_accel|Beschleuniger, durch Kommas getrennt: opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
es|h_accel|aceleradores separados por comas: opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
it|h_accel|acceleratori separati da virgole: opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
pt|h_accel|aceleradores separados por vírgulas: opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
nl|h_accel|versnellers gescheiden door komma's: opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
ru|h_accel|ускорители через запятую: opcache, jit, apcu, redis, memcached, fastcgi-cache, varnish, brotli, zstd, http3, ioncube
zh|h_accel|加速组件，以逗号分隔：opcache、jit、apcu、redis、memcached、fastcgi-cache、varnish、brotli、zstd、http3、ioncube
ar|h_accel|المُسرِّعات مفصولة بفواصل: opcache وjit وapcu وredis وmemcached وfastcgi-cache وvarnish وbrotli وzstd وhttp3 وioncube
en|h_ftp|FTP engine: builtin, pureftpd, proftpd, vsftpd, sftp or none
fr|h_ftp|moteur FTP : builtin, pureftpd, proftpd, vsftpd, sftp ou none
de|h_ftp|FTP-Engine: builtin, pureftpd, proftpd, vsftpd, sftp oder none
es|h_ftp|motor FTP: builtin, pureftpd, proftpd, vsftpd, sftp o none
it|h_ftp|motore FTP: builtin, pureftpd, proftpd, vsftpd, sftp o none
pt|h_ftp|motor FTP: builtin, pureftpd, proftpd, vsftpd, sftp ou none
nl|h_ftp|FTP-engine: builtin, pureftpd, proftpd, vsftpd, sftp of none
ru|h_ftp|FTP-сервер: builtin, pureftpd, proftpd, vsftpd, sftp или none
zh|h_ftp|FTP 引擎：builtin、pureftpd、proftpd、vsftpd、sftp 或 none
ar|h_ftp|محرك FTP: builtin أو pureftpd أو proftpd أو vsftpd أو sftp أو none
en|h_mail_engine|mail server of the stack: postfix, postfix-clamav, postfix-light, exim, relay or none; without a value: legacy mail installation (see below)
fr|h_mail_engine|serveur de courrier de la pile : postfix, postfix-clamav, postfix-light, exim, relay ou none ; sans valeur : installation du courrier historique (voir plus bas)
de|h_mail_engine|Mailserver des Stacks: postfix, postfix-clamav, postfix-light, exim, relay oder none; ohne Wert: bisherige Mail-Installation (siehe unten)
es|h_mail_engine|servidor de correo de la pila: postfix, postfix-clamav, postfix-light, exim, relay o none; sin valor: instalación de correo tradicional (véase abajo)
it|h_mail_engine|server di posta dello stack: postfix, postfix-clamav, postfix-light, exim, relay o none; senza valore: installazione di posta tradizionale (vedere sotto)
pt|h_mail_engine|servidor de correio da pilha: postfix, postfix-clamav, postfix-light, exim, relay ou none; sem valor: instalação de correio tradicional (ver abaixo)
nl|h_mail_engine|mailserver van de stack: postfix, postfix-clamav, postfix-light, exim, relay of none; zonder waarde: de oorspronkelijke mailinstallatie (zie hieronder)
ru|h_mail_engine|почтовый сервер стека: postfix, postfix-clamav, postfix-light, exim, relay или none; без значения: прежняя установка почты (см. ниже)
zh|h_mail_engine|软件栈的邮件服务器：postfix、postfix-clamav、postfix-light、exim、relay 或 none；不带值：沿用旧的邮件安装方式（见下）
ar|h_mail_engine|خادم البريد في الحزمة: postfix أو postfix-clamav أو postfix-light أو exim أو relay أو none؛ دون قيمة: تثبيت البريد التقليدي (انظر أدناه)
en|h_dns|DNS engine: bind, powerdns, knot, external or none
fr|h_dns|moteur DNS : bind, powerdns, knot, external ou none
de|h_dns|DNS-Engine: bind, powerdns, knot, external oder none
es|h_dns|motor DNS: bind, powerdns, knot, external o none
it|h_dns|motore DNS: bind, powerdns, knot, external o none
pt|h_dns|motor DNS: bind, powerdns, knot, external ou none
nl|h_dns|DNS-engine: bind, powerdns, knot, external of none
ru|h_dns|DNS-сервер: bind, powerdns, knot, external или none
zh|h_dns|DNS 引擎：bind、powerdns、knot、external 或 none
ar|h_dns|محرك DNS: bind أو powerdns أو knot أو external أو none
en|h_security|security components, comma-separated: firewall, fail2ban, modsecurity, clamav, toutwaf
fr|h_security|composants de sécurité séparés par des virgules : firewall, fail2ban, modsecurity, clamav, toutwaf
de|h_security|Sicherheitskomponenten, durch Kommas getrennt: firewall, fail2ban, modsecurity, clamav, toutwaf
es|h_security|componentes de seguridad separados por comas: firewall, fail2ban, modsecurity, clamav, toutwaf
it|h_security|componenti di sicurezza separati da virgole: firewall, fail2ban, modsecurity, clamav, toutwaf
pt|h_security|componentes de segurança separados por vírgulas: firewall, fail2ban, modsecurity, clamav, toutwaf
nl|h_security|beveiligingscomponenten gescheiden door komma's: firewall, fail2ban, modsecurity, clamav, toutwaf
ru|h_security|компоненты безопасности через запятую: firewall, fail2ban, modsecurity, clamav, toutwaf
zh|h_security|安全组件，以逗号分隔：firewall、fail2ban、modsecurity、clamav、toutwaf
ar|h_security|مكونات الأمان مفصولة بفواصل: firewall وfail2ban وmodsecurity وclamav وtoutwaf
en|h_runtime|runtimes, comma-separated: nodejs, python, go, ruby, java, docker
fr|h_runtime|environnements d'exécution séparés par des virgules : nodejs, python, go, ruby, java, docker
de|h_runtime|Laufzeitumgebungen, durch Kommas getrennt: nodejs, python, go, ruby, java, docker
es|h_runtime|entornos de ejecución separados por comas: nodejs, python, go, ruby, java, docker
it|h_runtime|ambienti di esecuzione separati da virgole: nodejs, python, go, ruby, java, docker
pt|h_runtime|ambientes de execução separados por vírgulas: nodejs, python, go, ruby, java, docker
nl|h_runtime|runtimes gescheiden door komma's: nodejs, python, go, ruby, java, docker
ru|h_runtime|среды выполнения через запятую: nodejs, python, go, ruby, java, docker
zh|h_runtime|运行时环境，以逗号分隔：nodejs、python、go、ruby、java、docker
ar|h_runtime|بيئات التشغيل مفصولة بفواصل: nodejs وpython وgo وruby وjava وdocker
en|h_tools|tools, comma-separated: certbot, git, composer, phpmyadmin, adminer, restic, goaccess
fr|h_tools|outils séparés par des virgules : certbot, git, composer, phpmyadmin, adminer, restic, goaccess
de|h_tools|Werkzeuge, durch Kommas getrennt: certbot, git, composer, phpmyadmin, adminer, restic, goaccess
es|h_tools|herramientas separadas por comas: certbot, git, composer, phpmyadmin, adminer, restic, goaccess
it|h_tools|strumenti separati da virgole: certbot, git, composer, phpmyadmin, adminer, restic, goaccess
pt|h_tools|ferramentas separadas por vírgulas: certbot, git, composer, phpmyadmin, adminer, restic, goaccess
nl|h_tools|hulpmiddelen gescheiden door komma's: certbot, git, composer, phpmyadmin, adminer, restic, goaccess
ru|h_tools|утилиты через запятую: certbot, git, composer, phpmyadmin, adminer, restic, goaccess
zh|h_tools|工具，以逗号分隔：certbot、git、composer、phpmyadmin、adminer、restic、goaccess
ar|h_tools|الأدوات مفصولة بفواصل: certbot وgit وcomposer وphpmyadmin وadminer وrestic وgoaccess
en|h_install_mode|installation type: single-server, single-site, multi-site or multi-server
fr|h_install_mode|type d'installation : single-server, single-site, multi-site ou multi-server
de|h_install_mode|Installationstyp: single-server, single-site, multi-site oder multi-server
es|h_install_mode|tipo de instalación: single-server, single-site, multi-site o multi-server
it|h_install_mode|tipo di installazione: single-server, single-site, multi-site o multi-server
pt|h_install_mode|tipo de instalação: single-server, single-site, multi-site ou multi-server
nl|h_install_mode|installatietype: single-server, single-site, multi-site of multi-server
ru|h_install_mode|тип установки: single-server, single-site, multi-site или multi-server
zh|h_install_mode|安装类型：single-server、single-site、multi-site 或 multi-server
ar|h_install_mode|نوع التثبيت: single-server أو single-site أو multi-site أو multi-server
en|h_roles|with multi-server: roles of this machine, comma-separated (web,db,mail,dns)
fr|h_roles|avec multi-server : rôles de cette machine séparés par des virgules (web,db,mail,dns)
de|h_roles|bei multi-server: Rollen dieses Rechners, durch Kommas getrennt (web,db,mail,dns)
es|h_roles|con multi-server: roles de esta máquina separados por comas (web,db,mail,dns)
it|h_roles|con multi-server: ruoli di questa macchina separati da virgole (web,db,mail,dns)
pt|h_roles|com multi-server: funções desta máquina separadas por vírgulas (web,db,mail,dns)
nl|h_roles|bij multi-server: rollen van deze machine gescheiden door komma's (web,db,mail,dns)
ru|h_roles|для multi-server: роли этой машины через запятую (web,db,mail,dns)
zh|h_roles|配合 multi-server：本机承担的角色，以逗号分隔（web,db,mail,dns）
ar|h_roles|مع multi-server: أدوار هذا الجهاز مفصولة بفواصل (web,db,mail,dns)
en|h_stack_file|JSON selection file (the one produced by toutpanel stack plan --json)
fr|h_stack_file|fichier JSON de sélection (celui produit par toutpanel stack plan --json)
de|h_stack_file|JSON-Auswahldatei (die von toutpanel stack plan --json erzeugte)
es|h_stack_file|archivo JSON de selección (el que produce toutpanel stack plan --json)
it|h_stack_file|file JSON di selezione (quello prodotto da toutpanel stack plan --json)
pt|h_stack_file|ficheiro JSON de seleção (o produzido por toutpanel stack plan --json)
nl|h_stack_file|JSON-selectiebestand (het bestand dat toutpanel stack plan --json maakt)
ru|h_stack_file|JSON-файл выбора (тот, что создаёт toutpanel stack plan --json)
zh|h_stack_file|JSON 选择文件（由 toutpanel stack plan --json 生成）
ar|h_stack_file|ملف JSON للاختيار (الذي ينتجه toutpanel stack plan --json)
en|h_no_tuning|do not tune PHP, MariaDB and Redis according to the available memory
fr|h_no_tuning|ne pas régler PHP, MariaDB et Redis selon la mémoire disponible
de|h_no_tuning|PHP, MariaDB und Redis nicht an den verfügbaren Arbeitsspeicher anpassen
es|h_no_tuning|no ajustar PHP, MariaDB y Redis según la memoria disponible
it|h_no_tuning|non ottimizzare PHP, MariaDB e Redis in base alla memoria disponibile
pt|h_no_tuning|não ajustar PHP, MariaDB e Redis conforme a memória disponível
nl|h_no_tuning|PHP, MariaDB en Redis niet afstemmen op het beschikbare geheugen
ru|h_no_tuning|не настраивать PHP, MariaDB и Redis по объёму памяти
zh|h_no_tuning|不根据可用内存调优 PHP、MariaDB 和 Redis
ar|h_no_tuning|عدم ضبط PHP وMariaDB وRedis وفق الذاكرة المتاحة
en|h_accept_litespeed_license|--web litespeed: accept the LiteSpeed Technologies license agreement (commercial product: limited-time official trial, then paid license)
fr|h_accept_litespeed_license|--web litespeed : accepter le contrat de licence de LiteSpeed Technologies (produit commercial : essai officiel de durée limitée, puis licence payante)
de|h_accept_litespeed_license|--web litespeed: Lizenzvertrag von LiteSpeed Technologies akzeptieren (kommerzielles Produkt: offizielle Testversion mit begrenzter Dauer, danach kostenpflichtige Lizenz)
es|h_accept_litespeed_license|--web litespeed: aceptar el contrato de licencia de LiteSpeed Technologies (producto comercial: prueba oficial de duración limitada y después licencia de pago)
it|h_accept_litespeed_license|--web litespeed: accettare il contratto di licenza di LiteSpeed Technologies (prodotto commerciale: prova ufficiale di durata limitata, poi licenza a pagamento)
pt|h_accept_litespeed_license|--web litespeed: aceitar o contrato de licença da LiteSpeed Technologies (produto comercial: avaliação oficial de duração limitada e, depois, licença paga)
nl|h_accept_litespeed_license|--web litespeed: de licentieovereenkomst van LiteSpeed Technologies accepteren (commercieel product: officiële proefperiode van beperkte duur, daarna betaalde licentie)
ru|h_accept_litespeed_license|--web litespeed: принять лицензионное соглашение LiteSpeed Technologies (коммерческий продукт: официальная пробная версия ограниченной длительности, затем платная лицензия)
zh|h_accept_litespeed_license|--web litespeed：接受 LiteSpeed Technologies 的许可协议（商业产品：官方限时试用，之后需付费许可）
ar|h_accept_litespeed_license|--web litespeed: قبول اتفاقية ترخيص LiteSpeed Technologies (منتج تجاري: تجربة رسمية محدودة المدة ثم ترخيص مدفوع)
en|h_stack_old|deprecated, replaced by --profile (full = standard, minimal = node, none = panel only):
fr|h_stack_old|obsolète, remplacé par --profile (full = standard, minimal = node, none = panel seul) :
de|h_stack_old|veraltet, ersetzt durch --profile (full = standard, minimal = node, none = nur Panel):
es|h_stack_old|obsoleto, sustituido por --profile (full = standard, minimal = node, none = solo el panel):
it|h_stack_old|obsoleto, sostituito da --profile (full = standard, minimal = node, none = solo il pannello):
pt|h_stack_old|obsoleto, substituído por --profile (full = standard, minimal = node, none = apenas o painel):
nl|h_stack_old|verouderd, vervangen door --profile (full = standard, minimal = node, none = alleen het paneel):
ru|h_stack_old|устарело, заменено на --profile (full = standard, minimal = node, none = только панель):
zh|h_stack_old|已弃用，由 --profile 取代（full = standard，minimal = node，none = 仅面板）：
ar|h_stack_old|مهجور وحلّ محله --profile (full = standard وminimal = node وnone = اللوحة فقط):
en|h_firewall|who manages the server firewall: on = ToutPanel (opens only the ports it needs), off = an upstream firewall (cloud security group, host firewall: no system rule is touched, the ports to open are listed), ask = interactive question
fr|h_firewall|qui gère le pare-feu du serveur : on = ToutPanel (n'ouvre que les ports nécessaires), off = pare-feu en amont (groupe de sécurité cloud, pare-feu de l'hébergeur : aucune règle système touchée, les ports à ouvrir sont listés), ask = question interactive
de|h_firewall|wer die Firewall des Servers verwaltet: on = ToutPanel (öffnet nur die nötigen Ports), off = vorgelagerte Firewall (Cloud-Sicherheitsgruppe, Firewall des Hosters: keine Systemregel wird angefasst, die zu öffnenden Ports werden aufgelistet), ask = interaktive Frage
es|h_firewall|quién gestiona el cortafuegos del servidor: on = ToutPanel (solo abre los puertos necesarios), off = cortafuegos externo (grupo de seguridad en la nube, cortafuegos del proveedor: no se toca ninguna regla del sistema, se listan los puertos que hay que abrir), ask = pregunta interactiva
it|h_firewall|chi gestisce il firewall del server: on = ToutPanel (apre solo le porte necessarie), off = firewall a monte (gruppo di sicurezza cloud, firewall del provider: nessuna regola di sistema viene toccata, le porte da aprire sono elencate), ask = domanda interattiva
pt|h_firewall|quem gere o firewall do servidor: on = ToutPanel (abre apenas as portas necessárias), off = firewall a montante (grupo de segurança na nuvem, firewall do fornecedor: nenhuma regra do sistema é alterada, as portas a abrir são listadas), ask = pergunta interativa
nl|h_firewall|wie de firewall van de server beheert: on = ToutPanel (opent alleen de nodige poorten), off = firewall stroomopwaarts (cloud-beveiligingsgroep, firewall van de hoster: geen systeemregel wordt aangeraakt, de te openen poorten worden getoond), ask = interactieve vraag
ru|h_firewall|кто управляет брандмауэром сервера: on = ToutPanel (открывает только нужные порты), off = внешний брандмауэр (группа безопасности облака, брандмауэр хостера: правила системы не трогаются, нужные порты перечисляются), ask = вопрос в терминале
zh|h_firewall|由谁管理服务器防火墙：on = ToutPanel（只开放必要端口），off = 上游防火墙（云安全组、主机商防火墙：不改动任何系统规则，并列出需开放的端口），ask = 交互式询问
ar|h_firewall|من يدير جدار حماية الخادم: on = ToutPanel (يفتح المنافذ اللازمة فقط)، off = جدار حماية أمامي (مجموعة أمان سحابية أو جدار المضيف: لا تُمس أي قاعدة في النظام وتُعرض المنافذ المطلوب فتحها)، ask = سؤال تفاعلي
en|h_firewall_engine|firewall engine with --firewall on: nft, ufw, firewalld, csf or iptables (default: detected)
fr|h_firewall_engine|moteur de pare-feu avec --firewall on : nft, ufw, firewalld, csf ou iptables (défaut : détecté)
de|h_firewall_engine|Firewall-Engine mit --firewall on: nft, ufw, firewalld, csf oder iptables (Standard: erkannt)
es|h_firewall_engine|motor de cortafuegos con --firewall on: nft, ufw, firewalld, csf o iptables (predeterminado: detectado)
it|h_firewall_engine|motore del firewall con --firewall on: nft, ufw, firewalld, csf o iptables (predefinito: rilevato)
pt|h_firewall_engine|motor de firewall com --firewall on: nft, ufw, firewalld, csf ou iptables (predefinição: detetado)
nl|h_firewall_engine|firewall-engine met --firewall on: nft, ufw, firewalld, csf of iptables (standaard: gedetecteerd)
ru|h_firewall_engine|движок брандмауэра с --firewall on: nft, ufw, firewalld, csf или iptables (по умолчанию: определяется)
zh|h_firewall_engine|配合 --firewall on 的防火墙引擎：nft、ufw、firewalld、csf 或 iptables（默认：自动检测）
ar|h_firewall_engine|محرك جدار الحماية مع --firewall on: nft أو ufw أو firewalld أو csf أو iptables (الافتراضي: يُكتشف تلقائيًا)
en|h_firewall_note|without the option: question in a terminal; without a terminal or with --yes: later (the mode is not chosen, nothing is touched). An update never changes the existing firewall.
fr|h_firewall_note|sans l'option : question dans un terminal ; sans terminal ou avec --yes : plus tard (le mode n'est pas choisi, rien n'est touché). Une mise à jour ne modifie jamais le pare-feu existant.
de|h_firewall_note|ohne die Option: Frage im Terminal; ohne Terminal oder mit --yes: später (der Modus ist nicht gewählt, nichts wird angefasst). Ein Update ändert nie die bestehende Firewall.
es|h_firewall_note|sin la opción: pregunta en un terminal; sin terminal o con --yes: más tarde (el modo no se elige, no se toca nada). Una actualización nunca modifica el cortafuegos existente.
it|h_firewall_note|senza l'opzione: domanda in un terminale; senza terminale o con --yes: più tardi (la modalità non è scelta, nulla viene toccato). Un aggiornamento non modifica mai il firewall esistente.
pt|h_firewall_note|sem a opção: pergunta num terminal; sem terminal ou com --yes: mais tarde (o modo não é escolhido, nada é alterado). Uma atualização nunca altera o firewall existente.
nl|h_firewall_note|zonder de optie: vraag in een terminal; zonder terminal of met --yes: later (de modus is niet gekozen, er wordt niets aangeraakt). Een update wijzigt de bestaande firewall nooit.
ru|h_firewall_note|без параметра: вопрос в терминале; без терминала или с --yes: позже (режим не выбран, ничего не меняется). Обновление никогда не меняет существующий брандмауэр.
zh|h_firewall_note|未指定该选项：在终端中询问；无终端或使用 --yes：稍后再定（不选择模式，不改动任何内容）。更新永远不会修改现有防火墙。
ar|h_firewall_note|دون الخيار: سؤال في الطرفية؛ دون طرفية أو مع --yes: لاحقًا (لا يُختار الوضع ولا يُمس شيء). التحديث لا يغيّر جدار الحماية الحالي أبدًا.
en|h_dry_run|show the detected distribution, directory and the commands that would be run, without changing anything (no root needed)
fr|h_dry_run|affiche la distribution détectée, le répertoire et les commandes qui seraient lancées, sans rien modifier (pas besoin de root)
de|h_dry_run|zeigt die erkannte Distribution, das Verzeichnis und die auszuführenden Befehle an, ohne etwas zu ändern (kein root nötig)
es|h_dry_run|muestra la distribución detectada, el directorio y los comandos que se ejecutarían, sin modificar nada (no requiere root)
it|h_dry_run|mostra la distribuzione rilevata, la directory e i comandi che verrebbero eseguiti, senza modificare nulla (root non necessario)
pt|h_dry_run|mostra a distribuição detetada, o diretório e os comandos que seriam executados, sem alterar nada (não requer root)
nl|h_dry_run|toont de gedetecteerde distributie, de map en de commando's die zouden worden uitgevoerd, zonder iets te wijzigen (geen root nodig)
ru|h_dry_run|показывает определённый дистрибутив, каталог и команды, которые были бы выполнены, ничего не изменяя (root не нужен)
zh|h_dry_run|显示检测到的发行版、目录以及将要执行的命令，不做任何更改（无需 root）
ar|h_dry_run|يعرض التوزيعة المكتشفة والمجلد والأوامر التي ستُنفَّذ دون تغيير أي شيء (لا حاجة إلى root)
en|help_env_opts|Each stack and firewall option also has a variable named TOUTPANEL_ followed by the option in capitals with underscores (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT; for --mail ENGINE: TOUTPANEL_MAIL_ENGINE).
fr|help_env_opts|Chaque option de pile et de pare-feu a aussi une variable nommée TOUTPANEL_ suivi de l'option en majuscules avec des tirets bas (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT ; pour --mail MOTEUR : TOUTPANEL_MAIL_ENGINE).
de|help_env_opts|Jede Stack- und Firewall-Option hat auch eine Variable namens TOUTPANEL_ gefolgt von der Option in Großbuchstaben mit Unterstrichen (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT; für --mail ENGINE: TOUTPANEL_MAIL_ENGINE).
es|help_env_opts|Cada opción de pila y de cortafuegos tiene también una variable llamada TOUTPANEL_ seguida de la opción en mayúsculas con guiones bajos (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT; para --mail MOTOR: TOUTPANEL_MAIL_ENGINE).
it|help_env_opts|Ogni opzione dello stack e del firewall ha anche una variabile chiamata TOUTPANEL_ seguita dall'opzione in maiuscolo con trattini bassi (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT; per --mail MOTORE: TOUTPANEL_MAIL_ENGINE).
pt|help_env_opts|Cada opção da pilha e do firewall tem também uma variável chamada TOUTPANEL_ seguida da opção em maiúsculas com sublinhados (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT; para --mail MOTOR: TOUTPANEL_MAIL_ENGINE).
nl|help_env_opts|Elke stack- en firewalloptie heeft ook een variabele met de naam TOUTPANEL_ gevolgd door de optie in hoofdletters met underscores (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT; voor --mail ENGINE: TOUTPANEL_MAIL_ENGINE).
ru|help_env_opts|У каждого параметра стека и брандмауэра есть переменная TOUTPANEL_ с именем параметра заглавными буквами и подчёркиваниями (TOUTPANEL_FIREWALL, TOUTPANEL_PHP_DEFAULT; для --mail ДВИЖОК: TOUTPANEL_MAIL_ENGINE).
zh|help_env_opts|每个软件栈和防火墙选项也有对应的环境变量：TOUTPANEL_ 加上大写、下划线形式的选项名（TOUTPANEL_FIREWALL、TOUTPANEL_PHP_DEFAULT；--mail 引擎：TOUTPANEL_MAIL_ENGINE）。
ar|help_env_opts|لكل خيار من خيارات الحزمة وجدار الحماية متغير بيئة اسمه TOUTPANEL_ متبوعًا باسم الخيار بأحرف كبيرة وشرطات سفلية (TOUTPANEL_FIREWALL وTOUTPANEL_PHP_DEFAULT؛ وللخيار --mail المحرك: TOUTPANEL_MAIL_ENGINE).
en|opt_needs_value|Option %s requires a value (see --help)
fr|opt_needs_value|L'option %s demande une valeur (voir --help)
de|opt_needs_value|Die Option %s erfordert einen Wert (siehe --help)
es|opt_needs_value|La opción %s requiere un valor (véase --help)
it|opt_needs_value|L'opzione %s richiede un valore (vedere --help)
pt|opt_needs_value|A opção %s requer um valor (consulte --help)
nl|opt_needs_value|De optie %s vereist een waarde (zie --help)
ru|opt_needs_value|Параметру %s требуется значение (см. --help)
zh|opt_needs_value|选项 %s 需要一个值（参见 --help）
ar|opt_needs_value|الخيار %s يتطلب قيمة (راجع --help)
en|bad_opt_value|Invalid value for %s: "%s" (accepted: %s)
fr|bad_opt_value|Valeur invalide pour %s : « %s » (valeurs acceptées : %s)
de|bad_opt_value|Ungültiger Wert für %s: „%s“ (zulässig: %s)
es|bad_opt_value|Valor no válido para %s: «%s» (valores admitidos: %s)
it|bad_opt_value|Valore non valido per %s: «%s» (valori ammessi: %s)
pt|bad_opt_value|Valor inválido para %s: «%s» (valores aceites: %s)
nl|bad_opt_value|Ongeldige waarde voor %s: "%s" (toegestaan: %s)
ru|bad_opt_value|Недопустимое значение для %s: «%s» (допустимо: %s)
zh|bad_opt_value|%s 的值无效：“%s”（可用值：%s）
ar|bad_opt_value|قيمة غير صالحة للخيار %s: "%s" (القيم المقبولة: %s)
en|fw_engine_needs_on|--firewall-engine only applies to a firewall managed by ToutPanel: it cannot be combined with --firewall off.
fr|fw_engine_needs_on|--firewall-engine ne vaut que pour un pare-feu géré par ToutPanel : impossible de l'associer à --firewall off.
de|fw_engine_needs_on|--firewall-engine gilt nur für eine von ToutPanel verwaltete Firewall: nicht mit --firewall off kombinierbar.
es|fw_engine_needs_on|--firewall-engine solo vale para un cortafuegos gestionado por ToutPanel: no se puede combinar con --firewall off.
it|fw_engine_needs_on|--firewall-engine vale solo per un firewall gestito da ToutPanel: non si può combinare con --firewall off.
pt|fw_engine_needs_on|--firewall-engine só se aplica a um firewall gerido pelo ToutPanel: não pode ser combinado com --firewall off.
nl|fw_engine_needs_on|--firewall-engine geldt alleen voor een door ToutPanel beheerde firewall: niet te combineren met --firewall off.
ru|fw_engine_needs_on|--firewall-engine применим только к брандмауэру под управлением ToutPanel: его нельзя сочетать с --firewall off.
zh|fw_engine_needs_on|--firewall-engine 仅适用于由 ToutPanel 管理的防火墙：不能与 --firewall off 同时使用。
ar|fw_engine_needs_on|--firewall-engine ينطبق فقط على جدار حماية تديره ToutPanel: لا يمكن جمعه مع --firewall off.
en|stack_file_bad|Stack file not found or unreadable: %s
fr|stack_file_bad|Fichier de pile introuvable ou illisible : %s
de|stack_file_bad|Stack-Datei nicht gefunden oder nicht lesbar: %s
es|stack_file_bad|Archivo de pila no encontrado o ilegible: %s
it|stack_file_bad|File dello stack non trovato o illeggibile: %s
pt|stack_file_bad|Ficheiro da pilha não encontrado ou ilegível: %s
nl|stack_file_bad|Stackbestand niet gevonden of onleesbaar: %s
ru|stack_file_bad|Файл стека не найден или недоступен для чтения: %s
zh|stack_file_bad|找不到软件栈文件或无法读取：%s
ar|stack_file_bad|ملف الحزمة غير موجود أو غير قابل للقراءة: %s
en|litespeed_license_needed|LiteSpeed Enterprise is a commercial product: add --accept-litespeed-license to accept the LiteSpeed Technologies license agreement (limited-time official trial, then paid license).
fr|litespeed_license_needed|LiteSpeed Enterprise est un produit commercial : ajoutez --accept-litespeed-license pour accepter le contrat de licence de LiteSpeed Technologies (essai officiel de durée limitée, puis licence payante).
de|litespeed_license_needed|LiteSpeed Enterprise ist ein kommerzielles Produkt: Fügen Sie --accept-litespeed-license hinzu, um den Lizenzvertrag von LiteSpeed Technologies zu akzeptieren (offizielle Testversion mit begrenzter Dauer, danach kostenpflichtige Lizenz).
es|litespeed_license_needed|LiteSpeed Enterprise es un producto comercial: añada --accept-litespeed-license para aceptar el contrato de licencia de LiteSpeed Technologies (prueba oficial de duración limitada y después licencia de pago).
it|litespeed_license_needed|LiteSpeed Enterprise è un prodotto commerciale: aggiungere --accept-litespeed-license per accettare il contratto di licenza di LiteSpeed Technologies (prova ufficiale di durata limitata, poi licenza a pagamento).
pt|litespeed_license_needed|O LiteSpeed Enterprise é um produto comercial: adicione --accept-litespeed-license para aceitar o contrato de licença da LiteSpeed Technologies (avaliação oficial de duração limitada e, depois, licença paga).
nl|litespeed_license_needed|LiteSpeed Enterprise is een commercieel product: voeg --accept-litespeed-license toe om de licentieovereenkomst van LiteSpeed Technologies te accepteren (officiële proefperiode van beperkte duur, daarna betaalde licentie).
ru|litespeed_license_needed|LiteSpeed Enterprise — коммерческий продукт: добавьте --accept-litespeed-license, чтобы принять лицензионное соглашение LiteSpeed Technologies (официальная пробная версия ограниченной длительности, затем платная лицензия).
zh|litespeed_license_needed|LiteSpeed Enterprise 是商业产品：请添加 --accept-litespeed-license 以接受 LiteSpeed Technologies 的许可协议（官方限时试用，之后需付费许可）。
ar|litespeed_license_needed|LiteSpeed Enterprise منتج تجاري: أضف --accept-litespeed-license لقبول اتفاقية ترخيص LiteSpeed Technologies (تجربة رسمية محدودة المدة ثم ترخيص مدفوع).
en|stack_conflict|--stack (deprecated) cannot be combined with the stack options (--profile, --web, --php, --db, --accel, --ftp, --mail ENGINE, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning): use --profile.
fr|stack_conflict|--stack (obsolète) ne se combine pas avec les options de pile (--profile, --web, --php, --db, --accel, --ftp, --mail MOTEUR, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning) : utilisez --profile.
de|stack_conflict|--stack (veraltet) lässt sich nicht mit den Stack-Optionen kombinieren (--profile, --web, --php, --db, --accel, --ftp, --mail ENGINE, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning): verwenden Sie --profile.
es|stack_conflict|--stack (obsoleto) no se combina con las opciones de pila (--profile, --web, --php, --db, --accel, --ftp, --mail MOTOR, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning): use --profile.
it|stack_conflict|--stack (obsoleto) non si combina con le opzioni dello stack (--profile, --web, --php, --db, --accel, --ftp, --mail MOTORE, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning): usare --profile.
pt|stack_conflict|--stack (obsoleto) não se combina com as opções da pilha (--profile, --web, --php, --db, --accel, --ftp, --mail MOTOR, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning): use --profile.
nl|stack_conflict|--stack (verouderd) is niet te combineren met de stackopties (--profile, --web, --php, --db, --accel, --ftp, --mail ENGINE, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning): gebruik --profile.
ru|stack_conflict|--stack (устарел) нельзя сочетать с параметрами стека (--profile, --web, --php, --db, --accel, --ftp, --mail ДВИЖОК, --dns, --security, --runtime, --tools, --install-mode, --roles, --stack-file, --redis, --no-tuning): используйте --profile.
zh|stack_conflict|--stack（已弃用）不能与软件栈选项（--profile、--web、--php、--db、--accel、--ftp、--mail 引擎、--dns、--security、--runtime、--tools、--install-mode、--roles、--stack-file、--redis、--no-tuning）同时使用：请改用 --profile。
ar|stack_conflict|لا يمكن جمع --stack (المهجور) مع خيارات الحزمة (--profile و--web و--php و--db و--accel و--ftp و--mail المحرك و--dns و--security و--runtime و--tools و--install-mode و--roles و--stack-file و--redis و--no-tuning): استخدم --profile.
en|home_unsafe|Refusing to use %s as the panel directory (system directory): choose a dedicated directory, e.g. /var/toutpanel.
fr|home_unsafe|Refus d'utiliser %s comme répertoire du panel (dossier système) : choisissez un dossier dédié, par ex. /var/toutpanel.
de|home_unsafe|%s wird nicht als Panel-Verzeichnis verwendet (Systemverzeichnis): wählen Sie ein eigenes Verzeichnis, z. B. /var/toutpanel.
es|home_unsafe|Se rechaza usar %s como directorio del panel (directorio del sistema): elija un directorio propio, p. ej. /var/toutpanel.
it|home_unsafe|Rifiuto di usare %s come directory del pannello (directory di sistema): scegliere una directory dedicata, ad es. /var/toutpanel.
pt|home_unsafe|Recusa-se usar %s como diretório do painel (diretório do sistema): escolha um diretório dedicado, p. ex. /var/toutpanel.
nl|home_unsafe|%s wordt niet gebruikt als paneelmap (systeemmap): kies een eigen map, bijv. /var/toutpanel.
ru|home_unsafe|Отказ использовать %s как каталог панели (системный каталог): выберите отдельный каталог, например /var/toutpanel.
zh|home_unsafe|拒绝将 %s 用作面板目录（系统目录）：请选择专用目录，例如 /var/toutpanel。
ar|home_unsafe|رفض استخدام %s مجلدًا للوحة (مجلد نظام): اختر مجلدًا مخصصًا، مثل /var/toutpanel.
en|home_legacy_kept|Existing installation detected in %s (former default directory; new installations use %s): kept in place, nothing is moved. Use --home DIR to choose another directory.
fr|home_legacy_kept|Installation existante détectée dans %s (ancien répertoire par défaut ; les nouvelles installations utilisent %s) : conservée sur place, rien n'est déplacé. --home DIR choisit un autre répertoire.
de|home_legacy_kept|Bestehende Installation in %s erkannt (früheres Standardverzeichnis; neue Installationen nutzen %s): bleibt an Ort und Stelle, nichts wird verschoben. Mit --home DIR wählen Sie ein anderes Verzeichnis.
es|home_legacy_kept|Instalación existente detectada en %s (antiguo directorio predeterminado; las nuevas instalaciones usan %s): se conserva en su sitio, no se mueve nada. --home DIR elige otro directorio.
it|home_legacy_kept|Installazione esistente rilevata in %s (vecchia directory predefinita; le nuove installazioni usano %s): conservata sul posto, nulla viene spostato. --home DIR sceglie un'altra directory.
pt|home_legacy_kept|Instalação existente detetada em %s (antigo diretório predefinido; as novas instalações usam %s): mantida no local, nada é movido. --home DIR escolhe outro diretório.
nl|home_legacy_kept|Bestaande installatie gevonden in %s (voormalige standaardmap; nieuwe installaties gebruiken %s): blijft op zijn plaats, er wordt niets verplaatst. Met --home DIR kiest u een andere map.
ru|home_legacy_kept|Обнаружена существующая установка в %s (прежний каталог по умолчанию; новые установки используют %s): остаётся на месте, ничего не переносится. --home DIR задаёт другой каталог.
zh|home_legacy_kept|检测到 %s 中的现有安装（旧的默认目录；新安装使用 %s）：原地保留，不做任何移动。可用 --home DIR 选择其他目录。
ar|home_legacy_kept|تم اكتشاف تثبيت موجود في %s (المجلد الافتراضي السابق؛ التثبيتات الجديدة تستخدم %s): يبقى في مكانه دون نقل. يحدد --home DIR مجلدًا آخر.
en|home_other_install|A ToutPanel installation already exists in %s; installing in %s creates another copy and replaces the system service (one panel per server).
fr|home_other_install|Une installation de ToutPanel existe déjà dans %s ; installer dans %s crée une autre copie et remplace le service système (un seul panel par serveur).
de|home_other_install|In %s existiert bereits eine ToutPanel-Installation; die Installation in %s erzeugt eine weitere Kopie und ersetzt den Systemdienst (ein Panel pro Server).
es|home_other_install|Ya existe una instalación de ToutPanel en %s; instalar en %s crea otra copia y reemplaza el servicio del sistema (un solo panel por servidor).
it|home_other_install|Esiste già un'installazione di ToutPanel in %s; installare in %s crea un'altra copia e sostituisce il servizio di sistema (un solo pannello per server).
pt|home_other_install|Já existe uma instalação do ToutPanel em %s; instalar em %s cria outra cópia e substitui o serviço do sistema (um só painel por servidor).
nl|home_other_install|In %s bestaat al een ToutPanel-installatie; installeren in %s maakt nog een kopie en vervangt de systeemservice (één paneel per server).
ru|home_other_install|В %s уже есть установка ToutPanel; установка в %s создаст ещё одну копию и заменит системную службу (одна панель на сервер).
zh|home_other_install|%s 中已存在 ToutPanel 安装；安装到 %s 会创建另一份副本并替换系统服务（每台服务器只能有一个面板）。
ar|home_other_install|يوجد تثبيت ToutPanel في %s؛ سيؤدي التثبيت في %s إلى إنشاء نسخة أخرى واستبدال خدمة النظام (لوحة واحدة لكل خادم).
en|st_distro|System detection
fr|st_distro|Détection du système
de|st_distro|Systemerkennung
es|st_distro|Detección del sistema
it|st_distro|Rilevamento del sistema
pt|st_distro|Deteção do sistema
nl|st_distro|Systeemdetectie
ru|st_distro|Определение системы
zh|st_distro|系统检测
ar|st_distro|اكتشاف النظام
en|distro_line|System: %s (ID %s), family %s, package manager %s, init %s, architecture %s
fr|distro_line|Système : %s (ID %s), famille %s, gestionnaire de paquets %s, init %s, architecture %s
de|distro_line|System: %s (ID %s), Familie %s, Paketmanager %s, Init %s, Architektur %s
es|distro_line|Sistema: %s (ID %s), familia %s, gestor de paquetes %s, init %s, arquitectura %s
it|distro_line|Sistema: %s (ID %s), famiglia %s, gestore di pacchetti %s, init %s, architettura %s
pt|distro_line|Sistema: %s (ID %s), família %s, gestor de pacotes %s, init %s, arquitetura %s
nl|distro_line|Systeem: %s (ID %s), familie %s, pakketbeheerder %s, init %s, architectuur %s
ru|distro_line|Система: %s (ID %s), семейство %s, менеджер пакетов %s, init %s, архитектура %s
zh|distro_line|系统：%s（ID %s），家族 %s，包管理器 %s，init %s，架构 %s
ar|distro_line|النظام: %s (المعرّف %s)، العائلة %s، مدير الحزم %s، init %s، المعمارية %s
en|distro_note|Note: %s
fr|distro_note|Remarque : %s
de|distro_note|Hinweis: %s
es|distro_note|Nota: %s
it|distro_note|Nota: %s
pt|distro_note|Nota: %s
nl|distro_note|Opmerking: %s
ru|distro_note|Примечание: %s
zh|distro_note|说明：%s
ar|distro_note|ملاحظة: %s
en|distro_reduced|Reduced support level (the panel works, but some features are missing or need manual steps): %s
fr|distro_reduced|Niveau de support réduit (le panel fonctionne, mais certaines fonctions manquent ou demandent une intervention) : %s
de|distro_reduced|Eingeschränkte Unterstützung (das Panel funktioniert, aber manche Funktionen fehlen oder erfordern manuelle Schritte): %s
es|distro_reduced|Nivel de soporte reducido (el panel funciona, pero faltan algunas funciones o requieren intervención manual): %s
it|distro_reduced|Livello di supporto ridotto (il pannello funziona, ma alcune funzioni mancano o richiedono interventi manuali): %s
pt|distro_reduced|Nível de suporte reduzido (o painel funciona, mas algumas funções faltam ou exigem intervenção manual): %s
nl|distro_reduced|Beperkt ondersteuningsniveau (het paneel werkt, maar sommige functies ontbreken of vragen handmatige stappen): %s
ru|distro_reduced|Ограниченный уровень поддержки (панель работает, но некоторые функции отсутствуют или требуют ручных действий): %s
zh|distro_reduced|支持级别受限（面板可运行，但部分功能缺失或需要手动操作）：%s
ar|distro_reduced|مستوى دعم محدود (تعمل اللوحة لكن بعض الميزات ناقصة أو تتطلب تدخلًا يدويًا): %s
en|distro_refused|Unsupported distribution: %s. %s
fr|distro_refused|Distribution non prise en charge : %s. %s
de|distro_refused|Nicht unterstützte Distribution: %s. %s
es|distro_refused|Distribución no admitida: %s. %s
it|distro_refused|Distribuzione non supportata: %s. %s
pt|distro_refused|Distribuição não suportada: %s. %s
nl|distro_refused|Niet-ondersteunde distributie: %s. %s
ru|distro_refused|Дистрибутив не поддерживается: %s. %s
zh|distro_refused|不支持的发行版：%s。%s
ar|distro_refused|توزيعة غير مدعومة: %s. %s
en|distro_refused_hint|Supported: Debian, Ubuntu and derivatives, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (levels per version: toutpanel compat, or the Linux installation page of the documentation). Nothing was modified.
fr|distro_refused_hint|Pris en charge : Debian, Ubuntu et dérivés, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (niveaux par version : toutpanel compat, ou la page d'installation Linux de la documentation). Rien n'a été modifié.
de|distro_refused_hint|Unterstützt: Debian, Ubuntu und Derivate, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (Stufen je Version: toutpanel compat oder die Linux-Installationsseite der Dokumentation). Es wurde nichts geändert.
es|distro_refused_hint|Admitidas: Debian, Ubuntu y derivadas, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (niveles por versión: toutpanel compat, o la página de instalación en Linux de la documentación). No se ha modificado nada.
it|distro_refused_hint|Supportate: Debian, Ubuntu e derivate, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (livelli per versione: toutpanel compat, o la pagina di installazione Linux della documentazione). Nulla è stato modificato.
pt|distro_refused_hint|Suportadas: Debian, Ubuntu e derivadas, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (níveis por versão: toutpanel compat, ou a página de instalação em Linux da documentação). Nada foi alterado.
nl|distro_refused_hint|Ondersteund: Debian, Ubuntu en afgeleiden, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (niveaus per versie: toutpanel compat, of de Linux-installatiepagina van de documentatie). Er is niets gewijzigd.
ru|distro_refused_hint|Поддерживаются: Debian, Ubuntu и производные, RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux, Fedora, Amazon Linux, openSUSE / SLES, Arch, Alpine (уровни по версиям: toutpanel compat или страница установки на Linux в документации). Ничего не изменено.
zh|distro_refused_hint|支持：Debian、Ubuntu 及其衍生版，RHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux，Fedora，Amazon Linux，openSUSE / SLES，Arch，Alpine（各版本的级别：toutpanel compat，或文档中的 Linux 安装页面）。未做任何修改。
ar|distro_refused_hint|المدعومة: Debian وUbuntu ومشتقاتهما وRHEL / AlmaLinux / Rocky / CentOS / Oracle / CloudLinux وFedora وAmazon Linux وopenSUSE / SLES وArch وAlpine (المستويات لكل إصدار: toutpanel compat أو صفحة التثبيت على لينكس في الوثائق). لم يُعدَّل شيء.
en|pkg_update_failed|Package index update failed (end-of-life system?): continuing with the package lists already known.
fr|pkg_update_failed|Mise à jour de l'index des paquets en échec (système en fin de vie ?) : poursuite avec les listes déjà connues.
de|pkg_update_failed|Aktualisierung des Paketindex fehlgeschlagen (System am Lebensende?): es wird mit den bekannten Listen fortgefahren.
es|pkg_update_failed|Falló la actualización del índice de paquetes (¿sistema al final de su vida útil?): se continúa con las listas ya conocidas.
it|pkg_update_failed|Aggiornamento dell'indice dei pacchetti non riuscito (sistema a fine vita?): si prosegue con gli elenchi già noti.
pt|pkg_update_failed|Falha na atualização do índice de pacotes (sistema em fim de vida?): continua-se com as listas já conhecidas.
nl|pkg_update_failed|Bijwerken van de pakketindex mislukt (systeem aan het einde van zijn levensduur?): doorgaan met de al bekende lijsten.
ru|pkg_update_failed|Не удалось обновить индекс пакетов (система снята с поддержки?): продолжаем с уже известными списками.
zh|pkg_update_failed|软件包索引更新失败（系统已停止维护？）：将使用已有的列表继续。
ar|pkg_update_failed|فشل تحديث فهرس الحزم (نظام انتهى دعمه؟): المتابعة بالقوائم المعروفة مسبقًا.
en|dr_eol|end-of-life system
fr|dr_eol|système en fin de vie
de|dr_eol|System am Lebensende
es|dr_eol|sistema al final de su vida útil
it|dr_eol|sistema a fine vita
pt|dr_eol|sistema em fim de vida
nl|dr_eol|systeem aan het einde van zijn levensduur
ru|dr_eol|система снята с поддержки
zh|dr_eol|系统已停止维护
ar|dr_eol|نظام انتهى دعمه
en|dr_yum|yum instead of dnf
fr|dr_yum|yum à la place de dnf
de|dr_yum|yum statt dnf
es|dr_yum|yum en lugar de dnf
it|dr_yum|yum al posto di dnf
pt|dr_yum|yum em vez de dnf
nl|dr_yum|yum in plaats van dnf
ru|dr_yum|yum вместо dnf
zh|dr_yum|使用 yum 而非 dnf
ar|dr_yum|yum بدلًا من dnf
en|dr_pyold|system Python older than 3.9: a 3.9+ interpreter will be provided
fr|dr_pyold|Python du système antérieur à 3.9 : un interpréteur 3.9+ sera fourni
de|dr_pyold|System-Python älter als 3.9: ein Interpreter ab 3.9 wird bereitgestellt
es|dr_pyold|Python del sistema anterior a 3.9: se aportará un intérprete 3.9+
it|dr_pyold|Python di sistema precedente alla 3.9: verrà fornito un interprete 3.9+
pt|dr_pyold|Python do sistema anterior à 3.9: será fornecido um interpretador 3.9+
nl|dr_pyold|systeem-Python ouder dan 3.9: er wordt een interpreter 3.9+ aangeleverd
ru|dr_pyold|системный Python старше 3.9: будет предоставлен интерпретатор 3.9+
zh|dr_pyold|系统 Python 低于 3.9：将提供 3.9+ 解释器
ar|dr_pyold|إصدار Python في النظام أقدم من 3.9: سيتم توفير مفسّر 3.9+
en|dr_stack_amzn|reduced stack (PHP from the Amazon repository, one PHP at a time; no Remi, MariaDB or PGDG repositories)
fr|dr_stack_amzn|pile réduite (PHP du dépôt Amazon, un seul PHP à la fois ; pas de dépôts Remi, MariaDB ni PGDG)
de|dr_stack_amzn|reduzierter Stack (PHP aus dem Amazon-Repository, jeweils nur ein PHP; keine Remi-, MariaDB- oder PGDG-Repositories)
es|dr_stack_amzn|pila reducida (PHP del repositorio de Amazon, un solo PHP a la vez; sin repositorios Remi, MariaDB ni PGDG)
it|dr_stack_amzn|stack ridotto (PHP dal repository Amazon, un solo PHP alla volta; nessun repository Remi, MariaDB o PGDG)
pt|dr_stack_amzn|pilha reduzida (PHP do repositório da Amazon, um só PHP de cada vez; sem repositórios Remi, MariaDB nem PGDG)
nl|dr_stack_amzn|beperkte stack (PHP uit de Amazon-repository, telkens één PHP; geen Remi-, MariaDB- of PGDG-repositories)
ru|dr_stack_amzn|урезанный стек (PHP из репозитория Amazon, только один PHP; нет репозиториев Remi, MariaDB и PGDG)
zh|dr_stack_amzn|精简软件栈（使用 Amazon 仓库的 PHP，一次只能有一个 PHP；没有 Remi、MariaDB、PGDG 仓库）
ar|dr_stack_amzn|حزمة مخفّضة (PHP من مستودع Amazon، نسخة واحدة في كل مرة؛ دون مستودعات Remi وMariaDB وPGDG)
en|dr_stack_suse|reduced stack (system PHP only, no multi-version repository)
fr|dr_stack_suse|pile réduite (PHP du système uniquement, pas de dépôt multi-versions)
de|dr_stack_suse|reduzierter Stack (nur System-PHP, kein Multi-Versions-Repository)
es|dr_stack_suse|pila reducida (solo el PHP del sistema, sin repositorio multiversión)
it|dr_stack_suse|stack ridotto (solo il PHP di sistema, nessun repository multiversione)
pt|dr_stack_suse|pilha reduzida (apenas o PHP do sistema, sem repositório multiversão)
nl|dr_stack_suse|beperkte stack (alleen het systeem-PHP, geen repository met meerdere versies)
ru|dr_stack_suse|урезанный стек (только системный PHP, нет репозитория с несколькими версиями)
zh|dr_stack_suse|精简软件栈（仅系统自带 PHP，没有多版本仓库）
ar|dr_stack_suse|حزمة مخفّضة (PHP النظام فقط، دون مستودع متعدد الإصدارات)
en|dr_stack_arch|reduced stack (rolling release, system PHP only, no multi-version repository)
fr|dr_stack_arch|pile réduite (distribution en rolling release, PHP du système uniquement, pas de dépôt multi-versions)
de|dr_stack_arch|reduzierter Stack (Rolling Release, nur System-PHP, kein Multi-Versions-Repository)
es|dr_stack_arch|pila reducida (distribución rolling release, solo el PHP del sistema, sin repositorio multiversión)
it|dr_stack_arch|stack ridotto (rolling release, solo il PHP di sistema, nessun repository multiversione)
pt|dr_stack_arch|pilha reduzida (rolling release, apenas o PHP do sistema, sem repositório multiversão)
nl|dr_stack_arch|beperkte stack (rolling release, alleen het systeem-PHP, geen repository met meerdere versies)
ru|dr_stack_arch|урезанный стек (скользящий релиз, только системный PHP, нет репозитория с несколькими версиями)
zh|dr_stack_arch|精简软件栈（滚动发行，仅系统自带 PHP，没有多版本仓库）
ar|dr_stack_arch|حزمة مخفّضة (إصدار متجدد، PHP النظام فقط، دون مستودع متعدد الإصدارات)
en|dr_stack_alpine|reduced stack (OpenRC, musl: some systemd, AppArmor and package features are missing)
fr|dr_stack_alpine|pile réduite (OpenRC, musl : certaines fonctions systemd, AppArmor et certains paquets sont absents)
de|dr_stack_alpine|reduzierter Stack (OpenRC, musl: einige systemd-, AppArmor- und Paketfunktionen fehlen)
es|dr_stack_alpine|pila reducida (OpenRC, musl: faltan algunas funciones de systemd, AppArmor y algunos paquetes)
it|dr_stack_alpine|stack ridotto (OpenRC, musl: mancano alcune funzioni di systemd, AppArmor e alcuni pacchetti)
pt|dr_stack_alpine|pilha reduzida (OpenRC, musl: faltam algumas funções do systemd, do AppArmor e alguns pacotes)
nl|dr_stack_alpine|beperkte stack (OpenRC, musl: sommige systemd-, AppArmor- en pakketfuncties ontbreken)
ru|dr_stack_alpine|урезанный стек (OpenRC, musl: часть функций systemd, AppArmor и некоторые пакеты отсутствуют)
zh|dr_stack_alpine|精简软件栈（OpenRC、musl：缺少部分 systemd、AppArmor 功能和某些软件包）
ar|dr_stack_alpine|حزمة مخفّضة (OpenRC وmusl: بعض ميزات systemd وAppArmor وبعض الحزم غير متوفرة)
en|dr_rolling|rolling release
fr|dr_rolling|distribution en rolling release
de|dr_rolling|Rolling Release
es|dr_rolling|distribución rolling release
it|dr_rolling|rolling release
pt|dr_rolling|rolling release
nl|dr_rolling|rolling release
ru|dr_rolling|скользящий релиз
zh|dr_rolling|滚动发行
ar|dr_rolling|إصدار متجدد
en|dr_audit|audit-oriented distribution (Debian testing): server use is not recommended
fr|dr_audit|distribution orientée audit (Debian testing) : usage serveur déconseillé
de|dr_audit|auf Sicherheitsaudits ausgerichtete Distribution (Debian testing): Serverbetrieb nicht empfohlen
es|dr_audit|distribución orientada a auditoría (Debian testing): no se recomienda su uso como servidor
it|dr_audit|distribuzione orientata all'audit (Debian testing): uso come server sconsigliato
pt|dr_audit|distribuição orientada para auditoria (Debian testing): uso em servidor desaconselhado
nl|dr_audit|op audits gerichte distributie (Debian testing): gebruik als server wordt afgeraden
ru|dr_audit|дистрибутив для аудита безопасности (Debian testing): использование на сервере не рекомендуется
zh|dr_audit|面向安全审计的发行版（Debian testing）：不建议用作服务器
ar|dr_audit|توزيعة موجهة للتدقيق الأمني (Debian testing): لا يُنصح باستخدامها كخادم
en|dr_nosystemd|no systemd (sysvinit, OpenRC or runit): timers, journald and service units are unavailable
fr|dr_nosystemd|sans systemd (sysvinit, OpenRC ou runit) : timers, journald et unités de service indisponibles
de|dr_nosystemd|ohne systemd (sysvinit, OpenRC oder runit): Timer, journald und Service-Units nicht verfügbar
es|dr_nosystemd|sin systemd (sysvinit, OpenRC o runit): temporizadores, journald y unidades de servicio no disponibles
it|dr_nosystemd|senza systemd (sysvinit, OpenRC o runit): timer, journald e unità di servizio non disponibili
pt|dr_nosystemd|sem systemd (sysvinit, OpenRC ou runit): temporizadores, journald e unidades de serviço indisponíveis
nl|dr_nosystemd|zonder systemd (sysvinit, OpenRC of runit): timers, journald en serviceunits niet beschikbaar
ru|dr_nosystemd|без systemd (sysvinit, OpenRC или runit): таймеры, journald и юниты служб недоступны
zh|dr_nosystemd|无 systemd（sysvinit、OpenRC 或 runit）：定时器、journald 和服务单元不可用
ar|dr_nosystemd|دون systemd (sysvinit أو OpenRC أو runit): المؤقتات وjournald ووحدات الخدمة غير متاحة
en|dr_noinit|init %s: systemd timers and units are unavailable
fr|dr_noinit|init %s : timers et unités systemd indisponibles
de|dr_noinit|Init %s: systemd-Timer und -Units nicht verfügbar
es|dr_noinit|init %s: temporizadores y unidades de systemd no disponibles
it|dr_noinit|init %s: timer e unità systemd non disponibili
pt|dr_noinit|init %s: temporizadores e unidades systemd indisponíveis
nl|dr_noinit|init %s: systemd-timers en -units niet beschikbaar
ru|dr_noinit|init %s: таймеры и юниты systemd недоступны
zh|dr_noinit|init %s：systemd 定时器和单元不可用
ar|dr_noinit|init %s: مؤقتات ووحدات systemd غير متاحة
en|dr_testing|Debian testing / sid (rolling): follows the latest known version, not guaranteed
fr|dr_testing|Debian testing / sid (rolling) : suit la dernière version connue, non garanti
de|dr_testing|Debian testing / sid (Rolling): folgt der neuesten bekannten Version, ohne Garantie
es|dr_testing|Debian testing / sid (rolling): sigue la última versión conocida, sin garantía
it|dr_testing|Debian testing / sid (rolling): segue l'ultima versione nota, senza garanzia
pt|dr_testing|Debian testing / sid (rolling): segue a última versão conhecida, sem garantia
nl|dr_testing|Debian testing / sid (rolling): volgt de nieuwste bekende versie, zonder garantie
ru|dr_testing|Debian testing / sid (скользящий): следует последней известной версии, без гарантии
zh|dr_testing|Debian testing / sid（滚动）：按最新已知版本处理，不作保证
ar|dr_testing|Debian testing / sid (متجدد): يُعامل كأحدث إصدار معروف دون ضمان
en|dr_recent_ubuntu|recent Ubuntu (%s): handled as the latest known version
fr|dr_recent_ubuntu|Ubuntu récente (« %s ») : traitée comme la dernière version connue
de|dr_recent_ubuntu|neue Ubuntu-Version („%s“): wird wie die neueste bekannte Version behandelt
es|dr_recent_ubuntu|Ubuntu reciente («%s»): tratada como la última versión conocida
it|dr_recent_ubuntu|Ubuntu recente («%s»): trattata come l'ultima versione nota
pt|dr_recent_ubuntu|Ubuntu recente («%s»): tratada como a última versão conhecida
nl|dr_recent_ubuntu|recente Ubuntu ("%s"): behandeld als de nieuwste bekende versie
ru|dr_recent_ubuntu|новая версия Ubuntu («%s»): обрабатывается как последняя известная версия
zh|dr_recent_ubuntu|较新的 Ubuntu（“%s”）：按最新已知版本处理
ar|dr_recent_ubuntu|إصدار Ubuntu حديث ("%s"): يُعامل كأحدث إصدار معروف
en|dr_untested_pm|untested distribution: family %s deduced from the package manager
fr|dr_untested_pm|distribution non testée : famille %s déduite du gestionnaire de paquets
de|dr_untested_pm|ungetestete Distribution: Familie %s aus dem Paketmanager abgeleitet
es|dr_untested_pm|distribución no probada: familia %s deducida del gestor de paquetes
it|dr_untested_pm|distribuzione non testata: famiglia %s dedotta dal gestore di pacchetti
pt|dr_untested_pm|distribuição não testada: família %s deduzida do gestor de pacotes
nl|dr_untested_pm|niet geteste distributie: familie %s afgeleid van de pakketbeheerder
ru|dr_untested_pm|непроверенный дистрибутив: семейство %s определено по менеджеру пакетов
zh|dr_untested_pm|未经测试的发行版：根据包管理器推断为 %s 家族
ar|dr_untested_pm|توزيعة غير مختبرة: استُنتجت العائلة %s من مدير الحزم
en|dr_untested_like|untested distribution attached to the %s family through ID_LIKE
fr|dr_untested_like|distribution non testée rattachée à la famille %s par ID_LIKE
de|dr_untested_like|ungetestete Distribution, über ID_LIKE der Familie %s zugeordnet
es|dr_untested_like|distribución no probada asociada a la familia %s mediante ID_LIKE
it|dr_untested_like|distribuzione non testata associata alla famiglia %s tramite ID_LIKE
pt|dr_untested_like|distribuição não testada associada à família %s através de ID_LIKE
nl|dr_untested_like|niet geteste distributie, via ID_LIKE aan de familie %s gekoppeld
ru|dr_untested_like|непроверенный дистрибутив, отнесённый к семейству %s по ID_LIKE
zh|dr_untested_like|未经测试的发行版：通过 ID_LIKE 归入 %s 家族
ar|dr_untested_like|توزيعة غير مختبرة أُلحقت بالعائلة %s عبر ID_LIKE
en|dr_untested_base|untested derivative of %s: repositories of the base are used
fr|dr_untested_base|dérivée non testée de %s : dépôts de la base utilisés
de|dr_untested_base|ungetestetes Derivat von %s: Repositories der Basis werden verwendet
es|dr_untested_base|derivada no probada de %s: se usan los repositorios de la base
it|dr_untested_base|derivata non testata di %s: vengono usati i repository della base
pt|dr_untested_base|derivada não testada de %s: são usados os repositórios da base
nl|dr_untested_base|niet getest afgeleide van %s: repositories van de basis worden gebruikt
ru|dr_untested_base|непроверенный производный дистрибутив %s: используются репозитории основы
zh|dr_untested_base|未经测试的 %s 衍生版：使用其基础发行版的软件源
ar|dr_untested_base|مشتقة غير مختبرة من %s: تُستخدم مستودعات الأساس
en|dr_arch|architecture %s: Python dependencies are compiled at install time and some packages are missing
fr|dr_arch|architecture %s : dépendances Python compilées à l'installation et certains paquets absents
de|dr_arch|Architektur %s: Python-Abhängigkeiten werden bei der Installation kompiliert, manche Pakete fehlen
es|dr_arch|arquitectura %s: las dependencias de Python se compilan durante la instalación y faltan algunos paquetes
it|dr_arch|architettura %s: le dipendenze Python vengono compilate durante l'installazione e mancano alcuni pacchetti
pt|dr_arch|arquitetura %s: as dependências Python são compiladas durante a instalação e faltam alguns pacotes
nl|dr_arch|architectuur %s: Python-afhankelijkheden worden bij de installatie gecompileerd en sommige pakketten ontbreken
ru|dr_arch|архитектура %s: зависимости Python компилируются при установке, некоторые пакеты отсутствуют
zh|dr_arch|架构 %s：安装时需编译 Python 依赖，且缺少部分软件包
ar|dr_arch|المعمارية %s: تُصرَّف اعتماديات Python أثناء التثبيت وبعض الحزم غير متوفرة
en|dr_tooold|version too old
fr|dr_tooold|version trop ancienne
de|dr_tooold|Version zu alt
es|dr_tooold|versión demasiado antigua
it|dr_tooold|versione troppo vecchia
pt|dr_tooold|versão demasiado antiga
nl|dr_tooold|versie te oud
ru|dr_tooold|версия слишком старая
zh|dr_tooold|版本过旧
ar|dr_tooold|الإصدار قديم جدًا
en|dr_unknown_distro|unrecognised distribution (%s): neither ID_LIKE nor a known package manager
fr|dr_unknown_distro|distribution non reconnue (%s) : ni ID_LIKE ni gestionnaire de paquets connu
de|dr_unknown_distro|nicht erkannte Distribution (%s): weder ID_LIKE noch ein bekannter Paketmanager
es|dr_unknown_distro|distribución no reconocida (%s): ni ID_LIKE ni un gestor de paquetes conocido
it|dr_unknown_distro|distribuzione non riconosciuta (%s): né ID_LIKE né un gestore di pacchetti noto
pt|dr_unknown_distro|distribuição não reconhecida (%s): nem ID_LIKE nem um gestor de pacotes conhecido
nl|dr_unknown_distro|niet herkende distributie (%s): geen ID_LIKE en geen bekende pakketbeheerder
ru|dr_unknown_distro|дистрибутив не распознан (%s): нет ни ID_LIKE, ни известного менеджера пакетов
zh|dr_unknown_distro|无法识别的发行版（%s）：既没有 ID_LIKE，也没有已知的包管理器
ar|dr_unknown_distro|توزيعة غير معروفة (%s): لا ID_LIKE ولا مدير حزم معروف
en|dr_outofscope|%s: package manager not supported (apt, dnf, yum, zypper, pacman or apk required)
fr|dr_outofscope|%s : gestionnaire de paquets non pris en charge (apt, dnf, yum, zypper, pacman ou apk requis)
de|dr_outofscope|%s: Paketmanager nicht unterstützt (apt, dnf, yum, zypper, pacman oder apk erforderlich)
es|dr_outofscope|%s: gestor de paquetes no admitido (se requiere apt, dnf, yum, zypper, pacman o apk)
it|dr_outofscope|%s: gestore di pacchetti non supportato (richiesto apt, dnf, yum, zypper, pacman o apk)
pt|dr_outofscope|%s: gestor de pacotes não suportado (requer apt, dnf, yum, zypper, pacman ou apk)
nl|dr_outofscope|%s: pakketbeheerder niet ondersteund (apt, dnf, yum, zypper, pacman of apk vereist)
ru|dr_outofscope|%s: менеджер пакетов не поддерживается (нужен apt, dnf, yum, zypper, pacman или apk)
zh|dr_outofscope|%s：不支持该包管理器（需要 apt、dnf、yum、zypper、pacman 或 apk）
ar|dr_outofscope|%s: مدير الحزم غير مدعوم (يلزم apt أو dnf أو yum أو zypper أو pacman أو apk)
en|dr_immutable|%s: immutable system, no modifiable package manager
fr|dr_immutable|%s : système immuable, pas de gestionnaire de paquets modifiable
de|dr_immutable|%s: unveränderliches System, kein veränderbarer Paketmanager
es|dr_immutable|%s: sistema inmutable, sin gestor de paquetes modificable
it|dr_immutable|%s: sistema immutabile, nessun gestore di pacchetti modificabile
pt|dr_immutable|%s: sistema imutável, sem gestor de pacotes modificável
nl|dr_immutable|%s: onveranderlijk systeem, geen aanpasbare pakketbeheerder
ru|dr_immutable|%s: неизменяемая система, нет изменяемого менеджера пакетов
zh|dr_immutable|%s：不可变系统，没有可修改的包管理器
ar|dr_immutable|%s: نظام غير قابل للتعديل، لا يوجد مدير حزم قابل للتعديل
en|lvl_full|full
fr|lvl_full|complet
de|lvl_full|vollständig
es|lvl_full|completo
it|lvl_full|completo
pt|lvl_full|completo
nl|lvl_full|volledig
ru|lvl_full|полный
zh|lvl_full|完整
ar|lvl_full|كامل
en|lvl_reduced|reduced
fr|lvl_reduced|réduit
de|lvl_reduced|eingeschränkt
es|lvl_reduced|reducido
it|lvl_reduced|ridotto
pt|lvl_reduced|reduzido
nl|lvl_reduced|beperkt
ru|lvl_reduced|ограниченный
zh|lvl_reduced|受限
ar|lvl_reduced|محدود
en|lvl_unsupported|unsupported
fr|lvl_unsupported|non pris en charge
de|lvl_unsupported|nicht unterstützt
es|lvl_unsupported|no admitido
it|lvl_unsupported|non supportato
pt|lvl_unsupported|não suportado
nl|lvl_unsupported|niet ondersteund
ru|lvl_unsupported|не поддерживается
zh|lvl_unsupported|不支持
ar|lvl_unsupported|غير مدعوم
en|compat_line|Compatibility level reported by the panel: %s
fr|compat_line|Niveau de compatibilité relevé par le panel : %s
de|compat_line|Vom Panel ermittelte Kompatibilitätsstufe: %s
es|compat_line|Nivel de compatibilidad indicado por el panel: %s
it|compat_line|Livello di compatibilità rilevato dal pannello: %s
pt|compat_line|Nível de compatibilidade indicado pelo painel: %s
nl|compat_line|Door het paneel vastgesteld compatibiliteitsniveau: %s
ru|compat_line|Уровень совместимости по данным панели: %s
zh|compat_line|面板报告的兼容级别：%s
ar|compat_line|مستوى التوافق الذي رصدته اللوحة: %s
en|compat_line_reason|Compatibility level reported by the panel: %s (%s)
fr|compat_line_reason|Niveau de compatibilité relevé par le panel : %s (%s)
de|compat_line_reason|Vom Panel ermittelte Kompatibilitätsstufe: %s (%s)
es|compat_line_reason|Nivel de compatibilidad indicado por el panel: %s (%s)
it|compat_line_reason|Livello di compatibilità rilevato dal pannello: %s (%s)
pt|compat_line_reason|Nível de compatibilidade indicado pelo painel: %s (%s)
nl|compat_line_reason|Door het paneel vastgesteld compatibiliteitsniveau: %s (%s)
ru|compat_line_reason|Уровень совместимости по данным панели: %s (%s)
zh|compat_line_reason|面板报告的兼容级别：%s（%s）
ar|compat_line_reason|مستوى التوافق الذي رصدته اللوحة: %s (%s)
en|python_old|Python 3.9 or later is required (system Python: %s): looking for a recent interpreter…
fr|python_old|Python 3.9 ou plus récent requis (Python du système : %s) : recherche d'un interpréteur récent…
de|python_old|Python 3.9 oder neuer erforderlich (System-Python: %s): suche einen aktuellen Interpreter …
es|python_old|Se requiere Python 3.9 o posterior (Python del sistema: %s): buscando un intérprete reciente…
it|python_old|Richiesto Python 3.9 o successivo (Python di sistema: %s): ricerca di un interprete recente…
pt|python_old|É necessário Python 3.9 ou posterior (Python do sistema: %s): a procurar um interpretador recente…
nl|python_old|Python 3.9 of nieuwer vereist (systeem-Python: %s): zoeken naar een recente interpreter…
ru|python_old|Требуется Python 3.9 или новее (системный Python: %s): ищем свежий интерпретатор…
zh|python_old|需要 Python 3.9 或更高版本（系统 Python：%s）：正在寻找较新的解释器…
ar|python_old|يلزم Python 3.9 أو أحدث (إصدار النظام: %s): جارٍ البحث عن مفسّر حديث…
en|python_pkg|Installing a recent Python from the distribution packages: %s
fr|python_pkg|Installation d'un Python récent depuis les paquets de la distribution : %s
de|python_pkg|Ein aktuelles Python wird aus den Paketen der Distribution installiert: %s
es|python_pkg|Instalando un Python reciente desde los paquetes de la distribución: %s
it|python_pkg|Installazione di un Python recente dai pacchetti della distribuzione: %s
pt|python_pkg|A instalar um Python recente a partir dos pacotes da distribuição: %s
nl|python_pkg|Een recente Python wordt uit de pakketten van de distributie geïnstalleerd: %s
ru|python_pkg|Установка свежего Python из пакетов дистрибутива: %s
zh|python_pkg|正在从发行版软件包安装较新的 Python：%s
ar|python_pkg|تثبيت Python حديث من حزم التوزيعة: %s
en|python_ask|System Python is %s and no recent package is available. Download a standalone Python %s (python-build-standalone installed with uv, SHA-256 verified) into %s? %s
fr|python_ask|Le Python du système est %s et aucun paquet récent n'est disponible. Télécharger un Python autonome %s (python-build-standalone installé avec uv, SHA-256 vérifié) dans %s ? %s
de|python_ask|Das System-Python ist %s und es gibt kein aktuelles Paket. Ein eigenständiges Python %s (python-build-standalone, mit uv installiert, SHA-256 geprüft) nach %s herunterladen? %s
es|python_ask|El Python del sistema es %s y no hay ningún paquete reciente. ¿Descargar un Python autónomo %s (python-build-standalone instalado con uv, SHA-256 verificado) en %s? %s
it|python_ask|Il Python di sistema è %s e non c'è nessun pacchetto recente. Scaricare un Python autonomo %s (python-build-standalone installato con uv, SHA-256 verificato) in %s? %s
pt|python_ask|O Python do sistema é %s e não há nenhum pacote recente. Transferir um Python autónomo %s (python-build-standalone instalado com uv, SHA-256 verificado) para %s? %s
nl|python_ask|Het systeem-Python is %s en er is geen recent pakket beschikbaar. Een zelfstandige Python %s (python-build-standalone, met uv geïnstalleerd, SHA-256 gecontroleerd) downloaden naar %s? %s
ru|python_ask|Системный Python — %s, свежего пакета нет. Скачать автономный Python %s (python-build-standalone, устанавливается через uv, SHA-256 проверяется) в %s? %s
zh|python_ask|系统 Python 为 %s，且没有可用的较新软件包。是否将独立的 Python %s（通过 uv 安装 python-build-standalone，并校验 SHA-256）下载到 %s？%s
ar|python_ask|إصدار Python في النظام هو %s ولا توجد حزمة حديثة. هل تنزّل Python %s مستقلًا (python-build-standalone يُثبَّت عبر uv مع التحقق من SHA-256) إلى %s؟ %s
en|python_standalone_download|Downloading uv and a standalone Python %s (%s)…
fr|python_standalone_download|Téléchargement de uv et d'un Python autonome %s (%s)…
de|python_standalone_download|uv und ein eigenständiges Python %s (%s) werden heruntergeladen …
es|python_standalone_download|Descargando uv y un Python autónomo %s (%s)…
it|python_standalone_download|Download di uv e di un Python autonomo %s (%s)…
pt|python_standalone_download|A transferir o uv e um Python autónomo %s (%s)…
nl|python_standalone_download|uv en een zelfstandige Python %s (%s) worden gedownload…
ru|python_standalone_download|Загрузка uv и автономного Python %s (%s)…
zh|python_standalone_download|正在下载 uv 和独立的 Python %s（%s）…
ar|python_standalone_download|جارٍ تنزيل uv وPython مستقل %s (%s)…
en|python_standalone_net|Download failed: %s
fr|python_standalone_net|Téléchargement impossible : %s
de|python_standalone_net|Download fehlgeschlagen: %s
es|python_standalone_net|No se pudo descargar: %s
it|python_standalone_net|Download non riuscito: %s
pt|python_standalone_net|Falha na transferência: %s
nl|python_standalone_net|Downloaden mislukt: %s
ru|python_standalone_net|Не удалось скачать: %s
zh|python_standalone_net|下载失败：%s
ar|python_standalone_net|فشل التنزيل: %s
en|python_sha_bad|The SHA-256 check of %s failed or the file is unusable: nothing was installed from it.
fr|python_sha_bad|La vérification SHA-256 de %s a échoué ou le fichier est inutilisable : rien n'en a été installé.
de|python_sha_bad|Die SHA-256-Prüfung von %s ist fehlgeschlagen oder die Datei ist unbrauchbar: nichts davon wurde installiert.
es|python_sha_bad|La verificación SHA-256 de %s falló o el archivo es inutilizable: no se instaló nada de él.
it|python_sha_bad|La verifica SHA-256 di %s non è riuscita o il file è inutilizzabile: non ne è stato installato nulla.
pt|python_sha_bad|A verificação SHA-256 de %s falhou ou o ficheiro é inutilizável: nada foi instalado a partir dele.
nl|python_sha_bad|De SHA-256-controle van %s is mislukt of het bestand is onbruikbaar: er is niets van geïnstalleerd.
ru|python_sha_bad|Проверка SHA-256 для %s не пройдена или файл непригоден: из него ничего не установлено.
zh|python_sha_bad|%s 的 SHA-256 校验失败或文件无法使用：未安装其中任何内容。
ar|python_sha_bad|فشل التحقق من SHA-256 للملف %s أو أنه غير صالح: لم يُثبَّت منه شيء.
en|python_standalone_failed|The standalone Python could not be installed.
fr|python_standalone_failed|Le Python autonome n'a pas pu être installé.
de|python_standalone_failed|Das eigenständige Python konnte nicht installiert werden.
es|python_standalone_failed|No se pudo instalar el Python autónomo.
it|python_standalone_failed|Non è stato possibile installare il Python autonomo.
pt|python_standalone_failed|Não foi possível instalar o Python autónomo.
nl|python_standalone_failed|De zelfstandige Python kon niet worden geïnstalleerd.
ru|python_standalone_failed|Не удалось установить автономный Python.
zh|python_standalone_failed|无法安装独立的 Python。
ar|python_standalone_failed|تعذّر تثبيت Python المستقل.
en|python_standalone_ok|Standalone Python %s installed in %s (checksums verified).
fr|python_standalone_ok|Python autonome %s installé dans %s (sommes de contrôle vérifiées).
de|python_standalone_ok|Eigenständiges Python %s in %s installiert (Prüfsummen verifiziert).
es|python_standalone_ok|Python autónomo %s instalado en %s (sumas de comprobación verificadas).
it|python_standalone_ok|Python autonomo %s installato in %s (checksum verificati).
pt|python_standalone_ok|Python autónomo %s instalado em %s (somas de verificação confirmadas).
nl|python_standalone_ok|Zelfstandige Python %s geïnstalleerd in %s (controlesommen geverifieerd).
ru|python_standalone_ok|Автономный Python %s установлен в %s (контрольные суммы проверены).
zh|python_standalone_ok|独立的 Python %s 已安装到 %s（校验和已验证）。
ar|python_standalone_ok|تم تثبيت Python المستقل %s في %s (جرى التحقق من المجاميع الاختبارية).
en|python_standalone_arch|No standalone Python is published for the architecture %s.
fr|python_standalone_arch|Aucun Python autonome n'est publié pour l'architecture %s.
de|python_standalone_arch|Für die Architektur %s wird kein eigenständiges Python angeboten.
es|python_standalone_arch|No se publica ningún Python autónomo para la arquitectura %s.
it|python_standalone_arch|Non è pubblicato alcun Python autonomo per l'architettura %s.
pt|python_standalone_arch|Não é publicado nenhum Python autónomo para a arquitetura %s.
nl|python_standalone_arch|Voor de architectuur %s wordt geen zelfstandige Python aangeboden.
ru|python_standalone_arch|Для архитектуры %s автономный Python не публикуется.
zh|python_standalone_arch|没有针对架构 %s 发布的独立 Python。
ar|python_standalone_arch|لا يوجد Python مستقل منشور للمعمارية %s.
en|python_refused|Python 3.9 or later is required and could not be installed from the distribution. Install it yourself (python3.11 or later), or run again with %s to allow a standalone Python download into %s.
fr|python_refused|Python 3.9 ou plus récent est requis et n'a pas pu être installé depuis la distribution. Installez-le vous-même (python3.11 ou plus récent), ou relancez avec %s pour autoriser le téléchargement d'un Python autonome dans %s.
de|python_refused|Python 3.9 oder neuer ist erforderlich und konnte nicht aus der Distribution installiert werden. Installieren Sie es selbst (python3.11 oder neuer) oder starten Sie erneut mit %s, um den Download eines eigenständigen Python nach %s zu erlauben.
es|python_refused|Se requiere Python 3.9 o posterior y no se pudo instalar desde la distribución. Instálelo usted mismo (python3.11 o posterior) o vuelva a ejecutar con %s para permitir la descarga de un Python autónomo en %s.
it|python_refused|È richiesto Python 3.9 o successivo e non è stato possibile installarlo dalla distribuzione. Installarlo manualmente (python3.11 o successivo) oppure rilanciare con %s per consentire il download di un Python autonomo in %s.
pt|python_refused|É necessário Python 3.9 ou posterior e não foi possível instalá-lo a partir da distribuição. Instale-o você mesmo (python3.11 ou posterior) ou execute novamente com %s para permitir a transferência de um Python autónomo para %s.
nl|python_refused|Python 3.9 of nieuwer is vereist en kon niet uit de distributie worden geïnstalleerd. Installeer het zelf (python3.11 of nieuwer) of start opnieuw met %s om het downloaden van een zelfstandige Python naar %s toe te staan.
ru|python_refused|Нужен Python 3.9 или новее, но установить его из дистрибутива не удалось. Установите его сами (python3.11 или новее) либо запустите снова с %s, чтобы разрешить загрузку автономного Python в %s.
zh|python_refused|需要 Python 3.9 或更高版本，但无法从发行版安装。请自行安装（python3.11 或更高），或使用 %s 重新运行，以允许将独立的 Python 下载到 %s。
ar|python_refused|يلزم Python 3.9 أو أحدث وتعذّر تثبيته من التوزيعة. ثبّته بنفسك (python3.11 أو أحدث) أو أعد التشغيل مع %s للسماح بتنزيل Python مستقل إلى %s.
en|arch_compile|Architecture %s: Python dependencies may have to be compiled (this can take several minutes); the compiler and development headers are installed.
fr|arch_compile|Architecture %s : les dépendances Python peuvent devoir être compilées (plusieurs minutes) ; le compilateur et les en-têtes de développement sont installés.
de|arch_compile|Architektur %s: Python-Abhängigkeiten müssen eventuell kompiliert werden (kann mehrere Minuten dauern); Compiler und Entwicklungs-Header werden installiert.
es|arch_compile|Arquitectura %s: puede que haya que compilar las dependencias de Python (varios minutos); se instalan el compilador y las cabeceras de desarrollo.
it|arch_compile|Architettura %s: le dipendenze Python potrebbero dover essere compilate (alcuni minuti); vengono installati il compilatore e gli header di sviluppo.
pt|arch_compile|Arquitetura %s: as dependências Python podem ter de ser compiladas (vários minutos); o compilador e os cabeçalhos de desenvolvimento são instalados.
nl|arch_compile|Architectuur %s: Python-afhankelijkheden moeten mogelijk worden gecompileerd (enkele minuten); compiler en ontwikkelheaders worden geïnstalleerd.
ru|arch_compile|Архитектура %s: зависимости Python, возможно, придётся компилировать (несколько минут); устанавливаются компилятор и заголовочные файлы.
zh|arch_compile|架构 %s：Python 依赖可能需要编译（可能耗时数分钟）；将安装编译器和开发头文件。
ar|arch_compile|المعمارية %s: قد يلزم تصريف اعتماديات Python (عدة دقائق)؛ يُثبَّت المصرِّف وملفات التطوير.
en|build_deps_failed|The compiler packages could not be installed: installing the Python dependencies may fail.
fr|build_deps_failed|Les paquets du compilateur n'ont pas pu être installés : l'installation des dépendances Python peut échouer.
de|build_deps_failed|Die Compiler-Pakete konnten nicht installiert werden: die Installation der Python-Abhängigkeiten kann scheitern.
es|build_deps_failed|No se pudieron instalar los paquetes del compilador: la instalación de las dependencias de Python puede fallar.
it|build_deps_failed|Non è stato possibile installare i pacchetti del compilatore: l'installazione delle dipendenze Python potrebbe non riuscire.
pt|build_deps_failed|Não foi possível instalar os pacotes do compilador: a instalação das dependências Python pode falhar.
nl|build_deps_failed|De compilerpakketten konden niet worden geïnstalleerd: het installeren van de Python-afhankelijkheden kan mislukken.
ru|build_deps_failed|Не удалось установить пакеты компилятора: установка зависимостей Python может завершиться ошибкой.
zh|build_deps_failed|无法安装编译器软件包：安装 Python 依赖可能会失败。
ar|build_deps_failed|تعذّر تثبيت حزم المصرِّف: قد يفشل تثبيت اعتماديات Python.
en|php_unavailable|No PHP package found for this system: install PHP afterwards from the panel (Software).
fr|php_unavailable|Aucun paquet PHP trouvé pour ce système : installez PHP ensuite depuis le panel (Logiciels).
de|php_unavailable|Für dieses System wurde kein PHP-Paket gefunden: installieren Sie PHP anschließend im Panel (Software).
es|php_unavailable|No se encontró ningún paquete de PHP para este sistema: instale PHP después desde el panel (Software).
it|php_unavailable|Nessun pacchetto PHP trovato per questo sistema: installare PHP in seguito dal pannello (Software).
pt|php_unavailable|Nenhum pacote PHP encontrado para este sistema: instale o PHP depois a partir do painel (Software).
nl|php_unavailable|Geen PHP-pakket gevonden voor dit systeem: installeer PHP achteraf via het paneel (Software).
ru|php_unavailable|Для этой системы не найден пакет PHP: установите PHP позже из панели (Программы).
zh|php_unavailable|未找到适用于此系统的 PHP 软件包：请稍后在面板（软件）中安装 PHP。
ar|php_unavailable|لم يُعثر على حزمة PHP لهذا النظام: ثبّت PHP لاحقًا من اللوحة (البرامج).
en|fw_q_title|Firewall: who manages the firewall of this server?
fr|fw_q_title|Pare-feu : qui gère le pare-feu de ce serveur ?
de|fw_q_title|Firewall: Wer verwaltet die Firewall dieses Servers?
es|fw_q_title|Cortafuegos: ¿quién gestiona el cortafuegos de este servidor?
it|fw_q_title|Firewall: chi gestisce il firewall di questo server?
pt|fw_q_title|Firewall: quem gere o firewall deste servidor?
nl|fw_q_title|Firewall: wie beheert de firewall van deze server?
ru|fw_q_title|Брандмауэр: кто управляет брандмауэром этого сервера?
zh|fw_q_title|防火墙：由谁管理此服务器的防火墙？
ar|fw_q_title|جدار الحماية: من يدير جدار حماية هذا الخادم؟
en|fw_q_panel|ToutPanel: it opens only the ports it needs (SSH, panel, sites, mail…)
fr|fw_q_panel|ToutPanel : il n'ouvre que les ports nécessaires (SSH, panel, sites, courrier…)
de|fw_q_panel|ToutPanel: öffnet nur die nötigen Ports (SSH, Panel, Websites, Mail …)
es|fw_q_panel|ToutPanel: abre solo los puertos necesarios (SSH, panel, sitios, correo…)
it|fw_q_panel|ToutPanel: apre solo le porte necessarie (SSH, pannello, siti, posta…)
pt|fw_q_panel|ToutPanel: abre apenas as portas necessárias (SSH, painel, sites, correio…)
nl|fw_q_panel|ToutPanel: opent alleen de nodige poorten (SSH, paneel, sites, mail…)
ru|fw_q_panel|ToutPanel: открывает только нужные порты (SSH, панель, сайты, почта…)
zh|fw_q_panel|ToutPanel：只开放必要的端口（SSH、面板、网站、邮件……）
ar|fw_q_panel|ToutPanel: يفتح المنافذ اللازمة فقط (SSH واللوحة والمواقع والبريد…)
en|fw_q_external|An upstream firewall (cloud security group, hosting provider firewall): ToutPanel touches no system rule and lists the ports to open there
fr|fw_q_external|Un pare-feu en amont (groupe de sécurité cloud, pare-feu de l'hébergeur) : ToutPanel ne touche à aucune règle système et liste les ports à y ouvrir
de|fw_q_external|Eine vorgelagerte Firewall (Cloud-Sicherheitsgruppe, Firewall des Hosters): ToutPanel fasst keine Systemregel an und listet die dort zu öffnenden Ports auf
es|fw_q_external|Un cortafuegos externo (grupo de seguridad en la nube, cortafuegos del proveedor): ToutPanel no toca ninguna regla del sistema y lista los puertos que hay que abrir allí
it|fw_q_external|Un firewall a monte (gruppo di sicurezza cloud, firewall del provider): ToutPanel non tocca alcuna regola di sistema e elenca le porte da aprire lì
pt|fw_q_external|Um firewall a montante (grupo de segurança na nuvem, firewall do fornecedor): o ToutPanel não altera nenhuma regra do sistema e lista as portas a abrir aí
nl|fw_q_external|Een firewall stroomopwaarts (cloud-beveiligingsgroep, firewall van de hoster): ToutPanel raakt geen systeemregel aan en toont de daar te openen poorten
ru|fw_q_external|Внешний брандмауэр (группа безопасности облака, брандмауэр хостера): ToutPanel не трогает правила системы и перечисляет порты, которые нужно открыть там
zh|fw_q_external|上游防火墙（云安全组、主机商防火墙）：ToutPanel 不改动任何系统规则，并列出需要在那里开放的端口
ar|fw_q_external|جدار حماية أمامي (مجموعة أمان سحابية أو جدار حماية المضيف): لا تمس ToutPanel أي قاعدة في النظام وتعرض المنافذ المطلوب فتحها هناك
en|fw_q_later|Decide later in the setup wizard: nothing is touched for now
fr|fw_q_later|Décider plus tard dans l'assistant de configuration : rien n'est touché pour l'instant
de|fw_q_later|Später im Einrichtungsassistenten entscheiden: vorerst wird nichts angefasst
es|fw_q_later|Decidirlo más tarde en el asistente de configuración: de momento no se toca nada
it|fw_q_later|Decidere più tardi nella procedura guidata: per ora nulla viene toccato
pt|fw_q_later|Decidir mais tarde no assistente de configuração: por agora nada é alterado
nl|fw_q_later|Later beslissen in de installatiewizard: voorlopig wordt niets aangeraakt
ru|fw_q_later|Решить позже в мастере настройки: пока ничего не меняется
zh|fw_q_later|稍后在设置向导中决定：目前不做任何改动
ar|fw_q_later|القرار لاحقًا في معالج الإعداد: لا يُمس شيء الآن
en|fw_q_prompt|Choice [%s]:
fr|fw_q_prompt|Choix [%s] :
de|fw_q_prompt|Auswahl [%s]:
es|fw_q_prompt|Opción [%s]:
it|fw_q_prompt|Scelta [%s]:
pt|fw_q_prompt|Escolha [%s]:
nl|fw_q_prompt|Keuze [%s]:
ru|fw_q_prompt|Выбор [%s]:
zh|fw_q_prompt|请选择 [%s]：
ar|fw_q_prompt|الاختيار [%s]:
en|fw_update_ignored|Update: the existing firewall is never modified, so the --firewall option is ignored (use toutpanel firewall mode to change it).
fr|fw_update_ignored|Mise à jour : le pare-feu existant n'est jamais modifié, l'option --firewall est donc ignorée (toutpanel firewall mode permet de le changer).
de|fw_update_ignored|Update: die bestehende Firewall wird nie verändert, daher wird die Option --firewall ignoriert (mit toutpanel firewall mode lässt sie sich ändern).
es|fw_update_ignored|Actualización: el cortafuegos existente nunca se modifica, por lo que se ignora la opción --firewall (toutpanel firewall mode permite cambiarlo).
it|fw_update_ignored|Aggiornamento: il firewall esistente non viene mai modificato, quindi l'opzione --firewall è ignorata (toutpanel firewall mode permette di cambiarlo).
pt|fw_update_ignored|Atualização: o firewall existente nunca é alterado, por isso a opção --firewall é ignorada (toutpanel firewall mode permite alterá-lo).
nl|fw_update_ignored|Update: de bestaande firewall wordt nooit gewijzigd, dus de optie --firewall wordt genegeerd (met toutpanel firewall mode wijzigt u hem).
ru|fw_update_ignored|Обновление: существующий брандмауэр никогда не меняется, поэтому параметр --firewall игнорируется (изменить его можно командой toutpanel firewall mode).
zh|fw_update_ignored|更新：现有防火墙绝不会被修改，因此忽略 --firewall 选项（可用 toutpanel firewall mode 更改）。
ar|fw_update_ignored|التحديث: لا يُعدَّل جدار الحماية الحالي أبدًا، لذا يُتجاهل الخيار --firewall (يمكن تغييره عبر toutpanel firewall mode).
en|fw_update_unchanged|unchanged (an update never modifies the firewall)
fr|fw_update_unchanged|inchangé (une mise à jour ne modifie jamais le pare-feu)
de|fw_update_unchanged|unverändert (ein Update ändert die Firewall nie)
es|fw_update_unchanged|sin cambios (una actualización nunca modifica el cortafuegos)
it|fw_update_unchanged|invariato (un aggiornamento non modifica mai il firewall)
pt|fw_update_unchanged|inalterado (uma atualização nunca altera o firewall)
nl|fw_update_unchanged|ongewijzigd (een update wijzigt de firewall nooit)
ru|fw_update_unchanged|без изменений (обновление никогда не меняет брандмауэр)
zh|fw_update_unchanged|保持不变（更新永远不会修改防火墙）
ar|fw_update_unchanged|دون تغيير (التحديث لا يعدّل جدار الحماية أبدًا)
en|fw_engine_ignored|--firewall-engine %s is ignored: the firewall is not managed by ToutPanel.
fr|fw_engine_ignored|--firewall-engine %s est ignoré : le pare-feu n'est pas géré par ToutPanel.
de|fw_engine_ignored|--firewall-engine %s wird ignoriert: die Firewall wird nicht von ToutPanel verwaltet.
es|fw_engine_ignored|--firewall-engine %s se ignora: el cortafuegos no lo gestiona ToutPanel.
it|fw_engine_ignored|--firewall-engine %s è ignorato: il firewall non è gestito da ToutPanel.
pt|fw_engine_ignored|--firewall-engine %s é ignorado: o firewall não é gerido pelo ToutPanel.
nl|fw_engine_ignored|--firewall-engine %s wordt genegeerd: de firewall wordt niet door ToutPanel beheerd.
ru|fw_engine_ignored|--firewall-engine %s игнорируется: брандмауэром не управляет ToutPanel.
zh|fw_engine_ignored|--firewall-engine %s 被忽略：防火墙不由 ToutPanel 管理。
ar|fw_engine_ignored|يُتجاهل --firewall-engine %s: جدار الحماية لا تديره ToutPanel.
en|fw_engine_missing|The firewall engine %s is not installed and could not be installed: ToutPanel will pick one itself.
fr|fw_engine_missing|Le moteur de pare-feu %s n'est pas installé et n'a pas pu l'être : ToutPanel en choisira un lui-même.
de|fw_engine_missing|Die Firewall-Engine %s ist nicht installiert und konnte nicht installiert werden: ToutPanel wählt selbst eine aus.
es|fw_engine_missing|El motor de cortafuegos %s no está instalado y no se pudo instalar: ToutPanel elegirá uno por sí mismo.
it|fw_engine_missing|Il motore del firewall %s non è installato e non è stato possibile installarlo: ToutPanel ne sceglierà uno da solo.
pt|fw_engine_missing|O motor de firewall %s não está instalado e não foi possível instalá-lo: o ToutPanel escolherá um por si.
nl|fw_engine_missing|De firewall-engine %s is niet geïnstalleerd en kon niet worden geïnstalleerd: ToutPanel kiest er zelf een.
ru|fw_engine_missing|Движок брандмауэра %s не установлен и не удалось его установить: ToutPanel выберет подходящий сам.
zh|fw_engine_missing|防火墙引擎 %s 未安装且无法安装：ToutPanel 将自行选择。
ar|fw_engine_missing|محرك جدار الحماية %s غير مثبّت وتعذّر تثبيته: ستختار ToutPanel محركًا بنفسها.
en|fw_enabled|Firewall enabled by ToutPanel (panel, SSH and active services ports are open).
fr|fw_enabled|Pare-feu activé par ToutPanel (ports du panel, de SSH et des services actifs ouverts).
de|fw_enabled|Firewall von ToutPanel aktiviert (Ports von Panel, SSH und aktiven Diensten sind offen).
es|fw_enabled|Cortafuegos activado por ToutPanel (puertos del panel, SSH y servicios activos abiertos).
it|fw_enabled|Firewall attivato da ToutPanel (porte del pannello, di SSH e dei servizi attivi aperte).
pt|fw_enabled|Firewall ativado pelo ToutPanel (portas do painel, do SSH e dos serviços ativos abertas).
nl|fw_enabled|Firewall door ToutPanel ingeschakeld (poorten van paneel, SSH en actieve services zijn open).
ru|fw_enabled|Брандмауэр включён ToutPanel (порты панели, SSH и активных служб открыты).
zh|fw_enabled|ToutPanel 已启用防火墙（面板、SSH 和活动服务的端口已开放）。
ar|fw_enabled|فعّلت ToutPanel جدار الحماية (منافذ اللوحة وSSH والخدمات النشطة مفتوحة).
en|fw_enable_failed|The firewall could not be enabled (no supported engine, or command refused). Install ufw, firewalld or nftables, then run:
fr|fw_enable_failed|Le pare-feu n'a pas pu être activé (aucun moteur pris en charge, ou commande refusée). Installez ufw, firewalld ou nftables, puis lancez :
de|fw_enable_failed|Die Firewall konnte nicht aktiviert werden (keine unterstützte Engine oder Befehl abgelehnt). Installieren Sie ufw, firewalld oder nftables und führen Sie dann aus:
es|fw_enable_failed|No se pudo activar el cortafuegos (ningún motor admitido, o comando rechazado). Instale ufw, firewalld o nftables y ejecute:
it|fw_enable_failed|Non è stato possibile attivare il firewall (nessun motore supportato, o comando rifiutato). Installare ufw, firewalld o nftables, poi eseguire:
pt|fw_enable_failed|Não foi possível ativar o firewall (nenhum motor suportado, ou comando recusado). Instale ufw, firewalld ou nftables e execute:
nl|fw_enable_failed|De firewall kon niet worden ingeschakeld (geen ondersteunde engine, of opdracht geweigerd). Installeer ufw, firewalld of nftables en voer uit:
ru|fw_enable_failed|Не удалось включить брандмауэр (нет поддерживаемого движка или команда отклонена). Установите ufw, firewalld или nftables и выполните:
zh|fw_enable_failed|无法启用防火墙（没有受支持的引擎，或命令被拒绝）。请安装 ufw、firewalld 或 nftables，然后运行：
ar|fw_enable_failed|تعذّر تفعيل جدار الحماية (لا يوجد محرك مدعوم أو رُفض الأمر). ثبّت ufw أو firewalld أو nftables ثم نفّذ:
en|fw_external_note|Upstream firewall: no system firewall rule was touched. The ports to open at your hosting provider are listed in the summary.
fr|fw_external_note|Pare-feu en amont : aucune règle de pare-feu système n'a été touchée. Les ports à ouvrir chez votre hébergeur sont listés dans le récapitulatif.
de|fw_external_note|Vorgelagerte Firewall: keine System-Firewallregel wurde angefasst. Die beim Hoster zu öffnenden Ports stehen in der Zusammenfassung.
es|fw_external_note|Cortafuegos externo: no se ha tocado ninguna regla del cortafuegos del sistema. Los puertos que hay que abrir en su proveedor figuran en el resumen.
it|fw_external_note|Firewall a monte: nessuna regola del firewall di sistema è stata toccata. Le porte da aprire presso il provider sono elencate nel riepilogo.
pt|fw_external_note|Firewall a montante: nenhuma regra do firewall do sistema foi alterada. As portas a abrir no seu fornecedor estão listadas no resumo.
nl|fw_external_note|Firewall stroomopwaarts: er is geen systeemfirewallregel aangeraakt. De bij uw hoster te openen poorten staan in het overzicht.
ru|fw_external_note|Внешний брандмауэр: правила системного брандмауэра не затрагивались. Порты, которые нужно открыть у хостера, перечислены в итоговой сводке.
zh|fw_external_note|上游防火墙：未改动任何系统防火墙规则。需要在主机商处开放的端口见总结。
ar|fw_external_note|جدار حماية أمامي: لم تُمس أي قاعدة في جدار حماية النظام. المنافذ المطلوب فتحها لدى المضيف مذكورة في الملخص.
en|fw_ports_title|Ports to open at your hosting provider (security group, upstream firewall):
fr|fw_ports_title|Ports à ouvrir chez votre hébergeur (groupe de sécurité, pare-feu en amont) :
de|fw_ports_title|Beim Hoster zu öffnende Ports (Sicherheitsgruppe, vorgelagerte Firewall):
es|fw_ports_title|Puertos que hay que abrir en su proveedor (grupo de seguridad, cortafuegos externo):
it|fw_ports_title|Porte da aprire presso il provider (gruppo di sicurezza, firewall a monte):
pt|fw_ports_title|Portas a abrir no seu fornecedor (grupo de segurança, firewall a montante):
nl|fw_ports_title|Bij uw hoster te openen poorten (beveiligingsgroep, firewall stroomopwaarts):
ru|fw_ports_title|Порты, которые нужно открыть у хостера (группа безопасности, внешний брандмауэр):
zh|fw_ports_title|需要在主机商处开放的端口（安全组、上游防火墙）：
ar|fw_ports_title|المنافذ المطلوب فتحها لدى المضيف (مجموعة الأمان، جدار الحماية الأمامي):
en|fw_later_hint|Firewall mode not chosen: decide in the setup wizard, or run toutpanel firewall mode panel (ToutPanel manages it) or toutpanel firewall mode external (upstream firewall).
fr|fw_later_hint|Mode du pare-feu non choisi : décidez dans l'assistant de configuration, ou lancez toutpanel firewall mode panel (ToutPanel le gère) ou toutpanel firewall mode external (pare-feu en amont).
de|fw_later_hint|Firewall-Modus nicht gewählt: entscheiden Sie im Einrichtungsassistenten oder führen Sie toutpanel firewall mode panel (ToutPanel verwaltet sie) oder toutpanel firewall mode external (vorgelagerte Firewall) aus.
es|fw_later_hint|Modo del cortafuegos sin elegir: decídalo en el asistente de configuración, o ejecute toutpanel firewall mode panel (lo gestiona ToutPanel) o toutpanel firewall mode external (cortafuegos externo).
it|fw_later_hint|Modalità del firewall non scelta: decidere nella procedura guidata, oppure eseguire toutpanel firewall mode panel (lo gestisce ToutPanel) o toutpanel firewall mode external (firewall a monte).
pt|fw_later_hint|Modo do firewall não escolhido: decida no assistente de configuração, ou execute toutpanel firewall mode panel (gerido pelo ToutPanel) ou toutpanel firewall mode external (firewall a montante).
nl|fw_later_hint|Firewallmodus niet gekozen: beslis in de installatiewizard, of voer toutpanel firewall mode panel (ToutPanel beheert hem) of toutpanel firewall mode external (firewall stroomopwaarts) uit.
ru|fw_later_hint|Режим брандмауэра не выбран: решите в мастере настройки или выполните toutpanel firewall mode panel (управляет ToutPanel) либо toutpanel firewall mode external (внешний брандмауэр).
zh|fw_later_hint|尚未选择防火墙模式：请在设置向导中决定，或运行 toutpanel firewall mode panel（由 ToutPanel 管理）或 toutpanel firewall mode external（上游防火墙）。
ar|fw_later_hint|لم يُختر وضع جدار الحماية: قرّر في معالج الإعداد أو نفّذ toutpanel firewall mode panel (تديره ToutPanel) أو toutpanel firewall mode external (جدار حماية أمامي).
en|fw_val_panel|managed by ToutPanel (engine: %s)
fr|fw_val_panel|géré par ToutPanel (moteur : %s)
de|fw_val_panel|von ToutPanel verwaltet (Engine: %s)
es|fw_val_panel|gestionado por ToutPanel (motor: %s)
it|fw_val_panel|gestito da ToutPanel (motore: %s)
pt|fw_val_panel|gerido pelo ToutPanel (motor: %s)
nl|fw_val_panel|beheerd door ToutPanel (engine: %s)
ru|fw_val_panel|управляется ToutPanel (движок: %s)
zh|fw_val_panel|由 ToutPanel 管理（引擎：%s）
ar|fw_val_panel|تديره ToutPanel (المحرك: %s)
en|fw_val_panel_failed|managed by ToutPanel, but not enabled (see the warning above)
fr|fw_val_panel_failed|géré par ToutPanel, mais non activé (voir l'avertissement ci-dessus)
de|fw_val_panel_failed|von ToutPanel verwaltet, aber nicht aktiviert (siehe Warnung oben)
es|fw_val_panel_failed|gestionado por ToutPanel, pero no activado (véase la advertencia anterior)
it|fw_val_panel_failed|gestito da ToutPanel, ma non attivato (vedere l'avviso sopra)
pt|fw_val_panel_failed|gerido pelo ToutPanel, mas não ativado (consulte o aviso acima)
nl|fw_val_panel_failed|beheerd door ToutPanel, maar niet ingeschakeld (zie de waarschuwing hierboven)
ru|fw_val_panel_failed|управляется ToutPanel, но не включён (см. предупреждение выше)
zh|fw_val_panel_failed|由 ToutPanel 管理，但未启用（见上方警告）
ar|fw_val_panel_failed|تديره ToutPanel لكنه غير مفعّل (انظر التحذير أعلاه)
en|fw_val_external|upstream firewall (no system rule touched)
fr|fw_val_external|pare-feu en amont (aucune règle système touchée)
de|fw_val_external|vorgelagerte Firewall (keine Systemregel angefasst)
es|fw_val_external|cortafuegos externo (ninguna regla del sistema tocada)
it|fw_val_external|firewall a monte (nessuna regola di sistema toccata)
pt|fw_val_external|firewall a montante (nenhuma regra do sistema alterada)
nl|fw_val_external|firewall stroomopwaarts (geen systeemregel aangeraakt)
ru|fw_val_external|внешний брандмауэр (правила системы не затронуты)
zh|fw_val_external|上游防火墙（未改动任何系统规则）
ar|fw_val_external|جدار حماية أمامي (لم تُمس أي قاعدة في النظام)
en|fw_val_later|not chosen yet (nothing touched)
fr|fw_val_later|pas encore choisi (rien n'est touché)
de|fw_val_later|noch nicht gewählt (nichts angefasst)
es|fw_val_later|aún sin elegir (no se toca nada)
it|fw_val_later|non ancora scelto (nulla viene toccato)
pt|fw_val_later|ainda não escolhido (nada é alterado)
nl|fw_val_later|nog niet gekozen (niets aangeraakt)
ru|fw_val_later|ещё не выбран (ничего не затронуто)
zh|fw_val_later|尚未选择（未改动任何内容）
ar|fw_val_later|لم يُختر بعد (لا يُمس شيء)
en|fw_val_ask|question asked during the installation (terminal only)
fr|fw_val_ask|question posée pendant l'installation (dans un terminal seulement)
de|fw_val_ask|Frage während der Installation (nur im Terminal)
es|fw_val_ask|pregunta durante la instalación (solo en un terminal)
it|fw_val_ask|domanda durante l'installazione (solo in un terminale)
pt|fw_val_ask|pergunta durante a instalação (apenas num terminal)
nl|fw_val_ask|vraag tijdens de installatie (alleen in een terminal)
ru|fw_val_ask|вопрос во время установки (только в терминале)
zh|fw_val_ask|安装过程中询问（仅限终端）
ar|fw_val_ask|سؤال أثناء التثبيت (في الطرفية فقط)
en|st_stack|Software stack
fr|st_stack|Pile logicielle
de|st_stack|Software-Stack
es|st_stack|Pila de software
it|st_stack|Stack software
pt|st_stack|Pilha de software
nl|st_stack|Softwarestack
ru|st_stack|Программный стек
zh|st_stack|软件栈
ar|st_stack|حزمة البرامج
en|stack_applying|Applying the software stack: toutpanel %s
fr|stack_applying|Application de la pile logicielle : toutpanel %s
de|stack_applying|Der Software-Stack wird angewendet: toutpanel %s
es|stack_applying|Aplicando la pila de software: toutpanel %s
it|stack_applying|Applicazione dello stack software: toutpanel %s
pt|stack_applying|A aplicar a pilha de software: toutpanel %s
nl|stack_applying|De softwarestack wordt toegepast: toutpanel %s
ru|stack_applying|Применение программного стека: toutpanel %s
zh|stack_applying|正在应用软件栈：toutpanel %s
ar|stack_applying|جارٍ تطبيق حزمة البرامج: toutpanel %s
en|stack_ok|Software stack installed.
fr|stack_ok|Pile logicielle installée.
de|stack_ok|Software-Stack installiert.
es|stack_ok|Pila de software instalada.
it|stack_ok|Stack software installato.
pt|stack_ok|Pilha de software instalada.
nl|stack_ok|Softwarestack geïnstalleerd.
ru|stack_ok|Программный стек установлен.
zh|stack_ok|软件栈已安装。
ar|stack_ok|تم تثبيت حزمة البرامج.
en|stack_failed|The software stack was not completely installed (the panel itself is installed and running).
fr|stack_failed|La pile logicielle n'a pas été installée complètement (le panel lui-même est installé et fonctionne).
de|stack_failed|Der Software-Stack wurde nicht vollständig installiert (das Panel selbst ist installiert und läuft).
es|stack_failed|La pila de software no se instaló por completo (el panel en sí está instalado y en marcha).
it|stack_failed|Lo stack software non è stato installato completamente (il pannello stesso è installato e in esecuzione).
pt|stack_failed|A pilha de software não foi instalada por completo (o painel em si está instalado e em execução).
nl|stack_failed|De softwarestack is niet volledig geïnstalleerd (het paneel zelf is geïnstalleerd en draait).
ru|stack_failed|Программный стек установлен не полностью (сама панель установлена и работает).
zh|stack_failed|软件栈未完整安装（面板本身已安装并在运行）。
ar|stack_failed|لم تُثبَّت حزمة البرامج بالكامل (اللوحة نفسها مثبّتة وتعمل).
en|stack_soon|A requested component is not available yet: nothing was installed from the stack (the panel is installed).
fr|stack_soon|Un composant demandé n'est pas encore disponible : rien n'a été installé de la pile (le panel est installé).
de|stack_soon|Eine angeforderte Komponente ist noch nicht verfügbar: vom Stack wurde nichts installiert (das Panel ist installiert).
es|stack_soon|Un componente solicitado aún no está disponible: no se instaló nada de la pila (el panel está instalado).
it|stack_soon|Un componente richiesto non è ancora disponibile: dello stack non è stato installato nulla (il pannello è installato).
pt|stack_soon|Um componente pedido ainda não está disponível: nada da pilha foi instalado (o painel está instalado).
nl|stack_soon|Een gevraagd onderdeel is nog niet beschikbaar: er is niets van de stack geïnstalleerd (het paneel is geïnstalleerd).
ru|stack_soon|Запрошенный компонент пока недоступен: из стека ничего не установлено (панель установлена).
zh|stack_soon|所请求的组件尚不可用：软件栈中的内容均未安装（面板已安装）。
ar|stack_soon|أحد المكونات المطلوبة غير متاح بعد: لم يُثبَّت شيء من الحزمة (اللوحة مثبّتة).
en|stack_usage|The stack options were refused by toutpanel stack (see the message above); the panel is installed.
fr|stack_usage|Les options de pile ont été refusées par toutpanel stack (voir le message ci-dessus) ; le panel est installé.
de|stack_usage|Die Stack-Optionen wurden von toutpanel stack abgelehnt (siehe Meldung oben); das Panel ist installiert.
es|stack_usage|Las opciones de pila fueron rechazadas por toutpanel stack (véase el mensaje anterior); el panel está instalado.
it|stack_usage|Le opzioni dello stack sono state rifiutate da toutpanel stack (vedere il messaggio sopra); il pannello è installato.
pt|stack_usage|As opções da pilha foram recusadas por toutpanel stack (consulte a mensagem acima); o painel está instalado.
nl|stack_usage|De stackopties zijn geweigerd door toutpanel stack (zie de melding hierboven); het paneel is geïnstalleerd.
ru|stack_usage|Параметры стека отклонены командой toutpanel stack (см. сообщение выше); панель установлена.
zh|stack_usage|toutpanel stack 拒绝了这些软件栈选项（见上方信息）；面板已安装。
ar|stack_usage|رفض toutpanel stack خيارات الحزمة (انظر الرسالة أعلاه)؛ اللوحة مثبّتة.
en|stack_not_applied|To resume the stack installation (finished steps are kept), run:
fr|stack_not_applied|Pour reprendre l'installation de la pile (les étapes terminées sont conservées), lancez :
de|stack_not_applied|Um die Stack-Installation fortzusetzen (abgeschlossene Schritte bleiben erhalten), führen Sie aus:
es|stack_not_applied|Para reanudar la instalación de la pila (los pasos terminados se conservan), ejecute:
it|stack_not_applied|Per riprendere l'installazione dello stack (i passaggi completati sono conservati), eseguire:
pt|stack_not_applied|Para retomar a instalação da pilha (os passos concluídos são mantidos), execute:
nl|stack_not_applied|Om de stackinstallatie te hervatten (voltooide stappen blijven behouden), voert u uit:
ru|stack_not_applied|Чтобы продолжить установку стека (завершённые шаги сохраняются), выполните:
zh|stack_not_applied|要继续安装软件栈（已完成的步骤会保留），请运行：
ar|stack_not_applied|لاستئناف تثبيت الحزمة (تُحفظ الخطوات المنجزة) نفّذ:
en|stack_later|Stack not installed now: choose it later in the web setup wizard (Software).
fr|stack_later|Pile non installée maintenant : à choisir plus tard dans l'assistant web (Logiciels).
de|stack_later|Stack wird jetzt nicht installiert: später im Web-Einrichtungsassistenten wählen (Software).
es|stack_later|Pila no instalada ahora: se elegirá más tarde en el asistente web (Software).
it|stack_later|Stack non installato ora: da scegliere più tardi nella procedura guidata web (Software).
pt|stack_later|Pilha não instalada agora: a escolher mais tarde no assistente web (Software).
nl|stack_later|Stack nu niet geïnstalleerd: later te kiezen in de webwizard (Software).
ru|stack_later|Стек сейчас не устанавливается: выберите его позже в веб-мастере (Программы).
zh|stack_later|暂不安装软件栈：稍后在网页设置向导（软件）中选择。
ar|stack_later|لن تُثبَّت الحزمة الآن: اخترها لاحقًا في معالج الإعداد عبر الويب (البرامج).
en|stack_profiles_unavailable|The list of profiles is unavailable: installing the default stack.
fr|stack_profiles_unavailable|La liste des profils est indisponible : installation de la pile par défaut.
de|stack_profiles_unavailable|Die Profilliste ist nicht verfügbar: der Standard-Stack wird installiert.
es|stack_profiles_unavailable|La lista de perfiles no está disponible: se instala la pila predeterminada.
it|stack_profiles_unavailable|L'elenco dei profili non è disponibile: viene installato lo stack predefinito.
pt|stack_profiles_unavailable|A lista de perfis não está disponível: a instalar a pilha predefinida.
nl|stack_profiles_unavailable|De lijst met profielen is niet beschikbaar: de standaardstack wordt geïnstalleerd.
ru|stack_profiles_unavailable|Список профилей недоступен: устанавливается стек по умолчанию.
zh|stack_profiles_unavailable|配置方案列表不可用：将安装默认软件栈。
ar|stack_profiles_unavailable|قائمة الملفات غير متاحة: سيتم تثبيت الحزمة الافتراضية.
en|stack_q_title|Software stack: choose a profile (* = recommended for this server)
fr|stack_q_title|Pile logicielle : choisissez un profil (* = recommandé pour ce serveur)
de|stack_q_title|Software-Stack: wählen Sie ein Profil (* = für diesen Server empfohlen)
es|stack_q_title|Pila de software: elija un perfil (* = recomendado para este servidor)
it|stack_q_title|Stack software: scegliere un profilo (* = consigliato per questo server)
pt|stack_q_title|Pilha de software: escolha um perfil (* = recomendado para este servidor)
nl|stack_q_title|Softwarestack: kies een profiel (* = aanbevolen voor deze server)
ru|stack_q_title|Программный стек: выберите профиль (* = рекомендуется для этого сервера)
zh|stack_q_title|软件栈：请选择配置方案（* = 推荐用于此服务器）
ar|stack_q_title|حزمة البرامج: اختر ملفًا (* = موصى به لهذا الخادم)
en|stack_q_ram|RAM %s MB
fr|stack_q_ram|RAM %s Mo
de|stack_q_ram|RAM %s MB
es|stack_q_ram|RAM %s MB
it|stack_q_ram|RAM %s MB
pt|stack_q_ram|RAM %s MB
nl|stack_q_ram|RAM %s MB
ru|stack_q_ram|ОЗУ %s МБ
zh|stack_q_ram|内存 %s MB
ar|stack_q_ram|الذاكرة %s MB
en|stack_q_later|Decide later in the web setup wizard (nothing is installed now)
fr|stack_q_later|Décider plus tard dans l'assistant web (rien n'est installé maintenant)
de|stack_q_later|Später im Web-Einrichtungsassistenten entscheiden (jetzt wird nichts installiert)
es|stack_q_later|Decidirlo más tarde en el asistente web (ahora no se instala nada)
it|stack_q_later|Decidere più tardi nella procedura guidata web (ora non viene installato nulla)
pt|stack_q_later|Decidir mais tarde no assistente web (agora não é instalado nada)
nl|stack_q_later|Later beslissen in de webwizard (nu wordt niets geïnstalleerd)
ru|stack_q_later|Решить позже в веб-мастере (сейчас ничего не устанавливается)
zh|stack_q_later|稍后在网页设置向导中决定（现在不安装任何内容）
ar|stack_q_later|القرار لاحقًا في معالج الإعداد عبر الويب (لا يُثبَّت شيء الآن)
en|stack_q_prompt|Choice [%s]:
fr|stack_q_prompt|Choix [%s] :
de|stack_q_prompt|Auswahl [%s]:
es|stack_q_prompt|Opción [%s]:
it|stack_q_prompt|Scelta [%s]:
pt|stack_q_prompt|Escolha [%s]:
nl|stack_q_prompt|Keuze [%s]:
ru|stack_q_prompt|Выбор [%s]:
zh|stack_q_prompt|请选择 [%s]：
ar|stack_q_prompt|الاختيار [%s]:
en|stack_val_composer|profile %s (stack composer)
fr|stack_val_composer|profil %s (composeur de pile)
de|stack_val_composer|Profil %s (Stack-Composer)
es|stack_val_composer|perfil %s (compositor de pila)
it|stack_val_composer|profilo %s (compositore dello stack)
pt|stack_val_composer|perfil %s (compositor de pilha)
nl|stack_val_composer|profiel %s (stackcomposer)
ru|stack_val_composer|профиль %s (конструктор стека)
zh|stack_val_composer|配置方案 %s（软件栈编排器）
ar|stack_val_composer|الملف %s (مُركِّب الحزمة)
en|stack_val_default|default stack (Nginx, PHP-FPM, MariaDB, Redis, Certbot…)
fr|stack_val_default|pile par défaut (Nginx, PHP-FPM, MariaDB, Redis, Certbot…)
de|stack_val_default|Standard-Stack (Nginx, PHP-FPM, MariaDB, Redis, Certbot …)
es|stack_val_default|pila predeterminada (Nginx, PHP-FPM, MariaDB, Redis, Certbot…)
it|stack_val_default|stack predefinito (Nginx, PHP-FPM, MariaDB, Redis, Certbot…)
pt|stack_val_default|pilha predefinida (Nginx, PHP-FPM, MariaDB, Redis, Certbot…)
nl|stack_val_default|standaardstack (Nginx, PHP-FPM, MariaDB, Redis, Certbot…)
ru|stack_val_default|стек по умолчанию (Nginx, PHP-FPM, MariaDB, Redis, Certbot…)
zh|stack_val_default|默认软件栈（Nginx、PHP-FPM、MariaDB、Redis、Certbot……）
ar|stack_val_default|الحزمة الافتراضية (Nginx وPHP-FPM وMariaDB وRedis وCertbot…)
en|stack_val_none|panel only
fr|stack_val_none|panel seul
de|stack_val_none|nur das Panel
es|stack_val_none|solo el panel
it|stack_val_none|solo il pannello
pt|stack_val_none|apenas o painel
nl|stack_val_none|alleen het paneel
ru|stack_val_none|только панель
zh|stack_val_none|仅面板
ar|stack_val_none|اللوحة فقط
en|stack_val_failed|not completely installed (resume with: toutpanel stack apply)
fr|stack_val_failed|installée partiellement (reprise : toutpanel stack apply)
de|stack_val_failed|nicht vollständig installiert (Fortsetzen mit: toutpanel stack apply)
es|stack_val_failed|instalada parcialmente (reanudar con: toutpanel stack apply)
it|stack_val_failed|installata parzialmente (riprendere con: toutpanel stack apply)
pt|stack_val_failed|instalada parcialmente (retomar com: toutpanel stack apply)
nl|stack_val_failed|niet volledig geïnstalleerd (hervatten met: toutpanel stack apply)
ru|stack_val_failed|установлен не полностью (продолжить: toutpanel stack apply)
zh|stack_val_failed|未完整安装（继续安装：toutpanel stack apply）
ar|stack_val_failed|لم تُثبَّت بالكامل (للاستئناف: toutpanel stack apply)
en|stack_val_later|to be chosen in the web setup wizard
fr|stack_val_later|à choisir dans l'assistant web
de|stack_val_later|im Web-Einrichtungsassistenten zu wählen
es|stack_val_later|se elegirá en el asistente web
it|stack_val_later|da scegliere nella procedura guidata web
pt|stack_val_later|a escolher no assistente web
nl|stack_val_later|te kiezen in de webwizard
ru|stack_val_later|будет выбран в веб-мастере
zh|stack_val_later|在网页设置向导中选择
ar|stack_val_later|يُختار في معالج الإعداد عبر الويب
en|dry_title|Dry run: nothing is modified
fr|dry_title|Simulation : rien n'est modifié
de|dry_title|Testlauf: nichts wird verändert
es|dry_title|Simulación: no se modifica nada
it|dry_title|Simulazione: nulla viene modificato
pt|dry_title|Simulação: nada é alterado
nl|dry_title|Proefrun: er wordt niets gewijzigd
ru|dry_title|Пробный запуск: ничего не изменяется
zh|dry_title|模拟运行：不做任何修改
ar|dry_title|تشغيل تجريبي: لا يُعدَّل شيء
en|dry_distro_detail|ID %s, family %s, %s, init %s, %s
fr|dry_distro_detail|ID %s, famille %s, %s, init %s, %s
de|dry_distro_detail|ID %s, Familie %s, %s, Init %s, %s
es|dry_distro_detail|ID %s, familia %s, %s, init %s, %s
it|dry_distro_detail|ID %s, famiglia %s, %s, init %s, %s
pt|dry_distro_detail|ID %s, família %s, %s, init %s, %s
nl|dry_distro_detail|ID %s, familie %s, %s, init %s, %s
ru|dry_distro_detail|ID %s, семейство %s, %s, init %s, %s
zh|dry_distro_detail|ID %s，家族 %s，%s，init %s，%s
ar|dry_distro_detail|المعرّف %s، العائلة %s، %s، init %s، %s
en|dry_python_provision|system Python too old (strategy: %s)
fr|dry_python_provision|Python du système trop ancien (stratégie : %s)
de|dry_python_provision|System-Python zu alt (Strategie: %s)
es|dry_python_provision|Python del sistema demasiado antiguo (estrategia: %s)
it|dry_python_provision|Python di sistema troppo vecchio (strategia: %s)
pt|dry_python_provision|Python do sistema demasiado antigo (estratégia: %s)
nl|dry_python_provision|systeem-Python te oud (strategie: %s)
ru|dry_python_provision|системный Python слишком старый (стратегия: %s)
zh|dry_python_provision|系统 Python 过旧（策略：%s）
ar|dry_python_provision|Python النظام قديم جدًا (الاستراتيجية: %s)
en|dry_python_system|system Python (3.9+ available or not needed)
fr|dry_python_system|Python du système (3.9+ disponible ou sans objet)
de|dry_python_system|System-Python (3.9+ vorhanden oder nicht nötig)
es|dry_python_system|Python del sistema (3.9+ disponible o no necesario)
it|dry_python_system|Python di sistema (3.9+ disponibile o non necessario)
pt|dry_python_system|Python do sistema (3.9+ disponível ou desnecessário)
nl|dry_python_system|systeem-Python (3.9+ beschikbaar of niet nodig)
ru|dry_python_system|системный Python (3.9+ доступен или не требуется)
zh|dry_python_system|系统 Python（有 3.9+ 或无需提供）
ar|dry_python_system|Python النظام (3.9+ متوفر أو غير مطلوب)
en|dry_cmds|Commands that would run once the panel is installed:
fr|dry_cmds|Commandes qui seraient lancées une fois le panel installé :
de|dry_cmds|Befehle, die nach der Installation des Panels ausgeführt würden:
es|dry_cmds|Comandos que se ejecutarían una vez instalado el panel:
it|dry_cmds|Comandi che verrebbero eseguiti dopo l'installazione del pannello:
pt|dry_cmds|Comandos que seriam executados depois de instalar o painel:
nl|dry_cmds|Opdrachten die zouden worden uitgevoerd zodra het paneel is geïnstalleerd:
ru|dry_cmds|Команды, которые будут выполнены после установки панели:
zh|dry_cmds|面板安装完成后将执行的命令：
ar|dry_cmds|الأوامر التي ستُنفَّذ بعد تثبيت اللوحة:
en|dry_nothing|Nothing was changed (--dry-run).
fr|dry_nothing|Rien n'a été modifié (--dry-run).
de|dry_nothing|Es wurde nichts geändert (--dry-run).
es|dry_nothing|No se ha modificado nada (--dry-run).
it|dry_nothing|Nulla è stato modificato (--dry-run).
pt|dry_nothing|Nada foi alterado (--dry-run).
nl|dry_nothing|Er is niets gewijzigd (--dry-run).
ru|dry_nothing|Ничего не изменено (--dry-run).
zh|dry_nothing|未做任何修改（--dry-run）。
ar|dry_nothing|لم يُعدَّل شيء (--dry-run).
en|lbl_distro|Distribution
fr|lbl_distro|Distribution
de|lbl_distro|Distribution
es|lbl_distro|Distribución
it|lbl_distro|Distribuzione
pt|lbl_distro|Distribuição
nl|lbl_distro|Distributie
ru|lbl_distro|Дистрибутив
zh|lbl_distro|发行版
ar|lbl_distro|التوزيعة
en|lbl_support|Support level
fr|lbl_support|Niveau de support
de|lbl_support|Unterstützungsstufe
es|lbl_support|Nivel de soporte
it|lbl_support|Livello di supporto
pt|lbl_support|Nível de suporte
nl|lbl_support|Ondersteuningsniveau
ru|lbl_support|Уровень поддержки
zh|lbl_support|支持级别
ar|lbl_support|مستوى الدعم
en|lbl_python|Python
fr|lbl_python|Python
de|lbl_python|Python
es|lbl_python|Python
it|lbl_python|Python
pt|lbl_python|Python
nl|lbl_python|Python
ru|lbl_python|Python
zh|lbl_python|Python
ar|lbl_python|Python
en|lbl_firewall|Firewall
fr|lbl_firewall|Pare-feu
de|lbl_firewall|Firewall
es|lbl_firewall|Cortafuegos
it|lbl_firewall|Firewall
pt|lbl_firewall|Firewall
nl|lbl_firewall|Firewall
ru|lbl_firewall|Брандмауэр
zh|lbl_firewall|防火墙
ar|lbl_firewall|جدار الحماية
en|lbl_stack|Software stack
fr|lbl_stack|Pile logicielle
de|lbl_stack|Software-Stack
es|lbl_stack|Pila de software
it|lbl_stack|Stack software
pt|lbl_stack|Pilha de software
nl|lbl_stack|Softwarestack
ru|lbl_stack|Программный стек
zh|lbl_stack|软件栈
ar|lbl_stack|حزمة البرامج
en|lbl_profile|Stack profile
fr|lbl_profile|Profil de pile
de|lbl_profile|Stack-Profil
es|lbl_profile|Perfil de pila
it|lbl_profile|Profilo dello stack
pt|lbl_profile|Perfil da pilha
nl|lbl_profile|Stackprofiel
ru|lbl_profile|Профиль стека
zh|lbl_profile|软件栈配置方案
ar|lbl_profile|ملف الحزمة
en|lbl_components|Components
fr|lbl_components|Composants
de|lbl_components|Komponenten
es|lbl_components|Componentes
it|lbl_components|Componenti
pt|lbl_components|Componentes
nl|lbl_components|Onderdelen
ru|lbl_components|Компоненты
zh|lbl_components|组件
ar|lbl_components|المكونات
en|lbl_compat|Compatibility
fr|lbl_compat|Compatibilité
de|lbl_compat|Kompatibilität
es|lbl_compat|Compatibilidad
it|lbl_compat|Compatibilità
pt|lbl_compat|Compatibilidade
nl|lbl_compat|Compatibiliteit
ru|lbl_compat|Совместимость
zh|lbl_compat|兼容性
ar|lbl_compat|التوافق
en|opt_linux_only|The option %s is only available with the Linux installer (stack composer, firewall mode and system detection are Linux features). On Windows use -Stack to install Nginx, PHP and MariaDB.
fr|opt_linux_only|L'option %s n'existe que dans l'installeur Linux (composeur de pile, mode du pare-feu et détection du système sont des fonctions Linux). Sous Windows, -Stack installe Nginx, PHP et MariaDB.
de|opt_linux_only|Die Option %s gibt es nur im Linux-Installer (Stack-Composer, Firewall-Modus und Systemerkennung sind Linux-Funktionen). Unter Windows installiert -Stack Nginx, PHP und MariaDB.
es|opt_linux_only|La opción %s solo existe en el instalador de Linux (compositor de pila, modo del cortafuegos y detección del sistema son funciones de Linux). En Windows, -Stack instala Nginx, PHP y MariaDB.
it|opt_linux_only|L'opzione %s esiste solo nell'installer Linux (compositore dello stack, modalità del firewall e rilevamento del sistema sono funzioni Linux). Su Windows, -Stack installa Nginx, PHP e MariaDB.
pt|opt_linux_only|A opção %s só existe no instalador Linux (compositor de pilha, modo do firewall e deteção do sistema são funções do Linux). No Windows, -Stack instala Nginx, PHP e MariaDB.
nl|opt_linux_only|De optie %s bestaat alleen in het Linux-installatieprogramma (stackcomposer, firewallmodus en systeemdetectie zijn Linux-functies). Op Windows installeert -Stack Nginx, PHP en MariaDB.
ru|opt_linux_only|Параметр %s есть только в установщике для Linux (конструктор стека, режим брандмауэра и определение системы — функции Linux). В Windows -Stack устанавливает Nginx, PHP и MariaDB.
zh|opt_linux_only|选项 %s 仅在 Linux 安装程序中提供（软件栈编排器、防火墙模式和系统检测都是 Linux 功能）。在 Windows 上，-Stack 会安装 Nginx、PHP 和 MariaDB。
ar|opt_linux_only|الخيار %s متاح فقط في مثبّت لينكس (مُركِّب الحزمة ووضع جدار الحماية واكتشاف النظام ميزات خاصة بلينكس). في ويندوز يثبّت -Stack كلًا من Nginx وPHP وMariaDB.
en|win_dryrun_na|The option -DryRun is not available on Windows.
fr|win_dryrun_na|L'option -DryRun n'existe pas sous Windows.
de|win_dryrun_na|Die Option -DryRun gibt es unter Windows nicht.
es|win_dryrun_na|La opción -DryRun no existe en Windows.
it|win_dryrun_na|L'opzione -DryRun non esiste su Windows.
pt|win_dryrun_na|A opção -DryRun não existe no Windows.
nl|win_dryrun_na|De optie -DryRun bestaat niet op Windows.
ru|win_dryrun_na|Параметра -DryRun в Windows нет.
zh|win_dryrun_na|Windows 上没有 -DryRun 选项。
ar|win_dryrun_na|الخيار -DryRun غير متاح في ويندوز.
en|home_existing_kept|Existing installation detected in %s: kept in place, nothing is moved.
fr|home_existing_kept|Installation existante détectée dans %s : conservée sur place, rien n'est déplacé.
de|home_existing_kept|Bestehende Installation in %s erkannt: bleibt an Ort und Stelle, nichts wird verschoben.
es|home_existing_kept|Instalación existente detectada en %s: se conserva en su sitio, no se mueve nada.
it|home_existing_kept|Installazione esistente rilevata in %s: conservata sul posto, nulla viene spostato.
pt|home_existing_kept|Instalação existente detetada em %s: mantida no local, nada é movido.
nl|home_existing_kept|Bestaande installatie gevonden in %s: blijft op zijn plaats, er wordt niets verplaatst.
ru|home_existing_kept|Обнаружена существующая установка в %s: остаётся на месте, ничего не переносится.
zh|home_existing_kept|检测到 %s 中的现有安装：原地保留，不做任何移动。
ar|home_existing_kept|تم اكتشاف تثبيت موجود في %s: يبقى في مكانه دون نقل.
en|help_win_linux_only|Linux only (see install.sh --help): firewall mode, stack composer (--profile, --web, --php, --db…), distribution detection, --dry-run. On Windows, -Stack installs Nginx, PHP and MariaDB.
fr|help_win_linux_only|Réservé à Linux (voir install.sh --help) : mode du pare-feu, composeur de pile (--profile, --web, --php, --db…), détection de la distribution, --dry-run. Sous Windows, -Stack installe Nginx, PHP et MariaDB.
de|help_win_linux_only|Nur unter Linux (siehe install.sh --help): Firewall-Modus, Stack-Composer (--profile, --web, --php, --db …), Distributionserkennung, --dry-run. Unter Windows installiert -Stack Nginx, PHP und MariaDB.
es|help_win_linux_only|Solo en Linux (véase install.sh --help): modo del cortafuegos, compositor de pila (--profile, --web, --php, --db…), detección de la distribución, --dry-run. En Windows, -Stack instala Nginx, PHP y MariaDB.
it|help_win_linux_only|Solo su Linux (vedere install.sh --help): modalità del firewall, compositore dello stack (--profile, --web, --php, --db…), rilevamento della distribuzione, --dry-run. Su Windows, -Stack installa Nginx, PHP e MariaDB.
pt|help_win_linux_only|Apenas no Linux (consulte install.sh --help): modo do firewall, compositor de pilha (--profile, --web, --php, --db…), deteção da distribuição, --dry-run. No Windows, -Stack instala Nginx, PHP e MariaDB.
nl|help_win_linux_only|Alleen op Linux (zie install.sh --help): firewallmodus, stackcomposer (--profile, --web, --php, --db…), distributiedetectie, --dry-run. Op Windows installeert -Stack Nginx, PHP en MariaDB.
ru|help_win_linux_only|Только для Linux (см. install.sh --help): режим брандмауэра, конструктор стека (--profile, --web, --php, --db…), определение дистрибутива, --dry-run. В Windows -Stack устанавливает Nginx, PHP и MariaDB.
zh|help_win_linux_only|仅限 Linux（见 install.sh --help）：防火墙模式、软件栈编排器（--profile、--web、--php、--db……）、发行版检测、--dry-run。在 Windows 上，-Stack 会安装 Nginx、PHP 和 MariaDB。
ar|help_win_linux_only|خاص بلينكس (راجع install.sh --help): وضع جدار الحماية ومُركِّب الحزمة (--profile و--web و--php و--db…) واكتشاف التوزيعة و--dry-run. في ويندوز يثبّت -Stack كلًا من Nginx وPHP وMariaDB.
en|h_password_env|admin password: variable TOUTPANEL_PASSWORD (keep it with sudo -E); not visible in the process list
fr|h_password_env|mot de passe admin : variable TOUTPANEL_PASSWORD (à conserver avec sudo -E) ; invisible dans la liste des processus
de|h_password_env|Admin-Passwort: Variable TOUTPANEL_PASSWORD (mit sudo -E beibehalten); in der Prozessliste nicht sichtbar
es|h_password_env|contraseña del administrador: variable TOUTPANEL_PASSWORD (conservarla con sudo -E); no visible en la lista de procesos
it|h_password_env|password dell'amministratore: variabile TOUTPANEL_PASSWORD (da mantenere con sudo -E); non visibile nell'elenco dei processi
pt|h_password_env|senha do administrador: variável TOUTPANEL_PASSWORD (preservar com sudo -E); não visível na lista de processos
nl|h_password_env|beheerderswachtwoord: variabele TOUTPANEL_PASSWORD (behouden met sudo -E); niet zichtbaar in de proceslijst
ru|h_password_env|пароль администратора: переменная TOUTPANEL_PASSWORD (сохраняйте через sudo -E); не виден в списке процессов
zh|h_password_env|管理员密码：环境变量 TOUTPANEL_PASSWORD（用 sudo -E 保留）；不会出现在进程列表中
ar|h_password_env|كلمة مرور المسؤول: المتغير TOUTPANEL_PASSWORD (احتفظ به باستخدام sudo -E)؛ لا يظهر في قائمة العمليات
en|h_password_env_win|admin password: variable $env:TOUTPANEL_PASSWORD; not visible in the process list
fr|h_password_env_win|mot de passe admin : variable $env:TOUTPANEL_PASSWORD ; invisible dans la liste des processus
de|h_password_env_win|Admin-Passwort: Variable $env:TOUTPANEL_PASSWORD; in der Prozessliste nicht sichtbar
es|h_password_env_win|contraseña del administrador: variable $env:TOUTPANEL_PASSWORD; no visible en la lista de procesos
it|h_password_env_win|password dell'amministratore: variabile $env:TOUTPANEL_PASSWORD; non visibile nell'elenco dei processi
pt|h_password_env_win|senha do administrador: variável $env:TOUTPANEL_PASSWORD; não visível na lista de processos
nl|h_password_env_win|beheerderswachtwoord: variabele $env:TOUTPANEL_PASSWORD; niet zichtbaar in de proceslijst
ru|h_password_env_win|пароль администратора: переменная $env:TOUTPANEL_PASSWORD; не виден в списке процессов
zh|h_password_env_win|管理员密码：变量 $env:TOUTPANEL_PASSWORD；不会出现在进程列表中
ar|h_password_env_win|كلمة مرور المسؤول: المتغير $env:TOUTPANEL_PASSWORD؛ لا يظهر في قائمة العمليات
en|h_password_file|read the admin password from this file (first line; on Linux the file must be reserved to its owner: chmod 600)
fr|h_password_file|lit le mot de passe admin dans ce fichier (1re ligne ; sous Linux, le fichier doit être réservé à son propriétaire : chmod 600)
de|h_password_file|Admin-Passwort aus dieser Datei lesen (erste Zeile; unter Linux nur für den Eigentümer zugänglich: chmod 600)
es|h_password_file|lee la contraseña del administrador de este archivo (primera línea; en Linux el archivo debe ser accesible solo a su propietario: chmod 600)
it|h_password_file|legge la password dell'amministratore da questo file (prima riga; su Linux il file deve essere riservato al proprietario: chmod 600)
pt|h_password_file|lê a senha do administrador deste ficheiro (primeira linha; no Linux o ficheiro deve ser reservado ao proprietário: chmod 600)
nl|h_password_file|leest het beheerderswachtwoord uit dit bestand (eerste regel; op Linux alleen toegankelijk voor de eigenaar: chmod 600)
ru|h_password_file|читает пароль администратора из этого файла (первая строка; в Linux файл должен быть доступен только владельцу: chmod 600)
zh|h_password_file|从该文件读取管理员密码（第一行；在 Linux 上文件只能由所有者访问：chmod 600）
ar|h_password_file|يقرأ كلمة مرور المسؤول من هذا الملف (السطر الأول؛ في لينكس يجب أن يقتصر الملف على مالكه: chmod 600)
en|h_password_stdin|read the admin password on standard input (first line; not usable with curl | bash)
fr|h_password_stdin|lit le mot de passe admin sur l'entrée standard (1re ligne ; inutilisable avec curl | bash)
de|h_password_stdin|Admin-Passwort von der Standardeingabe lesen (erste Zeile; nicht mit curl | bash nutzbar)
es|h_password_stdin|lee la contraseña del administrador de la entrada estándar (primera línea; no utilizable con curl | bash)
it|h_password_stdin|legge la password dell'amministratore dallo standard input (prima riga; non utilizzabile con curl | bash)
pt|h_password_stdin|lê a senha do administrador da entrada padrão (primeira linha; não utilizável com curl | bash)
nl|h_password_stdin|leest het beheerderswachtwoord van de standaardinvoer (eerste regel; niet bruikbaar met curl | bash)
ru|h_password_stdin|читает пароль администратора со стандартного ввода (первая строка; непригодно при curl | bash)
zh|h_password_stdin|从标准输入读取管理员密码（第一行；不能与 curl | bash 同用）
ar|h_password_stdin|يقرأ كلمة مرور المسؤول من الإدخال القياسي (السطر الأول؛ لا يصلح مع curl | bash)
en|pass_arg_warn|Warning: --password puts the admin password in the process list (ps) and the shell history. Prefer the variable TOUTPANEL_PASSWORD (keep it with sudo -E), --password-file FILE or --password-stdin.
fr|pass_arg_warn|Attention : --password place le mot de passe admin dans la liste des processus (ps) et l'historique du shell. Préférez la variable TOUTPANEL_PASSWORD (à conserver avec sudo -E), --password-file FICHIER ou --password-stdin.
de|pass_arg_warn|Achtung: --password legt das Admin-Passwort in die Prozessliste (ps) und den Shell-Verlauf. Besser: Variable TOUTPANEL_PASSWORD (mit sudo -E beibehalten), --password-file DATEI oder --password-stdin.
es|pass_arg_warn|Atención: --password deja la contraseña del administrador en la lista de procesos (ps) y en el historial del shell. Es preferible la variable TOUTPANEL_PASSWORD (consérvela con sudo -E), --password-file ARCHIVO o --password-stdin.
it|pass_arg_warn|Attenzione: --password lascia la password dell'amministratore nell'elenco dei processi (ps) e nella cronologia della shell. Meglio la variabile TOUTPANEL_PASSWORD (mantenerla con sudo -E), --password-file FILE o --password-stdin.
pt|pass_arg_warn|Atenção: --password deixa a senha do administrador na lista de processos (ps) e no histórico da shell. Prefira a variável TOUTPANEL_PASSWORD (preserve-a com sudo -E), --password-file FICHEIRO ou --password-stdin.
nl|pass_arg_warn|Let op: --password zet het beheerderswachtwoord in de proceslijst (ps) en de shellgeschiedenis. Gebruik liever de variabele TOUTPANEL_PASSWORD (behouden met sudo -E), --password-file BESTAND of --password-stdin.
ru|pass_arg_warn|Внимание: --password оставляет пароль администратора в списке процессов (ps) и истории оболочки. Лучше используйте переменную TOUTPANEL_PASSWORD (сохраняйте через sudo -E), --password-file ФАЙЛ или --password-stdin.
zh|pass_arg_warn|注意：--password 会把管理员密码留在进程列表（ps）和 shell 历史中。建议使用变量 TOUTPANEL_PASSWORD（用 sudo -E 保留）、--password-file 文件 或 --password-stdin。
ar|pass_arg_warn|تنبيه: يترك --password كلمة مرور المسؤول في قائمة العمليات (ps) وسجل الصدفة. يُفضَّل المتغير TOUTPANEL_PASSWORD (احتفظ به باستخدام sudo -E) أو --password-file ملف أو --password-stdin.
en|pass_arg_warn_win|Warning: -Password puts the admin password in the process list and the command history. Prefer $env:TOUTPANEL_PASSWORD, -PasswordFile FILE, -PasswordSecure or -PasswordStdin.
fr|pass_arg_warn_win|Attention : -Password place le mot de passe admin dans la liste des processus et l'historique des commandes. Préférez $env:TOUTPANEL_PASSWORD, -PasswordFile FICHIER, -PasswordSecure ou -PasswordStdin.
de|pass_arg_warn_win|Achtung: -Password legt das Admin-Passwort in die Prozessliste und den Befehlsverlauf. Besser: $env:TOUTPANEL_PASSWORD, -PasswordFile DATEI, -PasswordSecure oder -PasswordStdin.
es|pass_arg_warn_win|Atención: -Password deja la contraseña del administrador en la lista de procesos y en el historial de comandos. Es preferible $env:TOUTPANEL_PASSWORD, -PasswordFile ARCHIVO, -PasswordSecure o -PasswordStdin.
it|pass_arg_warn_win|Attenzione: -Password lascia la password dell'amministratore nell'elenco dei processi e nella cronologia dei comandi. Meglio $env:TOUTPANEL_PASSWORD, -PasswordFile FILE, -PasswordSecure o -PasswordStdin.
pt|pass_arg_warn_win|Atenção: -Password deixa a senha do administrador na lista de processos e no histórico de comandos. Prefira $env:TOUTPANEL_PASSWORD, -PasswordFile FICHEIRO, -PasswordSecure ou -PasswordStdin.
nl|pass_arg_warn_win|Let op: -Password zet het beheerderswachtwoord in de proceslijst en de opdrachtgeschiedenis. Gebruik liever $env:TOUTPANEL_PASSWORD, -PasswordFile BESTAND, -PasswordSecure of -PasswordStdin.
ru|pass_arg_warn_win|Внимание: -Password оставляет пароль администратора в списке процессов и истории команд. Лучше используйте $env:TOUTPANEL_PASSWORD, -PasswordFile ФАЙЛ, -PasswordSecure или -PasswordStdin.
zh|pass_arg_warn_win|注意：-Password 会把管理员密码留在进程列表和命令历史中。建议使用 $env:TOUTPANEL_PASSWORD、-PasswordFile 文件、-PasswordSecure 或 -PasswordStdin。
ar|pass_arg_warn_win|تنبيه: يترك -Password كلمة مرور المسؤول في قائمة العمليات وسجل الأوامر. يُفضَّل $env:TOUTPANEL_PASSWORD أو -PasswordFile ملف أو -PasswordSecure أو -PasswordStdin.
en|pass_conflict|Give only one of --password, --password-file and --password-stdin.
fr|pass_conflict|Donnez une seule des options --password, --password-file et --password-stdin.
de|pass_conflict|Geben Sie nur eine der Optionen --password, --password-file und --password-stdin an.
es|pass_conflict|Indique solo una de las opciones --password, --password-file y --password-stdin.
it|pass_conflict|Indicare una sola delle opzioni --password, --password-file e --password-stdin.
pt|pass_conflict|Indique apenas uma das opções --password, --password-file e --password-stdin.
nl|pass_conflict|Geef slechts één van de opties --password, --password-file en --password-stdin op.
ru|pass_conflict|Укажите только один из параметров --password, --password-file и --password-stdin.
zh|pass_conflict|--password、--password-file 和 --password-stdin 只能使用其中一个。
ar|pass_conflict|حدّد واحدًا فقط من الخيارات --password و--password-file و--password-stdin.
en|pass_conflict_win|Give only one of -Password, -PasswordFile, -PasswordSecure and -PasswordStdin.
fr|pass_conflict_win|Donnez une seule des options -Password, -PasswordFile, -PasswordSecure et -PasswordStdin.
de|pass_conflict_win|Geben Sie nur eine der Optionen -Password, -PasswordFile, -PasswordSecure und -PasswordStdin an.
es|pass_conflict_win|Indique solo una de las opciones -Password, -PasswordFile, -PasswordSecure y -PasswordStdin.
it|pass_conflict_win|Indicare una sola delle opzioni -Password, -PasswordFile, -PasswordSecure e -PasswordStdin.
pt|pass_conflict_win|Indique apenas uma das opções -Password, -PasswordFile, -PasswordSecure e -PasswordStdin.
nl|pass_conflict_win|Geef slechts één van de opties -Password, -PasswordFile, -PasswordSecure en -PasswordStdin op.
ru|pass_conflict_win|Укажите только один из параметров -Password, -PasswordFile, -PasswordSecure и -PasswordStdin.
zh|pass_conflict_win|-Password、-PasswordFile、-PasswordSecure 和 -PasswordStdin 只能使用其中一个。
ar|pass_conflict_win|حدّد واحدًا فقط من الخيارات -Password و-PasswordFile و-PasswordSecure و-PasswordStdin.
en|pass_stdin_pipe|--password-stdin cannot be used when this script itself is read from standard input (curl | bash): use TOUTPANEL_PASSWORD (keep it with sudo -E) or --password-file FILE.
fr|pass_stdin_pipe|--password-stdin est inutilisable quand le script lui-même arrive sur l'entrée standard (curl | bash) : utilisez TOUTPANEL_PASSWORD (à conserver avec sudo -E) ou --password-file FICHIER.
de|pass_stdin_pipe|--password-stdin ist nicht nutzbar, wenn das Skript selbst über die Standardeingabe kommt (curl | bash): verwenden Sie TOUTPANEL_PASSWORD (mit sudo -E beibehalten) oder --password-file DATEI.
es|pass_stdin_pipe|--password-stdin no es utilizable cuando el propio script llega por la entrada estándar (curl | bash): use TOUTPANEL_PASSWORD (consérvela con sudo -E) o --password-file ARCHIVO.
it|pass_stdin_pipe|--password-stdin non è utilizzabile quando lo script stesso arriva dallo standard input (curl | bash): usare TOUTPANEL_PASSWORD (mantenerla con sudo -E) oppure --password-file FILE.
pt|pass_stdin_pipe|--password-stdin não é utilizável quando o próprio script chega pela entrada padrão (curl | bash): use TOUTPANEL_PASSWORD (preserve-a com sudo -E) ou --password-file FICHEIRO.
nl|pass_stdin_pipe|--password-stdin kan niet worden gebruikt als het script zelf via de standaardinvoer binnenkomt (curl | bash): gebruik TOUTPANEL_PASSWORD (behouden met sudo -E) of --password-file BESTAND.
ru|pass_stdin_pipe|--password-stdin нельзя использовать, когда сам скрипт поступает через стандартный ввод (curl | bash): используйте TOUTPANEL_PASSWORD (сохраняйте через sudo -E) или --password-file ФАЙЛ.
zh|pass_stdin_pipe|当脚本本身通过标准输入传入（curl | bash）时，不能使用 --password-stdin：请使用 TOUTPANEL_PASSWORD（用 sudo -E 保留）或 --password-file 文件。
ar|pass_stdin_pipe|لا يمكن استخدام --password-stdin عندما يصل السكربت نفسه عبر الإدخال القياسي (curl | bash): استخدم TOUTPANEL_PASSWORD (واحتفظ به باستخدام sudo -E) أو --password-file ملف.
en|pass_stdin_waf|--password-stdin and --waf-token-stdin both read standard input: give the password with TOUTPANEL_PASSWORD or --password-file FILE.
fr|pass_stdin_waf|--password-stdin et --waf-token-stdin lisent tous deux l'entrée standard : donnez le mot de passe par TOUTPANEL_PASSWORD ou --password-file FICHIER.
de|pass_stdin_waf|--password-stdin und --waf-token-stdin lesen beide die Standardeingabe: geben Sie das Passwort über TOUTPANEL_PASSWORD oder --password-file DATEI an.
es|pass_stdin_waf|--password-stdin y --waf-token-stdin leen ambas la entrada estándar: indique la contraseña con TOUTPANEL_PASSWORD o --password-file ARCHIVO.
it|pass_stdin_waf|--password-stdin e --waf-token-stdin leggono entrambi lo standard input: indicare la password con TOUTPANEL_PASSWORD o --password-file FILE.
pt|pass_stdin_waf|--password-stdin e --waf-token-stdin leem ambos a entrada padrão: indique a senha com TOUTPANEL_PASSWORD ou --password-file FICHEIRO.
nl|pass_stdin_waf|--password-stdin en --waf-token-stdin lezen allebei de standaardinvoer: geef het wachtwoord op via TOUTPANEL_PASSWORD of --password-file BESTAND.
ru|pass_stdin_waf|--password-stdin и --waf-token-stdin оба читают стандартный ввод: передайте пароль через TOUTPANEL_PASSWORD или --password-file ФАЙЛ.
zh|pass_stdin_waf|--password-stdin 和 --waf-token-stdin 都会读取标准输入：请通过 TOUTPANEL_PASSWORD 或 --password-file 文件 提供密码。
ar|pass_stdin_waf|كلٌّ من --password-stdin و--waf-token-stdin يقرأ الإدخال القياسي: مرّر كلمة المرور عبر TOUTPANEL_PASSWORD أو --password-file ملف.
en|pass_stdin_waf_win|-PasswordStdin and -WafTokenStdin both read standard input: give the password with $env:TOUTPANEL_PASSWORD or -PasswordFile FILE.
fr|pass_stdin_waf_win|-PasswordStdin et -WafTokenStdin lisent tous deux l'entrée standard : donnez le mot de passe par $env:TOUTPANEL_PASSWORD ou -PasswordFile FICHIER.
de|pass_stdin_waf_win|-PasswordStdin und -WafTokenStdin lesen beide die Standardeingabe: geben Sie das Passwort über $env:TOUTPANEL_PASSWORD oder -PasswordFile DATEI an.
es|pass_stdin_waf_win|-PasswordStdin y -WafTokenStdin leen ambas la entrada estándar: indique la contraseña con $env:TOUTPANEL_PASSWORD o -PasswordFile ARCHIVO.
it|pass_stdin_waf_win|-PasswordStdin e -WafTokenStdin leggono entrambi lo standard input: indicare la password con $env:TOUTPANEL_PASSWORD o -PasswordFile FILE.
pt|pass_stdin_waf_win|-PasswordStdin e -WafTokenStdin leem ambos a entrada padrão: indique a senha com $env:TOUTPANEL_PASSWORD ou -PasswordFile FICHEIRO.
nl|pass_stdin_waf_win|-PasswordStdin en -WafTokenStdin lezen allebei de standaardinvoer: geef het wachtwoord op via $env:TOUTPANEL_PASSWORD of -PasswordFile BESTAND.
ru|pass_stdin_waf_win|-PasswordStdin и -WafTokenStdin оба читают стандартный ввод: передайте пароль через $env:TOUTPANEL_PASSWORD или -PasswordFile ФАЙЛ.
zh|pass_stdin_waf_win|-PasswordStdin 和 -WafTokenStdin 都会读取标准输入：请通过 $env:TOUTPANEL_PASSWORD 或 -PasswordFile 文件 提供密码。
ar|pass_stdin_waf_win|كلٌّ من -PasswordStdin و-WafTokenStdin يقرأ الإدخال القياسي: مرّر كلمة المرور عبر $env:TOUTPANEL_PASSWORD أو -PasswordFile ملف.
en|pass_file_bad|Admin password file unreadable or empty: %s
fr|pass_file_bad|Fichier du mot de passe admin illisible ou vide : %s
de|pass_file_bad|Admin-Passwortdatei nicht lesbar oder leer: %s
es|pass_file_bad|Archivo de la contraseña del administrador ilegible o vacío: %s
it|pass_file_bad|File della password dell'amministratore illeggibile o vuoto: %s
pt|pass_file_bad|Ficheiro da senha do administrador ilegível ou vazio: %s
nl|pass_file_bad|Bestand met het beheerderswachtwoord onleesbaar of leeg: %s
ru|pass_file_bad|Файл с паролем администратора нечитаем или пуст: %s
zh|pass_file_bad|管理员密码文件无法读取或为空：%s
ar|pass_file_bad|ملف كلمة مرور المسؤول غير قابل للقراءة أو فارغ: %s
en|pass_file_perm|Password file %s is accessible to other users, or belongs to neither root nor you: restrict it with chmod 600 %s and retry.
fr|pass_file_perm|Le fichier du mot de passe %s est accessible à d'autres utilisateurs, ou n'appartient ni à root ni à vous : restreignez-le avec chmod 600 %s puis recommencez.
de|pass_file_perm|Die Passwortdatei %s ist für andere Benutzer zugänglich oder gehört weder root noch Ihnen: beschränken Sie sie mit chmod 600 %s und versuchen Sie es erneut.
es|pass_file_perm|El archivo de contraseña %s es accesible a otros usuarios o no pertenece ni a root ni a usted: restrinja el acceso con chmod 600 %s y vuelva a intentarlo.
it|pass_file_perm|Il file della password %s è accessibile ad altri utenti oppure non appartiene né a root né a voi: limitarlo con chmod 600 %s e riprovare.
pt|pass_file_perm|O ficheiro da senha %s é acessível a outros utilizadores ou não pertence nem a root nem a si: restrinja-o com chmod 600 %s e tente novamente.
nl|pass_file_perm|Het wachtwoordbestand %s is toegankelijk voor andere gebruikers of is niet van root of van u: beperk het met chmod 600 %s en probeer opnieuw.
ru|pass_file_perm|Файл пароля %s доступен другим пользователям либо принадлежит не root и не вам: ограничьте доступ командой chmod 600 %s и повторите попытку.
zh|pass_file_perm|密码文件 %s 可被其他用户访问，或既不属于 root 也不属于您：请用 chmod 600 %s 限制权限后重试。
ar|pass_file_perm|ملف كلمة المرور %s متاح لمستخدمين آخرين أو لا يخص root ولا يخصك: قيّد صلاحياته باستخدام chmod 600 %s ثم أعد المحاولة.
en|pass_err_short|Admin password refused: at least %s characters are required.
fr|pass_err_short|Mot de passe admin refusé : %s caractères au minimum.
de|pass_err_short|Admin-Passwort abgelehnt: mindestens %s Zeichen erforderlich.
es|pass_err_short|Contraseña del administrador rechazada: se requieren al menos %s caracteres.
it|pass_err_short|Password dell'amministratore rifiutata: servono almeno %s caratteri.
pt|pass_err_short|Senha do administrador recusada: são necessários pelo menos %s carateres.
nl|pass_err_short|Beheerderswachtwoord geweigerd: minstens %s tekens vereist.
ru|pass_err_short|Пароль администратора отклонён: нужно не менее %s символов.
zh|pass_err_short|管理员密码被拒绝：至少需要 %s 个字符。
ar|pass_err_short|رُفضت كلمة مرور المسؤول: يلزم %s أحرف على الأقل.
en|pass_err_long|Admin password refused: 256 characters at most.
fr|pass_err_long|Mot de passe admin refusé : 256 caractères au maximum.
de|pass_err_long|Admin-Passwort abgelehnt: höchstens 256 Zeichen.
es|pass_err_long|Contraseña del administrador rechazada: 256 caracteres como máximo.
it|pass_err_long|Password dell'amministratore rifiutata: al massimo 256 caratteri.
pt|pass_err_long|Senha do administrador recusada: no máximo 256 carateres.
nl|pass_err_long|Beheerderswachtwoord geweigerd: maximaal 256 tekens.
ru|pass_err_long|Пароль администратора отклонён: не более 256 символов.
zh|pass_err_long|管理员密码被拒绝：最多 256 个字符。
ar|pass_err_long|رُفضت كلمة مرور المسؤول: 256 حرفًا كحد أقصى.
en|pass_err_chars|Admin password refused: it must contain at least one letter and one digit.
fr|pass_err_chars|Mot de passe admin refusé : il doit contenir au moins une lettre et un chiffre.
de|pass_err_chars|Admin-Passwort abgelehnt: es muss mindestens einen Buchstaben und eine Ziffer enthalten.
es|pass_err_chars|Contraseña del administrador rechazada: debe contener al menos una letra y un dígito.
it|pass_err_chars|Password dell'amministratore rifiutata: deve contenere almeno una lettera e una cifra.
pt|pass_err_chars|Senha do administrador recusada: tem de conter pelo menos uma letra e um dígito.
nl|pass_err_chars|Beheerderswachtwoord geweigerd: het moet minstens één letter en één cijfer bevatten.
ru|pass_err_chars|Пароль администратора отклонён: он должен содержать хотя бы одну букву и одну цифру.
zh|pass_err_chars|管理员密码被拒绝：必须至少包含一个字母和一个数字。
ar|pass_err_chars|رُفضت كلمة مرور المسؤول: يجب أن تحتوي على حرف واحد ورقم واحد على الأقل.
en|pass_err_user|Admin password refused: it must not be identical to the username.
fr|pass_err_user|Mot de passe admin refusé : il ne doit pas être identique au nom d'utilisateur.
de|pass_err_user|Admin-Passwort abgelehnt: es darf nicht mit dem Benutzernamen identisch sein.
es|pass_err_user|Contraseña del administrador rechazada: no debe ser idéntica al nombre de usuario.
it|pass_err_user|Password dell'amministratore rifiutata: non deve coincidere con il nome utente.
pt|pass_err_user|Senha do administrador recusada: não pode ser igual ao nome de utilizador.
nl|pass_err_user|Beheerderswachtwoord geweigerd: het mag niet gelijk zijn aan de gebruikersnaam.
ru|pass_err_user|Пароль администратора отклонён: он не должен совпадать с именем пользователя.
zh|pass_err_user|管理员密码被拒绝：不能与用户名相同。
ar|pass_err_user|رُفضت كلمة مرور المسؤول: يجب ألا تطابق اسم المستخدم.
en|pass_err_common|Admin password refused: this password is too common.
fr|pass_err_common|Mot de passe admin refusé : ce mot de passe est trop courant.
de|pass_err_common|Admin-Passwort abgelehnt: dieses Passwort ist zu gebräuchlich.
es|pass_err_common|Contraseña del administrador rechazada: esta contraseña es demasiado común.
it|pass_err_common|Password dell'amministratore rifiutata: questa password è troppo comune.
pt|pass_err_common|Senha do administrador recusada: esta senha é demasiado comum.
nl|pass_err_common|Beheerderswachtwoord geweigerd: dit wachtwoord is te gebruikelijk.
ru|pass_err_common|Пароль администратора отклонён: этот пароль слишком распространён.
zh|pass_err_common|管理员密码被拒绝：该密码过于常见。
ar|pass_err_common|رُفضت كلمة مرور المسؤول: كلمة المرور هذه شائعة جدًا.
en|pass_update_ignored|Existing installation: the admin password is left unchanged (the password you provided is ignored; to change it: toutpanel passwd).
fr|pass_update_ignored|Installation existante : le mot de passe admin reste inchangé (le mot de passe fourni est ignoré ; pour le changer : toutpanel passwd).
de|pass_update_ignored|Bestehende Installation: Das Admin-Passwort bleibt unverändert (das angegebene Passwort wird ignoriert; zum Ändern: toutpanel passwd).
es|pass_update_ignored|Instalación existente: la contraseña del administrador no cambia (se ignora la contraseña indicada; para cambiarla: toutpanel passwd).
it|pass_update_ignored|Installazione esistente: la password dell'amministratore resta invariata (la password indicata viene ignorata; per cambiarla: toutpanel passwd).
pt|pass_update_ignored|Instalação existente: a senha do administrador permanece inalterada (a senha indicada é ignorada; para a alterar: toutpanel passwd).
nl|pass_update_ignored|Bestaande installatie: het beheerderswachtwoord blijft ongewijzigd (het opgegeven wachtwoord wordt genegeerd; wijzigen kan met toutpanel passwd).
ru|pass_update_ignored|Существующая установка: пароль администратора остаётся прежним (указанный пароль игнорируется; чтобы изменить его: toutpanel passwd).
zh|pass_update_ignored|已有安装：管理员密码保持不变（忽略您提供的密码；如需修改：toutpanel passwd）。
ar|pass_update_ignored|تثبيت موجود: تبقى كلمة مرور المسؤول دون تغيير (تُتجاهل كلمة المرور المحدّدة؛ لتغييرها: toutpanel passwd).
en|pass_set_by_you|(the password you provided, not displayed)
fr|pass_set_by_you|(celui que vous avez fourni, non affiché)
de|pass_set_by_you|(das von Ihnen angegebene, nicht angezeigt)
es|pass_set_by_you|(la que usted indicó, no se muestra)
it|pass_set_by_you|(quella indicata da voi, non mostrata)
pt|pass_set_by_you|(a que indicou, não apresentada)
nl|pass_set_by_you|(het door u opgegeven wachtwoord, niet getoond)
ru|pass_set_by_you|(указанный вами пароль, не отображается)
zh|pass_set_by_you|（您提供的密码，不显示）
ar|pass_set_by_you|(كلمة المرور التي حدّدتها، غير معروضة)
en|pass_q_title|Admin password:
fr|pass_q_title|Mot de passe de l'administrateur :
de|pass_q_title|Administrator-Passwort:
es|pass_q_title|Contraseña del administrador:
it|pass_q_title|Password dell'amministratore:
pt|pass_q_title|Senha do administrador:
nl|pass_q_title|Beheerderswachtwoord:
ru|pass_q_title|Пароль администратора:
zh|pass_q_title|管理员密码：
ar|pass_q_title|كلمة مرور المسؤول:
en|pass_q_generate|generate one automatically (recommended)
fr|pass_q_generate|générer automatiquement (recommandé)
de|pass_q_generate|automatisch erzeugen (empfohlen)
es|pass_q_generate|generarla automáticamente (recomendado)
it|pass_q_generate|generarla automaticamente (consigliato)
pt|pass_q_generate|gerar automaticamente (recomendado)
nl|pass_q_generate|automatisch genereren (aanbevolen)
ru|pass_q_generate|сгенерировать автоматически (рекомендуется)
zh|pass_q_generate|自动生成（推荐）
ar|pass_q_generate|إنشاؤها تلقائيًا (موصى به)
en|pass_q_type|enter it myself (hidden input, with confirmation)
fr|pass_q_type|la saisir (sans écho, avec confirmation)
de|pass_q_type|selbst eingeben (Eingabe verborgen, mit Bestätigung)
es|pass_q_type|introducirla yo (entrada oculta, con confirmación)
it|pass_q_type|inserirla io (input nascosto, con conferma)
pt|pass_q_type|introduzi-la eu (entrada oculta, com confirmação)
nl|pass_q_type|zelf invoeren (invoer verborgen, met bevestiging)
ru|pass_q_type|ввести самостоятельно (ввод скрыт, с подтверждением)
zh|pass_q_type|自行输入（输入不回显，需确认）
ar|pass_q_type|إدخالها بنفسي (الإدخال مخفي، مع تأكيد)
en|pass_prompt1|Admin password (input hidden): 
fr|pass_prompt1|Mot de passe admin (saisie masquée) : 
de|pass_prompt1|Admin-Passwort (Eingabe verborgen): 
es|pass_prompt1|Contraseña del administrador (entrada oculta): 
it|pass_prompt1|Password dell'amministratore (input nascosto): 
pt|pass_prompt1|Senha do administrador (entrada oculta): 
nl|pass_prompt1|Beheerderswachtwoord (invoer verborgen): 
ru|pass_prompt1|Пароль администратора (ввод скрыт): 
zh|pass_prompt1|管理员密码（输入不回显）：
ar|pass_prompt1|كلمة مرور المسؤول (الإدخال مخفي): 
en|pass_prompt2|Confirm the password (input hidden): 
fr|pass_prompt2|Confirmez le mot de passe (saisie masquée) : 
de|pass_prompt2|Passwort bestätigen (Eingabe verborgen): 
es|pass_prompt2|Confirme la contraseña (entrada oculta): 
it|pass_prompt2|Confermare la password (input nascosto): 
pt|pass_prompt2|Confirme a senha (entrada oculta): 
nl|pass_prompt2|Bevestig het wachtwoord (invoer verborgen): 
ru|pass_prompt2|Подтвердите пароль (ввод скрыт): 
zh|pass_prompt2|确认密码（输入不回显）：
ar|pass_prompt2|أكّد كلمة المرور (الإدخال مخفي): 
en|pass_mismatch|The two passwords do not match: try again.
fr|pass_mismatch|Les deux mots de passe ne correspondent pas : recommencez.
de|pass_mismatch|Die beiden Passwörter stimmen nicht überein: bitte erneut versuchen.
es|pass_mismatch|Las dos contraseñas no coinciden: inténtelo de nuevo.
it|pass_mismatch|Le due password non coincidono: riprovare.
pt|pass_mismatch|As duas senhas não coincidem: tente novamente.
nl|pass_mismatch|De twee wachtwoorden komen niet overeen: probeer opnieuw.
ru|pass_mismatch|Пароли не совпадают: повторите ввод.
zh|pass_mismatch|两次输入的密码不一致：请重试。
ar|pass_mismatch|كلمتا المرور غير متطابقتين: أعد المحاولة.
en|pass_prompt_failed|No valid password entered: installation cancelled, nothing was modified. Run it again, or provide the password with TOUTPANEL_PASSWORD or a file.
fr|pass_prompt_failed|Aucun mot de passe valable saisi : installation annulée, rien n'a été modifié. Relancez-la, ou fournissez le mot de passe par TOUTPANEL_PASSWORD ou un fichier.
de|pass_prompt_failed|Kein gültiges Passwort eingegeben: Installation abgebrochen, nichts wurde geändert. Starten Sie erneut oder geben Sie das Passwort über TOUTPANEL_PASSWORD oder eine Datei an.
es|pass_prompt_failed|No se introdujo ninguna contraseña válida: instalación cancelada, no se modificó nada. Vuelva a ejecutarla o indique la contraseña con TOUTPANEL_PASSWORD o un archivo.
it|pass_prompt_failed|Nessuna password valida inserita: installazione annullata, nulla è stato modificato. Rieseguire oppure indicare la password con TOUTPANEL_PASSWORD o un file.
pt|pass_prompt_failed|Nenhuma senha válida introduzida: instalação cancelada, nada foi modificado. Execute novamente ou indique a senha com TOUTPANEL_PASSWORD ou um ficheiro.
nl|pass_prompt_failed|Geen geldig wachtwoord ingevoerd: installatie geannuleerd, er is niets gewijzigd. Start opnieuw of geef het wachtwoord op via TOUTPANEL_PASSWORD of een bestand.
ru|pass_prompt_failed|Допустимый пароль не введён: установка отменена, ничего не изменено. Запустите её снова или передайте пароль через TOUTPANEL_PASSWORD либо файл.
zh|pass_prompt_failed|未输入有效密码：安装已取消，未做任何修改。请重新运行，或通过 TOUTPANEL_PASSWORD 或文件提供密码。
ar|pass_prompt_failed|لم تُدخل كلمة مرور صالحة: أُلغي التثبيت ولم يُعدَّل شيء. أعد التشغيل أو مرّر كلمة المرور عبر TOUTPANEL_PASSWORD أو ملف.
en|pass_refused_by_panel|The panel refused the provided password (its password policy): a random password was generated instead and is shown below; change it with toutpanel passwd.
fr|pass_refused_by_panel|Le panel a refusé le mot de passe fourni (sa politique de mots de passe) : un mot de passe aléatoire a été généré à la place et s'affiche plus bas ; changez-le avec toutpanel passwd.
de|pass_refused_by_panel|Das Panel hat das angegebene Passwort abgelehnt (seine Passwortrichtlinie): stattdessen wurde ein zufälliges Passwort erzeugt, das unten angezeigt wird; ändern Sie es mit toutpanel passwd.
es|pass_refused_by_panel|El panel rechazó la contraseña indicada (su política de contraseñas): se generó en su lugar una contraseña aleatoria que se muestra más abajo; cámbiela con toutpanel passwd.
it|pass_refused_by_panel|Il pannello ha rifiutato la password indicata (la sua politica delle password): ne è stata generata una casuale, mostrata più sotto; cambiarla con toutpanel passwd.
pt|pass_refused_by_panel|O painel recusou a senha indicada (a sua política de senhas): foi gerada uma senha aleatória, apresentada abaixo; altere-a com toutpanel passwd.
nl|pass_refused_by_panel|Het paneel heeft het opgegeven wachtwoord geweigerd (zijn wachtwoordbeleid): in plaats daarvan is een willekeurig wachtwoord gegenereerd, hieronder getoond; wijzig het met toutpanel passwd.
ru|pass_refused_by_panel|Панель отклонила указанный пароль (её политика паролей): вместо него создан случайный пароль, он показан ниже; измените его командой toutpanel passwd.
zh|pass_refused_by_panel|面板拒绝了所提供的密码（其密码策略）：已改为生成随机密码，显示在下方；请用 toutpanel passwd 修改。
ar|pass_refused_by_panel|رفضت اللوحة كلمة المرور المحدّدة (سياسة كلمات المرور فيها): أُنشئت بدلًا منها كلمة مرور عشوائية تظهر أدناه؛ غيّرها باستخدام toutpanel passwd.
en|pass_src_generated|generated randomly (shown at the end)
fr|pass_src_generated|générée aléatoirement (affichée à la fin)
de|pass_src_generated|zufällig erzeugt (am Ende angezeigt)
es|pass_src_generated|generada aleatoriamente (se muestra al final)
it|pass_src_generated|generata casualmente (mostrata alla fine)
pt|pass_src_generated|gerada aleatoriamente (apresentada no fim)
nl|pass_src_generated|willekeurig gegenereerd (aan het eind getoond)
ru|pass_src_generated|создаётся случайно (показывается в конце)
zh|pass_src_generated|随机生成（结束时显示）
ar|pass_src_generated|تُنشأ عشوائيًا (تُعرض في النهاية)
en|pass_src_arg|taken from --password (visible in ps: not recommended)
fr|pass_src_arg|reprise de --password (visible dans ps : déconseillé)
de|pass_src_arg|aus --password übernommen (in ps sichtbar: nicht empfohlen)
es|pass_src_arg|tomada de --password (visible en ps: no recomendado)
it|pass_src_arg|presa da --password (visibile in ps: sconsigliato)
pt|pass_src_arg|obtida de --password (visível em ps: não recomendado)
nl|pass_src_arg|overgenomen uit --password (zichtbaar in ps: niet aanbevolen)
ru|pass_src_arg|берётся из --password (видна в ps: не рекомендуется)
zh|pass_src_arg|取自 --password（在 ps 中可见：不推荐）
ar|pass_src_arg|تؤخذ من --password (ظاهرة في ps: غير موصى به)
en|pass_src_env|taken from the variable TOUTPANEL_PASSWORD
fr|pass_src_env|reprise de la variable TOUTPANEL_PASSWORD
de|pass_src_env|aus der Variable TOUTPANEL_PASSWORD übernommen
es|pass_src_env|tomada de la variable TOUTPANEL_PASSWORD
it|pass_src_env|presa dalla variabile TOUTPANEL_PASSWORD
pt|pass_src_env|obtida da variável TOUTPANEL_PASSWORD
nl|pass_src_env|overgenomen uit de variabele TOUTPANEL_PASSWORD
ru|pass_src_env|берётся из переменной TOUTPANEL_PASSWORD
zh|pass_src_env|取自变量 TOUTPANEL_PASSWORD
ar|pass_src_env|تؤخذ من المتغير TOUTPANEL_PASSWORD
en|pass_src_file|read from --password-file
fr|pass_src_file|lue dans --password-file
de|pass_src_file|aus --password-file gelesen
es|pass_src_file|leída de --password-file
it|pass_src_file|letta da --password-file
pt|pass_src_file|lida de --password-file
nl|pass_src_file|gelezen uit --password-file
ru|pass_src_file|читается из --password-file
zh|pass_src_file|从 --password-file 读取
ar|pass_src_file|تُقرأ من --password-file
en|pass_src_stdin|read from standard input (--password-stdin)
fr|pass_src_stdin|lue sur l'entrée standard (--password-stdin)
de|pass_src_stdin|von der Standardeingabe gelesen (--password-stdin)
es|pass_src_stdin|leída de la entrada estándar (--password-stdin)
it|pass_src_stdin|letta dallo standard input (--password-stdin)
pt|pass_src_stdin|lida da entrada padrão (--password-stdin)
nl|pass_src_stdin|gelezen van de standaardinvoer (--password-stdin)
ru|pass_src_stdin|читается со стандартного ввода (--password-stdin)
zh|pass_src_stdin|从标准输入读取（--password-stdin）
ar|pass_src_stdin|تُقرأ من الإدخال القياسي (--password-stdin)
en|pass_src_ask|asked during the installation (random or typed)
fr|pass_src_ask|demandée pendant l'installation (aléatoire ou saisie)
de|pass_src_ask|wird bei der Installation abgefragt (zufällig oder eingegeben)
es|pass_src_ask|se pregunta durante la instalación (aleatoria o introducida)
it|pass_src_ask|richiesta durante l'installazione (casuale o digitata)
pt|pass_src_ask|pedida durante a instalação (aleatória ou introduzida)
nl|pass_src_ask|wordt tijdens de installatie gevraagd (willekeurig of ingetypt)
ru|pass_src_ask|запрашивается при установке (случайный или введённый)
zh|pass_src_ask|安装时询问（随机生成或手动输入）
ar|pass_src_ask|تُطلب أثناء التثبيت (عشوائية أو مُدخلة يدويًا)
en|pass_src_kept|unchanged (existing account kept)
fr|pass_src_kept|inchangé (compte existant conservé)
de|pass_src_kept|unverändert (bestehendes Konto bleibt)
es|pass_src_kept|sin cambios (se conserva la cuenta existente)
it|pass_src_kept|invariata (account esistente conservato)
pt|pass_src_kept|inalterada (conta existente mantida)
nl|pass_src_kept|ongewijzigd (bestaand account blijft)
ru|pass_src_kept|без изменений (существующая учётная запись сохраняется)
zh|pass_src_kept|保持不变（保留现有账户）
ar|pass_src_kept|دون تغيير (يُحتفظ بالحساب الحالي)
en|h_password_secure_win|admin password as a SecureString, e.g. (Read-Host -AsSecureString); never visible in the process list
fr|h_password_secure_win|mot de passe admin sous forme de SecureString, p. ex. (Read-Host -AsSecureString) ; jamais visible dans la liste des processus
de|h_password_secure_win|Admin-Passwort als SecureString, z. B. (Read-Host -AsSecureString); in der Prozessliste nie sichtbar
es|h_password_secure_win|contraseña del administrador como SecureString, p. ej. (Read-Host -AsSecureString); nunca visible en la lista de procesos
it|h_password_secure_win|password dell'amministratore come SecureString, ad es. (Read-Host -AsSecureString); mai visibile nell'elenco dei processi
pt|h_password_secure_win|senha do administrador como SecureString, p. ex. (Read-Host -AsSecureString); nunca visível na lista de processos
nl|h_password_secure_win|beheerderswachtwoord als SecureString, bijv. (Read-Host -AsSecureString); nooit zichtbaar in de proceslijst
ru|h_password_secure_win|пароль администратора в виде SecureString, например (Read-Host -AsSecureString); никогда не виден в списке процессов
zh|h_password_secure_win|SecureString 形式的管理员密码，例如 (Read-Host -AsSecureString)；绝不会出现在进程列表中
ar|h_password_secure_win|كلمة مرور المسؤول بصيغة SecureString، مثل (Read-Host -AsSecureString)؛ لا تظهر أبدًا في قائمة العمليات
en|setup_note_given|This link (24 h, single use) lets you change the panel address, the username and the password.
fr|setup_note_given|Ce lien (24 h, usage unique) permet de changer l'adresse du panel, l'utilisateur et le mot de passe.
de|setup_note_given|Mit diesem Link (24 h, einmalig) können Sie Panel-Adresse, Benutzernamen und Passwort ändern.
es|setup_note_given|Este enlace (24 h, un solo uso) permite cambiar la dirección del panel, el usuario y la contraseña.
it|setup_note_given|Questo link (24 h, uso singolo) consente di modificare l'indirizzo del pannello, il nome utente e la password.
pt|setup_note_given|Esta ligação (24 h, utilização única) permite alterar o endereço do painel, o utilizador e a senha.
nl|setup_note_given|Met deze link (24 u, eenmalig) kunt u het adres van het paneel, de gebruikersnaam en het wachtwoord wijzigen.
ru|setup_note_given|Эта ссылка (24 ч, однократная) позволяет изменить адрес панели, имя пользователя и пароль.
zh|setup_note_given|通过此链接（24 小时内一次性有效）可修改面板地址、用户名和密码。
ar|setup_note_given|يتيح هذا الرابط (24 ساعة، استخدام واحد) تغيير عنوان اللوحة واسم المستخدم وكلمة المرور.
en|h_result_json|write a machine-readable result (JSON: panel version and URLs, WAF link state, server id) to FILE, absolute path, mode 600; never a password or a token
fr|h_result_json|écrit un résultat lisible par machine (JSON : version et URL du panel, état de la liaison WAF, identifiant de serveur) dans FILE, chemin absolu, mode 600 ; jamais de mot de passe ni de jeton
de|h_result_json|schreibt ein maschinenlesbares Ergebnis (JSON: Panel-Version und URLs, WAF-Verbindungsstatus, Server-ID) nach FILE, absoluter Pfad, Modus 600; niemals ein Passwort oder Token
es|h_result_json|escribe un resultado legible por máquina (JSON: versión y URL del panel, estado del enlace WAF, id del servidor) en FILE, ruta absoluta, modo 600; nunca una contraseña ni un token
it|h_result_json|scrive un risultato leggibile da macchina (JSON: versione e URL del pannello, stato del collegamento WAF, id del server) in FILE, percorso assoluto, modo 600; mai una password né un token
pt|h_result_json|escreve um resultado legível por máquina (JSON: versão e URL do painel, estado da ligação WAF, id do servidor) em FILE, caminho absoluto, modo 600; nunca uma palavra-passe nem um token
nl|h_result_json|schrijft een machineleesbaar resultaat (JSON: paneelversie en URL's, WAF-koppelstatus, server-id) naar FILE, absoluut pad, modus 600; nooit een wachtwoord of token
ru|h_result_json|записывает результат в машиночитаемом виде (JSON: версия и URL панели, состояние связи с WAF, идентификатор сервера) в FILE, абсолютный путь, режим 600; никогда пароль или токен
zh|h_result_json|将机器可读的结果（JSON：面板版本和 URL、WAF 连接状态、服务器 ID）写入 FILE，绝对路径，权限 600；绝不包含密码或令牌
ar|h_result_json|يكتب نتيجة قابلة للقراءة آليًا (JSON: إصدار اللوحة وعناوينها، حالة ربط WAF، معرّف الخادم) في FILE، مسار مطلق، الصلاحيات 600؛ ولا يتضمن أبدًا كلمة مرور أو رمزًا
en|result_json_bad|--result-json expects an absolute file path: %s
fr|result_json_bad|--result-json attend un chemin de fichier absolu : %s
de|result_json_bad|--result-json erwartet einen absoluten Dateipfad: %s
es|result_json_bad|--result-json espera una ruta de archivo absoluta: %s
it|result_json_bad|--result-json richiede un percorso di file assoluto: %s
pt|result_json_bad|--result-json espera um caminho de ficheiro absoluto: %s
nl|result_json_bad|--result-json verwacht een absoluut bestandspad: %s
ru|result_json_bad|--result-json требует абсолютный путь к файлу: %s
zh|result_json_bad|--result-json 需要文件的绝对路径：%s
ar|result_json_bad|يتطلب --result-json مسار ملف مطلقًا: %s
en|result_json_saved|Machine-readable result written to %s
fr|result_json_saved|Résultat lisible par machine écrit dans %s
de|result_json_saved|Maschinenlesbares Ergebnis geschrieben nach %s
es|result_json_saved|Resultado legible por máquina escrito en %s
it|result_json_saved|Risultato leggibile da macchina scritto in %s
pt|result_json_saved|Resultado legível por máquina escrito em %s
nl|result_json_saved|Machineleesbaar resultaat geschreven naar %s
ru|result_json_saved|Машиночитаемый результат записан в %s
zh|result_json_saved|机器可读的结果已写入 %s
ar|result_json_saved|تمت كتابة النتيجة القابلة للقراءة آليًا في %s
en|result_json_failed|Could not write the machine-readable result to %s (the installation is not affected).
fr|result_json_failed|Impossible d'écrire le résultat lisible par machine dans %s (l'installation n'est pas affectée).
de|result_json_failed|Das maschinenlesbare Ergebnis konnte nicht nach %s geschrieben werden (die Installation ist nicht betroffen).
es|result_json_failed|No se pudo escribir el resultado legible por máquina en %s (la instalación no se ve afectada).
it|result_json_failed|Impossibile scrivere il risultato leggibile da macchina in %s (l'installazione non è interessata).
pt|result_json_failed|Não foi possível escrever o resultado legível por máquina em %s (a instalação não é afetada).
nl|result_json_failed|Het machineleesbare resultaat kon niet naar %s worden geschreven (de installatie blijft onaangetast).
ru|result_json_failed|Не удалось записать машиночитаемый результат в %s (установка не затронута).
zh|result_json_failed|无法将机器可读的结果写入 %s（不影响安装）。
ar|result_json_failed|تعذّرت كتابة النتيجة القابلة للقراءة آليًا في %s (لا يتأثر التثبيت).
# END CATALOG
TP_CATALOG
}
# msg CLÉ [args…] : texte traduit, sans saut de ligne final (clé inconnue : la clé elle-même)
msg() {
  local key="$1" fmt; shift
  fmt="${_MSG[$key]-$key}"
  # shellcheck disable=SC2059
  printf -- "$fmt" "$@"
}
say() { msg "$@"; printf '\n'; }

_on_err() { printf '\n\033[1;31m[ToutPanel] %s\033[0m\n%s\n' "$(msg err_failed "$1" "$2" "$3")" "$(msg err_retry)" >&2; }
trap 'rc=$?; _on_err "$LINENO" "$rc" "$BASH_COMMAND"' ERR

log()  { printf '\033[1;32m[ToutPanel]\033[0m %s\n' "$(msg "$@")"; }
warn() { printf '\033[1;33m[ToutPanel]\033[0m %s\n' "$(msg "$@")"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$(msg "$@")"; }
C0=$'\033[0m'; CB=$'\033[1;34m'; CC=$'\033[1;36m'; CG=$'\033[1;32m'; CY=$'\033[1;33m'; CD=$'\033[2m'; CW=$'\033[1m'

# --- Choix de la langue : option > TOUTPANEL_LANG > INSTALLER_LANG > langue du système > anglais ---------------------
LANG_OPT=""
_prev=""
for _a in "$@"; do   # pré-lecture des options : la langue doit être connue avant le premier message (même --help)
  if [[ -n "$_prev" ]]; then [[ "$_prev" == "--lang" ]] && LANG_OPT="$_a"; _prev=""; continue; fi
  case "$_a" in
    --lang) _prev="--lang";;
    --lang=*) LANG_OPT="${_a#--lang=}";;
    --en|--fr|--de|--es|--it|--pt|--nl|--ru|--zh|--ar) LANG_OPT="${_a#--}";;
    --port|--https-port|--version|--home|--stack|--waf|--master|--username|--password|--entrance|--source|--branch|--channel) _prev="$_a";;
    --waf-console|--waf-origin-ip|--waf-origin-addr|--waf-cert-mode|--waf-ssl|--waf-server-id|--waf-fingerprint|--waf-token-file|--waf-token|--password-file|--result-json) _prev="$_a";;
    --firewall|--firewall-engine|--profile|--web|--php|--php-default|--php-ext|--db|--accel|--ftp|--dns|--security|--runtime|--tools|--install-mode|--roles|--stack-file) _prev="$_a";;
  esac
done
LANG_SRC="default"
LANG_BAD=""
# fr, FR, fr_FR.UTF-8, fr-FR → fr ; renvoie 1 si la langue n'est pas prise en charge
_pick_lang() {
  local v="${1,,}"
  v="${v%%[_.@-]*}"
  if [[ -n "$v" && " $SUPPORTED_LANGS " == *" $v "* ]]; then UI_LANG="$v"; LANG_SRC="$2"; return 0; fi
  return 1
}
if [[ -n "$LANG_OPT" ]]; then _pick_lang "$LANG_OPT" option || LANG_BAD="$LANG_OPT"
elif [[ -n "${TOUTPANEL_LANG:-}" ]]; then _pick_lang "$TOUTPANEL_LANG" env || LANG_BAD="$TOUTPANEL_LANG"
elif [[ -n "$INSTALLER_LANG" ]]; then _pick_lang "$INSTALLER_LANG" file || LANG_BAD="$INSTALLER_LANG"
else _pick_lang "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" system || true
fi
_load_catalog
[[ -n "$LANG_BAD" ]] && warn lang_unknown "$LANG_BAD" "$SUPPORTED_LANGS"

usage() {
  local o='  %-28s %s\n'
  printf 'ToutPanel — install.sh\n\n'
  say usage_title
  printf '  curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash\n'
  printf '  curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --lang fr\n'
  printf '  sudo bash install.sh [options]\n\n'
  say options_title
  printf '\n  %s\n' "$(msg hs_account)"
  printf "$o" "--username NAME" "$(msg h_username)"
  printf "$o" "--password PASS" "$(msg h_password)"
  printf "$o" "(TOUTPANEL_PASSWORD)" "$(msg h_password_env)"
  printf "$o" "--password-file FILE" "$(msg h_password_file)"
  printf "$o" "--password-stdin" "$(msg h_password_stdin)"
  printf "$o" "--entrance /PATH" "$(msg h_entrance)"
  printf '\n  %s\n' "$(msg hs_network)"
  printf "$o" "--port N" "$(msg h_port)"
  printf "$o" "--https-port N" "$(msg h_https_port)"
  printf "$o" "--random-port" "$(msg h_random_port)"
  printf "$o" "--node" "$(msg h_node)"
  printf "$o" "--master URL" "$(msg h_master)"
  printf '\n  %s\n' "$(msg hs_dirs)"
  printf "$o" "--home DIR" "$(msg h_home_linux "$DEFAULT_HOME" "$LEGACY_HOME")"
  printf "$o" "--source DIR" "$(msg h_source)"
  printf '\n  %s\n' "$(msg hs_version)"
  printf "$o" "--version X.Y.Z" "$(msg h_version)"
  printf "$o" "--list-versions" "$(msg h_list_versions)"
  printf "$o" "--branch NAME" "$(msg h_branch)"
  printf "$o" "--channel stable|dev" "$(msg h_channel)"
  printf "$o" "--update" "$(msg h_update)"
  printf "$o" "--reinstall" "$(msg h_reinstall)"
  printf "$o" "--uninstall" "$(msg h_uninstall)"
  printf '\n  %s\n' "$(msg hs_stack)"
  printf "$o" "" "$(msg h_stack_note)"
  printf "$o" "--profile NAME" "$(msg h_profile)"
  printf "$o" "--web SERVER" "$(msg h_web)"
  printf "$o" "--php VERSIONS|none" "$(msg h_php)"
  printf "$o" "--php-default VERSION" "$(msg h_php_default)"
  printf "$o" "--php-ext SET" "$(msg h_php_ext)"
  printf "$o" "--db ENGINE[:VER]|none" "$(msg h_db)"
  printf "$o" "--redis" "$(msg h_redis)"
  printf "$o" "--accel LIST" "$(msg h_accel)"
  printf "$o" "--ftp ENGINE" "$(msg h_ftp)"
  printf "$o" "--mail [ENGINE]" "$(msg h_mail_engine)"
  printf "$o" "" "$(msg h_mail)"
  printf "$o" "--dns ENGINE" "$(msg h_dns)"
  printf "$o" "--security LIST" "$(msg h_security)"
  printf "$o" "--runtime LIST" "$(msg h_runtime)"
  printf "$o" "--tools LIST" "$(msg h_tools)"
  printf "$o" "--install-mode MODE" "$(msg h_install_mode)"
  printf "$o" "--roles LIST" "$(msg h_roles)"
  printf "$o" "--stack-file FILE" "$(msg h_stack_file)"
  printf "$o" "--no-tuning" "$(msg h_no_tuning)"
  printf "$o" "--accept-litespeed-license" "$(msg h_accept_litespeed_license)"
  printf "$o" "--postgres" "$(msg h_postgres)"
  printf "$o" "--stack full|minimal|none" "$(msg h_stack_old)"
  printf "$o" "    full" "$(msg h_stack_full)"
  printf "$o" "    minimal" "Nginx + PHP-FPM + Certbot"
  printf "$o" "    none" "$(msg h_stack_none)"
  printf '\n  %s\n' "$(msg hs_firewall)"
  printf "$o" "--firewall on|off|ask" "$(msg h_firewall)"
  printf "$o" "--firewall-engine ENGINE" "$(msg h_firewall_engine)"
  printf "$o" "" "$(msg h_firewall_note)"
  printf '\n  %s\n' "$(msg hs_waf)"
  printf '  %s\n' "--waf toutwaf|bunkerweb|safeline|none"
  printf "$o" "" "$(msg h_waf)"
  printf "$o" "" "$(msg h_waf2)"
  printf "$o" "" "$(msg h_waf_none)"
  printf '  %s\n' "$(msg h_waf_section)"
  printf "$o" "--waf-console URL" "$(msg h_waf_console)"
  printf "$o" "--waf-origin-ip IP" "$(msg h_waf_origin_ip)"
  printf "$o" "--waf-origin-addr IP" "$(msg h_waf_origin_addr)"
  printf "$o" "--waf-restrict" "$(msg h_waf_restrict)"
  printf "$o" "--waf-cert-mode MODE" "$(msg h_waf_cert_mode)"
  printf "$o" "--waf-ssl MODE" "$(msg h_waf_ssl)"
  printf "$o" "--waf-server-id ID" "$(msg h_waf_server_id)"
  printf "$o" "--waf-fingerprint FP" "$(msg h_waf_fingerprint)"
  printf "$o" "--waf-trust-first-use" "$(msg h_waf_trust)"
  printf "$o" "--waf-strict" "$(msg h_waf_strict)"
  printf "$o" "(TOUTPANEL_WAF_TOKEN)" "$(msg h_waf_token_env)"
  printf "$o" "--waf-token-file FILE" "$(msg h_waf_token_file)"
  printf "$o" "--waf-token-stdin" "$(msg h_waf_token_stdin)"
  printf '\n  %s\n' "$(msg hs_misc)"
  printf "$o" "--yes, -y" "$(msg h_yes)"
  printf "$o" "--dry-run" "$(msg h_dry_run)"
  printf "$o" "--result-json FILE" "$(msg h_result_json)"
  printf "$o" "--lang CODE" "$(msg h_lang)"
  printf '  %s\n' "--en --fr --de --es --it --pt --nl --ru --zh --ar"
  printf "$o" "" "$(msg h_lang_short)"
  printf "$o" "-h, --help" "$(msg h_help)"
  printf '\n'
  say help_menu
  say help_lang "LC_ALL, LC_MESSAGES, LANG"
  say help_env "TOUTPANEL_LANG, TOUTPANEL_HOME, TOUTPANEL_REPO, TOUTPANEL_BRANCH, TOUTPANEL_CHANNEL, TOUTPANEL_VERSION"
  say help_env_opts
  say help_env_waf "TOUTPANEL_WAF_TOKEN, TOUTPANEL_WAF_URL, TOUTPANEL_WAF_PIN, TOUTPANEL_WAF_SERVER_ID"
  say help_wheels
}

PORT=8888          # port HTTP du panel
HTTPS_PORT=8443    # port HTTPS du panel (le panel écoute en HTTP ET en HTTPS ; mode nœud : HTTPS seul sur PORT)
HTTP_ON=1          # écoute HTTP active (relue dans les réglages du panel avant le pare-feu et le récapitulatif)
HTTPS_ON=1         # écoute HTTPS active
RANDOM_PORT=0
# Répertoire du panel : /var/toutpanel par défaut ; une installation existante dans l'ancien défaut /www/toutpanel est conservée telle quelle
# (voir « Répertoire du panel » plus bas : détection de l'installation existante). --home DIR / TOUTPANEL_HOME imposent un répertoire.
DEFAULT_HOME="/var/toutpanel"
LEGACY_HOME="/www/toutpanel"
HOME_DIR="${TOUTPANEL_HOME:-}"
HOME_SET=0; [[ -n "$HOME_DIR" ]] && HOME_SET=1
HOME_LEGACY=0            # 1 : installation existante conservée dans l'ancien défaut /www/toutpanel, 2 : dans un autre répertoire détecté (sans déplacement)
HOME_OTHER=""            # une installation existante a été détectée ailleurs que dans --home (avertissement)
FS_ROOT="${TOUTPANEL_FS_ROOT:-}"   # caché (tests) : préfixe des chemins lus pour détecter une installation existante
STACK="full"
STACK_SET=0
# Pile du composeur (« toutpanel stack apply ») : options transmises telles quelles APRÈS l'installation du panel (voir « Pile logicielle »).
PROFILE="${TOUTPANEL_PROFILE:-}"; WEB="${TOUTPANEL_WEB:-}"; PHP_VERS="${TOUTPANEL_PHP:-}"; PHP_DEFAULT="${TOUTPANEL_PHP_DEFAULT:-}"; PHP_EXT="${TOUTPANEL_PHP_EXT:-}"
DB="${TOUTPANEL_DB:-}"; ACCEL="${TOUTPANEL_ACCEL:-}"; FTP="${TOUTPANEL_FTP:-}"; MAIL_ENGINE="${TOUTPANEL_MAIL_ENGINE:-}"; DNS="${TOUTPANEL_DNS:-}"
SECURITY="${TOUTPANEL_SECURITY:-}"; RUNTIME="${TOUTPANEL_RUNTIME:-}"; TOOLS="${TOUTPANEL_TOOLS:-}"; INSTALL_MODE_OPT="${TOUTPANEL_INSTALL_MODE:-}"; ROLES="${TOUTPANEL_ROLES:-}"
STACK_FILE="${TOUTPANEL_STACK_FILE:-}"
REDIS_OPT=0; NO_TUNING=0; ACCEPT_LS_LICENSE=0
STACK_OPTS_SET=0          # au moins une option du composeur a été donnée : la pile est déléguée à « toutpanel stack apply »
# Pare-feu : on = ToutPanel le gère, off = pare-feu en amont (aucune règle système), ask = question interactive ; sans option : question
# dans un terminal, « plus tard » (le mode n'est pas choisi, rien n'est touché) sans terminal ou avec --yes.
FIREWALL="${TOUTPANEL_FIREWALL:-}"; FIREWALL_ENGINE="${TOUTPANEL_FIREWALL_ENGINE:-}"
FW_MODE=""                # résolu : panel | external | later
DRY_RUN=0                 # --dry-run : détection et plan affichés, rien n'est modifié
POST_DRY=0                # --post-dry (caché, tests) : exécute seulement les étapes après l'installation du panel avec le « toutpanel » du PATH
INIT_DRY=0                # --init-dry (caché, tests) : affiche les fichiers de service (unité systemd, scripts d'init, logrotate) sans rien écrire
PYTHON_DRY=0              # --python-dry (caché, tests) : exécute seulement la recherche d'un Python 3.9+ (paquets de la distribution simulés, Python autonome réel)
UPDATE=0
REINSTALL=0
UNINSTALL=0
YES=0
MAIL=0
POSTGRES=0
NODE=0          # --node : installation en mode nœud (multi-serveurs)
MASTER_URL=""   # --master : URL du panel maître
WAF=""
# ToutWAF distant (--waf toutwaf avec --waf-console) : le panel se relie à un ToutWAF installé sur un AUTRE serveur (voir « ToutWAF distant » plus bas).
# Le jeton d'API ne passe JAMAIS en argument : variable TOUTPANEL_WAF_TOKEN, --waf-token-file ou --waf-token-stdin (il vit dans WAF_TOKEN_VAL, jamais exporté).
WAF_CONSOLE=""; WAF_CONSOLE_SET=0   # --waf-console URL (ou TOUTPANEL_WAF_URL) : https://IP:9443/<chemin-secret>
WAF_ORIGIN_IP=""                    # --waf-origin-ip : adresse du ToutWAF vue par ce serveur (→ waf connect --waf-ip)
WAF_ORIGIN_ADDR=""                  # --waf-origin-addr : adresse de ce serveur vue par ToutWAF (→ waf connect --origin-ip)
WAF_RESTRICT=0                      # --waf-restrict : 80/443 limités à ToutWAF
WAF_CERT_MODE=""                    # --waf-cert-mode import|acme
WAF_SSL=""                          # --waf-ssl toutwaf|panel : « toutpanel waf connect toutwaf --ssl » (attendu avant le premier heartbeat ; la valeur du heartbeat fait foi)
WAF_SERVER_ID=""                    # --waf-server-id (ou TOUTPANEL_WAF_SERVER_ID)
WAF_FP=""; WAF_FP_SET=0             # --waf-fingerprint sha256:… (ou TOUTPANEL_WAF_PIN)
WAF_TRUST=0                         # --waf-trust-first-use
WAF_TOKEN_FILE=""; WAF_TOKEN_STDIN=0
WAF_TOKEN_VAL=""                    # le jeton : variable shell locale, retirée de l'environnement dès la lecture
WAF_OPT=0                           # une option --waf-* a été donnée (elle exige --waf toutwaf)
WAF_REMOTE_OPTS=""                  # options propres au mode distant données explicitement (elles exigent une console)
WAF_REMOTE=0                        # 1 : ToutWAF distant (aucune installation locale de ToutWAF)
WAF_RESTRICT_OK=0                   # restriction confirmée (--yes ou réponse à la question)
WAF_DRY=0                           # --waf-dry (caché, tests) : valide les options puis lance seulement le raccordement avec le « toutpanel » du PATH
WAF_STRICT=0                        # --waf-strict : code de sortie 3 (après le récapitulatif et --result-json, ok=false) si la liaison à ToutWAF n'est pas « linked »
WAF_WARNINGS=""                     # avertissements de la liaison (codes stables, séparés par des espaces) : server_id_missing ; repris dans --result-json (waf.warnings)
RESULT_JSON=""                      # --result-json FICHIER : résultat lisible par machine (voir write_result_json) ; jamais de mot de passe ni de jeton
ADMIN_USER=""
ADMIN_PASS=""                       # le mot de passe de l'administrateur : variable shell locale, jamais exportée, jamais en argument d'un processus fils
PASS_FILE=""; PASS_FILE_SET=0       # --password-file FICHIER
PASS_STDIN=0                        # --password-stdin
PASS_ARG_SET=0                      # --password VALEUR (déconseillé : visible dans « ps » et l'historique du shell)
PASS_SRC="generated"                # origine : generated (aléatoire, affiché au récapitulatif) | arg | env | file | stdin | prompt (jamais affiché)
ENTRANCE=""
SRC=""
# Dépôt public des versions ; TOUTPANEL_REPO permet d'installer depuis un autre dépôt (développement, fork).
REPO="${TOUTPANEL_REPO:-https://github.com/qu3ntin01/toutpanel.git}"
BRANCH="${TOUTPANEL_BRANCH:-main}"
CHANNEL="${TOUTPANEL_CHANNEL:-}"   # stable | dev (--channel) : dev clone la branche dev
VERSION="${TOUTPANEL_VERSION:-}"   # --version X.Y.Z : installe cette version publiée (voir « Version précise » plus bas)
LIST_VERSIONS=0                    # --list-versions : liste les versions publiées puis quitte
RESOLVE_ONLY=0                     # --resolve-only (avec --version) : vérification sans effet de bord, affiche le commit et la roue puis quitte

# options avec valeur : « --option=valeur » équivaut à « --option valeur »
_VALUE_OPTS=" --result-json --port --https-port --home --stack --waf --master --username --password --password-file --entrance --source --branch --channel --version --firewall --firewall-engine --profile --web --php --php-default --php-ext --db --accel --ftp --dns --security --runtime --tools --install-mode --roles --stack-file "
# option dont la valeur manque : message traduit (sinon « set -u » s'arrêterait sans explication)
_need() { if [[ $# -lt 2 ]]; then say opt_needs_value "$1"; exit 1; fi; }
# --mail seul = installation de Postfix + Dovecot + OpenDKIM (historique) ; --mail MOTEUR = serveur de courrier du composeur de pile
_MAIL_ENGINES="postfix postfix-clamav postfix-light exim relay none"

while [[ $# -gt 0 ]]; do
  case "$1" in --waf-*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}";; esac   # --waf-console=URL : même chose que --waf-console URL
  case "$1" in --*=*) if [[ "$_VALUE_OPTS" == *" ${1%%=*} "* ]]; then set -- "${1%%=*}" "${1#*=}" "${@:2}"; fi;; esac
  case "$1" in
    --port) _need "$@"; PORT="$2"; shift 2;;
    --https-port) _need "$@"; HTTPS_PORT="$2"; shift 2;;
    --random-port) RANDOM_PORT=1; shift;;
    --home) _need "$@"; HOME_DIR="$2"; HOME_SET=1; shift 2;;
    --stack) _need "$@"; STACK="$2"; STACK_SET=1; shift 2;;
    --update) UPDATE=1; shift;;
    --reinstall) REINSTALL=1; shift;;
    --uninstall) UNINSTALL=1; shift;;
    --yes|-y) YES=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    --post-dry) POST_DRY=1; shift;;
    --python-dry) PYTHON_DRY=1; shift;;
    --init-dry) INIT_DRY=1; shift;;
    --mail=*) MAIL_ENGINE="${1#--mail=}"; shift;;
    --mail)
      if [[ $# -gt 1 && " $_MAIL_ENGINES " == *" $2 "* ]]; then MAIL_ENGINE="$2"; shift 2; else MAIL=1; shift; fi;;
    --postgres) POSTGRES=1; shift;;
    --firewall) _need "$@"; FIREWALL="$2"; shift 2;;
    --firewall-engine) _need "$@"; FIREWALL_ENGINE="$2"; shift 2;;
    --profile) _need "$@"; PROFILE="$2"; shift 2;;
    --web) _need "$@"; WEB="$2"; shift 2;;
    --php) _need "$@"; PHP_VERS="$2"; shift 2;;
    --php-default) _need "$@"; PHP_DEFAULT="$2"; shift 2;;
    --php-ext) _need "$@"; PHP_EXT="$2"; shift 2;;
    --db) _need "$@"; DB="$2"; shift 2;;
    --redis) REDIS_OPT=1; shift;;
    --accel) _need "$@"; ACCEL="$2"; shift 2;;
    --ftp) _need "$@"; FTP="$2"; shift 2;;
    --dns) _need "$@"; DNS="$2"; shift 2;;
    --security) _need "$@"; SECURITY="$2"; shift 2;;
    --runtime) _need "$@"; RUNTIME="$2"; shift 2;;
    --tools) _need "$@"; TOOLS="$2"; shift 2;;
    --install-mode) _need "$@"; INSTALL_MODE_OPT="$2"; shift 2;;
    --roles) _need "$@"; ROLES="$2"; shift 2;;
    --stack-file) _need "$@"; STACK_FILE="$2"; shift 2;;
    --no-tuning) NO_TUNING=1; shift;;
    --accept-litespeed-license) ACCEPT_LS_LICENSE=1; shift;;
    --waf) _need "$@"; WAF="$2"; shift 2;;
    --waf-token) say waf_token_arg_refused; exit 1;;   # le jeton en argument serait visible dans « ps » et l'historique : refusé (la valeur n'est jamais lue ni affichée)
    --waf-console) WAF_CONSOLE="${2:-}"; WAF_CONSOLE_SET=1; WAF_OPT=1; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-origin-ip) WAF_ORIGIN_IP="${2:-}"; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-origin-addr) WAF_ORIGIN_ADDR="${2:-}"; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-restrict) WAF_RESTRICT=1; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift;;
    --waf-cert-mode) WAF_CERT_MODE="${2:-}"; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-ssl) WAF_SSL="${2:-}"; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-server-id) WAF_SERVER_ID="${2:-}"; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-fingerprint) WAF_FP="${2:-}"; WAF_FP_SET=1; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-trust-first-use) WAF_TRUST=1; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift;;
    --waf-token-file) WAF_TOKEN_FILE="${2:-}"; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift $(( $# > 1 ? 2 : 1 ));;
    --waf-token-stdin) WAF_TOKEN_STDIN=1; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift;;
    --waf-strict) WAF_STRICT=1; WAF_OPT=1; WAF_REMOTE_OPTS+=" $1"; shift;;
    --waf-dry) WAF_DRY=1; shift;;
    --result-json) _need "$@"; RESULT_JSON="$2"; shift 2;;
    --node) NODE=1; shift;;
    --master) _need "$@"; MASTER_URL="$2"; shift 2;;
    --username) _need "$@"; ADMIN_USER="$2"; shift 2;;
    --password) _need "$@"; ADMIN_PASS="$2"; if [[ -n "$2" ]]; then PASS_ARG_SET=1; fi; shift 2;;
    --password-file) _need "$@"; PASS_FILE="$2"; PASS_FILE_SET=1; shift 2;;
    --password-stdin) PASS_STDIN=1; shift;;
    --entrance) _need "$@"; ENTRANCE="$2"; shift 2;;
    --source) _need "$@"; SRC="$2"; shift 2;;
    --branch) _need "$@"; BRANCH="$2"; shift 2;;
    --channel) _need "$@"; CHANNEL="$2"; shift 2;;
    --version) _need "$@"; VERSION="$2"; shift 2;;
    --list-versions) LIST_VERSIONS=1; shift;;
    --resolve-only) RESOLVE_ONLY=1; shift;;
    --lang) _need "$@"; LANG_OPT="$2"; shift 2;;   # déjà prise en compte par la pré-lecture ci-dessus
    --lang=*|--en|--fr|--de|--es|--it|--pt|--nl|--ru|--zh|--ar) shift;;
    -h|--help) usage; exit 0;;
    *) say unknown_option "$1"; exit 1;;
  esac
done
case "$CHANNEL" in
  "") ;;
  stable) ;;
  dev) if [[ "$BRANCH" == "main" ]]; then BRANCH="dev"; fi ;;   # canal développeur : branche dev du dépôt public (sauf --branch explicite)
  *) say bad_channel "$CHANNEL"; exit 1;;
esac
case "$WAF" in
  ""|none|toutwaf|bunkerweb|safeline) ;;
  *) say bad_waf "$WAF"; exit 1;;
esac

# ------------------------------------------------------------------------------
# Contrôle des options de pile et de pare-feu (syntaxe et valeurs évidentes ; la validation fine est celle de « toutpanel stack » / « toutpanel firewall »).
# Avant toute modification du système : un message traduit, code de sortie 1.
# ------------------------------------------------------------------------------
_bad() { say bad_opt_value "$1" "$2" "$3"; exit 1; }
# valeur dans une liste fermée : _in_set OPTION VALEUR mot1 mot2 …
_in_set() { local opt="$1" v="$2" w; shift 2; for w in "$@"; do [[ "$v" == "$w" ]] && return 0; done; _bad "$opt" "$v" "$*"; }
# liste séparée par des virgules dont chaque élément respecte l'expression : _in_list OPTION VALEUR EXPRESSION AIDE
_in_list() {
  local opt="$1" v="$2" re="$3" help="$4" item
  [[ -n "$v" && "$v" != *,,* && "$v" != ,* && "$v" != *, ]] || _bad "$opt" "$v" "$help"
  while IFS= read -r item; do [[ "$item" =~ $re ]] || _bad "$opt" "$v" "$help"; done < <(printf '%s\n' "${v//,/$'\n'}")
}
validate_options() {
  local re_tok='^[a-z][a-z0-9-]*(:[A-Za-z0-9._-]+)?$' re_ver='^[0-9]+\.[0-9]+$'
  if [[ -n "$RESULT_JSON" && ( "$RESULT_JSON" != /* || "$RESULT_JSON" == *$'\n'* || -d "$RESULT_JSON" ) ]]; then say result_json_bad "$RESULT_JSON"; exit 1; fi
  # pare-feu
  if [[ -n "$FIREWALL" ]]; then _in_set --firewall "$FIREWALL" on off ask; fi
  if [[ -n "$FIREWALL_ENGINE" ]]; then
    _in_set --firewall-engine "$FIREWALL_ENGINE" nft nftables ufw firewalld csf iptables
    if [[ "$FIREWALL" == "off" ]]; then say fw_engine_needs_on; exit 1; fi
  fi
  # pile : un nom de profil, des listes de composants (la CLI valide chaque composant), des versions
  if [[ -n "$PROFILE" ]]; then _in_set --profile "$PROFILE" single-site multi-site hosting performance application mail-only dns-only node lamp standard custom minimal full none; fi
  if [[ -n "$WEB" ]]; then [[ "$WEB" =~ ^(none|(nginx|apache|apache-modphp|nginx-apache|caddy|openlitespeed|litespeed)(:[0-9]+(\.[0-9]+)*)?)$ ]] || _bad --web "$WEB" "nginx, apache, nginx-apache, openlitespeed[:1.9], litespeed[:6.3], none"; fi
  # LiteSpeed Enterprise : produit commercial, contrat de licence à accepter explicitement (refus avant toute modification)
  if [[ "$WEB" =~ ^litespeed(:|$) && $ACCEPT_LS_LICENSE -ne 1 ]]; then say litespeed_license_needed; exit 1; fi
  if [[ -n "$PHP_VERS" && "$PHP_VERS" != "none" ]]; then _in_list --php "$PHP_VERS" '^[0-9]+\.[0-9]+$' "8.4,8.5 | none"; fi
  if [[ -n "$PHP_DEFAULT" ]]; then [[ "$PHP_DEFAULT" =~ $re_ver ]] || _bad --php-default "$PHP_DEFAULT" "8.5"; fi
  if [[ -n "$PHP_EXT" ]]; then _in_set --php-ext "$PHP_EXT" minimal standard full; fi
  if [[ -n "$DB" && "$DB" != "none" ]]; then _in_list --db "$DB" '^(mariadb|mysql|percona|postgresql)(:[A-Za-z0-9._-]+)?$' "mariadb[:11.4], mysql[:8.4], percona, postgresql[:17], none"; fi
  if [[ -n "$ACCEL" && "$ACCEL" != "none" ]]; then _in_list --accel "$ACCEL" "$re_tok" "opcache,jit,apcu,redis,memcached,fastcgi-cache,varnish,brotli,zstd,http3,ioncube"; fi
  if [[ -n "$FTP" ]]; then _in_set --ftp "$FTP" builtin pureftpd proftpd vsftpd sftp none; fi
  if [[ -n "$MAIL_ENGINE" ]]; then _in_set --mail "$MAIL_ENGINE" $_MAIL_ENGINES; fi
  if [[ -n "$DNS" ]]; then _in_set --dns "$DNS" bind powerdns knot external none; fi
  if [[ -n "$SECURITY" && "$SECURITY" != "none" ]]; then _in_list --security "$SECURITY" '^[a-z][a-z0-9-]*$' "firewall,fail2ban,modsecurity,clamav,toutwaf"; fi
  if [[ -n "$RUNTIME" && "$RUNTIME" != "none" ]]; then _in_list --runtime "$RUNTIME" '^[a-z][a-z0-9-]*$' "nodejs,python,go,ruby,java,docker"; fi
  if [[ -n "$TOOLS" && "$TOOLS" != "none" ]]; then _in_list --tools "$TOOLS" '^[a-z][a-z0-9-]*$' "certbot,git,composer,phpmyadmin,adminer,restic,goaccess"; fi
  if [[ -n "$INSTALL_MODE_OPT" ]]; then _in_set --install-mode "$INSTALL_MODE_OPT" single-server single-site multi-site multi-server; fi
  if [[ -n "$ROLES" ]]; then _in_list --roles "$ROLES" '^(web|db|mail|dns)$' "web,db,mail,dns"; fi
  if [[ -n "$STACK_FILE" && ! -r "$STACK_FILE" ]]; then say stack_file_bad "$STACK_FILE"; exit 1; fi
  case "$STACK" in full|minimal|none) ;; *) _bad --stack "$STACK" "full, minimal, none";; esac
  # --home : chemin absolu
  if [[ $HOME_SET -eq 1 && "$HOME_DIR" != /* ]]; then _bad --home "$HOME_DIR" "/var/toutpanel"; fi
  # la pile du composeur et l'ancienne option --stack ne se combinent pas
  if [[ -n "$PROFILE$WEB$PHP_VERS$PHP_DEFAULT$PHP_EXT$DB$ACCEL$FTP$MAIL_ENGINE$DNS$SECURITY$RUNTIME$TOOLS$INSTALL_MODE_OPT$ROLES$STACK_FILE" || $REDIS_OPT -eq 1 || $NO_TUNING -eq 1 || $ACCEPT_LS_LICENSE -eq 1 ]]; then
    STACK_OPTS_SET=1
    if [[ $STACK_SET -eq 1 ]]; then say stack_conflict; exit 1; fi
  fi
}
validate_options

# ------------------------------------------------------------------------------
# ToutWAF distant : --waf toutwaf --waf-console https://IP:9443/<chemin-secret> (ou variable TOUTPANEL_WAF_URL)
# Le panel se relie à un ToutWAF installé sur un AUTRE serveur (aucune installation locale de ToutWAF) : en fin d'installation, une fois le panel
# démarré, « toutpanel waf connect toutwaf --json … » (le panel teste l'API, épingle l'empreinte TLS, déclare les sites, restreint 80/443 si demandé).
# Sans console, --waf toutwaf garde son comportement : installation de ToutWAF sur CE serveur. Le jeton d'API n'est JAMAIS un argument : il est lu dans
# TOUTPANEL_WAF_TOKEN (sudo -E le conserve), --waf-token-file ou --waf-token-stdin, gardé dans une variable shell non exportée, et transmis uniquement
# à l'environnement du processus « toutpanel waf connect » ; il n'est écrit ni dans install-info.txt, ni dans la sortie (masqué si le panel le répétait).
# ------------------------------------------------------------------------------
WAF_STATE=""        # linked | partial | unlinked (vide : pas de ToutWAF distant)
WAF_PINNED=""       # empreinte épinglée ou vue (récapitulatif)
WAF_FW_IPS=""       # adresses autorisées sur 80/443 quand la restriction est active
WAF_RC=0            # code de sortie de « toutpanel waf connect »
_has_tty() { { : </dev/tty; } 2>/dev/null; }
# adresse IPv4 (octets <= 255) ou IPv6 (crochets facultatifs)
_is_ip() {
  local v="${1#[}" i; v="${v%]}"
  if [[ "$v" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    for i in 1 2 3 4; do if (( 10#${BASH_REMATCH[$i]} > 255 )); then return 1; fi; done
    return 0
  fi
  [[ "$v" =~ ^[0-9A-Fa-f:.]+$ && "$v" == *:*:* ]]
}
# jeton : --waf-token-stdin, sinon --waf-token-file, sinon TOUTPANEL_WAF_TOKEN
waf_load_token() {
  local t=""
  if [[ $WAF_TOKEN_STDIN -eq 1 ]]; then
    case "${BASH_SOURCE[0]:-}" in ""|main) say waf_token_stdin_pipe; exit 1;; esac   # « curl | bash » : l'entrée standard est le script lui-même (BASH_SOURCE vaut « main » dans une fonction)
    IFS= read -r t || true
  elif [[ -n "$WAF_TOKEN_FILE" ]]; then
    if [[ ! -r "$WAF_TOKEN_FILE" ]]; then say waf_token_file_bad "$WAF_TOKEN_FILE"; exit 1; fi
    IFS= read -r t < "$WAF_TOKEN_FILE" || true
  else
    t="${TOUTPANEL_WAF_TOKEN:-}"
  fi
  t="${t//[[:space:]]/}"
  if [[ -z "$t" && ( $WAF_TOKEN_STDIN -eq 1 || -n "$WAF_TOKEN_FILE" ) ]]; then say waf_token_file_bad "${WAF_TOKEN_FILE:-stdin}"; exit 1; fi
  WAF_TOKEN_VAL="$t"
}
# avertissement « identifiant de serveur ToutWAF absent » : encadré, en jaune gras (le même texte dans les 10 langues : clé waf_server_id_missing)
waf_warn_server_id() {
  local line="!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  printf '\n\033[1;33m%s\n[ToutPanel] %s\n%s\033[0m\n\n' "$line" "$(msg waf_server_id_missing)" "$line"
}
waf_add_warning() { [[ " $WAF_WARNINGS " == *" $1 "* ]] || WAF_WARNINGS="${WAF_WARNINGS:+$WAF_WARNINGS }$1"; }
# --waf-strict : après le récapitulatif et l'écriture de --result-json (ok=false), code de sortie 3 si la liaison n'est pas « linked » (partial, unlinked)
waf_strict_exit() {
  if [[ $WAF_STRICT -eq 1 && $WAF_REMOTE -eq 1 && "$WAF_STATE" != "linked" ]]; then
    printf '\033[1;31m[ToutPanel] %s\033[0m\n' "$(msg waf_strict_failed "${WAF_STATE:-unlinked}")" >&2
    exit 3
  fi
  return 0
}
# contrôle des options --waf-* (avant toute modification du système) ; --waf none = aucun WAF externe
waf_validate() {
  local re_console='^https://[][A-Za-z0-9.:-]+(/[A-Za-z0-9._~/-]*)?$' re_fp='^([Ss][Hh][Aa]256:)?([0-9A-Fa-f]{2}:?){31}[0-9A-Fa-f]{2}$'
  if [[ "$WAF" == "none" ]]; then WAF=""; fi
  if [[ $WAF_OPT -eq 1 && "$WAF" != "toutwaf" ]]; then say waf_opts_need_waf; exit 1; fi
  if [[ "$WAF" != "toutwaf" ]]; then return 0; fi
  if [[ $WAF_CONSOLE_SET -eq 0 ]]; then WAF_CONSOLE="${TOUTPANEL_WAF_URL:-}"; fi
  if [[ $WAF_FP_SET -eq 0 ]]; then WAF_FP="${TOUTPANEL_WAF_PIN:-}"; fi
  if [[ -z "$WAF_SERVER_ID" ]]; then WAF_SERVER_ID="${TOUTPANEL_WAF_SERVER_ID:-}"; fi
  if [[ $WAF_CONSOLE_SET -eq 1 && -z "$WAF_CONSOLE" ]]; then say waf_console_empty; exit 1; fi
  if [[ -z "$WAF_CONSOLE" ]]; then   # pas de console : ToutWAF s'installe sur CE serveur (comportement historique) ; les options du mode distant n'ont pas de sens
    if [[ -n "$WAF_REMOTE_OPTS" ]]; then set -- $WAF_REMOTE_OPTS; say waf_opts_need_console "$1"; exit 1; fi
    return 0
  fi
  WAF_REMOTE=1
  if [[ ! "$WAF_CONSOLE" =~ $re_console ]]; then say waf_bad_console "$WAF_CONSOLE"; exit 1; fi
  if [[ -n "$WAF_ORIGIN_IP" ]] && ! _is_ip "$WAF_ORIGIN_IP"; then say waf_bad_ip "--waf-origin-ip" "$WAF_ORIGIN_IP"; exit 1; fi
  if [[ -n "$WAF_ORIGIN_ADDR" ]] && ! _is_ip "$WAF_ORIGIN_ADDR"; then say waf_bad_ip "--waf-origin-addr" "$WAF_ORIGIN_ADDR"; exit 1; fi
  if [[ -n "$WAF_CERT_MODE" && "$WAF_CERT_MODE" != "import" && "$WAF_CERT_MODE" != "acme" ]]; then say waf_bad_cert_mode "$WAF_CERT_MODE"; exit 1; fi
  if [[ -n "$WAF_SSL" && "$WAF_SSL" != "toutwaf" && "$WAF_SSL" != "panel" ]]; then say waf_bad_ssl "$WAF_SSL"; exit 1; fi
  if [[ ( $WAF_FP_SET -eq 1 || -n "$WAF_FP" ) && ! "$WAF_FP" =~ $re_fp ]]; then say waf_bad_fp; exit 1; fi
  if [[ -n "$WAF_SERVER_ID" && ! "$WAF_SERVER_ID" =~ ^[A-Za-z0-9._:-]{1,80}$ ]]; then say waf_bad_server_id; exit 1; fi
  if [[ -n "$WAF_FP" && $WAF_TRUST -eq 1 ]]; then say waf_tls_conflict; exit 1; fi
  if [[ $WAF_RESTRICT -eq 1 && $YES -eq 0 ]] && { [[ $WAF_DRY -eq 1 ]] || ! _has_tty; }; then say waf_restrict_needs_yes; exit 1; fi
  # identifiant de serveur absent : ni heartbeat ni remise du jeton d'API du panel à ToutWAF. Avertissement bruyant AVANT l'installation (répété à la fin si la
  # liaison ne l'a pas retrouvé dans un lien existant) ; jamais bloquant (compatibilité), code « server_id_missing » dans --result-json (waf.warnings)
  if [[ -z "$WAF_SERVER_ID" ]]; then waf_add_warning server_id_missing; fi
  if [[ -z "$WAF_SERVER_ID" && $UNINSTALL -eq 0 && $LIST_VERSIONS -eq 0 && $RESOLVE_ONLY -eq 0 ]]; then waf_warn_server_id; fi
  waf_load_token
  if [[ -z "$WAF_TOKEN_VAL" && $UNINSTALL -eq 0 && $LIST_VERSIONS -eq 0 && $RESOLVE_ONLY -eq 0 && $DRY_RUN -eq 0 ]]; then
    # sans terminal (ou avec --yes) on ne peut pas demander le jeton : échec AVANT toute modification ; sinon il est demandé plus loin, sans écho
    if [[ $WAF_DRY -eq 1 || $YES -eq 1 ]] || ! _has_tty; then say waf_token_missing; exit 1; fi
  fi
  return 0
}
waf_validate
# le jeton, l'URL de la console, l'empreinte et l'identifiant ne restent pas dans l'environnement de l'installeur (apt, pip, « toutpanel start »… ne les héritent pas)
unset TOUTPANEL_WAF_TOKEN TOUTPANEL_WAF_URL TOUTPANEL_WAF_PIN TOUTPANEL_WAF_SERVER_ID

# ------------------------------------------------------------------------------
# Mot de passe administrateur (installation neuve) : il ne doit apparaître ni dans la ligne de commande (« ps », historique du shell), ni dans les journaux,
# ni dans install-info.txt, ni dans le récapitulatif, ni dans les arguments de « toutpanel setup » (il lui est transmis par l'environnement de ce seul processus).
# Sources, UNE seule option à la fois (deux options = erreur) ; ordre de priorité :
#   1. l'option donnée : --password-stdin (1re ligne de l'entrée standard), --password-file FICHIER (1re ligne ; refusé si le fichier est lisible par le groupe
#      ou les autres, ou n'appartient ni à root ni à l'utilisateur), --password VALEUR (déconseillé : avertissement, mais jamais refusé) ;
#   2. la variable d'environnement TOUTPANEL_PASSWORD (à conserver avec sudo -E) ;
#   3. sinon : question dans un terminal (aléatoire recommandé, ou saisie sans écho avec confirmation) ; sans terminal ou avec --yes : aléatoire (affiché au récapitulatif).
# Un mot de passe fourni n'est jamais affiché ni écrit : le récapitulatif et install-info.txt le disent (« celui que vous avez fourni »). Mise à jour : jamais modifié.
# ------------------------------------------------------------------------------
PASS_MIN_LEN=8      # politique par défaut du panel (réglage pwd_min_length) ; le panel reste juge : il refuse un mot de passe qui ne respecte pas ses réglages (code 3)
PASS_KEPT=0         # 1 : mise à jour, le compte existant est conservé (aucun mot de passe n'est lu ni appliqué)
# code de l'erreur de politique (short | long | chars | user | common), rien si le mot de passe convient ; alignée sur toutpanel.security.password_policy
pass_policy_error() {   # $1 = mot de passe, $2 = nom d'utilisateur
  local p="$1" u="${2:-}"
  if (( ${#p} < PASS_MIN_LEN )); then printf short
  elif (( ${#p} > 256 )); then printf long
  elif [[ "$p" != *[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ]* || "$p" != *[0123456789]* ]]; then printf chars
  elif [[ -n "$u" && "${p,,}" == "${u,,}" ]]; then printf user
  else
    case "${p,,}" in password|motdepasse|admin123|12345678|azerty123|qwerty123|password1|motdepasse1|azertyuiop|123456789) printf common;; esac
  fi
  return 0
}
pass_say_error() {
  case "$1" in
    short) say pass_err_short "$PASS_MIN_LEN";;
    long) say pass_err_long;;
    chars) say pass_err_chars;;
    user) say pass_err_user;;
    *) say pass_err_common;;
  esac
}
# lecture de la source choisie (avant toute modification du système) ; la valeur vit dans ADMIN_PASS, jamais exportée
pass_load() {
  local p="" n mode uid
  if [[ $UNINSTALL -eq 1 || $LIST_VERSIONS -eq 1 || $RESOLVE_ONLY -eq 1 || $UPDATE -eq 1 ]]; then return 0; fi
  n=$(( PASS_ARG_SET + PASS_FILE_SET + PASS_STDIN ))
  if [[ $n -gt 1 ]]; then say pass_conflict; exit 1; fi
  if [[ $PASS_STDIN -eq 1 && $WAF_TOKEN_STDIN -eq 1 ]]; then say pass_stdin_waf; exit 1; fi
  if [[ $PASS_STDIN -eq 1 ]]; then
    case "${BASH_SOURCE[0]:-}" in ""|main) say pass_stdin_pipe; exit 1;; esac   # « curl | bash » : l'entrée standard est le script lui-même (BASH_SOURCE vaut « main » dans une fonction)
    if [[ -t 0 ]]; then IFS= read -rs p || true; printf '\n' >&2; else IFS= read -r p || true; fi
    PASS_SRC="stdin"
  elif [[ $PASS_FILE_SET -eq 1 ]]; then
    case "$PASS_FILE" in /dev/stdin|/dev/fd/0|/proc/self/fd/0) case "${BASH_SOURCE[0]:-}" in ""|main) say pass_stdin_pipe; exit 1;; esac;; esac
    if [[ -z "$PASS_FILE" || ! -r "$PASS_FILE" || -d "$PASS_FILE" ]]; then say pass_file_bad "$PASS_FILE"; exit 1; fi
    if [[ -f "$PASS_FILE" ]]; then   # fichier ordinaire : ni lisible ni modifiable par le groupe ou les autres, propriétaire root ou l'utilisateur (tube, <(…) et terminal : pas de contrôle)
      mode=$(stat -c '%a' -- "$PASS_FILE" 2>/dev/null || echo 777); uid=$(stat -c '%u' -- "$PASS_FILE" 2>/dev/null || echo -1)
      if (( 8#$mode & 8#077 )) || [[ "$uid" != 0 && "$uid" != "$EUID" && "$uid" != "${SUDO_UID:-x}" ]]; then say pass_file_perm "$PASS_FILE" "$PASS_FILE"; exit 1; fi
    fi
    IFS= read -r p < "$PASS_FILE" || true
    PASS_SRC="file"
  elif [[ $PASS_ARG_SET -eq 1 ]]; then
    warn pass_arg_warn; PASS_SRC="arg"; return 0
  elif [[ $PASS_ENV_SET -eq 1 ]]; then
    ADMIN_PASS="$PASS_ENV"; PASS_ENV=""; PASS_SRC="env"; return 0
  else
    return 0
  fi
  p="${p%$'\r'}"   # fichier créé sous Windows (fin de ligne CRLF)
  if [[ -z "$p" ]]; then say pass_file_bad "${PASS_FILE:-stdin}"; exit 1; fi
  ADMIN_PASS="$p"
}
pass_load

# questions du mode interactif (après le menu) : jeton sans écho, confirmation de la restriction du pare-feu
waf_prompts() {
  local ans=""
  if [[ -z "$WAF_TOKEN_VAL" ]]; then
    if [[ $YES -eq 1 ]] || ! _has_tty; then say waf_token_missing; exit 1; fi
    printf '  %s' "$(msg waf_token_prompt)" >/dev/tty
    IFS= read -rs WAF_TOKEN_VAL </dev/tty || true
    printf '\n' >/dev/tty
    WAF_TOKEN_VAL="${WAF_TOKEN_VAL//[[:space:]]/}"
    if [[ -z "$WAF_TOKEN_VAL" ]]; then say waf_token_missing; exit 1; fi
  fi
  if [[ $WAF_RESTRICT -eq 1 ]]; then
    if [[ $YES -eq 1 ]]; then
      WAF_RESTRICT_OK=1
    else
      printf '  %s' "$(msg waf_ask_restrict "$(msg yn_hint)")" >/dev/tty
      read -r ans </dev/tty || ans=""
      if is_yes "$ans"; then WAF_RESTRICT_OK=1; else WAF_RESTRICT=0; warn waf_restrict_declined; fi
    fi
  fi
}
# https://IP:9443/<chemin-secret> → https://IP:9443 (le chemin secret n'est jamais repris dans le récapitulatif)
waf_console_base() { local u="${WAF_CONSOLE#https://}"; printf 'https://%s' "${u%%/*}"; }
# masque le jeton (valeur connue, ou tout motif tw_…) dans le texte lu sur l'entrée standard
waf_mask() {
  local t; t=$(cat)
  if [[ -n "$WAF_TOKEN_VAL" ]]; then t="${t//"$WAF_TOKEN_VAL"/tw_***}"; fi
  printf '%s' "$t" | sed -E 's/tw_[A-Za-z0-9_-]{8,}/tw_***/g'
}
# options de « toutpanel waf connect » (sans --json ; l'URL, l'empreinte et l'identifiant passent par l'environnement, pas par les arguments)
waf_connect_flags() {   # $1 = 1 : version à relancer à la main (la restriction demandée l'est, sans --yes : le panel posera la question)
  local f=""
  if [[ -n "$WAF_ORIGIN_IP" ]]; then f+=" --waf-ip $WAF_ORIGIN_IP"; fi
  if [[ -n "$WAF_ORIGIN_ADDR" ]]; then f+=" --origin-ip $WAF_ORIGIN_ADDR"; fi
  if [[ -n "$WAF_CERT_MODE" ]]; then f+=" --cert-mode $WAF_CERT_MODE"; fi
  if [[ -n "$WAF_SSL" ]]; then f+=" --ssl $WAF_SSL"; fi
  if [[ $WAF_TRUST -eq 1 ]]; then f+=" --trust-first-use"; fi
  if [[ "${1:-}" == "1" ]]; then
    if [[ $WAF_RESTRICT -eq 1 ]]; then f+=" --restrict-origin"; fi
  elif [[ $WAF_RESTRICT_OK -eq 1 ]]; then
    f+=" --restrict-origin --yes"
  fi
  printf '%s' "$f"
}
# commandes à relancer à la main si le raccordement a échoué (le jeton est à exporter : jamais en argument)
waf_retry_lines() {
  local pre="${1:-}" env_line="export TOUTPANEL_WAF_TOKEN='tw_...' TOUTPANEL_WAF_URL='$WAF_CONSOLE'"
  if [[ -n "$WAF_FP" ]]; then env_line+=" TOUTPANEL_WAF_PIN='$WAF_FP'"; fi
  if [[ -n "$WAF_SERVER_ID" ]]; then env_line+=" TOUTPANEL_WAF_SERVER_ID='$WAF_SERVER_ID'"; fi
  printf '%s  %s\n' "$pre" "$(msg waf_retry)"
  printf '%s    %s\n' "$pre" "$env_line"
  printf '%s    toutpanel waf connect toutwaf%s\n' "$pre" "$(waf_connect_flags 1)"
}
# raccordement : « toutpanel waf connect toutwaf --json » ; le panel reste installé quoi qu'il arrive (retourne toujours 0, l'état est dans WAF_STATE)
waf_connect() {
  local bin="$1" out="" errf rc=0 prog tls fp emsg ra rips detail sid
  local -a a=(waf connect toutwaf --json) F=() extra=()
  read -r -a extra <<<"$(waf_connect_flags)"
  if [[ ${#extra[@]} -gt 0 ]]; then a+=("${extra[@]}"); fi
  log waf_connecting "$(waf_console_base)"
  errf=$(mktemp "${TMPDIR:-/tmp}/toutpanel-waf.XXXXXX")
  # l'environnement n'est transmis qu'à CE processus : ni arguments (« ps »), ni historique, ni fichier
  # TOUTPANEL_LANG : langue des messages de « waf connect » (une variable et non une option --lang : un panel plus ancien l'ignore sans erreur)
  out=$(TOUTPANEL_WAF_TOKEN="$WAF_TOKEN_VAL" TOUTPANEL_WAF_URL="$WAF_CONSOLE" TOUTPANEL_WAF_PIN="$WAF_FP" TOUTPANEL_WAF_SERVER_ID="$WAF_SERVER_ID" TOUTPANEL_WAF_INSTALLED_VIA=installer \
        TOUTPANEL_LANG="$UI_LANG" "$bin" "${a[@]}" 2>"$errf") || rc=$?
  WAF_RC=$rc
  if [[ -s "$errf" ]]; then sed 's/^/    /' "$errf" | waf_mask; printf '\n'; fi
  prog=$(cat <<'PY'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}
e = d.get("error") if isinstance(d.get("error"), dict) else {}
r = d.get("restrict") if isinstance(d.get("restrict"), dict) else {}
def one(v):
    return "" if v is None else str(v).replace("\n", " ").replace("\r", " ")
ips = r.get("ips") if isinstance(r.get("ips"), list) else []
print(one(d.get("tls")))
print(one(d.get("fingerprint") or e.get("fingerprint")))
print(one(e.get("message")))
print(1 if r.get("active") else 0)
print(",".join(str(i) for i in ips))
print(one(d.get("server_id")))
PY
)
  mapfile -t F < <(printf '%s' "$out" | PYTHONIOENCODING=utf-8 python3 -c "$prog" 2>/dev/null || true)
  tls="${F[0]:-}"; fp="${F[1]:-}"; emsg="${F[2]:-}"; ra="${F[3]:-0}"; rips="${F[4]:-}"; sid="${F[5]:-}"
  rm -f "$errf"
  detail=""
  if [[ -n "$emsg" ]]; then detail=$(printf '%s' "$emsg" | waf_mask); fi
  case "$rc" in
    0|7|8)
      WAF_STATE="linked"; if [[ "$rc" -eq 7 ]]; then WAF_STATE="partial"; fi
      log waf_linked "$(waf_console_base)"
      if [[ "$tls" == "pinned" && -n "$fp" ]]; then WAF_PINNED="$fp"; log waf_pinned "$fp"; else warn waf_unpinned; fi
      if [[ "$rc" -eq 7 ]]; then warn waf_partial; fi
      # identifiant retenu par le panel (celui d'un lien existant au même ToutWAF est conservé quand l'option n'est pas donnée)
      if [[ -z "$WAF_SERVER_ID" && "$sid" =~ ^[A-Za-z0-9._:-]{1,80}$ ]]; then WAF_SERVER_ID="$sid"; fi
      if [[ -n "$detail" && "$rc" -ne 0 ]]; then warn waf_detail "$detail"; fi
      if [[ "$rc" -eq 8 ]]; then
        warn waf_firewall
      elif [[ $WAF_RESTRICT_OK -eq 1 ]]; then
        if [[ "$ra" == "1" ]]; then WAF_FW_IPS="$rips"; log waf_fw_closed "$rips"
        else warn waf_firewall; fi
      fi
      ;;
    *)
      WAF_STATE="unlinked"
      case "$rc" in
        2) warn waf_args;;
        3) warn waf_unreachable;;
        4) if [[ -n "$fp" ]]; then warn waf_fp_seen "$fp" "$fp"; else warn waf_tls_other; fi;;
        5) warn waf_denied;;
        6) warn waf_incompat;;
        *) warn waf_error "$rc";;
      esac
      if [[ -n "$detail" ]]; then warn waf_detail "$detail"; fi
      warn waf_not_linked
      waf_retry_lines "    "
      ;;
  esac
  if [[ -z "$WAF_SERVER_ID" ]]; then waf_add_warning server_id_missing; waf_warn_server_id; else WAF_WARNINGS="${WAF_WARNINGS//server_id_missing/}"; fi
  WAF_TOKEN_VAL=""
  return 0
}
# lignes « libellé : valeur » du récapitulatif (console et install-info.txt) : jamais le jeton ni le chemin secret de la console
waf_info_lines() {   # $1 = largeur des libellés, $2 = préfixe, $3 = 1 : joindre la commande à relancer si le raccordement a échoué (install-info.txt)
  if [[ $WAF_REMOTE -eq 0 ]]; then return 0; fi
  local w="$1" pre="${2:-}" st
  case "$WAF_STATE" in
    linked) st=$(msg waf_st_linked);;
    partial) st=$(msg waf_st_partial);;
    *) st=$(msg waf_st_unlinked);;
  esac
  printf '%s' "$pre"; kv "$w" "$(msg lbl_waf)" "$(msg waf_info_remote "$(waf_console_base)")"
  printf '%s' "$pre"; kv "$w" "$(msg lbl_waf_link)" "$st"
  printf '%s' "$pre"; kv "$w" "$(msg lbl_waf_pin)" "${WAF_PINNED:-$(msg waf_pin_none)}"
  if [[ -n "$WAF_FW_IPS" ]]; then printf '%s' "$pre"; kv "$w" "$(msg lbl_waf_fw)" "$(msg waf_fw_on "$WAF_FW_IPS")"
  elif [[ $WAF_RESTRICT -eq 1 ]]; then printf '%s' "$pre"; kv "$w" "$(msg lbl_waf_fw)" "$(msg waf_fw_off)"; fi
  if [[ " $WAF_WARNINGS " == *" server_id_missing "* ]]; then printf '%s%s\n' "$pre" "$(msg waf_server_id_missing)"; fi
  if [[ "$WAF_STATE" == "unlinked" && "${3:-}" == "1" ]]; then waf_retry_lines "$pre"; fi
  return 0
}

# ------------------------------------------------------------------------------
# Version précise : --version X.Y.Z (aussi vX.Y.Z, 0.4.0-beta.1 ou 0.4.0b1 ; variable TOUTPANEL_VERSION) et --list-versions
# Le dépôt public n'a pas d'étiquettes obligatoires : chaque publication est UN commit dont le sujet est exactement « ToutPanel X.Y.Z »
# (convention de scripts/publish-public.sh, à ne pas changer) et dont dist/ contient les roues de cette version. Résolution : (a) étiquette
# vX.Y.Z si elle existe (clone --depth 1), (b) sinon commit de publication retrouvé par son sujet dans un clone partiel (sans les fichiers),
# (c) sinon arrêt AVANT toute modification du serveur avec la liste des versions disponibles.
# ------------------------------------------------------------------------------
NORM=""; RES_DIR=""; RES_SHA=""; RES_BRANCH=""; RES_VIA=""; RES_WHEEL=""
trap '[[ -n "${RES_DIR:-}" ]] && rm -rf "$RES_DIR"; true' EXIT

# 0.4.0-beta.1 / 0.4.0b1 / v0.4.0 / 0.4.0-rc.2 → 0.4.0b1 / 0.4.0 / 0.4.0rc2 ; code 1 si ce n'est pas une version
normalize_version() {
  local v="${1,,}" re='^([0-9]+\.[0-9]+\.[0-9]+)([-.]?(alpha|beta|rc|a|b|c)[-.]?([0-9]+))?$' k=""
  v="${v#v}"; v="${v// /}"
  [[ "$v" =~ $re ]] || return 1
  if [[ -n "${BASH_REMATCH[2]}" ]]; then
    case "${BASH_REMATCH[3]}" in alpha|a) k=a;; beta|b) k=b;; *) k=rc;; esac
    printf '%s%s%s' "${BASH_REMATCH[1]}" "$k" "${BASH_REMATCH[4]}"
  else
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}
# compare deux versions normalisées : affiche -1, 0 ou 1 (préversions a < b < rc < finale)
version_cmp() {
  python3 - "$1" "$2" <<'PY'
import re, sys
def key(v):
    m = re.match(r'^(\d+)\.(\d+)\.(\d+)(?:(a|b|rc)(\d+))?', v)
    if not m:
        return (0, 0, 0, 0, 0)
    return (int(m[1]), int(m[2]), int(m[3]), {'a': 0, 'b': 1, 'rc': 2, None: 3}[m[4]], int(m[5] or 0))
a, b = key(sys.argv[1]), key(sys.argv[2])
print((a > b) - (a < b))
PY
}
# git est nécessaire pour chercher les versions ; installé au besoin (seul prérequis ajouté avant la résolution)
ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  if [[ $EUID -ne 0 ]]; then say version_need_git; return 1; fi
  say version_git_install
  if command -v apt-get >/dev/null; then apt-get update -qq >/dev/null 2>&1 || true; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null; then dnf install -y git >/dev/null 2>&1 || true
  elif command -v yum >/dev/null; then yum install -y git >/dev/null 2>&1 || true
  elif command -v pacman >/dev/null; then pacman -S --noconfirm --needed git >/dev/null 2>&1 || true
  elif command -v apk >/dev/null; then apk add --no-cache git >/dev/null 2>&1 || true
  elif command -v zypper >/dev/null; then zypper --non-interactive install git >/dev/null 2>&1 || true
  fi
  command -v git >/dev/null 2>&1 || { say version_need_git; return 1; }
}
# clone partiel (commits et arbres seulement, aucun fichier) dans $1 ; repli sur un clone complet si le serveur refuse le filtre
fetch_history() {
  rm -rf "$1"
  git clone --quiet --filter=blob:none --no-checkout "$REPO" "$1" 2>/dev/null || git clone --quiet --no-checkout "$REPO" "$1"
}
# versions publiées d'un clone : « version<TAB>branche », la plus récente d'abord (main prime si une version est sur les deux branches)
list_versions_of() {
  local ref br
  while read -r ref; do
    br="${ref#origin/}"; [[ "$br" == HEAD ]] && continue
    git -C "$1" log "$ref" --format='%ct%x09%s' 2>/dev/null | awk -F'\t' -v b="$br" '$2 ~ /^ToutPanel [0-9]/ { sub(/^ToutPanel /, "", $2); print $1 "\t" $2 "\t" b }'
  done < <(git -C "$1" for-each-ref --format='%(refname:short)' refs/remotes/origin) \
    | sort -t$'\t' -k1,1nr | awk -F'\t' '{ if (!($2 in seen)) order[++n] = $2; if (!($2 in seen) || $3 == "main") br[$2] = $3; seen[$2] = 1 } END { for (i = 1; i <= n; i++) print order[i] "\t" br[order[i]] }'
}
print_versions() {   # $1 = clone ; affiche la liste lisible (stable / dev)
  local v b label n=0
  while IFS=$'\t' read -r v b; do
    n=$((n + 1))
    case "$b" in main) label=$(msg ver_stable);; dev) label=$(msg ver_dev);; *) label="$b";; esac
    printf '  %-14s %s\n' "$v" "$label"
  done < <(list_versions_of "$1")
  [[ $n -gt 0 ]] || printf '  %s\n' "$(msg versions_none "$REPO")"
}
# roue du Python du système dans le commit résolu (lecture de l'arbre, sans télécharger de fichier) ; RES_WHEEL vide si aucune roue (dépôt de sources)
check_wheel() {
  local tag names sup pyv
  RES_WHEEL=""
  command -v python3 >/dev/null 2>&1 || return 0
  tag=$(python3 -c 'import sys;print(f"cp{sys.version_info[0]}{sys.version_info[1]}")' 2>/dev/null) || return 0
  pyv=$(python3 -c 'import sys;print(f"{sys.version_info[0]}.{sys.version_info[1]}")' 2>/dev/null) || return 0
  names=$(git -C "$RES_DIR/repo" ls-tree --name-only "$RES_SHA" dist/ 2>/dev/null | sed 's#^dist/##' | grep '^toutpanel-.*-none-any\.whl$' || true)
  [[ -n "$names" ]] || return 0
  RES_WHEEL=$(printf '%s\n' "$names" | grep -- "-${tag}-none-any\.whl\$" | sort -V | tail -1 || true)
  if [[ -z "$RES_WHEEL" ]]; then
    sup=$(git -C "$RES_DIR/repo" show "$RES_SHA:version.json" 2>/dev/null | python3 -c 'import json,sys;print(" ".join(json.load(sys.stdin)["pythons"]))' 2>/dev/null || true)
    [[ -n "$sup" ]] || sup=$(printf '%s\n' "$names" | sed -E 's/.*-cp3([0-9]+)-none-any\.whl/3.\1/' | sort -V | tr '\n' ' ')
    say version_no_wheel "$NORM" "$pyv" "$sup"
    return 1
  fi
}
# résout $NORM dans $RES_DIR/repo : RES_SHA, RES_BRANCH (main / dev), RES_VIA (tag / commit), RES_WHEEL. Quitte avec un message clair
# (et la liste des versions disponibles) si la version est introuvable ou n'a pas de roue pour ce Python : rien n'est modifié.
resolve_or_die() {
  local pat
  RES_DIR=$(mktemp -d "${TMPDIR:-/tmp}/toutpanel-version.XXXXXX")
  if git ls-remote --exit-code --tags "$REPO" "refs/tags/v$NORM" >/dev/null 2>&1 \
     && { git clone --quiet --depth 1 --filter=blob:none --no-checkout -b "v$NORM" "$REPO" "$RES_DIR/repo" 2>/dev/null \
          || git clone --quiet --depth 1 --no-checkout -b "v$NORM" "$REPO" "$RES_DIR/repo" 2>/dev/null; }; then
    RES_SHA=$(git -C "$RES_DIR/repo" rev-parse HEAD); RES_VIA="tag"
    if [[ "$NORM" =~ (a|b|rc)[0-9]+$ ]]; then RES_BRANCH="dev"; else RES_BRANCH="main"; fi
  else
    if ! fetch_history "$RES_DIR/repo"; then say version_net_fail "$REPO"; exit 1; fi
    pat="^ToutPanel ${NORM//./\\.}\$"
    RES_SHA=$(git -C "$RES_DIR/repo" log --all --format=%H --grep="$pat" -n1 2>/dev/null || true)
    if [[ -z "$RES_SHA" ]]; then
      say version_not_found "$NORM" "$REPO"
      print_versions "$RES_DIR/repo"
      exit 1
    fi
    RES_VIA="commit"
    if git -C "$RES_DIR/repo" branch -r --contains "$RES_SHA" 2>/dev/null | grep -q 'origin/main'; then RES_BRANCH="main"; else RES_BRANCH="dev"; fi
  fi
  check_wheel || exit 1
}

if [[ -n "$VERSION" ]]; then
  NORM=$(normalize_version "$VERSION") || { say bad_version "$VERSION"; exit 1; }
fi
if [[ $LIST_VERSIONS -eq 1 ]]; then          # liste des versions publiées : aucun droit root requis, rien n'est modifié
  ensure_git || exit 1
  RES_DIR=$(mktemp -d "${TMPDIR:-/tmp}/toutpanel-version.XXXXXX")
  fetch_history "$RES_DIR/repo" || { say version_net_fail "$REPO"; exit 1; }
  say versions_title
  print_versions "$RES_DIR/repo"
  exit 0
fi
if [[ $RESOLVE_ONLY -eq 1 ]]; then           # vérification : commit et roue trouvés pour --version, sans rien installer ni modifier
  [[ -n "$NORM" ]] || { say bad_version ""; exit 1; }
  ensure_git || exit 1
  resolve_or_die
  printf 'version=%s\ncommit=%s\nbranch=%s\nvia=%s\nwheel=%s\n' "$NORM" "$RES_SHA" "$RES_BRANCH" "$RES_VIA" "$RES_WHEEL"
  exit 0
fi

if [[ $EUID -ne 0 && $WAF_DRY -eq 0 && $DRY_RUN -eq 0 && $POST_DRY -eq 0 && $PYTHON_DRY -eq 0 && $INIT_DRY -eq 0 ]]; then say need_root; exit 1; fi   # --dry-run, --waf-dry et --post-dry (tests) : aucun droit root, rien n'est modifié

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
# Largeur d'affichage d'un texte (caractères chinois : 2 colonnes) pour aligner les récapitulatifs, quelle que soit la locale
_dw() { python3 -c 'import sys,unicodedata as u;print(sum(0 if u.combining(c) else 2 if u.east_asian_width(c) in "WF" else 1 for c in sys.argv[1]))' "$1" 2>/dev/null || printf '%s' "${#1}"; }
# kv LARGEUR LIBELLÉ VALEUR : « libellé    : valeur » aligné sur LARGEUR colonnes
kv() {
  local w pad
  w=$(_dw "$2"); pad=$(( $1 - w ))
  if (( pad < 1 )); then pad=1; fi
  printf '%s%*s: %s\n' "$2" "$pad" "" "$3"
}
# Cadre du message final, largeur fixe quelle que soit la langue
box() {
  local w pad
  w=$(_dw "$1"); pad=$(( 64 - w ))
  if (( pad < 1 )); then pad=1; fi
  printf '\033[1;32m╔══════════════════════════════════════════════════════════════════╗\033[0m\n'
  printf '\033[1;32m║  %s%*s║\033[0m\n' "$1" "$pad" ""
  printf '\033[1;32m╚══════════════════════════════════════════════════════════════════╝\033[0m\n'
}
# Réponse « oui » à une question [o/N] : o / y, plus l'initiale de « oui » dans la langue choisie
is_yes() { local c="${1:0:1}"; [[ -n "$c" && "oOyY$(msg yes_chars)" == *"$c"* ]]; }

# --result-json FICHIER : résultat lisible par machine pour un outil qui pilote l'installeur (ToutWAF). Contenu : version et URL du panel, état de la liaison WAF
# (console sans chemin secret, empreinte épinglée, identifiant de serveur). JAMAIS de mot de passe, de jeton ni de lien d'assistant : ces secrets restent dans
# install-info.txt (mode 600). Fichier écrit en mode 600 ; un échec d'écriture n'affecte pas l'installation.
#
# CONTRAT (schema 1, documenté dans docs/content/installation/linux.md « Résultat lisible par machine », figé par tests/test_installer_result_contract.py) :
#   schema (int) · ok (bool) · mode (str : install | update | waf-dry) · written_at (str)
#   panel.{version (str), url (str), api_url (str), entrance_set (bool), port (int|null), https_port (int|null), home (str), up (bool)}
#        (port / https_port : écoute HTTP / HTTPS du panel, null quand elle est désactivée)
#   server.{hostname (str)}
#   waf.{remote (bool), state (str : linked | partial | unlinked, "" sans ToutWAF distant), console (str), fingerprint (str), server_id (str),
#        strict (bool), warnings (liste de codes str : server_id_missing)}
# Ajouter une clé est permis. Tout changement INCOMPATIBLE (clé retirée ou renommée, type ou sens d'une valeur changé) incrémente « schema ».
# ok = false seulement avec --waf-strict quand la liaison n'est pas « linked » (le script sort alors avec le code 3, APRÈS avoir écrit ce fichier).
write_result_json() {   # $1 = install | update | waf-dry
  [[ -n "$RESULT_JSON" ]] || return 0
  local py ver=""
  py="${PYX:-$(command -v python3 || true)}"
  if [[ -z "$py" ]]; then warn result_json_failed "$RESULT_JSON"; return 0; fi
  if [[ "$1" != "waf-dry" ]]; then ver=$("${TP:-toutpanel}" --version 2>/dev/null | head -1 || true); fi
  if RJ_MODE="$1" RJ_VERSION="${ver:-${NORM:-}}" RJ_URL="${URL:-}" RJ_ENTRANCE="${ENTRANCE:-}" RJ_PORT="$([[ ${HTTP_ON:-1} -eq 1 ]] && printf '%s' "${PORT:-}" || true)" \
     RJ_HTTPS_PORT="$([[ ${HTTPS_ON:-1} -eq 1 ]] && printf '%s' "${HTTPS_PORT:-}" || true)" \
     RJ_HOME="${HOME_DIR:-}" RJ_UP="${PANEL_UP:-1}" RJ_HOST="$(hostname 2>/dev/null || true)" RJ_WAF_REMOTE="$WAF_REMOTE" RJ_WAF_STATE="$WAF_STATE" \
     RJ_WAF_CONSOLE="$([[ $WAF_REMOTE -eq 1 ]] && waf_console_base || true)" RJ_WAF_FP="$WAF_PINNED" RJ_WAF_SID="$WAF_SERVER_ID" \
     RJ_WAF_STRICT="$WAF_STRICT" RJ_WAF_WARNINGS="$([[ $WAF_REMOTE -eq 1 ]] && printf '%s' "$WAF_WARNINGS" || true)" \
     PYTHONIOENCODING=utf-8 "$py" -c '
import json, os, sys, tempfile
from datetime import datetime, timezone
e = os.environ
url, ent = e.get("RJ_URL", ""), e.get("RJ_ENTRANCE", "")
api = url[: -len(ent)] if ent and url.endswith(ent) else url
def num(v):
    return int(v) if str(v).isdigit() else None
strict = e.get("RJ_WAF_STRICT") == "1"
remote = e.get("RJ_WAF_REMOTE") == "1"
# schema : incrémenté à tout changement incompatible (voir le contrat au-dessus de write_result_json) ; ajouter une clé reste permis
doc = {"schema": 1, "ok": not (strict and remote and e.get("RJ_WAF_STATE", "") != "linked"), "mode": e["RJ_MODE"], "written_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "panel": {"version": e.get("RJ_VERSION", ""), "url": url, "api_url": api, "entrance_set": bool(ent), "port": num(e.get("RJ_PORT", "")),
                 "https_port": num(e.get("RJ_HTTPS_PORT", "")), "home": e.get("RJ_HOME", ""), "up": e.get("RJ_UP", "1") == "1"},
       "server": {"hostname": e.get("RJ_HOST", "")},
       "waf": {"remote": remote, "state": e.get("RJ_WAF_STATE", ""), "console": e.get("RJ_WAF_CONSOLE", ""),
               "fingerprint": e.get("RJ_WAF_FP", ""), "server_id": e.get("RJ_WAF_SID", ""), "strict": strict,
               "warnings": e.get("RJ_WAF_WARNINGS", "").split()}}
path = sys.argv[1]
d = os.path.dirname(path)
os.makedirs(d, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".result-", dir=d)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=1)
    f.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, path)
' "$RESULT_JSON" 2>/dev/null; then
    log result_json_saved "$RESULT_JSON"
  else
    warn result_json_failed "$RESULT_JSON"
  fi
  return 0
}

# --waf-dry (caché, pour les tests) : options déjà validées ; lance SEULEMENT le raccordement avec le « toutpanel » trouvé dans le PATH, puis affiche le
# récapitulatif ToutWAF et l'écrit dans $HOME_DIR/data/install-info.txt. Ni paquet, ni service, ni pare-feu, ni droit root.
if [[ $WAF_DRY -eq 1 ]]; then
  if [[ $WAF_REMOTE -eq 0 ]]; then say waf_opts_need_console "--waf-dry"; exit 1; fi
  WAF_RESTRICT_OK=$WAF_RESTRICT
  step st_waf_remote
  waf_connect "$(command -v toutpanel || printf toutpanel)"
  mkdir -p "$HOME_DIR/data"
  waf_info_lines 26 "" 1 > "$HOME_DIR/data/install-info.txt"
  waf_info_lines 26 "  "
  write_result_json waf-dry
  waf_strict_exit
  exit 0
fi

if [[ $RANDOM_PORT -eq 1 ]]; then PORT=$(( (RANDOM % 20000) + 20000 )); fi
[[ $NODE -eq 0 && "$HTTPS_PORT" == "$PORT" ]] && HTTPS_PORT=$(( PORT + 1 ))   # les ports HTTP et HTTPS du panel doivent différer

# ------------------------------------------------------------------------------
# Répertoire du panel : /var/toutpanel par défaut. Une installation existante est DÉTECTÉE et conservée telle quelle (jamais déplacée) :
# 1. unité systemd (ou script d'init) qui déclare TOUTPANEL_HOME, 2. /var/toutpanel/data, 3. lien /usr/local/bin/toutpanel -> <home>/venv/bin/toutpanel,
# 4. /www/toutpanel/data (ancien défaut). Même règle que toutpanel.config.default_home pour le CLI. --home DIR / TOUTPANEL_HOME : choix explicite.
# ------------------------------------------------------------------------------
_init_home() {   # répertoire déclaré par l'unité systemd ou le script d'init du panel (TOUTPANEL_HOME=…), vide sinon
  local f l
  for f in "$FS_ROOT/etc/systemd/system/toutpanel.service" "$FS_ROOT/etc/init.d/toutpanel"; do
    [[ -r "$f" ]] || continue
    l=$(grep -m1 -E 'TOUTPANEL_HOME=' "$f" 2>/dev/null) || continue
    l="${l#*TOUTPANEL_HOME=}"; l="${l%%[\"\' ]*}"
    [[ "$l" == /* ]] && { printf '%s' "$l"; return 0; }
  done
  return 0
}
_link_home() {   # répertoire déduit du lien /usr/local/bin/toutpanel
  local t; t=$(readlink "$FS_ROOT/usr/local/bin/toutpanel" 2>/dev/null) || return 0
  case "$t" in */venv/bin/toutpanel) printf '%s' "${t%/venv/bin/toutpanel}";; esac
  return 0
}
# affiche le répertoire d'une installation existante, ou rien
find_existing_home() {
  local c
  for c in "$(_init_home)" "$DEFAULT_HOME" "$(_link_home)" "$LEGACY_HOME"; do
    if [[ -n "$c" && -d "$FS_ROOT$c/data" ]]; then printf '%s' "$c"; return 0; fi
  done
  return 0
}
resolve_home() {
  local found; found=$(find_existing_home)
  if [[ $HOME_SET -eq 1 ]]; then
    if [[ -n "$found" && "$found" != "$HOME_DIR" ]]; then HOME_OTHER="$found"; fi
    return 0
  fi
  if [[ -n "$found" ]]; then
    HOME_DIR="$found"
    if [[ "$found" == "$LEGACY_HOME" ]]; then HOME_LEGACY=1; elif [[ "$found" != "$DEFAULT_HOME" ]]; then HOME_LEGACY=2; fi
  else
    HOME_DIR="$DEFAULT_HOME"
  fi
  return 0
}
resolve_home
# racine des sites : TOUTPANEL_WWW, sinon /www/wwwroot (panel dans le défaut ou l'ancien défaut), sinon à côté du panel (comme toutpanel.config.default_www_root)
WWW_ROOT="${TOUTPANEL_WWW:-}"
if [[ -z "$WWW_ROOT" ]]; then
  case "$HOME_DIR" in "$DEFAULT_HOME"|"$LEGACY_HOME") WWW_ROOT="/www/wwwroot";; *) WWW_ROOT="$(dirname "$HOME_DIR")/wwwroot";; esac
fi
# garde-fou : le répertoire du panel ne doit jamais être un dossier système (il est supprimé par --uninstall)
case "$HOME_DIR" in
  /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|/www|/var/lib|/usr/local|/usr/local/bin) say home_unsafe "$HOME_DIR"; exit 1;;
esac

# mot de passe fourni : mise à jour (ignoré, avertissement) ou contrôle de la politique du panel, AVANT toute modification du serveur
pass_check() {
  local err
  if [[ $UNINSTALL -eq 1 ]]; then return 0; fi
  if [[ $UPDATE -eq 1 || ( $POST_DRY -eq 0 && $REINSTALL -eq 0 && -f "$HOME_DIR/data/settings.json" ) ]]; then
    if [[ $PASS_ARG_SET -eq 1 || $PASS_FILE_SET -eq 1 || $PASS_STDIN -eq 1 || $PASS_ENV_SET -eq 1 ]]; then warn pass_update_ignored; fi
    ADMIN_PASS=""; PASS_SRC="generated"; PASS_KEPT=1
    return 0
  fi
  if [[ "$PASS_SRC" != "generated" ]]; then
    err=$(pass_policy_error "$ADMIN_PASS" "$ADMIN_USER")
    if [[ -n "$err" ]]; then pass_say_error "$err"; exit 1; fi
  fi
  return 0
}
pass_check

# ------------------------------------------------------------------------------
# Détection de la distribution (port de toutpanel/platform/distro.py : mêmes familles, mêmes planchers de version, JAMAIS de plafond :
# une version future d'une famille connue est prise en charge au niveau de la dernière version connue). Lit /etc/os-release
# (ID, ID_LIKE, VERSION_ID, VERSION_CODENAME, UBUNTU_CODENAME, DEBIAN_CODENAME, VARIANT_ID) et non l'ID seul.
# Familles : debian, rhel (dnf), rhel-yum (CentOS / RHEL / Oracle 7), amzn, suse, arch, alpine. Niveaux : full / reduced / unsupported.
# TOUTPANEL_OS_RELEASE_FILE (caché, tests) : fichier os-release factice ; TOUTPANEL_ARCH : architecture factice ; sans ces variables, détection réelle.
# ------------------------------------------------------------------------------
declare -A _OSR=()
OS_RELEASE_FILE="${TOUTPANEL_OS_RELEASE_FILE:-}"
LIVE=1; [[ -n "$OS_RELEASE_FILE" ]] && LIVE=0     # fichier factice : aucune sonde de la machine (init, gestionnaire de paquets)
_read_os_release() {
  local f="" c line k v
  for c in "$OS_RELEASE_FILE" /etc/os-release /usr/lib/os-release; do
    if [[ -n "$c" && -r "$c" ]]; then f="$c"; break; fi
  done
  [[ -n "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in ""|"#"*) continue;; esac
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"; v="${line#*=}"
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    if [[ ${#v} -ge 2 && "${v:0:1}" == "${v: -1}" && ( "${v:0:1}" == '"' || "${v:0:1}" == "'" ) ]]; then v="${v:1:${#v}-2}"; fi
    _OSR[$k]="$v"
  done < "$f"
}
# les (au plus 3) premiers nombres d'un texte : « 20.04 » -> « 20 4 » ; « 3.22.0_alpha » -> « 3 22 0 »
_vt() {
  local s="$1" out="" n=0
  while [[ $n -lt 3 && "$s" =~ ([0-9]+)(.*)$ ]]; do out+="$((10#${BASH_REMATCH[1]})) "; s="${BASH_REMATCH[2]}"; n=$((n + 1)); done
  printf '%s' "$out"
}
# _vge A B : vrai si A >= B (comparaison de tuples : « 20.4 » >= « 20 », « » < « 11 »)
_vge() {
  local -a a b; local i n
  read -r -a a <<<"$(_vt "$1")"; read -r -a b <<<"$(_vt "$2")"
  n=${#a[@]}; if (( ${#b[@]} > n )); then n=${#b[@]}; fi
  for (( i = 0; i < n; i++ )); do
    if (( i >= ${#a[@]} )); then return 1; fi
    if (( i >= ${#b[@]} )); then return 0; fi
    if (( a[i] > b[i] )); then return 0; fi
    if (( a[i] < b[i] )); then return 1; fi
  done
  return 0
}
_lc() { printf '%s' "${1,,}"; }
_enc() { printf '%s' "${1// /%20}"; }   # un argument de raison ne contient pas d'espace (décodé par reason_text)
# _rules CLÉ VERSION : « niveau|codes » (le premier plancher atteint s'applique)
_rules() {
  local tbl="" ent vmin lvl codes
  case "$1" in
    debian)   tbl="11:full: 10:reduced:eol+pyold 0:unsupported:tooold";;
    ubuntu)   tbl="20.04:full: 18.04:reduced:eol+pyold 0:unsupported:tooold";;
    rhel)     tbl="8:full: 7:reduced:eol+yum+pyold 0:unsupported:tooold";;
    almalinux|rocky) tbl="8:full: 0:unsupported:tooold";;
    centos)   tbl="9:full: 7:reduced:eol+yum 0:unsupported:tooold";;
    ol|cloudlinux) tbl="8:full: 7:reduced:eol+yum 0:unsupported:tooold";;
    fedora)   tbl="39:full: 30:reduced:eol 0:unsupported:tooold";;
    amzn)     tbl="2023:reduced:stack_amzn 2:reduced:eol+yum+stack_amzn+pyold 0:unsupported:tooold";;
    opensuse-leap) tbl="15:reduced:stack_suse 0:unsupported:tooold";;
    opensuse-tumbleweed) tbl="0:reduced:stack_suse+rolling";;
    sles)     tbl="15:reduced:stack_suse+pyold 0:unsupported:tooold";;
    arch)     tbl="0:reduced:stack_arch";;
    alpine)   tbl="3.18:reduced:stack_alpine 0:unsupported:tooold";;
    *)        printf 'reduced|'; return 0;;
  esac
  for ent in $tbl; do
    vmin="${ent%%:*}"; ent="${ent#*:}"; lvl="${ent%%:*}"; codes="${ent#*:}"
    if _vge "$2" "$vmin"; then printf '%s|%s' "$lvl" "${codes//+/ }"; return 0; fi
  done
  printf 'unsupported|tooold'
}
_ubuntu_ver() {
  case "$1" in xenial) echo 16.04;; bionic) echo 18.04;; focal) echo 20.04;; jammy) echo 22.04;; noble) echo 24.04;; oracular) echo 24.10;;
    plucky) echo 25.04;; questing) echo 25.10;; resolute) echo 26.04;; *) echo "";; esac
}
_debian_ver() {
  case "$1" in stretch) echo 9;; buster) echo 10;; bullseye) echo 11;; bookworm) echo 12;; trixie) echo 13;; forky) echo 14;; duke) echo 15;; *) echo "";; esac
}
_devuan_map() {
  case "$1" in ascii) echo stretch;; beowulf) echo buster;; chimaera) echo bullseye;; daedalus) echo bookworm;; excalibur) echo trixie;; freia) echo forky;; ceres) echo sid;; *) echo "$1";; esac
}
_oos_name() {
  case "$1" in gentoo) echo "Gentoo (portage)";; void) echo "Void Linux (xbps)";; nixos) echo "NixOS (nix)";; photon) echo "VMware Photon (tdnf)";;
    azurelinux) echo "Azure Linux (tdnf)";; mariner) echo "CBL-Mariner (tdnf)";; clear-linux-os) echo "Clear Linux (swupd)";; slackware) echo "Slackware";;
    mageia) echo "Mageia (urpmi)";; wolfi) echo "Wolfi (apk, glibc sans systemd)";; flatcar) echo "Flatcar (immuable)";; *) echo "";;
  esac
}
_norm_arch() {
  local m; m=$(_lc "$1")
  case "$m" in amd64|x64) echo x86_64;; arm64) echo aarch64;; armv8l|armv8|armhf) echo armv7l;; i386|i486|i586) echo i686;; ppc64el) echo ppc64le;; *) echo "$m";; esac
}
# résultats de detect_distro
FAMILY=""; PM=""; INIT="systemd"; ARCH=""; SUPPORT="full"; SUPPORT_CODES=""
D_ID=""; D_PRETTY=""; D_VERSION=""; D_NAME=""; D_KNOWN=0
BASE_ID=""; BASE_VERSION=""; BASE_CODENAME=""; PY_PROVISION=0; PY_STRATEGY="none"
DISTRO_ID=""; DISTRO_MAJOR="0"
detect_distro() {
  local id like ver cn ucn dcn variant tok c fam="" probed=0 major=0 known=0 name="" rule="" klevel="" kcode="" kinit="" immut=0
  local base_id base_version base_cn rolling=0 level="full" codes="" key lv rs arch_n al ar pmx init_x
  _read_os_release
  id=$(_lc "${_OSR[ID]:-}"); like=$(_lc "${_OSR[ID_LIKE]:-}"); ver="${_OSR[VERSION_ID]:-}"
  cn=$(_lc "${_OSR[VERSION_CODENAME]:-}"); ucn=$(_lc "${_OSR[UBUNTU_CODENAME]:-}"); dcn=$(_lc "${_OSR[DEBIAN_CODENAME]:-}"); variant=$(_lc "${_OSR[VARIANT_ID]:-}")
  D_ID="$id"; D_VERSION="$ver"; D_PRETTY="${_OSR[PRETTY_NAME]:-${_OSR[NAME]:-${id:-Linux}}}"
  arch_n=$(_norm_arch "${TOUTPANEL_ARCH:-$(uname -m 2>/dev/null || true)}"); ARCH="$arch_n"
  # distributions identifiées (id -> famille, nom, clé des planchers, options)
  case "$id" in
    debian) known=1; fam=debian; name=Debian; rule=debian;;
    ubuntu) known=1; fam=debian; name=Ubuntu; rule=ubuntu;;
    raspbian) known=1; fam=debian; name="Raspberry Pi OS"; rule=debian;;
    devuan) known=1; fam=debian; name=Devuan; rule=debian; klevel=reduced; kcode=nosystemd; kinit=sysvinit;;
    kali) known=1; fam=debian; name="Kali Linux"; rule=debian; klevel=reduced; kcode=audit;;
    parrot) known=1; fam=debian; name="Parrot OS"; rule=debian; klevel=reduced; kcode=audit;;
    linuxmint) known=1; fam=debian; name="Linux Mint"; rule=ubuntu;;
    pop) known=1; fam=debian; name="Pop!_OS"; rule=ubuntu;;
    zorin) known=1; fam=debian; name="Zorin OS"; rule=ubuntu;;
    elementary) known=1; fam=debian; name="elementary OS"; rule=ubuntu;;
    neon) known=1; fam=debian; name="KDE neon"; rule=ubuntu;;
    armbian) known=1; fam=debian; name=Armbian; rule=debian;;
    rhel) known=1; fam=rhel; name="Red Hat Enterprise Linux"; rule=rhel;;
    almalinux) known=1; fam=rhel; name=AlmaLinux; rule=almalinux;;
    rocky) known=1; fam=rhel; name="Rocky Linux"; rule=rocky;;
    centos) known=1; fam=rhel; name=CentOS; rule=centos;;
    ol) known=1; fam=rhel; name="Oracle Linux"; rule=ol;;
    cloudlinux) known=1; fam=rhel; name=CloudLinux; rule=cloudlinux;;
    fedora) known=1; fam=rhel; name=Fedora; rule=fedora;;
    amzn) known=1; fam=amzn; name="Amazon Linux"; rule=amzn;;
    opensuse-leap) known=1; fam=suse; name="openSUSE Leap"; rule=opensuse-leap;;
    opensuse-tumbleweed) known=1; fam=suse; name="openSUSE Tumbleweed"; rule=opensuse-tumbleweed;;
    opensuse-slowroll) known=1; fam=suse; name="openSUSE Slowroll"; rule=opensuse-tumbleweed;;
    sles) known=1; fam=suse; name="SUSE Linux Enterprise Server"; rule=sles;;
    sled) known=1; fam=suse; name="SUSE Linux Enterprise Desktop"; rule=sles;;
    arch) known=1; fam=arch; name="Arch Linux"; rule=arch;;
    manjaro) known=1; fam=arch; name=Manjaro; rule=arch;;
    endeavouros) known=1; fam=arch; name=EndeavourOS; rule=arch;;
    cachyos) known=1; fam=arch; name=CachyOS; rule=arch;;
    garuda) known=1; fam=arch; name="Garuda Linux"; rule=arch;;
    artix) known=1; fam=arch; name="Artix Linux"; rule=arch; kinit=openrc;;
    alpine) known=1; fam=alpine; name="Alpine Linux"; rule=alpine; kinit=openrc;;
    sl-micro) known=1; fam=suse; name="SUSE Linux Micro"; rule=sles; klevel=unsupported; immut=1;;
    opensuse-microos) known=1; fam=suse; name="openSUSE MicroOS"; rule=opensuse-tumbleweed; klevel=unsupported; immut=1;;
    opensuse-aeon) known=1; fam=suse; name="openSUSE Aeon"; rule=opensuse-tumbleweed; klevel=unsupported; immut=1;;
  esac
  if [[ $known -eq 0 ]]; then   # distribution inconnue : famille déduite de ID_LIKE (ou de l'ID)
    fam="unknown"; name="${_OSR[NAME]:-${id:-Linux}}"
    for tok in $id $like; do
      case "$tok" in debian|ubuntu) fam=debian; break;; rhel|centos|fedora) fam=rhel; break;; suse|opensuse) fam=suse; break;; arch|archlinux) fam=arch; break;; alpine) fam=alpine; break;; esac
    done
    if [[ "$fam" == "unknown" && $LIVE -eq 1 ]]; then   # dernier recours : le gestionnaire de paquets présent
      for tok in apt-get:debian dnf:rhel yum:rhel-yum zypper:suse pacman:arch apk:alpine; do
        if command -v "${tok%%:*}" >/dev/null 2>&1; then fam="${tok#*:}"; probed=1; break; fi
      done
    fi
  fi
  if [[ "$ver" =~ ([0-9]+) ]]; then major=$((10#${BASH_REMATCH[1]})); fi
  base_id="$id"; base_version="$ver"; base_cn=""; if [[ -z "$ver" ]]; then rolling=1; fi
  if [[ "$fam" == "rhel" || "$fam" == "amzn" ]]; then
    if [[ "$id" == "amzn" ]]; then fam=amzn; base_id=amzn; base_version="$ver"
    else
      if [[ "$id" == fedora || $major -ge 25 ]]; then base_id=fedora; else base_id=el; fi
      base_version="$ver"
      if [[ "$base_id" == fedora || $major -ge 8 || $major -eq 0 ]]; then fam=rhel; else fam=rhel-yum; fi
    fi
  elif [[ "$fam" == "debian" ]]; then
    rolling=0
    if [[ "$id" == ubuntu || -n "$ucn" ]]; then
      c="${ucn:-$cn}"; base_id=ubuntu
      if [[ "$id" == ubuntu ]]; then base_version="$ver"; else base_version=$(_ubuntu_ver "$c"); fi
      if [[ -z "$base_version" && "$id" =~ ^(pop|elementary|neon|tuxedo|ubuntu-budgie)$ && "$ver" =~ ^[0-9]+\.[0-9]+$ ]]; then base_version="$ver"; fi
      [[ -z "$base_version" ]] && base_version=$(_ubuntu_ver "$c")
      base_cn="$c"
    else
      c="$dcn"; [[ -z "$c" ]] && c=$(_devuan_map "$cn")
      base_id=debian; base_version=""; base_cn="$c"; rolling=1
      if [[ "$id" =~ ^(debian|raspbian|armbian|pve|proxmox)$ && "$ver" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        base_version="${ver%%.*}"; rolling=0
        if [[ -z "$(_debian_ver "$c")" ]]; then
          for tok in stretch buster bullseye bookworm trixie forky duke; do [[ "$(_debian_ver "$tok")" == "$base_version" ]] && { c="$tok"; break; }; done
        fi
        base_cn="$c"
      elif [[ "$id" == devuan && -n "$(_debian_ver "$(_devuan_map "$cn")")" ]]; then
        base_cn=$(_devuan_map "$cn"); base_version=$(_debian_ver "$base_cn"); rolling=0
      elif [[ -n "$(_debian_ver "$c")" ]]; then
        base_cn="$c"; base_version=$(_debian_ver "$c"); rolling=0
      else   # testing / sid / codename inconnu (version future) : traité comme la dernière version connue, sans plafond
        case "$c" in sid|testing|unstable|kali-rolling|ceres) base_cn="";; esac
      fi
    fi
  fi
  # --- niveau de support
  if [[ $known -eq 1 ]]; then
    if [[ "$fam" == "debian" ]]; then
      if [[ -n "$klevel" ]]; then level="$klevel"; codes="$kcode"
      else
        key=debian; [[ "$base_id" == ubuntu ]] && key=ubuntu
        if [[ $rolling -eq 1 && -z "$base_version" ]]; then level=full; codes="testing"
        elif [[ -z "$base_version" && "$base_id" == ubuntu ]]; then level=full; codes="recent_ubuntu:$base_cn"
        else rs=$(_rules "$key" "$base_version"); level="${rs%%|*}"; codes="${rs#*|}"; fi
      fi
    else
      lv="$ver"; if [[ -z "$ver" || "$id" == opensuse-tumbleweed || "$id" == opensuse-slowroll ]]; then lv=99999; fi
      if [[ -n "$klevel" ]]; then level="$klevel"; codes="$kcode"
      else rs=$(_rules "$rule" "$lv"); level="${rs%%|*}"; codes="${rs#*|}"; fi
    fi
    if [[ $immut -eq 1 ]]; then level=unsupported; codes="immutable:$(_enc "$name")"; fi
  elif [[ -n "$(_oos_name "$id")" && "$fam" == "unknown" ]]; then
    level=unsupported; codes="outofscope:$(_enc "$(_oos_name "$id")")"
  elif [[ "$fam" == "unknown" ]]; then
    level=unsupported; codes="unknown_distro:$(_enc "${id:-?}")"
  else   # distribution inconnue rattachée à une famille : niveau réduit au plus (non testée)
    if [[ $probed -eq 1 ]]; then level=reduced; codes="untested_pm:$fam"
    elif [[ "$fam" == "debian" && "$base_id" == ubuntu && -z "$base_version" ]]; then level=reduced; codes="untested_base:Ubuntu%20$base_cn"
    elif [[ "$fam" == "debian" && -n "$base_version" ]]; then
      key=debian; [[ "$base_id" == ubuntu ]] && key=ubuntu
      rs=$(_rules "$key" "$base_version"); lv="${rs%%|*}"
      level=reduced; [[ "$lv" == unsupported ]] && level=unsupported
      codes="untested_base:$([[ "$base_id" == ubuntu ]] && echo Ubuntu || echo Debian)%20$base_version"; [[ -n "${rs#*|}" ]] && codes+=" ${rs#*|}"
    else level=reduced; codes="untested_like:$fam"; fi
    if [[ ( "$fam" == "rhel" || "$fam" == "rhel-yum" ) && $major -gt 0 && $major -lt 8 ]]; then level=reduced; codes="eol yum"; fi
  fi
  # --- système immuable (VARIANT_ID)
  case "$variant" in coreos|silverblue|kinoite|sericea|onyx|iot|atomic|cosmic-atomic|silverblue-nonfree) level=unsupported; codes="immutable:$(_enc "$D_PRETTY")";; esac
  # --- init : celui de la distribution, puis les sondes réelles
  init_x="${kinit:-systemd}"
  if [[ $LIVE -eq 1 ]]; then
    if [[ -d /run/systemd/system ]]; then init_x=systemd
    elif [[ -e /run/openrc || -e /sbin/openrc || -e /usr/sbin/openrc ]]; then init_x=openrc
    elif [[ "$init_x" == systemd && "$fam" != unknown && ! ( -e /usr/lib/systemd/system || -e /lib/systemd/system ) ]] && ! command -v systemctl >/dev/null 2>&1; then init_x=sysvinit; fi
  fi
  INIT="$init_x"
  if [[ "$INIT" != systemd && "$level" == full ]]; then level=reduced; codes="${codes:+$codes }noinit:$INIT"; fi
  # --- architecture
  case "$arch_n" in
    x86_64|aarch64) al=full; ar="";;
    armv7l|armv6l|i686|ppc64le|s390x|riscv64) al=reduced; ar="arch:$arch_n";;
    "") al=full; ar="";;
    *) al=reduced; ar="arch:$arch_n";;
  esac
  if [[ "$al" == reduced && "$level" == full ]]; then level=reduced; codes="${codes:+$codes }$ar"
  elif [[ -n "$ar" && "$level" == reduced ]]; then codes="${codes:+$codes }$ar"; fi
  # --- gestionnaire de paquets
  case "$fam" in
    debian) pmx=apt-get;; rhel) pmx=dnf;; rhel-yum) pmx=yum;; suse) pmx=zypper;; arch) pmx=pacman;; alpine) pmx=apk;; *) pmx="";;
  esac
  if [[ "$fam" == "amzn" ]]; then if [[ $major -ge 2022 ]]; then pmx=dnf; else pmx=yum; fi; fi
  if [[ $LIVE -eq 1 && ( "$fam" == rhel || "$fam" == rhel-yum || "$fam" == amzn ) ]]; then
    if command -v dnf >/dev/null 2>&1; then pmx=dnf; elif command -v yum >/dev/null 2>&1; then pmx=yum; fi
  fi
  FAMILY="$fam"; PM="$pmx"; SUPPORT="$level"; SUPPORT_CODES="$codes"; D_NAME="$name"; D_KNOWN=$known
  BASE_ID="$base_id"; BASE_VERSION="$base_version"; BASE_CODENAME="$base_cn"
  DISTRO_ID="$id"; DISTRO_MAJOR="$major"
  if [[ "$fam" == "rhel" || "$fam" == "rhel-yum" || "$fam" == "amzn" ]]; then DISTRO_MAJOR="${base_version%%.*}"; [[ -z "$DISTRO_MAJOR" ]] && DISTRO_MAJOR=0; fi
  # --- Python système < 3.9 : stratégie (paquet récent de la distribution, puis Python autonome)
  PY_PROVISION=0; PY_STRATEGY="none"
  case "$fam" in
    debian) if [[ "$base_id" == ubuntu ]]; then if [[ -n "$base_version" ]] && ! _vge "$base_version" 20.10; then PY_PROVISION=1; PY_STRATEGY="apt+deadsnakes+standalone"; fi
            else if [[ -n "$base_version" ]] && ! _vge "$base_version" 11; then PY_PROVISION=1; PY_STRATEGY="apt+standalone"; fi; fi;;
    rhel|rhel-yum) if [[ "$base_id" == el && -n "$base_version" && $major -lt 9 ]]; then PY_PROVISION=1; PY_STRATEGY="appstream+standalone"; [[ $major -lt 8 ]] && PY_STRATEGY="standalone"; fi;;
    amzn) if [[ "$base_version" == 2 ]]; then PY_PROVISION=1; PY_STRATEGY="standalone"; fi;;
    suse) case "$id" in sles|sled|opensuse-leap) if [[ -n "$ver" && $major -lt 16 ]]; then PY_PROVISION=1; PY_STRATEGY="zypper+standalone"; fi;; esac;;
  esac
  return 0
}
# texte des raisons du niveau de support : codes « code[:argument] » traduits et séparés par « ; » (les espaces d'un argument sont codés « %20 »)
reason_text() {
  local out="" c arg code
  for c in $SUPPORT_CODES; do
    code="${c%%:*}"; arg=""; [[ "$c" == *:* ]] && arg="${c#*:}"; arg="${arg//%20/ }"
    out+="${out:+; }$(msg "dr_$code" "$arg")"
  done
  printf '%s' "$out"
}
detect_distro

# ------------------------------------------------------------------------------
# Paquets, services et utilisateurs web par famille (les noms réellement installés plus bas viennent d'ici ; --dry-run les affiche)
# ------------------------------------------------------------------------------
PK_DEPS=(); PK_BUILD=(); PK_DB=(); PK_REDIS=(); PK_MAIL=(); PK_PG=(); NEED_BUILD=0
SVC_DB="mariadb"; SVC_REDIS="redis"; WEB_USER="www-data"; NGINX_USER="nginx"; APACHE_PKG="apache2"; APACHE_SVC="apache2"
compute_packages() {
  case "$ARCH" in x86_64|aarch64|"") NEED_BUILD=0;; *) NEED_BUILD=1;; esac   # dépendances Python compilées à l'installation (pas de roues binaires)
  case "$FAMILY" in
    debian)
      PK_DEPS=(python3 python3-venv python3-pip git curl ca-certificates unzip tar gnupg lsb-release)
      PK_BUILD=(build-essential python3-dev libffi-dev libssl-dev pkg-config)
      PK_DB=(mariadb-server mariadb-client); PK_REDIS=(redis-server); SVC_REDIS="redis-server"
      PK_MAIL=(postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd opendkim opendkim-tools); PK_PG=(postgresql postgresql-client)
      WEB_USER="www-data"; NGINX_USER="www-data"; APACHE_PKG="apache2"; APACHE_SVC="apache2";;
    rhel)
      PK_DEPS=(python3 python3-pip git curl ca-certificates unzip tar policycoreutils-python-utils dnf-plugins-core)
      PK_BUILD=(gcc make python3-devel libffi-devel openssl-devel)
      PK_DB=(mariadb-server mariadb); PK_REDIS=(redis); PK_MAIL=(postfix dovecot opendkim opendkim-tools); PK_PG=(postgresql-server postgresql)
      WEB_USER="nginx"; NGINX_USER="nginx"; APACHE_PKG="httpd"; APACHE_SVC="httpd";;
    rhel-yum)
      PK_DEPS=(python3 python3-pip git curl ca-certificates unzip tar policycoreutils-python yum-utils)
      PK_BUILD=(gcc make python3-devel libffi-devel openssl-devel)
      PK_DB=(mariadb-server mariadb); PK_REDIS=(redis); PK_MAIL=(postfix dovecot opendkim opendkim-tools); PK_PG=(postgresql-server postgresql)
      WEB_USER="nginx"; NGINX_USER="nginx"; APACHE_PKG="httpd"; APACHE_SVC="httpd";;
    amzn)
      PK_DEPS=(python3 python3-pip git curl unzip tar ca-certificates)
      PK_BUILD=(gcc make python3-devel libffi-devel openssl-devel)
      if [[ "$PM" == "dnf" ]]; then PK_DB=(mariadb105-server mariadb105); else PK_DB=(mariadb-server mariadb); fi
      PK_REDIS=(redis6); PK_MAIL=(postfix dovecot opendkim); PK_PG=(postgresql15-server postgresql15)
      WEB_USER="nginx"; NGINX_USER="nginx"; APACHE_PKG="httpd"; APACHE_SVC="httpd";;
    suse)
      PK_DEPS=(python3 python3-pip git curl unzip tar ca-certificates)
      PK_BUILD=(gcc make python3-devel libffi-devel libopenssl-devel)
      PK_DB=(mariadb mariadb-client); PK_REDIS=(redis); PK_MAIL=(postfix dovecot opendkim opendkim-tools); PK_PG=(postgresql-server postgresql)
      WEB_USER="wwwrun"; NGINX_USER="nginx"; APACHE_PKG="apache2"; APACHE_SVC="apache2";;
    arch)
      PK_DEPS=(python python-pip git curl unzip tar ca-certificates)
      PK_BUILD=(base-devel libffi openssl)
      PK_DB=(mariadb); PK_REDIS=(redis); PK_MAIL=(postfix dovecot opendkim); PK_PG=(postgresql)
      WEB_USER="http"; NGINX_USER="http"; APACHE_PKG="apache"; APACHE_SVC="httpd";;
    alpine)
      PK_DEPS=(python3 py3-pip git curl unzip tar ca-certificates)
      PK_BUILD=(gcc musl-dev python3-dev libffi-dev openssl-dev)
      PK_DB=(mariadb mariadb-client); PK_REDIS=(redis); PK_MAIL=(postfix dovecot opendkim opendkim-utils); PK_PG=(postgresql postgresql-client)
      WEB_USER="nginx"; NGINX_USER="nginx"; APACHE_PKG="apache2"; APACHE_SVC="apache2";;
  esac
  # Alpine : musl, certaines roues manquent : compilateur toujours installé (comportement historique) ; ailleurs seulement hors x86_64 / aarch64
  if [[ "$FAMILY" == "alpine" ]]; then NEED_BUILD=1; fi
  return 0
}
compute_packages

# ------------------------------------------------------------------------------
# Décisions dérivées des options : pare-feu et pile (arguments exacts des commandes « toutpanel » lancées après l'installation du panel)
# ------------------------------------------------------------------------------
# pile : composer = « toutpanel stack apply » (une option du composeur a été donnée) ; bash = pile historique (--stack full|minimal|none, défaut) ;
# ask = question du profil dans un terminal (aucune option de pile) ; none = panel seul
STACK_MODE="bash"; STACK_ASK=0
resolve_stack_mode() {
  if [[ $STACK_OPTS_SET -eq 1 ]]; then STACK_MODE="composer"
  elif [[ "$STACK" == "none" ]]; then STACK_MODE="none"
  else STACK_MODE="bash"; fi
}
resolve_stack_mode
# arguments de « toutpanel stack apply » : les options du composeur telles que données, plus --yes
STACK_ARGS=()
build_stack_args() {
  STACK_ARGS=()
  if [[ -n "$PROFILE" ]]; then STACK_ARGS+=(--profile "$PROFILE"); fi
  if [[ -n "$WEB" ]]; then STACK_ARGS+=(--web "$WEB"); fi
  if [[ -n "$PHP_VERS" ]]; then STACK_ARGS+=(--php "$PHP_VERS"); fi
  if [[ -n "$PHP_DEFAULT" ]]; then STACK_ARGS+=(--php-default "$PHP_DEFAULT"); fi
  if [[ -n "$PHP_EXT" ]]; then STACK_ARGS+=(--php-ext "$PHP_EXT"); fi
  if [[ -n "$DB" ]]; then STACK_ARGS+=(--db "$DB"); fi
  if [[ $REDIS_OPT -eq 1 ]]; then STACK_ARGS+=(--redis); fi
  if [[ -n "$ACCEL" ]]; then STACK_ARGS+=(--accel "$ACCEL"); fi
  if [[ -n "$FTP" ]]; then STACK_ARGS+=(--ftp "$FTP"); fi
  if [[ -n "$MAIL_ENGINE" ]]; then STACK_ARGS+=(--mail "$MAIL_ENGINE"); elif [[ $MAIL -eq 1 ]]; then STACK_ARGS+=(--mail postfix); fi
  if [[ -n "$DNS" ]]; then STACK_ARGS+=(--dns "$DNS"); fi
  if [[ -n "$SECURITY" ]]; then STACK_ARGS+=(--security "$SECURITY"); fi
  if [[ -n "$RUNTIME" ]]; then STACK_ARGS+=(--runtime "$RUNTIME"); fi
  if [[ -n "$TOOLS" ]]; then STACK_ARGS+=(--tools "$TOOLS"); fi
  if [[ $POSTGRES -eq 1 ]]; then STACK_ARGS+=(--add postgresql); fi
  if [[ -n "$INSTALL_MODE_OPT" ]]; then STACK_ARGS+=(--install-mode "$INSTALL_MODE_OPT"); fi
  if [[ -n "$ROLES" ]]; then STACK_ARGS+=(--roles "$ROLES"); fi
  if [[ -n "$STACK_FILE" ]]; then STACK_ARGS+=(--stack-file "$STACK_FILE"); fi
  if [[ $NO_TUNING -eq 1 ]]; then STACK_ARGS+=(--no-tuning); fi
  if [[ $ACCEPT_LS_LICENSE -eq 1 ]]; then STACK_ARGS+=(--accept-litespeed-license); fi
  STACK_ARGS+=(--yes)
}
# arguments de « toutpanel setup » liés au pare-feu (installation neuve seulement : une mise à jour ne touche jamais au pare-feu)
FW_SETUP_ARGS=()
build_fw_setup_args() {
  FW_SETUP_ARGS=()
  case "$FW_MODE" in
    panel) FW_SETUP_ARGS=(--firewall panel); if [[ -n "$FIREWALL_ENGINE" ]]; then FW_SETUP_ARGS+=(--firewall-engine "$FIREWALL_ENGINE"); fi;;
    external) FW_SETUP_ARGS=(--firewall external);;
    *) FW_SETUP_ARGS=(--firewall later);;
  esac
}
# ports que « toutpanel firewall enable » doit ouvrir en plus de ceux que le panel connaît (services actifs) : courrier, consoles de WAF locaux
FW_ENABLE_ARGS=()
build_fw_enable_args() {
  FW_ENABLE_ARGS=(enable)
  local p
  if [[ $MAIL -eq 1 || ( -n "$MAIL_ENGINE" && "$MAIL_ENGINE" != "none" && "$MAIL_ENGINE" != "relay" ) ]]; then
    for p in 25 465 587 143 993 110 995; do FW_ENABLE_ARGS+=(--port "$p"); done
  fi
  [[ "$WAF" == "bunkerweb" ]] && FW_ENABLE_ARGS+=(--port 7000)
  [[ "$WAF" == "safeline" || ( "$WAF" == "toutwaf" && $WAF_REMOTE -eq 0 ) ]] && FW_ENABLE_ARGS+=(--port 9443)   # console de ToutWAF local (distant : rien à ouvrir ici)
  # 80 / 443 restreints à ToutWAF distant (restriction active) : jamais rouverts à tout le monde
  if [[ -n "$WAF_FW_IPS" ]]; then FW_ENABLE_ARGS+=(--no-web); fi
  return 0
}
# commande affichable (arguments protégés pour être recopiés dans un terminal)
_cmdline() { local out="" a; for a in "$@"; do out+="$(printf '%q' "$a") "; done; printf '%s' "${out% }"; }

# ------------------------------------------------------------------------------
# --dry-run : détection de la distribution, répertoire, pare-feu, pile et commandes qui seraient lancées ; rien n'est modifié, aucun droit root requis.
# TOUTPANEL_DRY_RUN_FORMAT=env (caché, tests) : lignes CLÉ=valeur stables à la place du texte traduit.
# ------------------------------------------------------------------------------
plan_fw_label() {
  case "$FW_MODE" in
    panel) msg fw_val_panel "${FIREWALL_ENGINE:-auto}";;
    external) msg fw_val_external;;
    *) if [[ $FW_ASK_OK -eq 1 ]]; then msg fw_val_ask; else msg fw_val_later; fi;;
  esac
}
FW_ASK_OK=0   # 1 : la question du pare-feu sera posée (terminal interactif, sans --yes)
plan_stack_label() {
  case "$STACK_MODE" in
    composer) msg stack_val_composer "${PROFILE:-custom}";;
    none) msg stack_val_none;;
    *) msg stack_val_default;;
  esac
}
# origine du mot de passe administrateur pour le plan (jamais sa valeur) : generated | arg | env | file | stdin | ask (question posée dans un terminal) | kept (mise à jour)
pass_src_code() {
  if [[ $PASS_KEPT -eq 1 || $UPDATE -eq 1 ]]; then printf kept
  elif [[ "$PASS_SRC" == "generated" && $YES -eq 0 ]] && _has_tty; then printf ask
  else printf '%s' "$PASS_SRC"
  fi
}
dry_run_plan() {
  local fmt="${TOUTPANEL_DRY_RUN_FORMAT:-text}" sf=() fw=() st=() cmd
  build_stack_args; build_fw_setup_args; build_fw_enable_args
  sf=(setup --json --port "$PORT" --https-port "$HTTPS_PORT" "${FW_SETUP_ARGS[@]}")
  if [[ $UPDATE -eq 1 ]]; then sf=(); fi
  if [[ "$fmt" == "env" ]]; then
    printf 'HOME_DIR=%s\nHOME_LEGACY=%s\nHOME_SET=%s\nHOME_OTHER=%s\nWWW_ROOT=%s\n' "$HOME_DIR" "$HOME_LEGACY" "$HOME_SET" "$HOME_OTHER" "$WWW_ROOT"
    printf 'D_ID=%s\nD_VERSION=%s\nFAMILY=%s\nPM=%s\nINIT=%s\nARCH=%s\nSUPPORT=%s\nSUPPORT_CODES=%s\n' "$D_ID" "$D_VERSION" "$FAMILY" "$PM" "$INIT" "$ARCH" "$SUPPORT" "$SUPPORT_CODES"
    printf 'BASE_ID=%s\nBASE_VERSION=%s\nBASE_CODENAME=%s\nDISTRO_MAJOR=%s\nPY_PROVISION=%s\nPY_STRATEGY=%s\n' "$BASE_ID" "$BASE_VERSION" "$BASE_CODENAME" "$DISTRO_MAJOR" "$PY_PROVISION" "$PY_STRATEGY"
    printf 'PK_DEPS=%s\nPK_BUILD=%s\nNEED_BUILD=%s\nPK_DB=%s\nPK_REDIS=%s\nSVC_DB=%s\nSVC_REDIS=%s\nWEB_USER=%s\nAPACHE_PKG=%s\nAPACHE_SVC=%s\n' \
      "${PK_DEPS[*]}" "${PK_BUILD[*]}" "$NEED_BUILD" "${PK_DB[*]}" "${PK_REDIS[*]}" "$SVC_DB" "$SVC_REDIS" "$WEB_USER" "$APACHE_PKG" "$APACHE_SVC"
    printf 'FIREWALL=%s\nFW_MODE=%s\nFW_ENGINE=%s\nSTACK_MODE=%s\n' "$FIREWALL" "$FW_MODE" "$FIREWALL_ENGINE" "$STACK_MODE"
    printf 'SETUP_CMD=%s\n' "$(_cmdline "${sf[@]}")"
    printf 'ADMIN_PASSWORD_SOURCE=%s\n' "$(pass_src_code)"
    printf 'STACK_CMD=%s\n' "$([[ "$STACK_MODE" == composer ]] && _cmdline stack apply "${STACK_ARGS[@]}")"
    printf 'FW_ENABLE_CMD=%s\n' "$([[ "$FW_MODE" == panel ]] && _cmdline firewall "${FW_ENABLE_ARGS[@]}")"
    return 0
  fi
  step dry_title
  printf '  '; kv 26 "$(msg lbl_distro)" "$D_PRETTY ($(msg dry_distro_detail "$D_ID" "$FAMILY" "${PM:--}" "$INIT" "$ARCH"))"
  printf '  '; kv 26 "$(msg lbl_support)" "$(msg "lvl_$SUPPORT")"
  [[ -n "$SUPPORT_CODES" ]] && { printf '  '; kv 26 "" "$(reason_text)"; }
  printf '  '; kv 26 "$(msg lbl_dir)" "$HOME_DIR"
  if [[ $HOME_LEGACY -eq 1 ]]; then printf '  '; kv 26 "" "$(msg home_legacy_kept "$HOME_DIR" "$DEFAULT_HOME")"; fi
  if [[ $HOME_LEGACY -eq 2 ]]; then printf '  '; kv 26 "" "$(msg home_existing_kept "$HOME_DIR")"; fi
  printf '  '; kv 26 "$(msg lbl_python)" "$(if [[ $PY_PROVISION -eq 1 ]]; then msg dry_python_provision "$PY_STRATEGY"; else msg dry_python_system; fi)"
  printf '  '; kv 26 "$(msg lbl_firewall)" "$(if [[ $UPDATE -eq 1 ]]; then msg fw_update_unchanged; else plan_fw_label; fi)"
  printf '  '; kv 26 "$(msg lbl_stack)" "$(plan_stack_label)"
  printf '  '; kv 26 "$(msg lbl_pass)" "$(msg "pass_src_$(pass_src_code)")"
  printf '\n  %s\n' "$(msg dry_cmds)"
  [[ ${#sf[@]} -gt 0 ]] && printf '    toutpanel %s\n' "$(_cmdline "${sf[@]}")"
  [[ "$STACK_MODE" == composer ]] && printf '    toutpanel %s\n' "$(_cmdline stack apply "${STACK_ARGS[@]}")"
  [[ "$FW_MODE" == panel && $UPDATE -eq 0 ]] && printf '    toutpanel %s\n' "$(_cmdline firewall "${FW_ENABLE_ARGS[@]}")"
  [[ "$FW_MODE" == external && $UPDATE -eq 0 ]] && printf '    toutpanel firewall ports\n'
  if [[ "$SUPPORT" == "unsupported" ]]; then printf '\n  %s\n  %s\n' "$(msg distro_refused "$D_PRETTY" "$(reason_text)")" "$(msg distro_refused_hint)"; fi
  printf '\n  %s\n' "$(msg dry_nothing)"
  return 0
}
if [[ $DRY_RUN -eq 1 ]]; then
  # le mode de pare-feu qui serait retenu sans terminal (une question n'est jamais posée en --dry-run)
  case "$FIREWALL" in on) FW_MODE=panel;; off) FW_MODE=external;; *) FW_MODE=later;; esac
  dry_run_plan
  case "$SUPPORT" in unsupported) exit 1;; esac
  exit 0
fi


# ------------------------------------------------------------------------------
# Présentation, état de l'installation et menu
# ------------------------------------------------------------------------------
banner() {
  printf '\n'
  printf "${CB}  ████████╗ ██████╗ ██╗   ██╗████████╗██████╗  █████╗ ███╗   ██╗███████╗██╗     ${C0}\n"
  printf "${CB}  ╚══██╔══╝██╔═══██╗██║   ██║╚══██╔══╝██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     ${C0}\n"
  printf "${CB}     ██║   ██║   ██║██║   ██║   ██║   ██████╔╝███████║██╔██╗ ██║█████╗  ██║     ${C0}\n"
  printf "${CC}     ██║   ██║   ██║██║   ██║   ██║   ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     ${C0}\n"
  printf "${CC}     ██║   ╚██████╔╝╚██████╔╝   ██║   ██║     ██║  ██║██║ ╚████║███████╗███████╗${C0}\n"
  printf "${CC}     ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝${C0}\n"
  printf "${CW}  %s${C0}\n" "$(msg tagline)"
  printf "${CD}  https://toutpanel.com · https://github.com/qu3ntin01/toutpanel${C0}\n"
  printf "${CD}  %s${C0}\n\n" "$(msg lang_line "$(msg lang_name)" "$(msg "lang_src_$LANG_SRC")" "--lang")"
}
intro() {
  printf "${CW}  %s${C0}\n" "$(msg intro_title)"
  printf "  %s\n" "$(msg intro_lead)"
  printf "   ${CG}•${C0} %s\n" "$(msg intro_b1 "Nginx / Apache")"
  printf "   ${CG}•${C0} %s\n" "$(msg intro_b2)"
  printf "   ${CG}•${C0} %s\n" "$(msg intro_b3)"
  printf "   ${CG}•${C0} %s\n" "$(msg intro_b4)"
  printf "  %s\n\n" "$(msg intro_end "$(msg intro_stack_linux)")"
}
EXISTING=0; EXISTING_VERSION=""
if [[ -f "$HOME_DIR/data/settings.json" ]]; then
  EXISTING=1
  EXISTING_VERSION=$("$HOME_DIR/venv/bin/toutpanel" --version 2>/dev/null || true)
fi
banner
if [[ $EXISTING -eq 1 ]]; then
  printf "  ${CG}●${C0} %s\n\n" "$(msg state_existing "${CW}${HOME_DIR}${C0}" "${EXISTING_VERSION:-$(msg unknown)}")"
else
  printf "  ${CY}○${C0} %s\n\n" "$(msg state_none "${CW}${HOME_DIR}${C0}")"
fi
# répertoire : installation existante conservée là où elle est (jamais déplacée) ; installation existante ailleurs que dans --home
if [[ $HOME_LEGACY -eq 1 && $UNINSTALL -eq 0 ]]; then printf "  %s\n\n" "$(msg home_legacy_kept "$HOME_DIR" "$DEFAULT_HOME")"; fi
if [[ $HOME_LEGACY -eq 2 && $UNINSTALL -eq 0 ]]; then printf "  %s\n\n" "$(msg home_existing_kept "$HOME_DIR")"; fi
if [[ -n "$HOME_OTHER" && $UNINSTALL -eq 0 ]]; then warn home_other_install "$HOME_OTHER" "$HOME_DIR"; fi

# Menu interactif : seulement dans un terminal, sans option de mode ni --yes (curl | bash lit le clavier via /dev/tty).
if [[ $YES -eq 0 && $UPDATE -eq 0 && $REINSTALL -eq 0 && $UNINSTALL -eq 0 ]] && [[ -r /dev/tty && -w /dev/tty ]] && { exec 3</dev/tty; } 2>/dev/null; then
  intro
  printf "${CW}  %s${C0}\n" "$(msg menu_title)"
  if [[ $EXISTING -eq 1 ]]; then
    printf "   ${CC}1${C0}) %s  ${CD}(%s)${C0}\n" "$(msg m_update)" "$(msg m_update_d)"
    printf "   ${CC}2${C0}) %s  ${CD}(%s)${C0}\n" "$(msg m_reinstall)" "$(msg m_reinstall_d "$HOME_DIR")"
    printf "   ${CC}3${C0}) %s  ${CD}(%s)${C0}\n" "$(msg m_uninstall)" "$(msg m_uninstall_d)"
    printf "   ${CC}4${C0}) %s\n" "$(msg m_quit)"
    DEFAULT_CHOICE=1
  else
    printf "   ${CC}1${C0}) %s  ${CD}(%s)${C0}\n" "$(msg m_install)" "$(msg m_install_d_linux)"
    printf "   ${CC}2${C0}) %s  ${CD}(%s)${C0}\n" "$(msg m_panel_only)" "$(msg m_panel_only_d)"
    printf "   ${CC}3${C0}) %s\n" "$(msg m_quit)"
    DEFAULT_CHOICE=1
  fi
  printf '  %s' "$(msg menu_choice "$DEFAULT_CHOICE")"
  read -r CHOICE <&3 || CHOICE=""
  CHOICE="${CHOICE:-$DEFAULT_CHOICE}"
  if [[ $EXISTING -eq 0 && "$CHOICE" == "1" && $POSTGRES -eq 0 ]]; then
    printf '  %s' "$(msg ask_postgres "$(msg yn_hint)")"
    read -r PG_CHOICE <&3 || PG_CHOICE=""
    is_yes "$PG_CHOICE" && POSTGRES=1
  fi
  if [[ $EXISTING -eq 0 && ( "$CHOICE" == "1" || "$CHOICE" == "2" ) && $NODE -eq 0 ]]; then
    printf '  %s' "$(msg ask_node "$(msg yn_hint)")"
    read -r NODE_CHOICE <&3 || NODE_CHOICE=""
    is_yes "$NODE_CHOICE" && NODE=1
  fi
  exec 3<&-
  echo
  if [[ $EXISTING -eq 1 ]]; then
    case "$CHOICE" in
      1) UPDATE=1;;
      2) REINSTALL=1;;
      3) UNINSTALL=1;;
      *) printf '  %s\n' "$(msg goodbye)"; exit 0;;
    esac
  else
    case "$CHOICE" in
      1) ;;
      2) STACK="none"; STACK_SET=1;;
      *) printf '  %s\n' "$(msg goodbye)"; exit 0;;
    esac
  fi
fi

# ------------------------------------------------------------------------------
# Désinstallation
# ------------------------------------------------------------------------------
if [[ $UNINSTALL -eq 1 ]]; then
  step st_uninstall
  if [[ $EXISTING -eq 0 && ! -d "$HOME_DIR" ]]; then printf '  %s\n' "$(msg un_nothing "$HOME_DIR")"; exit 0; fi
  printf '  %s\n' "$(msg un_remove "$HOME_DIR")"
  printf '  %s\n' "$(msg un_keep)"
  if [[ $YES -eq 0 ]]; then
    if [[ -r /dev/tty ]]; then
      CONFIRM_WORD=$(msg confirm_word)
      printf '\n  %s' "$(msg un_confirm "${CW}${CONFIRM_WORD}${C0}")"; read -r CONFIRM </dev/tty || CONFIRM=""
    else
      printf '  %s\n' "$(msg un_no_tty)"; exit 1
    fi
    # le mot affiché dans la langue choisie, ou « yes » / « oui » quelle que soit la langue
    [[ "$CONFIRM" == "$CONFIRM_WORD" || "$CONFIRM" == "yes" || "$CONFIRM" == "oui" ]] || { printf '  %s\n' "$(msg un_cancelled)"; exit 0; }
  fi
  ARCHIVE="/root/toutpanel-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
  if [[ -d "$HOME_DIR/data" ]]; then
    # archive des données du panel AVANT toute suppression : si elle échoue (disque plein…), on s'arrête sans rien supprimer
    if tar -czf "$ARCHIVE" -C "$HOME_DIR" data $( [[ -d "$HOME_DIR/ssl" ]] && echo ssl ) $( [[ -d "$HOME_DIR/vhost" ]] && echo vhost ) $( [[ -d "$HOME_DIR/templates" ]] && echo templates ) 2>/dev/null && chmod 600 "$ARCHIVE"; then
      log un_archived "$ARCHIVE"
    else
      rm -f "$ARCHIVE"; warn un_archive_failed "$ARCHIVE"; exit 1
    fi
  fi
  systemctl disable --now toutpanel >/dev/null 2>&1 || true
  if [[ -x /etc/init.d/toutpanel ]]; then   # OpenRC (Alpine, Artix…) ou sysvinit (Devuan…)
    rc-service toutpanel stop >/dev/null 2>&1 || service toutpanel stop >/dev/null 2>&1 || true
    rc-update del toutpanel default >/dev/null 2>&1 || update-rc.d -f toutpanel remove >/dev/null 2>&1 || true
    rm -f /etc/init.d/toutpanel
  fi
  [[ -f "$HOME_DIR/data/panel.pid" ]] && kill "$(cat "$HOME_DIR/data/panel.pid")" 2>/dev/null || true
  rm -f /etc/systemd/system/toutpanel.service /etc/logrotate.d/toutpanel
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -f /etc/nginx/conf.d/toutpanel_*.conf /etc/apache2/sites-enabled/toutpanel_*.conf /etc/apache2/sites-available/toutpanel_*.conf /etc/httpd/conf.d/toutpanel_*.conf
  (nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1) || true
  (command -v apachectl >/dev/null && apachectl -t >/dev/null 2>&1 && apachectl graceful >/dev/null 2>&1) || true
  rm -f /usr/local/bin/toutpanel
  rm -rf "$HOME_DIR"
  echo
  printf "${CG}  %s${C0}\n" "$(msg un_done)"
  [[ -f "$ARCHIVE" ]] && printf '  %s\n' "$(msg un_archive_info "$ARCHIVE")"
  printf '  %s\n' "$(msg un_kept)"
  echo
  exit 0
fi

# ToutWAF distant : jeton (sans écho) et confirmation de la restriction du pare-feu, demandés AVANT toute modification du serveur
if [[ $WAF_REMOTE -eq 1 ]]; then waf_prompts; fi

# ------------------------------------------------------------------------------
# Version précise : résolution AVANT toute modification du serveur (sauvegarde, paquets, panel)
# ------------------------------------------------------------------------------
if [[ -n "$NORM" ]]; then
  if [[ -n "$SRC" ]] || [[ -f "$(dirname "$0")/pyproject.toml" ]] || [[ -f "$(dirname "$0")/version.json" && -d "$(dirname "$0")/dist" ]]; then
    warn version_ignored; VERSION=""; NORM=""
  else
    ensure_git || exit 1
    resolve_or_die
    log version_resolved "$NORM" "${RES_SHA:0:12}" "$RES_BRANCH"
    # préversion (a / b / rc) : canal dev, sauf canal explicite ; version stable : le canal stable est conservé
    if [[ -z "$CHANNEL" ]]; then if [[ "$RES_BRANCH" == "dev" ]]; then CHANNEL="dev"; else CHANNEL="stable"; fi; fi
  fi
fi

# ------------------------------------------------------------------------------
# Installation existante ? → mode mise à jour (données, comptes et réglages conservés)
# ------------------------------------------------------------------------------
if [[ $REINSTALL -eq 0 && -f "$HOME_DIR/data/settings.json" ]]; then UPDATE=1; fi
if [[ $UPDATE -eq 1 ]]; then
  if [[ ! -f "$HOME_DIR/data/settings.json" ]]; then say no_install_update "$HOME_DIR" "--update"; exit 1; fi
  log update_detected "$HOME_DIR"
  [[ $STACK_SET -eq 0 && $STACK_OPTS_SET -eq 0 ]] && STACK="none"     # la pile n'est réinstallée que sur demande explicite (--stack …, --profile …)
  BK="$HOME_DIR/backup/panel-update-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$BK" && cp -a "$HOME_DIR/data" "$BK/" && chmod -R go-rwx "$BK"
  log data_backed_up "$BK"
  if [[ -f "$HOME_DIR/data/settings.json" ]]; then
    PORT=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('panel_port', 8888))" "$HOME_DIR/data/settings.json" 2>/dev/null || echo "$PORT")
  fi
fi
# descente de version (--version plus ancienne que la version installée) : avertissement et confirmation, sauf --yes
if [[ -n "$NORM" && -x "$HOME_DIR/venv/bin/toutpanel" ]]; then
  CUR_VER=$("$HOME_DIR/venv/bin/toutpanel" --version 2>/dev/null | head -1 || true)
  CUR_NORM=$(normalize_version "$CUR_VER" 2>/dev/null || true)
  if [[ -n "$CUR_NORM" && "$(version_cmp "$CUR_NORM" "$NORM")" == "1" ]]; then
    warn version_downgrade "$CUR_NORM" "$NORM"
    if [[ $YES -eq 0 ]]; then
      if [[ -r /dev/tty ]]; then
        printf '  %s' "$(msg ask_downgrade "$(msg yn_hint)")"; read -r DOWN_ANS </dev/tty || DOWN_ANS=""
        is_yes "$DOWN_ANS" || { printf '  %s\n' "$(msg downgrade_cancelled)"; exit 0; }
      else
        printf '  %s\n' "$(msg downgrade_no_tty)"; exit 1
      fi
    fi
  fi
fi

# ------------------------------------------------------------------------------
# Décisions et questions du mode interactif posées AVANT toute modification du serveur : mode du pare-feu, profil de la pile.
# Pare-feu : « on » = ToutPanel le gère, « off » = pare-feu en amont (aucune commande système de pare-feu), « ask » = question à 3 choix
# (ToutPanel / en amont / plus tard). Sans option : question dans un terminal ; sans terminal, ou avec --yes sans valeur : « plus tard »
# (mode non choisi, rien n'est touché). Mise à jour : le pare-feu existant n'est JAMAIS modifié. Jamais d'activation d'ufw sans --firewall on
# (ou choix « ToutPanel » à la question).
# ------------------------------------------------------------------------------
fw_decide() {
  local ans=""
  FW_MODE=""
  if [[ $UPDATE -eq 1 ]]; then
    if [[ -n "$FIREWALL" && "$FIREWALL" != "ask" ]]; then warn fw_update_ignored; fi
    return 0
  fi
  case "$FIREWALL" in
    on) FW_MODE=panel; return 0;;
    off) FW_MODE=external; return 0;;
  esac
  FW_MODE=later
  if [[ $YES -eq 1 ]] || ! _has_tty; then return 0; fi
  printf '\n  %s\n' "$(msg fw_q_title)"
  printf '   %s1%s) %s\n' "$CC" "$C0" "$(msg fw_q_panel)"
  printf '   %s2%s) %s\n' "$CC" "$C0" "$(msg fw_q_external)"
  printf '   %s3%s) %s\n' "$CC" "$C0" "$(msg fw_q_later)"
  printf '  %s' "$(msg fw_q_prompt 3)"
  read -r ans </dev/tty || ans=""
  case "${ans:-3}" in 1) FW_MODE=panel;; 2) FW_MODE=external;; *) FW_MODE=later;; esac
  printf '\n'
  return 0
}
# mot de passe de l'administrateur : question posée dans un terminal quand aucune source n'est fournie (installation neuve, sans --yes) ; saisie sans écho, avec confirmation
pass_decide() {
  local ans="" p1="" p2="" tries=0 err=""
  if [[ $UPDATE -eq 1 || $PASS_KEPT -eq 1 || -n "$ADMIN_PASS" || $YES -eq 1 ]] || ! _has_tty; then return 0; fi
  { set +x; } 2>/dev/null   # la saisie ne doit jamais apparaître dans une trace d'exécution (bash -x)
  printf '\n  %s\n' "$(msg pass_q_title)"
  printf '   %s1%s) %s\n' "$CC" "$C0" "$(msg pass_q_generate)"
  printf '   %s2%s) %s\n' "$CC" "$C0" "$(msg pass_q_type)"
  printf '  %s' "$(msg fw_q_prompt 1)"
  read -r ans </dev/tty || ans=""
  if [[ "${ans:-1}" != "2" ]]; then printf '\n'; return 0; fi
  while [[ $tries -lt 3 ]]; do
    tries=$(( tries + 1 ))
    printf '  %s' "$(msg pass_prompt1)" >/dev/tty
    IFS= read -rs p1 </dev/tty || p1=""
    printf '\n' >/dev/tty
    err=$(pass_policy_error "$p1" "$ADMIN_USER")
    if [[ -z "$p1" ]]; then continue; fi
    if [[ -n "$err" ]]; then pass_say_error "$err"; continue; fi
    printf '  %s' "$(msg pass_prompt2)" >/dev/tty
    IFS= read -rs p2 </dev/tty || p2=""
    printf '\n' >/dev/tty
    if [[ "$p1" != "$p2" ]]; then say pass_mismatch; continue; fi
    ADMIN_PASS="$p1"; PASS_SRC="prompt"; p1=""; p2=""
    return 0
  done
  say pass_prompt_failed
  exit 1
}
pass_decide
fw_decide
if [[ "$FW_MODE" != "panel" && -n "$FIREWALL_ENGINE" && $UPDATE -eq 0 ]]; then warn fw_engine_ignored "$FIREWALL_ENGINE"; fi
resolve_stack_mode
# profil de la pile demandé dans un terminal, après le démarrage du panel (la liste vient de « toutpanel stack profiles »), quand aucune option de pile n'est donnée
STACK_ASK=0
if [[ "$STACK_MODE" == "bash" && $STACK_SET -eq 0 && $STACK_OPTS_SET -eq 0 && $UPDATE -eq 0 && $YES -eq 0 ]] && _has_tty; then STACK_ASK=1; fi

# ------------------------------------------------------------------------------
# Fonctions : gestionnaire de paquets et de services, Python 3.9+, pile historique, étapes qui suivent l'installation du panel
# ------------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
pkg_install() {
  case "$FAMILY" in
    debian)   apt-get install -y -qq "$@";;
    rhel)     dnf install -y --allowerasing "$@";;
    rhel-yum) yum install -y "$@";;                                   # yum (CentOS / RHEL / Oracle 7) ne connaît pas --allowerasing
    amzn)     if [[ "$PM" == "dnf" ]]; then dnf install -y --allowerasing "$@"; else yum install -y "$@"; fi;;
    arch)     pacman -S --noconfirm --needed "$@";;
    alpine)   apk add --no-cache "$@";;
    suse)     zypper --non-interactive install "$@";;
  esac
}
pkg_update() {
  case "$FAMILY" in
    debian) apt-get update -qq || warn pkg_update_failed;;   # Debian 10 / Ubuntu 18.04 : dépôts archivés, l'échec n'est pas bloquant
    rhel|amzn) "$PM" makecache -q || true;;
    rhel-yum) yum makecache -q || true;;
    arch)   pacman -Sy --noconfirm;;
    alpine) apk update;;
    suse)   zypper --non-interactive refresh || true;;
    *) true;;
  esac
}
# gestionnaire de services : systemd, sinon OpenRC (Alpine, Artix), sinon sysvinit / « service » (Devuan, conteneurs sans systemd)
use_systemd() { command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; }
use_openrc() { command -v rc-update >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1; }
svc_enable() {
  local s
  for s in "$@"; do
    if use_systemd; then
      systemctl enable --now "$s" >/dev/null 2>&1 || service "$s" start >/dev/null 2>&1 || true
    elif use_openrc; then
      rc-update add "$s" default >/dev/null 2>&1 || true
      rc-service "$s" start >/dev/null 2>&1 || true
    else
      update-rc.d "$s" defaults >/dev/null 2>&1 || chkconfig "$s" on >/dev/null 2>&1 || true
      service "$s" start >/dev/null 2>&1 || true
    fi
  done
}
# IPv6 désactivé dans le noyau (ipv6.disable=1, certains VPS et conteneurs) : les configurations livrées par les distributions
# écoutent sur [::] (serveur nginx par défaut, dovecot) et le service refuse alors de démarrer (« Address family not supported »).
ipv6_ok() { [[ -e /proc/net/if_inet6 ]]; }
# paquet disponible (Debian / Ubuntu) : un candidat existe dans les dépôts configurés
apt_has() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { c = $2 } END { exit !(c != "" && c != "(none)") }'; }

# Dépôts complémentaires de la famille RHEL (EPEL + CRB) ; inutile sur Fedora et sur Amazon Linux
rhel_prepare() {
  [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]] || return 0
  [[ "$BASE_ID" == "fedora" ]] && return 0
  if ! rpm -q epel-release >/dev/null 2>&1 && ! rpm -q "oracle-epel-release-el${DISTRO_MAJOR}" >/dev/null 2>&1; then
    case "$DISTRO_ID" in
      rhel)
        "$PM" install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${DISTRO_MAJOR}.noarch.rpm" >/dev/null 2>&1 || true
        subscription-manager repos --enable "codeready-builder-for-rhel-${DISTRO_MAJOR}-$(uname -m)-rpms" >/dev/null 2>&1 || true;;
      ol)
        "$PM" install -y "oracle-epel-release-el${DISTRO_MAJOR}" >/dev/null 2>&1 || true
        "$PM" config-manager --set-enabled "ol${DISTRO_MAJOR}_codeready_builder" >/dev/null 2>&1 || true;;
      *)
        "$PM" install -y epel-release >/dev/null 2>&1 || true
        "$PM" config-manager --set-enabled crb >/dev/null 2>&1 || "$PM" config-manager --set-enabled powertools >/dev/null 2>&1 || true;;
    esac
  fi
}
# Dépôt Remi (PHP multi-versions) sur la famille RHEL (numérotation Fedora ou EL)
remi_prepare() {
  [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]] || return 0
  rpm -q remi-release >/dev/null 2>&1 && return 0
  if [[ "$BASE_ID" == "fedora" ]]; then
    "$PM" install -y "https://rpms.remirepo.net/fedora/remi-release-${DISTRO_MAJOR}.rpm" >/dev/null 2>&1 || true
  else
    "$PM" install -y "https://rpms.remirepo.net/enterprise/remi-release-${DISTRO_MAJOR}.rpm" >/dev/null 2>&1 || true
  fi
}

# ------------------------------------------------------------------------------
# Python 3.9+ pour le panel. Stratégie sur les systèmes trop anciens (Debian 10, Ubuntu 18.04 / 20.04, RHEL / Alma / Rocky / CentOS 7-8,
# Amazon Linux 2, SLES / Leap 15) : (1) paquet Python récent de la distribution (AppStream, python311 zypper, dépôts Ubuntu puis deadsnakes),
# (2) à défaut Python autonome (uv + python-build-standalone, vérifié par SHA-256) dans <home>/python, seulement si l'utilisateur l'accepte
# (--yes ou question) ; sinon refus clair. L'interpréteur retenu est PY_BIN (il crée l'environnement virtuel du panel).
# ------------------------------------------------------------------------------
PY_BIN=""
PY_STANDALONE=0                                              # 1 : Python autonome installé dans <home>/python
UV_BASE="${TOUTPANEL_UV_BASE_URL:-https://github.com/astral-sh/uv/releases/latest/download}"   # (avancé) miroir de uv
UV_PY_VERSION="${TOUTPANEL_STANDALONE_PYTHON:-3.12}"
_py_ok() { "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; }
_py_ver() { "$1" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true; }
# premier interpréteur >= 3.9 : celui de l'environnement existant, python3, puis python3.14 … python3.9
find_python() {
  local c p
  if [[ -x "$HOME_DIR/venv/bin/python" ]] && _py_ok "$HOME_DIR/venv/bin/python"; then PY_BIN="$HOME_DIR/venv/bin/python"; return 0; fi
  for c in python3 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9; do
    p=$(command -v "$c" 2>/dev/null) || continue
    if _py_ok "$p"; then PY_BIN="$p"; return 0; fi
  done
  return 1
}
# deadsnakes (Ubuntu et dérivés) : dépôt écrit à la main avec le codename de la BASE Ubuntu (add-apt-repository s'appuie sur lsb_release, faux pour Mint / Pop!_OS…)
deadsnakes_prepare() {
  [[ -n "$BASE_CODENAME" ]] || return 1
  pkg_install gnupg ca-certificates >/dev/null 2>&1 || true
  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF23C5A6CF475977595C89F51BA6932366A755776" 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/deadsnakes.gpg 2>/dev/null || return 1
  printf 'deb [signed-by=/etc/apt/keyrings/deadsnakes.gpg] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu %s main\n' "$BASE_CODENAME" > /etc/apt/sources.list.d/deadsnakes.list
  apt-get update -qq >/dev/null 2>&1 || { rm -f /etc/apt/sources.list.d/deadsnakes.list; return 1; }
}
# (1) paquet récent de la distribution
python_from_distro() {
  local v pk
  case "$PY_STRATEGY" in *apt*|*appstream*|*zypper*) ;; *) return 1;; esac   # pas de paquet récent à essayer (EL7, Amazon Linux 2, Debian 10 sans backports, ou Python déjà suffisant)
  case "$FAMILY" in
    debian)
      for v in 3.13 3.12 3.11 3.10 3.9; do
        if apt_has "python$v" && apt_has "python$v-venv"; then
          log python_pkg "python$v"
          if pkg_install "python$v" "python$v-venv" >/dev/null 2>&1 && find_python; then return 0; fi
        fi
      done
      if [[ "$BASE_ID" == "ubuntu" ]] && deadsnakes_prepare; then
        for v in 3.12 3.11 3.10; do
          if apt_has "python$v" && apt_has "python$v-venv"; then
            log python_pkg "python$v (deadsnakes)"
            if pkg_install "python$v" "python$v-venv" >/dev/null 2>&1 && find_python; then return 0; fi
          fi
        done
      fi;;
    rhel|rhel-yum)
      [[ "$BASE_ID" == "el" ]] || return 1
      for pk in python3.12 python3.11 python39; do   # AppStream (RHEL / Alma / Rocky 8) : paquets python3.12, python3.11, python39
        log python_pkg "$pk"
        if pkg_install "$pk" >/dev/null 2>&1; then pkg_install "${pk}-pip" >/dev/null 2>&1 || true; if find_python; then return 0; fi; fi
      done;;
    suse)
      for pk in python313 python312 python311 python310 python39; do   # SLE / Leap 15 : python311 (module Python 3)
        log python_pkg "$pk"
        if pkg_install "$pk" >/dev/null 2>&1; then pkg_install "${pk}-pip" >/dev/null 2>&1 || true; if find_python; then return 0; fi; fi
      done;;
  esac
  return 1
}
# triplet de la version de uv publiée pour cette machine
uv_triple() {
  local libc=gnu; [[ "$FAMILY" == "alpine" ]] && libc=musl
  case "$ARCH" in
    x86_64) echo "x86_64-unknown-linux-$libc";;
    aarch64) echo "aarch64-unknown-linux-$libc";;
    armv7l) echo "armv7-unknown-linux-gnueabihf";;
    i686) echo "i686-unknown-linux-gnu";;
    ppc64le) echo "powerpc64le-unknown-linux-gnu";;
    s390x) echo "s390x-unknown-linux-gnu";;
    riscv64) echo "riscv64gc-unknown-linux-gnu";;
    *) return 1;;
  esac
}
# (2) Python autonome : uv (SHA-256 vérifié ici) installe python-build-standalone (SHA-256 vérifié par uv) dans <home>/python
provision_standalone_python() {
  local triple tmp tgz url want got uvbin cand
  triple=$(uv_triple) || { warn python_standalone_arch "$ARCH"; return 1; }
  if [[ $YES -eq 0 ]]; then   # consentement : --yes, ou question dans un terminal ; sans terminal, refus
    if _has_tty; then
      local ans=""; printf '  %s' "$(msg python_ask "$(_py_ver python3)" "$UV_PY_VERSION" "$HOME_DIR/python" "$(msg yn_hint)")" >/dev/tty
      read -r ans </dev/tty || ans=""
      is_yes "$ans" || return 1
    else
      return 1
    fi
  fi
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/toutpanel-uv.XXXXXX")
  tgz="$tmp/uv.tar.gz"; url="$UV_BASE/uv-$triple.tar.gz"
  log python_standalone_download "$UV_PY_VERSION" "$triple"
  if ! curl -fsSL "$url" -o "$tgz" 2>/dev/null; then say python_standalone_net "$url"; rm -rf "$tmp"; return 1; fi
  want="${TOUTPANEL_UV_SHA256:-}"
  if [[ -z "$want" ]]; then want=$(curl -fsSL "$url.sha256" 2>/dev/null | awk 'NR == 1 { print $1 }' || true); fi
  got=$(sha256sum "$tgz" 2>/dev/null | awk '{ print $1 }' || true)
  if [[ -z "$want" || "$want" != "$got" ]]; then say python_sha_bad "uv-$triple.tar.gz"; rm -rf "$tmp"; return 1; fi
  tar -xzf "$tgz" -C "$tmp" 2>/dev/null || { say python_sha_bad "uv-$triple.tar.gz"; rm -rf "$tmp"; return 1; }
  uvbin=$(find "$tmp" -type f -name uv -perm -u+x 2>/dev/null | head -1 || true)
  if [[ -z "$uvbin" ]]; then say python_sha_bad "uv-$triple.tar.gz"; rm -rf "$tmp"; return 1; fi
  mkdir -p "$HOME_DIR/python"
  if ! UV_PYTHON_INSTALL_DIR="$HOME_DIR/python" UV_NO_CONFIG=1 "$uvbin" python install "$UV_PY_VERSION" >/dev/null 2>&1; then say python_standalone_failed; rm -rf "$tmp"; return 1; fi
  rm -rf "$tmp"
  cand=$(ls -d "$HOME_DIR"/python/cpython-"$UV_PY_VERSION"*/bin/python3 2>/dev/null | sort -V | tail -1 || true)
  if [[ -z "$cand" ]] || ! _py_ok "$cand"; then say python_standalone_failed; return 1; fi
  PY_BIN="$cand"; PY_STANDALONE=1
  log python_standalone_ok "$(_py_ver "$PY_BIN")" "$HOME_DIR/python"
}
ensure_python() {
  if find_python; then return 0; fi
  warn python_old "$(_py_ver python3)"
  if python_from_distro; then return 0; fi
  if provision_standalone_python; then return 0; fi
  say python_refused "$HOME_DIR/python" "--yes"
  return 1
}


# ------------------------------------------------------------------------------
# Pile logicielle historique (« bash ») : Nginx + PHP-FPM + Certbot (+ MariaDB, Redis, fail2ban avec --stack full). Utilisée sans option de pile
# du composeur ; dès qu'une option --profile / --web / --php… est donnée, la pile est déléguée à « toutpanel stack apply » (voir plus bas).
# Les noms de paquets et de services viennent de compute_packages (par famille).
# ------------------------------------------------------------------------------
PHP_VER=""
php_cli_version() { php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true; }
# Amazon Linux : AL2023 = paquets php8.N (un seul PHP à la fois), AL2 = amazon-linux-extras
install_php_amzn() {
  local v pk
  if [[ "$PM" == "yum" ]]; then
    amazon-linux-extras install -y php8.2 >/dev/null 2>&1 || true
    PHP_VER=$(php_cli_version); svc_enable php-fpm
    return 0
  fi
  # du plus récent au plus ancien : 8.5 (défaut du panel) si la distribution le propose (non vérifié pour Amazon Linux), sinon repli annoncé
  for v in 8.5 8.4 8.3 8.2 8.1; do
    if dnf list available "php$v-fpm" >/dev/null 2>&1; then
      pkg_install "php$v-fpm" "php$v-cli" "php$v-mysqlnd" "php$v-mbstring" "php$v-xml" "php$v-gd" "php$v-intl"
      # opcache : paquet séparé avant 8.5 seulement (compilé dans PHP 8.5) ; un paquet absent est simplement ignoré
      for pk in zip bcmath opcache; do pkg_install "php$v-$pk" >/dev/null 2>&1 || true; done
      if [[ "$v" != "8.5" ]]; then warn php_default_fallback "8.5" "$v"; fi
      PHP_VER="$v"; svc_enable php-fpm
      return 0
    fi
  done
  warn php_unavailable
  return 0
}
install_stack_bash() {
  local f pk
  step st_nginx
  if [[ "$FAMILY" == "amzn" && "$PM" == "yum" ]]; then amazon-linux-extras install -y nginx1; else pkg_install nginx; fi
  if ! ipv6_ok; then
    for f in /etc/nginx/nginx.conf /etc/nginx/sites-available/default /etc/nginx/conf.d/default.conf /etc/nginx/http.d/default.conf; do
      [[ -f "$f" ]] && sed -i -E 's/^([[:space:]]*)listen[[:space:]]+\[::\]:/\1# IPv6 indisponible : listen [::]:/' "$f"
    done
  fi
  svc_enable nginx

  step st_phpfpm
  case "$FAMILY" in
    debian)
      PHP_VER=$(apt-cache search --names-only '^php[0-9]+\.[0-9]+-fpm$' | sed -E 's/^php([0-9.]+)-fpm.*/\1/' | sort -V | tail -1)
      if [[ -z "$PHP_VER" ]]; then pkg_install php-fpm php-cli php-mysql php-curl php-mbstring php-xml php-zip php-gd php-intl; PHP_VER=$(php_cli_version)
      else
        pkg_install "php${PHP_VER}-fpm" "php${PHP_VER}-cli" "php${PHP_VER}-mysql" "php${PHP_VER}-curl" "php${PHP_VER}-mbstring" "php${PHP_VER}-xml" "php${PHP_VER}-zip" "php${PHP_VER}-gd" "php${PHP_VER}-intl"
        # bcmath et opcache : paquets séparés selon la version (opcache est intégré à PHP 8.5+, donc sans paquet « phpX.Y-opcache »)
        for pk in bcmath opcache; do pkg_install "php${PHP_VER}-$pk" >/dev/null 2>&1 || true; done
      fi
      svc_enable "php${PHP_VER}-fpm";;
    rhel|rhel-yum)
      # PHP 8.5 via Remi (collection php85, coexiste avec d'autres versions gérées par le panel ; publiée pour EL 8 / 9 / 10 d'après les
      # métadonnées du dépôt) ; repli 8.4 puis 8.3 annoncé si la collection n'est pas installable. OPcache est compilé dans PHP 8.5 :
      # php85-php-opcache n'est qu'un nom fourni par php85-php-common, il n'est donc demandé qu'avant 8.5.
      remi_prepare
      local rv rvv rext
      for rv in 8.5 8.4 8.3; do
        rvv="${rv//./}"; rext=""
        if [[ "$rv" != "8.5" ]]; then rext="php${rvv}-php-opcache"; fi
        # shellcheck disable=SC2086
        if pkg_install "php${rvv}-php-fpm" "php${rvv}-php-cli" "php${rvv}-php-common" "php${rvv}-php-mysqlnd" "php${rvv}-php-mbstring" "php${rvv}-php-xml" \
             "php${rvv}-php-gd" "php${rvv}-php-intl" "php${rvv}-php-pecl-zip" "php${rvv}-php-bcmath" $rext 2>/dev/null; then
          PHP_VER="$rv"; break
        fi
      done
      if [[ -n "$PHP_VER" ]]; then
        rvv="${PHP_VER//./}"
        if [[ "$PHP_VER" != "8.5" ]]; then warn php_default_fallback "8.5" "$PHP_VER"; fi
        # le pool Remi n'autorise que l'utilisateur apache sur sa socket : nginx doit y accéder
        sed -i "s/^user = apache/user = $NGINX_USER/; s/^group = apache/group = $NGINX_USER/; s/^listen.acl_users = .*/listen.acl_users = apache,$NGINX_USER/" "/etc/opt/remi/php${rvv}/php-fpm.d/www.conf"
        svc_enable "php${rvv}-php-fpm"
        ln -sf "/usr/bin/php${rvv}" /usr/local/bin/php 2>/dev/null || true
      else
        warn remi_unavailable
        pkg_install php-fpm php-cli php-mysqlnd php-mbstring php-xml php-gd php-intl php-zip php-opcache || true
        PHP_VER=$(php_cli_version)
        svc_enable php-fpm
      fi;;
    amzn)   install_php_amzn;;
    arch)   pkg_install php php-fpm php-gd php-intl; PHP_VER=$(php_cli_version); svc_enable php-fpm;;
    alpine)
      # php85 dans community à partir d'Alpine 3.23 (APKINDEX vérifié) ; avant : php84 / php83 (repli annoncé). Pas de php85-opcache (intégré).
      local av avv aext
      for av in 85 84 83 82; do
        aext="php${av}-opcache"; if [[ "$av" == "85" ]]; then aext=""; fi
        # shellcheck disable=SC2086
        if pkg_install "php$av" "php$av-fpm" "php$av-mysqli" "php$av-pdo_mysql" "php$av-curl" "php$av-mbstring" "php$av-xml" "php$av-zip" "php$av-gd" "php$av-intl" "php$av-session" $aext 2>/dev/null; then
          avv="${av:0:1}.${av:1}"; if [[ "$av" != "85" ]]; then warn php_default_fallback "8.5" "$avv"; fi
          break
        fi
      done
      PHP_VER=$(php_cli_version); svc_enable "php-fpm${PHP_VER//./}" php-fpm;;
    suse)   pkg_install php8 php8-fpm php8-mysql php8-mbstring php8-gd php8-intl php8-zip; PHP_VER=$(php_cli_version); svc_enable php-fpm;;
  esac
  log php_installed "${PHP_VER:-?}"

  step st_certbot
  case "$FAMILY" in
    debian) pkg_install certbot composer 2>/dev/null || pkg_install certbot;;
    rhel|rhel-yum|amzn) pkg_install certbot composer 2>/dev/null || pkg_install certbot 2>/dev/null || true;;
    *) pkg_install certbot 2>/dev/null || true;;
  esac

  if [[ "$STACK" == "full" ]]; then
    step st_mariadb
    pkg_install "${PK_DB[@]}"
    case "$FAMILY" in
      arch)   mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql >/dev/null 2>&1 || true;;
      alpine) mysql_install_db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || true;;
    esac
    svc_enable "$SVC_DB"
    step st_redis
    # Redis, sinon Valkey (qui le remplace sur les distributions récentes)
    { pkg_install "${PK_REDIS[@]}" >/dev/null 2>&1 && svc_enable "$SVC_REDIS"; } \
      || { pkg_install valkey >/dev/null 2>&1 && svc_enable valkey; } \
      || { pkg_install valkey-server >/dev/null 2>&1 && svc_enable valkey-server valkey; } || true
    step st_fail2ban
    pkg_install fail2ban 2>/dev/null || true
    # Debian 12+ sans rsyslog : pas de /var/log/auth.log et fail2ban refuse de démarrer (« Have not found any log file for sshd
    # jail ») ; comme Ubuntu, les jails système (sshd, postfix, dovecot) lisent alors le journal systemd.
    if [[ "$FAMILY" == "debian" && -d /etc/fail2ban/jail.d && ! -f /var/log/auth.log ]] && [[ -d /run/systemd/system ]] \
       && ! grep -qsE '^[[:space:]]*backend[[:space:]]*=[[:space:]]*systemd' /etc/fail2ban/jail.d/*.conf /etc/fail2ban/jail.local; then
      pkg_install python3-systemd 2>/dev/null || true
      printf '# Ajouté par l'"'"'installateur ToutPanel : pas de rsyslog, journaux lus dans journald\n[DEFAULT]\nbackend = systemd\n' > /etc/fail2ban/jail.d/00-toutpanel-systemd.conf
    fi
    command -v fail2ban-client >/dev/null && svc_enable fail2ban || true
  fi
  return 0
}
install_mail_bash() {
  step st_mail
  if [[ "$FAMILY" == "debian" ]]; then
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string $(hostname -f 2>/dev/null || hostname)" | debconf-set-selections
    pkg_install "${PK_MAIL[@]}"
    pkg_install dovecot-sieve dovecot-managesieved || true   # filtres Sieve, répondeur, ManageSieve (port 4190)
  elif [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]]; then
    rhel_prepare
    pkg_install "${PK_MAIL[@]}"
    pkg_install dovecot-pigeonhole || true
  else
    pkg_install "${PK_MAIL[@]}" 2>/dev/null || pkg_install postfix dovecot opendkim || true
    pkg_install dovecot-pigeonhole 2>/dev/null || pkg_install dovecot-pigeonhole-plugin 2>/dev/null || pkg_install pigeonhole 2>/dev/null || true
  fi
  # rspamd, ClamAV, mlmmj, fetchmail, Radicale : à la demande depuis Logiciels (catégorie Mail)
  if ! ipv6_ok && [[ -f /etc/dovecot/dovecot.conf ]]; then sed -i -E 's/^#?listen = .*/listen = */' /etc/dovecot/dovecot.conf; fi
  # RHEL : la configuration OpenDKIM livrée attend /etc/opendkim/keys/default.private, que opendkim-default-keygen ne crée pas
  # sans nom de domaine dans le nom d'hôte ; sans elle le service refuse de démarrer (le panel la remplace ensuite par ses KeyTable)
  if [[ -f /etc/opendkim.conf && ! -s /etc/opendkim/keys/default.private ]] && grep -q '^KeyFile[[:space:]]*/etc/opendkim/keys/default.private' /etc/opendkim.conf \
     && command -v opendkim-genkey >/dev/null; then
    mkdir -p /etc/opendkim/keys
    opendkim-genkey -D /etc/opendkim/keys -s default -d "$(hostname -d 2>/dev/null | grep . || echo localdomain)" >/dev/null 2>&1 \
      && chown -R root:opendkim /etc/opendkim/keys && chmod 640 /etc/opendkim/keys/default.private || true
  fi
  svc_enable postfix dovecot opendkim
  return 0
}
install_postgres_bash() {
  step st_postgres
  case "$FAMILY" in
    debian) pkg_install "${PK_PG[@]}"; svc_enable postgresql;;
    rhel|rhel-yum|amzn)
      pkg_install "${PK_PG[@]}"
      [[ -f /var/lib/pgsql/data/PG_VERSION ]] || postgresql-setup --initdb >/dev/null 2>&1 || true
      # connexions TCP locales par mot de passe (le panel se connecte en TCP sur 127.0.0.1)
      sed -i -E 's/^(host\s+all\s+all\s+(127\.0\.0\.1\/32|::1\/128)\s+)ident/\1scram-sha-256/' /var/lib/pgsql/data/pg_hba.conf 2>/dev/null || true
      svc_enable postgresql;;
    arch)   pkg_install "${PK_PG[@]}"; [[ -f /var/lib/postgres/data/PG_VERSION ]] || su - postgres -c "initdb -D /var/lib/postgres/data" >/dev/null 2>&1 || true; svc_enable postgresql;;
    alpine) pkg_install "${PK_PG[@]}"; svc_enable postgresql;;
    suse)   pkg_install "${PK_PG[@]}"; svc_enable postgresql;;
  esac
  return 0
}

# ------------------------------------------------------------------------------
# Étapes qui suivent l'installation du panel, en fonctions : elles s'enchaînent dans l'installation normale et sont les seules exécutées par
# --post-dry (caché, tests : « toutpanel » du PATH, rien d'autre n'est touché). TP = commande « toutpanel » utilisée ; PYX = Python des petits scripts.
# ------------------------------------------------------------------------------
TP="$HOME_DIR/venv/bin/toutpanel"
PYX="$HOME_DIR/venv/bin/python"
if [[ $POST_DRY -eq 1 ]]; then TP="$(command -v toutpanel || printf toutpanel)"; PYX="$(command -v python3 || printf python3)"; fi
SETUP_TOKEN=""
FW_STATE=""; FW_PORTS_TEXT=""
STACK_STATE=""; STACK_RC=0; STACK_PROFILE_SHOWN=""; STACK_COMPONENTS=""
COMPAT_LEVEL=""; COMPAT_REASON=""

# --- pare-feu : moteur demandé absent -> installé ; sinon le panel choisit lui-même (jamais d'arrêt de l'installation) -------------------------------
fw_prepare_engine() {
  local eng="$FIREWALL_ENGINE" cmd="" pk=""
  # famille RHEL sans aucun moteur de pare-feu (image cloud AlmaLinux / Rocky : ni firewalld ni nft) : firewalld, le pare-feu natif de la famille, est installé
  if [[ "$FW_MODE" == "panel" && -z "$eng" && "$FAMILY" == "rhel" && $POST_DRY -eq 0 ]] \
     && ! command -v ufw >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1 && ! command -v nft >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1 && ! command -v csf >/dev/null 2>&1; then
    eng="firewalld"; FIREWALL_ENGINE="firewalld"
  fi
  [[ "$FW_MODE" == "panel" && -n "$eng" ]] || return 0
  case "$eng" in
    ufw) cmd=ufw; pk=ufw;;
    firewalld) cmd=firewall-cmd; pk=firewalld;;
    nft|nftables) cmd=nft; pk=nftables;;
    iptables) cmd=iptables; pk=iptables;;
    csf) cmd=csf; pk="";;
  esac
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -n "$pk" && $POST_DRY -eq 0 ]]; then pkg_install "$pk" >/dev/null 2>&1 || true; fi
    if ! command -v "$cmd" >/dev/null 2>&1 && [[ $POST_DRY -eq 0 ]]; then warn fw_engine_missing "$eng"; FIREWALL_ENGINE=""; fi
  fi
  return 0
}

# --- compte administrateur, ports, mode du pare-feu (installation neuve seulement) -------------------------------------------------------------
do_admin() {
  if [[ $UPDATE -eq 0 ]]; then
    local -a SETUP_ARGS=(--port "$PORT" --https-port "$HTTPS_PORT")
    if [[ $NODE -eq 1 ]]; then SETUP_ARGS=(--port "$PORT" --ssl on); fi   # mode nœud : HTTPS seul sur le port du panel
    if [[ -n "$ADMIN_USER" ]]; then SETUP_ARGS+=(--username "$ADMIN_USER"); fi
    if [[ -n "$ENTRANCE" ]]; then SETUP_ARGS+=(--entrance "$ENTRANCE"); fi
    fw_prepare_engine
    build_fw_setup_args; SETUP_ARGS+=("${FW_SETUP_ARGS[@]}")
    local rc=0
    if [[ "$PASS_SRC" != "generated" && -n "$ADMIN_PASS" ]]; then
      # le mot de passe fourni n'est JAMAIS un argument (« ps ») : il est dans l'environnement de ce seul processus, qui le retire dès sa lecture
      { set +x; } 2>/dev/null
      SETUP_JSON=$(TOUTPANEL_SETUP_PASSWORD="$ADMIN_PASS" "$TP" setup --json "${SETUP_ARGS[@]}") || rc=$?
      if [[ $rc -eq 3 ]]; then   # refusé par la politique du panel (réglages pwd_*) : l'installation du panel n'est pas perdue, un mot de passe aléatoire est généré
        warn pass_refused_by_panel
        PASS_SRC="generated"; rc=0
        SETUP_JSON=$("$TP" setup --json "${SETUP_ARGS[@]}") || rc=$?
      fi
      if [[ $rc -ne 0 ]]; then return "$rc"; fi
    else
      SETUP_JSON=$("$TP" setup --json "${SETUP_ARGS[@]}")
    fi
    # lecture de la réponse par l'entrée standard (jamais en argument d'un processus : elle contient le mot de passe généré et le jeton)
    ADMIN_USER=$(printf '%s' "$SETUP_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['username'])")
    if [[ "$PASS_SRC" == "generated" ]]; then
      ADMIN_PASS=$(printf '%s' "$SETUP_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['password'])")
    else
      ADMIN_PASS=""   # le mot de passe fourni n'est plus gardé en mémoire : le récapitulatif ne l'affiche jamais
    fi
    ENTRANCE=$(printf '%s' "$SETUP_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['entrance'])")
    # jeton de l'assistant de configuration (#/setup : changer l'adresse, l'utilisateur et le mot de passe ; 24 h, usage unique)
    SETUP_TOKEN=$(printf '%s' "$SETUP_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('setup_token',''))" 2>/dev/null || echo "")
    # langue de l'installeur transmise au panel (réglage « language ») : l'interface s'ouvre dans la même langue
    if [[ $POST_DRY -eq 0 ]]; then "$PYX" -c 'import sys;from toutpanel import config;config.get_settings().set("language",sys.argv[1])' "$UI_LANG" >/dev/null 2>&1 || true; fi
  else
    log accounts_kept
    ENTRANCE=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('security_entrance') or '')" "$HOME_DIR/data/settings.json" 2>/dev/null || echo "")
  fi
  return 0
}

# --- MariaDB : mot de passe root et enregistrement dans le panel (pile historique « full » seulement : le composeur gère ses propres bases) ---------
DB_ROOT_PASS=""; PG_ROOT_PASS=""
secure_mariadb() {
  if [[ $UPDATE -eq 0 && "$STACK" == "full" && "$STACK_MODE" == "bash" ]] && command -v mysql >/dev/null; then
    step st_secure_mariadb
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
      "$TP" dbroot mysql --host localhost --port 3306 --user root --password "$DB_ROOT_PASS" >/dev/null
      log mariadb_ok
    else
      warn mariadb_fail
      DB_ROOT_PASS=""
    fi
  fi
  return 0
}
# PostgreSQL : mot de passe du rôle postgres (connexion TCP locale du panel) et enregistrement dans le panel
secure_postgres() {
  if [[ $POSTGRES -eq 1 && "$STACK_MODE" != "composer" ]] && command -v psql >/dev/null; then
    step st_secure_pg
    PG_ROOT_PASS=$(rand 20)
    sleep 2
    if su - postgres -c "psql -qAtc \"ALTER ROLE postgres WITH PASSWORD '${PG_ROOT_PASS}'\"" >/dev/null 2>&1; then
      "$TP" dbroot postgres --host 127.0.0.1 --port 5432 --user postgres --password "$PG_ROOT_PASS" >/dev/null
      log pg_ok
    else
      warn pg_fail
      PG_ROOT_PASS=""
    fi
  fi
  return 0
}

# --- niveau de compatibilité relevé par le panel (« toutpanel compat --json »), si la commande existe ----------------------------------------
show_compat() {
  local out="" l1="" l2=""
  out=$("$TP" compat --json 2>/dev/null) || return 0
  l1=$(printf '%s' "$out" | "$PYX" -c 'import json,sys
try:
    c = json.load(sys.stdin).get("current") or {}
except Exception:
    c = {}
print(c.get("support") or "")
print(str(c.get("reason") or "").replace("\n", " "))' 2>/dev/null) || return 0
  COMPAT_LEVEL=$(printf '%s\n' "$l1" | sed -n 1p); COMPAT_REASON=$(printf '%s\n' "$l1" | sed -n 2p)
  case "$COMPAT_LEVEL" in
    full|reduced|unsupported) ;;
    *) COMPAT_LEVEL=""; return 0;;
  esac
  if [[ "$COMPAT_LEVEL" == "full" ]]; then log compat_line "$(msg "lvl_$COMPAT_LEVEL")"
  else warn compat_line_reason "$(msg "lvl_$COMPAT_LEVEL")" "${COMPAT_REASON:-$(reason_text)}"; fi
  return 0
}

# --- pile logicielle : composeur (« toutpanel stack apply ») ; un échec ne fait JAMAIS échouer l'installation du panel -----------------------------
stack_collect() {   # profil et composants installés, d'après « toutpanel stack status --json »
  local out="" l=""
  out=$("$TP" stack status --json 2>/dev/null) || return 0
  l=$(printf '%s' "$out" | "$PYX" -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
rec = d.get("record") or {}
comps = d.get("components") or {}
names = []
for k, v in comps.items():
    if isinstance(v, dict) and v.get("installed"):
        names.append((k + " " + str(v.get("version") or "")).strip())
print(str(rec.get("stack_profile") or "").replace("\n", " "))
print(", ".join(names).replace("\n", " "))' 2>/dev/null) || return 0
  STACK_PROFILE_SHOWN=$(printf '%s\n' "$l" | sed -n 1p); STACK_COMPONENTS=$(printf '%s\n' "$l" | sed -n 2p)
  return 0
}
stack_apply_composer() {
  local rc=0
  build_stack_args
  step st_stack
  log stack_applying "$(_cmdline stack apply "${STACK_ARGS[@]}")"
  "$TP" stack apply "${STACK_ARGS[@]}" || rc=$?
  STACK_RC=$rc
  case "$rc" in
    0) STACK_STATE="ok"; log stack_ok; stack_collect;;
    3) STACK_STATE="refused"; warn stack_soon;;
    2) STACK_STATE="usage"; warn stack_usage;;
    *) STACK_STATE="failed"; warn stack_failed;;
  esac
  if [[ "$STACK_STATE" != "ok" ]]; then
    warn stack_not_applied
    printf '    toutpanel %s\n' "$(_cmdline stack apply "${STACK_ARGS[@]}")"
  fi
  return 0
}
# liste numérotée des profils (« toutpanel stack profiles --json »), ou « décider plus tard dans l'assistant web » ; défaut : le profil recommandé
stack_ask_profile() {
  local out="" ans="" i n reco=1 rec_id="" id nm sm rmx
  local -a ids=() names=() sums=() rams=()
  out=$("$TP" stack profiles --json 2>/dev/null) || out=""
  local -a L=()
  mapfile -t L < <(printf '%s' "$out" | "$PYX" -c 'import json,sys
try:
    d = json.load(sys.stdin)
    cards = d.get("profiles") or []
    print(d.get("recommended") or "")
    for p in cards:
        f = lambda k: str(p.get(k) or "").replace("\t", " ").replace("\n", " ")
        print("\t".join([f("id"), f("name"), f("summary"), f("ram_min_mb") + "-" + f("ram_reco_mb")]))
except Exception:
    pass' 2>/dev/null || true)
  if [[ ${#L[@]} -lt 2 ]]; then   # liste indisponible : pile historique
    warn stack_profiles_unavailable
    if [[ $POST_DRY -eq 1 ]]; then STACK_STATE="ok"; return 0; fi
    install_stack_bash; STACK_STATE="ok"
    if [[ $MAIL -eq 1 ]]; then install_mail_bash; fi
    if [[ $POSTGRES -eq 1 ]]; then install_postgres_bash; fi
    secure_mariadb; secure_postgres
    return 0
  fi
  rec_id="${L[0]}"
  for (( i = 1; i < ${#L[@]}; i++ )); do
    IFS=$'\t' read -r id nm sm rmx <<<"${L[$i]}"
    ids+=("$id"); names+=("$nm"); sums+=("$sm"); rams+=("$rmx")
    if [[ "$id" == "$rec_id" ]]; then reco=${#ids[@]}; fi
  done
  n=${#ids[@]}
  printf '\n  %s\n' "$(msg stack_q_title)"
  for (( i = 0; i < n; i++ )); do
    printf '   %s%2d%s) %-13s %s%s\n' "$CC" $((i + 1)) "$C0" "${ids[$i]}" "${names[$i]}" "$( [[ "${ids[$i]}" == "$rec_id" ]] && printf ' *' )"
    printf '        %s%s (%s)%s\n' "$CD" "${sums[$i]}" "$(msg stack_q_ram "${rams[$i]}")" "$C0"
  done
  printf '   %s 0%s) %s\n' "$CC" "$C0" "$(msg stack_q_later)"
  printf '  %s ' "$(msg stack_q_prompt "$reco")"
  read -r ans </dev/tty || ans=""
  ans="${ans:-$reco}"
  printf '\n'
  if [[ "$ans" =~ ^[0-9]+$ && $ans -ge 1 && $ans -le $n ]]; then
    PROFILE="${ids[$((ans - 1))]}"; STACK_MODE="composer"
    stack_apply_composer
  else
    STACK_MODE="none"; STACK_STATE="later"; log stack_later
    if [[ $MAIL -eq 1 ]]; then install_mail_bash; fi
    if [[ $POSTGRES -eq 1 ]]; then install_postgres_bash; fi
    secure_postgres
  fi
  return 0
}
run_stack_step() {
  if [[ $STACK_ASK -eq 1 ]]; then stack_ask_profile
  elif [[ "$STACK_MODE" == "composer" ]]; then stack_apply_composer
  elif [[ "$STACK_MODE" == "bash" ]]; then STACK_STATE="ok"
  else STACK_STATE="none"; fi
  return 0
}
# résumé de la pile (récapitulatif et install-info.txt)
stack_summary_value() {
  case "$STACK_STATE" in
    ok) if [[ "$STACK_MODE" == "composer" ]]; then msg stack_val_composer "${STACK_PROFILE_SHOWN:-${PROFILE:-custom}}"; else msg stack_val_default; fi;;
    failed|refused|usage) msg stack_val_failed;;
    later) msg stack_val_later;;
    *) msg stack_val_none;;
  esac
}

# --- pare-feu (installation neuve seulement ; une mise à jour ne le modifie jamais) -------------------------------------------------------
fw_apply() {
  if [[ $UPDATE -eq 1 ]]; then FW_STATE="update"; return 0; fi
  step st_firewall
  case "$FW_MODE" in
    panel)
      build_fw_enable_args
      if "$TP" firewall "${FW_ENABLE_ARGS[@]}"; then FW_STATE="enabled"; log fw_enabled
      else
        FW_STATE="failed"; warn fw_enable_failed
        printf '    toutpanel %s\n' "$(_cmdline firewall "${FW_ENABLE_ARGS[@]}")"
      fi;;
    external)
      # aucune commande système de pare-feu : seule la liste des ports à ouvrir chez l'hébergeur est demandée au panel
      FW_STATE="external"; log fw_external_note
      FW_PORTS_TEXT=$("$TP" firewall ports 2>/dev/null || true);;
    *)
      FW_STATE="later";;
  esac
  return 0
}
fw_summary_value() {
  case "$FW_STATE" in
    enabled) msg fw_val_panel "${FIREWALL_ENGINE:-auto}";;
    failed) msg fw_val_panel_failed;;
    external) msg fw_val_external;;
    later) msg fw_val_later;;
    update) msg fw_update_unchanged;;
    *) msg fw_val_later;;
  esac
}

# --- récapitulatif et install-info.txt ----------------------------------------------------------------------------------------------------
# « URL du panel (HTTP) », « (HTTPS) », puis les mêmes en local : kv LARGEUR [PRÉFIXE] [file|console]
#   console : la mention du certificat auto-signé suit l'adresse HTTPS, « depuis votre réseau » les adresses locales ; file : mention sur une ligne à part
print_urls() {
  local w="$1" pre="${2:-}" mode="${3:-console}" note=""
  [[ -n "$URL_HTTP" ]] && { printf '%s' "$pre"; kv "$w" "$(msg lbl_url_http)" "$URL_HTTP"; }
  if [[ -n "$URL_HTTPS" ]]; then
    [[ "$mode" == console && $SELF_SIGNED -eq 1 ]] && note="   $(msg self_signed_note)"
    printf '%s' "$pre"; kv "$w" "$(msg lbl_url_https)" "$URL_HTTPS$note"
    [[ "$mode" == file && $SELF_SIGNED -eq 1 ]] && printf '%s  %s\n' "$pre" "$(msg self_signed_note)"
  fi
  note=""; [[ "$mode" == console ]] && note="   $(msg from_network)"
  [[ -n "$URL_LOCAL_HTTP" ]] && { printf '%s' "$pre"; kv "$w" "$(msg lbl_url_local_http)" "$URL_LOCAL_HTTP$note"; }
  [[ -n "$URL_LOCAL_HTTPS" ]] && { printf '%s' "$pre"; kv "$w" "$(msg lbl_url_local_https)" "$URL_LOCAL_HTTPS$note"; }
  return 0
}
# lignes « pare-feu », « pile », « compatibilité » communes à la console et au fichier : kv LARGEUR [PRÉFIXE]
print_state_lines() {
  local w="$1" pre="${2:-}"
  printf '%s' "$pre"; kv "$w" "$(msg lbl_firewall)" "$(fw_summary_value)"
  if [[ "$STACK_STATE" == "ok" && "$STACK_MODE" == "composer" ]]; then
    printf '%s' "$pre"; kv "$w" "$(msg lbl_profile)" "${STACK_PROFILE_SHOWN:-${PROFILE:-custom}}"
    [[ -n "$STACK_COMPONENTS" ]] && { printf '%s' "$pre"; kv "$w" "$(msg lbl_components)" "$STACK_COMPONENTS"; }
  elif [[ -n "$STACK_STATE" ]]; then
    printf '%s' "$pre"; kv "$w" "$(msg lbl_stack)" "$(stack_summary_value)"
  fi
  [[ -n "$COMPAT_LEVEL" ]] && { printf '%s' "$pre"; kv "$w" "$(msg lbl_compat)" "$(msg "lvl_$COMPAT_LEVEL")"; }
  [[ $PY_STANDALONE -eq 1 ]] && { printf '%s' "$pre"; kv "$w" "$(msg lbl_python)" "$(msg python_standalone_ok "$(_py_ver "$PY_BIN")" "$HOME_DIR/python")"; }
  return 0
}
# ports à ouvrir chez l'hébergeur (pare-feu en amont) : en-tête puis liste du panel, avec un préfixe d'indentation
print_ports_block() {
  local pre="${1:-}"
  [[ "$FW_STATE" == "external" && -n "$FW_PORTS_TEXT" ]] || return 0
  printf '%s%s\n' "$pre" "$(msg fw_ports_title)"
  printf '%s\n' "$FW_PORTS_TEXT" | sed "s/^/$pre  /"
  return 0
}
# valeur de la ligne « Mot de passe » : le mot de passe généré, ou une mention quand il a été fourni (jamais sa valeur)
pass_shown() { if [[ "$PASS_SRC" == "generated" ]]; then printf '%s' "$ADMIN_PASS"; else msg pass_set_by_you; fi; }
print_summary() {
  local LOCAL_IP PUBLIC_IP IP INFO_FILE
  LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$LOCAL_IP" ]] && LOCAL_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1)
  PUBLIC_IP=""
  if [[ $POST_DRY -eq 0 ]]; then PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null | grep -E '^[0-9.]+$' || true); fi
  IP="${PUBLIC_IP:-${LOCAL_IP:-127.0.0.1}}"
  # adresses du panel : une par écoute active (HTTP, HTTPS), publiques puis locales ; mode nœud : HTTPS seul
  URL_HTTP=""; URL_HTTPS=""; URL_LOCAL_HTTP=""; URL_LOCAL_HTTPS=""
  [[ $HTTP_ON -eq 1 ]] && URL_HTTP="http://${IP}:${PORT}${ENTRANCE}"
  [[ $HTTPS_ON -eq 1 ]] && URL_HTTPS="https://${IP}:${HTTPS_PORT}${ENTRANCE}"
  if [[ -n "$LOCAL_IP" && "$LOCAL_IP" != "$IP" ]]; then
    [[ $HTTP_ON -eq 1 ]] && URL_LOCAL_HTTP="http://${LOCAL_IP}:${PORT}${ENTRANCE}"
    [[ $HTTPS_ON -eq 1 ]] && URL_LOCAL_HTTPS="https://${LOCAL_IP}:${HTTPS_PORT}${ENTRANCE}"
  fi
  # lien privilégié (assistant de configuration) : HTTPS quand il est actif, le jeton ne doit pas circuler en clair
  URL="${URL_HTTPS:-$URL_HTTP}"
  URL_LOCAL="${URL_LOCAL_HTTPS:-$URL_LOCAL_HTTP}"
  # certificat HTTPS auto-signé ? (mention de l'avertissement du navigateur)
  SELF_SIGNED=0
  if [[ $HTTPS_ON -eq 1 && $POST_DRY -eq 0 ]]; then
    SELF_SIGNED=$("$PYX" -c "from toutpanel.services import ssl
print(1 if ssl.cert_info(str(ssl.panel_cert()[0])).get('self_signed') else 0)" 2>/dev/null || echo 1)
  fi
  SETUP_URL=""   # assistant de configuration : même base que l'URL du panel (entrée sécurisée comprise) + ancre #/setup
  [[ $UPDATE -eq 0 && -n "${SETUP_TOKEN:-}" ]] && SETUP_URL="${URL}#/setup?token=${SETUP_TOKEN}"
  SETUP_URL_LOCAL=""   # même lien avec l'adresse locale (réseau privé), en plus de l'adresse publique
  [[ $UPDATE -eq 0 && -n "${SETUP_TOKEN:-}" && -n "$URL_LOCAL" ]] && SETUP_URL_LOCAL="${URL_LOCAL}#/setup?token=${SETUP_TOKEN}"
  INFO_FILE="$HOME_DIR/data/install-info.txt"
  [[ $UPDATE -eq 1 ]] && INFO_FILE="$HOME_DIR/data/update-info.txt"
  mkdir -p "$HOME_DIR/data"
  {
    # libellés dans la langue de l'installeur (en français, ceux que l'assistant de configuration met à jour)
    say info_title "$(date '+%Y-%m-%d %H:%M')"
    print_urls 26 "" file
    kv 26 "$(msg lbl_user)" "$ADMIN_USER"
    kv 26 "$(msg lbl_pass)" "$(pass_shown)"
    kv 26 "$(msg lbl_entrance)" "$ENTRANCE"
    [[ -n "$SETUP_URL" ]] && kv 26 "$(msg lbl_setup)" "$SETUP_URL" && printf '  %s\n' "$(msg setup_note_file)"
    [[ -n "$SETUP_URL_LOCAL" ]] && kv 26 "$(msg lbl_setup_local)" "$SETUP_URL_LOCAL"
    [[ -n "$DB_ROOT_PASS" ]] && kv 26 "$(msg lbl_mariadb)" "$DB_ROOT_PASS"
    [[ -n "$PG_ROOT_PASS" ]] && kv 26 "$(msg lbl_pg)" "postgres / $PG_ROOT_PASS"
    [[ -n "$PHP_VER" ]] && kv 26 "$(msg lbl_php)" "$PHP_VER"
    kv 26 "$(msg lbl_dir)" "$HOME_DIR"
    print_state_lines 26 ""
    print_ports_block ""
    [[ -n "$NODE_INFO" ]] && printf '\n%s\n%s\n' "$(msg info_node)" "$NODE_INFO"
    [[ -n "$WAF_INFO" ]] && printf '\n%s\n%s\n' "$(msg info_waf)" "$WAF_INFO"
    waf_info_lines 26 "" 1
  } > "$INFO_FILE"
  chmod 600 "$INFO_FILE"
  write_result_json "$([[ $UPDATE -eq 1 ]] && printf update || printf install)"

  if [[ $UPDATE -eq 1 ]]; then
    VERSION=$("$TP" --version 2>/dev/null || echo "")
    echo
    box "$(msg done_update)"
    echo
    if [[ ${PANEL_UP:-1} -eq 0 ]]; then
      printf '\033[1;33m  %s\033[0m\n' "$(msg panel_not_up_yet)"
      echo
    fi
    printf '  '; kv 26 "$(msg lbl_version)" "${VERSION:-$(msg unknown)}"
    print_urls 26 "  "
    print_state_lines 26 "  "
    waf_info_lines 26 "  "
    [[ -n "$NORM" ]] && printf '  %s\n' "$(msg version_installed_note "$NORM")"
    printf '  %s\n' "$(msg update_kept "$BK")"
    printf '  '; kv 26 "$(msg lbl_commands)" "toutpanel info | status | restart"
    echo
    return 0
  fi
  echo
  box "$(msg done_install)"
  echo
  if [[ ${PANEL_UP:-1} -eq 0 ]]; then
    printf '\033[1;33m  %s\033[0m\n' "$(msg panel_not_up_yet)"
    echo
  fi
  print_urls 26 "  "
  printf '  '; kv 26 "$(msg lbl_user)" "$ADMIN_USER"
  printf '  '; kv 26 "$(msg lbl_pass)" "$(pass_shown)"
  if [[ -n "$SETUP_URL" ]]; then
    echo
    printf '  '; kv 26 "$(msg lbl_setup)" "$SETUP_URL"
    [[ -n "$SETUP_URL_LOCAL" ]] && printf '  ' && kv 26 "$(msg lbl_setup_local)" "$SETUP_URL_LOCAL   $(msg from_network)"
    if [[ "$PASS_SRC" == "generated" ]]; then printf '  %s\n' "$(msg setup_note)"; else printf '  %s\n' "$(msg setup_note_given)"; fi
    printf '  %s\n' "$(msg setup_new_link)"
  fi
  [[ -n "$DB_ROOT_PASS" ]] && printf '  ' && kv 26 "$(msg lbl_mariadb)" "$DB_ROOT_PASS"
  [[ -n "$PG_ROOT_PASS" ]] && printf '  ' && kv 26 "$(msg lbl_pg)" "postgres / $PG_ROOT_PASS"
  [[ -n "$PHP_VER" ]]      && printf '  ' && kv 26 "$(msg lbl_php)" "$PHP_VER $(msg php_ready)"
  print_state_lines 26 "  "
  if [[ "$FW_STATE" == "later" ]]; then printf '  %s\n' "$(msg fw_later_hint)"; fi
  if [[ "$FW_STATE" == "external" ]]; then echo; print_ports_block "  "; fi
  if [[ -n "$NODE_INFO" ]]; then
    echo
    printf '  %s\n' "$(msg node_summary)"
    printf '%s\n' "$NODE_INFO" | sed 's/^/    /'
  fi
  if [[ -n "$WAF_INFO" ]]; then
    echo
    printf '  %s\n' "$(msg waf_summary)"
    printf '%s\n' "$WAF_INFO" | sed 's/^/    /'
  fi
  if [[ $WAF_REMOTE -eq 1 ]]; then
    echo
    waf_info_lines 26 "  "
  fi
  echo
  [[ -n "$NORM" ]] && printf '  %s\n' "$(msg version_installed_note "$NORM")"
  printf '  %s\n' "$(msg saved_in "$INFO_FILE")"
  printf '  %s\n' "$(msg entrance_note)"
  printf '  '; kv 26 "$(msg lbl_commands)" "toutpanel info | passwd | entrance | port | restart | setup | setup-link"
  echo
  return 0
}

# --- fichiers de service : unité systemd, scripts d'init OpenRC / sysvinit (qui délèguent à « toutpanel start|stop|restart »), rotation des journaux ----------------
panel_env_lines() {   # variables d'environnement du panel : TOUTPANEL_HOME et, si elle était définie à l'installation, TOUTPANEL_WWW
  printf 'Environment=TOUTPANEL_HOME=%s\n' "$HOME_DIR"
  if [[ -n "${TOUTPANEL_WWW:-}" ]]; then printf 'Environment=TOUTPANEL_WWW=%s\n' "$TOUTPANEL_WWW"; fi
  return 0
}
emit_systemd_unit() {
  cat <<UNIT
[Unit]
Description=ToutPanel - panel d'hébergement web
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
$(panel_env_lines)
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
}
emit_openrc_script() {
  local www=""
  if [[ -n "${TOUTPANEL_WWW:-}" ]]; then www="TOUTPANEL_WWW=$(printf '%q' "$TOUTPANEL_WWW") "; fi
  cat <<RC
#!/sbin/openrc-run
description="ToutPanel - panel d'hébergement web"
depend() { need net; }
start() { ebegin "Starting ToutPanel"; TOUTPANEL_HOME="$HOME_DIR" ${www}"$HOME_DIR/venv/bin/toutpanel" start >/dev/null 2>&1; eend \$?; }
stop() { ebegin "Stopping ToutPanel"; TOUTPANEL_HOME="$HOME_DIR" ${www}"$HOME_DIR/venv/bin/toutpanel" stop >/dev/null 2>&1; eend \$?; }
RC
}
emit_sysv_script() {
  local www=""
  if [[ -n "${TOUTPANEL_WWW:-}" ]]; then www="export TOUTPANEL_WWW=$(printf '%q' "$TOUTPANEL_WWW")"; fi
  cat <<'SYSV'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          toutpanel
# Required-Start:    $remote_fs $network
# Required-Stop:     $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ToutPanel - panel d'hebergement web
### END INIT INFO
SYSV
  cat <<SYSV
export TOUTPANEL_HOME="$HOME_DIR"
$www
BIN="$HOME_DIR/venv/bin/toutpanel"
case "\$1" in
  start|stop|restart) "\$BIN" "\$1";;
  status) "\$BIN" status;;
  *) echo "Usage: \$0 {start|stop|restart|status}"; exit 2;;
esac
SYSV
}
emit_logrotate() {
  cat <<ROTATE
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
    [ -f /var/run/httpd/httpd.pid ] && systemctl reload httpd 2>/dev/null || true
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
}

NODE_INFO=""; WAF_INFO=""; PANEL_UP=1
# --post-dry (caché, tests) : seulement les étapes qui suivent l'installation du panel, avec le « toutpanel » du PATH (aucun paquet, service ni système de fichiers hors <home>/data)
if [[ $POST_DRY -eq 1 ]]; then
  [[ -n "${BK:-}" ]] || BK="$HOME_DIR/backup/test"
  mkdir -p "$HOME_DIR/data"
  step st_admin
  do_admin
  run_stack_step
  if [[ $WAF_REMOTE -eq 1 ]]; then WAF_RESTRICT_OK=$WAF_RESTRICT; step st_waf_remote; waf_connect "$TP"; fi
  fw_apply
  show_compat
  print_summary
  waf_strict_exit
  exit 0
fi

# ------------------------------------------------------------------------------
# Distribution : niveau de support (détection faite plus haut) — refus propre, ou avertissement NON bloquant pour le niveau « reduced »
# --python-dry (caché, tests) : seulement la recherche d'un Python 3.9+ ; les paquets de la distribution sont SIMULÉS (aucune installation : ils échouent), le Python
# autonome est réel (TOUTPANEL_UV_BASE_URL permet un miroir local) ; affiche l'interpréteur retenu
if [[ $PYTHON_DRY -eq 1 ]]; then
  pkg_install() { printf 'PKG_INSTALL %s\n' "$*" >> "${TOUTPANEL_TEST_PKG_LOG:-/dev/null}"; return 1; }
  apt_has() { [[ " ${TOUTPANEL_TEST_APT_HAS:-} " == *" $1 "* ]]; }
  deadsnakes_prepare() { printf 'DEADSNAKES\n' >> "${TOUTPANEL_TEST_PKG_LOG:-/dev/null}"; return 1; }
  rc=0; ensure_python || rc=$?
  printf 'RC=%s\nPY_BIN=%s\nPY_STANDALONE=%s\n' "$rc" "$PY_BIN" "$PY_STANDALONE"
  exit 0
fi
# --init-dry (caché, tests) : affiche les fichiers de service qui seraient écrits (unité systemd, scripts OpenRC et sysvinit, logrotate), sans rien écrire
if [[ $INIT_DRY -eq 1 ]]; then
  printf '### systemd\n'; emit_systemd_unit
  printf '### openrc\n'; emit_openrc_script
  printf '### sysv\n'; emit_sysv_script
  printf '### logrotate\n'; emit_logrotate
  exit 0
fi
# ------------------------------------------------------------------------------
step st_distro
log distro_line "$D_PRETTY" "${D_ID:-?}" "$FAMILY" "${PM:-?}" "$INIT" "$ARCH"
case "$SUPPORT" in
  unsupported) say distro_refused "$D_PRETTY" "$(reason_text)"; say distro_refused_hint; exit 1;;
  reduced) warn distro_reduced "$(reason_text)";;
  *) if [[ -n "$SUPPORT_CODES" ]]; then log distro_note "$(reason_text)"; fi;;
esac

# ------------------------------------------------------------------------------
step st_deps
# ------------------------------------------------------------------------------
pkg_update
pkg_install "${PK_DEPS[@]}"
rhel_prepare
if [[ $NEED_BUILD -eq 1 ]]; then   # roues binaires absentes (armv7l, i686, ppc64le, s390x, riscv64, musl) : compilateur et en-têtes
  case "$ARCH" in x86_64|aarch64|"") ;; *) warn arch_compile "$ARCH";; esac
  pkg_install "${PK_BUILD[@]}" || warn build_deps_failed
fi
ensure_python || exit 1
# --stack / --mail / --postgres historiques : la pile est installée AVANT le panel, sauf quand elle est confiée au composeur (options --profile, --web, --php…,
# ou question du profil dans un terminal : voir « Pile logicielle » après le démarrage du panel). Mise à jour : seulement sur demande explicite.
STACK_LATE=0   # 1 : la pile historique est installée après le démarrage du panel (le choix du profil se fait alors dans un terminal)
if [[ $STACK_ASK -eq 1 ]]; then
  STACK_LATE=1
else
  if [[ "$STACK_MODE" == "bash" ]]; then install_stack_bash; fi
  if [[ $MAIL -eq 1 && "$STACK_MODE" != "composer" ]]; then install_mail_bash; fi
  if [[ $POSTGRES -eq 1 && "$STACK_MODE" != "composer" ]]; then install_postgres_bash; fi
fi

# ------------------------------------------------------------------------------
step st_install_panel "$HOME_DIR"
# ------------------------------------------------------------------------------
mkdir -p "$HOME_DIR"
# script lancé depuis un dépôt local (développement : pyproject.toml ; copie du dépôt public : version.json + dist/) : pas de clone
if [[ -z "$SRC" ]] && { [[ -f "$(dirname "$0")/pyproject.toml" ]] || [[ -f "$(dirname "$0")/version.json" && -d "$(dirname "$0")/dist" ]]; }; then SRC="$(cd "$(dirname "$0")" && pwd)"; fi
if [[ -z "$SRC" ]]; then
  if [[ -n "$RES_SHA" ]]; then
    # version précise : le clone partiel de la résolution devient <home>/src ; seuls les fichiers de ce commit sont téléchargés
    log src_version "$NORM" "${RES_SHA:0:12}"
    rm -rf "$HOME_DIR/src"
    mv "$RES_DIR/repo" "$HOME_DIR/src"
    git -C "$HOME_DIR/src" checkout --quiet --detach "$RES_SHA"
    rm -rf "$RES_DIR"; RES_DIR=""
  elif [[ -d "$HOME_DIR/src/.git" ]] && git -C "$HOME_DIR/src" remote get-url origin >/dev/null 2>&1; then
    log src_updating "$BRANCH"
    if ! (git -C "$HOME_DIR/src" fetch --quiet --depth 1 origin "$BRANCH" && git -C "$HOME_DIR/src" checkout --quiet -B "$BRANCH" FETCH_HEAD && git -C "$HOME_DIR/src" reset --quiet --hard FETCH_HEAD); then
      warn src_reclone
      rm -rf "$HOME_DIR/src"; git clone --quiet --depth 1 -b "$BRANCH" "$REPO" "$HOME_DIR/src"
    fi
  else
    log src_download "$BRANCH"
    rm -rf "$HOME_DIR/src"
    git clone --quiet --depth 1 -b "$BRANCH" "$REPO" "$HOME_DIR/src"
  fi
  SRC="$HOME_DIR/src"
fi
# Mode d'installation : sources (pyproject.toml : dépôt de développement) ou roue précompilée (dist/ : dépôt public)
if [[ -f "$SRC/pyproject.toml" ]]; then INSTALL_MODE="source"
elif [[ -d "$SRC/dist" ]]; then INSTALL_MODE="wheel"
else say repo_incomplete "$SRC" "dist/"; exit 1; fi
if [[ "$INSTALL_MODE" == "source" ]]; then
  if [[ ! -w "$SRC" ]]; then  # source en lecture seule (montage, dépôt partagé) : pip a besoin d'écrire les métadonnées
    rm -rf "$HOME_DIR/src-build"; cp -r "$SRC" "$HOME_DIR/src-build"; SRC="$HOME_DIR/src-build"
  fi
  rm -rf "$SRC/build" "$SRC"/*.egg-info 2>/dev/null || true   # artefacts de build obsolètes
fi
if [[ ! -x "$HOME_DIR/venv/bin/python" ]]; then
  [[ -n "$PY_BIN" ]] || find_python || { say python_required; exit 1; }
  "$PY_BIN" -m venv "$HOME_DIR/venv"
fi
"$HOME_DIR/venv/bin/pip" install --quiet --upgrade pip wheel setuptools
if [[ "$INSTALL_MODE" == "wheel" ]]; then
  # roue du Python de l'environnement : toutpanel-<version>-cp3XY-none-any.whl (bytecode portable, aucune source)
  PY_TAG=$("$HOME_DIR/venv/bin/python" -c 'import sys;print(f"cp{sys.version_info[0]}{sys.version_info[1]}")')
  PY_VER=$("$HOME_DIR/venv/bin/python" -c 'import sys;print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
  WHEEL=$(ls "$SRC"/dist/toutpanel-*-"$PY_TAG"-none-any.whl 2>/dev/null | sort -V | tail -1 || true)
  if [[ -z "$WHEEL" ]]; then
    SUPPORTED=$(ls "$SRC"/dist/toutpanel-*-cp3*-none-any.whl 2>/dev/null | sed -E 's/.*-cp3([0-9]+)-none-any\.whl/3.\1/' | sort -V | tr '\n' ' ')
    say no_wheel "$PY_VER" "$SRC/dist"
    say wheel_supported "${SUPPORTED:-$(msg none)}"
    say no_wheel_hint "$HOME_DIR/venv"
    exit 1
  fi
  if [[ -f "$SRC/dist/SHA256SUMS" ]] && command -v sha256sum >/dev/null; then   # intégrité de la roue (sommes publiées avec la version)
    (cd "$SRC/dist" && grep " $(basename "$WHEEL")\$" SHA256SUMS | sha256sum -c --quiet -) || { say checksum_bad "$(basename "$WHEEL")"; exit 1; }
  fi
  log installing_wheel "$(basename "$WHEEL")" "$PY_VER"
  "$HOME_DIR/venv/bin/pip" install --quiet --upgrade "$WHEEL"
  # pip ne réinstalle pas de lui-même une roue dont le numéro de version n'a pas changé (canal dev) : réinstallation forcée du seul paquet
  "$HOME_DIR/venv/bin/pip" install --quiet --upgrade --no-deps --force-reinstall "$WHEEL"
else
  log installing_source "$SRC"
  "$HOME_DIR/venv/bin/pip" install --quiet --upgrade "$SRC"
fi
ln -sf "$HOME_DIR/venv/bin/toutpanel" /usr/local/bin/toutpanel
export TOUTPANEL_HOME="$HOME_DIR"
mkdir -p "$WWW_ROOT"
# aide contextuelle : documentation MkDocs construite dans $HOME_DIR/docs-site (servie sous /help/) si MkDocs est installé,
# sinon le panel renvoie vers la documentation en ligne (étape facultative, jamais bloquante). Documentation multilingue :
# un site par langue sous docs-site/<langue>/ ; langues construites : TOUTPANEL_DOCS_LANGS (auto par défaut = français + langues déjà traduites,
# all, ou liste « fr,en,de »), voir docs/i18n/README.md
if [[ -f "$SRC/scripts/build-docs.sh" && -f "$SRC/docs/mkdocs.yml" ]]; then
  bash "$SRC/scripts/build-docs.sh" "$SRC" "$HOME_DIR/docs-site" || warn docs_not_built
fi
if [[ $UPDATE -eq 1 ]]; then
  step st_migrate
  "$HOME_DIR/venv/bin/toutpanel" migrate
fi
# canal et dépôt de mise à jour enregistrés dans le panel (Mises à jour → Panel, toutpanel update) : --channel, ou dépôt autre
# que le dépôt public (TOUTPANEL_REPO : miroir, fork) pour que le panel se mette à jour depuis le même dépôt
if [[ -n "$CHANNEL" || "$REPO" != "https://github.com/qu3ntin01/toutpanel.git" ]]; then
  "$HOME_DIR/venv/bin/toutpanel" update --channel "${CHANNEL:-stable}" --repo "$REPO" --check >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
step st_admin
# ------------------------------------------------------------------------------
do_admin
if [[ $STACK_ASK -eq 0 ]]; then secure_mariadb; secure_postgres; fi

# ------------------------------------------------------------------------------
# SELinux (Alma / Rocky / RHEL / Fedora / Oracle / Amazon Linux avec SELinux)
# ------------------------------------------------------------------------------
if command -v getenforce >/dev/null && [[ "$(getenforce 2>/dev/null)" != "Disabled" ]]; then
  # Le panel vit hors des chemins standard (/var/toutpanel, /www) : sans étiquette bin_t, systemd refuse d'exécuter ses binaires (203/EXEC).
  semanage fcontext -a -t bin_t "$HOME_DIR/venv/bin(/.*)?" 2>/dev/null || semanage fcontext -m -t bin_t "$HOME_DIR/venv/bin(/.*)?" 2>/dev/null || true
  restorecon -R "$HOME_DIR/venv/bin" >/dev/null 2>&1 || true
  if [[ $PY_STANDALONE -eq 1 || -d "$HOME_DIR/python" ]]; then   # Python autonome : l'interpréteur du venv pointe dans <home>/python
    semanage fcontext -a -t bin_t "$HOME_DIR/python(/.*)?/bin(/.*)?" 2>/dev/null || semanage fcontext -m -t bin_t "$HOME_DIR/python(/.*)?/bin(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t lib_t "$HOME_DIR/python(/.*)?/lib(/.*)?" 2>/dev/null || true
    restorecon -R "$HOME_DIR/python" >/dev/null 2>&1 || true
  fi
fi
if command -v getenforce >/dev/null && [[ "$(getenforce 2>/dev/null)" != "Disabled" && ( $UPDATE -eq 1 || ! -f "$HOME_DIR/data/.selinux-configured" ) ]]; then   # mise à jour : contextes réappliqués (idempotent), de nouveaux motifs peuvent avoir été ajoutés
  step st_selinux
  mkdir -p "$HOME_DIR/logs/sites" "$HOME_DIR/ssl" "$HOME_DIR/vhost" "$HOME_DIR/data/tls" "$WWW_ROOT"
  # une seule transaction « semanage import » (contextes + booléens) par « toutpanel selinux » : la liste est celle du panel (platform/linux.py),
  # chaque appel isolé de semanage reconstruit la politique (plusieurs minutes en émulation, laboratoire scripts/lab)
  if "$TP" selinux >/dev/null 2>&1; then
    restorecon -R "$WWW_ROOT" "$HOME_DIR" >/dev/null 2>&1 || true
    log selinux_ok "$WWW_ROOT"
  else
    semanage fcontext -a -t httpd_sys_rw_content_t "$WWW_ROOT(/.*)?" 2>/dev/null || semanage fcontext -m -t httpd_sys_rw_content_t "$WWW_ROOT(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t httpd_log_t "$HOME_DIR/logs/sites(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t cert_t "$HOME_DIR/ssl(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t cert_t "$HOME_DIR/data/tls(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t var_log_t "$HOME_DIR/logs" 2>/dev/null || true
    semanage fcontext -a -t var_log_t "$HOME_DIR/logs/[^/]+\\.[^/]+" 2>/dev/null || true
    semanage fcontext -a -t httpd_config_t "$HOME_DIR/vhost(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t mail_spool_t "/var/vmail(/.*)?" 2>/dev/null || true
    restorecon -R "$WWW_ROOT" "$HOME_DIR" >/dev/null 2>&1 || true
    setsebool -P httpd_can_network_connect 1 httpd_can_network_connect_db 1 httpd_can_sendmail 1 httpd_setrlimit 1 >/dev/null 2>&1 || true
    touch "$HOME_DIR/data/.selinux-configured"
    log selinux_ok "$WWW_ROOT"
  fi
fi
# AppArmor (Debian / Ubuntu / SUSE) : ajouts locaux des profils nginx / php-fpm / named (WWW_ROOT et répertoire du panel)
if [[ -r /sys/module/apparmor/parameters/enabled ]] && grep -qi '^y' /sys/module/apparmor/parameters/enabled && [[ ! -f "$HOME_DIR/data/.apparmor-configured" ]]; then
  step st_apparmor
  "$TP" apparmor apply || warn apparmor_fail
fi

# ------------------------------------------------------------------------------
step st_service
# ------------------------------------------------------------------------------
if use_systemd; then
  emit_systemd_unit > /etc/systemd/system/toutpanel.service
  systemctl daemon-reload
  systemctl enable toutpanel >/dev/null 2>&1
  if [[ $UPDATE -eq 1 ]]; then systemctl restart toutpanel; log panel_restarted; else systemctl start toutpanel; fi
  systemctl restart toutpanel
else
  # sans systemd (OpenRC : Alpine, Artix…, ou sysvinit : Devuan…) : script d'init qui délègue à « toutpanel start|stop|restart » (démarrage au boot), le panel est lancé tout de suite
  if [[ "$INIT" == "openrc" ]] && use_openrc && [[ -d /etc/init.d ]]; then
    emit_openrc_script > /etc/init.d/toutpanel
    chmod 755 /etc/init.d/toutpanel
    rc-update add toutpanel default >/dev/null 2>&1 || true
  elif [[ -d /etc/init.d ]] && { command -v update-rc.d >/dev/null 2>&1 || command -v chkconfig >/dev/null 2>&1; }; then
    emit_sysv_script > /etc/init.d/toutpanel
    chmod 755 /etc/init.d/toutpanel
    update-rc.d toutpanel defaults >/dev/null 2>&1 || chkconfig toutpanel on >/dev/null 2>&1 || true
  fi
  "$TP" restart >/dev/null || "$TP" start >/dev/null
fi
if [[ -d /etc/logrotate.d ]]; then emit_logrotate > /etc/logrotate.d/toutpanel; fi
# Écoutes du panel telles qu'enregistrées dans ses réglages (HTTP sur PORT, HTTPS sur HTTPS_PORT ; migration de l'ancien réglage « HTTPS seul »
# comprise : une installation existante en HTTPS seul le reste). HTTP_ON / HTTPS_ON valent 0 pour une écoute désactivée.
read_listeners() {
  local out
  out=$("$PYX" -c "from toutpanel import config
l = dict(config.panel_listeners())
print(l.get('http', 0), l.get('https', 0))" 2>/dev/null) || return 0
  set -- $out
  [[ -n "${1:-}" ]] || return 0
  if [[ "$1" -gt 0 ]]; then HTTP_ON=1; PORT="$1"; else HTTP_ON=0; fi
  if [[ "${2:-0}" -gt 0 ]]; then HTTPS_ON=1; HTTPS_PORT="$2"; else HTTPS_ON=0; fi
}
read_listeners
UP_PORT=$PORT; [[ $HTTP_ON -eq 0 ]] && UP_PORT=$HTTPS_PORT
# Le service est-il vraiment joignable ? (jusqu'à 30 s : démarrage de Python, migration de la base) — sur HTTP, sinon sur HTTPS (certificat non vérifié)
PANEL_UP=0
for _ in $(seq 1 "${TOUTPANEL_UP_WAIT:-30}"); do   # TOUTPANEL_UP_WAIT : secondes d'attente (machines très lentes, émulation : le premier démarrage dépasse 30 s)
  if [[ $HTTP_ON -eq 1 ]] && curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/"; then PANEL_UP=1; break; fi
  if [[ $HTTPS_ON -eq 1 ]] && curl -sk -o /dev/null --max-time 2 "https://127.0.0.1:${HTTPS_PORT}/"; then PANEL_UP=1; break; fi
  sleep 1
done
if [[ $PANEL_UP -eq 1 ]]; then
  log panel_up "$UP_PORT"
else
  warn panel_down "$UP_PORT"
  if use_systemd; then
    # diagnostics seulement : ces commandes renvoient un code non nul quand le service est en échec
    { systemctl --no-pager -l status toutpanel 2>&1 || true; } | head -12 | sed 's/^/    /' || true
    printf '    %s\n' "$(msg journal_header)"
    { journalctl -u toutpanel --no-pager -n 20 2>&1 || true; } | sed 's/^/    /' || true
  else
    { tail -n 20 "$HOME_DIR/logs/panel.out" 2>/dev/null || true; } | sed 's/^/    /' || true
  fi
  if command -v getenforce >/dev/null && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
    warn selinux_enforcing
  fi
fi
show_compat

# ------------------------------------------------------------------------------
# Pile logicielle du composeur (« toutpanel stack apply »), ou question du profil dans un terminal : APRÈS le démarrage du panel
# ------------------------------------------------------------------------------
run_stack_step

WAF_INFO=""
if [[ "$WAF" == "toutwaf" && $WAF_REMOTE -eq 0 ]]; then
  step st_waf_toutwaf
  "$TP" restart >/dev/null 2>&1 || "$TP" start >/dev/null 2>&1 || true
  if "$TP" waf install toutwaf --http-port 8080 --https-port 8443 && "$TP" restart >/dev/null 2>&1; then
    WAF_INFO=$("$TP" waf links toutwaf 2>/dev/null || true)
    log waf_deployed "$WAF" "$(printf '%s\n' "$WAF_INFO" | grep -o 'https://[^ ]*' | head -1)"
  else
    warn toutwaf_failed
  fi
elif [[ -n "$WAF" && "$WAF" != "toutwaf" ]]; then
  step st_waf_docker "$WAF"
  case "$WAF" in bunkerweb|safeline) ;; *) say bad_waf "$WAF"; exit 1;; esac
  if ! command -v docker >/dev/null; then
    if [[ "$FAMILY" == "debian" ]]; then pkg_install docker.io docker-compose-v2 || true
    elif [[ "$FAMILY" == "rhel" || "$FAMILY" == "rhel-yum" ]]; then
      rhel_prepare
      REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"; [[ "$BASE_ID" == "fedora" ]] && REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"
      curl -fsSL "$REPO_URL" -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
      pkg_install docker-ce docker-ce-cli containerd.io docker-compose-plugin || pkg_install docker docker-compose || true
    else pkg_install docker docker-compose || true; fi
    svc_enable docker
  fi
  "$TP" restart >/dev/null 2>&1 || "$TP" start >/dev/null 2>&1 || true
  if "$TP" waf install "$WAF" --http-port 8080 --https-port 8443 && "$TP" restart >/dev/null 2>&1; then
    log waf_deployed "$WAF" "$( [[ "$WAF" == bunkerweb ]] && echo "http://$(hostname -I 2>/dev/null | awk '{print $1}'):7000" || echo "https://$(hostname -I 2>/dev/null | awk '{print $1}'):9443" )"
  else
    warn waf_failed "$WAF"
  fi
fi

# ------------------------------------------------------------------------------
# ToutWAF distant : raccordement AVANT le pare-feu (si la restriction de 80/443 est active, « firewall enable --no-web » ne les rouvre pas à tout le monde).
# Ne fait jamais échouer l'installation du panel.
# ------------------------------------------------------------------------------
if [[ $WAF_REMOTE -eq 1 ]]; then
  step st_waf_remote
  waf_connect "$TP"
fi

# ------------------------------------------------------------------------------
# Pare-feu : « toutpanel firewall enable » (mode ToutPanel), liste des ports à ouvrir chez l'hébergeur (pare-feu en amont), ou rien (plus tard)
# ------------------------------------------------------------------------------
fw_apply

# ------------------------------------------------------------------------------
# Mode nœud (multi-serveurs) : HTTPS du panel puis jeton d'enrôlement pour le maître
# ------------------------------------------------------------------------------
NODE_INFO=""
if [[ $NODE -eq 1 ]]; then
  step st_node
  "$TP" ssl on >/dev/null
  if use_systemd; then systemctl restart toutpanel || true
  else "$TP" restart >/dev/null 2>&1 || true; fi
  if NODE_INFO=$("$TP" node enroll --master "$MASTER_URL"); then
    log node_ok
  else
    warn node_fail
    NODE_INFO=""
  fi
fi

# ------------------------------------------------------------------------------
# Récapitulatif
# ------------------------------------------------------------------------------
print_summary
waf_strict_exit
if [[ $UPDATE -eq 1 ]]; then exit 0; fi
