# Centralized Package Mirror Stack

Cette stack permet de déployer de manière centralisée et non redondante 8 miroirs de paquets distincts (Debian 11, Debian 11 snapshot du 20260824T000000Z, Debian 12, 13 et Ubuntu 20.04, 22.04, 24.04, 26.04).

## Architecture
Le code source est entièrement mis en commun dans le répertoire principal. Les particularités de chaque miroir sont stockées dans les 8 fichiers de `configs/`. `docker-compose` orchestre de manière indépendante les conteneurs de chaque distribution grâce à l'option `--env-file`.

Chaque fichier `.env` commence par :
```bash
MIRROR_NAME=mirror-debian_12
MIRROR_DATA="/data/debmirror/${MIRROR_NAME}"
```
- `MIRROR_NAME` (obligatoire) sert de nom de projet Docker Compose et de préfixe aux noms des conteneurs (`<MIRROR_NAME>-nginx`, `<MIRROR_NAME>-updater`).
- `MIRROR_DATA` est le répertoire de l'hôte où sont stockées les données du miroir. Il est monté en bind-mount, en écriture dans le conteneur de mise à jour et en lecture seule dans nginx. S'il n'est pas défini, `/data/debmirror/${MIRROR_NAME}` est utilisé. Docker crée le répertoire s'il n'existe pas, les fichiers appartiennent à root.

L'image de mise à jour (`Dockerfile`) est basée sur `debian:trixie-slim`. Elle installe `debmirror`, `gnupg` et `gpgv` (utilisé par debmirror pour vérifier les signatures des fichiers `Release`), ainsi que les trousseaux `debian-archive-keyring` et `ubuntu-keyring`. Le paquet `ubuntu-keyring` n'est pas disponible dans bookworm.

## 1. Installation
Placez le dossier entier dans `/opt/debmirror` :
- `/opt/debmirror` contiendra le docker-compose, le script, etc.
- `/opt/debmirror/configs/` contiendra les 8 fichiers `.env`.

Rendez les scripts exécutables :
```bash
cd /opt/debmirror
chmod +x update-mirror.sh progress-mirror.sh entrypoint.sh
```

## 2. Déployer en tant que service (Systemd)
Copiez le template vers systemd :
```bash
cp /opt/debmirror/debmirror@.service /etc/systemd/system/debmirror@.service
systemctl daemon-reload
```

Vous pouvez maintenant allumer indépendamment vos 8 miroirs :
```bash
systemctl enable --now debmirror@debian_11
systemctl enable --now debmirror@debian_11_snapshot_20260824
systemctl enable --now debmirror@debian_12
systemctl enable --now debmirror@debian_13
systemctl enable --now debmirror@ubuntu_20.04
systemctl enable --now debmirror@ubuntu_22.04
systemctl enable --now debmirror@ubuntu_24.04
systemctl enable --now debmirror@ubuntu_26.04
```

## 3. Mise à jour des miroirs
La mise à jour se fait avec le script commun en passant le nom de la configuration en paramètre :
```bash
cd /opt/debmirror
./update-mirror.sh debian_11_snapshot_20260824
./update-mirror.sh debian_13
./update-mirror.sh ubuntu_24.04
```
Le script se termine avec un code non nul si la mise à jour a échoué.

### Estimer le volume à télécharger (dry-run)
```bash
./update-mirror.sh debian_12 --dry-run
```
Seuls les fichiers d'index sont téléchargés (dans le répertoire `.temp` de chaque racine), aucun paquet n'est récupéré et le nettoyage est seulement simulé. Pour chaque racine, debmirror affiche :
```
Files to download: 87143 MiB
```
Ce chiffre correspond à la différence entre les index amont et ce qui est déjà présent dans `MIRROR_DATA`. Sur un miroir vide, c'est la taille de la synchronisation initiale. Sur un miroir existant, c'est la taille de la resynchronisation. Les paquets communs à plusieurs suites ne sont comptés qu'une fois. Les paquets obsolètes ne sont supprimés qu'en fin de synchronisation, ce qui provoque un pic d'occupation disque temporaire.

### Suivre l'avancement d'une synchronisation
Depuis un autre terminal, pendant qu'un `update-mirror.sh` est en cours :
```bash
./progress-mirror.sh debian_12
```
Le script affiche la racine en cours, `Files to download`, le pourcentage (en octets, il repart de 0 pour chaque racine) et le récapitulatif final. Ctrl+C arrête le suivi, sans arrêter la synchronisation.

Occupation disque d'un miroir :
```bash
du -sh /data/debmirror/mirror-debian_12/*
```

## 4. Configuration des racines (`MIRROR_ROOT`)
Un même miroir peut synchroniser et servir plusieurs racines de l'hôte amont. `MIRROR_ROOT` contient un ou plusieurs groupes `racine:releases`, séparés par des espaces (valeur entre guillemets) :
```bash
MIRROR_ROOT="/debian:bookworm,bookworm-updates,bookworm-backports /debian-security:bookworm-security"
```
`MIRROR_HOST`, `ARCHITECTURES`, `SECTIONS` et `KEYRING` sont communs à toutes les racines d'un même fichier.

Chaque racine est stockée et servie dans son propre sous-répertoire. Si une racine échoue, les suivantes sont tout de même synchronisées, puis la mise à jour se termine en erreur avec un récapitulatif.

Exemple de `sources.list` client pour Debian 12 :
```
deb http://<hote>:32012/debian bookworm main contrib non-free non-free-firmware
deb http://<hote>:32012/debian bookworm-updates main contrib non-free non-free-firmware
deb http://<hote>:32012/debian bookworm-backports main contrib non-free non-free-firmware
deb http://<hote>:32012/debian-security bookworm-security main contrib non-free non-free-firmware
```
Pour Ubuntu : `deb http://<hote>:42404/ubuntu noble main restricted universe multiverse` (idem pour `noble-updates`, `noble-security` et `noble-backports`).

Pour le snapshot Debian 11 (`debian_11_snapshot_20260824`, hôte `snapshot.debian.org`), le contenu est servi sous le chemin amont complet :
```
deb http://<hote>:34011/archive/debian/20260824T000000Z bullseye main contrib non-free
deb http://<hote>:34011/archive/debian/20260824T000000Z bullseye-updates main contrib non-free
deb http://<hote>:34011/archive/debian-security/20260824T000000Z bullseye-security main contrib non-free
```

## Remarques :
N/A
