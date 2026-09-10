De momento, tener lo que se va a necesitar, y hasta al final, acomodar las secciones de forma mas profesional.

# Docker commands

- Create the image: 'docker build -t dotnet-8 .'

- Create container: 'docker run --name Restaurant_API -p 8080:8080 dotnet-8'

- Start compose:  'docker compose up -d'

- Stop, remove containers, and delete the volume(add flag -v): 'docker compose down -v'

# .Env Configuration

- Use the file .env.example as a guide.

# Justification

Escribir aqui lo que se pide justificar por escrito