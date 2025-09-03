# Configuration DNS pour CouchDB

## URL d'accès

CouchDB sera accessible via l'URL : **https://couchdb.kk.karned.bzh**

## Configuration DNS requise

### Enregistrement DNS

Ajoutez un enregistrement DNS de type **A** ou **CNAME** :

```
Type: A (ou CNAME)
Nom: couchdb.kk
Domaine: karned.bzh
Valeur: [IP de votre cluster Kubernetes ou Load Balancer]
TTL: 300 (5 minutes)
```

### Exemple de configuration

```bash
# Si vous utilisez un Load Balancer externe
couchdb.kk.karned.bzh.    IN    A    203.0.113.10

# Ou si vous utilisez un CNAME vers votre cluster
couchdb.kk.karned.bzh.    IN    CNAME    k8s-cluster.karned.bzh.
```

## Configuration Ingress

L'Ingress est configuré avec :

- **Host** : `couchdb.kk.karned.bzh`
- **TLS** : Certificat Let's Encrypt automatique
- **Redirect** : HTTP vers HTTPS forcé
- **Class** : `nginx`

## Certificats SSL

Le certificat SSL sera généré automatiquement par cert-manager avec Let's Encrypt :

- **Issuer** : `letsencrypt-prod`
- **Secret** : `couchdb-tls`
- **Renouvellement** : Automatique

## Vérification

Une fois déployé, vous pouvez vérifier :

```bash
# Vérifier l'Ingress
kubectl get ingress -n kk

# Vérifier le certificat
kubectl get certificate -n kk

# Tester la connectivité
curl -I https://couchdb.kk.karned.bzh/_up
```

## Sécurité

- **HTTPS obligatoire** : Toutes les connexions HTTP sont redirigées vers HTTPS
- **Certificat valide** : Certificat Let's Encrypt automatiquement renouvelé
- **Network Policies** : Trafic autorisé uniquement depuis ingress-nginx

## Dépannage

### Problème de résolution DNS

```bash
# Vérifier la résolution DNS
nslookup couchdb.kk.karned.bzh

# Vérifier avec dig
dig couchdb.kk.karned.bzh
```

### Problème de certificat

```bash
# Vérifier le statut du certificat
kubectl describe certificate couchdb-tls -n kk

# Vérifier les logs cert-manager
kubectl logs -n cert-manager deployment/cert-manager
```

### Problème d'Ingress

```bash
# Vérifier l'Ingress
kubectl describe ingress couchdb -n kk

# Vérifier les logs nginx-ingress
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```
