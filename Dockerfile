# Multi-stage build for Directus with custom extensions and marketplace extensions
#FROM node:18-alpine AS extension-builder
FROM node:22-alpine AS extension-builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Copy custom extensions source
COPY extensions/ ./extensions/

# Install all dependencies (this will install marketplace extensions to node_modules)
RUN npm ci

# Build each custom extension
RUN cd extensions/endpoint-energy-summary && npm ci && npm run build
RUN cd extensions/endpoint-sql-view && npm ci && npm run build  
RUN cd extensions/endpoint-run-battery-sim && npm ci && npm run build
RUN cd extensions/panel-energy-summary && npm ci && npm run build
RUN cd extensions/panel-sql-view && npm ci && npm run build
RUN cd extensions/panel-run-battery-sim && npm ci && npm run build
RUN cd extensions/panel-open-link && npm ci && npm run build
RUN cd extensions/interface-dropdown && npm ci && npm run build
RUN cd extensions/panel-scenario-columns && npm ci && npm run build
RUN cd extensions/endpoint-sql-runner && npm ci && npm run build


# Production stage
FROM directus/directus:11.9.2

# Switch to root for file operations
USER root

# Copy built custom extensions (full folders, not just dist)
COPY --from=extension-builder /app/extensions/endpoint-energy-summary /directus/extensions/endpoint-energy-summary
COPY --from=extension-builder /app/extensions/endpoint-sql-view /directus/extensions/endpoint-sql-view
COPY --from=extension-builder /app/extensions/endpoint-run-battery-sim /directus/extensions/endpoint-run-battery-sim
COPY --from=extension-builder /app/extensions/panel-energy-summary /directus/extensions/panel-energy-summary
COPY --from=extension-builder /app/extensions/panel-sql-view /directus/extensions/panel-sql-view
COPY --from=extension-builder /app/extensions/panel-run-battery-sim /directus/extensions/panel-run-battery-sim
COPY --from=extension-builder /app/extensions/panel-open-link /directus/extensions/panel-open-link
COPY --from=extension-builder /app/extensions/interface-dropdown /directus/extensions/interface-dropdown
COPY --from=extension-builder /app/extensions/panel-scenario-columns /directus/extensions/panel-scenario-columns
COPY --from=extension-builder /app/extensions/endpoint-sql-runner /directus/extensions/endpoint-sql-runner


# Copy marketplace extensions (complete folders including package.json and dist)
COPY --from=extension-builder /app/node_modules/directus-extension-sql-query-panel /directus/extensions/sql-query-panel
COPY --from=extension-builder /app/node_modules/@directus-labs/table-view-panel /directus/extensions/table-view-panel
COPY --from=extension-builder /app/node_modules/@directus-labs/spreadsheet-layout /directus/extensions/spreadsheet-layout
COPY --from=extension-builder /app/node_modules/directus-extension-editable-layout /directus/extensions/editable-layout
COPY --from=extension-builder /app/node_modules/directus-extension-poms-selector /directus/extensions/poms-selector



# Copy database schema files
# COPY tables_up.sql /docker-entrypoint-initdb.d/01-schema.sql
# COPY materialized_view.sql /docker-entrypoint-initdb.d/02-views.sql
# COPY summary.sql /docker-entrypoint-initdb.d/03-summary.sql

# Copy uploads directory if needed
COPY uploads/ /directus/uploads/

# Set proper permissions for all copied files
RUN chown -R node:node /directus/extensions /directus/uploads

# Switch back to node user
USER node
