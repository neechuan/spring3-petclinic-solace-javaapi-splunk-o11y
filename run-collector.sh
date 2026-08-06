#!/usr/bin/env bash
#
# Run the Splunk Distribution of the OpenTelemetry Collector as a local podman
# container (gateway mode). The PetClinic app JVMs export OTLP to it
# (grpc localhost:4317 / http localhost:4318) and the collector forwards traces,
# metrics and logs to Splunk Observability Cloud for the configured realm.
#
# Credentials come from .env (SPLUNK_REALM + SPLUNK_ACCESS_TOKEN) so the token
# never appears on the command line or in `ps` output.
#
# To send the apps THROUGH this collector instead of straight to o11y cloud,
# start them with the realm unset and OTLP pointed at the collector, e.g.
#   SPLUNK_REALM= OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 ./run-otel.sh apps
#
# Usage:
#   ./run-collector.sh [up|down|status|logs]
#     up      pull (if needed) and (re)start the collector container   [default]
#     down    stop and remove the collector container
#     status  show the container state and published ports
#     logs    follow the collector logs
set -euo pipefail
cd "$(dirname "$0")"

# Load SPLUNK_REALM / SPLUNK_ACCESS_TOKEN from .env (gitignored). set -a exports
# them so `podman run -e VAR` forwards the value without printing it.
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env
  set +a
fi

CONTAINER_NAME="${SPLUNK_COLLECTOR_NAME:-splunk-otel-collector}"
IMAGE="${SPLUNK_COLLECTOR_IMAGE:-quay.io/signalfx/splunk-otel-collector:latest}"
# Bundled gateway config: receives OTLP/SAPM/SignalFx and forwards to Splunk.
SPLUNK_CONFIG_PATH="${SPLUNK_CONFIG:-/etc/otel/collector/gateway_config.yaml}"
SPLUNK_MEMORY_TOTAL_MIB="${SPLUNK_MEMORY_TOTAL_MIB:-512}"

# Shared podman network so the solace receiver can reach the broker by name
# (petclinic-solace:5672); run-all.sh attaches the broker to the same network.
PETCLINIC_NET="${PETCLINIC_NET:-petclinic-net}"
# Solace distributed-tracing overlay, merged onto the bundled gateway config so
# the collector also ingests broker spans from the #telemetry-<profile> queue.
SOLACE_OVERLAY_HOST="${SOLACE_OVERLAY:-$PWD/collector/solace-overlay.yaml}"
SOLACE_OVERLAY_CTR="/etc/otel/collector/solace-overlay.yaml"
SOLACE_TELEMETRY_USERNAME="${SOLACE_TELEMETRY_USERNAME:-otel-collector}"
SOLACE_TELEMETRY_PASSWORD="${SOLACE_TELEMETRY_PASSWORD:-otel-collector}"
SOLACE_TELEMETRY_PROFILE="${SOLACE_TELEMETRY_PROFILE:-trace}"

cmd="${1:-up}"

case "$cmd" in
  up)
    : "${SPLUNK_REALM:?set SPLUNK_REALM in .env (e.g. us1)}"
    : "${SPLUNK_ACCESS_TOKEN:?set SPLUNK_ACCESS_TOKEN in .env}"
    podman network exists "$PETCLINIC_NET" 2>/dev/null || podman network create "$PETCLINIC_NET" >/dev/null
    echo "Starting $CONTAINER_NAME (realm=$SPLUNK_REALM, gateway + solace overlay)..."
    # SPLUNK_CONFIG is intentionally NOT set: passing --config on the command line
    # takes precedence, and two --config flags are deep-merged by the collector.
    podman run -d --replace --name "$CONTAINER_NAME" \
      --restart unless-stopped \
      --network "$PETCLINIC_NET" \
      -e SPLUNK_ACCESS_TOKEN \
      -e SPLUNK_REALM \
      -e SPLUNK_MEMORY_TOTAL_MIB="$SPLUNK_MEMORY_TOTAL_MIB" \
      -e SPLUNK_LISTEN_INTERFACE=0.0.0.0 \
      -e SOLACE_TELEMETRY_USERNAME="$SOLACE_TELEMETRY_USERNAME" \
      -e SOLACE_TELEMETRY_PASSWORD="$SOLACE_TELEMETRY_PASSWORD" \
      -e SOLACE_TELEMETRY_PROFILE="$SOLACE_TELEMETRY_PROFILE" \
      -v "$SOLACE_OVERLAY_HOST:$SOLACE_OVERLAY_CTR:ro" \
      -p 4317:4317 \
      -p 4318:4318 \
      -p 13133:13133 \
      "$IMAGE" \
      --config="$SPLUNK_CONFIG_PATH" \
      --config="$SOLACE_OVERLAY_CTR"
    printf 'Waiting for collector health (http://localhost:13133) '
    for _ in $(seq 1 30); do
      if curl -fs -o /dev/null http://localhost:13133; then
        echo " ready."
        echo "Collector up. OTLP in: grpc :4317, http :4318  ->  Splunk (realm=$SPLUNK_REALM)."
        echo "Solace broker spans in from queue://#telemetry-$SOLACE_TELEMETRY_PROFILE."
        exit 0
      fi
      printf '.'; sleep 1
    done
    echo " timed out."
    echo "Collector did not report healthy; inspect with: ./run-collector.sh logs" >&2
    exit 1
    ;;
  down)
    if podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
      echo "Removed $CONTAINER_NAME."
    else
      echo "$CONTAINER_NAME is not running."
    fi
    ;;
  status)
    podman ps -a --filter "name=$CONTAINER_NAME" \
      --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    ;;
  logs)
    podman logs -f "$CONTAINER_NAME"
    ;;
  -h|--help|help)
    sed -n '2,25p' "$0"
    ;;
  *)
    echo "Usage: $0 [up|down|status|logs]" >&2
    exit 1
    ;;
esac
