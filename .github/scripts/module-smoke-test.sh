#!/usr/bin/env bash
#
# Smoke test: start a PrestaShop shop from docker-compose.yml, install the
# module through the PrestaShop console, uninstall it, and check both steps.
#
#   .github/scripts/module-smoke-test.sh ps81    (or: make smoke V=81)
#
# Override the image with PS81_TAG, PS82_TAG, PS90_TAG or PS92_TAG to test
# another PHP version. The shop is left running; stop it with `make down`.
#
# The console command is not trusted on its own: on PrestaShop 8.1,
# `prestashop:module install` exits 0 even when the install fails. Each step
# is therefore also checked in the ps_module table.

set -euo pipefail

SVC="${1:-}"
case "$SVC" in
  ps81 | ps82 | ps90 | ps92) ;;
  *)
    echo "Usage: $0 ps81|ps82|ps90|ps92" >&2
    exit 2
    ;;
esac

V="${SVC#ps}"
DB="db${V}"
PORT="80${V}"
MODULE="pensopay"
WAIT_SECONDS="${WAIT_SECONDS:-600}"

cd "$(dirname "$0")/../.."

COMPOSE=(docker compose --profile "$SVC")

log() { printf '\n==> %s\n' "$*"; }

fail() {
  echo "FAIL: $*" >&2
  log "Shop container logs (last 200 lines)"
  "${COMPOSE[@]}" logs --no-color --tail 200 "$SVC" || true
  log "PrestaShop logs (var/logs)"
  "${COMPOSE[@]}" exec -T "$SVC" sh -c 'tail -n 100 var/logs/*.log 2>/dev/null || echo "(no log files)"' || true
  exit 1
}

# Prints the module's `active` value, or nothing if the module is not installed.
module_state() {
  "${COMPOSE[@]}" exec -T -e MYSQL_PWD=prestashop "$DB" \
    mariadb -uroot prestashop -Nse "SELECT active FROM ps_module WHERE name = '${MODULE}'"
}

# Runs a module action and fails if the command fails or prints an error.
module_action() {
  local action="$1" output status=0
  output="$("${COMPOSE[@]}" exec -T "$SVC" php bin/console prestashop:module "$action" "$MODULE" 2>&1)" || status=$?
  echo "$output"
  if [ "$status" -ne 0 ]; then
    fail "'prestashop:module $action $MODULE' exited with $status"
  fi
  if grep -qi 'cannot' <<<"$output"; then
    fail "'prestashop:module $action $MODULE' reported an error"
  fi
}

if [ ! -f vendor/autoload.php ]; then
  echo "vendor/autoload.php is missing. Run 'composer install' first." >&2
  exit 1
fi

log "Starting $SVC ($("${COMPOSE[@]}" config --images | grep '^prestashop/'))"
"${COMPOSE[@]}" up -d

log "Waiting up to ${WAIT_SECONDS}s for the shop to finish installing on port $PORT"
deadline=$((SECONDS + WAIT_SECONDS))
until code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: localhost:$PORT" "http://127.0.0.1:$PORT/")" \
  && [[ "$code" =~ ^(200|301|302)$ ]]; do
  if [ -z "$("${COMPOSE[@]}" ps --status running -q "$SVC")" ]; then
    fail "$SVC stopped before the shop was ready"
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    fail "shop not ready after ${WAIT_SECONDS}s (last HTTP status: ${code:-none})"
  fi
  sleep 5
done
echo "Shop is up (HTTP $code)."

if [ -n "$(module_state)" ]; then
  fail "$MODULE is already installed in $SVC. Uninstall it, or run 'make reset V=$V' for a clean shop."
fi

log "Installing $MODULE"
module_action install
state="$(module_state)"
[ "$state" = "1" ] || fail "after install, expected ps_module.active = 1, got '${state}'"
echo "OK: $MODULE is installed and active."

log "Uninstalling $MODULE"
module_action uninstall
state="$(module_state)"
[ -z "$state" ] || fail "after uninstall, expected no ps_module row, got active = '${state}'"
echo "OK: $MODULE is uninstalled."

log "Smoke test passed for $SVC"
