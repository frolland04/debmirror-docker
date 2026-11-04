#!/bin/bash
cd "$(dirname "${0}")" || exit

usage() {
    echo "Usage : ${0} <nom_du_miroir> [--dry-run]"
    echo "Exemple : ${0} debian_11"
    echo "          ${0} debian_11 --dry-run   # estimation de ce qu'il reste à télécharger"
}

if [ -z "${1}" ]; then
    echo "Erreur : Vous devez spécifier le nom du miroir. C'est le même que le nom du fichier de configuration."
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

CONFIG_FILE="configs/${1}.env"
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Erreur : Le fichier de configuration ${CONFIG_FILE} n'existe pas."
    exit 1
fi

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
