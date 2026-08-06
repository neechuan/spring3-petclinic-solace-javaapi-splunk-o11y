#!/usr/bin/env bash
#
# Start the Solace PetClinic stack with the Splunk Distribution of OpenTelemetry
# Java agent attached.
#
# Unlike run-all.sh (which runs the apps via `mvn spring-boot:run`), this script
# launches the packaged Spring Boot fat jars directly so each app is its own JVM
# with the OpenTelemetry -javaagent bootstrapped. That gives clean per-JVM
# service separation in Splunk APM and a clean PID-based shutdown.
#
# Targets:
#   solace     Solace PubSub+ broker  (delegated to ./run-all.sh solace)
#   backend    persistence + JCSMP replier   (http://localhost:8081)
#   frontend   UI + JCSMP requestor          (http://localhost:8080)
#   apps       backend + frontend (no broker)
#   all        solace + backend + frontend   (default)
#
# A single requested app runs in the foreground with live logs (Ctrl+C stops
# it). Multiple apps run in the background (logs in ./logs) and are stopped
# together with Ctrl+C. The broker always runs detached - stop everything with
# ./stop-all.sh (it stops by port, so it works for jar-launched apps too).
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

# ===========================================================================
# Splunk OpenTelemetry Java agent configuration
# Every value can be overridden from the environment, e.g.
#   OTEL_SERVICE_NAME=my-app ./run-otel.sh
# Set OTEL_ENABLED=false to run the jars without the agent.
# ===========================================================================
OTEL_ENABLED="${OTEL_ENABLED:-true}"
OTEL_AGENT_JAR="${OTEL_AGENT_JAR:-splunk-otel-javaagent.jar}"
# Telemetry always flows: Java agent --OTLP--> local Splunk OTel Collector -->
# Splunk Observability Cloud. The realm + org access token belong to the
# COLLECTOR (see run-collector.sh / .env), NOT the agent; they are read here only
# to show the ultimate cloud destination in the log lines below.
SPLUNK_REALM="${SPLUNK_REALM:-}"
SPLUNK_ACCESS_TOKEN="${SPLUNK_ACCESS_TOKEN:-}"
# Where the agent ships OTLP: the local collector. Port 4318 is the OTLP/HTTP
# receiver, so the protocol must be http/protobuf (use port 4317 + grpc for the
# OTLP/gRPC receiver instead).
OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"
OTEL_EXPORTER_OTLP_PROTOCOL="${OTEL_EXPORTER_OTLP_PROTOCOL:-http/protobuf}"
# Log export is OFF by default: Splunk Observability Cloud only ingests logs with
# Log Observer (a valid HEC url+token), otherwise the collector's splunk_hec
# exporter 404s on /v1/log and drops them. Set OTEL_LOGS_EXPORTER=otlp to ship
# logs once a working SPLUNK_HEC_URL/SPLUNK_HEC_TOKEN is wired into the collector.
OTEL_LOGS_EXPORTER="${OTEL_LOGS_EXPORTER:-none}"
OTEL_RESOURCE_ATTRIBUTES="${OTEL_RESOURCE_ATTRIBUTES:-deployment.environment=lab,service.version=1.0}"
# Base service name; each app JVM reports as its own service (one per tier).
OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-gary-petclinic-solace}"
OTEL_BACKEND_SERVICE="${OTEL_BACKEND_SERVICE:-${OTEL_SERVICE_NAME}-backend}"
OTEL_FRONTEND_SERVICE="${OTEL_FRONTEND_SERVICE:-${OTEL_SERVICE_NAME}-frontend}"
# Human-readable telemetry destination for log lines (token is never printed).
# The agent always targets the collector; the realm (if known) is appended so
# the operator can see where the collector will forward the data.
if [ -n "$SPLUNK_REALM" ]; then
  OTEL_DEST="$OTEL_EXPORTER_OTLP_ENDPOINT ($OTEL_EXPORTER_OTLP_PROTOCOL) -> Splunk OTel Collector -> o11y cloud (realm=$SPLUNK_REALM)"
else
  OTEL_DEST="$OTEL_EXPORTER_OTLP_ENDPOINT ($OTEL_EXPORTER_OTLP_PROTOCOL) -> Splunk OTel Collector"
fi
# ===========================================================================

usage() {
  cat <<'EOF'
Usage: ./run-otel.sh [target ...]

Targets:
  solace     Start the Solace PubSub+ broker (detached container)
  backend    Start the backend  (persistence + replier, http://localhost:8081)
  frontend   Start the frontend (UI + requestor,        http://localhost:8080)
  apps       Start backend then frontend (no broker)
  all        Start solace, backend and frontend (default)
  build      Force a `mvn package` rebuild of the jars before starting

Examples:
  ./run-otel.sh                 # broker + both apps, OTel agent attached
  ./run-otel.sh apps            # backend then frontend (broker already up)
  ./run-otel.sh backend         # just the backend (live logs; Ctrl+C to stop)
  OTEL_ENABLED=false ./run-otel.sh apps   # run without the agent
  ./run-collector.sh up                   # start the collector the agent ships to

Stop everything with ./stop-all.sh (stops by port; works for these jars too).
EOF
}

# ---- parse targets ---------------------------------------------------------
want_solace=0 want_backend=0 want_frontend=0 force_build=0
targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(all)
for t in "${targets[@]}"; do
  case "$t" in
    all)      want_solace=1; want_backend=1; want_frontend=1 ;;
    apps)     want_backend=1; want_frontend=1 ;;
    solace)   want_solace=1 ;;
    backend)  want_backend=1 ;;
    frontend) want_frontend=1 ;;
    build)    force_build=1 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "error: unknown target '$t'" >&2; usage; exit 1 ;;
  esac
done

# ---- resolve a JRE to run the jars -----------------------------------------
# Prefer the bundled Azul Zulu 17.0.19 JRE in ./jre (matches the apps' Java 17
# target and is supported by the Splunk OpenTelemetry Java agent). `java` is not
# on PATH on this machine. Set JAVA_HOME to override the bundled runtime.
if [ -x "$PWD/jre/bin/java" ]; then
  JAVA_BIN="$PWD/jre/bin/java"
elif [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA_BIN="$JAVA_HOME/bin/java"
elif JH=$(/usr/libexec/java_home -v 17 2>/dev/null); then
  JAVA_BIN="$JH/bin/java"
elif JH=$(/usr/libexec/java_home 2>/dev/null); then
  JAVA_BIN="$JH/bin/java"
elif command -v java >/dev/null 2>&1; then
  JAVA_BIN=java
else
  echo "error: no JRE found (expected ./jre/bin/java or set JAVA_HOME)." >&2
  exit 1
fi
echo "Java runtime: $JAVA_BIN"

if [ "$OTEL_ENABLED" = "true" ] && [ ! -f "$OTEL_AGENT_JAR" ]; then
  echo "error: Splunk OpenTelemetry agent jar not found: $OTEL_AGENT_JAR" >&2
  echo "       set OTEL_AGENT_JAR or OTEL_ENABLED=false." >&2
  exit 1
fi

# Telemetry is forwarded by the local Splunk OTel Collector, which owns the realm
# + access token (validated in run-collector.sh). The agent only needs that
# collector reachable on OTEL_EXPORTER_OTLP_ENDPOINT, so make sure it is up.
COLLECTOR_HEALTH_URL="${COLLECTOR_HEALTH_URL:-http://localhost:13133}"
ensure_collector() {
  curl -fs -o /dev/null "$COLLECTOR_HEALTH_URL" && return 0
  if [ -x ./run-collector.sh ]; then
    echo "Splunk OTel Collector not reachable at $COLLECTOR_HEALTH_URL; starting it..."
    ./run-collector.sh up
  else
    echo "warning: no collector at $COLLECTOR_HEALTH_URL and ./run-collector.sh is missing;" >&2
    echo "         agent OTLP to $OTEL_EXPORTER_OTLP_ENDPOINT will be dropped until one is up." >&2
  fi
}

LOG_DIR=logs
mkdir -p "$LOG_DIR"
pids=()

cleanup() {
  echo
  echo "Stopping app(s)..."
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo "Done. The Solace broker is still running (stop it with ./stop-all.sh solace)."
}

wait_for_http() { # <name> <url>
  local name=$1 url=$2 i
  printf 'Waiting for %s ' "$name"
  for i in $(seq 1 90); do
    if curl -fs -o /dev/null "$url"; then echo " ready."; return 0; fi
    printf '.'; sleep 2
  done
  echo " timed out (continuing anyway)."
}

# resolve_jar <dir> - echo the repackaged fat jar (not the *.jar.original)
resolve_jar() {
  local dir=$1
  ls "$dir"/target/*.jar 2>/dev/null | grep -v '\.original$' | head -1 || true
}

# ensure_built <name> <dir> - echo the runnable jar, building it if needed
ensure_built() {
  local name=$1 dir=$2 jar
  jar=$(resolve_jar "$dir")
  if [ -z "$jar" ] || [ "$force_build" -eq 1 ]; then
    echo "Building $name ..." >&2
    mvn -q -f "$dir/pom.xml" -DskipTests package >&2
    jar=$(resolve_jar "$dir")
  fi
  [ -n "$jar" ] || { echo "error: no jar built for $name" >&2; exit 1; }
  printf '%s' "$jar"
}

# build_java_cmd <service> <jar> - populate the global JAVA_CMD array
build_java_cmd() {
  local service=$1 jar=$2
  JAVA_CMD=("$JAVA_BIN")
  if [ "$OTEL_ENABLED" = "true" ]; then
    JAVA_CMD+=(
      "-javaagent:$OTEL_AGENT_JAR"
      "-Dotel.service.name=$service"
      "-Dotel.resource.attributes=$OTEL_RESOURCE_ATTRIBUTES"
    )
    # Always export OTLP to the local collector; it forwards to o11y cloud.
    # splunk.realm=none is required: a realm (even one leaked via the SPLUNK_REALM
    # env var from .env) makes the agent ship traces/metrics STRAIGHT to o11y
    # cloud and ignore otel.exporter.otlp.endpoint. Forcing 'none' keeps all
    # signals on the OTLP path to the collector.
    JAVA_CMD+=(
      "-Dsplunk.realm=none"
      "-Dotel.exporter.otlp.endpoint=$OTEL_EXPORTER_OTLP_ENDPOINT"
      "-Dotel.exporter.otlp.protocol=$OTEL_EXPORTER_OTLP_PROTOCOL"
      "-Dotel.logs.exporter=$OTEL_LOGS_EXPORTER"
    )
  fi
  JAVA_CMD+=(-jar "$jar")
}

# start_app_bg <name> <dir> <url> <service> - background jar + agent, wait for HTTP
start_app_bg() {
  local name=$1 dir=$2 url=$3 service=$4 jar
  jar=$(ensure_built "$name" "$dir")
  build_java_cmd "$service" "$jar"
  echo "Starting $name (log: $LOG_DIR/$name.log)..."
  "${JAVA_CMD[@]}" > "$LOG_DIR/$name.log" 2>&1 &
  pids+=($!)
  wait_for_http "$name" "$url"
}

# run_app_fg <name> <dir> <service> - replace this process (Ctrl+C stops the app)
run_app_fg() {
  local name=$1 dir=$2 service=$3 jar
  jar=$(ensure_built "$name" "$dir")
  build_java_cmd "$service" "$jar"
  echo "Starting $name in the foreground (Ctrl+C to stop)..."
  [ "$OTEL_ENABLED" = "true" ] && \
    echo "Splunk OTel: service='$service' -> $OTEL_DEST"
  exec "${JAVA_CMD[@]}"
}

# ---- act, in canonical order: solace, backend, frontend --------------------
[ $want_solace -eq 1 ] && ./run-all.sh solace

# Enable broker distributed tracing so the collector's solace receiver gets broker
# spans. Idempotent; needs the broker SEMP API up. Non-fatal for the apps if it fails.
if [ $want_solace -eq 1 ] && [ -x ./configure-solace-tracing.sh ]; then
  ./configure-solace-tracing.sh || \
    echo "warning: Solace tracing config failed; broker spans may not flow (apps unaffected)." >&2
fi

if [ "$OTEL_ENABLED" = "true" ]; then
  echo "Splunk OpenTelemetry agent ENABLED: service='$OTEL_SERVICE_NAME' -> $OTEL_DEST"
else
  echo "Splunk OpenTelemetry agent DISABLED (OTEL_ENABLED=$OTEL_ENABLED)."
fi

java_count=$((want_backend + want_frontend))

if [ "$java_count" -eq 0 ]; then
  [ $want_solace -eq 1 ] && \
    echo "Solace Manager UI : http://localhost:8088/  (admin / admin)"
  exit 0
fi

# Apps run with the agent attached, which forwards through the collector.
[ "$OTEL_ENABLED" = "true" ] && ensure_collector

if [ "$java_count" -eq 1 ]; then
  if [ $want_backend -eq 1 ]; then
    run_app_fg backend backend "$OTEL_BACKEND_SERVICE"
  else
    run_app_fg frontend frontend "$OTEL_FRONTEND_SERVICE"
  fi
fi

# Two or more apps: background them and wait together.
trap cleanup INT TERM
[ $want_backend -eq 1 ]  && start_app_bg backend  backend  "http://localhost:8081/actuator/health" "$OTEL_BACKEND_SERVICE"
[ $want_frontend -eq 1 ] && start_app_bg frontend frontend "http://localhost:8080/actuator/health" "$OTEL_FRONTEND_SERVICE"

echo
echo "Services are up:"
[ $want_frontend -eq 1 ] && echo "  PetClinic UI      : http://localhost:8080/"
[ $want_backend -eq 1 ]  && echo "  Backend health    : http://localhost:8081/actuator/health"
[ $want_solace -eq 1 ]   && echo "  Solace Manager UI : http://localhost:8088/  (admin / admin)"
[ "$OTEL_ENABLED" = "true" ] && \
  echo "  Splunk OTel       : services '$OTEL_BACKEND_SERVICE' + '$OTEL_FRONTEND_SERVICE' -> $OTEL_DEST"
echo
echo "Logs in $LOG_DIR/. Press Ctrl+C to stop the app(s)."
wait
