#!/usr/bin/env bash
# ============================================================
# Démo formateur (facultative, 15 min) — installer Kubernetes « pour de vrai » avec kubeadm
# Capability Forge / Tahar ARIB — formation DOKUB, jour 1
#
# Sur une VM Linux jetable : Ubuntu 24.04, 2 vCPU, 4 Go de RAM, 20 Go de disque,
# avec un accès Internet (cloud ou hyperviseur du formateur). PAS sur le master WSL2.
#
#   sudo bash demo-kubeadm.sh verifier   prérequis du nœud (à montrer en séance)
#   sudo bash demo-kubeadm.sh preparer   noyau, containerd 2, paquets kubeadm (la VEILLE : ~5 min)
#   sudo bash demo-kubeadm.sh init       kubeadm init (en séance : ~1 min)
#   sudo bash demo-kubeadm.sh reseau     réseau des pods (Flannel) : le nœud passe Ready
#   sudo bash demo-kubeadm.sh visite     ce que kubeadm a posé : pods statiques, certificats, plan de montée de version
#   sudo bash demo-kubeadm.sh rejoindre  commande « kubeadm join » pour un second nœud
#   sudo bash demo-kubeadm.sh effacer    kubeadm reset : la VM redevient vierge (sauf les paquets)
#
# Le déroulé et le discours sont dans demo-kubeadm.md.
# ============================================================
set -euo pipefail

K8S_MINEURE=v1.37                     # même version mineure que le cluster kind des labs
POD_CIDR=10.244.0.0/16                # plage attendue par Flannel
FLANNEL=https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
export KUBECONFIG=/etc/kubernetes/admin.conf

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "\n${CYAN}$*${NC}"; }
ok()   { echo -e "  ${GREEN}[OK] $*${NC}"; }
warn() { echo -e "  ${YELLOW}[!]  $*${NC}"; }
ko()   { echo -e "  ${RED}[KO] $*${NC}"; }
die()  { ko "$*"; exit 1; }
montre() { echo -e "${YELLOW}\$ $*${NC}"; eval "$*"; }   # affiche la commande, puis l'exécute

[ "$(id -u)" -eq 0 ] || die "lancer avec sudo"

# ────────────────────────────────────────────────
verifier() {
    log "Prérequis d'un nœud kubeadm (documentation officielle)"
    local cpu mem
    cpu=$(nproc); mem=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    [ "$cpu" -ge 2 ] && ok "CPU : $cpu (2 au moins pour un control plane)" || ko "CPU : $cpu (2 au moins)"
    [ "$mem" -ge 1700 ] && ok "RAM : $mem Mo (2 Go conseillés)" || ko "RAM : $mem Mo"
    [ "$(stat -fc %T /sys/fs/cgroup/)" = cgroup2fs ] && ok "cgroup v2 (obligatoire depuis Kubernetes 1.35)" \
        || ko "cgroup v1 : le kubelet 1.35+ refuse de démarrer"
    if [ -z "$(swapon --show)" ]; then ok "swap désactivé"
    else warn "swap actif : le kubelet refuse de démarrer, sauf réglage explicite (swapoff -a)"; fi
    ok "nom d'hôte : $(hostname) — product_uuid : $(cat /sys/class/dmi/id/product_uuid 2>/dev/null || echo inconnu)"
    echo "     (noms, adresses MAC et product_uuid doivent être uniques entre les nœuds)"
    local p
    for p in 6443 2379 2380 10250 10257 10259; do
        ss -ltn "sport = :$p" | grep -q LISTEN && warn "port $p déjà occupé" || ok "port $p libre"
    done
}

# ────────────────────────────────────────────────
preparer() {
    log "[1/4] Swap et modules noyau"
    swapoff -a
    sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab              # pas de swap au redémarrage
    printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
    modprobe overlay; modprobe br_netfilter
    printf 'net.ipv4.ip_forward = 1\n' > /etc/sysctl.d/k8s.conf   # le nœud route le trafic des pods
    sysctl --system >/dev/null
    ok "swap coupé, overlay et br_netfilter chargés, routage IPv4 actif"

    log "[2/4] containerd 2 (Kubernetes 1.36+ ne prend plus en charge containerd 1.x)"
    # Ubuntu 24.04 livre containerd 1.7 : on prend le paquet containerd.io du dépôt Docker
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gpg >/dev/null
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq && apt-get install -y -qq containerd.io >/dev/null
    containerd --version | grep -q ' v2\.' || die "containerd 2 attendu : $(containerd --version)"
    containerd config default > /etc/containerd/config.toml
    grep -q 'SystemdCgroup = false' /etc/containerd/config.toml \
        || die "réglage SystemdCgroup introuvable dans la configuration par défaut : à vérifier"
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml  # même gestionnaire de cgroups que systemd
    systemctl restart containerd && systemctl enable -q containerd
    ok "$(containerd --version | awk '{print $1, $3}')"

    log "[3/4] kubeadm, kubelet, kubectl $K8S_MINEURE (dépôt pkgs.k8s.io)"
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/$K8S_MINEURE/deb/Release.key" \
        | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$K8S_MINEURE/deb/ /" \
        > /etc/apt/sources.list.d/kubernetes.list
    apt-get update -qq && apt-get install -y -qq kubelet kubeadm kubectl >/dev/null
    apt-mark hold kubelet kubeadm kubectl >/dev/null   # pas de montée de version involontaire
    systemctl enable -q kubelet
    ok "$(kubeadm version -o short) — paquets bloqués (apt-mark hold)"

    log "[4/4] Images du control plane, téléchargées à l'avance (la séance n'attend pas)"
    kubeadm config images pull 2>&1 | sed 's/^/    /'
    ok "VM prête pour « init »"
}

# ────────────────────────────────────────────────
init() {
    log "kubeadm init : le control plane démarre"
    montre "kubeadm init --pod-network-cidr=$POD_CIDR"
    mkdir -p ~/.kube && cp /etc/kubernetes/admin.conf ~/.kube/config
    log "Le nœud existe… mais n'est pas prêt : aucun réseau de pods"
    montre "kubectl get nodes"
    montre "kubectl -n kube-system get pods"
    echo "  → coredns reste Pending : sans CNI, aucun pod ne reçoit d'adresse."
}

reseau() {
    log "Réseau des pods : Flannel (kind installe kindnet ; en production : Calico, Cilium…)"
    montre "kubectl apply -f $FLANNEL"
    montre "kubectl wait --for=condition=Ready node --all --timeout=180s"
    montre "kubectl get nodes -o wide"
    log "Nœud unique de démonstration : autoriser les applications sur le control plane"
    montre "kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true"
    montre "kubectl create deployment web --image=nginx:stable --replicas=2"
    montre "kubectl rollout status deployment/web"
}

visite() {
    log "Les mêmes pods statiques que dans le nœud kind (lab 1, étape 8)"
    montre "ls /etc/kubernetes/manifests"
    log "Les certificats créés par kubeadm, et leur expiration (1 an)"
    montre "kubeadm certs check-expiration | head -14"
    log "La montée de version : une version mineure à la fois"
    montre "kubeadm upgrade plan 2>&1 | tail -20 || true"
}

rejoindre() {
    log "À exécuter sur un second nœud préparé avec « preparer »"
    montre "kubeadm token create --print-join-command"
}

effacer() {
    log "kubeadm reset : retour à une VM sans cluster"
    kubeadm reset -f
    rm -rf /etc/cni/net.d ~/.kube
    ok "cluster effacé ; containerd et les paquets restent installés"
}

case "${1:-}" in
    verifier|preparer|init|reseau|visite|rejoindre|effacer) "$1" ;;
    *) sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
