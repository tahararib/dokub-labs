# Démo formateur — installer Kubernetes avec kubeadm (jour 1, facultative, 15 min)

**Quand** : jour 1, juste après le lab 1 (avant la pause), ou en fin de jour 1 si le lab 1 a débordé.
**Pourquoi** : le lab 1 crée un vrai Kubernetes, mais kind cache la préparation des machines. L'objectif de la fiche GKN commence par « Installer, utiliser et déployer Kubernetes » : on montre une fois ce que kind fait à notre place.
**Ce n'est pas un lab** : les postes (4 CPU) ne peuvent pas porter 2 ou 3 VM par participant, et le temps est réservé aux modules 3 à 5.

## Matériel

- Une VM Linux jetable : Ubuntu 24.04, 2 vCPU, 4 Go de RAM, 20 Go, accès Internet (VM cloud du formateur, quelques centimes l'heure).
- `demo-kubeadm.sh` copié sur la VM ; une session SSH dans le partage d'écran.
- Facultatif : une seconde VM préparée de la même façon, pour montrer `kubeadm join`.

## La veille (5 min)

```bash
sudo bash demo-kubeadm.sh verifier
sudo bash demo-kubeadm.sh preparer      # containerd 2, kubeadm 1.37, images du control plane
```

Contrôler que `preparer` se termine par « VM prête pour init ». En cas d'échec de la vérification containerd 2 : le paquet containerd.io du dépôt Docker a changé de version, adapter puis relancer.

## En séance

| Temps | Commande | Ce qu'on dit |
|---|---|---|
| 0:00 | `sudo bash demo-kubeadm.sh verifier` | Les prérequis d'un nœud : 2 CPU et 2 Go, cgroup v2 (obligatoire depuis la 1.35), swap, ports, identités uniques. Dans kind, tout cela est hérité de WSL2. |
| 0:03 | (montrer `preparer` dans le script, sans le relancer) | Trois gestes par machine : noyau (br_netfilter, ip_forward), runtime containerd **2** (exigé depuis Kubernetes 1.36), paquets kubeadm/kubelet/kubectl **bloqués** (`apt-mark hold`). |
| 0:05 | `sudo bash demo-kubeadm.sh init` | kubeadm génère les certificats, écrit les pods statiques, démarre etcd et l'API. Faire lire la fin de la sortie : la commande `kubeadm join`. Le nœud est **NotReady**, coredns **Pending** : il manque le réseau des pods. |
| 0:08 | `sudo bash demo-kubeadm.sh reseau` | Le CNI est un choix d'architecture (kind : kindnet ; production : Calico, Cilium). Le nœud passe Ready. Retrait de la taint : on n'a qu'un nœud. |
| 0:11 | `sudo bash demo-kubeadm.sh visite` | Les mêmes manifestes que dans `dokub-control-plane`. Les certificats expirent après un an. `kubeadm upgrade plan` : une version mineure à la fois, trois par an. |
| 0:14 | `sudo bash demo-kubeadm.sh rejoindre` | Un worker rejoint avec un jeton. En production : trois control planes, un répartiteur devant l'API, des sauvegardes etcd. Le service managé fait tout cela à votre place. |

Fin : `sudo bash demo-kubeadm.sh effacer`, puis supprimer la VM.

## Questions fréquentes

- **« Pourquoi pas ça en lab ? »** Trois machines par personne, 1 h 30 de préparation système : c'est une formation d'administration (CKA), pas « les essentiels ».
- **« k3s, c'est du vrai Kubernetes ? »** Oui : une distribution certifiée, allégée (un binaire, base intégrée). k3d est à k3s ce que kind est à kubeadm.
- **« Et k2d ? »** Un traducteur API Kubernetes → Docker de Portainer, pour l'IoT ; ce n'est pas Kubernetes, et le projet est archivé depuis juin 2025.
