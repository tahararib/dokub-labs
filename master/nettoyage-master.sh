#!/usr/bin/env bash
# shellcheck disable=SC2088  # les « ~ » des messages sont du texte affiché, pas des chemins
# ============================================================
# nettoyage-master.sh — remet le master DOKUB dans l'état « avant formation »
# Capability Forge / Tahar ARIB
#
# Retire ce que les participants installent ou créent eux-mêmes :
#   clusters kind, cloud-provider-kind et ses répartiteurs, kubectl, kind,
#   Helm, k9s, stern, kubectx, ~/.kube, réglages bash (kubectl, DOKUB_POSTE), ~/labs, ~/.dokub, ~/rg,
#   relais socat et port-forward, historique bash,
#   images et volumes devenus inutiles.
# Garde : Docker, jq, yq, socat, ~/dokub-labs, commande dokub, images
#         postgres, kindest/node, cloud-provider-kind, registry, envoy, busybox,
#         nginx, metrics-server et taskboard.
#
# Exécution :  bash ~/dokub-labs/master/nettoyage-master.sh
# Ensuite   :  bash ~/dokub-labs/master/install-wsl2-dokub.sh step_08_validate
# ============================================================
set -uo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "\n${CYAN}$*${NC}"; }
ok()  { echo -e "  ${GREEN}[OK] $*${NC}"; }

log "Relais encore actifs (socat du lab 6, port-forward des labs 2 et 12)"
pkill -f "socat TCP4-LISTEN" 2>/dev/null && ok "socat arrêté"
pkill -f "kubectl.* port-forward" 2>/dev/null && ok "port-forward arrêtés"

log "Clusters kind et répartiteurs"
if command -v kind >/dev/null; then
    for c in $(kind get clusters 2>/dev/null); do kind delete cluster --name "$c" >/dev/null 2>&1 && ok "cluster $c supprimé"; done
fi
docker rm -f cloud-provider-kind >/dev/null 2>&1 && ok "cloud-provider-kind supprimé"
# cloud-provider-kind crée un conteneur répartiteur par Service LoadBalancer / Gateway
for c in $(docker ps -aq --filter "name=kindccm"); do docker rm -f "$c" >/dev/null; done
left=$(docker ps -aq); [ -n "$left" ] && docker rm -f $left >/dev/null
ok "aucun conteneur restant"

log "Outils installés par les participants"
for b in kubectl kind helm k9s stern; do
    [ -e "/usr/local/bin/$b" ] && sudo rm -f "/usr/local/bin/$b" && ok "/usr/local/bin/$b retiré"
done
dpkg -s kubectx >/dev/null 2>&1 && sudo apt-get remove -y -q kubectx >/dev/null && ok "paquet kubectx retiré"
rm -rf ~/.kube ~/.cache/helm ~/.config/helm ~/.local/share/helm ~/.config/k9s ~/.local/share/k9s ~/labs ~/.dokub ~/rg
ok "~/.kube, configurations Helm et k9s, ~/labs, ~/.dokub (lignes de progression), ~/rg supprimés"

log "Réglages bash de kubectl (ajoutés par les participants au lab 1)"
# Sans kubectl, « source <(kubectl completion bash) » afficherait une erreur à chaque ouverture
sed -i '/# --- DOKUB : complétion kubectl et alias k ---/,+3d' ~/.bashrc
sed -i '/kubectl completion bash/d; /^alias k=kubectl$/d; /__start_kubectl k$/d' ~/.bashrc
sed -i '/^export DOKUB_POSTE=/d' ~/.bashrc     # nom du participant (auto-évaluation, J1)
ok "~/.bashrc nettoyé"

log "Historique des commandes (les solutions du dry run)"
rm -f ~/.bash_history ~/.lesshst ~/.psql_history
ok "~/.bash_history supprimé ; fermez ensuite ce terminal sans relancer de commande"

log "Images et volumes inutiles"
# busybox, nginx, metrics-server, envoy restent : secours « kind load » si Docker Hub limite (README)
docker rmi maven:3.9-eclipse-temurin-21 >/dev/null 2>&1 && ok "maven:3.9-eclipse-temurin-21 retirée"
# Étiquettes localhost:5001/… : posées par les participants au lab 1 (les images taskboard:* restent)
for v in 1.0.0 2.0.0 3.0.0; do docker rmi "localhost:5001/taskboard:$v" >/dev/null 2>&1; done
ok "étiquettes localhost:5001/taskboard retirées"
docker volume rm dokub-m2 >/dev/null 2>&1 && ok "volume dokub-m2 retiré"
docker image prune -f >/dev/null; docker builder prune -af >/dev/null
rm -rf /tmp/kubectl* /tmp/kind* /tmp/*.yaml /tmp/get_helm.sh /tmp/helm*
ok "images orphelines et cache de construction purgés"

log "État final"
docker images --format '  {{.Repository}}:{{.Tag}}  {{.Size}}'
df -h / | tail -1 | awk '{print "  disque Ubuntu : " $3 " utilisés, " $4 " libres"}'
echo -e "\n  Étape suivante : bash ~/dokub-labs/master/install-wsl2-dokub.sh step_08_validate"
