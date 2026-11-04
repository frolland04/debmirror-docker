#!/bin/bash
# Suit l'avancement de la synchronisation en cours d'un miroir.
# Affiche la racine en cours, le volume à télécharger, le pourcentage et le récapitulatif final.
cd "$(dirname "${0}")" || exit

if [ -z "${1}" ]; then
    echo "Usage : ${0} <nom_du_miroir>"
    echo "Exemple : ${0} debian_11"
    exit 1
fi

CONFIG_FILE="configs/${1}.env"
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Erreur : Le fichier de configuration ${CONFIG_FILE} n'existe pas."
    exit 1
fi

PROJECT="${MIRROR_NAME:-$(sed -n 's/^MIRROR_NAME=//p' "${CONFIG_FILE}")}"
CONTAINER="$(docker ps \
    --filter "label=com.docker.compose.project=${PROJECT}" \
    --filter "label=com.docker.compose.service=updater" \
    --format '{{.Names}}' | head -n 1)"

if [ -z "${CONTAINER}" ]; then
    echo "Aucune synchronisation en cours pour ${1} (projet ${PROJECT})."
    exit 1
fi

echo "Suivi de ${CONTAINER} (Ctrl+C pour quitter, la synchronisation continue)..."
docker logs -f "${CONTAINER}" 2>&1 \
    | grep --line-buffered -oE '^(Racine .*|Releases .*|Mode .*|Files to download.*|\[ *[0-9]+%\]|Récapitulatif.*|  (OK|ÉCHEC) .*|Mise à jour du miroir .*)' \
    | uniq
