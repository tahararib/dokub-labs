# Démo formateur — Une base répliquée avec CloudNativePG (jour 3, 10 min)

**Quand** : jour 3, juste après le lab 11 étape 5 (« deux instances, deux bases »), si le groupe n'a pas le temps de faire l'étape 6 facultative du carnet.
**Pourquoi** : l'étape 5 montre ce que le StatefulSet ne fait pas : ni copie des données, ni instance principale, ni bascule. La démo montre l'outil qui le fait : un opérateur, c'est-à-dire de nouveaux types d'objets (CRD, jour 1) et un contrôleur qui connaît le métier de la base.
**Le déroulé est celui du carnet** (lab 11, étape 6, trois pages) : les participants qui ont le temps la refont eux-mêmes plus tard.

## Matériel

- Le poste du formateur, cluster kind « dokub » en fin de lab 11 étape 5 (`postgres` revenu à 1 instance).
- Deux onglets de terminal partagés, dans `~/labs/lab11` (fichier `base-repliquee.yaml` copié à l'étape 1).
- Accès à `raw.githubusercontent.com` (manifeste) et `ghcr.io` (images de l'opérateur et de PostgreSQL).

## Avant la séance (5 min, facultatif)

Installer l'opérateur à l'avance fait gagner une minute ; créer la base à l'avance fait perdre l'effet « un objet, trois instances ». Si le réseau est lent, créer la base une première fois puis la supprimer (`kubectl delete namespace pg`) : les images restent dans les nœuds.

## En séance

| Temps | Commande (carnet, lab 11 étape 6) | Ce qu'on dit |
|---|---|---|
| 0:00 | `kubectl apply --server-side -f $CNPG` | Installer un opérateur, c'est appliquer des manifestes, comme le reste. `--server-side` : les CRD sont trop grosses pour l'annotation de `kubectl apply` (lab 5). |
| 0:01 | `kubectl api-resources --api-group=postgresql.cnpg.io` | De nouveaux types d'objets : `kubectl get cluster` marche comme `kubectl get pods`. C'est le mécanisme des CRD du jour 1. |
| 0:02 | `cat base-repliquee.yaml` puis `kubectl apply -f base-repliquee.yaml` | Un seul objet. Ni pod, ni StatefulSet, ni Service, ni Secret écrits à la main. |
| 0:03 | `kubectl -n pg get pods -w` | Les instances naissent l'une après l'autre : `initdb` pour la première, `join` pour les suivantes (copie de la première). Pendant le téléchargement : relire le tableau de l'étape 5. |
| 0:05 | `psql` sur `$P`, puis sur `$R` | La réplique a reçu la ligne ; elle refuse d'écrire. Une seule instance écrit. |
| 0:06 | `kubectl -n pg get services` | `base-rw` suit la principale : l'application vise ce Service, jamais un pod. |
| 0:07 | onglet 2 `get cluster base -w` ; onglet 1 `delete pod $P` | La principale disparaît, une réplique est promue, `base-rw` la suit. L'ancienne revient comme réplique. |
| 0:09 | `select x from t` sur la nouvelle principale | La donnée est là. Comparer avec l'étape 5 : là, postgres-1 n'avait rien. |
| 0:10 | `kubectl delete namespace pg` ; `kubectl delete -f $CNPG` | Nettoyer avant le lab 12. |

## Ce qui peut surprendre

- **Les libellés de statut** de `kubectl get cluster -w` pendant la bascule dépendent de la version de l'opérateur ; seuls comptent la colonne PRIMARY et le retour à « Cluster in healthy state ».
- **La nouvelle principale** n'est pas forcément `base-2` : l'opérateur choisit la réplique la plus à jour.
- **`kubectl delete -f $CNPG`** après un nouvel onglet : la variable est vide ; la redéfinir.
- **Mémoire** : trois instances PostgreSQL de plus, environ 300 Mo ; à supprimer avant le lab 12.

## À vérifier au dry run (rien n'a encore tourné sur le master)

Sorties exactes de `api-resources`, `get cluster`, `get services`, statut pendant la bascule, durée de création (téléchargement `ghcr.io`), message d'écriture refusée sur la réplique.
