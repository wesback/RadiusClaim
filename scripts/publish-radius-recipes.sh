#!/usr/bin/env bash
#
# RadiusClaim - Publish Radius recipe artifacts
#
# Publishes the repo's custom Radius recipes to an OCI registry so Radius
# environments can reference them via templatePath.
#
# Usage:
#   ./scripts/publish-radius-recipes.sh <recipe-registry> <tag>
#
# Example:
#   ./scripts/publish-radius-recipes.sh ghcr.io/wesback/radiusclaim/recipes 20260324
#
# Optional environment variables:
#   RAD_BIN - Path to the rad CLI binary (default: rad)

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <recipe-registry> <tag>"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required so the registry login used by rad bicep publish is available."
    exit 1
fi

RAD_BIN="${RAD_BIN:-rad}"
RECIPE_REGISTRY="${1%/}"
RECIPE_TAG="$2"

if ! command -v "$RAD_BIN" >/dev/null 2>&1; then
    echo "rad CLI not found at '$RAD_BIN'. Set RAD_BIN if needed."
    exit 1
fi

publish_recipe() {
    local file_path="$1"
    local artifact_name="$2"

    "$RAD_BIN" bicep publish \
        --file "$file_path" \
        --target "br:${RECIPE_REGISTRY}/${artifact_name}:${RECIPE_TAG}"
}

publish_recipe "infra/radius/recipes/azure/state-store.bicep" "state-store"
publish_recipe "infra/radius/recipes/azure/pubsub.bicep" "pubsub"
publish_recipe "infra/radius/recipes/azure/secrets.bicep" "secrets"
