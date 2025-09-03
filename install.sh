helm install couchdb couchdb/couchdb \
  --version 4.6.2 \
  --namespace kk --create-namespace \
  -f values.yaml