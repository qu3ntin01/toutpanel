<div align="center">

# ToutPanel

**The web hosting control panel for Linux and Windows: sites, PHP, databases, mail, DNS, SSL, security and backups from a single web interface, in 10 languages.**

Nginx · Apache · OpenLiteSpeed *(experimental)* · IIS · PHP 5.6 → 8.5 · MariaDB · MySQL · PostgreSQL · MongoDB · Postfix / Dovecot · BIND / PowerDNS / Knot · Let's Encrypt · WAF / ToutWAF · firewall · Docker · multi-tenant · multi-server

![Version](https://img.shields.io/badge/version-0.4.0b2-2b5fd9?style=flat-square)
![Channel](https://img.shields.io/badge/channel-developer%20(beta)-f59e0b?style=flat-square)
![Systems](https://img.shields.io/badge/systems-Linux%20%7C%20Windows-0f172a?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.9%20%E2%86%92%203.14-3776ab?style=flat-square)
![Languages](https://img.shields.io/badge/languages-10-8b5cf6?style=flat-square)
![Personal edition](https://img.shields.io/badge/Personal%20edition-free-10b981?style=flat-square)

[Install](#full-installation) · [What's new in 0.4](#whats-new-in-040-beta) · [Features](#features) · [CMS](#cms) · [Screenshots](#screenshots) · [Themes](#themes) · [Editions](#editions) · [Architecture](#architecture) · [First start](#first-start) · [Troubleshooting](#troubleshooting) · [Français](README.md)

**Version 0.4.0b2** · **developer (beta)** channel · 2026-10-04

</div>

![ToutPanel dashboard, Horizon theme](screenshots/dashboard.webp)

> **Development branch (beta).** Test builds, not guaranteed: for the stable version use the [`main`](https://github.com/qu3ntin01/toutpanel) branch. Install: `curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/dev/install.sh | sudo bash -s -- --channel dev`.

---

## What is ToutPanel?

ToutPanel turns a freshly installed server into a **complete web hosting platform**, managed from your browser. One command installs the stack (by default Nginx, PHP-FPM, MariaDB, Redis or Valkey, Certbot, Fail2ban, or the stack you compose: profiles, versions, web server, FTP, mail, DNS, accelerators), the panel and its service; you then create sites, databases, mailboxes, DNS zones and certificates in a few clicks, without editing a single configuration file.

It is built both for people hosting **their own sites** (free Personal edition, no key, no sign-up) and for **agencies and hosting providers** reselling hosting: reseller and client accounts, plans and quotas, billing, white label, multi-server and high availability (Professional and Enterprise editions).

Your data stays **on your server**: no external fonts or CDN in the interface, and no call to the licence server unless a licence is activated.

> **This repository contains no source code.** It only publishes what is needed to install the panel: the `install.sh` and `install.ps1` installers, the compiled panel (`dist/`, "bytecode only" Python wheels), the release notes, the licence and `version.json`.

| | |
|---|---|
| **Systems** | Linux: Debian 11+, Ubuntu 20.04+, AlmaLinux / Rocky Linux / RHEL / CentOS Stream / Oracle Linux 8+, Fedora, with other families on a reduced stack (openSUSE, Arch, Alpine, Amazon Linux…) and a displayed **support level** (`toutpanel compat`); Windows 10 / 11, Windows Server 2016 → 2025 |
| **Web servers** | Nginx, Apache, Nginx + Apache, **OpenLiteSpeed** *(experimental, with LSPHP and LSCache)*, IIS (basic) |
| **Software stack** | **composer**: profiles, versions, diagram, resumable installation, real state; accelerators (OPcache, JIT, Redis / Valkey, Memcached, Varnish*, Brotli, Zstandard*, HTTP/3*) |
| **PHP** | 5.6 to 8.5 side by side, 138 extensions in the catalogue, one version per site |
| **Databases** | MariaDB, MySQL (distribution, or Oracle 8.4 / 9.x*), Percona Server*, PostgreSQL, MongoDB, SQLite, per-account Redis / Memcached |
| **FTP, DNS, mail** | FTP: built-in, Pure-FTPd*, ProFTPD*, vsftpd*, SFTP only* · DNS: BIND, PowerDNS, Knot · mail: Postfix + Dovecot, Exim* · one engine at a time, switch with rollback |
| **Firewall** | managed by the panel (nftables, ufw, firewalld, CSF, iptables) **or upstream**, anti-lockout guard |
| **CMS** | 595 CMS and applications in the catalogue (582 verified: 536 free, 46 commercial), version of your choice, tracked and updated installations |
| **Interface** | 10 languages, 13 light / dark themes (**Horizon** by default), any accent colour, WCAG AA accessibility |
| **Installers** | `install.sh` and `install.ps1` in 10 languages (English by default, `--lang` / `--fr`…, `TOUTPANEL_LANG`, system language), stack and firewall options, specific version (`--version`), an [installation assistant](https://toutpanel.com/installation-assistant) that generates the command |
| **Automation** | REST API (OpenAPI), 76-command CLI, signed webhooks, Ansible modules, Terraform examples |

<sub>\* *experimental*: real and tested, but less proven or with limits declared in the interface and in the [known limitations](#known-limitations).</sub>

## What's new in 0.4.0 (beta)

**0.4.0b2** is a **pre-release** published on the [`dev`](https://github.com/qu3ntin01/toutpanel/tree/dev) branch: not guaranteed, to be tried on a test server before any production use. Every feature carries its maturity: **stable**, **experimental** (real and tested, but less proven or with declared limits) or **coming soon** (visible, greyed out, never simulated).

| What's new | Maturity |
|---|---|
| **Simultaneous HTTP and HTTPS** panel listeners (8888 / 8443, self-signed certificate at first) | stable |
| **Install a specific version**: `--version X.Y.Z`, `--list-versions` | stable |
| **`/var/toutpanel` as the default directory** (an existing installation in `/www/toutpanel` is detected and kept) | stable |
| **Firewall managed by the panel or upstream** (cloud security group, hosting provider's firewall), dedicated page, ports to open, **60-second anti-lockout guard** | stable |
| **Stack composer**: profiles, versions, architecture diagram, memory / disk estimate, **9-step first-run setup wizard**, **Software stack** page (real state) | stable |
| **DNS engines**: BIND, PowerDNS, Knot DNS (one at a time, switch with zone migration and rollback) | stable |
| **Mail engines**: Postfix + Dovecot, external relay; **Exim + Dovecot** | stable; Exim: **experimental** |
| **FTP engines**: built-in server, **Pure-FTPd, ProFTPD, vsftpd, SFTP only** | built-in: stable; other engines: **experimental** |
| **OpenLiteSpeed** with LSPHP and LSCache (switch from Nginx / Apache with rollback) | **experimental** |
| **Accelerators**: OPcache, JIT, APCu, Redis / Valkey, Memcached, FastCGI cache, Brotli; **Varnish, Zstandard, HTTP/3** | Varnish, Zstandard, HTTP/3: **experimental**; others: stable |
| **Databases**: MariaDB 10.6 → 11.8, **MySQL 8.4 / 9.x** (Oracle repository), **Percona Server**, PostgreSQL 13 → 18 | Oracle MySQL and Percona: **experimental** |
| **Remote ToutWAF**: link the panel to a ToutWAF installed on another server | new (Professional edition) |
| **Extended distribution compatibility** with support levels (`toutpanel compat`) | stable |
| **Multilingual installer** with stack options (`--profile`, `--web`, `--php`, `--db`, `--ftp`, `--mail`, `--dns`, `--accel`…), `--firewall`, `--waf-*`, and an **[installation assistant](https://toutpanel.com/installation-assistant)** on the website that generates the command line | stable |
| Apache + mod_php, Caddy | **coming soon** (cleanly refused, never simulated) |

Details and limits: [Known limitations](#known-limitations) · [CHANGELOG.md](CHANGELOG.md) (in French).

## Features

### Web hosting
- **One-click sites**: multiple domains, PHP-FPM, static, reverse proxy, applications; **Nginx, Apache, Nginx + Apache, OpenLiteSpeed *(experimental)* or IIS** vhosts generated from Jinja2 templates and **tested before reload** (`nginx -t` / `apachectl -t`, last valid vhosts restored on failure).
- **Multiple PHP versions**: 5.6 → 8.5 side by side (Sury, ondrej PPA, Remi, windows.php.net), 138 extensions, ionCube, per-site `php.ini` and FPM pool, default CLI version.
- **Advanced hosting**: redirects, canonical host, headers, protected directories, error pages, anti-hotlinking, maintenance mode, FastCGI cache, staging, GoAccess statistics, load balancing (round robin, least_conn, ip_hash), compression, HTTP/2, HTTP/3, TLS profiles.
- Atomic per-site **Git deployment** (HTTPS with token or SSH, branch, tag or commit, automatic refresh, rollback).
- **Domains and IP addresses**: IP inventory, persistent additional IPs, IPs dedicated to an account, per-site listen address.
- **OpenLiteSpeed** *(experimental)*: installed from the official LiteSpeed repository (Debian / Ubuntu and the Red Hat family), **LSPHP** per PHP version, one `vhconf` per site, **LSCache**, switch from Nginx / Apache **with rollback**; features this server does not reproduce (built-in WAF, ModSecurity, country filtering…) are **reported**, never silently ignored.

### Software stack and accelerators
- **Stack composer**: starting profiles (single site, multi-site, hosting provider, high performance, application, mail only, DNS only, node, LAMP…) adapted to the detected memory, choice of web server, PHP (5.6 → 8.5 side by side), databases, FTP, mail, DNS, security, runtimes and tools; an **architecture diagram** updated at every choice (SVG / PNG export), estimated memory and disk, automatic tuning proportional to RAM.
- **One engine, three entry points**: the **setup wizard** (9 steps: welcome, account, address, preferences, profile, composition, stack summary, firewall, summary), the **Settings › Software stack** page (real state, adding a component, changing a version) and the `toutpanel stack` command line (also called by the installer).
- **Resumable and idempotent** installation: each step first checks whether it is already satisfied, a failed step is never counted as successful; "coming soon" components are visible but refused, without simulation.
- **Accelerators** (dedicated page): OPcache, PHP JIT, APCu, Redis / Valkey, Memcached, FastCGI cache, Brotli; **Varnish** *(experimental: HTTP only)*, **Zstandard** and **HTTP/3** *(experimental: depending on the module or build of Nginx, otherwise an explained refusal)*, with real state, memory, settings, "Clear cache" and displayed limits.

### SSL / TLS
- **Let's Encrypt** (HTTP-01, DNS-01, wildcard), ZeroSSL, Buypass, custom ACME authority, CSR, PFX import, self-signed, HSTS, **automatic renewal**.
- **Certificates** page: validity, issuer and expiry of every certificate; panel HTTPS with Let's Encrypt; SNI certificates for the mail server.

### DNS
- Zones served by **BIND, PowerDNS or Knot DNS** (one local server at a time; switch with migration of zones and DNSSEC keys, rollback), every record type, templates, **DNSSEC**, secondary servers (TSIG), reverse DNS, BIND import / export.
- Zones pushed to **Cloudflare, PowerDNS, OVH, Route53**; propagation check.

### Mail and webmail
- **Postfix, Dovecot, OpenDKIM** or rspamd; **Exim + Dovecot** as an alternative *(experimental: subset of Postfix, declared limits, switch with migration of domains, mailboxes and DKIM keys)*; domains, mailboxes, aliases, forwarders, mailing lists (mlmmj), Sieve filters and autoresponder.
- **Roundcube or SnappyMail webmail** installed in one click, with direct login from the panel.
- DKIM rotation, antispam, ClamAV, greylisting, RBL, sending rate limits, outbound relay, message tracking, mail queue, fetchmail, CalDAV / CardDAV, MTA-STS, client autoconfiguration.

### Databases
- **MariaDB (10.6 → 11.8), MySQL, Percona Server, PostgreSQL (13 → 18), MongoDB, SQLite**: databases, users and privileges, remote access by IP, **Adminer and phpMyAdmin with SSO** (any version, PHP compatibility checked), import / export, maintenance, size quotas.
- Additional servers (Docker), **per-account Redis / Memcached**, version detection, official MariaDB and PostgreSQL (PGDG) repositories, major version upgrade with prior backup, replication (Pro). **MySQL 8.4 LTS / 9.x** (Oracle repository) and **Percona Server** are *experimental* (one MySQL-family engine at a time, prior backup mandatory).

### Files, FTP and access
- Full **file manager**: CodeMirror editor, archives, trash, permissions and owner, content search, disk usage, drag and drop.
- **Built-in FTP / FTPS server** (accounts, rights, quotas, log) or, as you prefer, **Pure-FTPd, ProFTPD, vsftpd or SFTP only** *(experimental: panel accounts synchronised, per-engine capability table, switch with rollback)*, **chrooted SFTP**, restricted shell, SSH keys, **WebDAV** with FTP accounts.
- **Web terminal**: bash on Linux, PowerShell on Windows.

### CMS
- **CMS page**: a catalogue of **595 CMS and web applications**, **582 of them verified** (version source queried, download URL checked): **536 free** and **46 commercial**; search, filters by category, type (PHP, Node.js, Python, Go, Java, .NET, static) and distribution, "ready" or "missing requirements" badge.
- **Version of your choice**: latest stable by default, every published version (pre-releases on request); a sheet with checked requirements, existing or new site, subfolder, database created for you, administrator account and language, live progress.
- **Centralised installations**: automatic detection on every site (including installations made outside the panel), installed and latest version, banner of available updates; **backup** (files and database), **update** with a backup first and rollback on failure, **Update all**, **cloning** to another site or subfolder, reinstall, removal, operation log, automatic minor updates per installation.
- **Commercial software**: sheet with vendor, indicative price and purchase link; installed from the **package you provide** (upload from the sheet, path on the server or private URL) with its licence key; updates by package.
- **Local version search**: the panel queries the official sources itself (wordpress.org, GitHub, Packagist, npm, PyPI, vendor sites) with a 6-hour local cache, **twice a day** (05:23 and 17:23, configurable) or on demand; alerts through the notification channels, menu badge and dashboard widget.

### Applications, WordPress and Docker
- **Application installer**: WordPress, Joomla, Drupal, Grav, PrestaShop, Nextcloud, Laravel, Symfony, Matomo, Dolibarr, Moodle, phpBB, MediaWiki, Ghost — download, database, configuration and post-install steps done for you.
- **WP Toolkit** (WordPress tab of the CMS page): wp-cli, updates, hardening, vulnerability detection, cloning.
- **Node.js, Python, Ruby, Go, Java, .NET** applications with systemd unit and proxy.
- **Docker**: containers, images, `docker run`, per-account **Docker Compose** projects with a proxy site.

### Backups
- Back up a site, database, folder, mailbox, account or the **whole server**; GFS schedules; granular restore; automatic safety backups (before a deletion, for instance); backup verification.
- Encrypted, deduplicated **restic** engine, **remote destinations**: S3 and compatible, SFTP, Backblaze B2, and through rclone FTP / Google Drive / OneDrive / Dropbox / WebDAV (Pro). Secrets are encrypted in the database and never returned by the API.

### Security
- **Firewall**: nftables, firewalld, UFW, CSF or iptables (auto-detected), **managed by ToutPanel or upstream** (cloud security group, hardware or hosting-provider firewall: the panel then touches no system rule and lists the **ports to open at your provider**); rules, IP lists, predefined services, listening ports and exposure, anti-DDoS protection, **60-second guard**: without confirmation the server itself reverts the change.
- **Fail2ban**, **built-in WAF** (SQLi, XSS, RCE, path traversal, scanners, bots, rate limiting, automatic banning; country blocking in Pro) and per-site **ModSecurity + OWASP CRS** (Pro).
- **ToutWAF**, the vendor's WAF / reverse proxy, is the **recommended engine** in WAF › Engine (Pro): installed from the panel by its official installer (stable or dev channel, web server moved to fallback ports), secret **console** links (:9443), installed and available version, update with rollback, diagnostics, site **synchronisation** (local policy or console API); also at install time with `install.sh --waf toutwaf`. **BunkerWeb** and **SafeLine** (Docker) are still offered.
- **Remote ToutWAF**: the panel can link to a ToutWAF installed on **another server** (WAF › Engine › Mode “Remote”, or `toutpanel waf connect toutwaf`): sites declared through the REST API, console certificate pinned by fingerprint, encrypted token, firewall restriction of 80 / 443 to the ToutWAF only, monitoring and alerts.
- **Antimalware**: ClamAV / maldet / YARA with quarantine, integrity checks (rkhunter, chkrootkit, debsums, AIDE), AppArmor and **SELinux** configured automatically.
- **Authentication**: TOTP 2FA and recovery codes, **WebAuthn security keys / passkeys**, secret login path, IP allow list, ALTCHA captcha, persistent lockout, revocable sessions; LDAP / Active Directory, OpenID Connect and SAML (Pro).
- **Sealed audit log** (chained HMAC), "Recommendations" card on the Security page.

### Monitoring and alerts
- Customisable dashboard: **23 widgets** (CPU, RAM, disks, I/O, network, services, quotas, notes…), layout saved per user.
- Historical **monitoring**, HTTP(S) **uptime** probes, per-account processes, live logs, services with automatic restart.
- **Alerts** by e-mail, webhook, Telegram or SMS (service down, disk full, certificate expiring…), **Prometheus** `/metrics` export (Pro).
- Host administration: hostname, time zone, NTP, swap, system updates (security, automatic, reboot required), task queue, **self-repair**.

### Multi-tenant, resellers and billing
- **Administrator → resellers → clients → sub-users** hierarchy, permissions per module and action, access profiles.
- **Plans and quotas** (disk, inodes, traffic, sites, databases, mailboxes…), CPU / RAM / I/O limits (cgroups), dedicated system user, automatic suspension, "log in as", transfer, CSV import / export.
- **Billing** (VAT, proration, reminders, PDF), Stripe, PayPal, bank transfer, provisioning on order, WHMCS / Blesta / HostBill, **white label**, transactional e-mails, support tickets, announcements (Pro).

### Multi-server and high availability
- **Master panel and nodes** enrolled with a token (web, mail, DNS, databases), routed resources, mirror accounts, **account migration** between servers (Pro).
- **High availability**: web groups (rsync, lsyncd, NFS), MariaDB / PostgreSQL replication with failover, automatic secondary DNS and secondary MX, live migration (Pro).
- **Migration** from cPanel, Plesk, DirectAdmin, ISPConfig, shared hosting or IMAP mailboxes, with a report (Pro; export stays free).

### API, CLI and automation
- Complete **REST API** with scoped, IP-restricted tokens and **OpenAPI / Swagger** documentation.
- **Signed outgoing webhooks**, pre / post-action scripts, `toutpanel` **CLI** (site, account, db, mail, dns, backup, cron, ftp, task… with `--json` output), Ansible modules and Terraform examples.

### Store, customisation and comfort
- **Store** connected to the toutpanel.com catalogue: applications, server software, **modules** (validated manifest, mandatory sha256, hot loading), themes; local zip upload, offline mode.
- **Setup wizard** at the end of the installation (account, panel address, language, mode, theme, **main colour** and **density** with instant preview), **creation wizard** (site + database + certificate + mailboxes at once), **Ctrl+K global search**, contextual help on every page, diagnostic tools (DNS, HTTP, SSL, ping, traceroute, port, SMTP, WHOIS).
- **13 themes**, with **Horizon** by default, any accent colour, logo, CSS, menu links, vhost and e-mail templates; **10 languages**: français, English, español, Deutsch, italiano, português, Nederlands, русский, 中文, العربية (right-to-left).

### Compliance (GDPR)
- Personal data export and erasure, record of processing activities, log retention, password history, traceability of host access, external anchoring of the audit log (Pro).

## Screenshots

| | |
|---|---|
| ![Dashboard, dark mode](screenshots/dashboard-dark.webp)<br>**Dashboard, dark mode**: gauges, counters, attention points, licence | ![Websites](screenshots/sites.webp)<br>**Websites**: domains, type, root, traffic, SSL and actions |
| ![PHP](screenshots/php.webp)<br>**PHP**: versions 5.6 → 8.5 side by side, support status, FPM pools | ![Git deployment](screenshots/git.webp)<br>**Site settings**: Git deployment, SSL, redirects, security |
| ![DNS](screenshots/dns.webp)<br>**DNS**: BIND zones or providers, templates, DNSSEC, cluster | ![SSL certificates](screenshots/certs.webp)<br>**Certificates**: validity, issuer, renewal, panel certificate |
| ![Mail server](screenshots/mail.webp)<br>**Mail server**: Postfix, Dovecot, OpenDKIM, ports and tabs | ![Webmail](screenshots/webmail.webp)<br>**Webmail**: Roundcube or SnappyMail installed in one click |
| ![Databases](screenshots/databases.webp)<br>**Databases**: MariaDB, PostgreSQL, MongoDB, SQLite, Redis | ![Files](screenshots/files.webp)<br>**Files**: editor, archives, trash, permissions, disk usage |
| ![CMS](screenshots/cms.webp)<br>**CMS › Install**: 582 verified CMS and applications, search, filters, "ready" badge | ![Installation sheet](screenshots/cms-app.webp)<br>**CMS sheet**: checked requirements, version choice, target site, database |
| ![CMS installations](screenshots/cms-installed.webp)<br>**CMS › Installations**: versions, available updates, backup, cloning | ![WAF › Engine](screenshots/waf-engine.webp)<br>**WAF › Engine**: ToutWAF recommended, built-in WAF, BunkerWeb, SafeLine |
| ![Terminal](screenshots/terminal.webp)<br>**Terminal**: interactive bash / PowerShell shell in the browser | ![Applications](screenshots/apps.webp)<br>**Applications**: WordPress, Joomla, Drupal, PrestaShop, Nextcloud… |
| ![Store](screenshots/software.webp)<br>**Store**: server software, modules and themes in one click | ![Security](screenshots/security.webp)<br>**Security**: recommendations, firewall, anti-DDoS, Fail2ban |
| ![WAF](screenshots/waf.webp)<br>**WAF**: protections, thresholds, engines, GeoIP, attack log | ![Monitoring](screenshots/monitor.webp)<br>**Monitoring**: CPU, memory, network, load and disk from 1 h to 7 days |
| ![Accounts](screenshots/accounts.webp)<br>**Accounts**: resellers, clients, plans, access profiles | ![Servers](screenshots/nodes.webp)<br>**Servers**: master panel, nodes, routing, migration |
| ![Updates](screenshots/updates.webp)<br>**Updates**: system packages (security) and the panel itself | ![Settings](screenshots/settings.webp)<br>**Settings**: access, port, secret path, HTTPS, interface |
| ![Setup wizard](screenshots/setup.webp)<br>**Setup wizard**: theme, main colour, density, instant preview | ![Horizon light and dark](screenshots/horizon.webp)<br>**Horizon**, the default theme: the same screen in light and dark |

**What's new in 0.4.0 (beta)** — screenshots of a demonstration server (documentation addresses):

| | |
|---|---|
| ![Wizard: server profile](screenshots/setup-profil.webp)<br>**Setup wizard, Profile step**: starting profiles, detected memory, recommended profile | ![Wizard: stack composition](screenshots/setup-pile.webp)<br>**Stack composition**: choices by category, architecture diagram, validation and estimated resources |
| ![Stack installation](screenshots/pile-progression.webp)<br>**Stack installation**: progress, steps, resume after an error | ![Wizard: firewall](screenshots/setup-pare-feu.webp)<br>**Wizard, Firewall step**: managed by ToutPanel or upstream, ports that will be opened |
| ![Software stack](screenshots/pile-etat.webp)<br>**Settings › Software stack**: real state, installed versions, diagram of this server | ![Software stack, dark mode](screenshots/pile-etat-dark.webp)<br>**Software stack**, dark mode |
| ![Accelerators](screenshots/accelerators.webp)<br>**Accelerators**: OPcache, JIT, APCu, Redis, Memcached, FastCGI, Varnish… with state, memory and limits | ![OpenLiteSpeed](screenshots/openlitespeed.webp)<br>**OpenLiteSpeed** *(experimental)*: installation, LSPHP, web server switch, WebAdmin |
| ![Firewall](screenshots/firewall.webp)<br>**Security › Firewall**: engine, management mode, guard, rules | ![Exposed ports](screenshots/firewall-ports.webp)<br>**Listening ports and exposure**: exposed, restricted, protected |
| ![Upstream firewall](screenshots/firewall-amont.webp)<br>**Upstream firewall**: ports to open at your provider, to copy or download | ![Firewall, dark mode](screenshots/firewall-dark.webp)<br>**Firewall**, dark mode |
| ![DNS engines](screenshots/dns-engines.webp)<br>**DNS › Engine**: BIND, PowerDNS, Knot DNS, external provider | ![Mail engines](screenshots/mail-engines.webp)<br>**Mail server › Engine**: Postfix, Exim *(experimental)*, external relay |
| ![FTP engines](screenshots/ftp-engines.webp)<br>**FTP › Engine**: built-in, Pure-FTPd, ProFTPD, vsftpd, SFTP *(experimental)* | ![Remote ToutWAF](screenshots/waf-remote.webp)<br>**Remote ToutWAF**: panel linked to a ToutWAF on another server |
| ![Distribution banner](screenshots/compat.webp)<br>**Dashboard**: "reduced-stack distribution" banner according to the support level | |

**On mobile**, the interface adapts (collapsible menu, scrollable tables):

<table>
<tr>
<td align="center"><img src="screenshots/dashboard-mobile.webp" width="240" alt="Dashboard on mobile"><br><b>Dashboard</b></td>
<td align="center"><img src="screenshots/sites-mobile.webp" width="240" alt="Websites on mobile"><br><b>Websites</b></td>
</tr>
</table>

> Screenshots taken on a demonstration server (Ubuntu 24.04, documentation address 192.0.2.2, example domains), with the interface in French.

## Themes

### 13 themes, your colour

A new installation uses **Horizon**: a blue-cyan gradient sky, floating translucent menu and top bar, an active pill in a blue-violet gradient that follows the chosen colour, very bold blue headings. **Customisation › Appearance**: pick another design, then **any accent colour** (12 presets, colour picker or `#RRGGBB` code). The panel derives buttons, links, active menu, badges, gradients and charts from it while keeping a contrast ratio of at least 4.5:1. Every theme comes in **light and dark**, supports high contrast and right-to-left languages; the preview is instant and nothing is saved before "Save design". Density, corners, font, width, menu position, icons and animations can also be set, per user or as the default for everyone; themes can be exported and imported.

![Theme and colour picker](screenshots/custom.webp)

| | | |
|---|---|---|
| ![Horizon](screenshots/theme-horizon.webp)<br>**Horizon** *(default)* · `#2b5fd9` | ![Classique](screenshots/theme-classique.webp)<br>**Classique** · `#2563eb` | ![Aurora](screenshots/theme-aurora.webp)<br>**Aurora** · `#2563eb` |
| ![Nuage](screenshots/theme-nuage.webp)<br>**Nuage** · `#5b5bd6` | ![Minimal](screenshots/theme-minimal.webp)<br>**Minimal** · `#18181b` | ![Nuit](screenshots/theme-nuit.webp)<br>**Nuit** · `#0369a1` |
| ![Terminal](screenshots/theme-terminal.webp)<br>**Terminal** · `#15803d` | ![Gloss](screenshots/theme-gloss.webp)<br>**Gloss** · `#7c3aed` | ![Nébuleuse](screenshots/theme-nebuleuse.webp)<br>**Nébuleuse** · `#8b5cf6` |
| ![Obsidian](screenshots/theme-obsidian.webp)<br>**Obsidian** · `#22c55e` | ![Nordic](screenshots/theme-nordic.webp)<br>**Nordic** · `#14b8a6` | ![Ember](screenshots/theme-ember.webp)<br>**Ember** · `#f97316` |
| ![Executive](screenshots/theme-executive.webp)<br>**Executive** · `#10b981` | | |

<sub>Colour shown: the theme's default accent in light mode, freely changeable.</sub>

Theme, mode, **main colour** and **density** can also be chosen right in the **setup wizard** (Preferences step), with an instant preview; they become the defaults for every account, and each user can then pick their own.

## Editions

The program is the same for every edition: a **licence key** unlocks the advanced features on a given server. A fresh installation runs the Personal edition, with no sign-up and no Internet connection required.

| Edition | Price | Key | For |
|---|---|---|---|
| **Personal** | free, no time limit | none | personal use: your own sites, **up to 5** |
| **Professional** | paid | required | hosting providers, agencies, professional use: everything included, unlimited sites (or per licence plan) |
| **Enterprise** | paid | required | Professional + unlimited multi-server + priority support |

The Personal edition is **complete**: sites, multiple PHP versions, databases, mail, DNS, SSL, built-in WAF, local backups, monitoring, client accounts and sub-users, WebAuthn, GDPR tools, API and CLI. Reserved for the paid editions:

<details>
<summary><b>Exact list of Professional / Enterprise features</b></summary>

| Feature | Personal | Professional |
|---|---|---|
| Sites | 5 maximum | unlimited (or per licence) |
| Uptime probes | 3 | unlimited |
| Outgoing webhooks | 2 | unlimited |
| WAF engine choice (ToutWAF, BunkerWeb, SafeLine) | built-in WAF | ✓ |
| ModSecurity + OWASP CRS | — | ✓ |
| Multi-server: nodes, high availability, live migration | — | ✓ |
| Web groups and DNS cluster | — | ✓ |
| Database replication | — | ✓ |
| Billing, payment gateways, WHMCS, provisioning | — | ✓ |
| Reseller white label | — | ✓ |
| Custom panel domain | — | ✓ |
| Support (tickets) | — | ✓ |
| Announcements | — | ✓ |
| Reseller accounts | — (clients and sub-users: ✓) | ✓ |
| LDAP / OpenID Connect / SAML SSO | — (WebAuthn: ✓) | ✓ |
| Country blocking (GeoIP) | — | ✓ |
| Scheduled antimalware | manual scan | ✓ |
| Remote backups (S3, SFTP, B2, rclone) | local storage | ✓ |
| restic engine | — | ✓ |
| Prometheus `/metrics` export | — | ✓ |
| Import from cPanel, Plesk, DirectAdmin, ISPConfig, shared hosting, IMAP | — (export: ✓) | ✓ |
| Premium store modules | — | ✓ |
| External anchoring of the audit log | — (GDPR export and purge: ✓) | ✓ |

</details>

- Affected menu entries carry a **Pro** badge; pages remain viewable, only creating and editing are reserved.
- Activation: **Settings › Licence › Activate a key** (`TP-XXXXX-XXXXX-XXXXX-XXXXX`) or `toutpanel licence activate <key>`. The signed token is verified locally: the licence works offline (daily revalidation, 15-day grace period).
- If the licence expires or becomes invalid, the panel **falls back to the Personal edition without deleting anything**.

Pricing and purchase: **[toutpanel.com/tarifs](https://toutpanel.com/tarifs)** · details: [Editions and licence](https://toutpanel.com/docs/guide/editions/).

## Architecture

```mermaid
flowchart TB
    U["Browser<br/>admin · reseller · client"] -->|"HTTP :8888 / HTTPS :8443 + secret path"| P
    V["Visitors"] -->|"HTTP / HTTPS 80 · 443"| W
    subgraph S["Your server"]
        P["<b>ToutPanel</b><br/>FastAPI + Uvicorn · SQLite<br/>scheduler · built-in FTP · REST API"]
        subgraph PILE["Services driven by the panel"]
            W["Nginx / Apache / OpenLiteSpeed* / IIS"]
            F["PHP-FPM 5.6 → 8.5"]
            D[("MariaDB · MySQL · PostgreSQL<br/>MongoDB · Redis")]
            M["Postfix / Exim* · Dovecot · OpenDKIM"]
            B["BIND / PowerDNS / Knot (DNS)"]
            X["systemd · firewall (or upstream)<br/>Fail2ban · Docker"]
        end
        R[("/www/wwwroot<br/>site roots")]
        P ==>|"generated and tested configurations"| PILE
        W --> R
        F --> R
    end
    P -. "token API" .-> N["Other ToutPanel servers<br/>(nodes, multi-server)"]
```

| Component | Role |
|---|---|
| **Panel** | FastAPI application served by Uvicorn (`toutpanel` systemd service on Linux, `ToutPanel` scheduled task on Windows). Web interface with no external dependency, REST API, task scheduler, built-in FTP server. |
| **Web stack** | Nginx and/or Apache (OpenLiteSpeed with LSPHP: experimental; IIS on Windows) with PHP-FPM; the panel writes vhosts from its templates, tests them, then reloads the service. The **stack composer** chooses and evolves the software. |
| **Services** | MariaDB / MySQL / PostgreSQL / MongoDB, Postfix (or Exim*) / Dovecot / OpenDKIM, BIND (or PowerDNS, Knot), FTP (built-in or Pure-FTPd*, ProFTPD*, vsftpd*), Fail2ban, firewall, Docker: driven by the panel through their native tools. |
| **`toutpanel` CLI** | Panel administration (port, secret path, password, update, licence…) and scriptable business commands (`--json`). |

<sub>\* experimental</sub>

```
<home>  (/var/toutpanel or C:\toutpanel)
├── data/      panel SQLite database, settings.json, keys, install-info.txt
├── logs/      panel.log and site logs
├── vhost/     generated vhosts (when the web server's native folder is missing)
├── ssl/       site and panel certificates
├── backup/    local backups
├── src/       clone of this repository (channels, tags, toutpanel update)
└── venv/      panel Python environment
/www/wwwroot   site roots (C:\toutpanel\wwwroot on Windows)
```

## Full installation

### Requirements

| | Linux | Windows |
|---|---|---|
| **Systems** | **full** level: Debian 11 and later, Ubuntu 20.04 and later, AlmaLinux / Rocky Linux / RHEL / CentOS Stream / Oracle Linux / CloudLinux 8 and later, Fedora · **reduced** level (the panel works, some features are missing): Debian 10, Ubuntu 18.04, CentOS / RHEL 7, Amazon Linux, openSUSE / SLES, Arch, Alpine, Devuan · see [Distribution compatibility](#distribution-compatibility) | Windows 10, 11 · Windows Server 2016, 2019, 2022, 2025 (build 14393 minimum) |
| **Rights** | `root` (or `sudo`) and `bash` | PowerShell 5.1+ **as administrator** (winget not required) |
| **Python** | 3.9 to 3.14 (installed by the script when the distribution provides it) | installed by the script (3.12, python.org) if missing |
| **Memory** | 1 GB minimum (panel only), 2 GB recommended with MariaDB and PHP | same |
| **Disk** | 2 GB free + your sites | same |
| **Network** | outbound HTTPS (GitHub, PyPI, distribution repositories, Let's Encrypt); fixed public IP and reverse DNS for mail | same (python.org, nginx.org, windows.php.net, MariaDB) |

Architectures: `x86_64` and `aarch64` (others: reduced level). Preferably install on a **freshly installed** server. On a server where Nginx, Apache or MariaDB are already configured, use `--stack none`: the panel detects them and writes its vhosts into their native folder without touching anything else.

### Distribution compatibility

The installer and the panel detect the distribution (`/etc/os-release`, architecture) and display a **support level**: `toutpanel compat` lists the known distributions, `toutpanel check` gives the level of your server, and a dashboard banner warns when the level is not "full". There is **never a version ceiling**: a newer version of a known family is treated like the latest known one.

| Level | Meaning | Examples |
|---|---|---|
| **Full** | the complete stack is expected (web server, multi-version PHP, databases in chosen versions, mail, firewall, automatic updates) | Debian 11+, Ubuntu 20.04+ (LTS and interim), AlmaLinux / Rocky / RHEL / CentOS Stream / Oracle Linux 8+, CloudLinux 8 and 9, Fedora, 64-bit Raspberry Pi OS |
| **Reduced** | the panel works, but some features are missing or need manual action (end-of-life system, init without systemd, missing third-party repositories, 32-bit architecture); non-blocking warning | Debian 10, Ubuntu 18.04, CentOS / RHEL 7, Amazon Linux 2 and 2023 (one PHP at a time), openSUSE / SLES, Arch and derivatives, Alpine, Devuan, Kali |
| **Unsupported** | unknown, too old or immutable system: the installer says so and stops | Fedora CoreOS / Silverblue, MicroOS, Flatcar, Gentoo, NixOS, Void |

"Full" describes the level **expected** by the panel; end-to-end validation has not yet been done everywhere (see [Known limitations](#known-limitations)). Python 3.9+ is provided if the system is too old (recent distribution package, or standalone Python verified by SHA-256, with your consent).

### Linux

```bash
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash
```

To read the script before running it:

```bash
curl -sSLO https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh
less install.sh
sudo bash install.sh
```

Installation takes 3 to 6 minutes depending on the connection.

**Installation assistant.** Every option (account, ports, directory, stack, firewall, WAF, version, language…) can be chosen from menus on **[toutpanel.com/installation-assistant](https://toutpanel.com/installation-assistant)**, which generates the command line and checks it live (secrets never appear in clear there).

**Installing this beta or a specific version.** 0.4.0b2 is a pre-release of the `dev` channel:

```bash
# the latest pre-release of the dev channel
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/dev/install.sh | sudo bash -s -- --channel dev
# a specific version (list them with --list-versions)
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/dev/install.sh | sudo bash -s -- --list-versions
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/dev/install.sh | sudo bash -s -- --version 0.4.0b2
```

**Interactive menu.** When run in a terminal without a mode option, the script introduces ToutPanel, detects an existing installation and offers to **install** (full stack) or **install the panel only**, optionally in **node mode**; or, if the panel is already there, to **update**, **fully reinstall** or **uninstall**. It also asks the **firewall** question (ToutPanel / upstream / later) and, once the panel is running, the **stack profile** question. Without a terminal (automation, `--yes`), it asks nothing: it installs, or updates if the panel is present (firewall “later”, default stack).

**What the script does:**

1. installs Python 3.9+ if needed and creates the `<home>/venv` virtual environment;
2. installs the **web stack** (Nginx, PHP-FPM, MariaDB, Redis or Valkey, Certbot, Fail2ban) as before, or the one you compose (`--profile`, `--web`, `--php`, `--db`… passed to `toutpanel stack apply`);
3. clones this repository into `<home>/src`, **checks the SHA-256 sum** of the wheel matching the system Python and installs it;
4. creates a random **administrator account** and **secret access URL**;
5. registers the `toutpanel` **systemd service**;
6. sets up the **firewall** according to `--firewall`: `on` (ToutPanel manages it and opens the ports it needs), `off` (upstream firewall: no system rule, the ports to open at your hosting provider are listed), a question in a terminal, otherwise “later” (nothing is touched);
7. configures **SELinux** (Alma, Rocky, RHEL, Fedora) or **AppArmor** (Debian, Ubuntu, SUSE);
8. prints a summary, saved in `<home>/data/install-info.txt` (readable by root only).

#### `install.sh` options

| Option | Description | Default |
|---|---|---|
| `--stack full` | **deprecated** (see `--profile`): Nginx + PHP-FPM + MariaDB + Redis/Valkey + Certbot + Fail2ban | ✓ |
| `--stack minimal` | Nginx + PHP-FPM + Certbot | |
| `--stack none` | panel only (already configured server) | |
| `--profile NAME` | **stack composer** profile: `single-site`, `multi-site`, `hosting`, `performance`, `application`, `mail-only`, `dns-only`, `node`, `lamp`, `standard`, `custom` (values of the other options: see the table below) | default stack |
| `--web`, `--php`, `--php-default`, `--php-ext`, `--db`, `--redis`, `--accel`, `--ftp`, `--mail ENGINE`, `--dns`, `--security`, `--runtime`, `--tools`, `--install-mode`, `--roles`, `--stack-file`, `--no-tuning` | composer options, passed unchanged to `toutpanel stack apply … --yes` once the panel is installed (a stack failure never fails the panel installation: a resume command is shown) | |
| `--mail` | (alone) adds Postfix, Dovecot, OpenDKIM and opens the mail ports | no |
| `--firewall on\|off\|ask` | who manages the firewall: ToutPanel (`on`), an upstream firewall with no system rule (`off`), a question (`ask`); without a terminal or a value: “later”; never changed by an update | question in a terminal |
| `--firewall-engine nft\|ufw\|firewalld\|csf\|iptables` | engine of the firewall managed by ToutPanel | detected |
| `--dry-run` | prints the detected distribution, directory and planned commands without changing anything (no root) | no |
| `--postgres` | adds PostgreSQL (password of the `postgres` role generated and saved in the panel) | no |
| `--waf toutwaf` | deploys **ToutWAF**, the vendor's WAF, in front of the sites with its official installer (systemd services, no Docker; web server moved to 8080 / 8443, console on 9443, summary in `/etc/toutwaf/INSTALL-SUMMARY.txt`) | no |
| `--waf toutwaf --waf-console URL` | **remote ToutWAF**: links the panel to a ToutWAF installed on another server (no local installation), with `--waf-origin-ip`, `--waf-origin-addr`, `--waf-cert-mode import\|acme`, `--waf-server-id`, `--waf-fingerprint` or `--waf-trust-first-use`, `--waf-restrict` (80 / 443 limited to ToutWAF); the token is given with `--waf-token-file FILE` or `--waf-token-stdin` (never as an argument) | no |
| `--waf bunkerweb` / `--waf safeline` | installs Docker and deploys the external WAF in front of the sites (web server moved to 8080 / 8443, console on 7000 or 9443) | no |
| `--node` | multi-server **node** mode: panel served over HTTPS only, enrolment token, API URL and TLS fingerprint printed (to enter on the master: System › Servers › Add) | no |
| `--master URL` | with `--node`: URL of the master panel | — |
| `--port N` | panel **HTTP** port | `8888` |
| `--https-port N` | panel **HTTPS** port (the panel listens over HTTP **and** HTTPS; self-signed certificate at first) | `8443` |
| `--version X.Y.Z` | installs this published version (also `vX.Y.Z`, `0.4.0b1` or `0.4.0-beta.1`; `TOUTPANEL_VERSION` variable); a pre-release implies the `dev` channel; a version that is not found, or has no package for your Python, stops before anything is changed and lists the versions; a downgrade asks for confirmation (unless `--yes`) | latest of the channel |
| `--list-versions` | lists the published versions (most recent first), then exits without installing anything | |
| `--random-port` | random port between 20000 and 40000 | |
| `--username NAME` | administrator account name | random `admin_xxxxxx` |
| `--password PASS` | administrator password (visible in `ps` and the shell history: prefer the next three options) | 16 random characters |
| `TOUTPANEL_PASSWORD` | environment variable giving the password (kept by `sudo -E`); an option wins over the variable | — |
| `--password-file FILE` | reads the password from a file (readable by root only) | — |
| `--password-stdin` | reads the password from standard input | — |
| `--entrance /path` | secret path in the URL | random `/tp_xxxxxxxxxx` |
| `--home DIR` | panel directory (an existing installation in the former default `/www/toutpanel` is detected and kept) | `/var/toutpanel` |
| `--source DIR` | install from a local folder (copy of this repository with `dist/`) | clone of the branch |
| `--branch NAME` | Git branch to download | `main` |
| `--channel stable\|dev` | panel update channel, saved in the panel | `stable` |
| `--update` | updates an existing installation (detected automatically): data backup, new code, database migration, restart | auto |
| `--reinstall` | forces a full installation even if the panel is present | no |
| `--uninstall` | uninstalls the panel (sites and databases kept, panel data archived) | no |
| `--yes`, `-y` | no questions (menu and confirmations) | no |
| `--lang xx` | installer language and initial panel language: `en`, `fr`, `de`, `es`, `it`, `pt`, `nl`, `ru`, `zh`, `ar` | system language, otherwise `en` |
| `--en`, `--fr`, `--de`, `--es`, `--it`, `--pt`, `--nl`, `--ru`, `--zh`, `--ar` | shortcuts for `--lang` | |
| `-h`, `--help` | prints the script help (in French) | |

One password source at a time (two options are refused before any change). With none, an interactive terminal offers "generate automatically (recommended)" or "type it" (no echo, with confirmation); without a terminal or with `--yes`, a password is generated and shown at the end. A supplied password is neither displayed nor written to the summary or `install-info.txt`, and an update never changes it.

**Stack option values** (checked before any change; **\*** = experimental):

| Option | Values |
|---|---|
| `--web` | `nginx`, `apache`, `nginx-apache`, `openlitespeed`\* (`:1.9`, `:1.8`, `:1.7`), `none` |
| `--php` / `--php-default` / `--php-ext` | comma-separated versions (`8.3,8.4`, from 5.6 to 8.5) / default version / `minimal`, `standard`, `full` |
| `--db` | `mariadb` (`:10.6`, `:10.11`, `:11.4`, `:11.8`), `mysql`\* (`:8.4`, `:9.7`), `percona`\* (`:8.0`, `:8.4`), `postgresql` (`:13` to `:18`), `none` |
| `--accel` | `opcache`, `jit`, `apcu`, `redis`, `memcached`, `fastcgi-cache`, `varnish`\*, `brotli`, `zstd`\*, `http3`\*, `ioncube` |
| `--ftp` | `builtin`, `pureftpd`\*, `proftpd`\*, `vsftpd`\*, `sftp`\*, `none` |
| `--mail` | `postfix`, `postfix-clamav`, `postfix-light`, `exim`\*, `relay`, `none` |
| `--dns` | `bind`, `powerdns`, `knot`, `external`, `none` |
| `--security` | `firewall`, `fail2ban`, `modsecurity`, `clamav`, `toutwaf` |
| `--runtime` / `--tools` | `nodejs`, `python`, `go`, `ruby`, `java`, `docker` / `certbot`, `git`, `composer`, `phpmyadmin`, `adminer`, `restic`, `goaccess` |
| `--install-mode` / `--roles` | `single-server`, `single-site`, `multi-site`, `multi-server` / `web`, `db`, `mail`, `dns` |

A "coming soon" component (Apache + mod_php, Caddy) is cleanly refused by `toutpanel stack`, with nothing installed.

Examples:

```bash
sudo bash install.sh --stack minimal --port 7443
sudo bash install.sh --profile lamp --php 8.3,8.4 --db mariadb:11.4 --firewall on
sudo bash install.sh --profile hosting --mail postfix-clamav --dns bind --firewall off --yes
sudo bash install.sh --dry-run --profile lamp          # dry run
sudo bash install.sh --mail --postgres
sudo bash install.sh --mail --username me --password-file /root/password.txt --entrance /my-access
sudo bash install.sh --profile performance --web openlitespeed --php 8.3 --accel opcache,redis --firewall off --yes   # OpenLiteSpeed: experimental
sudo bash install.sh --waf toutwaf                 # the vendor's WAF in front of the sites
sudo bash install.sh --stack minimal --node --master https://master.example.com:8888   # server driven by a master
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --yes --random-port
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --channel dev
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --de   # installer in German
```

#### Installer language

The installers are **multilingual**: banner, menu and questions, steps, warnings, errors, help, summary and `install-info.txt` are shown in one of the **10 languages** below, **English by default**. The chosen language also becomes the panel's **initial language** (installation and reinstallation); a line under the banner states the language used and where it came from.

| Language | `--lang` | Linux shortcut | Windows |
|---|---|---|---|
| English *(default)* | `en` | `--en` | `-Lang en` / `-En` |
| Français | `fr` | `--fr` | `-Lang fr` / `-Fr` |
| Deutsch | `de` | `--de` | `-Lang de` / `-De` |
| Español | `es` | `--es` | `-Lang es` / `-Es` |
| Italiano | `it` | `--it` | `-Lang it` / `-It` |
| Português | `pt` | `--pt` | `-Lang pt` / `-Pt` |
| Nederlands | `nl` | `--nl` | `-Lang nl` / `-Nl` |
| Русский | `ru` | `--ru` | `-Lang ru` / `-Ru` |
| 中文 | `zh` | `--zh` | `-Lang zh` / `-Zh` |
| العربية | `ar` | `--ar` | `-Lang ar` / `-Ar` |

Priority order, strongest first:

| # | Source | Linux | Windows |
|---|---|---|---|
| 1 | command-line option | `--lang xx` or a shortcut (`--fr`…) | `-Lang xx` or a shortcut (`-Fr`…) |
| 2 | environment variable | `TOUTPANEL_LANG=fr` | `$env:TOUTPANEL_LANG = "fr"` |
| 3 | value written in the script | `INSTALLER_LANG="fr"` at the top of `install.sh` | `$InstallerLang = "fr"` at the top of `install.ps1` |
| 4 | **detected** system language, if it is one of the 10 | `LC_ALL`, `LC_MESSAGES`, `LANG` | `Get-Culture` |
| 5 | English | | |

```bash
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo env TOUTPANEL_LANG=de bash
```

Recognised environment variables: `TOUTPANEL_LANG` (installer language), `TOUTPANEL_HOME` (directory), `TOUTPANEL_REPO` (Git repository), `TOUTPANEL_BRANCH` (branch), `TOUTPANEL_CHANNEL` (`stable` or `dev`), `TOUTPANEL_VERSION` (specific version), `TOUTPANEL_PASSWORD` (administrator password), `TOUTPANEL_FIREWALL` / `TOUTPANEL_FIREWALL_ENGINE`, and one variable per stack option (`TOUTPANEL_PROFILE`, `TOUTPANEL_WEB`, `TOUTPANEL_PHP`, `TOUTPANEL_DB`, `TOUTPANEL_ACCEL`, `TOUTPANEL_FTP`, `TOUTPANEL_MAIL_ENGINE`, `TOUTPANEL_DNS`…).

<details>
<summary><b>Packages installed per distribution</b></summary>

- **Debian / Ubuntu**: `nginx`, `php8.x-fpm` (+ cli, mysql, curl, mbstring, xml, zip, gd, intl, bcmath, opcache), `certbot`, `composer`, `mariadb-server`, `redis-server`, `fail2ban`, `python3-venv`, `git`, `unzip`; multiple PHP versions through packages.sury.org (Debian) or the ondrej PPA (Ubuntu).
- **AlmaLinux / Rocky / RHEL / Fedora**: `epel-release` (+ CRB), `remi-release`, `nginx`, `php83-php-fpm` (+ extensions), `certbot`, `mariadb-server`, `redis` or `valkey`, `fail2ban`, `policycoreutils-python-utils`, `dnf-plugins-core`; SELinux contexts declared (`httpd_sys_rw_content_t` on `/www/wwwroot`, `httpd_log_t`, `cert_t`, `httpd_config_t`, `mail_spool_t`) and booleans `httpd_can_network_connect`, `httpd_can_network_connect_db`, `httpd_can_sendmail`, `httpd_setrlimit` enabled.
- **Optional Python modules** (not installed by default): `pymongo` (MongoDB), `wsgidav` (WebDAV), `geoip2` (GeoIP), `python3-saml` (SAML) — `/var/toutpanel/venv/bin/pip install "pymongo>=4.6"` then `systemctl restart toutpanel`.

</details>

### Windows

In PowerShell **as administrator**:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
iwr -useb https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.ps1 | iex
```

The script checks the Windows version and rights, installs **Python 3.12** if no Python 3.9+ is present, creates `C:\toutpanel\venv` and installs the panel into it, creates the admin account and secret URL, adds firewall rules (panel port, 80, 443, 21), creates the **ToutPanel** scheduled task (automatic start as SYSTEM) and adds `C:\toutpanel\bin` to the PATH.

To also install the web stack (**Nginx** in `C:\nginx`, **PHP 8.3** supervised by the panel, **MariaDB** as a Windows service):

```powershell
iwr -useb https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.ps1 -OutFile install.ps1
.\install.ps1 -Stack
```

| Option | Description |
|---|---|
| `-Port 8888` | panel **HTTP** port |
| `-HttpsPort 8443` | panel **HTTPS** port |
| `-Version X.Y.Z` / `-ListVersions` | install a specific published version (`TOUTPANEL_VERSION` variable) / list the published versions |
| `-Home C:\toutpanel` | panel directory |
| `-Stack` | installs Nginx, PHP 8.3, MariaDB |
| `-Username`, `-Password`, `-Entrance /x` | chosen admin account and secret URL (`-Password` is visible in the process list: prefer `$env:TOUTPANEL_PASSWORD`, `-PasswordFile FILE` or `-PasswordStdin`) |
| `-PythonVersion`, `-NginxVersion`, `-MariaDBVersion`, `-PhpVersion` | downloaded versions |
| `-Source C:\path` / `-Branch main` | local folder (copy of this repository) / downloaded branch |
| `-Update` / `-Reinstall` / `-Uninstall` | update / reinstall everything / uninstall |
| `-Yes` | no questions (automation) |
| `-Lang xx` / `-En`, `-Fr`, `-De`, `-Es`, `-It`, `-Pt`, `-Nl`, `-Ru`, `-Zh`, `-Ar` | installer language and initial panel language (default: system language when supported, otherwise English; see [Installer language](#installer-language)); with `iwr … \| iex`: set `$env:TOUTPANEL_LANG = "fr"` first |
| `-Help` | script help |

### Ports to open

| Port | Use | Opened by the installer |
|---|---|---|
| **8888** (configurable) | panel interface over **HTTP** | yes |
| **8443** (configurable) | panel interface over **HTTPS** (self-signed certificate at first) | yes (re-run the installer or open it by hand on an existing installation) |
| **80 / 443** | websites | yes |
| 21 + 60000-60100 | FTP (built-in, or the chosen engine: its passive range) | 21 only; open the passive range if you enable FTP |
| 25, 465, 587, 143, 993, 110, 995, 4190 | mail (SMTP, IMAP, POP3, ManageSieve) | with `--mail` (4190: open it for remote Sieve) |
| 53 (UDP and TCP) | DNS (BIND, PowerDNS or Knot) if you host your zones | no: Security › Firewall |
| 9443 / 7000 | ToutWAF and SafeLine consoles (9443), BunkerWeb (7000) | with `--waf` |
| 3306 / 5432 | remote database access (optional) | no: only if you enable it |

Do not forget your **hosting provider's firewall** (security group): if it blocks the panel ports (8888 and 8443), the browser shows nothing. With `--firewall off` (or the "Upstream" mode of Security › Firewall), ToutPanel touches no system rule and **lists the ports to open** at your provider (`toutpanel firewall ports`, copy or CSV download in the interface); with `--firewall on`, it opens them itself and a **60-second guard** reverts any unconfirmed change that would lock you out.

## First start

At the end of the installation, the script prints a summary (in French):

```
╔══════════════════════════════════════════════════════════════════╗
║  ToutPanel est installé !                                        ║
╚══════════════════════════════════════════════════════════════════╝

  URL du panel (HTTP)       : http://203.0.113.10:8888/tp_dchwp7kmkf
  URL du panel (HTTPS)      : https://203.0.113.10:8443/tp_dchwp7kmkf   certificat auto-signé : avertissement du navigateur normal
  Utilisateur               : admin_gbhjkv
  Mot de passe              : D9nYzTSKHbX8FTqC
  MariaDB root              : k3Jd82nLqP0sYt7wVb1c
  Assistant de configuration : https://203.0.113.10:8443/tp_dchwp7kmkf#/setup?token=npSj7xpVzJOI8weJl8R00AdQ18MHYn8YIJCbOYi43B8
  Ce lien (24 h, une seule utilisation) permet de changer l'adresse du panel, l'utilisateur et le mot de passe générés ci-dessus.
  Nouveau lien : toutpanel setup-link
  PHP                       : 8.3 (Nginx + PHP-FPM prêts)

  Ces informations sont enregistrées dans : /var/toutpanel/data/install-info.txt
  L'URL contient l'entrée sécurisée : sans elle, le panel répond 404.
```

1. **Write down the full URLs** (*URL du panel*, HTTP and HTTPS): they contain the **secret path** (`/tp_…`). Without it, the panel answers `404 Not Found`, which makes it invisible to scans. `toutpanel info` prints them again. The HTTPS certificate is **self-signed** at first: the browser warning is normal; the setup wizard link uses HTTPS so its token never travels in clear text.
2. **Open the setup wizard link** (*Assistant de configuration*, `#/setup?token=…`, valid 24 h, single use): in **nine steps** and without logging in, replace the generated values with your own (username, password, port, secret path, hostname, language, mode, theme, main colour and density), then **choose your server's profile and compose its stack** (profile, composition with architecture diagram, summary and resumable installation) and **who manages the firewall** (ToutPanel, upstream or later). Link expired? `toutpanel setup-link` creates a new one. The wizard remains available once logged in (dashboard › Quick shortcuts).
3. **Secure the account**: two-factor authentication (TOTP) and, if possible, a WebAuthn security key; allowed IPs if you have a fixed IP; a trusted HTTPS certificate (Settings › Access & interface, Let's Encrypt if a domain points to the server) and, if you wish, HTTP to HTTPS redirection.
4. **Create a first site**: Websites › New site (or the **Wizard** button for site + database + certificate + mailboxes), point the DNS to the server, then padlock › Let's Encrypt and "Force HTTPS".
5. **Enable protections**: WAF › Apply (or WAF › Engine › Install ToutWAF in the Professional edition), firewall rules (Security › Firewall), a scheduled daily backup, alerts (Settings › Alerts).
6. **Evolve the stack** at any time: Settings › Software stack (real state, adding a component, a PHP version, an engine), the Accelerators page, the Engine tabs of the FTP, DNS and Mail server pages.

## Updating

Every method keeps accounts, settings, sites, databases and software.

- **From the panel**: **Updates › Panel** shows the installed version, the followed channel, the available versions and the release notes. **Update** first backs up `settings.json`, the panel database and the current version (`<home>/data/updates/<date>/`), installs the new version's wheel, migrates the database and restarts; the panel then checks its health and **automatically rolls back** on failure. **Revert to the previous version** stays available at any time.
- **From the command line**:

  ```bash
  toutpanel update --check              # installed version, available version, release notes
  toutpanel update                      # install the version of the followed channel
  toutpanel update --channel dev        # follow the development branch
  toutpanel update --rollback           # revert to the previous version (--restore-data: data too)
  ```

- **With the installer**: run again on an equipped server, `install.sh` switches to update mode (backup of `data/` into `<home>/backup/panel-update-<date>/`, new wheel, `toutpanel migrate`, restart). The stack is not reinstalled unless you add `--stack`, `--mail` or `--waf`. On Windows: `.\install.ps1 -Update`.

## Uninstalling

```bash
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash -s -- --uninstall
```

Removes the service, `/var/toutpanel` (or the detected installation, e.g. `/www/toutpanel`: panel, Python environment, logs, certificates), `/usr/local/bin/toutpanel` and the Nginx / Apache configurations generated by the panel. Panel data is first archived to `/root/toutpanel-backup-<date>.tar.gz`. **Sites (`/www/wwwroot`), databases and stack software stay in place.** Add `--yes` to skip confirmation.

On Windows: `.\install.ps1 -Uninstall` (data archived to `C:\toutpanel-backup-<date>.zip`, sites moved to `C:\toutpanel-wwwroot-<date>`, Nginx, PHP and MariaDB kept).

## Manual installation from a wheel

For special environments, without the script. Pick the wheel matching your interpreter (`cp311` for Python 3.11, etc.):

```bash
git clone --depth 1 https://github.com/qu3ntin01/toutpanel.git /var/toutpanel/src
python3 -m venv /var/toutpanel/venv
. /var/toutpanel/venv/bin/activate          # Windows: venv\Scripts\activate
TAG=$(python -c 'import sys;print(f"cp{sys.version_info[0]}{sys.version_info[1]}")')
(cd /var/toutpanel/src/dist && sha256sum -c --ignore-missing SHA256SUMS)
pip install /var/toutpanel/src/dist/toutpanel-*-$TAG-none-any.whl
# e.g. for Python 3.12: pip install dist/toutpanel-0.4.0b2-cp312-none-any.whl
export TOUTPANEL_HOME=/var/toutpanel         # Windows: $env:TOUTPANEL_HOME="C:\toutpanel"
toutpanel setup --username admin --password 'MyPassword' --entrance /my-access
toutpanel run
```

Keeping the clone in `<home>/src` then enables `toutpanel update` (channels and rollback). `toutpanel service install` creates the systemd service (or the Windows scheduled task).

## Troubleshooting

| Symptom | Solution |
|---|---|
| `404 Not Found` when opening the panel | the URL lacks the secret path: `toutpanel info` prints the full URL; `toutpanel entrance /new-path` changes it |
| the browser shows nothing on the panel port | hosting provider firewall closed, or port changed: open the port, check it with `toutpanel info`; `toutpanel port N` to change it |
| lost password or 2FA unavailable | `toutpanel passwd` (new password generated) or `toutpanel passwd 'New' --disable-2fa` |
| the panel does not start | `systemctl status toutpanel`, `journalctl -u toutpanel -n 50` and `<home>/logs/panel.log`; `toutpanel check` for a machine diagnosis |
| `Le panel ne répond pas sur le port … après 30 s.` (panel not answering after 30 s) | slow or failed start: same logs, then `systemctl restart toutpanel` |
| `[ToutPanel] Échec à la ligne N (code C) : …` (failure at line N) | an installer command failed (repository, package, service): fix the cause and run again with `--update` |
| `Python 3.9+ requis.` or no wheel for this Python | install `python3.11` or `python3.12` (distribution package), then run again |
| site or PHP denied on Alma / Rocky / RHEL / Fedora | SELinux: `toutpanel selinux` declares the contexts again (after changing directories, in particular) |
| Windows: "Lancez PowerShell en tant qu'administrateur." | right click › Run as administrator; `Set-ExecutionPolicy Bypass -Scope Process -Force` before the script |

### Useful commands

```
toutpanel info                      full URL, username, initial password
toutpanel check                     diagnosis: OS, Python, rights, systemd, SELinux, firewall, web server, PHP, MariaDB, port
toutpanel setup-link                new setup wizard link (24 h, single use)
toutpanel passwd [PASS] [--disable-2fa]
toutpanel username NAME             rename the administrator
toutpanel port N                    change the port (restart required)
toutpanel entrance [/path]          set or disable the secret path
toutpanel ssl on|off                panel HTTPS (self-signed certificate)
toutpanel start|stop|restart|status
toutpanel service install|uninstall
toutpanel selinux | apparmor        SELinux contexts / AppArmor profiles
toutpanel php install|remove VERSION [--extensions a,b]
toutpanel waf status|install|remove|sync [toutwaf|bunkerweb|safeline]
toutpanel waf update|links|doctor toutwaf   ToutWAF update, console links, diagnostics
toutpanel waf connect|disconnect toutwaf    link / unlink a remote ToutWAF (token via TOUTPANEL_WAF_TOKEN or standard input)
toutpanel stack profiles|plan|apply|status  stack composer (--profile, --web, --php, --db…; plan and --dry-run change nothing)
toutpanel firewall status|mode|enable|ports firewall: panel / upstream mode, ports to open at your provider
toutpanel compat [--json]           supported distributions and this server's level
toutpanel accel …                   accelerators (Varnish, Memcached, JIT, Zstandard, HTTP/3)
toutpanel ols install|switch|status OpenLiteSpeed (experimental)
toutpanel dns engine [NAME] | mail engine [NAME]   DNS / mail engine (with --dry-run and --rollback)
toutpanel update [--check] [--channel stable|dev|custom] [--rollback]
toutpanel node enroll [--master URL] | status
toutpanel licence status|activate KEY|deactivate|refresh
toutpanel site|account|db|mail|dns|backup|cron|ftp|task …   business commands (--json)
```

Full reference (in French): [Command line](https://toutpanel.com/docs/reference/cli/) · [REST API](https://toutpanel.com/docs/reference/api/) · [Error codes](https://toutpanel.com/docs/reference/codes-erreur/).

## Channels

| Channel | Content | Installation | Afterwards |
|---|---|---|---|
| **stable** (default) | latest published version, `vX.Y.Z` tag on the [`main`](https://github.com/qu3ntin01/toutpanel/tree/main) branch | `install.sh` | Updates › Panel or `toutpanel update` |
| **dev** | [`dev`](https://github.com/qu3ntin01/toutpanel/tree/dev) branch: unreleased changes, not guaranteed | `install.sh --channel dev` | `toutpanel update --channel stable` to go back |
| **custom** | repository, branch or tag of your choice | `TOUTPANEL_REPO=… install.sh --branch …` | `toutpanel update --channel custom --repo URL --branch NAME` |

## Known limitations

To be transparent about what is less covered:

- **Windows** is less proven than Linux: no mail server, no `chmod` in the file manager, PHP run as `php-cgi` by the panel, no per-system-user isolation or cgroup limits, basic IIS support (prefer Nginx), simplified terminal without the `pywinpty` module.
- **Beta**: 0.4.0b2 is a pre-release. The new features (stack composer, engines, upstream firewall, OpenLiteSpeed…) were tested on Ubuntu 24.04; some families (Red Hat, Debian 12 / 13) and the `aarch64` architecture were not exercised for each of them. Try it on a test server.
- **Experimental features**: OpenLiteSpeed (LSPHP, LSCache), Exim, Pure-FTPd, ProFTPD, vsftpd and SFTP only, Varnish (HTTP only; HTTPS stays served by the web server), Zstandard and HTTP/3 (depending on the module or build of your Nginx, otherwise an explained refusal), MySQL 8.4 / 9.x (Oracle repository) and Percona Server. They work and their limits are displayed in the interface, but they are less proven than the rest. Apache + mod_php and Caddy are **coming soon**: visible, never simulated.
- **OpenLiteSpeed**: the panel's built-in WAF, ModSecurity, country filtering and the per-site connection limit do not apply (reported by the interface); put an external WAF in front. Distributions: Debian / Ubuntu and Red Hat family 8 to 10.
- **Distributions**: the "full" level is the level **expected** by the panel. The full installation has been validated end to end on AlmaLinux 9 and 10, and the test suite on Fedora (Python 3.14); the other supported distributions are handled by the installer but less proven. Arch, Alpine, openSUSE and Amazon Linux run at the **reduced** level (system PHP, a single version, no third-party repositories), **untested**.
- **ARM64**: the compiled panel is portable and its dependencies exist for ARM64 (full level), but no full installation has been validated on this architecture yet. 32-bit architectures are at the reduced level.
- **Built-in WAF**: it relies on native Nginx / Apache directives and **does not inspect POST request bodies**; for full inspection, add ToutWAF (recommended), ModSecurity + OWASP CRS, BunkerWeb or SafeLine (Professional edition).
- **Multi-server**: suspending an account on the master is not yet propagated to its mirror accounts on the nodes; the external WAF and statistics are configured on each node.
- **Optional modules**: MongoDB, WebDAV, GeoIP and SAML need an additional Python module (see [Full installation](#full-installation)); BorgBackup can be installed but is not driven by the panel.
- **Language**: the panel interface and the installers are translated into 10 languages, but the online documentation and the release notes are in French.
- **Firewall**: an upstream firewall is not visible to the panel (Fail2ban bans stay local); the guard protects against loss of network access but does not replace your hosting provider's rescue console.
- **Mail**: a reliable mail server requires a fixed public IP, correct reverse DNS and ports 25 / 465 / 587 not blocked by the hosting provider.

## Releases and downloads

**Version 0.4.0b2** (2026-10-04, **pre-release**) — simultaneous HTTP and HTTPS, specific-version installation, `/var/toutpanel` by default, **firewall** managed by the panel or upstream, **stack composer** and 9-step setup wizard, **FTP, DNS and mail** engines, **OpenLiteSpeed** and **accelerators** (partly experimental), **remote ToutWAF**, extended distribution compatibility, multilingual installer with stack options. Previous stable version: 0.3.1 (CMS, ToutWAF, Horizon theme). Full notes in [CHANGELOG.md](CHANGELOG.md) (in French), also shown by the panel before an update.

| File | Content |
|---|---|
| `install.sh`, `install.ps1` | Linux and Windows installers |
| `dist/toutpanel-0.4.0b2-cp3XY-none-any.whl` | the panel, **one wheel per CPython version**: `cp39`, `cp310`, `cp311`, `cp312`, `cp313`, `cp314` (3 to 4.5 MB each, bytecode only, portable across Linux / Windows) |
| `dist/manifest.json` | version, build date, supported Python versions, size and SHA-256 of each wheel |
| `dist/SHA256SUMS` | wheel checksums (verified automatically by the installer and by `toutpanel update`) |
| `version.json` | published version and date, minimum Python, available wheels: read by the Updates page |
| `CHANGELOG.md`, `LICENSE` | release notes, licence of use |
| `screenshots/` | screenshots used in this README |

Check the wheels by hand:

```bash
cd dist && sha256sum -c SHA256SUMS
```

Stable releases are tagged `vX.Y.Z` on `main`; pre-releases have no tag and are published on `dev` (find them with `install.sh --list-versions`); each release is a single commit.

## Licence

ToutPanel is **proprietary software**: see [LICENSE](LICENSE) (French, then English; the French version prevails). The **Personal edition** is granted free of charge for personal, non-commercial use, up to 5 sites per installation, without a key. The **Professional** and **Enterprise** editions require a licence key and are subject to the terms published on [toutpanel.com](https://toutpanel.com/tarifs). Third-party components used by the panel (FastAPI, Starlette, SQLAlchemy, Uvicorn, httpx, Jinja2…) remain under their own licences, listed in `LICENSE`.

---

<div align="center">

**[toutpanel.com](https://toutpanel.com)** · **[Documentation](https://toutpanel.com/docs/)** · **[Pricing](https://toutpanel.com/tarifs)** · **[Version française](README.md)**

</div>
