# Secrets Management

Ce dossier contient la configuration pour la gestion sécurisée des secrets CouchDB.

## Sealed Secrets

Les secrets sont gérés via [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) pour permettre un stockage sécurisé dans Git.

### Prérequis

1. Installer le controller Sealed Secrets dans votre cluster :
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml
```

2. Installer l'outil kubeseal :
```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/kubeseal-0.18.0-linux-amd64.tar.gz
tar xvfz kubeseal-0.18.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Génération des secrets

1. Créer un fichier temporaire avec vos secrets :
```bash
cat <<EOF > /tmp/couchdb-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: couchdb-secrets
  namespace: couchdb
type: Opaque
data:
  admin-username: $(echo -n "admin" | base64)
  admin-password: $(echo -n "votre-mot-de-passe-admin" | base64)
  erlang-cookie: $(echo -n "$(openssl rand -base64 32)" | base64)
  database-password: $(echo -n "votre-mot-de-passe-db" | base64)
EOF
```

2. Sceller le secret :
```bash
kubeseal --format=yaml --cert=public.pem < /tmp/couchdb-secrets.yaml > sealed-secrets.yaml
```

3. Nettoyer le fichier temporaire :
```bash
rm /tmp/couchdb-secrets.yaml
```

### Utilisation

Le fichier `sealed-secrets.yaml` peut être commité en toute sécurité dans Git. Le controller Sealed Secrets déchiffrera automatiquement les secrets lors du déploiement.

## Alternative : External Secrets Operator

Pour une gestion plus avancée des secrets, vous pouvez utiliser [External Secrets Operator](https://external-secrets.io/) avec des providers comme :

- AWS Secrets Manager
- Azure Key Vault
- HashiCorp Vault
- Google Secret Manager

### Configuration External Secrets

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: couchdb
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "couchdb"
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: couchdb-external-secrets
  namespace: couchdb
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: couchdb-secrets
    creationPolicy: Owner
  data:
  - secretKey: admin-username
    remoteRef:
      key: couchdb
      property: admin-username
  - secretKey: admin-password
    remoteRef:
      key: couchdb
      property: admin-password
  - secretKey: erlang-cookie
    remoteRef:
      key: couchdb
      property: erlang-cookie
  - secretKey: database-password
    remoteRef:
      key: couchdb
      property: database-password
```

## Sécurité

- **Ne jamais** commiter de secrets en clair
- Utiliser des mots de passe forts (minimum 32 caractères)
- Roter régulièrement les secrets
- Limiter l'accès aux namespaces contenant les secrets
- Utiliser des Network Policies pour restreindre l'accès réseau
