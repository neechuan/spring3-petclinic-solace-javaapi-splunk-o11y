#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

MVN_BIN="${MVN_BIN:-mvn}"
TARGET="${1:-all}"

# Optional: SKIP_TESTS=true ./rebuild-apps.sh all
MAVEN_ARGS=()
if [ "${SKIP_TESTS:-false}" = "true" ]; then
  MAVEN_ARGS+=("-DskipTests")
fi

build_backend() {
  echo "Building backend..."
  "$MVN_BIN" -f backend/pom.xml clean package "${MAVEN_ARGS[@]}"
}

build_frontend() {
  echo "Building frontend..."
  "$MVN_BIN" -f frontend/pom.xml clean package "${MAVEN_ARGS[@]}"
}

case "$TARGET" in
  backend)
    build_backend
    ;;
  frontend)
    build_frontend
    ;;
  all)
    build_backend
    build_frontend
    ;;
  *)
    echo "Usage: $0 [backend|frontend|all]"
    exit 1
    ;;
esac

echo "Build complete."
