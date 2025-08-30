FROM localstack/localstack:latest

# Instalar herramientas adicionales
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    jq \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Crear directorio para scripts de inicialización
RUN mkdir -p /etc/localstack/init/ready.d

# Copiar scripts de inicialización
COPY ./init-scripts/ /etc/localstack/init/ready.d/

# Hacer los scripts ejecutables
RUN chmod +x /etc/localstack/init/ready.d/*

# Exponer puertos
EXPOSE 4566 4510-4559