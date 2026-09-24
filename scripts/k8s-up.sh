#!/usr/bin/env sh
set -eu

cluster="restaurant-api"
secret_file="k8s/overlays/local/secrets.env"
secret_example="k8s/overlays/local/secrets.env.example"

# Si no existe secrets.env se crea desde la plantilla. La plantilla trae valores de
# desarrollo validos; se recomienda cambiarlos para ambientes compartidos.
if [ ! -f "$secret_file" ]; then
  cp "$secret_example" "$secret_file"
  echo "Se creo $secret_file desde el ejemplo."
fi

docker build -t restaurant-api:local .
if ! kind get clusters | grep -qx "$cluster"; then
  kind create cluster --name "$cluster" --config k8s/overlays/local/kind-config.yaml
fi
kind load docker-image restaurant-api:local --name "$cluster"
kubectl apply -k k8s/overlays/local
kubectl wait -n restaurant-api --for=condition=available deployment/postgres --timeout=180s
kubectl wait -n restaurant-api --for=condition=available deployment/keycloak --timeout=300s
kubectl wait -n restaurant-api --for=condition=available deployment/restaurant-api --timeout=180s
kubectl get pods -n restaurant-api
echo "API disponible en http://localhost:8081"
