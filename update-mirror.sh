#!/bin/bash

usage() {
    echo "Usage : ${0} <fichier_de_configuration> [--dry-run]"
    echo "Exemple : ${0} configs/debian_11.env"
    echo "          ${0} configs/debian_11.env --dry-run   # estimation de ce qu'il reste à télécharger"
}

if [ -z "${1}" ]; then
    echo "Erreur : Vous devez spécifier le chemin du fichier de configuration du miroir."
    usage
    exit 1
fi

DRY_RUN=0
case "${2}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Erreur : option inconnue '${2}'."; usage; exit 1 ;;
esac
export DRY_RUN

# Le chemin est résolu par rapport au répertoire courant, avant le changement de répertoire.
if [ ! -f "${1}" ]; then
    echo "Erreur : Le fichier de configuration ${1} n'existe pas."
    usage
    exit 1
fi
CONFIG_FILE="$(realpath "${1}")"

cd "$(dirname "${0}")" || exit

if [ "${DRY_RUN}" = "1" ]; then
    echo "Lancement de l'estimation (dry-run) pour ${1}..."
else
    echo "Lancement de la mise à jour pour ${1}..."
fi
docker compose --env-file "${CONFIG_FILE}" run --rm updater
rc=${?}
if [ "${rc}" -ne 0 ]; then
    echo "Processus de mise à jour de ${1} terminé en erreur (code ${rc})."
else
    echo "Processus de mise à jour de ${1} terminé."
fi
exit "${rc}"
