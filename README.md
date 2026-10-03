# ToutPanel

**Panel d'hébergement web pour Linux et Windows.** Sites Nginx / Apache / IIS, PHP multi-versions, bases de données
MariaDB / PostgreSQL / MongoDB, FTP, mail et webmail, DNS, SSL Let's Encrypt, WAF, sauvegardes, Docker, comptes
multi-tenant, facturation, multi-serveurs… depuis une interface web claire, traduite en 10 langues.

Site et documentation : **[toutpanel.com](https://toutpanel.com)** · **[toutpanel.com/docs](https://toutpanel.com/docs/)**

## Prérequis

- **Linux** : Debian 11+, Ubuntu 20.04+, Fedora 40+, AlmaLinux / Rocky Linux / RHEL 9 et 10 (Arch, Alpine, openSUSE :
  panel fonctionnel, pile logicielle réduite), accès root, Python 3.9 à 3.14.
- **Windows** : Windows 10 / 11, Windows Server 2016 à 2025, PowerShell 5.1 ou plus (Python installé par le script si
  nécessaire).
- Accès sortant HTTPS (ce dépôt, PyPI, dépôts de la distribution) ; 1 Go de mémoire au minimum, 2 Go recommandés.

## Installation

Linux (root) :

```bash
curl -sSL https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.sh | sudo bash
```

Windows (PowerShell en administrateur) :

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
iwr -useb https://raw.githubusercontent.com/qu3ntin01/toutpanel/main/install.ps1 | iex
```

Le script installe la pile (Nginx, PHP, MariaDB, Certbot…), le panel et son service, crée un compte administrateur et
une URL sécurisée aléatoires, puis affiche l'adresse d'accès. Options (`--stack`, `--mail`, `--postgres`, `--port`,
`--uninstall`…) : `bash install.sh --help` et [Installation](https://toutpanel.com/docs/installation/).

Relancé sur un serveur où le panel est déjà installé, le script passe en mode mise à jour (données sauvegardées,
comptes et réglages conservés).

## Contenu de ce dépôt et canaux

Ce dépôt ne contient que ce qui sert à installer le panel :

| Fichier | Rôle |
|---|---|
| `install.sh`, `install.ps1` | installateurs Linux et Windows |
| `dist/toutpanel-<version>-cp3XY-none-any.whl` | le panel, une roue Python par version de CPython (3.9 à 3.14), code compilé uniquement |
| `dist/manifest.json`, `dist/SHA256SUMS`, `version.json` | version publiée, versions de Python prises en charge, sommes de contrôle |
| `CHANGELOG.md` | notes de version (affichées par le panel avant une mise à jour) |
| `LICENSE` | licence d'utilisation |

Canaux de mise à jour (page **Mises à jour → Panel** ou `toutpanel update`) :

- **stable** : dernière version publiée, étiquette `vX.Y.Z` sur la branche `main` ;
- **développeur** : branche `dev` (`install.sh --channel dev`), versions de développement non garanties ;
- **personnalisé** : dépôt, branche ou étiquette de votre choix.

L'installateur clone ce dépôt dans `<home>/src` et installe la roue correspondant au Python du système ; le panel se
met ensuite à jour lui-même (sauvegarde préalable, migration, vérification de santé, retour arrière automatique).

## Licence

ToutPanel est un logiciel propriétaire : voir [LICENSE](LICENSE). L'**édition Personnelle** est gratuite pour un usage
personnel (jusqu'à 5 sites) ; les éditions **Professionnelle** et **Entreprise** (sites illimités, revendeurs,
facturation, multi-serveurs, haute disponibilité…) sont soumises à une clé de licence : [Éditions](https://toutpanel.com/docs/guide/editions/).
Les composants tiers restent sous leurs propres licences (liste dans `LICENSE`).
