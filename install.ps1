<#
  ToutPanel — installation Windows
  Pris en charge : Windows 10 / 11, Windows Server 2016 / 2019 / 2022 / 2025 (PowerShell 5.1 ou plus, aucune dépendance à winget)

  Usage (PowerShell en administrateur) :
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iwr -useb https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.ps1 | iex
    ou : .\install.ps1 [-Port 8888] [-Home C:\toutpanel] [-Stack] [-Username x] [-Password y] [-Entrance /x]

  -Stack  : installe aussi Nginx (nginx.org), PHP 8.3 (windows.php.net, géré par le panel) et MariaDB (MSI officiel, service Windows).
  -Update : met à jour une installation existante (détecté automatiquement si <Home>\data\settings.json existe) :
            sauvegarde des données, nouveau code, migration de la base, redémarrage de la tâche ; comptes et réglages conservés.
  -Reinstall : force une installation complète.
  -Uninstall : désinstalle le panel (tâches planifiées, dossier du panel) ; les sites et bases de données restent en place,
               les données du panel sont archivées dans un zip.
  -Yes : ne pose aucune question (menu et confirmations) : pour les installations automatisées.
  -Source DIR : installer depuis un dépôt local : sources (pyproject.toml présent, dépôt de développement) ou roues
                précompilées (dossier dist\, copie du dépôt public).

  Lancé dans une console sans option, le script affiche un menu : installer, mettre à jour ou désinstaller.

  Le dépôt public ne contient pas de code source : le panel y est publié sous forme de roues Python « bytecode seulement »
  dans dist\ (toutpanel-<version>-cp3XY-none-any.whl, une par version de CPython 3.9 à 3.14). Le script télécharge l'archive
  de la branche dans <Home>\src puis installe la roue correspondant au Python de l'environnement ; un dépôt contenant
  pyproject.toml (développement) est installé depuis ses sources.
#>
param(
  [int]$Port = 8888,
  # $HOME est une variable automatique en lecture seule de PowerShell (« Cannot overwrite variable Home ») : le paramètre
  # s'appelle $PanelHome, l'option -Home reste acceptée grâce à l'alias.
  [Alias("Home")][string]$PanelHome = "$env:SystemDrive\toutpanel",
  [switch]$Stack,
  [switch]$Update,
  [switch]$Reinstall,
  [switch]$Uninstall,
  [switch]$Yes,
  [string]$Username = "",
  [string]$Password = "",
  [string]$Entrance = "",
  [string]$Source = "",
  [string]$Branch = "main",
  [string]$PythonVersion = "3.12.10",
  [string]$NginxVersion = "1.26.3",
  [string]$MariaDBVersion = "11.4.5",
  [string]$PhpVersion = "8.3"
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Log($m) { Write-Host "[ToutPanel] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[ToutPanel] $m" -ForegroundColor Yellow }
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Download($url, $dest) { Log "Téléchargement $url"; (New-Object Net.WebClient).DownloadFile($url, $dest) }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Error "Lancez PowerShell en tant qu'administrateur."; exit 1 }
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 14393) { Write-Error "Windows 10 / Windows Server 2016 (build 14393) minimum requis (build actuel : $build)."; exit 1 }
$tmp = Join-Path $env:TEMP "toutpanel-install"; New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# --- Présentation, état et menu ---------------------------------------------------
function Banner {
  Write-Host ""
  $art = @(
    "  ████████╗ ██████╗ ██╗   ██╗████████╗██████╗  █████╗ ███╗   ██╗███████╗██╗     ",
    "  ╚══██╔══╝██╔═══██╗██║   ██║╚══██╔══╝██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     ",
    "     ██║   ██║   ██║██║   ██║   ██║   ██████╔╝███████║██╔██╗ ██║█████╗  ██║     ",
    "     ██║   ██║   ██║██║   ██║   ██║   ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     ",
    "     ██║   ╚██████╔╝╚██████╔╝   ██║   ██║     ██║  ██║██║ ╚████║███████╗███████╗",
    "     ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝")
  $i = 0; foreach ($line in $art) { Write-Host $line -ForegroundColor $(if ($i -lt 3) { "Blue" } else { "Cyan" }); $i++ }
  Write-Host "  Panel d'hébergement web · Linux & Windows · licence propriétaire, édition Personnelle gratuite" -ForegroundColor White
  Write-Host "  https://toutpanel.com · https://github.com/qu3ntin01/toutpanel" -ForegroundColor DarkGray
  Write-Host ""
}
function Intro {
  Write-Host "  À quoi sert ToutPanel ?" -ForegroundColor White
  Write-Host "  Gérer un serveur web complet depuis le navigateur, sans ligne de commande :"
  Write-Host "   • sites Nginx / IIS, PHP 5.6 → 8.4 côte à côte, WordPress en un clic"
  Write-Host "   • bases MariaDB / PostgreSQL, FTP, serveur mail et webmail, DNS"
  Write-Host "   • SSL Let's Encrypt automatique, pare-feu applicatif (WAF), sauvegardes, Docker"
  Write-Host "   • déploiement Git, répartition de charge, alertes, terminal et fichiers"
  Write-Host "  Ce script installe Python, la pile (-Stack : Nginx, PHP, MariaDB) puis le panel, crée le"
  Write-Host "  compte administrateur et affiche l'adresse d'accès à la fin."
  Write-Host ""
}
$Existing = Test-Path "$PanelHome\data\settings.json"
$ExistingVersion = ""
if ($Existing -and (Test-Path "$PanelHome\venv\Scripts\toutpanel.exe")) { try { $ExistingVersion = (& "$PanelHome\venv\Scripts\toutpanel.exe" --version 2>$null | Select-Object -First 1) } catch {} }
Banner
if ($Existing) { Write-Host "  ● Installation existante détectée dans $PanelHome (version $(if ($ExistingVersion) { $ExistingVersion } else { 'inconnue' }))" -ForegroundColor Green }
else { Write-Host "  ○ Aucune installation dans $PanelHome : première installation" -ForegroundColor Yellow }
Write-Host ""

$interactive = (-not $Yes) -and (-not $Update) -and (-not $Reinstall) -and (-not $Uninstall) -and [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)
if ($interactive) {
  Intro
  Write-Host "  Que voulez-vous faire ?" -ForegroundColor White
  if ($Existing) {
    Write-Host "   1) Mettre à jour ToutPanel          (comptes, réglages, sites et logiciels conservés)"
    Write-Host "   2) Réinstaller complètement          (repart de zéro dans $PanelHome)"
    Write-Host "   3) Désinstaller ToutPanel            (les sites et bases de données restent en place)"
    Write-Host "   4) Quitter"
  } else {
    Write-Host "   1) Installer ToutPanel               (avec la pile : Nginx, PHP, MariaDB)"
    Write-Host "   2) Installer le panel seul           (sans pile : vous gérez Nginx / PHP / MariaDB)"
    Write-Host "   3) Quitter"
  }
  $choice = Read-Host "  Votre choix [1]"
  if (-not $choice) { $choice = "1" }
  Write-Host ""
  if ($Existing) {
    switch ($choice) { "1" { $Update = $true } "2" { $Reinstall = $true } "3" { $Uninstall = $true } default { Write-Host "  À bientôt."; exit 0 } }
  } else {
    switch ($choice) { "1" { $Stack = $true } "2" { $Stack = $false } default { Write-Host "  À bientôt."; exit 0 } }
  }
}

# --- Désinstallation -------------------------------------------------------------
if ($Uninstall) {
  Step "Désinstallation de ToutPanel"
  if (-not (Test-Path $PanelHome)) { Write-Host "  Rien à désinstaller dans $PanelHome."; exit 0 }
  Write-Host "  Seront supprimés : les tâches planifiées ToutPanel et ToutPanel-Nginx, le dossier $PanelHome (panel, Python, journaux,"
  Write-Host "  certificats). Seront conservés : les sites dans $PanelHome\wwwroot (déplacés à côté), les bases de données, Nginx, PHP, MariaDB."
  if (-not $Yes) {
    $confirm = Read-Host "  Confirmez en tapant oui"
    if ($confirm -ne "oui") { Write-Host "  Désinstallation annulée."; exit 0 }
  }
  schtasks /End /TN ToutPanel 2>$null | Out-Null
  schtasks /Delete /F /TN ToutPanel 2>$null | Out-Null
  schtasks /Delete /F /TN ToutPanel-Nginx 2>$null | Out-Null
  Get-Process -Name python* -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$PanelHome\venv\*" } | Stop-Process -Force -ErrorAction SilentlyContinue
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $archive = "$env:SystemDrive\toutpanel-backup-$stamp.zip"
  $toArchive = @("data", "ssl", "vhost", "templates") | ForEach-Object { Join-Path $PanelHome $_ } | Where-Object { Test-Path $_ }
  if ($toArchive) { Compress-Archive -Path $toArchive -DestinationPath $archive -Force; Log "Données archivées dans $archive" }
  $www = Join-Path $PanelHome "wwwroot"
  if (Test-Path $www) { $keep = "$env:SystemDrive\toutpanel-wwwroot-$stamp"; Move-Item $www $keep; Log "Sites déplacés dans $keep" }
  Remove-Item -Recurse -Force $PanelHome -ErrorAction SilentlyContinue
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if ($machinePath -like "*$PanelHome\bin*") { [Environment]::SetEnvironmentVariable("Path", (($machinePath -split ";") | Where-Object { $_ -and $_ -ne "$PanelHome\bin" }) -join ";", "Machine") }
  Write-Host ""
  Write-Host "  ToutPanel est désinstallé." -ForegroundColor Green
  if (Test-Path $archive) { Write-Host "  Archive des données du panel : $archive" }
  Write-Host "  Pour réinstaller : relancez ce script."
  Write-Host ""
  exit 0
}

# --- Python -------------------------------------------------------------------
Step "Python"
function Find-Python {
  foreach ($c in @("py -3", "python", "python3")) {
    try { $v = & cmd /c "$c -c `"import sys;print(sys.version_info>=(3,9))`"" 2>$null; if ($v -eq "True") { return $c } } catch {}
  }
  return $null
}
$py = Find-Python
if (-not $py) {
  Log "Installation de Python $PythonVersion depuis python.org…"
  $exe = Join-Path $tmp "python-installer.exe"
  Download "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe" $exe
  Start-Process -FilePath $exe -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1" -Wait
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
  $py = Find-Python
  if (-not $py) { Write-Error "Python introuvable après installation. Installez Python 3.9+ manuellement puis relancez."; exit 1 }
}
Log "Python : $(& cmd /c "$py --version")"

# --- Installation existante ? → mise à jour --------------------------------------
if (-not $Reinstall -and (Test-Path "$PanelHome\data\settings.json")) { $Update = $true }
if ($Update) {
  if (-not (Test-Path "$PanelHome\data\settings.json")) { Write-Error "Aucune installation dans $PanelHome : lancez sans -Update."; exit 1 }
  Log "Installation existante détectée dans $PanelHome : mise à jour (comptes, réglages, sites et logiciels conservés)."
  $bk = Join-Path $PanelHome ("backup\panel-update-" + (Get-Date -Format "yyyyMMdd_HHmmss"))
  New-Item -ItemType Directory -Force -Path $bk | Out-Null
  Copy-Item -Recurse -Force "$PanelHome\data" $bk
  Log "Données sauvegardées dans $bk"
  try { $Port = (Get-Content "$PanelHome\data\settings.json" -Raw | ConvertFrom-Json).panel_port } catch {}
  schtasks /End /TN ToutPanel 2>$null | Out-Null
}

# --- Sources ------------------------------------------------------------------
Step ($(if ($Update) { "Mise à jour du panel dans $PanelHome" } else { "Installation du panel dans $PanelHome" }))
New-Item -ItemType Directory -Force -Path $PanelHome, "$PanelHome\wwwroot", "$PanelHome\data" | Out-Null
if (-not $Source -and $PSScriptRoot -and ((Test-Path (Join-Path $PSScriptRoot "pyproject.toml")) -or ((Test-Path (Join-Path $PSScriptRoot "version.json")) -and (Test-Path (Join-Path $PSScriptRoot "dist"))))) { $Source = $PSScriptRoot }
if (-not $Source) {
  $zip = Join-Path $tmp "toutpanel.zip"
  $repo = if ($env:TOUTPANEL_REPO) { $env:TOUTPANEL_REPO.TrimEnd("/") -replace "\.git$", "" } else { "https://github.com/qu3ntin01/toutpanel" }
  Download "$repo/archive/refs/heads/$Branch.zip" $zip
  $srcDir = Join-Path $PanelHome "src"
  if (Test-Path $srcDir) { Remove-Item -Recurse -Force $srcDir }
  $extract = Join-Path $tmp "src-extract"
  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  Expand-Archive -Path $zip -DestinationPath $extract -Force
  $inner = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
  if (-not $inner) { throw "Archive des sources vide ou illisible." }
  Move-Item $inner.FullName $srcDir
  $Source = $srcDir
}
if (-not (Test-Path "$PanelHome\venv\Scripts\python.exe")) { & cmd /c "$py -m venv `"$PanelHome\venv`"" }
$venvPy = "$PanelHome\venv\Scripts\python.exe"
& $venvPy -m pip install --quiet --upgrade pip wheel
# Mode d'installation : sources (pyproject.toml : dépôt de développement) ou roue précompilée (dist\ : dépôt public)
if (Test-Path (Join-Path $Source "pyproject.toml")) {
  Log "Installation depuis les sources ($Source)…"
  & $venvPy -m pip install --quiet --upgrade "$Source"
  if ($LASTEXITCODE -ne 0) { Write-Error "Installation du panel et de ses dépendances Python impossible (pip, code $LASTEXITCODE) : vérifiez l'accès à pypi.org puis relancez."; exit 1 }
} elseif (Test-Path (Join-Path $Source "dist")) {
  # roue du Python de l'environnement : toutpanel-<version>-cp3XY-none-any.whl (bytecode portable, aucune source)
  $pyTag = (& $venvPy -c "import sys;print('cp%d%d' % sys.version_info[:2])").Trim()
  $pyVer = (& $venvPy -c "import sys;print('%d.%d' % sys.version_info[:2])").Trim()
  $wheel = Get-ChildItem -Path (Join-Path $Source "dist") -Filter "toutpanel-*-$pyTag-none-any.whl" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
  if (-not $wheel) {
    $supported = (Get-ChildItem -Path (Join-Path $Source "dist") -Filter "toutpanel-*-cp3*-none-any.whl" -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Name -match "-cp3(\d+)-none-any\.whl$") { "3." + $Matches[1] } } | Sort-Object { [int]($_ -split "\.")[1] } -Unique) -join " "
    Write-Error "Aucune version du panel pour Python $pyVer dans $Source\dist. Versions de Python prises en charge par cette version de ToutPanel : $(if ($supported) { $supported } else { 'aucune' }). Installez l'une d'elles (python.org) puis relancez le script ; si $PanelHome\venv a été créé avec une autre version de Python, supprimez-le d'abord."
    exit 1
  }
  $sums = Join-Path $Source "dist\SHA256SUMS"
  if (Test-Path $sums) {   # intégrité de la roue (sommes publiées avec la version)
    $expected = (Get-Content $sums | Where-Object { $_ -match ("\s" + [regex]::Escape($wheel.Name) + "$") } | Select-Object -First 1) -split "\s+" | Select-Object -First 1
    $actual = (Get-FileHash -Algorithm SHA256 $wheel.FullName).Hash.ToLower()
    if ($expected -and $expected.ToLower() -ne $actual) { Write-Error "Somme de contrôle incorrecte pour $($wheel.Name) : dépôt altéré ou téléchargement incomplet."; exit 1 }
  }
  Log "Installation de $($wheel.Name) (Python $pyVer)…"
  & $venvPy -m pip install --quiet --upgrade $wheel.FullName
  if ($LASTEXITCODE -ne 0) { Write-Error "Installation du panel et de ses dépendances Python impossible (pip, code $LASTEXITCODE) : vérifiez l'accès à pypi.org puis relancez."; exit 1 }
  # pip ne réinstalle pas de lui-même une roue dont le numéro de version n'a pas changé (branche dev) : réinstallation forcée du seul paquet
  & $venvPy -m pip install --quiet --upgrade --no-deps --force-reinstall $wheel.FullName
  if ($LASTEXITCODE -ne 0) { Write-Error "Réinstallation du paquet du panel impossible (pip, code $LASTEXITCODE)."; exit 1 }
} else {
  Write-Error "Dépôt du panel incomplet dans $Source : ni pyproject.toml (sources) ni dist\ (roues précompilées)."; exit 1
}
[Environment]::SetEnvironmentVariable("TOUTPANEL_HOME", $PanelHome, "Machine")
$env:TOUTPANEL_HOME = $PanelHome
$tp = "$PanelHome\venv\Scripts\toutpanel.exe"

# --- Pile web (optionnelle, sans winget) --------------------------------------
if ($Stack) {
  Step "Nginx $NginxVersion"
  if (-not (Test-Path "C:\nginx\nginx.exe")) {
    $nz = Join-Path $tmp "nginx.zip"
    Download "https://nginx.org/download/nginx-$NginxVersion.zip" $nz
    Expand-Archive -Path $nz -DestinationPath $tmp -Force
    Move-Item (Join-Path $tmp "nginx-$NginxVersion") "C:\nginx"
  }
  New-Item -ItemType Directory -Force -Path "C:\nginx\conf\vhost", "C:\nginx\conf\conf.d" | Out-Null
  $conf = Get-Content "C:\nginx\conf\nginx.conf" -Raw
  if ($conf -notmatch "include vhost/\*\.conf;") { $conf = $conf -replace "(?m)^(\s*http\s*\{)", "`$1`r`n    include vhost/*.conf;`r`n    include conf.d/*.conf;" ; Set-Content "C:\nginx\conf\nginx.conf" $conf -Encoding ASCII }
  schtasks /Delete /F /TN ToutPanel-Nginx 2>$null | Out-Null
  # le répertoire de travail doit être C:\nginx : on passe par un lanceur
  "@echo off`r`ncd /d C:\nginx`r`nstart `"`" nginx.exe" | Set-Content "C:\nginx\start-nginx.cmd" -Encoding ASCII
  schtasks /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN ToutPanel-Nginx /TR "C:\nginx\start-nginx.cmd" | Out-Null
  Start-Process -FilePath "C:\nginx\start-nginx.cmd" -WindowStyle Hidden
  Log "Nginx installé dans C:\nginx (démarrage automatique)."

  Step "PHP $PhpVersion (windows.php.net, php-cgi géré par le panel)"
  & $tp php install $PhpVersion --extensions mysql,curl,gd,intl,mbstring,xml,zip,opcache
  if ($LASTEXITCODE -ne 0) { Warn "PHP $PhpVersion non installé : réessayez depuis la page PHP du panel." }

  Step "MariaDB $MariaDBVersion"
  if (-not (Get-Service -Name MariaDB -ErrorAction SilentlyContinue)) {
    $msi = Join-Path $tmp "mariadb.msi"
    Download "https://archive.mariadb.org/mariadb-$MariaDBVersion/winx64-packages/mariadb-$MariaDBVersion-winx64.msi" $msi
    $dbPass = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ })
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" SERVICENAME=MariaDB PASSWORD=$dbPass ALLOWREMOTEROOTACCESS=0 /qn" -Wait
    & $tp dbroot mysql --host 127.0.0.1 --port 3306 --user root --password $dbPass | Out-Null
    $script:DbRootPass = $dbPass
    Log "MariaDB installée (service MariaDB), mot de passe root enregistré dans le panel."
  } else { Log "Service MariaDB déjà présent." }
}

# --- Compte admin et URL sécurisée --------------------------------------------
if ($Update) {
  Step "Migration de la base"
  & $tp migrate
  $entrance = ""
  try { $entrance = (Get-Content "$PanelHome\data\settings.json" -Raw | ConvertFrom-Json).security_entrance } catch {}
  $setup = [pscustomobject]@{ username = "(conservé)"; password = "(conservé)"; entrance = $entrance }
} else {
Step "Compte administrateur et URL sécurisée"
$setupArgs = @("setup", "--json", "--port", "$Port")
if ($Username) { $setupArgs += @("--username", $Username) }
if ($Password) { $setupArgs += @("--password", $Password) }
if ($Entrance) { $setupArgs += @("--entrance", $Entrance) }
$setup = (& $tp @setupArgs) | ConvertFrom-Json
}

# --- Pare-feu Windows ---------------------------------------------------------
Step "Pare-feu"
foreach ($p in @($Port, 80, 443, 21)) {
  netsh advfirewall firewall delete rule name="ToutPanel $p" | Out-Null
  netsh advfirewall firewall add rule name="ToutPanel $p" dir=in action=allow protocol=TCP localport=$p | Out-Null
}

# --- Démarrage automatique (tâche planifiée SYSTEM) ---------------------------
Step "Service (tâche planifiée)"
schtasks /End /TN ToutPanel 2>$null | Out-Null
schtasks /Delete /F /TN ToutPanel 2>$null | Out-Null
schtasks /Create /F /SC ONSTART /RU SYSTEM /RL HIGHEST /TN ToutPanel /TR "`"$venvPy`" -m toutpanel run" | Out-Null
schtasks /Run /TN ToutPanel | Out-Null
Log "Tâche planifiée 'ToutPanel' créée et lancée (démarrage automatique)."

# --- Raccourci CLI ------------------------------------------------------------
$binDir = "$PanelHome\bin"; New-Item -ItemType Directory -Force -Path $binDir | Out-Null
"@echo off`r`nset TOUTPANEL_HOME=$PanelHome`r`n`"$tp`" %*" | Set-Content "$binDir\toutpanel.cmd" -Encoding ASCII
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notlike "*$binDir*") { [Environment]::SetEnvironmentVariable("Path", "$machinePath;$binDir", "Machine") }

# --- Récapitulatif ------------------------------------------------------------
$localIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
if (-not $localIp) { $localIp = "localhost" }
$publicIp = ""
try { $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5 -ErrorAction Stop).ToString().Trim() } catch {}
if ($publicIp -notmatch '^[0-9.]+$') { $publicIp = "" }
$ip = if ($publicIp) { $publicIp } else { $localIp }
$url = "http://$ip`:$Port$($setup.entrance)"
$urlLocal = if ($publicIp -and $publicIp -ne $localIp) { "http://$localIp`:$Port$($setup.entrance)" } else { "" }
# assistant de configuration (#/setup) : lien 24 h à usage unique pour changer l'adresse, l'utilisateur et le mot de passe générés
$setupUrl = if (-not $Update -and $setup.setup_token) { "$url#/setup?token=$($setup.setup_token)" } else { "" }
$info = @(
  "ToutPanel — informations d'installation ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))",
  "URL du panel      : $url",
  "URL locale        : $(if ($urlLocal) { $urlLocal } else { $url })",
  "Utilisateur       : $($setup.username)",
  "Mot de passe      : $($setup.password)",
  "Entrée sécurisée  : $($setup.entrance)",
  "Répertoire        : $PanelHome"
)
if ($setupUrl) { $info += "Assistant de configuration : $setupUrl"; $info += "  (24 h, usage unique : changer l'adresse, l'utilisateur et le mot de passe ; nouveau lien : toutpanel setup-link)" }
if ($script:DbRootPass) { $info += "MariaDB root      : $($script:DbRootPass)" }
$info | Set-Content "$PanelHome\data\install-info.txt" -Encoding UTF8

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "  ToutPanel est installé !" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "  URL du panel     : $url"
if ($urlLocal) { Write-Host "  URL locale       : $urlLocal   (depuis votre réseau)" }
Write-Host "  Utilisateur      : $($setup.username)"
Write-Host "  Mot de passe     : $($setup.password)"
if ($setupUrl) {
  Write-Host ""
  Write-Host "  Assistant de configuration : $setupUrl"
  Write-Host "  Ce lien (24 h, une seule utilisation) permet de changer l'adresse du panel, l'utilisateur et le mot de passe générés ci-dessus."
  Write-Host "  Nouveau lien : toutpanel setup-link"
}
if ($script:DbRootPass) { Write-Host "  MariaDB root     : $($script:DbRootPass)" }
Write-Host ""
Write-Host "  Ces informations sont enregistrées dans : $PanelHome\data\install-info.txt"
Write-Host "  L'URL contient l'entrée sécurisée : sans elle, le panel répond 404."
Write-Host "  Commandes : toutpanel info | check | passwd | entrance | port | restart | setup-link | php install 8.2"
