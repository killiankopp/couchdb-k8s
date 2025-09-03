# Guide de Déploiement CouchDB

Ce guide détaille le processus de déploiement de CouchDB sur Kubernetes avec ArgoCD et Helm.

## 🎯 Objectifs

- Déploiement sécurisé de CouchDB
- Gestion des secrets avec Sealed Secrets
- Automatisation avec ArgoCD
- Politiques de sécurité robustes
- Monitoring et observabilité

## 📋 Prérequis

### Infrastructure

- **Cluster Kubernetes** : Version 1.19 ou supérieure
- **Storage Class** : Pour le stockage persistant
- **Load Balancer** : Pour l'exposition externe (optionnel)
- **Ingress Controller** : Pour le routage HTTP (optionnel)

### Outils

- **kubectl** : Configuré pour accéder au cluster
- **Helm** : Version 3.x
- **ArgoCD** : Installé et configuré
- **Sealed Secrets Controller** : Pour la gestion des secrets

### Permissions

- Accès en lecture/écriture au cluster Kubernetes
- Permissions pour créer des namespaces
- Accès à ArgoCD pour la gestion des applications

## 🚀 Déploiement Étape par Étape

### 1. Préparation de l'Environnement

```bash
# Vérifier l'accès au cluster
kubectl cluster-info

# Vérifier les namespaces
kubectl get namespaces

# Vérifier les storage classes
kubectl get storageclass
```

### 2. Installation des Prérequis

#### ArgoCD

```bash
# Créer le namespace ArgoCD
kubectl create namespace argocd

# Installer ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que tous les pods soient prêts
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Récupérer le mot de passe admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### Sealed Secrets

```bash
# Installer le controller Sealed Secrets
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

# Vérifier l'installation
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

### 3. Configuration des Secrets

#### Génération des Secrets

```bash
# Aller dans le répertoire du projet
cd couchdb-k8s

# Générer les secrets scellés
./scripts/generate-secrets.sh
```

#### Vérification des Secrets

```bash
# Vérifier que le fichier sealed-secrets.yaml a été créé
ls -la secrets/sealed-secrets.yaml

# Vérifier le contenu (doit être chiffré)
cat secrets/sealed-secrets.yaml
```

### 4. Déploiement avec ArgoCD

#### Méthode Automatique

```bash
# Utiliser le script de déploiement
./scripts/deploy.sh
```

#### Méthode Manuelle

```bash
# Créer le namespace
kubectl apply -f argocd/namespace.yaml

# Appliquer les politiques de sécurité
kubectl apply -f argocd/rbac.yaml
kubectl apply -f argocd/network-policy.yaml

# Appliquer les secrets scellés
kubectl apply -f secrets/sealed-secrets.yaml

# Déployer l'application ArgoCD
kubectl apply -f argocd/application.yaml
```

### 5. Vérification du Déploiement

#### Vérification ArgoCD

```bash
# Vérifier le statut de l'application
kubectl get application couchdb -n argocd

# Voir les détails de l'application
kubectl describe application couchdb -n argocd
```

#### Vérification CouchDB

```bash
# Vérifier les pods
kubectl get pods -n couchdb

# Vérifier les services
kubectl get services -n couchdb

# Vérifier les PVCs
kubectl get pvc -n couchdb

# Vérifier les logs
kubectl logs -n couchdb deployment/couchdb -f
```

### 6. Test de Connexion

```bash
# Port-forward pour tester localement
kubectl port-forward -n couchdb svc/couchdb 5984:5984

# Tester la connexion
curl http://localhost:5984/_up

# Tester l'authentification
curl -X GET http://localhost:5984/_all_dbs -u admin:password
```

## 🔧 Configuration Avancée

### Personnalisation des Valeurs

Modifiez le fichier `helm/couchdb/values.yaml` pour adapter la configuration :

```yaml
# Exemple de personnalisation
replicaCount: 3
persistence:
  size: 50Gi
  storageClass: "fast-ssd"
resources:
  limits:
    memory: 4Gi
    cpu: 2000m
  requests:
    memory: 2Gi
    cpu: 1000m
```

### Configuration de l'Ingress

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: couchdb.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: couchdb-tls
      hosts:
        - couchdb.example.com
```

### Configuration du Monitoring

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
```

## 🔐 Sécurité

### Politiques de Sécurité

Le déploiement inclut plusieurs couches de sécurité :

1. **RBAC** : Contrôle d'accès basé sur les rôles
2. **Network Policies** : Isolation réseau
3. **Pod Security Policies** : Contraintes de sécurité
4. **Security Context** : Exécution non-privilégiée

### Rotation des Secrets

```bash
# Générer de nouveaux secrets
./scripts/generate-secrets.sh

# Redémarrer CouchDB pour appliquer les nouveaux secrets
kubectl rollout restart deployment/couchdb -n couchdb
```

### Audit de Sécurité

```bash
# Vérifier les politiques de sécurité
kubectl get networkpolicies -n couchdb
kubectl get podsecuritypolicies
kubectl get securitycontextconstraints

# Vérifier les permissions
kubectl auth can-i create pods --as=system:serviceaccount:couchdb:couchdb-sa
```

## 📊 Monitoring et Observabilité

### Métriques

CouchDB expose des métriques sur le port 9100 :

```bash
# Port-forward pour accéder aux métriques
kubectl port-forward -n couchdb svc/couchdb 9100:9100

# Voir les métriques
curl http://localhost:9100/metrics
```

### Logs

```bash
# Logs de l'application
kubectl logs -n couchdb deployment/couchdb -f

# Logs avec timestamps
kubectl logs -n couchdb deployment/couchdb --timestamps=true

# Logs des 100 dernières lignes
kubectl logs -n couchdb deployment/couchdb --tail=100
```

### Health Checks

```bash
# Vérifier la santé de CouchDB
kubectl exec -n couchdb deployment/couchdb -- curl -f http://localhost:5984/_up

# Vérifier les probes
kubectl describe pod -n couchdb -l app.kubernetes.io/name=couchdb
```

## 🔄 Maintenance

### Mise à Jour

```bash
# Mettre à jour l'image CouchDB
kubectl set image deployment/couchdb couchdb=couchdb:3.3.3 -n couchdb

# Vérifier le rollout
kubectl rollout status deployment/couchdb -n couchdb
```

### Sauvegarde

```bash
# Créer une sauvegarde
./scripts/backup.sh

# Sauvegarder avec un nom personnalisé
./scripts/backup.sh -d /path/to/backups
```

### Restauration

```bash
# Extraire la sauvegarde
tar -xzf backups/couchdb-backup-20231201_120000.tar.gz

# Restaurer
cd couchdb-backup-20231201_120000
./restore.sh
```

## 🐛 Dépannage

### Problèmes Courants

#### Pod en CrashLoopBackOff

```bash
# Vérifier les logs
kubectl logs -n couchdb deployment/couchdb

# Vérifier les événements
kubectl get events -n couchdb --sort-by='.lastTimestamp'

# Vérifier la configuration
kubectl describe pod -n couchdb -l app.kubernetes.io/name=couchdb
```

#### Problème de Stockage

```bash
# Vérifier les PVCs
kubectl get pvc -n couchdb

# Vérifier les PVs
kubectl get pv

# Vérifier les storage classes
kubectl get storageclass
```

#### Problème de Réseau

```bash
# Vérifier les services
kubectl get svc -n couchdb

# Vérifier les endpoints
kubectl get endpoints -n couchdb

# Tester la connectivité
kubectl exec -n couchdb deployment/couchdb -- curl -f http://localhost:5984/_up
```

### Commandes de Diagnostic

```bash
# État général du cluster
kubectl get nodes
kubectl get pods --all-namespaces

# État de CouchDB
kubectl get all -n couchdb

# Configuration ArgoCD
kubectl get application -n argocd
kubectl describe application couchdb -n argocd

# Secrets
kubectl get secrets -n couchdb
kubectl get sealedsecrets -n couchdb
```

## 📚 Ressources Supplémentaires

- [Documentation CouchDB](https://docs.couchdb.org/)
- [Documentation ArgoCD](https://argo-cd.readthedocs.io/)
- [Documentation Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Documentation Helm](https://helm.sh/docs/)
- [Documentation Kubernetes](https://kubernetes.io/docs/)

## 🆘 Support

En cas de problème :

1. Vérifier les logs et événements
2. Consulter la documentation
3. Créer une issue sur GitHub
4. Contacter l'équipe de support
