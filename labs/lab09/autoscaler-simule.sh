#!/usr/bin/env bash
# ============================================================
# Lab 9, étape 5 (facultative) — Un autoscaler de nœuds SIMULÉ
#
# kind ne peut pas créer de machine. Ce script joue le rôle d'un Cluster
# Autoscaler avec un nœud existant, dokub-worker2, gardé « en réserve » :
#   - au départ, il met la réserve hors service (cordon) : un seul worker reçoit les nouveaux pods ;
#   - des pods restent Pending (Unschedulable) : il « commande » un nœud,
#     attend un démarrage simulé, puis remet la réserve en service (uncordon) ;
#   - la réserve n'héberge plus aucun pod de remplissage pendant 60 s :
#     il la « rend » (cordon).
# Ctrl+C : la réserve est remise en service, le cluster revient à son état normal.
#
# Ce qui est réel : les nœuds, les pods, le scheduler, le message Unschedulable.
# Ce qui est simulé : la création et la suppression de la machine, et les critères de retrait
# (un vrai autoscaler : utilisation < 50 % des requests, pods déplaçables, 10 minutes).
#
#   bash ~/dokub-labs/labs/lab09/autoscaler-simule.sh
# Variables : RESERVE (dokub-worker2), DEMARRAGE (15 s), INUTILE (60 s)
# ============================================================
set -uo pipefail

RESERVE=${RESERVE:-dokub-worker2}
DEMARRAGE=${DEMARRAGE:-15}       # « démarrage de la machine » : quelques minutes dans un cloud
INUTILE=${INUTILE:-60}           # nœud inutile avant retrait : 10 minutes par défaut dans un vrai autoscaler
PERIODE=5                        # un vrai Cluster Autoscaler regarde toutes les 10 s
NS=taskboard

dit() { echo "$(date +%H:%M:%S)  $*"; }

remettre() {
    kubectl uncordon "$RESERVE" >/dev/null 2>&1
    echo
    dit "fin : $RESERVE remis en service (uncordon)"
    exit 0
}
trap remettre INT TERM

kubectl get node "$RESERVE" >/dev/null 2>&1 || { echo "nœud $RESERVE introuvable"; exit 1; }

kubectl cordon "$RESERVE" >/dev/null
dit "départ : $RESERVE en réserve (cordon)"
dit "surveillance toutes les ${PERIODE} s ; Ctrl+C pour arrêter"

vide_depuis=""
while true; do
    # Pods que le scheduler n'a pu placer nulle part : le signal d'un autoscaler de nœuds
    attente=$(kubectl get pods -n "$NS" --field-selector=status.phase=Pending \
        -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="PodScheduled")].reason}{"\n"}{end}' \
        | grep -c Unschedulable)

    if [ "$(kubectl get node "$RESERVE" -o jsonpath='{.spec.unschedulable}')" = "true" ]; then
        # Réserve hors service : faut-il « commander » un nœud ?
        if [ "$attente" -gt 0 ]; then
            dit "$attente pod(s) Unschedulable : commande d'un nœud"
            dit "démarrage simulé de la machine : ${DEMARRAGE} s"
            sleep "$DEMARRAGE"
            kubectl uncordon "$RESERVE" >/dev/null
            dit "$RESERVE prêt (uncordon) : pods placés"
            vide_depuis=""
        fi
    else
        # Réserve en service : est-elle encore utile ?
        n=$(kubectl get pods -n "$NS" -l app=remplissage \
              --field-selector spec.nodeName="$RESERVE" -o name | wc -l)
        if [ "$n" -eq 0 ] && [ "$attente" -eq 0 ]; then
            if [ -z "$vide_depuis" ]; then
                vide_depuis=$SECONDS
                dit "$RESERVE sans remplissage : décompte ${INUTILE} s"
            elif [ $((SECONDS - vide_depuis)) -ge "$INUTILE" ]; then
                kubectl cordon "$RESERVE" >/dev/null
                dit "$RESERVE inutile depuis ${INUTILE} s : rendu (cordon)"
                vide_depuis=""
            fi
        else
            vide_depuis=""
        fi
    fi
    sleep "$PERIODE"
done
