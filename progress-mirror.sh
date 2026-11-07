#!/bin/bash
# Suit l'avancement de la synchronisation en cours d'un miroir.
# Affiche la racine en cours, le volume à télécharger, le pourcentage et le récapitulatif final.

usage() {
    echo "Usage : ${0} <fichier_de_configuration>"
    echo "Exemple : ${0} configs/debian_11.env"
}

if [ -z "${1}" ]; then
    echo "Erreur : Vous devez spécifier le chemin du fichier de configuration du miroir."
    usage
    exit 1
fi

# Le chemin est résolu par rapport au répertoire courant.
if [ ! -f "${1}" ]; then
    echo "Erreur : Le fichier de configuration ${1} n'existe pas."
    usage
    exit 1
fi
CONFIG_FILE="${1}"

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
