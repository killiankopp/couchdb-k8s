# CouchDB Kubernetes Deployment

Ce projet fournit un déploiement sécurisé de CouchDB sur Kubernetes en utilisant Helm et ArgoCD, avec une gestion avancée des secrets et des politiques de sécurité.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     ArgoCD      │    │   Sealed        │    │    CouchDB      │
│   Application   │───▶│   Secrets       │───▶│   Deployment    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitOps Flow   │    │  Secret Mgmt    │    │  Security       │
│                 │    │                 │    │  Policies       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📁 Structure du Projet

```
couchdb-k8s/
├── helm/couchdb/                 # Chart Helm pour CouchDB
│   ├── Chart.yaml               # Métadonnées du chart
│   ├── values.yaml              # Valeurs par défaut
│   └── templates/               # Templates Kubernetes
│       ├── deployment.yaml      # Déploiement CouchDB
│       ├── service.yaml         # Service Kubernetes
│       ├── secret.yaml          # Gestion des secrets
│       ├── configmap.yaml       # Configuration CouchDB
│       ├── pvc.yaml             # Stockage persistant
│       ├── networkpolicy.yaml   # Politiques réseau
│       └── _helpers.tpl         # Fonctions helper
├── argocd/                      # Configuration ArgoCD
│   ├── application.yaml         # Application ArgoCD
│   ├── namespace.yaml           # Namespace dédié
│   ├── rbac.yaml               # Contrôle d'accès
│   └── network-policy.yaml     # Politiques réseau
├── secrets/                     # Gestion des secrets
│   ├── sealed-secrets.yaml     # Secrets scellés
│   └── README.md               # Documentation secrets
├── security/                    # Politiques de sécurité
│   ├── pod-security-policy.yaml
│   ├── security-context-constraints.yaml
│   ├── kyverno-policies.yaml
│   └── opa-gatekeeper-policies.yaml
└── README.md                    # Cette documentation
```

## 🌐 Accès

CouchDB sera accessible via : **https://couchdb.kk.karned.bzh**

## 🚀 Déploiement Rapide

### Prérequis

- Cluster Kubernetes (v1.19+)
- ArgoCD installé et configuré
- Sealed Secrets Controller installé
- Helm 3.x
- kubectl configuré
- **Ingress Controller** (nginx-ingress)
- **cert-manager** (pour les certificats SSL)
- **Configuration DNS** pour `couchdb.kk.karned.bzh`

### 1. Installation des prérequis

```bash
# Installer Sealed Secrets Controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

# Installer ArgoCD (si pas déjà fait)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Installer nginx-ingress (si pas déjà fait)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# Installer cert-manager (si pas déjà fait)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

### 2. Configuration DNS

Configurez un enregistrement DNS pour `couchdb.kk.karned.bzh` pointant vers votre cluster Kubernetes.

Voir [docs/dns-configuration.md](docs/dns-configuration.md) pour plus de détails.

### 3. Configuration des secrets

```bash
# Générer les secrets scellés
cd secrets/
./generate-secrets.sh
```

### 4. Déploiement via ArgoCD

```bash
# Appliquer l'application ArgoCD
kubectl apply -f argocd/application.yaml
```

### 5. Vérification de l'accès

```bash
# Vérifier que l'Ingress est créé
kubectl get ingress -n kk

# Tester l'accès
curl -I https://couchdb.kk.karned.bzh/_up
```

## 🔐 Sécurité

### Mesures de sécurité implémentées

- **Secrets Management** : Utilisation de Sealed Secrets pour un stockage sécurisé
- **RBAC** : Contrôle d'accès basé sur les rôles
- **Network Policies** : Isolation réseau restrictive
- **Pod Security Policies** : Contraintes de sécurité au niveau pod
- **Security Context** : Exécution en mode non-privilégié
- **Resource Limits** : Limitation des ressources CPU/mémoire
- **Read-only Root Filesystem** : Système de fichiers en lecture seule

### Politiques de sécurité

Le projet inclut des politiques pour plusieurs outils :

- **Kyverno** : Politiques de validation et mutation
- **OPA Gatekeeper** : Contraintes de sécurité
- **Pod Security Standards** : Standards de sécurité Kubernetes

## ⚙️ Configuration

### Variables principales

| Variable | Description | Valeur par défaut |
|----------|-------------|-------------------|
| `replicaCount` | Nombre de répliques | `1` |
| `persistence.enabled` | Stockage persistant | `true` |
| `persistence.size` | Taille du stockage | `10Gi` |
| `couchdb.config.security.requireValidUser` | Authentification requise | `true` |
| `networkPolicy.enabled` | Politiques réseau | `true` |
| `resources.limits.memory` | Limite mémoire | `1Gi` |
| `resources.limits.cpu` | Limite CPU | `1000m` |

### Personnalisation

Modifiez le fichier `helm/couchdb/values.yaml` pour adapter la configuration à vos besoins.

## 📊 Monitoring

### Health Checks

- **Liveness Probe** : Vérification de santé du conteneur
- **Readiness Probe** : Vérification de disponibilité
- **Startup Probe** : Vérification de démarrage

### Métriques

CouchDB expose des métriques sur le port 9100 (si activé) :
- Nombre de documents
- Taille de la base de données
- Requêtes par seconde
- Temps de réponse

## 🔧 Maintenance

### Mise à jour

```bash
# Mettre à jour via ArgoCD
kubectl patch application couchdb -n argocd --type merge -p '{"spec":{"source":{"targetRevision":"v1.2.3"}}}'
```

### Sauvegarde

```bash
# Sauvegarder les données
kubectl exec -n couchdb deployment/couchdb -- couchdb-backup /opt/couchdb/data
```

### Restauration

```bash
# Restaurer les données
kubectl exec -n couchdb deployment/couchdb -- couchdb-restore /opt/couchdb/data/backup
```

## 🐛 Dépannage

### Problèmes courants

1. **Pod en CrashLoopBackOff**
   ```bash
   kubectl logs -n couchdb deployment/couchdb
   kubectl describe pod -n couchdb -l app.kubernetes.io/name=couchdb
   ```

2. **Problème de permissions**
   ```bash
   kubectl auth can-i create pods --as=system:serviceaccount:couchdb:couchdb-sa
   ```

3. **Problème de réseau**
   ```bash
   kubectl get networkpolicies -n couchdb
   kubectl describe networkpolicy couchdb-network-policy -n couchdb
   ```

### Logs

```bash
# Logs de l'application
kubectl logs -n couchdb deployment/couchdb -f

# Logs ArgoCD
kubectl logs -n argocd deployment/argocd-application-controller -f
```

## 🤝 Contribution

1. Fork le projet
2. Créer une branche feature (`git checkout -b feature/amazing-feature`)
3. Commit les changements (`git commit -m 'Add amazing feature'`)
4. Push vers la branche (`git push origin feature/amazing-feature`)
5. Ouvrir une Pull Request

## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

## 🆘 Support

- **Issues** : [GitHub Issues](https://github.com/votre-username/couchdb-k8s/issues)
- **Documentation** : [Wiki](https://github.com/votre-username/couchdb-k8s/wiki)
- **Discussions** : [GitHub Discussions](https://github.com/votre-username/couchdb-k8s/discussions)

## 🙏 Remerciements

- [Apache CouchDB](https://couchdb.apache.org/) - Base de données NoSQL
- [Helm](https://helm.sh/) - Gestionnaire de packages Kubernetes
- [ArgoCD](https://argoproj.github.io/cd/) - GitOps continu
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) - Gestion sécurisée des secrets