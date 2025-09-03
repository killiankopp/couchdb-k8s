#!/bin/bash

# Script de validation YAML pour les fichiers Kubernetes
# Ce script vérifie la syntaxe YAML de tous les fichiers de configuration

set -e

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

# Vérifier si Python est disponible
check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        log_error "Python n'est pas installé"
        exit 1
    fi
}

# Valider un fichier YAML
validate_yaml() {
    local file="$1"
    log_info "Validation de $file"
    
    if $PYTHON_CMD -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        log_info "✅ $file - YAML valide"
        return 0
    else
        log_error "❌ $file - YAML invalide"
        return 1
    fi
}

# Valider tous les fichiers YAML
validate_all_yaml() {
    local errors=0
    
    # Fichiers ArgoCD
    for file in argocd/*.yaml; do
        if [ -f "$file" ]; then
            validate_yaml "$file" || ((errors++))
        fi
    done
    
    # Fichiers de sécurité
    for file in security/*.yaml; do
        if [ -f "$file" ]; then
            validate_yaml "$file" || ((errors++))
        fi
    done
    
    # Fichiers de secrets
    for file in secrets/*.yaml; do
        if [ -f "$file" ]; then
            validate_yaml "$file" || ((errors++))
        fi
    done
    
    # Templates Helm
    for file in helm/couchdb/templates/*.yaml; do
        if [ -f "$file" ]; then
            validate_yaml "$file" || ((errors++))
        fi
    done
    
    # Fichiers de configuration Helm
    validate_yaml "helm/couchdb/Chart.yaml" || ((errors++))
    validate_yaml "helm/couchdb/values.yaml" || ((errors++))
    
    return $errors
}

# Fonction principale
main() {
    log_info "Validation de la syntaxe YAML"
    
    check_python
    
    if validate_all_yaml; then
        log_info "🎉 Tous les fichiers YAML sont valides !"
        exit 0
    else
        log_error "❌ Certains fichiers YAML contiennent des erreurs"
        exit 1
    fi
}

# Exécution
main "$@"
