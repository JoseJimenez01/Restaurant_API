# Restaurant API — Servicio HTTP (parte de Franco)

Servicio REST de reservas de mesa en **ASP.NET Core 8 (.NET 8)** con persistencia en
**PostgreSQL** y autenticación delegada en **Keycloak** (JWT/OIDC). Este README cubre el
servicio y sus pruebas; el `Dockerfile` y el `docker-compose.yml` los aporta la parte de
Docker/Compose.

## Requisitos

- .NET SDK **8.0**
- Docker y Docker Compose

---

# Cómo empezar

## 1. Levantar la pila (PostgreSQL + Keycloak + API)

**Previo (una sola vez):**

```bash
cp .env.example .env      # y completar los valores reales
```

**Levantar todo:**

```bash
docker compose up -d
```

Este único comando deja los tres servicios en estado saludable, sin pasos manuales y
**sin cargar esquemas a mano**: la tabla `reservas` la crea el propio servicio al arrancar
(`EnsureCreatedAsync`, con reintentos contra la base).

**Verificar que la API responde:**

```bash
curl -s http://localhost:8080/health   # {"status":"healthy"}  -> 200
curl -s http://localhost:8080/ready    # {"status":"ready"}     -> 200
```

`/health` responde **sin tocar la base**; `/ready` depende de que PostgreSQL acepte
consultas. Si da `503`, la base aún no está disponible.

> **Requisitos del `docker-compose.yml`** (coordinación con la parte de Docker/Compose):
> - servicio `api`: puerto expuesto al host (p. ej. `8080:8080`), **healthcheck** apuntando
>   a `/health`, y `depends_on` con `condition: service_healthy` sobre `bd` y `auth`.
> - servicio `api`: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`,
>   `POSTGRES_PASSWORD`, `KEYCLOAK_AUTHORITY` (**por nombre de servicio**, ej.
>   `http://auth:8080/realms/restaurant`) y `KEYCLOAK_REQUIRED_ROLE`.
> - **Keycloak**: realm `restaurant` con el client `restaurant-api`, el rol `api-writer`
>   y los usuarios de prueba de la sección 2.

## 2. Pruebas (unitarias + integración)

Con la pila arriba, exporta la configuración y corre **todas** las pruebas con un solo
comando:

```bash
export TEST_API_BASE_URL=http://localhost:8080
export TEST_KEYCLOAK_TOKEN_URL=http://localhost:8080/realms/restaurant/protocol/openid-connect/token
export TEST_CLIENT_ID=restaurant-api
export TEST_CLIENT_SECRET=<client_secret_del_realm>

export TEST_USERNAME=escritor       TEST_PASSWORD=escritor-pass       # con el rol
export TEST_USERNAME_NOROLE=lector  TEST_PASSWORD_NOROLE=lector-pass  # sin el rol

dotnet test Project_Restaurant_API.Tests/Project_Restaurant_API.Tests.csproj
```

Esperado: **28 passed** (20 unitarias + 8 integración).

**Configuración de las pruebas** (valores por defecto entre paréntesis):

| Variable | Descripción |
|---|---|
| `TEST_API_BASE_URL` | URL de la API (`http://localhost:8080`) |
| `TEST_KEYCLOAK_TOKEN_URL` | Endpoint de token de Keycloak |
| `TEST_CLIENT_ID` / `TEST_CLIENT_SECRET` | Cliente confidencial para pedir token (`restaurant-api`) |
| `TEST_USERNAME` / `TEST_PASSWORD` | Usuario **con** el rol (`escritor`) |
| `TEST_USERNAME_NOROLE` / `TEST_PASSWORD_NOROLE` | Usuario **sin** el rol (`lector`) |

Las de integración (`Tests/Integration`) ejercitan contra la pila real:

| Prueba | Qué verifica |
|---|---|
| `Health_Responde200_SinTocarLaBase` | liveness abierto |
| `Ready_Responde200_CuandoPostgresAceptaConsultas` | readiness contra la BD |
| `CicloCRUD_Completo_ConPersistencia` | 401 → 201 → listar → filtrar → 200 → PUT 200 → DELETE 204 → 404 |
| `Crear_CuerpoInvalido_Responde400` | validación de entrada |
| `Consultar_IdInexistente_Responde404` | recurso inexistente |
| `Escribir_SinToken_Responde401` | autenticación requerida |
| `Escribir_TokenSinRol_Responde403` | rol requerido |
| `Salud_Y_Disponibilidad_QuedanAbiertas_SinToken` | health/ready abiertas |

**Solo unitarias** (sin Docker, PostgreSQL ni Keycloak):

```bash
dotnet test Project_Restaurant_API.Tests/Project_Restaurant_API.Tests.csproj \
  --filter "FullyQualifiedName~Unit"
```

Esperado: **20 passed** (validación de campos, límites 1–50 y mapeo DTO↔entidad).

**Compilar sin ejecutar pruebas:**

```bash
dotnet build Project_Restaurant_API/Project_Restaurant_API.sln
```

## 3. Verificación manual con `curl`

Recorre el contrato completo a mano. Suponiendo API en `:8080` y Keycloak en `:8081`
(ajusta según tus puertos):

```bash
API=http://localhost:8080
KC=http://localhost:8081/realms/restaurant/protocol/openid-connect/token

# --- Salud y disponibilidad (abiertas, sin token) ---
curl -s -w " [%{http_code}]\n" $API/health     # {"status":"healthy"} [200]
curl -s -w " [%{http_code}]\n" $API/ready      # {"status":"ready"}    [200]

# --- Lecturas (públicas) ---
curl -s -w " [%{http_code}]\n" $API/reservas                        # [] [200]
curl -s -w " [%{http_code}]\n" "$API/reservas?fecha=2026-08-20"     # [200]
curl -s -w " [%{http_code}]\n" $API/reservas/999999                 # 404

# --- Escritura SIN token -> 401 ---
curl -s -o /dev/null -w "%{http_code}\n" -X POST $API/reservas \
  -H "Content-Type: application/json" \
  -d '{"nombreCliente":"X","fecha":"2026-08-20","hora":"19:30:00","cantidadPersonas":2}'
# -> 401

# --- Obtener token (delegado a Keycloak) ---
TOKEN=$(curl -s -X POST $KC \
  -d "grant_type=password" \
  -d "client_id=restaurant-api" \
  -d "client_secret=<client_secret_del_realm>" \
  -d "username=escritor" -d "password=escritor-pass" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# --- Crear CON token -> 201 ---
curl -s -w "\n%{http_code}\n" -X POST $API/reservas \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"nombreCliente":"Ana Rodriguez","fecha":"2026-08-20","hora":"19:30:00","cantidadPersonas":4}'
# -> {"id":1,...} 201

# --- Token SIN el rol -> 403 ---
TOKEN_SIN_ROL=$(curl -s -X POST $KC \
  -d "grant_type=password" -d "client_id=restaurant-api" \
  -d "client_secret=<client_secret_del_realm>" \
  -d "username=lector" -d "password=lector-pass" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

curl -s -o /dev/null -w "%{http_code}\n" -X POST $API/reservas \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN_SIN_ROL" \
  -d '{"nombreCliente":"X","fecha":"2026-08-20","hora":"19:30:00","cantidadPersonas":2}'
# -> 403

# --- Cuerpo inválido -> 400 (no un 500) ---
curl -s -w "\n%{http_code}\n" -X POST $API/reservas \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"nombreCliente":""}'
# -> {"errors":{"NombreCliente":["..."],"Fecha":["..."],"Hora":["..."],...}} 400

# --- Listar y filtrar (lo que escribiste, leído desde la BD) ---
curl -s "$API/reservas?fecha=2026-08-20"

# --- Actualizar -> 200 ; y 404 si no existe ---
curl -s -w "\n%{http_code}\n" -X PUT $API/reservas/1 \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"nombreCliente":"Actualizado","fecha":"2026-08-21","hora":"20:00:00","cantidadPersonas":5}'
curl -s -o /dev/null -w "%{http_code}\n" -X PUT $API/reservas/999999 \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"nombreCliente":"X","fecha":"2026-08-21","hora":"20:00:00","cantidadPersonas":2}'
# -> 404

# --- Eliminar -> 204 ; repetir -> 404 ---
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE $API/reservas/1 -H "Authorization: Bearer $TOKEN"
# -> 204
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE $API/reservas/1 -H "Authorization: Bearer $TOKEN"
# -> 404
```

**Comportamiento esperado del proceso:** ninguna de estas llamadas (entrada mal formada,
recurso inexistente, token inválido) debe tumbar el servicio; el proceso sigue operativo
y `/health` sigue respondiendo `200`.

## 4. Comprobar la persistencia tras un reinicio

Los datos viven en el **volumen** de PostgreSQL, no en la app:

```bash
# 1. Escribir un registro (con token)
curl -s -X POST $API/reservas -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"nombreCliente":"Persistencia","fecha":"2026-12-24","hora":"13:00:00","cantidadPersonas":8}'

# 2. Bajar el sistema SIN borrar volúmenes
docker compose down

# 3. Volver a levantar
docker compose up -d

# 4. Leer los mismos datos
curl -s "$API/reservas?fecha=2026-12-24"
# -> debe devolver el mismo registro con el mismo id
```

> **Importante:** usar `docker compose down` **sin** la bandera `-v`. Con `-v` se borran
> los volúmenes y los datos se pierden (es lo que querrás al reiniciar desde cero, pero no
> para esta comprobación).

## 5. Apagar el sistema

```bash
docker compose down        # detiene y borra los contenedores, conserva el volumen
docker compose down -v     # idem, pero BORRA el volumen (pierde los datos)
docker compose down --rmi local  # además elimina las imágenes locales construidas
```

---

# Referencia

## Configuración (variables de entorno)

La imagen y el código **no contienen secretos**. Todo se inyecta por entorno
(usa `env.example` → `.env` como plantilla; el `.env` real va en `.gitignore`).

| Variable | Descripción | Ejemplo |
|---|---|---|
| `POSTGRES_HOST` | Host/nombre del servicio de BD en la red Compose | `bd` |
| `POSTGRES_PORT` | Puerto de PostgreSQL | `5432` |
| `POSTGRES_DB` | Nombre de la base | `restaurantdb` |
| `POSTGRES_USER` | Usuario de la base | `postgres` |
| `POSTGRES_PASSWORD` | Contraseña de la base | `secretodesk` |
| `KEYCLOAK_AUTHORITY` | URL del realm de Keycloak (issuer), **por nombre de servicio** | `http://auth:8080/realms/restaurant` |
| `KEYCLOAK_REQUIRED_ROLE` | Rol requerido para escribir | `api-writer` |
| `KEYCLOAK_AUDIENCE` | (opcional) Audiencia esperada del token | `restaurant-api` |
| `KEYCLOAK_VALID_ISSUER` | (opcional) Overrides del issuer si difiere de la authority | `http://localhost:8080/realms/restaurant` |

También se acepta la cadena de conexión completa en `ConnectionStrings__Default`; si no
existe, se arma a partir de las `POSTGRES_*`.

## Contrato de rutas

### Salud y disponibilidad (siempre abiertas, sin token)

| Método | Ruta | Descripción | Respuesta |
|---|---|---|---|
| `GET` | `/health` | **Liveness**. No toca la base de datos. | `200` `{"status":"healthy"}` |
| `GET` | `/ready` | **Readiness**. Verifica conexión a PostgreSQL. | `200` `{"status":"ready"}` o `503` si no conecta |

### Reservas (recurso)

| Método | Ruta | Auth | Descripción | Respuestas |
|---|---|---|---|---|
| `GET` | `/reservas` | pública | Lista todo. Admite filtro `?fecha=YYYY-MM-DD` | `200` `[ ... ]` |
| `GET` | `/reservas/{id}` | pública | Consulta por identificador | `200` / `404` |
| `POST` | `/reservas` | **rol requerido** | Crea una reserva | `201` / `400` / `401` / `403` |
| `PUT` | `/reservas/{id}` | **rol requerido** | Actualiza una reserva | `200` / `400` / `404` / `401` / `403` |
| `DELETE` | `/reservas/{id}` | **rol requerido** | Elimina una reserva | `204` / `404` / `401` / `403` |

> **Decisión documentada:** las **lecturas** (`GET`) quedan **públicas** y solo las
> **escrituras** (`POST`/`PUT`/`DELETE`) exigen token con el rol requerido. La spec lo
> deja a criterio del grupo; aquí se eligió exponer el listado/consulta sin autenticación
> y proteger únicamente las modificaciones.

## Cuerpo de una reserva y validación

```json
{
  "nombreCliente": "Ana Rodriguez",
  "fecha": "2026-08-20",
  "hora": "19:30:00",
  "cantidadPersonas": 4
}
```

- `nombreCliente`: obligatorio, máx. 120 caracteres.
- `fecha`: obligatoria, formato `yyyy-MM-dd`.
- `hora`: obligatoria, formato `HH:mm:ss`.
- `cantidadPersonas`: obligatorio, entero entre 1 y 50.

Cuerpo inválido o incompleto → **`400`** (RFC 7807, con el detalle por campo):

```json
{
  "title": "One or more validation errors occurred.",
  "status": 400,
  "errors": {
    "NombreCliente": ["nombreCliente es obligatorio."],
    "Fecha": ["fecha es obligatoria (formato yyyy-MM-dd)."],
    "Hora": ["hora es obligatoria (formato HH:mm:ss)."],
    "CantidadPersonas": ["cantidadPersonas es obligatoria."]
  }
}
```

## Autenticación (Keycloak)

- El servicio **no** implementa login ni firma de tokens; solo **valida** los JWT que
  recibe contra el proveedor (OIDC discovery + llaves públicas de Keycloak).
- `KEYCLOAK_AUTHORITY` apunta al issuer del realm. En la red de Compose se usa el
  **nombre del servicio** (`http://auth:8080/realms/...`), nunca `localhost` ni una IP fija.
- El rol viene en el claim `realm_access.roles` (realm) o `resource_access.<client>.roles`
  (cliente). Como ASP.NET no desanida esos objetos por sí solo, `Auth/KeycloakClaimsTransformation`
  los extrae y los expone como `ClaimTypes.Role` para que la política `Escritura` los evalúe.
- `POST`/`PUT`/`DELETE` usan la política `Escritura` (`RequireRole(KEYCLOAK_REQUIRED_ROLE)`).
- Resultados: sin token o token inválido → **401**; token válido **sin** el rol → **403**.

## Inicialización automática del esquema

Al arrancar, el servicio crea la tabla `reservas` si no existe
(`Database.EnsureCreatedAsync()` en `Program.cs`), con reintentos contra la base.
**No hay que cargar esquemas a mano.**

---

## Decisiones técnicas (servicio)

- **ASP.NET Core 8 + controladores**: mantiene la plantilla original del repo
  (`AddControllers`), sin introducir frameworks adicionales.
- **EF Core + Npgsql**: cliente oficial de PostgreSQL para .NET; permite mapear la entidad
  y crear el esquema por código de arranque.
- **Validación declarativa** (`Dtos/ReservaInputDto` con DataAnnotations): las reglas viven
  en atributos sobre el DTO (`[Required]`, `[MaxLength]`, `[Range]`), y al usar
  `[ApiController]` ASP.NET responde `400` automáticamente con el detalle por campo — en vez
  de un `500` — antes de ejecutar la acción. Sigue siendo unitaria con `Validator.TryValidateObject`.
- **`/health` sin tocar la base** y **`/ready` con `CanConnectAsync`**: separar liveness de
  readiness permite que el healthcheck del contenedor no dependa de la BD.
- **Seguridad por política** (`Escritura`), no por atributo con rol en duro: el rol se
  toma de `KEYCLOAK_REQUIRED_ROLE`.
