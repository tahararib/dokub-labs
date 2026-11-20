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

## Installation sur le master (Ubuntu 24.04 dans WSL2)

Prérequis : `install-wsl2-dokub.sh` exécuté, images taskboard construites
(`cd ~/taskboard && bash dokub/build-images.sh`).

```bash
cd ~
git clone https://github.com/tahararib/dokub-labs.git
sudo ln -sf ~/dokub-labs/bin/dokub /usr/local/bin/dokub
dokub images
dokub cluster up
dokub mesure
```

## Accès depuis Windows (vérifié sur le master le 20/11/2026)

| Mode | Depuis Ubuntu | Depuis le navigateur Windows |
|---|---|---|
| NodePort publié (`localhost:8080`) | oui | oui |
| `kubectl port-forward --address 0.0.0.0` | oui | oui (`localhost:<port>`) |
| Adresse LoadBalancer / Gateway (`172.18.x.x`) | oui | non : relais `socat` vers un port localhost |
