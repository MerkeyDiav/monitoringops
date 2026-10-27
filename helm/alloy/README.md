# Grafana Alloy — Documentation

## 1. Objectif

Grafana Alloy est l'agent de collecte des logs Kubernetes utilisé dans le projet `monitoringops`.

Son rôle est de découvrir les pods Kubernetes, de lire leurs fichiers de logs sur les nœuds et de transmettre ces logs à Loki.

Cette configuration utilise le chart Helm officiel `grafana/alloy`. Alloy est déployé sous la forme d'un DaemonSet afin qu'une instance de l'agent puisse fonctionner sur chaque nœud Kubernetes concerné.

**État actuel : configuration préparée, déploiement non effectué.**

Loki n'étant pas encore installé et accessible, Alloy ne doit pas être déployé en production ni considéré comme opérationnel à ce stade.

## 2. Architecture logique

```text
Kubernetes / K3s
       |
       v
Découverte des pods Kubernetes
       |
       v
Grafana Alloy (DaemonSet)
       |
       v
Lecture des fichiers /var/log/pods/
       |
       v
Ajout des labels Kubernetes
       |
       v
Envoi HTTP vers l'API d'ingestion Loki
       |
       v
Loki
       |
       v
Consultation des logs dans Grafana
```

### Responsabilités

- **Kubernetes** : fournit les métadonnées des pods et exécute Alloy.
- **Grafana Alloy** : découvre les pods, lit les fichiers et transmet les logs.
- **Loki** : reçoit, indexe selon son modèle de labels et stocke les logs.
- **Grafana** : permet de rechercher et d'explorer les logs via Loki.

Alloy ne remplace ni Loki ni Grafana. Il s'agit d'un agent de collecte et de transfert.

## 3. Organisation des fichiers

Les fichiers Alloy sont conservés dans le dépôt Git :

```text
monitoringops/
└── helm/
    └── alloy/
        ├── README.md
        ├── values-dev.yaml
        └── values-prod.yaml
```

### `values-dev.yaml`

Contient les paramètres du chart Helm destinés au laboratoire de développement.

### `values-prod.yaml`

Contient les paramètres destinés à la production. Les paramètres de production doivent être vérifiés indépendamment avant déploiement ; ils ne doivent pas être supposés identiques à ceux du laboratoire.

### `README.md`

Documente l'architecture, les paramètres, les prérequis, les procédures de validation et les opérations de maintenance.

## 4. Méthode de déploiement

Le workflow du projet est le suivant :

1. Modifier les fichiers localement dans VS Code.
2. Vérifier les changements avec Git.
3. Créer un commit.
4. Pousser les changements sur GitHub.
5. Récupérer les changements sur le bastion avec `git pull`.
6. Valider le rendu Helm et la configuration Alloy.
7. Déployer via la procédure automatisée retenue.
8. Vérifier les pods, les logs Alloy et la réception dans Loki.

Les fichiers ne doivent pas être modifiés directement dans le dépôt du bastion. Les changements doivent passer par le dépôt Git afin de conserver une source de vérité versionnée.

## 5. Paramètres Helm

### Type de contrôleur

La configuration utilise :

```yaml
controller:
  type: daemonset
```

Un DaemonSet permet d'exécuter une instance d'Alloy sur chaque nœud éligible. Il est adapté à la collecte des fichiers de logs locaux aux nœuds.

### Tolérance du nœud de contrôle

La configuration contient une tolérance pour :

```yaml
- key: "node-role.kubernetes.io/control-plane"
  operator: "Exists"
  effect: "NoSchedule"
```

Elle permet au pod Alloy d'être planifié sur un nœud de contrôle qui possède la taint correspondante. Les autres contraintes de planification et les éventuelles taints supplémentaires doivent également être prises en compte.

### Reporting

```yaml
alloy:
  enableReporting: false
```

Le reporting Alloy est désactivé dans cette configuration.

### Montage des logs

```yaml
alloy:
  mounts:
    varlog: true
```

Ce paramètre demande au chart de monter le répertoire `/var/log` de l'hôte dans le conteneur Alloy.

Le montage est indispensable à la lecture des fichiers de logs locaux. Il ne garantit toutefois pas, à lui seul, que les fichiers seront accessibles : les chemins, les permissions et les contraintes du système doivent également être vérifiés.

## 6. Configuration Alloy

### 6.1 Journalisation interne

```alloy
logging {
  level  = "info"
  format = "logfmt"
}
```

Cette configuration définit le niveau de journalisation interne d'Alloy à `info` et le format des messages à `logfmt`.

Ces logs permettent de diagnostiquer les erreurs de configuration, de découverte, de lecture des fichiers et d'envoi vers Loki.

### 6.2 Découverte Kubernetes

```alloy
discovery.kubernetes "pods" {
  role = "pod"
}
```

Le composant découvre les pods Kubernetes et expose leurs métadonnées sous forme de cibles.

Ces métadonnées servent notamment à déterminer :

- le namespace ;
- le nom du pod ;
- le nom du conteneur ;
- le nœud sur lequel le pod est exécuté ;
- l'UID du pod.

La découverte nécessite des permissions Kubernetes adaptées. Le chart Helm génère les ressources RBAC utilisées par Alloy ; leur contenu doit être contrôlé avant le déploiement.

### 6.3 Relabellisation

```alloy
discovery.relabel "pod_logs" {
  targets = discovery.kubernetes.pods.targets
}
```

Le composant `discovery.relabel` transforme les métadonnées découvertes en labels utilisables par les composants suivants.

La configuration ajoute les labels suivants :

| Label | Valeur |
|---|---|
| `namespace` | Namespace Kubernetes du pod |
| `pod` | Nom du pod |
| `container` | Nom du conteneur |
| `node` | Nom du nœud Kubernetes |

Ces labels facilitent les recherches et les filtres dans Grafana.

Il faut éviter d'ajouter des labels à cardinalité élevée sans besoin opérationnel précis. Par exemple, les UID uniques ne doivent généralement pas devenir des labels Loki permanents.

### 6.4 Construction du chemin des fichiers

La règle actuelle utilise les métadonnées suivantes :

```alloy
rule {
  source_labels = [
    "__meta_kubernetes_namespace",
    "__meta_kubernetes_pod_name",
    "__meta_kubernetes_pod_uid"
  ]
  separator     = "_"
  target_label  = "__path__"
  replacement   = "/var/log/pods/$1/*/*.log"
}
```

Les chemins observés sur le nœud K3s suivent cette structure :

```text
/var/log/pods/<namespace>_<pod>_<uid>/<container>/<numero>.log
```

Exemple :

```text
/var/log/pods/default_redis-master-5c644fc869-rgk9p_b90e43e1-a601-4edd-b7bb-b902fe01ccc5/redis-master/0.log
```

La règle concatène le namespace, le nom du pod et son UID avec `_`. La substitution `$1` correspond à la valeur concaténée capturée par la règle de relabellisation. Le motif `*/*.log` cible ensuite les répertoires de conteneurs et les fichiers de logs.

Cette règle doit être validée avec la version d'Alloy utilisée et avec des chemins réels avant le déploiement. Il faut également vérifier que les fichiers ciblés sont accessibles depuis le conteneur Alloy.

### 6.5 Lecture des fichiers

```alloy
loki.source.file "pod_logs" {
  targets    = discovery.relabel.pod_logs.output
  forward_to = [loki.write.local.receiver]
}
```

`loki.source.file` lit les fichiers identifiés par la cible `__path__` et transmet les entrées de logs au composant d'écriture Loki.

Les vérifications nécessaires comprennent :

- l'existence des fichiers ciblés ;
- les permissions de lecture ;
- la gestion des fichiers renouvelés ou supprimés ;
- l'absence de doublons ou de trous de collecte lors des redémarrages ;
- les performances en cas d'augmentation du nombre de fichiers.

### 6.6 Envoi vers Loki

```alloy
loki.write "local" {
  endpoint {
    url = "http://172.31.35.92:3100/loki/api/v1/push"
  }
}
```

Cette configuration utilise l'adresse interne prévue pour le point d'ingestion Loki.

L'adresse doit rester cohérente avec l'emplacement réel du service. Si Loki est déployé derrière un service Kubernetes ou un équilibreur de charge, l'URL devra être adaptée.

**Important : Loki n'est pas encore installé.** Le fait que cette URL figure dans le fichier ne signifie pas que l'endpoint est opérationnel. Alloy ne pourra transmettre les logs qu'une fois Loki installé, prêt et accessible depuis les nœuds concernés.

En production, il faudra également définir les exigences d'authentification, de chiffrement TLS, de filtrage réseau et de gestion des secrets.

## 7. Prérequis au déploiement

Avant d'installer Alloy, vérifier les points suivants :

- [ ] Le cluster K3s est accessible et ses nœuds sont `Ready`.
- [ ] La version du chart Helm est explicitement définie.
- [ ] Le montage de `/var/log` apparaît dans le rendu Helm.
- [ ] Le `ServiceAccount`, le `ClusterRole` et le `ClusterRoleBinding` sont générés.
- [ ] Les droits `get`, `list` et `watch` sur les ressources nécessaires sont présents.
- [ ] La configuration Alloy est valide selon la version utilisée.
- [ ] Les chemins de logs correspondent à la structure du nœud.
- [ ] Les permissions permettent de lire les fichiers.
- [ ] Loki est installé, prêt et joignable depuis le cluster.
- [ ] La rétention et le stockage Loki sont configurés indépendamment.
- [ ] La configuration de production a été revue séparément de celle du laboratoire.

## 8. Validation Helm

Le rendu Helm permet de vérifier les ressources Kubernetes générées par le chart.

Exemple de commande :

```bash
helm template alloy-dev grafana/alloy \
  --namespace observability \
  --version 1.14.3 \
  --values helm/alloy/values-dev.yaml \
  > /tmp/alloy-rendered.yaml
```

Le résultat doit être examiné pour confirmer notamment :

- le type `DaemonSet` ;
- le montage `/var/log` ;
- les ressources RBAC ;
- le ConfigMap contenant la configuration Alloy ;
- les références aux composants de découverte, de lecture et d'écriture.

Un rendu Helm réussi ne valide pas automatiquement la syntaxe interne de la configuration Alloy. Une validation Alloy distincte est nécessaire avant le déploiement.

## 9. Contrôles après déploiement

Une fois Loki installé et Alloy déployé, vérifier :

1. Que les pods Alloy sont présents sur les nœuds attendus.
2. Que les pods Alloy sont en état `Running` et prêts.
3. Que les logs Alloy ne contiennent pas d'erreurs de configuration ou de permission.
4. Que la découverte Kubernetes renvoie des cibles.
5. Que les fichiers de logs sont effectivement lus.
6. Que l'endpoint Loki est accessible.
7. Que les logs apparaissent dans Loki.
8. Que les labels `namespace`, `pod`, `container` et `node` sont disponibles dans les requêtes Grafana.
9. Que les redémarrages d'Alloy n'entraînent pas de pertes ou de duplications inacceptables.

## 10. Dépannage

### Aucun pod Alloy

Vérifier le namespace, le DaemonSet, les événements Kubernetes, les taints et les tolérances.

### Erreurs de découverte Kubernetes

Vérifier le `ServiceAccount`, le `ClusterRoleBinding` et les permissions sur les pods et leurs métadonnées.

### Aucun fichier collecté

Vérifier le montage `/var/log`, la valeur de `__path__`, la présence de fichiers et les permissions.

### Erreurs de connexion à Loki

Vérifier l'adresse configurée, le port, le routage, les règles réseau et l'état du service Loki. Un code HTTP `000` avec `curl` indique que la connexion n'a pas abouti ; il ne prouve pas à lui seul la cause.

### Aucun log visible dans Grafana

Vérifier successivement la lecture des fichiers par Alloy, l'envoi vers Loki, l'absence d'erreurs d'ingestion et les labels utilisés dans la requête Grafana.

## 11. Sécurité et exploitation

Pour un environnement de production :

- limiter les permissions Kubernetes au strict nécessaire ;
- ne pas stocker de secrets dans Git ;
- préférer HTTPS/TLS lorsque l'architecture le permet ;
- définir des règles réseau explicites entre Alloy et Loki ;
- surveiller la santé et les erreurs d'Alloy ;
- documenter les versions des charts et des images ;
- définir les ressources CPU et mémoire après mesure ;
- vérifier la capacité de stockage et la politique de rétention de Loki ;
- tester les redémarrages, les indisponibilités et les mises à jour.

## 12. État du projet et prochaines étapes

État connu :

- [x] Le chart Helm Alloy a été rendu avec la version `1.14.3`.
- [x] Le montage `/var/log` apparaît dans le rendu.
- [x] Les ressources RBAC sont générées.
- [x] La structure réelle des fichiers de logs K3s a été observée.
- [ ] Valider la configuration Alloy avec l'outil de validation approprié.
- [ ] Préparer et déployer Loki.
- [ ] Vérifier l'accessibilité de Loki depuis le cluster.
- [ ] Déployer Alloy via le workflow versionné.
- [ ] Confirmer la réception des logs dans Loki.
- [ ] Préparer une configuration de production séparée et validée.

**Ordre recommandé :** valider la configuration Alloy, installer et tester Loki, déployer Alloy, puis confirmer la collecte de bout en bout avant d'envisager la production.
