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

## Répartition du travail (décidée le 21/11/2026)

| Préinstallé sur le master | Fait par les participants |
|---|---|
| Windows Terminal, VS Code, WSL2, Ubuntu 24.04 | installer kubectl et kind (lab 1) |
| Docker CE, git, curl, jq, yq, socat | créer le cluster (lab 1) |
| images postgres, kindest/node, cloud-provider-kind, registry:3, taskboard 1.0/2.0/3.0 | démarrer cloud-provider-kind et un registre local, installer metrics-server, étiqueter et pousser les images taskboard (lab 1) |
| dépôt `~/dokub-labs`, commande `dokub` | installer Helm (lab 12) |

`dokub` ne remplace aucun geste du carnet : `lab check` vérifie, `lab start` remet un participant bloqué en selle.

## Préparer le master

Scripts dans `master/` :

| Script | Rôle |
|---|---|
| `install-windows-dokub.ps1` | partie Windows : WSL2, Ubuntu 24.04, `.wslconfig`, Windows Terminal et VS Code (étape facultative) |
| `install-wsl2-dokub.sh` | partie Ubuntu : Docker CE, outils de base, images, dépôt, images taskboard ; validation finale |
| `nettoyage-master.sh` | remet un master déjà utilisé dans l'état « avant formation » |
| `inventaire-master.ps1` | inventaire Windows en lecture seule |

## Accès depuis Windows (vérifié sur le master le 20/11/2026)

| Mode | Depuis Ubuntu | Depuis le navigateur Windows |
|---|---|---|
| NodePort publié (`localhost:8080`) | oui | oui |
| `kubectl port-forward --address 0.0.0.0` | oui | oui (`localhost:<port>`) |
| Adresse LoadBalancer / Gateway (`172.18.x.x`) | oui | non : relais `socat` vers un port localhost |
