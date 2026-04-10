#!/usr/bin/env bash
set -euo pipefail

# build-and-push.sh — Build and push RadiusClaim service images to GHCR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/lib/platform-common.sh"

# Defaults
REGISTRY="${REGISTRY:-}"
TAG="${TAG:-}"
PLATFORM="${PLATFORM:-}"
DRY_RUN=false

usage() {
  cat <<USAGE
Usage: ./scripts/build-and-push.sh [options]

Builds and pushes RadiusClaim service images to GHCR (or a specified registry).

Optional:
  --registry <prefix>   Container registry/repository prefix (default: derived from git remote)
  --tag <tag>           Image tag (default: current git short SHA)
  --platform <platform> Target build platform (e.g. linux/amd64)
  --dry-run             Print what would be built/pushed without executing
  --help, -h            Show this help message
USAGE
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag)      TAG="$2";      shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true;  shift ;;
    --help|-h)  usage; exit 0 ;;
    *)
      usage >&2
      fail "Unknown flag: $1"
      ;;
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
    fail "Dockerfile not found at $DOCKERFILE"
  fi
  
  echo "Building $svc..."
  run_cmd docker build "${PLATFORM_ARGS[@]}" \
    --file "$DOCKERFILE" \
    --tag "$IMAGE" \
    "$REPO_ROOT"
  
  echo "Pushing $svc..."
  run_cmd docker push "$IMAGE"
  echo "  ✓ $IMAGE"
  echo ""
done

echo "All images pushed. To deploy locally:"
echo ""
echo "  rad deploy infra/radius/app.bicep \\"
echo "    --parameters containerRegistry=\"${REGISTRY}\" \\"
echo "    --parameters imageTag=\"${TAG}\" \\"
echo "    --parameters deploymentTarget=local"
