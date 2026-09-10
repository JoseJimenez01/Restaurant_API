
#Never use comments at the end of an instruction

# Specifie the base image from which i am building, taken from: https://learn.microsoft.com/en-us/dotnet/architecture/microservices/net-core-net-framework-containers/official-net-docker-images
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

COPY . .

# Restore dependencies, from the solution
RUN dotnet restore Project_Restaurant_API/Project_Restaurant_API.sln

# Publish version
RUN dotnet publish Project_Restaurant_API/Project_Restaurant_API.sln -c Release -o /app --no-restore

# Make it Multi-Stage, without compilation tools
FROM mcr.microsoft.com/dotnet/aspnet:8.0

WORKDIR /app

# Specifie the stage from i am copying
COPY --from=build /app ./

# equal to: 'dotnet api.dll' in console
ENTRYPOINT ["dotnet", "Project_Restaurant_API.dll"]

