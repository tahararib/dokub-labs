# Démo formateur — GitOps avec Argo CD (jour 3, facultative, 15 min)

**Quand** : jour 3, après le lab 13 et le slide « Démonstration · Argo CD », vers 16 h 15. À ne pas faire si l'incident 3 et l'évaluation risquent d'être écourtés.
**Pourquoi** : le lab 13 montre que l'application se reconstruit depuis des fichiers. La démonstration montre l'étape suivante : un agent dans le cluster qui applique ces fichiers en continu, et corrige ce qui a été fait à la main.
**Ce n'est pas un lab** : Argo CD demande environ 1 Go de mémoire de plus par poste, et un dépôt Git avec droits de push par participant.

## Matériel

- Le poste du formateur, cluster kind « dokub » dans l'état de fin du lab 13 : `dokub lab check 13` vert, Secret `postgres-cred` recréé.
- `formateur/demo-argocd.sh` ; un onglet de terminal partagé, un navigateur pour l'interface.
- Pour l'étape « commit » seulement : un clone du dépôt avec droits de push (variable `DEPOT`, défaut `~/dokub-labs`). Sans droits de push, sauter l'étape et la raconter.

Le dépôt `tahararib/dokub-labs` est public : Argo CD le lit sans identifiants. Pour un autre dépôt, passer `DEPOT_URL=…`.

## Avant la séance (5 min)

```bash
bash formateur/demo-argocd.sh installer      # Argo CD, branche stable, apply côté serveur
bash formateur/demo-argocd.sh ouvrir         # dans un onglet dédié : https://localhost:8443
```

Se connecter une fois avec `admin` et le mot de passe affiché, pour vérifier l'accès. Laisser l'onglet du port-forward ouvert.

## En séance

| Temps | Commande | Ce qu'on dit |
|---|---|---|
| 0:00 | (interface vide) | Argo CD est installé dans le namespace `argocd`. Il n'a reçu aucune commande : il attend qu'on lui confie un dépôt. |
| 0:01 | `bash demo-argocd.sh application` | Lire l'objet `Application` affiché : un dépôt, un dossier (`labs/lab13`), une destination. Deux réglages : `selfHeal` corrige les écarts ; `ignoreDifferences` laisse `replicas` à l'HPA (lab 9). `prune: false` : le Secret n'est pas dans Git (D9), il ne doit pas être supprimé. |
| 0:03 | (interface) | L'arbre des objets : Deployment, ReplicaSets, pods, Services, Gateway, HPA, NetworkPolicies. Tout est **Synced** et **Healthy** : le cluster correspond au dépôt. |
| 0:05 | `bash demo-argocd.sh ecart` | Un collègue supprime un Service à la main. L'application passe **OutOfSync**, puis le Service revient, sans commande. C'est la boucle de réconciliation du jour 1, appliquée à Git. |
| 0:08 | `bash demo-argocd.sh commit` | Changer de version, c'est changer une ligne dans Git (`newTag` du lab 13). Le commit part, Argo CD le lit, le rollout démarre : readiness et preStop du jour 2 font le reste. Montrer la révision Git affichée dans l'interface. |
| 0:12 | `bash demo-argocd.sh commit` | Le retour arrière est un second commit, pas un `rollout undo` : le fichier et le cluster ne divergent plus (lab 7). |
| 0:14 | `bash demo-argocd.sh etat` | Synthèse : Git fait foi, l'agent applique, personne n'a besoin de droits d'écriture sur le cluster. |

Fin : `bash demo-argocd.sh effacer`. L'application est retirée sans toucher à taskboard, puis Argo CD est désinstallé.

## Ce qui peut surprendre

- **L'écart n'est pas corrigé tout de suite** : la comparaison suit les événements du cluster, en général en quelques secondes. Le script force un `refresh` au bout d'une minute.
- **Le commit n'est pas pris en compte** : Argo CD relit le dépôt toutes les 3 minutes ; le script force la relecture avec l'annotation `argocd.argoproj.io/refresh`.
- **L'application reste OutOfSync sur le Deployment** : vérifier que `ignoreDifferences` est bien présent ; sans lui, Argo CD et l'HPA se disputent `replicas`.
- **Health « Progressing » prolongé** : la Gateway attend son adresse de cloud-provider-kind ; vérifier que `cloud-provider-kind` tourne (`docker ps`).

## Questions fréquentes

- **« Argo CD ou Flux ? »** Deux projets CNCF gradués, même principe. Argo CD a une interface riche et un modèle d'applications ; Flux est plus modulaire, piloté par des objets et la ligne de commande.
- **« Et les Secrets ? »** Jamais en clair dans Git : Sealed Secrets ou SOPS (un Secret chiffré versionné), ou External Secrets Operator (une référence à un coffre). C'est la dette D9.
- **« Et la CI ? »** Elle construit l'image, la signe, et écrit l'empreinte dans le dépôt de déploiement. Argo CD ne construit rien : il applique.
