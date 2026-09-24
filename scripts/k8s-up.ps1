$ErrorActionPreference = "Stop"
$cluster = "restaurant-api"
$secretFile = "k8s/overlays/local/secrets.env"
$secretExample = "k8s/overlays/local/secrets.env.example"

if (-not (Test-Path $secretFile)) {
    Copy-Item $secretExample $secretFile
    Write-Host "Se creo $secretFile desde el ejemplo. Cambie los valores CAMBIAR_* antes de continuar."
    exit 1
}

if (Select-String -Path $secretFile -Pattern "CAMBIAR_" -Quiet) {
    Write-Host "Edite $secretFile: todavia contiene valores CAMBIAR_*."
    exit 1
}

docker build -t restaurant-api:local .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$clusters = kind get clusters 2>$null
if ($clusters -notcontains $cluster) {
    kind create cluster --name $cluster --config k8s/overlays/local/kind-config.yaml
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

kind load docker-image restaurant-api:local --name $cluster
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

kubectl apply -k k8s/overlays/local
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

kubectl wait -n restaurant-api --for=condition=available deployment/postgres --timeout=180s
kubectl wait -n restaurant-api --for=condition=available deployment/keycloak --timeout=300s
kubectl wait -n restaurant-api --for=condition=available deployment/restaurant-api --timeout=180s
kubectl get pods -n restaurant-api
Write-Host "API disponible en http://localhost:8081"
