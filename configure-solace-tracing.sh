#!/usr/bin/env bash
#
# Enable Solace distributed tracing on the PetClinic broker so it emits broker
# receive/send spans to the #telemetry-<profile> queue that the Splunk OTel
# Collector's `solace` receiver consumes (see collector/solace-overlay.yaml).
#
# Idempotent: safe to re-run. Drives the broker's SEMPv2 config API (admin/admin)
# over the PubSub+ Manager port. Distributed tracing runs in 7-day demo mode on
# the software broker (no product key required).
#
# NOTE: Solace only generates broker trace events for guaranteed OR "promoted
# direct" messages -- a pure direct message is traced only when a queue/endpoint
# also attracts (spools) it. The PetClinic RPC is pure direct request/reply, so a
# small TTL-bounded promotion queue subscribed to petclinic/rpc/> is created below
# to promote those direct messages; without it the broker emits zero spans.
#
# Usage: ./configure-solace-tracing.sh
set -euo pipefail
cd "$(dirname "$0")"

# Reuse the same .env the other scripts read (telemetry receiver creds live here).
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env
  set +a
fi

SEMP_URL="${SOLACE_SEMP_URL:-http://localhost:8088/SEMP/v2/config}"
SEMP_USER="${SOLACE_SEMP_USER:-admin}"
SEMP_PASS="${SOLACE_SEMP_PASS:-admin}"
VPN="${SOLACE_VPN:-default}"
PROFILE="${SOLACE_TELEMETRY_PROFILE:-trace}"
FILTER="${SOLACE_TRACE_FILTER:-petclinic}"
SUBSCRIPTION="${SOLACE_TRACE_SUBSCRIPTION:-petclinic/rpc/>}"
RECV_USER="${SOLACE_TELEMETRY_USERNAME:-otel-collector}"
RECV_PASS="${SOLACE_TELEMETRY_PASSWORD:-otel-collector}"
# The PetClinic apps' Solace credentials (see backend/frontend application.properties).
# They must have a password once the VPN switches to internal basic auth (below).
APP_USER="${SOLACE_APP_USERNAME:-default}"
APP_PASS="${SOLACE_APP_PASSWORD:-default}"
# Promotion queue that spools (promotes) the pure-direct RPC messages so the
# broker generates spans for them. TTL-bounded so it never accumulates.
PROMOTE_QUEUE="${SOLACE_TRACE_PROMOTE_QUEUE:-q-petclinic-trace}"
PROMOTE_TTL="${SOLACE_TRACE_PROMOTE_TTL:-10}"           # seconds; messages auto-expire
PROMOTE_SPOOL_MB="${SOLACE_TRACE_PROMOTE_SPOOL_MB:-50}" # hard spool cap (MB)

# semp <METHOD> <PATH> <JSON> <DESCRIPTION>
# PUT create-or-replaces an object (idempotent); a POST that hits an existing
# object returns ALREADY_EXISTS which is treated as success.
semp() {
  local method=$1 path=$2 body=$3 desc=$4 out code json
  out=$(curl -sS -u "$SEMP_USER:$SEMP_PASS" -X "$method" "$SEMP_URL$path" \
    -H 'Content-Type: application/json' -d "$body" -w '\n%{http_code}') || {
      echo "  ! $desc: cannot reach broker SEMP at $SEMP_URL" >&2; return 1; }
  code=${out##*$'\n'}
  json=${out%$'\n'*}
  if [ "$code" = "200" ]; then echo "  ok  $desc"; return 0; fi
  if printf '%s' "$json" | grep -q 'ALREADY_EXISTS'; then
    echo "  ok  $desc (already configured)"; return 0
  fi
  echo "  !!  $desc failed (HTTP $code): $json" >&2
  return 1
}

# The broker's SMF port (55554) opens before its SEMP/management port, so a caller
# that starts the broker and immediately runs this script can hit "Empty reply from
# server". Poll the SEMP 'about' endpoint until it answers (or give up after ~60s).
wait_semp() {
  local about="${SEMP_URL%/config}/config/about" i
  for i in $(seq 1 60); do
    if curl -sS -o /dev/null -u "$SEMP_USER:$SEMP_PASS" "$about" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "  ! broker SEMP at $SEMP_URL not reachable after 60s" >&2
  return 1
}

echo "Configuring Solace distributed tracing (vpn=$VPN, profile=$PROFILE) via $SEMP_URL"
wait_semp

# 1. AMQP plaintext must be up so the collector's solace receiver can connect
#    (amqp://petclinic-solace:5672). Enabled by default on this image; enforce it.
semp PATCH "/msgVpns/$VPN" \
  '{"serviceAmqpPlainTextEnabled":true}' \
  "AMQP plaintext service enabled"

# 2. Telemetry profile - enabling the receiver auto-creates the
#    #telemetry-<profile> queue that broker spans are spooled to.
semp PUT "/msgVpns/$VPN/telemetryProfiles/$PROFILE" \
  "{\"telemetryProfileName\":\"$PROFILE\",\"receiverEnabled\":true,\"receiverAclConnectDefaultAction\":\"allow\",\"traceEnabled\":true,\"traceSendSpanGenerationEnabled\":true}" \
  "Telemetry profile '$PROFILE' (receiver + trace enabled)"

# 3. Trace filter + subscription select which topics generate spans.
semp PUT "/msgVpns/$VPN/telemetryProfiles/$PROFILE/traceFilters/$FILTER" \
  "{\"traceFilterName\":\"$FILTER\",\"enabled\":true}" \
  "Trace filter '$FILTER'"

# The subscription key contains '/' and '>' so create via POST (re-runs tolerated).
semp POST "/msgVpns/$VPN/telemetryProfiles/$PROFILE/traceFilters/$FILTER/subscriptions" \
  "{\"subscription\":\"$SUBSCRIPTION\",\"subscriptionSyntax\":\"smf\"}" \
  "Trace subscription '$SUBSCRIPTION'"

# 3b. Promotion queue: the PetClinic RPC is pure DIRECT messaging, which the broker
#     does NOT trace on its own (only guaranteed or "promoted direct"). This durable
#     queue subscribes to the same topics so each direct request is also spooled
#     (promoted), which is what makes the broker emit the receive/send spans. A short
#     maxTtl + respectTtl auto-expires the spooled copies so the queue never grows.
semp PUT "/msgVpns/$VPN/queues/$PROMOTE_QUEUE" \
  "{\"queueName\":\"$PROMOTE_QUEUE\",\"accessType\":\"non-exclusive\",\"permission\":\"consume\",\"ingressEnabled\":true,\"egressEnabled\":true,\"maxMsgSpoolUsage\":$PROMOTE_SPOOL_MB,\"maxTtl\":$PROMOTE_TTL,\"respectTtlEnabled\":true}" \
  "Direct-message promotion queue '$PROMOTE_QUEUE' (ttl=${PROMOTE_TTL}s)"

semp POST "/msgVpns/$VPN/queues/$PROMOTE_QUEUE/subscriptions" \
  "{\"subscriptionTopic\":\"$SUBSCRIPTION\"}" \
  "Promotion queue subscription '$SUBSCRIPTION'"

# 4. Client username the collector authenticates as (SASL PLAIN over AMQP). It
#    MUST use the telemetry client-profile AND ACL-profile that were auto-created
#    with the telemetry profile (both named '#telemetry-<profile>') -- a client
#    can only bind to the telemetry queue through those profiles; the 'default'
#    profiles are denied ("amqp:unauthorized-access ... Permission Not Allowed").
semp PUT "/msgVpns/$VPN/clientUsernames/$RECV_USER" \
  "{\"clientUsername\":\"$RECV_USER\",\"password\":\"$RECV_PASS\",\"clientProfileName\":\"#telemetry-$PROFILE\",\"aclProfileName\":\"#telemetry-$PROFILE\",\"enabled\":true}" \
  "Telemetry receiver client username '$RECV_USER' (telemetry client+acl profiles)"

# 5. The broker only OFFERS SASL PLAIN over AMQP when the VPN's basic-auth type is
#    'internal'. The software image ships 'none', which offers only SASL ANONYMOUS
#    and rejects the receiver's username/password ("no supported auth mechanism
#    ([ANONYMOUS])"). Internal auth validates every basic-auth client against the
#    client-username database, so the app username needs its password set first or
#    the PetClinic apps would be rejected after the switch.
semp PUT "/msgVpns/$VPN/clientUsernames/$APP_USER" \
  "{\"clientUsername\":\"$APP_USER\",\"password\":\"$APP_PASS\",\"enabled\":true}" \
  "App client username '$APP_USER' (password set for internal auth)"

semp PATCH "/msgVpns/$VPN" \
  '{"authenticationBasicEnabled":true,"authenticationBasicType":"internal"}' \
  "VPN basic authentication = internal (enables SASL PLAIN over AMQP)"

echo "Done. Collector receiver queue: queue://#telemetry-$PROFILE (user '$RECV_USER')."
