using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Project_Restaurant_API.Auth;
using Project_Restaurant_API.Data;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Configuración por variables de entorno: sin secretos en la imagen ni en el código.
// ---------------------------------------------------------------------------
var config = builder.Configuration;

// Cadena de conexión armada desde las POSTGRES_* (o ConnectionStrings__Default).
var connectionString = config.GetConnectionString("Default")
    ?? $"Host={config["POSTGRES_HOST"] ?? "bd"}" +
       $";Port={config["POSTGRES_PORT"] ?? "5432"}" +
       $";Database={config["POSTGRES_DB"] ?? "restaurantdb"}" +
       $";Username={config["POSTGRES_USER"] ?? "postgres"}" +
       $";Password={config["POSTGRES_PASSWORD"] ?? ""}";

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddDbContext<RestaurantContext>(options => options.UseNpgsql(connectionString));

// --- Autenticación delegada: la app solo VALIDA los JWT que emite Keycloak ---
var authority = config["KEYCLOAK_AUTHORITY"];          // ej. http://auth:8080/realms/restaurant
var audience = config["KEYCLOAK_AUDIENCE"];            // opcional
var validIssuer = config["KEYCLOAK_VALID_ISSUER"];     // opcional, si el issuer difiere

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        if (!string.IsNullOrEmpty(authority))
        {
            options.Authority = authority;   // OIDC discovery + llaves públicas
        }

        options.RequireHttpsMetadata = false;  // Keycloak corre por http en la red de Compose

        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateLifetime = true,
            ValidateAudience = !string.IsNullOrEmpty(audience)
            // Los roles se exponen como ClaimTypes.Role vía KeycloakClaimsTransformation.
        };

        if (!string.IsNullOrEmpty(validIssuer))
        {
            options.TokenValidationParameters.ValidIssuer = validIssuer;
        }

        if (!string.IsNullOrEmpty(audience))
        {
            options.TokenValidationParameters.ValidAudience = audience;
        }
    });

// Política de escritura: el rol sale de la configuración, no está en duro.
builder.Services.AddAuthorization(options =>
    options.AddPolicy("Escritura",
        p => p.RequireRole(config["KEYCLOAK_REQUIRED_ROLE"] ?? "api-writer")));

builder.Services.AddSingleton<IClaimsTransformation, KeycloakClaimsTransformation>();

var app = builder.Build();

// Inicialización automática del esquema (sin migraciones ni pasos manuales).
// Con reintentos por si la base tarda en estar disponible.
await CrearEsquemaSiNoExisteAsync(app.Services);

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthentication();
app.UseAuthorization();

// --- Salud (liveness) y disponibilidad (readiness) ---
// Ambas quedan abiertas: sin ellas el healthcheck del contenedor no funcionaría.

// Liveness: responde sin tocar la base; indica que el proceso está vivo.
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
   .AllowAnonymous();

// Readiness: comprueba que PostgreSQL acepta consultas (200) o no (503).
app.MapGet("/ready", async Task<IResult> (RestaurantContext db, CancellationToken ct) =>
{
    try
    {
        return await db.Database.CanConnectAsync(ct)
            ? Results.Ok(new { status = "ready" })
            : Results.Json(new { status = "unavailable" },
                statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (Exception)
    {
        // Nunca cae: devuelve 503 y el proceso sigue operativo.
        return Results.Json(new { status = "unavailable" },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
}).AllowAnonymous();

app.MapControllers();

app.Run();

static async Task CrearEsquemaSiNoExisteAsync(IServiceProvider services)
{
    const int maxIntentos = 30;

    for (int intento = 1; intento <= maxIntentos; intento++)
    {
        try
        {
            using var scope = services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<RestaurantContext>();
            await db.Database.EnsureCreatedAsync();
            return;
        }
        catch (Exception ex) when (intento < maxIntentos)
        {
            services.GetRequiredService<ILogger<Program>>().LogWarning(
                ex, "Esquema no inicializado (intento {Intento}/{Max}); reintentando...",
                intento, maxIntentos);

            await Task.Delay(TimeSpan.FromSeconds(3));
        }
    }
}
