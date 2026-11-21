# Slides du jour 1 — « Du conteneur au pod : la pile d'exécution » (8 slides, avant le lab 1)

Contenu validé le 21/11/2026, à intégrer aux slides HTML du J1 (modèle MG708).
Commandes reprises dans le carnet J1 : lab 1, étape 9 facultative (« deux étages »).

## 1. La pile en un schéma

```
docker (CLI) ──REST /var/run/docker.sock──▶ dockerd ──gRPC /run/containerd/containerd.sock──▶ containerd
kubelet ──────CRI (gRPC)──────────────────────────────────────────────────────────────────▶ containerd
containerd ──▶ containerd-shim-runc-v2 ──▶ runc ──▶ processus (namespaces + cgroups)
```

Message : Docker et Kubernetes arrivent au même endroit, containerd, par deux portes différentes.

## 2. Qui fait quoi

| Composant | Rôle |
|---|---|
| docker (CLI) | client : envoie des requêtes à dockerd |
| dockerd | construction d'images, réseaux et volumes Docker, Compose, API Docker |
| containerd | images, couches (snapshots), cycle de vie des conteneurs ; API gRPC ; espaces de noms (`moby`, `k8s.io`) |
| shim | un par conteneur : le garde vivant si containerd redémarre, collecte le code de sortie |
| runc | crée le conteneur (namespaces, cgroups, montages) selon la spécification OCI, puis se retire |

## 3. OCI : des normes, pas un produit

- Open Container Initiative (2015), trois spécifications :
  - **image-spec** : le format d'une image (manifeste, couches, configuration) ;
  - **runtime-spec** : comment exécuter un conteneur (le `config.json` que lit runc) ;
  - **distribution-spec** : l'API d'un registre.
- Conséquence : une image construite par `docker build` tourne sous containerd, CRI-O, Podman ; elle se range dans Docker Hub, GHCR, Harbor, le registre local du lab 1.

## 4. CRI : le contrat entre le kubelet et le runtime

- Interface gRPC définie par Kubernetes (depuis la 1.5).
- Deux services : **RuntimeService** (RunPodSandbox, CreateContainer, StartContainer, StopPodSandbox…) et **ImageService** (PullImage, ListImages…).
- Implémentations : containerd (plugin CRI intégré), CRI-O.
- `crictl` est un client du CRI : il voit exactement ce que voit le kubelet.
- Pourquoi : Kubernetes ne dépend d'aucun runtime ; le runtime évolue sans toucher au kubelet.

## 5. Pourquoi tout ça : l'histoire en 5 dates

| Date | Événement |
|---|---|
| 2013 | Docker : un seul démon fait tout |
| 2015 | création de l'OCI ; runc extrait de Docker |
| 2016-2017 | containerd extrait de Docker, confié à la CNCF ; Kubernetes définit le CRI |
| 2020-2022 | dockershim (l'adaptateur Docker du kubelet) déprécié, puis retiré en 1.24 |
| aujourd'hui | Docker construit les images ; containerd ou CRI-O les exécutent dans les clusters. Docker Engine utilise lui-même containerd, y compris pour ranger ses images. Qui veut garder Docker Engine comme runtime Kubernetes utilise cri-dockerd. |

Message : « Kubernetes a abandonné Docker » est faux. Il a abandonné un adaptateur ; les images Docker n'ont pas changé.

## 6. Le pod vu par le runtime

- Chaque pod = une **sandbox** (conteneur `pause`) qui porte les namespaces partagés, dont le réseau (une adresse IP par pod).
- Les conteneurs de l'application rejoignent la sandbox.
- `crictl pods` liste les sandboxes ; `crictl ps` les conteneurs.

## 7. Sur votre poste : deux étages

```
Windows ─ WSL2 Ubuntu ─ dockerd + containerd (espace « moby »)
                          ├─ conteneur dokub-control-plane ─ containerd (espace « k8s.io ») ─ pods système
                          ├─ conteneur dokub-worker        ─ containerd ─ pods taskboard
                          └─ conteneur dokub-worker2       ─ containerd ─ pods taskboard
```

Limite rappelée : tous les étages partagent le noyau de WSL2 (cf. node-exporter, lab 8).

## 8. Les commandes pour le voir

```bash
# poste
ps -o pid,ppid,cmd -C dockerd,containerd
docker info --format '{{.DefaultRuntime}}'
sudo ctr namespaces ls
sudo ctr -n moby containers ls
# nœud
kubectl get nodes -o wide                       # CONTAINER-RUNTIME
docker exec dokub-worker ctr namespaces ls
docker exec dokub-worker crictl pods
docker exec dokub-worker ctr -n k8s.io containers ls | grep -c pause
```

---

# Slide complémentaire — « Que contient etcd ? » (module 2, après l'architecture)

- Clés : `/registry/<type>/<namespace>/<nom>` (lab 1, étape 10).
- Valeurs : binaires (protobuf) depuis Kubernetes 1.6 ; l'outil `auger` (projet etcd) les décode en YAML.
- Seul l'API server écrit dans etcd ; on lit les objets par l'API, qui contrôle les droits.
- Les Secrets y sont en clair sans chiffrement au repos (lab 5, étape 4 facultative) ; une sauvegarde d'etcd est un document sensible.

# Mention k9s (slide « outils autour de kubectl », J1)

- k9s : interface en terminal, temps réel ; Headlamp : interface web (lab 12) ; kubectl reste la référence.
- Installation facultative au lab 2 (étape 8), fiche en annexe du carnet J1.
