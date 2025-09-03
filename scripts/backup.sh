#!/bin/bash

# Script de sauvegarde CouchDB
# Ce script crée une sauvegarde complète de CouchDB

set -e

# Configuration
NAMESPACE="kk"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="couchdb-backup-${TIMESTAMP}"

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

# Vérifier que CouchDB est déployé
check_couchdb() {
    if ! kubectl get deployment couchdb -n ${NAMESPACE} &> /dev/null; then
        log_error "CouchDB n'est pas déployé dans le namespace ${NAMESPACE}"
        exit 1
    fi
    log_info "CouchDB est déployé et accessible"
}

# Créer le répertoire de sauvegarde
create_backup_dir() {
    log_step "Création du répertoire de sauvegarde"
    mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}"
    log_info "Répertoire de sauvegarde créé: ${BACKUP_DIR}/${BACKUP_NAME}"
}

# Sauvegarder la configuration
backup_config() {
    log_step "Sauvegarde de la configuration"
    
    # Sauvegarder les ConfigMaps
    kubectl get configmap -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/configmaps.yaml"
    
    # Sauvegarder les Secrets (sans les données sensibles)
    kubectl get secret -n ${NAMESPACE} -o yaml | sed '/data:/,$d' > "${BACKUP_DIR}/${BACKUP_NAME}/secrets-metadata.yaml"
    
    # Sauvegarder les Services
    kubectl get service -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/services.yaml"
    
    # Sauvegarder les PVCs
    kubectl get pvc -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/${BACKUP_NAME}/pvcs.yaml"
    
    log_info "Configuration sauvegardée"
}

# Sauvegarder les données CouchDB
backup_data() {
    log_step "Sauvegarde des données CouchDB"
    
    # Créer un job de sauvegarde
    cat > /tmp/backup-job.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: couchdb-backup-${TIMESTAMP}
  namespace: ${NAMESPACE}
spec:
  template:
    spec:
      containers:
      - name: backup
        image: couchdb:3.3.2
        command:
        - /bin/bash
        - -c
        - |
          set -e
          echo "Début de la sauvegarde..."
          
          # Attendre que CouchDB soit prêt
          until curl -f http://localhost:5984/_up; do
            echo "Attente de CouchDB..."
            sleep 5
          done
          
          # Créer la sauvegarde
          mkdir -p /backup
          cp -r /opt/couchdb/data/* /backup/
          
          # Compresser la sauvegarde
          cd /backup
          tar -czf /backup/couchdb-data-${TIMESTAMP}.tar.gz .
          
          echo "Sauvegarde terminée"
        volumeMounts:
        - name: couchdb-data
          mountPath: /opt/couchdb/data
          readOnly: true
        - name: backup-storage
          mountPath: /backup
      volumes:
      - name: couchdb-data
        persistentVolumeClaim:
          claimName: couchdb
      - name: backup-storage
        emptyDir: {}
      restartPolicy: Never
  backoffLimit: 3
EOF
    
    # Appliquer le job
    kubectl apply -f /tmp/backup-job.yaml
    
    # Attendre la completion du job
    log_info "Attente de la completion du job de sauvegarde..."
    kubectl wait --for=condition=complete job/couchdb-backup-${TIMESTAMP} -n ${NAMESPACE} --timeout=600s
    
    # Copier les données de sauvegarde
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l job-name=couchdb-backup-${TIMESTAMP} -o jsonpath='{.items[0].metadata.name}')
    kubectl cp ${NAMESPACE}/${POD_NAME}:/backup/couchdb-data-${TIMESTAMP}.tar.gz "${BACKUP_DIR}/${BACKUP_NAME}/couchdb-data.tar.gz"
    
    # Nettoyer le job
    kubectl delete job couchdb-backup-${TIMESTAMP} -n ${NAMESPACE}
    rm -f /tmp/backup-job.yaml
    
    log_info "Données CouchDB sauvegardées"
}

# Créer un manifest de restauration
create_restore_manifest() {
    log_step "Création du manifest de restauration"
    
    cat > "${BACKUP_DIR}/${BACKUP_NAME}/restore.sh" << EOF
#!/bin/bash
# Script de restauration CouchDB
# Généré automatiquement le $(date)

set -e

NAMESPACE="${NAMESPACE}"
BACKUP_DIR="${BACKUP_DIR}/${BACKUP_NAME}"

echo "Restauration de CouchDB depuis ${BACKUP_NAME}"

# Vérifier que CouchDB est arrêté
kubectl scale deployment couchdb -n \${NAMESPACE} --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=couchdb -n \${NAMESPACE} --timeout=300s

# Restaurer la configuration
kubectl apply -f \${BACKUP_DIR}/configmaps.yaml
kubectl apply -f \${BACKUP_DIR}/services.yaml
kubectl apply -f \${BACKUP_DIR}/pvcs.yaml

# Redémarrer CouchDB
kubectl scale deployment couchdb -n \${NAMESPACE} --replicas=1
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=couchdb -n \${NAMESPACE} --timeout=300s

# Restaurer les données
POD_NAME=\$(kubectl get pods -n \${NAMESPACE} -l app.kubernetes.io/name=couchdb -o jsonpath='{.items[0].metadata.name}')
kubectl cp \${BACKUP_DIR}/couchdb-data.tar.gz \${NAMESPACE}/\${POD_NAME}:/tmp/couchdb-data.tar.gz

kubectl exec -n \${NAMESPACE} \${POD_NAME} -- /bin/bash -c "
  cd /opt/couchdb/data
  tar -xzf /tmp/couchdb-data.tar.gz
  chown -R couchdb:couchdb /opt/couchdb/data
  rm /tmp/couchdb-data.tar.gz
"

echo "Restauration terminée"
EOF
    
    chmod +x "${BACKUP_DIR}/${BACKUP_NAME}/restore.sh"
    log_info "Manifest de restauration créé"
}

# Créer un fichier de métadonnées
create_metadata() {
    log_step "Création des métadonnées de sauvegarde"
    
    cat > "${BACKUP_DIR}/${BACKUP_NAME}/metadata.yaml" << EOF
backup:
  name: ${BACKUP_NAME}
  timestamp: ${TIMESTAMP}
  date: $(date -Iseconds)
  namespace: ${NAMESPACE}
  version: $(kubectl get deployment couchdb -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}')
  size: $(du -sh "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1)
  files:
    - configmaps.yaml
    - secrets-metadata.yaml
    - services.yaml
    - pvcs.yaml
    - couchdb-data.tar.gz
    - restore.sh
    - metadata.yaml
EOF
    
    log_info "Métadonnées créées"
}

# Compresser la sauvegarde
compress_backup() {
    log_step "Compression de la sauvegarde"
    
    cd "${BACKUP_DIR}"
    tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
    rm -rf "${BACKUP_NAME}"
    
    log_info "Sauvegarde compressée: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
}

# Afficher les informations de sauvegarde
show_backup_info() {
    log_step "Informations de sauvegarde"
    
    BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
    
    echo ""
    log_info "Sauvegarde créée avec succès :"
    echo "  - Nom: ${BACKUP_NAME}"
    echo "  - Taille: ${BACKUP_SIZE}"
    echo "  - Emplacement: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    echo ""
    echo "Pour restaurer cette sauvegarde :"
    echo "  tar -xzf ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    echo "  cd ${BACKUP_NAME}"
    echo "  ./restore.sh"
    echo ""
}

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Afficher cette aide"
    echo "  -d, --dir DIR  Répertoire de sauvegarde (défaut: ./backups)"
    echo "  --no-compress  Ne pas compresser la sauvegarde"
    echo ""
    echo "Ce script crée une sauvegarde complète de CouchDB"
}

# Variables par défaut
NO_COMPRESS=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --no-compress)
            NO_COMPRESS=true
            shift
            ;;
        *)
            log_error "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Fonction principale
main() {
    log_info "Sauvegarde de CouchDB"
    
    # Vérifications préalables
    check_kubectl
    check_couchdb
    
    # Sauvegarde
    create_backup_dir
    backup_config
    backup_data
    create_restore_manifest
    create_metadata
    
    if [ "$NO_COMPRESS" = false ]; then
        compress_backup
    fi
    
    show_backup_info
    
    log_info "Sauvegarde terminée avec succès !"
}

# Exécution
main "$@"
