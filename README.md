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
systemctl enable --now debmirror@debian_11_snapshot_20260824T0000000
systemctl enable --now debmirror@debian_12
systemctl enable --now debmirror@debian_13
systemctl enable --now debmirror@ubuntu_20.04
systemctl enable --now debmirror@ubuntu_22.04
systemctl enable --now debmirror@ubuntu_24.04
systemctl enable --now debmirror@ubuntu_26.04
```

### Mise à jour périodique (timer)
Le template `debmirror-update@.timer` déclenche `debmirror-update@.service`, qui lance `update-mirror.sh` avec `configs/<instance>.env`. Le déclenchement a lieu toutes les 6 heures (00:00, 06:00, 12:00, 18:00), décalé aléatoirement de 0 à 4 h pour étaler les miroirs. Un déclenchement manqué (machine éteinte) est rattrapé au démarrage suivant. En cas d'échec, il n'y a pas de relance immédiate : le déclenchement suivant fait office de nouvelle tentative. Si une mise à jour est encore en cours, elle n'est pas relancée.

Installation :
```bash
cp /opt/debmirror/debmirror-update@.service /opt/debmirror/debmirror-update@.timer /etc/systemd/system/
systemctl daemon-reload
```

Activer ou désactiver la mise à jour périodique d'un miroir :
```bash
systemctl enable --now debmirror-update@debian_12.timer
systemctl disable --now debmirror-update@debian_12.timer
```

Suivi :
```bash
systemctl list-timers 'debmirror-update@*'
systemctl status debmirror-update@debian_12.service
journalctl -u debmirror-update@debian_12.service -f
```
Pour lancer une mise à jour tout de suite via systemd : `systemctl start --no-block debmirror-update@debian_12.service`.

## 3. Mise à jour des miroirs
La mise à jour se fait avec le script commun en passant en paramètre le chemin du fichier de configuration du miroir. Un chemin relatif est résolu depuis le répertoire courant :
```bash
cd /opt/debmirror
./update-mirror.sh configs/debian_11_snapshot_20260824T0000000.env
./update-mirror.sh configs/debian_13.env
./update-mirror.sh /opt/debmirror/configs/ubuntu_24.04.env
```
Le script se termine avec un code non nul si la mise à jour a échoué.

### Estimer le volume à télécharger (dry-run)
```bash
./update-mirror.sh configs/debian_12.env --dry-run
```
Seuls les fichiers d'index sont téléchargés (dans le répertoire `.temp` de chaque racine), aucun paquet n'est récupéré et le nettoyage est seulement simulé. Pour chaque racine, debmirror affiche :
```
Files to download: 87143 MiB
```
Ce chiffre correspond à la différence entre les index amont et ce qui est déjà présent dans `MIRROR_DATA`. Sur un miroir vide, c'est la taille de la synchronisation initiale. Sur un miroir existant, c'est la taille de la resynchronisation. Les paquets communs à plusieurs suites ne sont comptés qu'une fois. Les paquets obsolètes ne sont supprimés qu'en fin de synchronisation, ce qui provoque un pic d'occupation disque temporaire.

### Suivre l'avancement d'une synchronisation
Depuis un autre terminal, pendant qu'un `update-mirror.sh` est en cours :
```bash
./progress-mirror.sh configs/debian_12.env
```
Le script affiche la racine en cours, `Files to download`, le pourcentage (en octets, il repart de 0 pour chaque racine) et le récapitulatif final. Ctrl+C arrête le suivi, sans arrêter la synchronisation.

Occupation disque d'un miroir :
```bash
du -sh /data/debmirror/mirror-debian_12/*
```

## Utilisation via make
Le `Makefile` regroupe les opérations courantes. Les cibles propres à un miroir prennent `CONFIG=<chemin du fichier .env>`, résolu depuis le répertoire courant. `make` (ou `make help`) liste les cibles.

| Cible | Action |
|---|---|
| `list` | Liste les configurations (nom, port, hôte) |
| `check` | Vérifie toutes les configurations : variables obligatoires, `PORT` / `MIRROR_NAME` en doublon, `docker compose config` |
| `start-web` / `stop-web` | Démarre / arrête le nginx du miroir via docker compose (`stop-web` n'arrête pas une mise à jour en cours) |
| `build` | Reconstruit l'image de mise à jour (nécessaire après une modification d'`entrypoint.sh`) |
| `start-update` / `stop-update` | Lance une mise à jour en arrière-plan / arrête la mise à jour en cours |
| `dry-run` | Estimation du volume à télécharger (premier plan) |
| `show-progress` | Suit l'avancement de la mise à jour en cours |
| `logs` | Logs de la mise à jour en cours, sinon journal de `debmirror-update@<nom>.service` |
| `status` | État du nginx, de la mise à jour et du timer |
| `du` | Occupation disque du miroir |
| `start-timer` / `stop-timer` | Active / désactive `debmirror-update@<nom>.timer` (systemd) |
| `install` / `uninstall` | Installe / supprime les unités systemd dans `/etc/systemd/system` (désactiver d'abord les timers) |

Exemples :
```bash
make start-web CONFIG=configs/ubuntu_20.04.env
make start-update CONFIG=configs/ubuntu_20.04.env
make show-progress CONFIG=configs/ubuntu_20.04.env
sudo make install
sudo make start-timer CONFIG=configs/ubuntu_20.04.env
```
Le Makefile n'utilise pas `sudo` : lancez `sudo make …` pour les cibles systemd. Les unités systemd lisent `/opt/debmirror/configs/<nom>.env`, où `<nom>` est le nom du fichier sans `.env`. `start-timer` et `stop-timer` affichent un avertissement si `CONFIG` désigne un autre fichier.

`make start-web` et `debmirror@.service` gèrent le même conteneur nginx : n'utilisez pas les deux pour un même miroir.

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

Pour le snapshot Debian 11 (`debian_11_snapshot_20260824T0000000`, hôte `snapshot.debian.org`), le contenu est servi sous le chemin amont complet :
```
deb http://<hote>:34011/archive/debian/20260824T000000Z bullseye main contrib non-free
deb http://<hote>:34011/archive/debian/20260824T000000Z bullseye-updates main contrib non-free
deb http://<hote>:34011/archive/debian-security/20260824T000000Z bullseye-security main contrib non-free
```

## Remarques :
N/A
