# Directus Migration Guide: Development to Production

This guide documents the step-by-step process for migrating a Dockerized Directus application from development to production, including PostgreSQL database, schema, and file uploads.

## Overview

**Source (Development):**
- Server: `easerver` (ecologic@easerver)
- Docker Image: `setool:v0.0.2` (custom image with built-in extensions)
- Database: PostgreSQL on `ecologic_net` network
- Path: `/home/ecologic/apps/directus/aos`

**Target (Production):**
- Server: `EcoDocker` (root@139.180.171.227)
- Docker Image: `oddinnovate/setool:v0.0.1` (pulled from registry)
- Database: TimescaleDB on `ecologic_net` network
- Path: `/srv/apps/setool/directus-migration`

## Prerequisites

- SSH access to both development and production servers
- Docker and Docker Compose installed on both servers
- Sufficient disk space for backups (~300MB in this case)
- Network connectivity between servers

## Migration Steps

### Phase 1: Backup Development Environment

#### 1.1 Create Schema Snapshot

```bash
# On development server
cd /home/ecologic/apps/directus/aos

# Create Directus schema snapshot
docker compose exec directus npx directus schema snapshot /directus/uploads/snapshot.yaml

# Copy snapshot from container to host
docker compose cp directus:/directus/uploads/snapshot.yaml ./snapshot.yaml
```

**Output:** `snapshot.yaml` (975KB) - Contains all Directus collections, fields, relations, and settings.

#### 1.2 Backup PostgreSQL Database

```bash
# Find the PostgreSQL container name
docker ps | grep postgres

# Create PostgreSQL dump (custom format with compression)
docker exec postgres pg_dump -U directus -d directus_crm -F c -f /tmp/aos_backup.dump

# Copy dump from container to host with date stamp
docker cp postgres:/tmp/aos_backup.dump ./aos_backup_$(date +%Y%m%d).dump
```

**Output:** `aos_backup_20251001.dump` (105MB) - Full database backup in PostgreSQL custom format.

#### 1.3 Backup Uploads Volume

```bash
# Backup the uploads volume to compressed tarball
docker run --rm \
  -v aos_directus_uploads:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/uploads_backup_$(date +%Y%m%d).tar.gz -C /data .
```

**Output:** `uploads_backup_20251001.tar.gz` (168MB) - All uploaded files and assets.

#### 1.4 Verify Backup Files

```bash
# Check all backup files are created
ls -lh *.yaml *.dump *.tar.gz

# Expected output:
# aos_backup_20251001.dump (105MB)
# snapshot.yaml (975KB)
# uploads_backup_20251001.tar.gz (168MB)
```

### Phase 2: Prepare Production Configuration

#### 2.1 Production Environment File

Your production `.env.prod` should contain:

```bash
# ── Database Configuration
DB_CLIENT=pg
DB_HOST=timescaledb
DB_PORT=5432
DB_DATABASE=setool
DB_USER=ecoadmin
DB_PASSWORD=<your-secure-password>

# ── Cache & Session Configuration
CACHE_ENABLED=true
CACHE_STORE=redis
CACHE_TTL=300
CACHE_AUTO_PURGE=true
CACHE_NAMESPACE=directus_cache
REDIS=redis://redis:6379
SESSION_STORE=redis
SESSION_REDIS=redis://redis:6379

# ── Security Configuration (GENERATE NEW VALUES)
KEY=<generate-new-uuid>
SECRET=<generate-new-uuid>

# ── Admin User Configuration
ADMIN_EMAIL=admin@yourcompany.com
ADMIN_PASSWORD=<strong-password>

# ── Application Configuration
PUBLIC_URL=https://your-production-domain.com
LOG_LEVEL=info
EXTENSIONS_PATH=/directus/extensions

# ── Performance & Limits
PRESSURE_LIMITER_ENABLED=true
MAX_PAYLOAD_SIZE=500mb
QUERY_LIMIT_MAX=200000
EXPORT_BATCH_SIZE=50000
IMPORT_TIMEOUT=600000
IMPORT_BATCH_SIZE=10000
DB_QUERY_TIMEOUT=300000

# ── File Upload Configuration
FILES_MAX_UPLOAD_SIZE=2gb
TUS_ENABLED=true
TUS_CHUNK_SIZE=50mb

# ── Rate Limiting
RATE_LIMITER_ENABLED=true
RATE_LIMITER_STORE=redis

# ── Docker Configuration
COMPOSE_PROJECT_NAME=setool-prod
DIRECTUS_IMAGE=oddinnovate/setool:v0.0.1
REDIS_IMAGE=redis:7-alpine
NETWORK_NAME=ecologic_net
```

#### 2.2 Production Docker Compose File

Your `docker-compose.prod.yml` should use environment variables:

```yaml
services:
  redis:
    image: ${REDIS_IMAGE:-redis:7-alpine}
    restart: unless-stopped
    volumes:
      - redis_data:/data
    networks:
      - ecologic_net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  directus:
    image: ${DIRECTUS_IMAGE}
    restart: unless-stopped
    ports:
      - "8055:8055"
    environment:
      # All environment variables from .env file
      DB_CLIENT: ${DB_CLIENT}
      DB_HOST: ${DB_HOST}
      # ... (reference your complete compose file)
    volumes:
      - directus_uploads:/directus/uploads
      - directus_database:/directus/database
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - ecologic_net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8055/server/health"]
      interval: 30s
      timeout: 10s
      retries: 5

volumes:
  redis_data:
  directus_uploads:
  directus_database:

networks:
  ecologic_net:
    name: ${NETWORK_NAME:-ecologic_net}
    external: true
```

### Phase 3: Transfer Files to Production

#### 3.1 Create Directory on Production Server

```bash
# On development server, create remote directory
ssh root@139.180.171.227 "mkdir -p /srv/apps/setool/directus-migration"
```

#### 3.2 Transfer All Migration Files

```bash
# On development server, transfer all files at once
rsync -avz --progress \
  snapshot.yaml \
  aos_backup_20251001.dump \
  uploads_backup_20251001.tar.gz \
  .env.prod \
  docker-compose.prod.yml \
  root@139.180.171.227:/srv/apps/setool/directus-migration/
```

### Phase 4: Deploy on Production

#### 4.1 SSH to Production Server

```bash
ssh root@139.180.171.227
cd /srv/apps/setool/directus-migration
```

#### 4.2 Setup Environment

```bash
# Rename .env.prod to .env
mv .env.prod .env

# Create the ecologic_net network if it doesn't exist
docker network create ecologic_net 2>/dev/null || true

# Pull the Docker image from registry
docker pull oddinnovate/setool:v0.0.1
```

#### 4.3 Start Services

```bash
# Start Redis and Directus services
docker compose -f docker-compose.prod.yml up -d

# Wait for services to initialize
sleep 30

# Check service status
docker compose -f docker-compose.prod.yml ps
```

### Phase 5: Restore Database and Schema

#### 5.1 Grant Database Permissions

```bash
# The directus role should already exist on production
# Grant necessary privileges using a superuser account
docker exec timescaledb psql -U nocodb -d postgres -c "GRANT ecoadmin TO directus;"
```

#### 5.2 Restore PostgreSQL Database

```bash
# Restore database dump with ownership mapping
docker exec -i timescaledb pg_restore \
  -U ecoadmin \
  -d setool \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  < aos_backup_20251001.dump
```

**Key flags:**
- `--clean`: Drop existing objects before recreating
- `--if-exists`: Don't error if objects don't exist
- `--no-owner`: Skip ownership restoration (use current user)
- `--no-privileges`: Skip permission restoration

#### 5.3 Apply Directus Schema Snapshot

```bash
# Copy snapshot to container
docker cp directus-migration/snapshot.yaml \
  $(docker compose -f docker-compose.prod.yml ps -q directus):/directus/uploads/

# Apply the schema
docker compose -f docker-compose.prod.yml exec directus \
  npx directus schema apply /directus/uploads/snapshot.yaml
```

**Note:** You'll be prompted to confirm schema changes. Type `Yes` to proceed.

#### 5.4 Restore Uploads Volume

```bash
# Extract uploads backup into the Docker volume
docker run --rm \
  -v setool-prod_directus_uploads:/data \
  -v $(pwd)/directus-migration:/backup \
  alpine tar xzf /backup/uploads_backup_20251001.tar.gz -C /data
```

### Phase 6: Finalize and Verify

#### 6.1 Restart Services

```bash
# Restart Directus to ensure all changes are loaded
docker compose -f docker-compose.prod.yml restart directus

# Wait for startup
sleep 10
```

#### 6.2 Verify Deployment

```bash
# Check container health
docker compose -f docker-compose.prod.yml ps

# View logs for any errors
docker compose -f docker-compose.prod.yml logs directus --tail 50

# Test health endpoint
curl http://localhost:8055/server/health
```

#### 6.3 Access Directus

Open your browser and navigate to your `PUBLIC_URL` (e.g., `https://your-domain.com:8055`)

Login with credentials from your `.env` file:
- Email: `ADMIN_EMAIL`
- Password: `ADMIN_PASSWORD`

## Verification Checklist

- [ ] All collections are visible in Directus admin
- [ ] Custom extensions are loaded (check logs for extension list)
- [ ] Uploaded files are accessible
- [ ] Database queries work correctly
- [ ] Custom panels and endpoints function properly
- [ ] Materialized views are present (if applicable)
- [ ] Users can login successfully
- [ ] Health check endpoint returns 200 OK

## Troubleshooting

### Database Restore Issues

**Problem:** `must be able to SET ROLE "directus"`

**Solution:** Use `--no-owner --no-privileges` flags to skip role/ownership checks.

### Schema Apply Fails

**Problem:** `ENOENT: no such file or directory, open '/directus/uploads/snapshot.yaml'`

**Solution:** Copy the snapshot file into the container first using `docker cp`.

### Container Unhealthy

**Problem:** Directus container shows as unhealthy

**Solution:**
- Check logs: `docker compose logs directus`
- Verify database connection settings
- Ensure Redis is healthy
- Check if extensions are loading properly

### Missing Extensions

**Problem:** Custom extensions not loading

**Solution:**
- Verify extensions are built into your Docker image
- Check `EXTENSIONS_PATH` environment variable
- View logs for extension loading messages

## Important Notes

1. **Database User Mapping**: If source and target databases use different usernames, use `--no-owner --no-privileges` flags during restore.

2. **Custom Extensions**: If your extensions are built into the Docker image (like `setool:v0.0.2`), you don't need to copy extension folders separately.

3. **Network Requirements**: Ensure the `ecologic_net` network exists and is properly configured for inter-container communication.

4. **Schema Snapshots vs Database Dumps**:
   - Schema snapshots (`.yaml`) contain Directus-specific configuration
   - Database dumps (`.dump`) contain actual data and database structure
   - Both are needed for a complete migration

5. **Version Compatibility**: Ensure source and target Directus versions are compatible. In this migration, both used v11.9.2.

## Maintenance

### Creating Regular Backups

Add this script to your cron for automated backups:

```bash
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR="/root/backups"

mkdir -p $BACKUP_DIR

# Schema snapshot
docker compose exec -T directus npx directus schema snapshot - > $BACKUP_DIR/snapshot_$DATE.yaml

# Database backup
docker exec timescaledb pg_dump -U ecoadmin -d setool -F c -f /tmp/backup.dump
docker cp timescaledb:/tmp/backup.dump $BACKUP_DIR/db_backup_$DATE.dump

# Uploads backup
docker run --rm -v setool-prod_directus_uploads:/data -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/uploads_$DATE.tar.gz -C /data .

# Cleanup old backups (keep last 7 days)
find $BACKUP_DIR -name "*.yaml" -mtime +7 -delete
find $BACKUP_DIR -name "*.dump" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
```

## Summary

This migration process successfully transferred:
- ✅ Directus schema and configuration (975KB)
- ✅ PostgreSQL database with all data (105MB)
- ✅ File uploads and assets (168MB)
- ✅ Custom extensions (built into Docker image)
- ✅ Environment configuration

**Total Migration Time:** ~15-30 minutes (depending on network speed and database size)

**Downtime:** Minimal - deploy production in parallel, then switch DNS/traffic

## References

- [Directus Schema Management](https://docs.directus.io/configuration/data-model/)
- [PostgreSQL pg_dump Documentation](https://www.postgresql.org/docs/current/app-pgdump.html)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
