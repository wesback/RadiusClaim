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
#   ./scripts/publish-radius-recipes.sh ghcr.io/wesback/radiusclaim/recipes 20260326
#
# Optional environment variables:
#   RAD_BIN                 - Path to the rad CLI binary (default: rad)
#   GHCR_TOKEN              - GitHub personal access token or GITHUB_TOKEN for ghcr.io auth
#   GHCR_USERNAME           - GitHub username for ghcr.io auth (aliases: GITHUB_USERNAME, GITHUB_ACTOR, or git config user.name)
#   GITHUB_USERNAME         - Alias for GHCR_USERNAME (accepted for compatibility)
#   REGISTRY_USERNAME       - Generic registry username (for non-GHCR registries)
#   REGISTRY_PASSWORD       - Generic registry password (for non-GHCR registries)
#
# GHCR Authentication:
#   For ghcr.io registries, this script will attempt docker login using:
#   1. GHCR_TOKEN + GHCR_USERNAME (or GITHUB_USERNAME) if set
#   2. Existing docker credential store (if already logged in)
#   3. Fail with actionable message if neither available
#
# Non-GHCR Authentication:
#   For other registries, set REGISTRY_USERNAME and REGISTRY_PASSWORD, or
#   ensure docker is already authenticated via 'docker login <registry>'

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <recipe-registry> <tag>"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is required so the registry login used by rad bicep publish is available."
    exit 1
fi

RAD_BIN="${RAD_BIN:-rad}"
RECIPE_REGISTRY="${1%/}"
RECIPE_TAG="$2"

if ! command -v "$RAD_BIN" >/dev/null 2>&1; then
    echo "Error: rad CLI not found at '$RAD_BIN'. Set RAD_BIN if needed."
    exit 1
fi

# Extract the registry hostname from the recipe registry path
# Example: ghcr.io/owner/radiusclaim/recipes → ghcr.io
REGISTRY_HOST="${RECIPE_REGISTRY%%/*}"

# Attempt GHCR authentication if target is ghcr.io and credentials are available
if [[ "$REGISTRY_HOST" == "ghcr.io" ]]; then
    if [ -n "${GHCR_TOKEN:-}" ]; then
        # Accept either GHCR_USERNAME or GITHUB_USERNAME for compatibility
        GHCR_USERNAME="${GHCR_USERNAME:-${GITHUB_USERNAME:-${GITHUB_ACTOR:-$(git config user.name 2>/dev/null || echo "")}}}"
        if [ -z "$GHCR_USERNAME" ]; then
            echo "Error: GHCR_TOKEN is set but username could not be determined."
            echo "Set GHCR_USERNAME or GITHUB_USERNAME explicitly, or ensure 'git config user.name' is configured."
            exit 1
        fi

        echo "Authenticating to ghcr.io as '${GHCR_USERNAME}'..."
        if ! echo "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin 2>/dev/null; then
            echo "Error: docker login to ghcr.io failed."
            echo "Verify GHCR_TOKEN has 'write:packages' scope and GHCR_USERNAME is correct."
            exit 1
        fi
        echo "Successfully authenticated to ghcr.io"
    else
        # Check if already authenticated to ghcr.io via credential store
        local cred_store
        cred_store="$(docker info -f '{{.CredentialsStore}}' 2>/dev/null || true)"
        local already_authed=false
        if [ -n "$cred_store" ]; then
            if docker-credential-"${cred_store}" list 2>/dev/null | grep -q "ghcr.io"; then
                already_authed=true
            fi
        fi
        if [ "$already_authed" = false ]; then
            echo "Warning: Publishing to ghcr.io but no GHCR_TOKEN found and docker may not be authenticated."
            echo ""
            echo "To authenticate, choose one of:"
            echo "  1. Set GHCR_TOKEN (and optionally GHCR_USERNAME) and re-run this script"
            echo "  2. Run 'echo \$TOKEN | docker login ghcr.io --username YOUR_GITHUB_USERNAME --password-stdin'"
            echo "  3. Run 'docker login ghcr.io' and provide credentials interactively"
            echo ""
            echo "If you're already authenticated, you can ignore this warning."
            echo "Publishing will proceed and fail clearly if authentication is actually missing."
            echo ""
        fi
    fi
elif [ -n "${REGISTRY_USERNAME:-}" ] && [ -n "${REGISTRY_PASSWORD:-}" ]; then
    # Generic registry authentication
    echo "Authenticating to ${REGISTRY_HOST}..."
    if ! echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_HOST" --username "$REGISTRY_USERNAME" --password-stdin 2>/dev/null; then
        echo "Error: docker login to ${REGISTRY_HOST} failed."
        echo "Verify REGISTRY_USERNAME and REGISTRY_PASSWORD are correct."
        exit 1
    fi
    echo "Successfully authenticated to ${REGISTRY_HOST}"
fi

publish_recipe() {
    local file_path="$1"
    local artifact_name="$2"
    local target="br:${RECIPE_REGISTRY}/${artifact_name}:${RECIPE_TAG}"

    echo "Publishing ${artifact_name} to ${target}..."
    if ! "$RAD_BIN" bicep publish --file "$file_path" --target "$target" 2>&1; then
        echo ""
        echo "Error: Failed to publish recipe artifact '${artifact_name}'."
        echo ""
        if [[ "$REGISTRY_HOST" == "ghcr.io" ]]; then
            echo "Common GHCR publish failures:"
            echo "  1. 403 Forbidden: Not authenticated or token lacks 'write:packages' scope"
            echo "     → Set GHCR_TOKEN with a GitHub PAT that has 'write:packages' scope"
            echo "     → Or run: echo \$TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin"
            echo ""
            echo "  2. 403 Forbidden: Package exists but you don't have write access"
            echo "     → Ensure the package namespace matches your GitHub username/org"
            echo "     → Verify '${RECIPE_REGISTRY}' is under your control"
            echo ""
            echo "  3. Package is private and pull auth will be needed later"
            echo "     → Make the package public in GitHub Package settings, or"
            echo "     → Configure imagePullSecrets for the Kubernetes namespace"
        else
            echo "Ensure you are authenticated to '${REGISTRY_HOST}':"
            echo "  → Set REGISTRY_USERNAME and REGISTRY_PASSWORD, or"
            echo "  → Run 'docker login ${REGISTRY_HOST}' manually"
        fi
        echo ""
        return 1
    fi
    echo "Successfully published ${artifact_name}"
}

echo "Publishing Radius recipes to ${RECIPE_REGISTRY}:${RECIPE_TAG}"
echo ""

publish_recipe "infra/radius/recipes/azure/state-store.bicep" "state-store"
publish_recipe "infra/radius/recipes/azure/pubsub.bicep" "pubsub"
publish_recipe "infra/radius/recipes/azure/secrets.bicep" "secrets"

echo ""
echo "All recipes published successfully to ${RECIPE_REGISTRY}:${RECIPE_TAG}"
