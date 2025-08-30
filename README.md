# Entorno de Desarrollo Unificado

Este proyecto combina varios servicios esenciales para desarrollo en un solo entorno Docker:

- **LocalStack**: Simulación local de servicios AWS
- **MySQL**: Base de datos relacional
- **PHPMyAdmin**: Interfaz web para gestión de MySQL
- **MailHog**: Servidor SMTP de pruebas para capturar emails
- **N8N**: Plataforma de automatización y workflows

## Requisitos

- Docker
- Docker Compose
- Make (opcional, para comandos simplificados)

## Estructura del Proyecto

```
proyecto/
├── docker-compose.yml          # Configuración principal
├── Dockerfile                  # LocalStack personalizado
├── Makefile                    # Comandos útiles
├── README.md                   # Este archivo
├── data/
│   └── localstack/            # Datos persistentes de LocalStack
├── init-scripts/              # Scripts de inicialización de LocalStack
├── localstack-config/         # Configuración de LocalStack
├── aws-scripts/               # Scripts de AWS CLI
├── mysql-init/                # Scripts de inicialización de MySQL
│   └── init-mysql.sql
└── n8n-backups/              # Backups de workflows de N8N
```

## Configuración Inicial

1. Clonar o crear el proyecto:

```bash
mkdir mi-entorno-dev && cd mi-entorno-dev
```

1. Copiar los archivos del proyecto (docker-compose.yml, Dockerfile, etc.)

2. Crear la estructura de directorios:

```bash
make setup
# O manualmente:
mkdir -p data/localstack init-scripts localstack-config aws-scripts mysql-init n8n-backups
```

1. Copiar el script de inicialización de MySQL:

```bash
cp init-mysql.sql mysql-init/
```

## Uso

### Con Make (Recomendado)

```bash
# Ver todos los comandos disponibles
make help

# Iniciar todos los servicios
make up

# Ver logs en tiempo real
make logs

# Ver estado de los servicios
make status

# Parar todos los servicios
make down

# Limpiar todo (contenedores, volúmenes, etc.)
make clean
```

### Con Docker Compose

```bash
# Iniciar servicios
docker-compose up -d

# Ver logs
docker-compose logs -f

# Parar servicios
docker-compose down
```

## Acceso a los Servicios

Una vez iniciados los servicios, estarán disponibles en:

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| LocalStack | <http://localhost:4566> | test/test |
| PHPMyAdmin | <http://localhost:8082> | root/root_password |
| MailHog Web UI | <http://localhost:8025> | - |
| N8N | <http://localhost:5678> | admin/admin |
| MySQL | localhost:3306 | root/root_password |
| MailHog SMTP | localhost:1025 | - |

## Configuraciones Específicas

### LocalStack

- **Endpoint**: <http://localhost:4566>
- **Región**: us-east-1  
- **Access Key**: test
- **Secret Key**: test

Para usar AWS CLI con LocalStack:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
```

### MySQL

- **Host**: localhost (o mysql desde otros contenedores)
- **Puerto**: 3306
- **Usuario root**: root / root_password
- **Usuario admin**: admin / admin
- **Bases de datos**: db_template, n8n_db, dev_database

### N8N

- **URL**: <http://localhost:5678>
- **Usuario**: admin
- **Contraseña**: admin
- **Base de datos**: Configurada para usar MySQL
- **Email**: Configurado para usar MailHog

### MailHog

- **Web UI**: <http://localhost:8025>
- **SMTP**: localhost:1025
- **Configuración para aplicaciones**:
  - Host: localhost (o mailhog desde contenedores)
  - Puerto: 1025
  - Sin autenticación

## Comandos Útiles

### Backup de N8N

```bash
make backup-n8n
```

### Acceder a shells de contenedores

```bash
make shell-mysql
make shell-localstack
make shell-n8n
```

### Verificar salud de servicios

```bash
make health
```

### Reiniciar un servicio específico

```bash
make restart-service SERVICE=mysql
```

## Personalización

### Agregar scripts de inicialización de LocalStack

Coloca scripts en `./init-scripts/` y se ejecutarán cuando LocalStack esté listo.

### Agregar scripts de inicialización de MySQL

Coloca archivos `.sql` en `./mysql-init/` y se ejecutarán al crear la base de datos.

### Modificar configuraciones

Edita las variables de entorno en el `docker-compose.yml` según tus necesidades.

## Troubleshooting

### Los servicios no se conectan entre sí

Todos los servicios están en la red `dev-network`. Usa los nombres de servicio como hostnames.

### N8N no puede conectar a MySQL

Verifica que MySQL esté saludable antes de que N8N inicie:

```bash
docker-compose logs mysql
make health
```

### LocalStack no persiste datos

Verifica que el directorio `./data/localstack` existe y tiene permisos correctos.

### Puertos ocupados

Si algún puerto está ocupado, modifica el mapeo en `docker-compose.yml`:

```yaml
ports:
  - "NUEVO_PUERTO:PUERTO_CONTENEDOR"
```

## Limpieza

Para limpiar completamente el entorno:

```bash
make clean-all
```

Esto eliminará:

- Todos los contenedores
- Volúmenes de datos
- Redes
- Imágenes no utilizadas

## Contribuir

Para agregar nuevos servicios:

1. Añade el servicio en `docker-compose.yml`
2. Agrega la red `dev-network`
3. Actualiza este README
4. Agrega comandos útiles al Makefile
