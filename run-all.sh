#!/usr/bin/env bash
#
# Start the Solace PetClinic stack, all together or one service at a time:
#   solace     Solace PubSub+ broker  (detached container)
#   backend    persistence + JCSMP replier   (http://localhost:8081)
#   frontend   UI + JCSMP requestor          (http://localhost:8080)
#   all        solace + backend + frontend   (default)
#
# A single requested app runs in the foreground with live logs (Ctrl+C stops
# it). Multiple apps run in the background (logs in ./logs) and are stopped
# together with Ctrl+C. The broker always runs detached - stop it with:
#   ./stop-all.sh solace
set -euo pipefail
cd "$(dirname "$0")"

# Load local config/secrets from .env if present (keeps SPLUNK_ACCESS_TOKEN out
# of this script and out of git - see .gitignore). set -a exports every value.
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env
  set +a
fi

usage() {
  cat <<'EOF'
Usage: ./run-all.sh [target ...]

Targets:
  solace     Start the Solace PubSub+ broker (detached container)
  backend    Start the backend  (persistence + replier, http://localhost:8081)
  frontend   Start the frontend (UI + requestor,        http://localhost:8080)
  apps       Start backend then frontend (no broker)
  all        Start solace, backend and frontend (default)

Examples:
  ./run-all.sh                 # start everything
  ./run-all.sh solace          # just the broker
  ./run-all.sh backend         # just the backend (live logs; Ctrl+C to stop)
  ./run-all.sh apps            # backend then frontend
  ./run-all.sh solace backend  # broker + backend
EOF
}

# Prefer the bundled Maven wrapper if it is configured, otherwise system mvn.
if [ -x ./mvnw ] && [ -f .mvn/wrapper/maven-wrapper.properties ]; then
  MVN=./mvnw
elif command -v mvn >/dev/null 2>&1; then
  MVN=mvn
else
  echo "error: no working ./mvnw wrapper and 'mvn' is not on PATH." >&2
  exit 1
fi

# ---- parse targets ---------------------------------------------------------
want_solace=0 want_backend=0 want_frontend=0
targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(all)
for t in "${targets[@]}"; do
  case "$t" in
    all)      want_solace=1; want_backend=1; want_frontend=1 ;;
    apps)     want_backend=1; want_frontend=1 ;;
    solace)   want_solace=1 ;;
    backend)  want_backend=1 ;;
    frontend) want_frontend=1 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "error: unknown target '$t'" >&2; usage; exit 1 ;;
  esac
done

LOG_DIR=logs
mkdir -p "$LOG_DIR"
pids=()

wait_for_http() { # <name> <url>
  local name=$1 url=$2 i
  printf 'Waiting for %s ' "$name"
  for i in $(seq 1 90); do
    if curl -fs -o /dev/null "$url"; then echo " ready."; return 0; fi
    printf '.'; sleep 2
  done
  echo " timed out (continuing anyway)."
}

run_solace() {
  local name="${SOLACE_CONTAINER:-petclinic-solace}"
  local image="${SOLACE_IMAGE:-docker.io/solace/solace-pubsub-standard:latest}"
  local net="${PETCLINIC_NET:-petclinic-net}"
  # Shared network so the Splunk OTel collector can reach the broker's AMQP port
  # by name (petclinic-solace:5672) for the Solace distributed-tracing receiver.
  podman network exists "$net" 2>/dev/null || podman network create "$net" >/dev/null
  if podman container exists "$name"; then
    podman start "$name"
    # Attach an already-created broker to the shared network (no recreate needed).
    podman network connect "$net" "$name" 2>/dev/null || true
  else
    # Port 55554 -> broker 55555 (SMF): host TCP 55555 is reserved on some
    # machines by Cisco Secure Client, so the SMF port is published as 55554.
    # 8088 -> 8080 keeps the PubSub+ Manager UI off the frontend's port 8080.
    # Solace POST requires a hard nofile limit of 1048576 and >=2.42 GiB of memory.
    podman run -d --name "$name" --hostname solace \
      --network "$net" \
      --shm-size=2g --ulimit core=-1 --ulimit nofile=2448:1048576 -m 3500m \
      -p 55554:55555 \
      -p 8008:8008 \
      -p 1943:1943 \
      -p 8088:8080 \
      -e username_admin_globalaccesslevel=admin \
      -e username_admin_password=admin \
      -e system_scaling_maxconnectioncount=100 \
      "$image"
  fi
  echo "Solace broker '$name' starting (SMF tcp://localhost:55554, UI http://localhost:8088 admin/admin)."
  printf 'Waiting for Solace SMF (55554) '
  for i in $(seq 1 60); do
    if nc -z localhost 55554 2>/dev/null; then echo " open."; break; fi
    printf '.'; sleep 2
  done
}

# start_app_bg <name> <pom-dir> <health-url>
start_app_bg() {
  local name=$1 dir=$2 url=$3
  echo "Starting $name (log: $LOG_DIR/$name.log)..."
  # fork=false keeps the app in this Maven process so Ctrl+C stops it cleanly.
  MAVEN_OPTS="${MAVEN_OPTS:-}" \
    $MVN -q -f "$dir/pom.xml" -Dspring-boot.run.fork=false spring-boot:run \
    > "$LOG_DIR/$name.log" 2>&1 &
  pids+=($!)
  wait_for_http "$name" "$url"
}

# run_app_fg <name> <pom-dir>  (replaces this process; Ctrl+C stops the app)
run_app_fg() {
  local name=$1 dir=$2
  echo "Starting $name in the foreground (Ctrl+C to stop)..."
  export MAVEN_OPTS="${MAVEN_OPTS:-}"
  exec $MVN -f "$dir/pom.xml" -Dspring-boot.run.fork=false spring-boot:run
}

# ---- act, in canonical order: solace, backend, frontend --------------------
[ $want_solace -eq 1 ] && run_solace

java_count=$((want_backend + want_frontend))

if [ "$java_count" -eq 0 ]; then
  [ $want_solace -eq 1 ] && \
    echo "Solace Manager UI : http://localhost:8088/  (admin / admin)"
  exit 0
fi

if [ "$java_count" -eq 1 ]; then
  if [ $want_backend -eq 1 ]; then
    run_app_fg backend backend
  else
    run_app_fg frontend frontend
  fi
fi

# Two or more apps: background them and wait together.
trap cleanup INT TERM
[ $want_backend -eq 1 ]  && start_app_bg backend  backend  "http://localhost:8081/actuator/health"
[ $want_frontend -eq 1 ] && start_app_bg frontend frontend "http://localhost:8080/actuator/health"

echo
echo "Services are up:"
[ $want_frontend -eq 1 ] && echo "  PetClinic UI      : http://localhost:8080/"
[ $want_backend -eq 1 ]  && echo "  Backend health    : http://localhost:8081/actuator/health"
[ $want_solace -eq 1 ]   && echo "  Solace Manager UI : http://localhost:8088/  (admin / admin)"
echo
echo "Logs in $LOG_DIR/. Press Ctrl+C to stop the app(s)."
wait
