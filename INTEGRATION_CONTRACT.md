# Contrato de integración

Documento de coordinación entre la API (servicio ASP.NET Core 8), las pruebas k6 y los
despliegues (Docker Compose y Kubernetes). Describe lo que cada lado debe cumplir para que
el sistema opere end-to-end.

## API

Puerto interno esperado: `8080`

Rutas públicas:

- `GET /health` -> `200` y JSON, sin consultar PostgreSQL
- `GET /ready` -> `200` cuando PostgreSQL acepta consultas; `503` si no está disponible
- `GET /reservas` -> `200` y arreglo JSON
- `GET /reservas?fecha=YYYY-MM-DD` -> `200` y solo elementos de esa fecha
- `GET /reservas/{id}` -> `200`; `404` si no existe

Rutas protegidas con el rol `api-writer`:

- `POST /reservas` -> `201` con el recurso creado e `id`
- `PUT /reservas/{id}` -> `200`; `400` inválido; `404` inexistente
- `DELETE /reservas/{id}` -> `204`; `404` inexistente

Sin token válido, las rutas protegidas deben responder `401`. Con token válido pero sin
`api-writer`, deben responder `403`.

Entidad usada por las pruebas:

```json
{
  "id": 1,
  "nombreCliente": "Cliente de prueba",
  "fecha": "2026-10-01",
  "hora": "19:30:00",
  "cantidadPersonas": 2
}
```

Los campos obligatorios deben validar al menos: `nombreCliente` no vacío (máx. 120 chars),
`fecha` válida/no vacía, `hora` válida/no vacía y `cantidadPersonas` entre 1 y 50. Las
lecturas son públicas; solo `POST`/`PUT`/`DELETE` exigen token con el rol.

## Variables que la API recibe del entorno

La API lee estos nombres exactos (ver `Program.cs`):

- PostgreSQL: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`,
  `POSTGRES_PASSWORD` (alternativa: `ConnectionStrings__Default`)
- Keycloak: `KEYCLOAK_AUTHORITY` (URL del realm que se usa para el discovery OIDC),
  `KEYCLOAK_REQUIRED_ROLE` (rol exigido para escribir), opcionalmente `KEYCLOAK_AUDIENCE`
  y `KEYCLOAK_VALID_ISSUER`

En Kubernetes los mismos valores se inyectan desde el `ConfigMap` `restaurant-config`
(`POSTGRES_HOST`, `POSTGRES_PORT`, `APP_DB_NAME`->`POSTGRES_DB`, `KEYCLOAK_URL`,
`KEYCLOAK_REALM`, `KEYCLOAK_REQUIRED_ROLE`) y el `Secret` `restaurant-secrets`
(`POSTGRES_USER`, `POSTGRES_PASSWORD`, credenciales de prueba k6).

## Keycloak

- Compose: el realm `restaurant` se importa de `keycloak/realm-export.json` al arrancar.
- Kubernetes: un `initContainer` renderiza el realm desde `k8s/base/keycloak/realm-template.json`
  (usando env del `ConfigMap` y del `Secret`) y Keycloak lo importa con `--import-realm`.

En ambos casos se crea:

- realm: `restaurant`
- client público: `restaurant-api` (Direct Access Grants habilitado para el flujo
  `grant_type=password` de las pruebas)
- rol de realm: `api-writer`
- usuario `escritor` con el rol `api-writer`
- usuario `lector` sin ese rol

Los nombres/contraseñas de escritor y lector se leen de secretos por entorno
(`K6_WRITER_USERNAME`/`K6_WRITER_PASSWORD`, `K6_READER_USERNAME`/`K6_READER_PASSWORD`);
en Compose vienen del `.env` y en Kubernetes del `Secret` generado por Kustomize.

## Docker Compose

Para ejecutar k6 dentro de la red de Compose (`scripts/run-compose-integration.sh` y
`scripts/run-compose-persistence.sh`):

- API: `api:8080`
- Keycloak: `auth:8080` (host `:8081`)
- PostgreSQL: `bd:5432`

Los tres servicios declaran healthcheck y `tests/k6/docker-compose.k6.yml` usa
`depends_on` con `condition: service_healthy` sobre `api` y `auth`.

## Kubernetes

- `scripts/k8s-up.sh`: crea el clúster `kind`, carga la imagen, aplica el overlay local y
  espera a que los tres Deployments estén disponibles.
- `scripts/k8s-run-integration.sh` y `scripts/k8s-run-persistence.sh`: ejecutan las
  pruebas k6 como Jobs dentro del clúster (el API se alcanza por `http://restaurant-api:8080`
  y Keycloak por `http://keycloak:8080`).
- `scripts/k8s-down.sh`: elimina el clúster `kind`.
- Correspondencias Compose → Kubernetes: volumen `postgres_data` → `PersistentVolumeClaim`
  `postgres-data`; healthchecks → `startupProbe`/`livenessProbe`/`readinessProbe`; variables
  de entorno → `ConfigMap`/`Secret`; los tres servicios → Deployments + Services; el realm
  importado en Compose → el realm renderizado por `initContainer` e importado por Keycloak.