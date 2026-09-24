# Contrato de integración

## API

Puerto interno esperado: `8080`

Rutas públicas:

- `GET /health` -> `200` y JSON, sin consultar PostgreSQL
- `GET /ready` -> `200` cuando PostgreSQL acepta consultas; `503` si no está disponible
- `GET /reservas` -> `200` y arreglo JSON
- `GET /reservas?fecha=YYYY-MM-DD` -> `200` y solo elementos de esa fecha
- `GET /reservas/{id}` -> `200`; `404` si no existe

Rutas protegidas con el rol `restaurant-writer`:

- `POST /reservas` -> `201` con el recurso creado e `id`
- `PUT /reservas/{id}` -> `200`; `400` inválido; `404` inexistente
- `DELETE /reservas/{id}` -> `204`; `404` inexistente

Sin token válido, las rutas protegidas deben responder `401`. Con token válido pero sin `restaurant-writer`, deben responder `403`

Entidad usada por las pruebas:

```json
{
  "id": 1,
  "nombre": "Cliente de prueba",
  "fecha": "2026-10-01",
  "cantidadPersonas": 2
}
```

Los campos obligatorios deben validar al menos: `nombre` no vacío, `fecha` válida/no vacía y `cantidadPersonas > 0`

## Variables que la API recibe en Kubernetes

Hay dos estilos para facilitar la integración con .NET:

- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `ConnectionStrings__DefaultConnection`
- `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `KEYCLOAK_CLIENT_ID`, `KEYCLOAK_REQUIRED_ROLE`
- `Keycloak__Authority`, `Keycloak__Audience`, `Keycloak__RequiredRole`, `Keycloak__RequireHttpsMetadata`

La API solo necesita consumir un conjunto coherente de esos valores







## Keycloak

Kubernetes crea automáticamente:

- realm: `restaurant`
- client público: `restaurant-api`
- direct access grants habilitado para pruebas k6
- rol: `restaurant-writer`
- usuario writer con ese rol
- usuario reader sin ese rol
- audience mapper para que el access token incluya `restaurant-api`

Los nombres de usuario y contraseñas reales se leen desde un `Secret` generado por Kustomize a partir de `k8s/overlays/local/secrets.env`, que no se versiona






## Docker Compose

Para ejecutar el mismo k6 dentro de la red de Compose, el servicio principal debe conservar o adaptar estos nombres:

- API: `api:8080`
- Keycloak: `auth:8080`
- PostgreSQL: el nombre que use la API/Keycloak, normalmente `bd:5432`

El Docker Compose debe declarar healthchecks para API, PostgreSQL y Keycloak. El archivo `tests/k6/docker-compose.k6.yml` espera que `api` y `auth` tengan healthcheck y usa `depends_on` con `condition: service_healthy`

El realm/client/roles/usuarios de prueba de Docker deben coincidir con las variables de `tests/k6/docker-env-snippet.example`
