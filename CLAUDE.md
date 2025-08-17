# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an energy management system built on Directus CMS with PostgreSQL. It tracks power consumption, solar production, battery scenarios, and spot prices for energy analysis and optimization. The system uses custom Directus extensions for data visualization and API endpoints.

## Commands

### Extension Development
```bash
# Build all extensions
cd extensions/[extension-name] && npm run build

# Development mode with watch
cd extensions/[extension-name] && npm run dev

# Validate extension
cd extensions/[extension-name] && npm run validate

# Link extension for development
cd extensions/[extension-name] && npm run link
```

### Database Management
```bash
# Apply schema changes
psql -d directus -f tables_up.sql

# Rollback schema changes  
psql -d directus -f tables_down.sql

# Refresh materialized views
psql -d directus -f refresh_materialized_views.sql
```

## Architecture

### Database Schema
The system centers around energy data with these core tables:
- `power_consumption` - Main site energy consumption with timestamps
- `solar` - Solar energy production data
- `battery_scenario_sim` - Battery charge/discharge simulations
- `spot_prices_gen` - Energy spot pricing with action flags
- `scenario` - Energy scenario configurations linking all data sources

### Materialized Views
- `energy_summary_mv` - Transposed yearly summary with auto-refresh triggers
- `joined_energy_data_mv` - Unified energy data table for Directus compatibility

### Extension Types

**Panels** (dashboard widgets):
- `panel-energy-summary` - Pivoted year-by-metric energy display
- `panel-sql-view` - SQL query results visualization
- `panel-run-battery-sim` - Battery simulation interface
- `panel-open-link` - Link navigation widget

**Endpoints** (API routes):
- `endpoint-energy-summary` - Energy data aggregation API
- `endpoint-sql-view` - Secure SELECT-only SQL execution
- `endpoint-run-battery-sim` - Battery simulation calculations

**Interfaces**:
- `interface-dropdown` - Custom dropdown component

### Data Flow
1. Time-series data flows into core tables (consumption, solar, battery, spot prices)
2. Materialized views aggregate data for efficient querying
3. Panel extensions fetch data via endpoint extensions
4. Scenario table links different data sources for analysis

### Extension Structure
Each extension follows Directus conventions:
- `src/index.ts` - Main extension definition
- `src/panel.vue` - Vue component for panels
- TypeScript with Vue 3 for panel interfaces
- Build output to `dist/` directory

### Key Patterns
- All energy data uses `timestamptz` for timezone consistency
- Composite indexes on `(code, timestamp)` for efficient queries
- Foreign key relationships maintain data integrity
- Extensions communicate via REST API calls to `/endpoint-*` routes

## Docker Deployment

### Local Development
```bash
# Build and start all services
docker-compose up --build -d

# Check service status
docker-compose ps

# View logs
docker-compose logs directus

# Stop all services
docker-compose down
```

### Build Extensions
```bash
# Build all extensions at once
./scripts/build-extensions.sh

# Or build individually
cd extensions/[extension-name] && npm run build
```

### Production Deployment Notes
**IMPORTANT**: Before deploying to production, you MUST change these values:
- `ADMIN_EMAIL` - Change from admin@example.com to your email
- `ADMIN_PASSWORD` - Change from d1r3ctu5 to a secure password
- `KEY` - Generate new random key for encryption
- `SECRET` - Generate new random secret for JWT tokens

**Access**: System available at http://localhost:8055 after startup
**Database**: Schema files automatically loaded on first PostgreSQL startup
**Extensions**: All 8 custom extensions pre-built and installed in container

## Private Registry Deployment

### Option 1: Private Docker Registry
```bash
# Configure registry in environment
export REGISTRY_HOST=your-registry.company.com
export IMAGE_NAME=lesetool-directus
export VERSION=latest

# Deploy to registry
./scripts/deploy-private-registry.sh

# On your servers
docker pull your-registry.company.com/lesetool-directus:latest
docker-compose -f docker-compose.prod.yml up -d
```

### Option 2: AWS ECR
```bash
# Configure AWS variables
export AWS_REGION=us-west-2
export AWS_ACCOUNT_ID=123456789012
export REPOSITORY_NAME=lesetool-directus

# Deploy to ECR
./scripts/deploy-aws-ecr.sh

# On EC2 servers
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-west-2.amazonaws.com
docker-compose -f docker-compose.prod.yml up -d
```

### Option 3: Direct Server Transfer
```bash
# Configure server details
export SERVER_HOST=your-server.com
export SERVER_USER=ubuntu

# Deploy directly
./scripts/deploy-direct-server.sh
```

### Production Setup
```bash
# Generate secure secrets
./scripts/generate-secrets.sh

# Setup production environment
./scripts/setup-production.sh

# Deploy with production config
docker-compose -f docker-compose.prod.yml up -d
```

**Registry Authentication**: See `registry-auth.example` for authentication setup examples for different registry types.

## Forgejo Git Repository & Container Registry

### Setup Forgejo Authentication
```bash
# Interactive setup
./scripts/setup-forgejo-auth.sh

# Or manual login
docker login forgejo.yourcompany.com --username your-username
```

### Deploy to Forgejo Registry
```bash
# Configure environment
export FORGEJO_REGISTRY=forgejo.yourcompany.com
export FORGEJO_ORG=your-organization
export FORGEJO_USER=your-username

# Deploy to registry
./scripts/deploy-forgejo.sh

# Deploy with Forgejo-specific compose file
docker-compose -f docker-compose.forgejo.yml up -d
```

### Forgejo Actions CI/CD
The project includes Forgejo Actions workflows in `.forgejo/workflows/`:

- **build-and-deploy.yml** - Builds extensions, creates Docker image, pushes to Forgejo registry
- **test.yml** - Tests extension builds and Docker image creation

**Image naming**: `forgejo.yourcompany.com/your-org/lesetool-directus:latest`
**Registry format**: `{registry}/{owner}/{image}:{tag}` (follows OCI standard)
**Authentication**: Use Personal Access Token for 2FA/automated deployments

### Required Forgejo Settings
- Enable Container Registry in repository settings
- Create Personal Access Token with `write:packages` permission
- Set repository variables: `FORGEJO_REGISTRY`
- Set repository secrets: `GITEA_TOKEN`