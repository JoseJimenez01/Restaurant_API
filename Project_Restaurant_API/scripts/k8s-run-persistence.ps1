$ErrorActionPreference = "Stop"
$marker = "persist-" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$date = (Get-Date).ToUniversalTime().AddDays(10).ToString("yyyy-MM-dd")

kubectl -n restaurant-api create configmap k6-scripts `
  --from-file=integration.js=tests/k6/integration.js `
  --from-file=persistence-create.js=tests/k6/persistence-create.js `
  --from-file=persistence-verify.js=tests/k6/persistence-verify.js `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n restaurant-api create configmap k6-persistence-config `
  --from-literal=PERSISTENCE_MARKER=$marker `
  --from-literal=PERSISTENCE_DATE=$date `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job k6-persistence-create -n restaurant-api --ignore-not-found
kubectl apply -f k8s/tests/k6-persistence-create-job.yaml
kubectl wait -n restaurant-api --for=condition=complete job/k6-persistence-create --timeout=180s
if ($LASTEXITCODE -ne 0) {
    kubectl logs -n restaurant-api job/k6-persistence-create
    exit 1
}
kubectl logs -n restaurant-api job/k6-persistence-create

# Reinicia solo el pod de PostgreSQL. El PVC permanece.
kubectl delete pod -n restaurant-api -l app=postgres
Start-Sleep -Seconds 5
kubectl wait -n restaurant-api --for=condition=ready pod -l app=postgres --timeout=180s
kubectl wait -n restaurant-api --for=condition=ready pod -l app=keycloak --timeout=240s
kubectl wait -n restaurant-api --for=condition=ready pod -l app=restaurant-api --timeout=180s

kubectl delete job k6-persistence-verify -n restaurant-api --ignore-not-found
kubectl apply -f k8s/tests/k6-persistence-verify-job.yaml
kubectl wait -n restaurant-api --for=condition=complete job/k6-persistence-verify --timeout=180s
$waitCode = $LASTEXITCODE
kubectl logs -n restaurant-api job/k6-persistence-verify
exit $waitCode
