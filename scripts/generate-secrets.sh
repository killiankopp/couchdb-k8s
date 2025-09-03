#!/bin/bash

# Script pour générer les secrets scellés pour CouchDB
# Ce script utilise kubeseal pour créer des secrets sécurisés

set -e

# Configuration
NAMESPACE="kk"
SECRET_NAME="couchdb-secrets"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=""
ERLANG_COOKIE=""
DATABASE_PASSWORD=""

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifier que kubeseal est installé
check_kubeseal() {
    if ! command -v kubeseal &> /dev/null; then
        log_error "kubeseal n'est pas installé. Veuillez l'installer d'abord."
        echo "Installation sur macOS: brew install kubeseal"
        echo "Installation sur Linux: wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/kubeseal-0.18.0-linux-amd64.tar.gz"
        exit 1
    fi
}

# Vérifier que le controller Sealed Secrets est installé
check_sealed_secrets_controller() {
    if ! kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        log_error "Le controller Sealed Secrets n'est pas installé."
        echo "Installez-le avec: kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml"
        exit 1
    fi
}

# Générer des mots de passe sécurisés
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Demander les mots de passe à l'utilisateur
get_passwords() {
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo -n "Mot de passe admin (laisser vide pour générer automatiquement): "
        read -s ADMIN_PASSWORD
        echo
        if [ -z "$ADMIN_PASSWORD" ]; then
            ADMIN_PASSWORD=$(generate_password)
            log_info "Mot de passe admin généré automatiquement"
        fi
    fi

    if [ -z "$ERLANG_COOKIE" ]; then
        ERLANG_COOKIE=$(generate_password)
        log_info "Cookie Erlang généré automatiquement"
    fi

    if [ -z "$DATABASE_PASSWORD" ]; then
        DATABASE_PASSWORD=$(generate_password)
        log_info "Mot de passe base de données généré automatiquement"
    fi
}

# Créer le fichier de secret temporaire
create_temp_secret() {
    log_info "Création du fichier de secret temporaire..."
    
    cat > /tmp/couchdb-secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
data:
  admin-username: $(echo -n "${ADMIN_USERNAME}" | base64)
  admin-password: $(echo -n "${ADMIN_PASSWORD}" | base64)
  erlang-cookie: $(echo -n "${ERLANG_COOKIE}" | base64)
  database-password: $(echo -n "${DATABASE_PASSWORD}" | base64)
EOF
}

# Sceller le secret
seal_secret() {
    log_info "Scellement du secret avec kubeseal..."
    
    # Récupérer la clé publique
    kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system > /tmp/public.pem
    
    # Sceller le secret
    kubeseal --format=yaml --cert=/tmp/public.pem < /tmp/couchdb-secrets.yaml > secrets/sealed-secrets.yaml
    
    log_info "Secret scellé créé dans secrets/sealed-secrets.yaml"
}

# Nettoyer les fichiers temporaires
cleanup() {
    log_info "Nettoyage des fichiers temporaires..."
    rm -f /tmp/couchdb-secrets.yaml /tmp/public.pem
}

# Afficher les informations de connexion
show_connection_info() {
    log_info "Informations de connexion CouchDB:"
    echo "  - URL: http://couchdb.${NAMESPACE}.svc.cluster.local:5984"
    echo "  - Admin Username: ${ADMIN_USERNAME}"
    echo "  - Admin Password: ${ADMIN_PASSWORD}"
    echo "  - Database Username: killian"
    echo "  - Database Password: ${DATABASE_PASSWORD}"
    echo ""
    log_warn "IMPORTANT: Sauvegardez ces informations dans un endroit sécurisé !"
}

# Fonction principale
main() {
    log_info "Génération des secrets scellés pour CouchDB"
    
    # Vérifications préalables
    check_kubeseal
    check_sealed_secrets_controller
    
    # Obtenir les mots de passe
    get_passwords
    
    # Créer le secret temporaire
    create_temp_secret
    
    # Sceller le secret
    seal_secret
    
    # Nettoyer
    cleanup
    
    # Afficher les informations
    show_connection_info
    
    log_info "Génération terminée avec succès !"
    log_info "Vous pouvez maintenant commiter le fichier secrets/sealed-secrets.yaml"
}

# Gestion des erreurs
trap cleanup EXIT

# Exécution
main "$@"
