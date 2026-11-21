#!/usr/bin/env bash
# ============================================================
# Démo formateur (facultative, 15 min) — GitOps : le dossier du lab 13, appliqué par Argo CD
# Capability Forge / Tahar ARIB — formation DOKUB, jour 3, après le lab 13
#
# Sur le poste du formateur, cluster kind « dokub » dans l'état de fin du lab 13
# (dokub lab check 13 vert), avec un accès Internet. Argo CD lit le dépôt sur GitHub.
#
#   bash demo-argocd.sh installer    Argo CD dans le namespace argocd (la VEILLE ou avant la séance : ~3 min)
#   bash demo-argocd.sh ouvrir       l'interface sur https://localhost:8443 (onglet séparé), et le mot de passe admin
#   bash demo-argocd.sh application  confier le dossier labs/lab13 à Argo CD : il compare, puis synchronise
#   bash demo-argocd.sh ecart        supprimer un Service à la main : Argo CD le signale et le recrée
#   bash demo-argocd.sh commit       changer la version dans Git (branche de démo) : le rollout part seul
#   bash demo-argocd.sh etat         état de l'application : synchronisation, santé, révision
#   bash demo-argocd.sh effacer      retirer l'application (sans toucher à taskboard), puis Argo CD
#
# Variables (facultatives) :
#   DEPOT_URL  dépôt lu par Argo CD     (défaut : https://github.com/tahararib/dokub-labs.git)
#   BRANCHE    branche suivie            (défaut : demo-argocd ; créée par « commit » si absente)
#   DEPOT      clone local avec droits de push, pour « commit » (défaut : ~/dokub-labs)
#
# Le déroulé et le discours sont dans demo-argocd.md.
# ============================================================
set -euo pipefail

DEPOT_URL=${DEPOT_URL:-https://github.com/tahararib/dokub-labs.git}
BRANCHE=${BRANCHE:-demo-argocd}
DEPOT=${DEPOT:-$HOME/dokub-labs}
CHEMIN=labs/lab13
CTX=kind-dokub
ARGO_MANIFESTE=https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "\n${CYAN}$*${NC}"; }
ok()   { echo -e "  ${GREEN}[OK] $*${NC}"; }
warn() { echo -e "  ${YELLOW}[!]  $*${NC}"; }
ko()   { echo -e "  ${RED}[KO] $*${NC}"; }
die()  { ko "$*"; exit 1; }
montre() { echo -e "${YELLOW}\$ $*${NC}"; eval "$*"; }   # affiche la commande, puis l'exécute
k()    { kubectl --context "$CTX" "$@"; }

k get ns >/dev/null 2>&1 || die "cluster kind « dokub » injoignable (contexte $CTX)"

# ────────────────────────────────────────────────
installer() {
    log "Installer Argo CD (manifeste officiel, branche stable)"
    k get ns taskboard >/dev/null 2>&1 || warn "namespace taskboard absent : faites d'abord le lab 13 (ou dokub lab start 13, puis le lab)"
    k get secret postgres-cred -n taskboard >/dev/null 2>&1 || warn "Secret postgres-cred absent : la base ne démarrera pas (dette D9, lab 13)"
    k create namespace argocd --dry-run=client -o yaml | k apply -f - >/dev/null
    # --server-side : certaines CRD d'Argo CD dépassent la taille permise par l'apply côté client
    montre "kubectl --context $CTX apply -n argocd --server-side --force-conflicts -f $ARGO_MANIFESTE >/dev/null"
    log "Attendre que les composants soient prêts (2 à 3 minutes au premier téléchargement)"
    montre "kubectl --context $CTX -n argocd rollout status deployment/argocd-server --timeout=300s"
    montre "kubectl --context $CTX -n argocd rollout status deployment/argocd-repo-server --timeout=300s"
    montre "kubectl --context $CTX -n argocd rollout status statefulset/argocd-application-controller --timeout=300s"
    ok "Argo CD installé"
}

# ────────────────────────────────────────────────
ouvrir() {
    log "Mot de passe initial du compte admin"
    k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
    log "Interface : https://localhost:8443 (certificat auto-signé : accepter l'avertissement)"
    echo "  Laisser cette commande tourner dans un onglet dédié ; Ctrl+C pour arrêter."
    montre "kubectl --context $CTX -n argocd port-forward svc/argocd-server 8443:443 --address 0.0.0.0"
}

# ────────────────────────────────────────────────
application() {
    log "Vérifier que la branche suivie existe sur le dépôt"
    if git ls-remote --exit-code --heads "$DEPOT_URL" "$BRANCHE" >/dev/null 2>&1; then
        ok "branche $BRANCHE présente sur $DEPOT_URL"
        local rev=$BRANCHE
    else
        warn "branche $BRANCHE absente : l'application suit main (« commit » la créera)"
        local rev=main
    fi
    log "Confier $CHEMIN à Argo CD"
    cat <<EOF | tee /tmp/application-taskboard.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: taskboard
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $DEPOT_URL
    targetRevision: $rev
    path: $CHEMIN                  # le kustomization.yaml du lab 13
  destination:
    server: https://kubernetes.default.svc
    namespace: taskboard
  ignoreDifferences:               # replicas appartient à l'HPA (lab 9)
  - group: apps
    kind: Deployment
    jsonPointers: ["/spec/replicas"]
  syncPolicy:
    automated:
      selfHeal: true               # corriger les écarts faits à la main
      prune: false                 # ne rien supprimer : le Secret n'est pas dans Git (D9)
    syncOptions:
    - RespectIgnoreDifferences=true
EOF
    montre "kubectl --context $CTX apply -f /tmp/application-taskboard.yaml"
    log "Montrer, dans l'interface : l'arbre des objets, l'état Synced / Healthy, la révision Git"
    sleep 20
    etat
}

# ────────────────────────────────────────────────
ecart() {
    log "Un écart fait à la main : supprimer le Service NodePort"
    montre "kubectl --context $CTX -n taskboard delete service taskboard-np"
    montre "kubectl --context $CTX -n taskboard get service taskboard-np || true"
    log "Argo CD constate l'écart (OutOfSync) et recrée le Service (selfHeal) : 5 à 20 secondes"
    for _ in $(seq 1 12); do
        sleep 5
        if k -n taskboard get service taskboard-np >/dev/null 2>&1; then
            ok "Service taskboard-np recréé par Argo CD, sans aucune commande"
            montre "kubectl --context $CTX -n taskboard get service taskboard-np"
            return 0
        fi
    done
    warn "pas encore recréé : forcer une comparaison avec « refresh »"
    k -n argocd annotate application taskboard argocd.argoproj.io/refresh=normal --overwrite >/dev/null
}

# ────────────────────────────────────────────────
commit() {
    [ -d "$DEPOT/.git" ] || die "clone local introuvable : DEPOT=$DEPOT (il faut un clone avec droits de push)"
    log "Changer la version livrée dans Git, sur la branche $BRANCHE"
    git -C "$DEPOT" fetch -q origin
    if git -C "$DEPOT" ls-remote --exit-code --heads origin "$BRANCHE" >/dev/null 2>&1; then
        git -C "$DEPOT" switch -q "$BRANCHE" 2>/dev/null || git -C "$DEPOT" switch -q -c "$BRANCHE" "origin/$BRANCHE"
        git -C "$DEPOT" pull -q --ff-only origin "$BRANCHE"
    else
        git -C "$DEPOT" switch -q -c "$BRANCHE" origin/main
    fi
    local f="$DEPOT/$CHEMIN/kustomization.yaml" actuelle nouvelle
    actuelle=$(sed -n 's/^  newTag: "\(.*\)"/\1/p' "$f")
    [ "$actuelle" = "2.0.0" ] && nouvelle=1.0.0 || nouvelle=2.0.0
    montre "sed -i 's/^  newTag: \"$actuelle\"/  newTag: \"$nouvelle\"/' $f"
    montre "git -C $DEPOT diff --stat"
    montre "git -C $DEPOT commit -qam 'démo Argo CD : taskboard en $nouvelle'"
    montre "git -C $DEPOT push -q -u origin $BRANCHE"
    git -C "$DEPOT" switch -q main
    if [ "$(k -n argocd get application taskboard -o jsonpath='{.spec.source.targetRevision}')" != "$BRANCHE" ]; then
        log "L'application suivait main : la faire suivre $BRANCHE"
        montre "kubectl --context $CTX -n argocd patch application taskboard --type merge -p '{\"spec\":{\"source\":{\"targetRevision\":\"$BRANCHE\"}}}'"
    fi
    log "Argo CD relit le dépôt toutes les 3 minutes ; on lui demande de le faire tout de suite"
    montre "kubectl --context $CTX -n argocd annotate application taskboard argocd.argoproj.io/refresh=normal --overwrite"
    montre "kubectl --context $CTX -n taskboard rollout status deployment/taskboard --timeout=180s"
    montre "kubectl --context $CTX -n taskboard get deployment taskboard -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"
    ok "version $nouvelle déployée par un commit ; relancer « commit » pour revenir"
}

# ────────────────────────────────────────────────
etat() {
    log "État de l'application taskboard"
    k -n argocd get application taskboard \
      -o custom-columns='SYNC:.status.sync.status,SANTÉ:.status.health.status,RÉVISION:.status.sync.revision,BRANCHE:.spec.source.targetRevision'
}

# ────────────────────────────────────────────────
effacer() {
    log "Retirer l'application : sans finalizer, les objets de taskboard restent en place"
    montre "kubectl --context $CTX -n argocd delete application taskboard --ignore-not-found"
    log "Retirer Argo CD"
    montre "kubectl --context $CTX delete -n argocd --ignore-not-found -f $ARGO_MANIFESTE >/dev/null"
    montre "kubectl --context $CTX delete namespace argocd --ignore-not-found"
    ok "Argo CD retiré ; taskboard tourne toujours"
}

case "${1:-}" in
    installer|ouvrir|application|ecart|commit|etat|effacer) "$1" ;;
    *) sed -n '3,22p' "$0"; exit 1 ;;
esac
