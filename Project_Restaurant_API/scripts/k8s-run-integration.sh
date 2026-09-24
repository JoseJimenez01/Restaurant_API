#!/usr/bin/env sh
set -eu

kubectl -n restaurant-api create configmap k6-scripts \
  --from-file=integration.js=tests/k6/integration.js \
  --from-file=persistence-create.js=tests/k6/persistence-create.js \
  --from-file=persistence-verify.js=tests/k6/persistence-verify.js \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job k6-integration -n restaurant-api --ignore-not-found
kubectl apply -f k8s/tests/k6-integration-job.yaml
kubectl wait -n restaurant-api --for=condition=complete job/k6-integration --timeout=240s
kubectl logs -n restaurant-api job/k6-integration
