#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# health-check.sh — Standalone health check script
#
# Usage:
#   ./health-check.sh blue 8081      # Check blue on port 8081
#   ./health-check.sh green 8082     # Check green on port 8082
#
# Exit codes:
#   0 — healthy
#   1 — unhealthy (all retries exhausted)
#
# Called by Jenkinsfile but can also run as a cron or monitoring probe.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Arguments ──────────────────────────────────────────────────────────────────
ENV_NAME="${1:-blue}"
PORT="${2:-8081}"

# ── Config ─────────────────────────────────────────────────────────────────────
MAX_RETRIES=5
RETRY_DELAY=10    # seconds
TIMEOUT=5         # seconds per curl attempt
HEALTH_URL="http://localhost:${PORT}/health"

# ── Colors ─────────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
RESET="\033[0m"

log()  { echo -e "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"; }
pass() { log "${GREEN}✅ PASS${RESET} $*"; }
fail() { log "${RED}❌ FAIL${RESET} $*"; }
warn() { log "${YELLOW}⚠️  WARN${RESET} $*"; }

# ── Health check function ───────────────────────────────────────────────────────
check_health() {
    local attempt=$1

    log "🔁 Attempt ${attempt}/${MAX_RETRIES} → ${HEALTH_URL}"

    # Capture HTTP status and body separately
    local response
    response=$(curl \
        --silent \
        --max-time "${TIMEOUT}" \
        --write-out "\nHTTPSTATUS:%{http_code}" \
        "${HEALTH_URL}" 2>&1) || {
            fail "curl failed (connection refused or timeout)"
            return 1
        }

    local http_status body
    http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*//g' | tr -d '\n')

    log "   HTTP status : ${http_status}"
    log "   Body        : ${body}"

    # Validate HTTP 200
    if [[ "$http_status" != "200" ]]; then
        fail "Expected HTTP 200, got ${http_status}"
        return 1
    fi

    # Validate body contains "OK" or "healthy" (case-insensitive)
    if echo "$body" | grep -qiE '"?OK"?|"?healthy"?'; then
        pass "Response body confirms healthy"
        return 0
    else
        fail "Body does not contain 'OK' or 'healthy'"
        return 1
    fi
}

# ── Main retry loop ─────────────────────────────────────────────────────────────
log "🏥 Starting health check for [${ENV_NAME}] at ${HEALTH_URL}"
log "   Max retries : ${MAX_RETRIES}"
log "   Retry delay : ${RETRY_DELAY}s"
log "   Timeout     : ${TIMEOUT}s"
echo "─────────────────────────────────────────────"

HEALTHY=false

for attempt in $(seq 1 "${MAX_RETRIES}"); do
    if check_health "${attempt}"; then
        HEALTHY=true
        break
    fi

    if [[ "${attempt}" -lt "${MAX_RETRIES}" ]]; then
        warn "Waiting ${RETRY_DELAY}s before retry..."
        sleep "${RETRY_DELAY}"
    fi
done

echo "─────────────────────────────────────────────"

if [[ "${HEALTHY}" == "true" ]]; then
    pass "[${ENV_NAME}] is HEALTHY. Ready to receive traffic."
    exit 0
else
    fail "[${ENV_NAME}] is UNHEALTHY after ${MAX_RETRIES} attempts."
    fail "Do NOT switch Nginx traffic. Rolling back."
    exit 1
fi
