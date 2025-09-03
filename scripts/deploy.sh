#!/bin/bash

# Script de déploiement CouchDB avec ArgoCD
# Ce script automatise le déploiement complet de CouchDB

set -e

# Configuration
NAMESPACE="kk"
ARGOCD_NAMESPACE="argocd"
APP_NAME="couchdb-kk"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Vérifier que kubectl est configuré
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl n'est pas configuré ou le cluster n'est pas accessible."
        exit 1
    fi
    log_info "kubectl est configuré et le cluster est accessible"
}

# Vérifier que ArgoCD est installé
check_argocd() {
    if ! kubectl get deployment argocd-server -n ${ARGOCD_NAMESPACE} &> /dev/null; then
        log_error "ArgoCD n'est pas installé dans le namespace ${ARGOCD_NAMESPACE}"
        echo "Installez ArgoCD avec:"
        echo "kubectl create namespace ${ARGOCD_NAMESPACE}"
        echo "kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
        exit 1
    fi
    log_info "ArgoCD est installé et accessible"
}

# Vérifier que Sealed Secrets est installé
check_sealed_secrets() {
    if ! kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        log_error "Sealed Secrets Controller n'est pas installé"
        echo "Installez-le avec:"
        echo "kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml"
        exit 1
    fi
    log_info "Sealed Secrets Controller est installé"
}

# Créer le namespace
create_namespace() {
    log_step "Création du namespace ${NAMESPACE}"
    kubectl apply -f argocd/namespace.yaml
    log_info "Namespace ${NAMESPACE} créé"
}

# Appliquer les politiques de sécurité
apply_security_policies() {
    log_step "Application des politiques de sécurité"
    
    # RBAC
    kubectl apply -f argocd/rbac.yaml
    log_info "RBAC appliqué"
    
    # Network Policies
    kubectl apply -f argocd/network-policy.yaml
    log_info "Network Policies appliquées"
    
    # Pod Security Policies (si supporté)
    if kubectl api-resources | grep -q "podsecuritypolicies"; then
        kubectl apply -f security/pod-security-policy.yaml
        log_info "Pod Security Policies appliquées"
    else
        log_warn "Pod Security Policies non supportées sur ce cluster"
    fi
}

# Appliquer les secrets scellés
apply_sealed_secrets() {
    log_step "Application des secrets scellés"
    
    if [ ! -f "secrets/sealed-secrets.yaml" ]; then
        log_error "Fichier secrets/sealed-secrets.yaml non trouvé"
        echo "Générez d'abord les secrets avec: ./scripts/generate-secrets.sh"
        exit 1
    fi
    
    kubectl apply -f secrets/sealed-secrets.yaml
    log_info "Secrets scellés appliqués"
}

# Déployer l'application ArgoCD
deploy_argocd_app() {
    log_step "Déploiement de l'application ArgoCD"
    
    # Mettre à jour l'URL du repository dans le fichier application.yaml
    REPO_URL=$(git remote get-url origin 2>/dev/null || echo "https://github.com/votre-username/couchdb-k8s.git")
    sed -i.bak "s|https://github.com/votre-username/couchdb-k8s.git|${REPO_URL}|g" argocd/application.yaml
    
    kubectl apply -f argocd/application.yaml
    log_info "Application ArgoCD déployée"
    
    # Restaurer le fichier original
    mv argocd/application.yaml.bak argocd/application.yaml 2>/dev/null || true
}

# Attendre que l'application soit synchronisée
wait_for_sync() {
    log_step "Attente de la synchronisation ArgoCD"
    
    log_info "Vérification du statut de l'application..."
    kubectl wait --for=condition=Synced application/${APP_NAME} -n ${ARGOCD_NAMESPACE} --timeout=300s
    
    log_info "Application synchronisée avec succès"
}

# Vérifier le déploiement
verify_deployment() {
    log_step "Vérification du déploiement"
    
    # Vérifier que le pod est en cours d'exécution
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=couchdb -n ${NAMESPACE} --timeout=300s
    
    # Vérifier que le service est créé
    kubectl get service couchdb -n ${NAMESPACE}
    
    # Vérifier que le PVC est créé
    kubectl get pvc -n ${NAMESPACE}
    
    log_info "Déploiement vérifié avec succès"
}

# Afficher les informations de connexion
show_connection_info() {
    log_step "Informations de connexion"
    
    # Obtenir l'IP du service
    SERVICE_IP=$(kubectl get service couchdb -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
    SERVICE_PORT=$(kubectl get service couchdb -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].port}')
    
    echo ""
    log_info "CouchDB est déployé et accessible :"
    echo "  - URL interne: http://${SERVICE_IP}:${SERVICE_PORT}"
    echo "  - URL FQDN: http://couchdb.${NAMESPACE}.svc.cluster.local:${SERVICE_PORT}"
    echo ""
    
    # Afficher les commandes utiles
    echo "Commandes utiles :"
    echo "  - Voir les logs: kubectl logs -n ${NAMESPACE} deployment/couchdb -f"
    echo "  - Accéder au pod: kubectl exec -it -n ${NAMESPACE} deployment/couchdb -- /bin/bash"
    echo "  - Voir le statut: kubectl get all -n ${NAMESPACE}"
    echo "  - Interface ArgoCD: kubectl port-forward -n ${ARGOCD_NAMESPACE} svc/argocd-server 8080:443"
    echo ""
}

# Fonction de nettoyage
cleanup() {
    log_warn "Nettoyage en cours..."
    # Restaurer le fichier application.yaml si nécessaire
    if [ -f "argocd/application.yaml.bak" ]; then
        mv argocd/application.yaml.bak argocd/application.yaml
    fi
}

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Afficher cette aide"
    echo "  --skip-secrets Ignorer la vérification des secrets"
    echo "  --skip-sync    Ignorer l'attente de synchronisation"
    echo ""
    echo "Ce script déploie CouchDB sur Kubernetes avec ArgoCD"
}

# Variables par défaut
SKIP_SECRETS=false
SKIP_SYNC=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --skip-secrets)
            SKIP_SECRETS=true
            shift
            ;;
        --skip-sync)
            SKIP_SYNC=true
            shift
            ;;
        *)
            log_error "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Gestion des erreurs
trap cleanup EXIT

# Fonction principale
main() {
    log_info "Déploiement de CouchDB avec ArgoCD"
    
    # Vérifications préalables
    check_kubectl
    check_argocd
    check_sealed_secrets
    
    # Déploiement
    create_namespace
    apply_security_policies
    
    if [ "$SKIP_SECRETS" = false ]; then
        apply_sealed_secrets
    else
        log_warn "Vérification des secrets ignorée"
    fi
    
    deploy_argocd_app
    
    if [ "$SKIP_SYNC" = false ]; then
        wait_for_sync
        verify_deployment
    else
        log_warn "Attente de synchronisation ignorée"
    fi
    
    show_connection_info
    
    log_info "Déploiement terminé avec succès !"
}

# Exécution
main "$@"
