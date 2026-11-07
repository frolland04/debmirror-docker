# Makefile d'exploitation des miroirs.
# Usage : make <cible> CONFIG=configs/<miroir>.env
# CONFIG est le chemin du fichier de configuration, résolu depuis le répertoire courant.

SHELL := /bin/bash

ROOT        := $(patsubst %/,%,$(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
COMPOSE     := docker compose -f $(ROOT)/docker-compose.yml --project-directory $(ROOT)
CONFIG_ABS   = $(realpath $(CONFIG))
NAME         = $(basename $(notdir $(CONFIG)))
PROJECT      = $(shell sed -n 's/^MIRROR_NAME=//p' "$(CONFIG_ABS)")
SYSTEMD_DIR ?= /etc/systemd/system
INSTALL_DIR := /opt/debmirror
UNITS       := debmirror@.service debmirror-update@.service debmirror-update@.timer
REQUIRED    := MIRROR_NAME PORT MIRROR_HOST MIRROR_ROOT ARCHITECTURES SECTIONS

# Conteneurs du projet pour un service donné (mêmes labels que progress-mirror.sh).
containers = docker ps --filter "label=com.docker.compose.project=$(PROJECT)" --filter "label=com.docker.compose.service=$(1)" --format '{{.Names}}'

.DEFAULT_GOAL := help
.PHONY: help list check start-web stop-web build start-update stop-update dry-run \
        show-progress logs status du start-timer stop-timer install uninstall \
        need-config warn-systemd-path

help: ## Affiche cette aide
	@echo "Usage : make <cible> [CONFIG=configs/<miroir>.env]"
	@echo "Exemple : make start-web CONFIG=configs/ubuntu_20.04.env"
	@echo ""
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

need-config:
	@if [ -z "$(CONFIG)" ]; then \
	    echo "Erreur : CONFIG doit indiquer le chemin du fichier de configuration du miroir."; \
	    echo "Exemple : make $(MAKECMDGOALS) CONFIG=configs/debian_12.env"; \
	    exit 1; \
	fi
	@if [ ! -f "$(CONFIG)" ]; then \
	    echo "Erreur : Le fichier de configuration \"$(CONFIG)\" n'existe pas."; \
	    exit 1; \
	fi

warn-systemd-path: need-config
	@if [ "$(CONFIG_ABS)" != "$(INSTALL_DIR)/configs/$(NAME).env" ]; then \
	    echo "Avertissement : l'unité systemd lira \"$(INSTALL_DIR)/configs/$(NAME).env\" et non \"$(CONFIG_ABS)\"."; \
	fi

list: ## Liste les configurations disponibles
	@printf "%-50s %-45s %-6s %s\n" FICHIER MIRROR_NAME PORT MIRROR_HOST
	@for f in $(ROOT)/configs/*.env; do \
	    printf "%-50s %-45s %-6s %s\n" "configs/$${f##*/}" \
	        "$$(sed -n 's/^MIRROR_NAME=//p' "$$f")" \
	        "$$(sed -n 's/^PORT=//p' "$$f")" \
	        "$$(sed -n 's/^MIRROR_HOST=//p' "$$f")"; \
	done

check: ## Vérifie toutes les configurations (variables obligatoires, doublons, compose)
	@rc=0; \
	for f in $(ROOT)/configs/*.env; do \
	    for v in $(REQUIRED); do \
	        grep -q "^$$v=." "$$f" || { echo "ERREUR \"configs/$${f##*/}\" : $$v manquant"; rc=1; }; \
	    done; \
	    $(COMPOSE) --env-file "$$f" config -q || { echo "ERREUR \"configs/$${f##*/}\" : docker compose config invalide"; rc=1; }; \
	done; \
	for v in PORT MIRROR_NAME; do \
	    dups="$$(grep -H "^$$v=" $(ROOT)/configs/*.env | sed "s/^.*:$$v=//" | sort | uniq -d)"; \
	    for d in $$dups; do \
	        echo "ERREUR : $$v=\"$$d\" utilisé par : $$(grep -l "^$$v=$$d\$$" $(ROOT)/configs/*.env | xargs -n1 basename | tr '\n' ' ')"; \
	        rc=1; \
	    done; \
	done; \
	[ $$rc -eq 0 ] && echo "Toutes les configurations sont valides."; \
	exit $$rc

start-web: need-config ## Sert le miroir (nginx)
	$(COMPOSE) --env-file "$(CONFIG_ABS)" up -d web

stop-web: need-config ## Arrête le nginx du miroir (une mise à jour en cours continue)
	$(COMPOSE) --env-file "$(CONFIG_ABS)" rm -sf web

build: need-config ## Reconstruit l'image de mise à jour (après une modification d'entrypoint.sh)
	$(COMPOSE) --env-file "$(CONFIG_ABS)" build updater

start-update: need-config ## Lance une mise à jour en arrière-plan
	DRY_RUN=0 $(COMPOSE) --env-file "$(CONFIG_ABS)" run -d --rm updater
	@echo "Mise à jour de \"$(CONFIG)\" lancée. Suivi : make show-progress CONFIG=$(CONFIG)"

stop-update: need-config ## Arrête la mise à jour en cours
	@c="$$($(call containers,updater))"; \
	if [ -z "$$c" ]; then \
	    echo "Aucune mise à jour en cours pour \"$(CONFIG)\" (projet \"$(PROJECT)\")."; \
	else \
	    docker stop $$c; \
	fi

dry-run: need-config ## Estime le volume à télécharger (premier plan)
	$(ROOT)/update-mirror.sh "$(CONFIG_ABS)" --dry-run

show-progress: need-config ## Suit l'avancement de la mise à jour en cours
	$(ROOT)/progress-mirror.sh "$(CONFIG_ABS)"

logs: need-config ## Logs de la mise à jour en cours, sinon du dernier lancement par le timer
	@c="$$($(call containers,updater) | head -n 1)"; \
	if [ -n "$$c" ]; then \
	    docker logs -f "$$c"; \
	else \
	    echo "Aucune mise à jour en cours pour \"$(CONFIG)\", journal de \"debmirror-update@$(NAME).service\" :"; \
	    journalctl -u "debmirror-update@$(NAME).service" -n 200 --no-pager; \
	fi

status: need-config ## État du nginx, de la mise à jour et du timer
	@echo "Miroir   : \"$(CONFIG)\" (projet \"$(PROJECT)\")"
	@w="$$($(call containers,web))"; echo "Nginx    : $${w:+en cours (\"$$w\")}$${w:-arrêté}"
	@u="$$($(call containers,updater))"; echo "Mise à j.: $${u:+en cours (\"$$u\")}$${u:-aucune}"
	@e="$$(systemctl is-enabled debmirror-update@$(NAME).timer 2>/dev/null)"; \
	a="$$(systemctl is-active debmirror-update@$(NAME).timer 2>/dev/null)"; \
	echo "Timer    : \"debmirror-update@$(NAME).timer\" $${e:-inconnu (unités non installées ?)} / $${a:-inconnu}"
	@systemctl list-timers --all --no-pager "debmirror-update@$(NAME).timer" 2>/dev/null | head -n 2 || true
	@systemctl show -p Result -p ExecMainStatus -p ExecMainExitTimestamp "debmirror-update@$(NAME).service" 2>/dev/null || true

du: need-config ## Occupation disque du miroir
	@d="$$(set -a; . "$(CONFIG_ABS)"; echo "$${MIRROR_DATA:-/data/debmirror/$${MIRROR_NAME}}")"; \
	if [ -d "$$d" ]; then shopt -s nullglob; du -sh "$$d"/* "$$d"; else echo "Répertoire \"$$d\" absent."; fi

start-timer: warn-systemd-path ## Active la mise à jour périodique (systemd)
	systemctl enable --now "debmirror-update@$(NAME).timer"

stop-timer: warn-systemd-path ## Désactive la mise à jour périodique (systemd)
	systemctl disable --now "debmirror-update@$(NAME).timer"

install: ## Installe les unités systemd
	cp $(addprefix $(ROOT)/,$(UNITS)) $(SYSTEMD_DIR)/
	systemctl daemon-reload

uninstall: ## Désinstalle les unités systemd (désactiver d'abord les timers avec stop-timer)
	@echo "Rappel : désactivez d'abord les timers actifs (make stop-timer CONFIG=...)."
	rm -f $(addprefix $(SYSTEMD_DIR)/,$(UNITS))
	systemctl daemon-reload
