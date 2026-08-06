#!/usr/bin/env bash
# Run the k6 browser CRUD test suite against the PetClinic frontend.
# Usage: ./tests/k6/run-crud-test.sh [BASE_URL]
#   ./tests/k6/run-crud-test.sh                       # http://localhost:8080
#   ./tests/k6/run-crud-test.sh http://localhost:8080
#   HEADFUL=1 ./tests/k6/run-crud-test.sh             # show the browser window
set -euo pipefail

BASE_URL="${1:-${BASE_URL:-http://localhost:8080}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FILE="${SCRIPT_DIR}/petclinic-crud.browser.js"

command -v k6 >/dev/null 2>&1 || { echo "ERROR: k6 is not installed (brew install k6)"; exit 1; }

echo "Checking frontend at ${BASE_URL} ..."
code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/" || echo 000)"
if [[ "${code}" != "200" ]]; then
  echo "ERROR: frontend not reachable at ${BASE_URL} (HTTP ${code}). Start it first (e.g. ./run-otel.sh apps)." >&2
  exit 1
fi

export BASE_URL
[[ "${HEADFUL:-0}" == "1" ]] && export K6_BROWSER_HEADLESS=false

echo "Running k6 browser CRUD suite ..."
exec k6 run "${TEST_FILE}"
