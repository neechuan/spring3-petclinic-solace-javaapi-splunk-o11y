#!/usr/bin/env bash
#
# Run a minimal Prometheus container for local Solace + collector monitoring.
#
# Usage:
#   ./run-prometheus.sh [up|down|status|logs]
#     up      start or replace Prometheus container   [default]
#     down    stop and remove Prometheus container
#     status  show the container state and published ports
#     logs    follow Prometheus logs
#
set -euo pipefail
cd "$(dirname "$0")"

PROMETHEUS_CONTAINER_NAME="${PROMETHEUS_CONTAINER_NAME:-petclinic-prometheus}"
PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-docker.io/prom/prometheus:v2.55.1}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
PETCLINIC_NET="${PETCLINIC_NET:-petclinic-net}"

PROMETHEUS_CONFIG_HOST="${PROMETHEUS_CONFIG:-$PWD/prometheus/prometheus.yml}"
PROMETHEUS_CONFIG_CTR="/etc/prometheus/prometheus.yml"
PROMETHEUS_DATA_DIR="${PROMETHEUS_DATA_DIR:-$PWD/prometheus/data}"

cmd="${1:-up}"

case "$cmd" in
  up)
    if [ ! -f "$PROMETHEUS_CONFIG_HOST" ]; then
      echo "error: Prometheus config not found: $PROMETHEUS_CONFIG_HOST" >&2
      exit 1
    fi
    mkdir -p "$PROMETHEUS_DATA_DIR"
    podman network exists "$PETCLINIC_NET" 2>/dev/null || podman network create "$PETCLINIC_NET" >/dev/null

    echo "Starting $PROMETHEUS_CONTAINER_NAME (port=$PROMETHEUS_PORT, network=$PETCLINIC_NET)..."
    podman run -d --replace --name "$PROMETHEUS_CONTAINER_NAME" \
      --restart unless-stopped \
      --network "$PETCLINIC_NET" \
      -p "$PROMETHEUS_PORT:9090" \
      -v "$PROMETHEUS_CONFIG_HOST:$PROMETHEUS_CONFIG_CTR:ro" \
      -v "$PROMETHEUS_DATA_DIR:/prometheus" \
      "$PROMETHEUS_IMAGE" \
      --config.file="$PROMETHEUS_CONFIG_CTR" \
      --storage.tsdb.path=/prometheus \
      --web.enable-lifecycle

    printf 'Waiting for Prometheus readiness (http://localhost:%s/-/ready) ' "$PROMETHEUS_PORT"
    for _ in $(seq 1 30); do
      if curl -fs -o /dev/null "http://localhost:$PROMETHEUS_PORT/-/ready"; then
        echo " ready."
        echo "Prometheus UI: http://localhost:$PROMETHEUS_PORT"
        echo "Targets page:  http://localhost:$PROMETHEUS_PORT/targets"
        exit 0
      fi
      printf '.'; sleep 1
    done
    echo " timed out."
    echo "Prometheus did not report ready; inspect with: ./run-prometheus.sh logs" >&2
    exit 1
    ;;
  down)
    if podman rm -f "$PROMETHEUS_CONTAINER_NAME" >/dev/null 2>&1; then
      echo "Removed $PROMETHEUS_CONTAINER_NAME."
    else
      echo "$PROMETHEUS_CONTAINER_NAME is not running."
    fi
    ;;
  status)
    podman ps -a --filter "name=$PROMETHEUS_CONTAINER_NAME" \
      --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    ;;
  logs)
    podman logs -f "$PROMETHEUS_CONTAINER_NAME"
    ;;
  -h|--help|help)
    sed -n '2,11p' "$0"
    ;;
  *)
    echo "Usage: $0 [up|down|status|logs]" >&2
    exit 1
    ;;
esac
