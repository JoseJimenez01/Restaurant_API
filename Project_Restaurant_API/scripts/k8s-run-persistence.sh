#!/usr/bin/env sh
set -eu

marker="persist-$(date +%s)"
date_value="$(date -u -d '+10 days' +%F 2>/dev/null || date -u -v+10d +%F)"

kubectl -n restaurant-api create configmap k6-scripts \
  --from-file=integration.js=tests/k6/integration.js \
  --from-file=persistence-create.js=tests/k6/persistence-create.js \
  --from-file=persistence-verify.js=tests/k6/persistence-verify.js \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n restaurant-api create configmap k6-persistence-config \
  --from-literal=PERSISTENCE_MARKER="$marker" \
  --from-literal=PERSISTENCE_DATE="$date_value" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job k6-persistence-create -n restaurant-api --ignore-not-found
kubectl apply -f k8s/tests/k6-persistence-create-job.yaml
kubectl wait -n restaurant-api --for=condition=complete job/k6-persistence-create --timeout=180s
kubectl logs -n restaurant-api job/k6-persistence-create

kubectl delete pod -n restaurant-api -l app=postgres
sleep 5
kubectl wait -n restaurant-api --for=condition=ready pod -l app=postgres --timeout=180s
kubectl wait -n restaurant-api --for=condition=ready pod -l app=keycloak --timeout=240s
kubectl wait -n restaurant-api --for=condition=ready pod -l app=restaurant-api --timeout=180s

kubectl delete job k6-persistence-verify -n restaurant-api --ignore-not-found
kubectl apply -f k8s/tests/k6-persistence-verify-job.yaml
kubectl wait -n restaurant-api --for=condition=complete job/k6-persistence-verify --timeout=180s
kubectl logs -n restaurant-api job/k6-persistence-verify
