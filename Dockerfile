# Dockerfile del servicio Restaurant API (ASP.NET Core 8 + EF Core/Npgsql).
#
# Todas las decisiones se justifican en el README (seccion "Decisiones de contenerizacion").
#
# --------------------------------------------------------------------------------------
# Etapa 1: compilacion. Imagen base oficial del SDK de .NET 8.0 de Microsoft.
# --------------------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

# Se copia todo el contexto de construccion. El .dockerignore ya excluye lo que no
# corresponde (bin/, obj/, .git, .env, el propio Dockerfile y el compose, README, etc.).
COPY . .

# Se restauran las dependencias a partir de la solucion (incluye el proyecto de pruebas,
# que comparte paquetes y por eso se publica junto con la app en la etapa siguiente).
RUN dotnet restore Project_Restaurant_API/Project_Restaurant_API.sln

# Se publica SOLO el servicio (no las pruebas) en Release, sin volver a restaurar.
RUN dotnet publish Project_Restaurant_API/Project_Restaurant_API.csproj -c Release -o /app --no-restore

# --------------------------------------------------------------------------------------
# Etapa 2: ejecucion. Imagen base oficial aspnet 8.0: solo el runtime, sin herramientas
# de compilacion, mas pequena y con menor superficie de ataque.
# --------------------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:8.0

WORKDIR /app

# Se copia unicamente el artefacto publicado (no el codigo fuente ni el SDK).
COPY --from=build /app ./

# Las imagenes oficiales aspnet de .NET 8 escuchan en el puerto 8080
# (variable ASPNETCORE_HTTP_PORTS=8080). Se declara por transparencia.
EXPOSE 8080

# Comando de arranque del proceso.
ENTRYPOINT ["dotnet", "Project_Restaurant_API.dll"]