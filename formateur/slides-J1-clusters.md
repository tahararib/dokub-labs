# Slides du jour 1 — « D'où vient un cluster » (5 slides, après « Créer un cluster »)

Contenu validé le 21/11/2026, à intégrer aux slides HTML du J1 (modèle MG708).
Sources vérifiées : documentation kubeadm (prérequis), blog Kubernetes (cgroup v2 en 1.35, containerd 1.x abandonné en 1.36, swap GA en 1.34), dépôt portainer/k2d (archivé le 8 juin 2025).

## 1. Les familles de clusters

| Famille | Exemples | Qui opère le control plane | Pour quoi |
|---|---|---|---|
| Service managé | AKS, EKS, GKE, OVHcloud, Scaleway | le fournisseur | le cas le plus courant en production |
| kubeadm | Kubernetes du projet, sur VM ou serveurs | vous | sur site, maîtrise complète |
| Distributions | k3s, RKE2, k0s, MicroK8s, OpenShift, Talos | vous, outillé par l'éditeur | sur site, périphérie (edge), support éditeur |
| Clusters locaux | kind, k3d, minikube | votre poste | formation, tests, intégration continue |

Message : tous exposent la même API ; ce qui change, c'est qui fait le travail d'exploitation.

## 2. Ce que fait kind

- kind = des conteneurs Docker qui jouent les machines + kubeadm à l'intérieur : du vrai Kubernetes, mêmes binaires, mêmes pods statiques.
- k3d = la même idée avec k3s. minikube = un nœud, en VM ou en conteneur.
- Ce que kind ne simule pas : le noyau (partagé par tous les nœuds, ici celui de WSL2), la préparation des machines, une vraie panne matérielle, le stockage distribué.
- À ne pas confondre : k2d (Portainer) traduit l'API Kubernetes en commandes Docker ; ce n'est pas Kubernetes (projet archivé en 2025).

## 3. Les prérequis d'un nœud kubeadm

- 2 Go de RAM par machine, 2 CPU pour le control plane.
- Réseau complet entre les nœuds ; noms d'hôte, adresses MAC et product_uuid uniques ; ports 6443, 2379-2380, 10250, 10257, 10259.
- cgroup v2 : depuis la 1.35, le kubelet refuse de démarrer en cgroup v1.
- Runtime : containerd 2 (containerd 1.x abandonné en 1.36) ou CRI-O.
- Swap : le kubelet refuse de démarrer si le swap est actif, sauf réglage explicite (pris en charge en mode limité depuis la 1.34).

## 4. La production, au-delà de l'installation

- 3 control planes (quorum etcd : nombre impair) + un répartiteur devant l'API.
- Sauvegardes etcd testées ; certificats à renouveler (1 an par défaut).
- Choix du réseau (CNI : Calico, Cilium…) et du stockage (CSI).
- Montées de version : 3 versions mineures par an, une à la fois, environ 14 mois de correctifs par version.
- Observabilité, sécurité des accès (RBAC, OIDC), politiques d'admission.

## 5. Comment choisir

| Situation | Choix habituel |
|---|---|
| Équipe applicative, cloud public possible | service managé |
| Données sur site, équipe système | distribution supportée (RKE2, OpenShift) ou kubeadm |
| Sites distants, petites machines | k3s, k0s |
| Poste, CI, formation | kind, k3d |

Mention unique de l'IA (décision du 21/11) : à placer dans une autre slide, pas ici.
Démo facultative associée : `formateur/demo-kubeadm.md`.
