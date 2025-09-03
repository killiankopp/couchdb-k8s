#!/bin/bash

# Script de test pour CouchDB
# Ce script teste la connectivité et la configuration de CouchDB

set -e

# Configuration
NAMESPACE="kk"
SERVICE_NAME="couchdb"
SERVICE_PORT="5984"

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

# Vérifier que le pod CouchDB est en cours d'exécution
check_pod_status() {
    log_step "Vérification du statut du pod CouchDB"
    
    if ! kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=couchdb &> /dev/null; then
        log_error "Aucun pod CouchDB trouvé dans le namespace ${NAMESPACE}"
        exit 1
    fi
    
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=couchdb -o jsonpath='{.items[0].metadata.name}')
    POD_STATUS=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}')
    
    if [ "$POD_STATUS" != "Running" ]; then
        log_error "Le pod CouchDB n'est pas en cours d'exécution (statut: ${POD_STATUS})"
        log_info "Logs du pod:"
        kubectl logs -n ${NAMESPACE} ${POD_NAME} --tail=20
        exit 1
    fi
    
    log_info "Pod CouchDB en cours d'exécution: ${POD_NAME}"
}

# Tester la connectivité interne
test_internal_connectivity() {
    log_step "Test de connectivité interne"
    
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=couchdb -o jsonpath='{.items[0].metadata.name}')
    
    # Tester l'endpoint de santé
    if kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -f http://localhost:${SERVICE_PORT}/_up &> /dev/null; then
        log_info "✅ Endpoint de santé accessible"
    else
        log_error "❌ Endpoint de santé non accessible"
        return 1
    fi
    
    # Tester l'endpoint principal
    if kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -f http://localhost:${SERVICE_PORT}/ &> /dev/null; then
        log_info "✅ Endpoint principal accessible"
    else
        log_error "❌ Endpoint principal non accessible"
        return 1
    fi
}

# Tester la connectivité via le service
test_service_connectivity() {
    log_step "Test de connectivité via le service"
    
    SERVICE_IP=$(kubectl get service ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
    
    if [ -z "$SERVICE_IP" ]; then
        log_error "Service ${SERVICE_NAME} non trouvé dans le namespace ${NAMESPACE}"
        return 1
    fi
    
    log_info "Service IP: ${SERVICE_IP}"
    
    # Port-forward pour tester
    kubectl port-forward -n ${NAMESPACE} svc/${SERVICE_NAME} 8080:${SERVICE_PORT} &
    PORT_FORWARD_PID=$!
    
    # Attendre que le port-forward soit prêt
    sleep 3
    
    # Tester la connectivité
    if curl -f http://localhost:8080/_up &> /dev/null; then
        log_info "✅ Service accessible via port-forward"
    else
        log_error "❌ Service non accessible via port-forward"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        return 1
    fi
    
    # Nettoyer le port-forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
}

# Tester l'accès public (si Ingress est configuré)
test_public_access() {
    log_step "Test de l'accès public"
    
    if kubectl get ingress -n ${NAMESPACE} &> /dev/null; then
        INGRESS_HOST=$(kubectl get ingress -n ${NAMESPACE} -o jsonpath='{.items[0].spec.rules[0].host}')
        
        if [ -n "$INGRESS_HOST" ]; then
            log_info "Ingress configuré pour: ${INGRESS_HOST}"
            
            if curl -f -I https://${INGRESS_HOST}/_up &> /dev/null; then
                log_info "✅ Accès public accessible"
            else
                log_warn "⚠️ Accès public non accessible (peut être normal si DNS non configuré)"
            fi
        else
            log_warn "⚠️ Aucun host Ingress configuré"
        fi
    else
        log_warn "⚠️ Aucun Ingress configuré"
    fi
}

# Vérifier la configuration
check_configuration() {
    log_step "Vérification de la configuration"
    
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=couchdb -o jsonpath='{.items[0].metadata.name}')
    
    # Vérifier les variables d'environnement
    log_info "Variables d'environnement:"
    kubectl exec -n ${NAMESPACE} ${POD_NAME} -- env | grep -E "(COUCHDB|NODENAME|ERL)" || true
    
    # Vérifier les fichiers de configuration
    log_info "Fichiers de configuration:"
    kubectl exec -n ${NAMESPACE} ${POD_NAME} -- ls -la /opt/couchdb/etc/local.d/ || true
    
    # Vérifier les logs récents
    log_info "Logs récents:"
    kubectl logs -n ${NAMESPACE} ${POD_NAME} --tail=10
}

# Afficher les informations de connexion
show_connection_info() {
    log_step "Informations de connexion"
    
    SERVICE_IP=$(kubectl get service ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
    INGRESS_HOST=$(kubectl get ingress -n ${NAMESPACE} -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    
    echo ""
    log_info "CouchDB est accessible via :"
    echo "  - URL interne: http://${SERVICE_IP}:${SERVICE_PORT}"
    echo "  - URL FQDN: http://${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local:${SERVICE_PORT}"
    if [ -n "$INGRESS_HOST" ]; then
        echo "  - URL publique: https://${INGRESS_HOST}"
    fi
    echo ""
    
    # Afficher les commandes utiles
    echo "Commandes utiles :"
    echo "  - Port-forward: kubectl port-forward -n ${NAMESPACE} svc/${SERVICE_NAME} 8080:${SERVICE_PORT}"
    echo "  - Logs: kubectl logs -n ${NAMESPACE} deployment/${SERVICE_NAME} -f"
    echo "  - Shell: kubectl exec -it -n ${NAMESPACE} deployment/${SERVICE_NAME} -- /bin/bash"
    echo ""
}

# Fonction principale
main() {
    log_info "Test de CouchDB"
    
    # Vérifications préalables
    check_kubectl
    check_pod_status
    
    # Tests de connectivité
    test_internal_connectivity
    test_service_connectivity
    test_public_access
    
    # Vérification de la configuration
    check_configuration
    
    # Informations de connexion
    show_connection_info
    
    log_info "🎉 Tests terminés avec succès !"
}

# Exécution
main "$@"
