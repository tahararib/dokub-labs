# Démo formateur — Une base répliquée avec CloudNativePG (jour 3, 15 min)

**Quand** : jour 3, juste après le lab 11 étape 5 (« deux instances, deux bases »), si le groupe n'a pas le temps de faire l'étape 6 facultative du carnet.
**Pourquoi** : l'étape 5 montre ce que le StatefulSet ne fait pas : ni copie des données, ni instance principale, ni bascule. La démo montre l'outil qui le fait : un opérateur, c'est-à-dire de nouveaux types d'objets (CRD, jour 1) et un contrôleur qui connaît le métier de la base.
**Le déroulé est celui du carnet** (lab 11, étape 6, quatre pages) : les participants qui ont le temps la refont eux-mêmes plus tard.

## Matériel

- Le poste du formateur, cluster kind « dokub » en fin de lab 11 étape 5 (`postgres` revenu à 1 instance).
- Deux onglets de terminal partagés, dans `~/labs/lab11` (fichiers `base-repliquee.yaml` et `brancher-cnpg.yaml` copiés à l'étape 1), un navigateur sur `localhost:8080`.
- Accès à `raw.githubusercontent.com` (manifeste) et `ghcr.io` (images de l'opérateur et de PostgreSQL).

## Avant la séance (5 min, facultatif)

Installer l'opérateur à l'avance fait gagner une minute ; créer la base à l'avance fait perdre l'effet « un objet, trois instances ». Si le réseau est lent, créer la base une première fois puis la supprimer (`kubectl delete -f base-repliquee.yaml`) : les images restent dans les nœuds.

## En séance

| Temps | Commande (carnet, lab 11 étape 6) | Ce qu'on dit |
|---|---|---|
| 0:00 | `kubectl apply --server-side -f $CNPG` | Installer un opérateur, c'est appliquer des manifestes, comme le reste. `--server-side` : les CRD sont trop grosses pour l'annotation de `kubectl apply` (lab 5). |
| 0:01 | `kubectl api-resources --api-group=postgresql.cnpg.io` | De nouveaux types d'objets : `kubectl get cluster` marche comme `kubectl get pods`. C'est le mécanisme des CRD du jour 1. |
| 0:02 | `cat base-repliquee.yaml` puis `kubectl apply -f base-repliquee.yaml` | Un seul objet. Ni pod, ni StatefulSet, ni Service, ni Secret écrits à la main. |
| 0:03 | `kubectl get pods -l cnpg.io/cluster=base -w` | Les instances naissent l'une après l'autre : `initdb` pour la première, `join` pour les suivantes. Pendant le téléchargement : relire le tableau de l'étape 5. |
| 0:05 | `kubectl get services,secrets -l cnpg.io/cluster=base` | `base-rw` suit la principale, `base-ro` les répliques ; `base-app` porte les identifiants. |
| 0:06 | `cat brancher-cnpg.yaml` puis `kubectl patch … --patch-file` | Changer de base, c'est changer trois variables. L'application vise un Service, jamais un pod. Seules les 3 tâches d'exemple : base neuve, remplie au démarrage. |
| 0:08 | `curl … -d "title=…"` puis la boucle `psql` sur base-1, 2, 3 | Une écriture, par la principale ; trois copies. |
| 0:09 | onglet 2 `get cluster base -w` ; onglet 1 `delete pod $P` | La principale attend d'abord que taskboard ferme ses connexions (`smartShutdownTimeout`, 10 s dans le fichier, 180 s par défaut), puis une réplique est promue et `base-rw` la suit. L'ancienne revient comme réplique. PRIMARY ne change qu'une fois la promotion faite. |
| 0:11 | `curl … -d "title=Après la bascule"` ; recharger la page | L'application écrit toujours. Comparer avec l'étape 5 : là, postgres-1 n'avait rien. |
| 0:12 | `psql -c "insert …"` sur `$P` | L'ancienne principale, devenue réplique, refuse d'écrire. |
| 0:13 | `kubectl rollout undo deployment/taskboard` | Retour à la base du StatefulSet (lab 7). « Tâche à garder » revient. |
| 0:14 | `kubectl delete -f base-repliquee.yaml` ; `kubectl delete -f $CNPG` | Nettoyer avant le lab 12. |

## Ce qui peut surprendre

- **Les libellés de statut** de `kubectl get cluster -w` pendant la bascule dépendent de la version de l'opérateur ; seuls comptent la colonne PRIMARY et le retour à « Cluster in healthy state ».
- **La nouvelle principale** n'est pas forcément `base-2` : l'opérateur choisit la réplique la plus à jour.
- **`kubectl delete -f $CNPG`** après un nouvel onglet : la variable est vide ; la redéfinir.
- **Mémoire** : trois instances PostgreSQL de plus, environ 300 Mo ; à supprimer avant le lab 12.
- **Une requête en erreur pendant la bascule** : les connexions de taskboard vers l'ancienne principale sont coupées ; les suivantes passent.
- **Niveau restricted** : la base est créée dans le namespace `taskboard`, où le lab 5 impose le niveau restricted. Les pods de CloudNativePG sont prévus pour ; si l'admission les refuse (`kubectl get events`), noter le message.

## À vérifier au dry run (rien n'a encore tourné sur le master)

Sorties exactes de `api-resources`, `get cluster`, `get services,secrets`, statut pendant la bascule, durée de création (téléchargement `ghcr.io`), message d'écriture refusée, admission des pods au niveau restricted, création de la table par taskboard sur la base `app`, suppression des PVC avec le `Cluster`.
