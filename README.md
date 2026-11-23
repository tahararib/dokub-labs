# dokub-labs — environnement des labs « Kubernetes, les essentiels »

Capability Forge — formation DOKUB (3 jours, 14 labs).
L'application des labs est **taskboard**, branche `dokub` du dépôt `tahararib/taskboard`.

## Contenu

| Chemin | Rôle |
|---|---|
| `bin/dokub` | commande de l'environnement : cluster, images, mesures (puis `lab start` / `lab check`) |
| `cluster/kind-dokub.yaml` | cluster des labs : 1 control plane + 2 workers, Kubernetes 1.37.0, NodePort 30080 publié sur le port 8080 |
| `cluster/metrics-server.yaml` | metrics-server v0.9.1, copie du manifeste officiel + `--kubelet-insecure-tls` |
| `manifests/mesure/` | PostgreSQL + taskboard pour la mesure des temps de démarrage |
| `labs/` | fichiers que les participants copient ou appliquent : `lab00/compose.yaml` ; `commun/boucle.yaml` (requêtes en continu, labs 4 et 7) et `commun/outils.yaml` (pod de diagnostic conforme « restricted ») ; `lab06/` (Service sans sélecteur, headless, Gateway) ; `lab07/` (canary, bleu/vert) |
| `solutions/labNN/` | état attendu en fin de lab NN ; `dokub lab start NN+1` les applique (cumulativement) |

## Répartition du travail (décidée le 21/11/2026)

| Préinstallé sur le master | Fait par les participants |
|---|---|
| Windows Terminal, VS Code, WSL2, Ubuntu 24.04 | installer kubectl et kind (lab 1) |
| Docker CE, git, curl, jq, yq, socat | créer le cluster (lab 1) |
| images postgres, kindest/node, cloud-provider-kind, registry:3, taskboard 1.0/2.0/3.0 | démarrer cloud-provider-kind et un registre local, installer metrics-server, étiqueter et pousser les images taskboard (lab 1) |
| dépôt `~/dokub-labs`, commande `dokub` | installer Helm (lab 12) |

`dokub` ne remplace aucun geste du carnet : `lab check` vérifie, `lab start` remet un participant bloqué en selle.

## Mesure de progression (décidée le 23/11/2026, pas de QCM)

| Quand | Commande participant | Ce qui est mesuré |
|---|---|---|
| J1 9:30 et J3 16:35 | `dokub auto a b c d e` | auto-évaluation, une note de 1 à 4 par objectif de la formation |
| J2 9:30, J3 9:30, J3 16:35 | `dokub incident start 1` (puis 2, 3) ; `dokub incident indice` ; `dokub incident check` | incident sans indications dans le namespace `incident` : résolu ou non, minutes, indices demandés |
| fin de chaque lab | `dokub lab check NN` | points de contrôle du lab (ligne `LAB NN` déjà en place) |

Chaque commande affiche une ligne à coller dans le chat et l'ajoute à `~/.dokub/progression.log` (`dokub bilan` les réaffiche).
Rien ne quitte le poste. Le nom affiché est `$DOKUB_POSTE` (réglé par chaque participant le premier matin, espaces remplacés par `_`), sinon le nom de la machine.
Côté formateur : copier le chat dans un fichier, puis `python3 formateur/progression.py chat.txt` (`--anonyme` pour la projection).

`dokub incident start` est la seule commande qui met volontairement le cluster en panne : c'est une mise en place, comme `lab start`, pas un geste du carnet.

## Préparer le master

Scripts dans `master/` :

| Script | Rôle |
|---|---|
| `install-windows-dokub.ps1` | partie Windows : WSL2, Ubuntu 24.04, `.wslconfig`, Windows Terminal et VS Code (étape facultative) |
| `install-wsl2-dokub.sh` | partie Ubuntu : Docker CE, outils de base, images, dépôt, images taskboard ; validation finale |
| `nettoyage-master.sh` | remet un master déjà utilisé dans l'état « avant formation » |
| `inventaire-master.ps1` | inventaire Windows en lecture seule |

### Rejouer les labs sur le master (dry run)

Les participants partent d'un poste cloné, déjà dans l'état du premier matin : ils n'ont rien de ceci à faire.
Le formateur qui rejoue les labs sur le master le remet d'abord dans cet état :

```
cd ~/dokub-labs && git pull
cp -r ~/rg ~/rg-sauvegarde              # si vous enregistrez vos essais dans ~/rg
bash ~/dokub-labs/master/nettoyage-master.sh
mv ~/rg-sauvegarde ~/rg
dokub images && dokub lab start 01      # « Prêt pour le lab 1 : aucun cluster »
```

Puis fermer tous les onglets Ubuntu et en ouvrir un nouveau : un onglet déjà ouvert garde l'alias `k` et la complétion de kubectl que le nettoyage a retirés de `~/.bashrc`.
Avant de cloner les postes, relancer le nettoyage une dernière fois.

## Accès depuis Windows (vérifié sur le master le 20/11/2026)

| Mode | Depuis Ubuntu | Depuis le navigateur Windows |
|---|---|---|
| NodePort publié (`localhost:8080`) | oui | oui |
| `kubectl port-forward --address 0.0.0.0` | oui | oui (`localhost:<port>`) |
| Adresse LoadBalancer / Gateway (`172.18.x.x`) | oui | non : relais `socat` vers un port localhost |

## Accès Internet nécessaires depuis Ubuntu (session et préparation)

| Site | Pour |
|---|---|
| `dl.k8s.io` | kubectl (lab 1) |
| `kind.sigs.k8s.io`, `github.com`, `objects.githubusercontent.com` | kind (lab 1) |
| `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com` | busybox, postgres, nginx, tirés par les nœuds. Limite anonyme mesurée le 23/11/2026 depuis le master : 100 téléchargements par heure et par adresse. En cas de `toomanyrequests` : `kind load docker-image postgres:16-alpine busybox:1.37 nginx:stable --name dokub` (images présentes sur le poste) |
| `registry.k8s.io` | metrics-server, cloud-provider-kind |
| `quay.io` | node-exporter (lab 8) |
| `raw.githubusercontent.com` | script d'installation de Helm (lab 12) |
| `get.helm.sh` | binaire Helm (lab 12) |
| `kubernetes-sigs.github.io`, `ghcr.io` | chart et image Headlamp (lab 12) |

Les autres scripts du formateur sont dans `formateur/` : grille de progression (`progression.py`), démo Argo CD (jour 3), démo kubeadm (non prévue au programme, conservée pour référence), contenu des slides « D'où vient un cluster ».
