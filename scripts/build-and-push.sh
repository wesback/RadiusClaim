#!/usr/bin/env bash
set -euo pipefail

# build-and-push.sh — Build and push RadiusClaim service images to GHCR
# Usage: ./scripts/build-and-push.sh [--registry PREFIX] [--tag TAG] [--platform PLATFORM]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
REGISTRY="${REGISTRY:-}"
TAG="${TAG:-}"
PLATFORM="${PLATFORM:-}"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag)      TAG="$2";      shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Derive registry from git remote if not provided
if [[ -z "$REGISTRY" ]]; then
  REMOTE_URL=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
  REPO_OWNER=$(echo "$REMOTE_URL" | sed -E 's|.*[:/]([^/]+)/[^/]+\.git.*|\1|' | tr '[:upper:]' '[:lower:]')
  REPO_NAME=$(echo "$REMOTE_URL" | sed -E 's|.*[:/][^/]+/([^/]+)\.git.*|\1|' | tr '[:upper:]' '[:lower:]')
  REGISTRY="ghcr.io/${REPO_OWNER}/${REPO_NAME}"
fi

# Derive tag from git short SHA if not provided
if [[ -z "$TAG" ]]; then
  TAG=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
fi

PLATFORM_ARGS=()
if [[ -n "$PLATFORM" ]]; then
  PLATFORM_ARGS=(--platform "$PLATFORM")
fi

SERVICES=(expense-api workflow-engine notification-svc)

echo "Registry: $REGISTRY"
echo "Tag:      $TAG"
echo ""

for svc in "${SERVICES[@]}"; do
  IMAGE="${REGISTRY}/${svc}:${TAG}"
  DOCKERFILE="${REPO_ROOT}/src/${svc}/Dockerfile"
  
  if [[ ! -f "$DOCKERFILE" ]]; then
    echo "ERROR: Dockerfile not found at $DOCKERFILE" >&2
    exit 1
  fi
  
  echo "Building $svc..."
  docker build "${PLATFORM_ARGS[@]}" \
    --file "$DOCKERFILE" \
    --tag "$IMAGE" \
    "$REPO_ROOT"
  
  echo "Pushing $svc..."
  docker push "$IMAGE"
  echo "  ✓ $IMAGE"
  echo ""
done

echo "All images pushed. To deploy locally:"
echo ""
echo "  rad deploy infra/radius/app.bicep \\"
echo "    --parameters containerRegistry=\"${REGISTRY}\" \\"
echo "    --parameters imageTag=\"${TAG}\" \\"
echo "    --parameters deploymentTarget=local"
