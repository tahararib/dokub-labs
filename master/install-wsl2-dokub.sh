#!/usr/bin/env bash
# shellcheck disable=SC2088  # les « ~ » des messages sont du texte affiché, pas des chemins
# ============================================================
# install-wsl2-dokub.sh — préparation du master DOKUB (Ubuntu 24.04 dans WSL2)
# Capability Forge / Tahar ARIB
#
# Répartition retenue (21/11/2026) :
#   PRÉINSTALLÉ ici : Docker CE, outils de base (git, curl, jq, yq, socat),
#                     réglages noyau pour kind, images des premiers labs,
#                     dépôt dokub-labs, images taskboard construites.
#   INSTALLÉ PAR LES PARTICIPANTS : kubectl et kind (lab 1), Helm (lab 12).
#   → ce script n'installe NI kubectl, NI kind, NI Helm.
#
# Exécution (compte Linux normal, pas root) :  bash install-wsl2-dokub.sh
# Une seule étape :                             bash install-wsl2-dokub.sh step_07_depots
# Rejouable : chaque étape vérifie l'état avant d'agir.
# ============================================================
set -euo pipefail
STEP=${1:-all}

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "\n${CYAN}$*${NC}"; }
ok()   { echo -e "  ${GREEN}[OK] $*${NC}"; }
warn() { echo -e "  ${YELLOW}[!]  $*${NC}"; }
die()  { echo -e "  ${RED}[KO] $*${NC}"; exit 1; }
is_installed() { command -v "$1" &>/dev/null; }
latest_tag() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name'; }

# Images gardées sur le poste (versions figées, identiques au carnet)
IMAGES=(
  postgres:16-alpine                                                  # lab 0 (Docker Compose)
  kindest/node:v1.37.0                                                # lab 1 : image des nœuds kind
  registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0 # lab 1, étape 5
  registry:3                                                          # lab 1, étape 6 : registre local
)

[ "$(id -u)" -eq 0 ] && die "Lancer ce script avec le compte Linux normal, pas en root."

# ────────────────────────────────────────────────
step_01_systemd() {
    log "[01/08] systemd dans WSL2 (démarrage automatique de Docker)..."
    if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then ok "systemd actif"; return; fi
    grep -q "systemd=true" /etc/wsl.conf 2>/dev/null || printf "\n[boot]\nsystemd=true\n" | sudo tee -a /etc/wsl.conf >/dev/null
    warn "systemd activé : PowerShell → wsl --shutdown, rouvrir Ubuntu, relancer ce script"; exit 0
}

# ────────────────────────────────────────────────
step_02_base_tools() {
    log "[02/08] Outils de base..."
    sudo apt-get update -q
    sudo apt-get upgrade -y -q
    # socat : relais localhost → Gateway (lab 6) ; jq : lecture du JSON (lab 3)
    sudo apt-get install -y -q curl wget git jq make unzip ca-certificates gnupg bash-completion tree socat
    ok "curl, git, jq, socat, bash-completion installés"
}

# ────────────────────────────────────────────────
# Source : https://docs.docker.com/engine/install/ubuntu/
step_03_docker_ce() {
    log "[03/08] Docker CE (sans Docker Desktop)..."
    if is_installed docker; then ok "Docker déjà installé ($(docker --version))"
    else
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo apt-get update -q
        sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ok "Docker CE installé ($(docker --version))"
    fi
    sudo systemctl enable --now docker >/dev/null 2>&1
    if ! id -nG "$USER" | grep -qw docker; then
        sudo usermod -aG docker "$USER"
        warn "Compte ajouté au groupe docker : effectif à la prochaine ouverture de session"
    fi
}

# ────────────────────────────────────────────────
# Source : https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files
step_04_kernel_limits() {
    log "[04/08] Limites inotify pour un cluster kind de 3 nœuds..."
    printf "fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 512\n" \
        | sudo tee /etc/sysctl.d/99-kind.conf >/dev/null
    sudo sysctl --system >/dev/null
    ok "max_user_watches=$(sysctl -n fs.inotify.max_user_watches), max_user_instances=$(sysctl -n fs.inotify.max_user_instances)"
    [ "$(stat -fc %T /sys/fs/cgroup)" = "cgroup2fs" ] && ok "cgroup v2 actif" || die "cgroup v1 : les nœuds kind 1.35+ ne démarreront pas"
}

# ────────────────────────────────────────────────
# yq : https://github.com/mikefarah/yq/releases (lab 3 : YAML → JSON)
step_05_yq() {
    log "[05/08] yq..."
    if is_installed yq; then ok "yq déjà installé ($(yq --version))"; return; fi
    local v; v=$(latest_tag mikefarah/yq)
    curl -fsSL -o /tmp/yq "https://github.com/mikefarah/yq/releases/download/${v}/yq_linux_amd64"
    sudo install -m 0755 /tmp/yq /usr/local/bin/yq && rm -f /tmp/yq
    ok "yq ${v} installé"
}

# Les étapes suivantes utilisent docker sans sudo : il faut une session ouverte après l'étape 03.
docker_ok() { docker info >/dev/null 2>&1 || die "docker inaccessible sans sudo : fermer Ubuntu, PowerShell → wsl --terminate Ubuntu-24.04, rouvrir, puis : bash install-wsl2-dokub.sh $1"; }

# ────────────────────────────────────────────────
step_06_images() {
    log "[06/08] Images gardées sur le poste..."
    docker_ok step_06_images
    for img in "${IMAGES[@]}"; do
        if docker image inspect "$img" >/dev/null 2>&1; then ok "$img déjà présente"
        else docker pull -q "$img" >/dev/null && ok "$img récupérée"; fi
    done
}

# ────────────────────────────────────────────────
step_07_depots() {
    log "[07/08] Dépôt des labs et images taskboard..."
    docker_ok step_07_depots
    if [ -d "$HOME/dokub-labs/.git" ]; then git -C "$HOME/dokub-labs" pull -q
    else git clone -q https://github.com/tahararib/dokub-labs.git "$HOME/dokub-labs"; fi
    sudo ln -sf ~/dokub-labs/bin/dokub /usr/local/bin/dokub
    ok "~/dokub-labs à jour, commande dokub disponible"

    if docker image inspect taskboard:1.0.0 taskboard:2.0.0 taskboard:3.0.0 >/dev/null 2>&1; then
        ok "images taskboard déjà construites"
    else
        local src; src=$(mktemp -d)
        git clone -q -b dokub https://github.com/tahararib/taskboard.git "$src/taskboard"
        bash "$src/taskboard/dokub/build-images.sh"
        rm -rf "$src"
        # l'outillage de construction ne sert plus : on allège le master
        docker rmi maven:3.9-eclipse-temurin-21 >/dev/null 2>&1 || true
        docker volume rm dokub-m2 >/dev/null 2>&1 || true
        ok "images taskboard 1.0.0, 2.0.0, 3.0.0 construites"
    fi
}

# ────────────────────────────────────────────────
step_08_validate() {
    log "[08/08] Validation du master..."
    local pass=0 fail=0
    check() { if eval "$2" &>/dev/null; then echo -e "  ${GREEN}[OK] $1${NC}"; pass=$((pass+1)); else echo -e "  ${RED}[KO] $1${NC}"; fail=$((fail+1)); fi; }
    check "systemd actif"                       "[ \"\$(ps -p 1 -o comm=)\" = systemd ]"
    check "docker utilisable sans sudo"          "docker info"
    check "cgroup v2"                            "[ \"\$(stat -fc %T /sys/fs/cgroup)\" = cgroup2fs ]"
    check "limites inotify"                      "[ \$(sysctl -n fs.inotify.max_user_watches) -ge 524288 ]"
    check "jq, yq, socat, git, curl"             "command -v jq && command -v yq && command -v socat && command -v git && command -v curl"
    for img in "${IMAGES[@]}" taskboard:1.0.0 taskboard:2.0.0 taskboard:3.0.0; do
        check "image $img"                       "docker image inspect $img"
    done
    check "commande dokub"                       "command -v dokub"
    # Ce que les participants installent eux-mêmes ne doit PAS être sur le master
    check "kubectl absent (installé au lab 1)"   "! command -v kubectl"
    check "kind absent (installé au lab 1)"      "! command -v kind"
    check "helm absent (installé au lab 12)"     "! command -v helm"
    check "aucun cluster ni conteneur restant"   "[ -z \"\$(docker ps -aq)\" ]"
    echo -e "\n  Réussis : ${pass} / Échoués : ${fail}"
    [ "$fail" -eq 0 ] && ok "Master conforme : prêt pour la capture FOG (après compactage du disque WSL)." \
                      || warn "Corriger les lignes [KO] (sur un master existant : bash nettoyage-master.sh)."
}

ALL_STEPS=(step_01_systemd step_02_base_tools step_03_docker_ce step_04_kernel_limits
           step_05_yq step_06_images step_07_depots step_08_validate)
if [ "$STEP" = "all" ]; then for s in "${ALL_STEPS[@]}"; do "$s"; done
elif declare -f "$STEP" >/dev/null; then "$STEP"
else die "Étape inconnue : $STEP — étapes : ${ALL_STEPS[*]}"; fi
