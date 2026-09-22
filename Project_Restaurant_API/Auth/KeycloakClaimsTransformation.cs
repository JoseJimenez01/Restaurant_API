using System.Security.Claims;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authentication;

namespace Project_Restaurant_API.Auth;

/// <summary>
/// Expone los roles de Keycloak como ClaimTypes.Role para que la política
/// RequireRole() pueda evaluarlos.
///
/// Keycloak entrega los roles anidados en "realm_access" ({"roles":[...]}) o en
/// "resource_access" ({"cliente":{"roles":[...]}}); ASP.NET NO desanida esos objetos
/// por sí solo, de modo que sin esta transformación un token con el rol recibiría 403.
/// </summary>
public class KeycloakClaimsTransformation : IClaimsTransformation
{
    public Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        var identity = principal.Identities.FirstOrDefault(i => i.IsAuthenticated);
        if (identity is null)
        {
            return Task.FromResult(principal);
        }

        var roles = RolesDeRealm(principal).Concat(RolesDeClientes(principal));

        foreach (var rol in roles)
        {
            // Sin duplicados: la transformación puede invocarse más de una vez.
            if (!identity.HasClaim(ClaimTypes.Role, rol))
            {
                identity.AddClaim(new Claim(ClaimTypes.Role, rol));
            }
        }

        return Task.FromResult(principal);
    }

    private static IEnumerable<string> RolesDeRealm(ClaimsPrincipal p) =>
        Strings(LeerJson(p, "realm_access")?["roles"] as JsonArray);

    private static IEnumerable<string> RolesDeClientes(ClaimsPrincipal p) =>
        (LeerJson(p, "resource_access") as JsonObject)?
            .Select(cliente => Strings(cliente.Value?["roles"] as JsonArray))
            .SelectMany(x => x)
        ?? Enumerable.Empty<string>();

    private static IEnumerable<string> Strings(JsonArray? array) =>
        array?.OfType<JsonValue>()
             .Select(v => v.TryGetValue<string>(out var s) ? s : null)
             .OfType<string>()
        ?? Enumerable.Empty<string>();

    /// <summary>Claim mal formado no debe tumbar la petición: se ignora.</summary>
    private static JsonNode? LeerJson(ClaimsPrincipal p, string claim)
    {
        try
        {
            return JsonNode.Parse(p.FindFirst(claim)?.Value ?? "null");
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }
}
