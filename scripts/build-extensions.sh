#!/bin/bash

# Build all Directus extensions
set -e

echo "Building Directus extensions..."

extensions=(
    "endpoint-energy-summary"
    "endpoint-sql-view" 
    "endpoint-run-battery-sim"
    "panel-energy-summary"
    "panel-sql-view"
    "panel-run-battery-sim"
    "panel-open-link"
    "interface-dropdown"
)

for ext in "${extensions[@]}"; do
    if [ -d "extensions/$ext" ]; then
        echo "Building $ext..."
        cd "extensions/$ext"
        npm ci
        npm run build
        cd ../..
        echo "✓ $ext built successfully"
    else
        echo "⚠️  Extension directory not found: extensions/$ext"
    fi
done

echo "All extensions built successfully!"