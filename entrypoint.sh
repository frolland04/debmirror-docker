#!/bin/bash
#
# MIRROR_ROOT contient un ou plusieurs groupes "racine:releases" séparés par des espaces.
# Exemple :
#   MIRROR_ROOT="/debian:bookworm,bookworm-updates /debian-security:bookworm-security"
# Chaque racine est synchronisée dans son propre sous-répertoire de /data/mirror
# (ex. /data/mirror/debian, /data/mirror/debian-security).

MIRROR_HOST=${MIRROR_HOST:-deb.debian.org}
MIRROR_ROOT=${MIRROR_ROOT:-/debian:trixie}
MIRROR_METHOD=${MIRROR_METHOD:-http}
ARCHITECTURES=${ARCHITECTURES:-amd64}
SECTIONS=${SECTIONS:-main}
DEST_BASE="/data/mirror"
DRY_RUN=${DRY_RUN:-0}

EXTRA_OPTS=()
if [ "${DRY_RUN}" = "1" ]; then
    # Ne télécharge que les fichiers d'index (dans .temp), aucun paquet ;
    # le nettoyage est seulement simulé. Affiche "Files to download".
    EXTRA_OPTS+=(--dry-run)
fi

if [ -n "${KEYRING}" ]; then
    KEYRING_PATH="${KEYRING}"
elif [[ "${MIRROR_HOST}" == *"ubuntu"* ]]; then
    KEYRING_PATH="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
else
    KEYRING_PATH="/usr/share/keyrings/debian-archive-keyring.gpg"
fi

read -ra ENTRIES <<< "${MIRROR_ROOT}"

if [ ${#ENTRIES[@]} -eq 0 ]; then
    echo "Erreur : MIRROR_ROOT est vide."
    exit 1
fi

SUMMARY=()
FAILED=0

for entry in "${ENTRIES[@]}"; do
    root="${entry%%:*}"
    dists="${entry#*:}"

    if [[ "${entry}" != *:* || "${root}" != /* || "${root}" == "/" || -z "${dists}" ]]; then
        echo "Erreur : entrée MIRROR_ROOT invalide '${entry}' (format attendu : /racine:release1,release2)."
        SUMMARY+=("ÉCHEC  ${entry} (format invalide)")
        FAILED=1
        continue
    fi

    dest="${DEST_BASE}${root}"
    mkdir -p "${dest}"

    echo "=========================================="
    echo "Démarrage de debmirror..."
    echo "Hôte         : ${MIRROR_HOST}"
    echo "Racine       : ${root}"
    echo "Releases     : ${dists}"
    echo "Architecture : ${ARCHITECTURES}"
    echo "Sections     : ${SECTIONS}"
    echo "Keyring      : ${KEYRING_PATH}"
    echo "Destination  : ${dest}"
    [ "${DRY_RUN}" = "1" ] && echo "Mode         : dry-run (estimation, aucun paquet téléchargé)"
    echo "=========================================="

    if debmirror \
        --progress \
        --verbose \
        --nosource \
        --host="${MIRROR_HOST}" \
        --root="${root}" \
        --method="${MIRROR_METHOD}" \
        --dist="${dists}" \
        --arch="${ARCHITECTURES}" \
        --section="${SECTIONS}" \
        --keyring="${KEYRING_PATH}" \
        --rsync-extra=none \
        --i18n \
        "${EXTRA_OPTS[@]}" \
        "${dest}"; then
        SUMMARY+=("OK     ${root} (${dists})")
    else
        SUMMARY+=("ÉCHEC  ${root} (${dists})")
        FAILED=1
    fi
done

echo ""
echo "============================================"
echo "Récapitulatif :"
for line in "${SUMMARY[@]}"; do
    echo "  ${line}"
done
echo "============================================"

if [ "${FAILED}" -ne 0 ]; then
    echo "Mise à jour du miroir terminée avec des erreurs."
    exit 1
fi

echo "Mise à jour du miroir terminée avec succès !"
echo "============================================"
echo ""
